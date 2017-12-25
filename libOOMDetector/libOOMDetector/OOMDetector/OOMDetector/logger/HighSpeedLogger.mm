//
//  HighSpeedLogger.m
//  QQLeak
//
//  Tencent is pleased to support the open source community by making OOMDetector available.
//  Copyright (C) 2017 THL A29 Limited, a Tencent company. All rights reserved.
//  Licensed under the MIT License (the "License"); you may not use this file except
//  in compliance with the License. You may obtain a copy of the License at
//
//  http://opensource.org/licenses/MIT
//
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.
//
//

#import "HighSpeedLogger.h"
#include <sys/mman.h>

#if __has_feature(objc_arc)
#error  this file should use MRC
#endif

HighSpeedLogger *createLogger(malloc_zone_t *memory_zone, NSString *path, size_t mmap_size)
{
    HighSpeedLogger *logger = (HighSpeedLogger *)memory_zone->malloc(memory_zone, sizeof(HighSpeedLogger));
    logger->current_len = 0;
    logger->mmap_size = mmap_size;
    logger->memory_zone = memory_zone;
    FILE *fp = fopen ( [path fileSystemRepresentation] , "wb+" ) ;
    if(fp != NULL){
        int ret = ftruncate(fileno(fp), mmap_size);
        if(ret == -1){
            memory_zone->free(memory_zone,logger);
            return NULL;
        }
        else {
            fseek(fp, 0, SEEK_SET);
            char *mmap_ptr = (char *)mmap(0, mmap_size, PROT_WRITE | PROT_READ, (MAP_FILE|MAP_SHARED), fileno(fp), 0);
            memset(mmap_ptr, '\0', mmap_size);
            if(mmap_ptr != NULL){
                logger->mmap_ptr = mmap_ptr;
                logger->fp = fp;
                return logger;
            }
            else {
                memory_zone->free(memory_zone,logger);
                return NULL;
            }
        }
    }
    else {
        memory_zone->free(memory_zone,logger);
        return NULL;
    }
}

BOOL sprintfLogger(HighSpeedLogger *logger,size_t grain_size,const char *format, ...)
{
    va_list args;
    va_start(args, format);
    BOOL result = NO;
    size_t maxSize = 10240;
    char *tmp = (char *)logger->memory_zone->malloc(logger->memory_zone, maxSize);
    size_t length = vsnprintf(tmp, maxSize, format, args);
    if(length >= maxSize) {
        logger->memory_zone->free(logger->memory_zone,tmp);
        return NO;
    }
    if (logger->logPrinterCallBack != NULL) {
        logger->logPrinterCallBack(tmp);
    }
    if(length + logger->current_len < logger->mmap_size - 1){
        logger->current_len += snprintf(logger->mmap_ptr + logger->current_len, (logger->mmap_size - 1 - logger->current_len), "%s", (const char*)tmp);
        result = YES;
    }
    else {
        char *copy = (char *)logger->memory_zone->malloc(logger->memory_zone, logger->mmap_size);
        memcpy(copy, logger->mmap_ptr, logger->mmap_size);
        munmap(logger->mmap_ptr ,logger->mmap_size);
        size_t copy_size = logger->mmap_size;
        logger->mmap_size += grain_size;
        int ret = ftruncate(fileno(logger->fp), logger->mmap_size);
        if(ret == -1){
            logger->memory_zone->free(logger->memory_zone,copy);
            result = NO;
        }
        else {
            fseek(logger->fp, 0, SEEK_SET);
            logger->mmap_ptr = (char *)mmap(0, logger->mmap_size, PROT_WRITE | PROT_READ, (MAP_FILE|MAP_SHARED), fileno(logger->fp), 0);
            memset(logger->mmap_ptr, '\0', logger->mmap_size);
            if(!logger->mmap_ptr){
                logger->memory_zone->free(logger->memory_zone,copy);
                result = NO;
            }
            else {
                result = YES;
                memcpy(logger->mmap_ptr, copy, copy_size);
                logger->current_len += snprintf(logger->mmap_ptr + logger->current_len, (logger->mmap_size - 1 - logger->current_len), "%s", (const char*)tmp);
            }
        }
        logger->memory_zone->free(logger->memory_zone,copy);
    }
    va_end(args);
    logger->memory_zone->free(logger->memory_zone,tmp);
    return result;
}

void cleanLogger(HighSpeedLogger *logger)
{
    logger->current_len = 0;
    memset(logger->mmap_ptr, '\0', logger->mmap_size);
}

void syncLogger(HighSpeedLogger *logger)
{
    msync(logger->mmap_ptr, logger->mmap_size, MS_ASYNC);
}

void registorLggPrinter(HighSpeedLogger *logger, LogPrinter printer)
{
    logger->logPrinterCallBack = printer;
}
