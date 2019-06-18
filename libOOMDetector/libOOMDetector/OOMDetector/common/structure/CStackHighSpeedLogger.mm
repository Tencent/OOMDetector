//
//  CStackHighSpeedLogger.mm
//  OOMDetector
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

#import "CStackHighSpeedLogger.h"
#import <sys/mman.h>

CStackHighSpeedLogger::CStackHighSpeedLogger(size_t num,malloc_zone_t *memory_zone,NSString *path)
{
    entry_num = num;
    mmap_size = entry_num*sizeof(cache_stack_t);
    total_logger_cnt = 0;
    isFailed = false;
    FILE *fp = fopen ( [path fileSystemRepresentation] , "wb+" ) ;
    if(fp != NULL){
        int ret = ftruncate(fileno(fp), mmap_size);
        if(ret == -1){
            isFailed = true;
        }
        else {
            fseek(fp, 0, SEEK_SET);
            cache_stack_t *ptr = (cache_stack_t *)mmap(0, mmap_size, PROT_WRITE | PROT_READ, (MAP_FILE|MAP_SHARED), fileno(fp), 0);
            memset(ptr, '\0', mmap_size);
            if(ptr != NULL){
                mmap_ptr = ptr;
                mmap_fp = fp;
            }
            else {
                isFailed = true;
            }
        }
    }
    else {
        isFailed = true;
    }
}

CStackHighSpeedLogger::~CStackHighSpeedLogger()
{
    if(mmap_ptr != NULL){
        munmap(mmap_ptr , mmap_size);
    }
}

void CStackHighSpeedLogger::updateStack(merge_stack_t *current,base_stack_t *stack)
{
    if(isFailed) return;
    size_t offset = (size_t)current->digest%(entry_num - 1);
    cache_stack_t *cache_stack = mmap_ptr + offset;
    while (cache_stack->count != 0) {
        if(cache_stack->digest != current->digest){
            if(++offset == entry_num){
                offset = 0;
            }
            cache_stack = mmap_ptr + offset;
        }
        else {
            if(total_logger_cnt > 0){
                total_logger_cnt--;
            }
            break;
        }
    }
    cache_stack->size = (uint32_t)current->size;
    cache_stack->count = current->count;
    cache_stack->type = stack->type;
    cache_stack->stack_depth = stack->depth;
    cache_stack->digest = current->digest;
    memcpy(cache_stack->stacks, stack->stack, stack->depth * sizeof(vm_address_t));
    total_logger_cnt++;
    if(total_logger_cnt > (entry_num - 2) && stack->type != 1){
        char *copy = (char *)memory_zone->malloc(memory_zone, mmap_size);
        memcpy(copy, mmap_ptr, mmap_size);
        munmap(mmap_ptr ,mmap_size);
        size_t copy_size = mmap_size;
        entry_num = 2*entry_num;
        mmap_size = entry_num*sizeof(cache_stack_t);
        int ret = ftruncate(fileno(mmap_fp), mmap_size);
        if(ret == -1){
            memory_zone->free(memory_zone,copy);
            isFailed = true;
        }
        else {
            fseek(mmap_fp, 0, SEEK_SET);
            mmap_ptr = (cache_stack_t *)mmap(0, mmap_size, PROT_WRITE | PROT_READ, (MAP_FILE|MAP_SHARED), fileno(mmap_fp), 0);
            memset(mmap_ptr, '\0', mmap_size);
            if(!mmap_ptr){
                memory_zone->free(memory_zone,copy);
                isFailed = false;
            }
            else {
                isFailed = true;
                memcpy(mmap_ptr, copy, copy_size);
            }
        }
        memory_zone->free(memory_zone,copy);
    }
}

void CStackHighSpeedLogger::removeStack(merge_stack_t *current,bool needRemove)
{
    if(isFailed) return;
    size_t offset = (size_t)current->digest%(entry_num - 1);
    size_t last_offset = (offset == 0) ? (entry_num - 1) : (offset - 1);
    cache_stack_t *cache_stack = mmap_ptr + offset;
    while (cache_stack->count != 0 && cache_stack->digest != current->digest) {
        if(++offset == entry_num){
            offset = 0;
        }
        if(offset == last_offset){
            cache_stack = NULL;
            break;
        }
        cache_stack = mmap_ptr + offset;
    }
    if(cache_stack != NULL && cache_stack->count != 0){
        if(needRemove){
            cache_stack->size = 0;
            cache_stack->count = 0;
        }
        else {
            cache_stack->size = current->size;
            cache_stack->count = current->count;
        }
        if(total_logger_cnt > 0 && cache_stack->count == 0){
            total_logger_cnt--;
        }
    }
}
