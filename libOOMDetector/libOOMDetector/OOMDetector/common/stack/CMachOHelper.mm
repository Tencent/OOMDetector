//
//  CMachOHelper.m
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

#include "CMachOHelper.h"

#if __has_feature(objc_arc)
#error  this file should use MRC
#endif

typedef struct AppImages
{
    size_t size;
    segImageInfo **imageInfos;
}AppImages;

static AppImages allImages;

void initAllImages(){
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        uint32_t count = _dyld_image_count();
        allImages.imageInfos =(segImageInfo **)malloc(count*sizeof(segImageInfo*));
        allImages.size = 0;
        for (uint32_t i = 0; i < count; i++) {
            const mach_header_t* header = (const mach_header_t*)_dyld_get_image_header(i);
            const char* name = _dyld_get_image_name(i);
            const char* tmp = strrchr(name, '/');
            long slide = _dyld_get_image_vmaddr_slide(i);
            if (tmp) {
                name = tmp + 1;
            }
            long offset = (long)header + sizeof(mach_header_t);
            for (unsigned int i = 0; i < header->ncmds; i++) {
                const segment_command_t* segment = (const segment_command_t*)offset;
                if (segment->cmd == MY_SEGMENT_CMD_TYPE && strcmp(segment->segname, SEG_TEXT) == 0) {
                    long begin = (long)segment->vmaddr + slide;
                    long end = (long)(begin + segment->vmsize);
                    segImageInfo *image = (segImageInfo *)malloc(sizeof(segImageInfo));
                    image->loadAddr = (long)header;
                    image->beginAddr = begin;
                    image->endAddr = end;
                    image->name = name;
                    allImages.imageInfos[allImages.size++] = image;
                    break;
                }
                offset += segment->cmdsize;
            }
        }
    });
}

bool isInAppAddress(vm_address_t addr){
    if(addr > allImages.imageInfos[0]->beginAddr && addr < allImages.imageInfos[0]->endAddr) return true;
    return false;
}

bool getImageByAddr(vm_address_t addr,segImageInfo *image){
    for (size_t i = 0; i < allImages.size; i++)
    {
        if (addr > allImages.imageInfos[i]->beginAddr && addr < allImages.imageInfos[i]->endAddr) {
            image->name = allImages.imageInfos[i]->name;
            image->loadAddr = allImages.imageInfos[i]->loadAddr;
            image->beginAddr = allImages.imageInfos[i]->beginAddr;
            image->endAddr = allImages.imageInfos[i]->endAddr;
            return true;
        }
    }
    return false;
}

void removeAllImages(){
    for (size_t i = 0; i < allImages.size; i++)
    {
        free(allImages.imageInfos[i]);
    }
    free(allImages.imageInfos);
    allImages.imageInfos = NULL;
    allImages.size = 0;
}
