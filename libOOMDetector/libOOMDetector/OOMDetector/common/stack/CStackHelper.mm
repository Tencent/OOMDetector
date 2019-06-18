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

#import "CStackHelper.h"
#import "RapidCRC.h"
#import "CommonMallocLogger.h"

#if __has_feature(objc_arc)
#error This file must be compiled without ARC. Use -fno-objc-arc flag.
#endif

typedef struct
{
    vm_address_t beginAddr;
    vm_address_t endAddr;
}App_Address;

static App_Address app_addrs[3];

CStackHelper::~CStackHelper()
{
    for (size_t i = 0; i < allImages.size; i++)
    {
        free(allImages.imageInfos[i]);
    }
    free(allImages.imageInfos);
    allImages.imageInfos = NULL;
    allImages.size = 0;
}

CStackHelper::CStackHelper(NSString *saveDir)
{
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
        for (unsigned int j = 0; j < header->ncmds; j++) {
            const segment_command_t* segment = (const segment_command_t*)offset;
            if (segment->cmd == MY_SEGMENT_CMD_TYPE && strcmp(segment->segname, SEG_TEXT) == 0) {
                long begin = (long)segment->vmaddr + slide;
                long end = (long)(begin + segment->vmsize);
                segImageInfo *image = (segImageInfo *)malloc(sizeof(segImageInfo));
                image->loadAddr = (long)header;
                image->beginAddr = begin;
                image->endAddr = end;
                image->name = name;
#ifdef build_for_QQ
                static int index = 0;
                if((strcmp(name, "TlibDy") == 0 || strcmp(name, "QQMainProject") == 0  || strcmp(name, "QQStoryCommon") == 0) && index < 3)
                {
                    app_addrs[index].beginAddr = image->beginAddr;
                    app_addrs[index++].endAddr = image->endAddr;
                }
#else
                if(i == 0){
                    app_addrs[0].beginAddr = image->beginAddr;
                    app_addrs[0].endAddr = image->endAddr;
                }
#endif
                allImages.imageInfos[allImages.size++] = image;
                break;
            }
            offset += segment->cmdsize;
        }
    }
    if(saveDir){
        saveImages(saveDir);
    }
}

void CStackHelper::saveImages(NSString *saveDir)
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSMutableArray *result = [[[NSMutableArray alloc] init] autorelease];
        for (size_t i = 0; i < allImages.size; i++)
        {
            NSString *imageName = [NSString stringWithCString:allImages.imageInfos[i]->name encoding:NSUTF8StringEncoding];
            NSDictionary *app_image = [NSDictionary dictionaryWithObjectsAndKeys:imageName,@"name",[NSNumber numberWithInteger:allImages.imageInfos[i]->beginAddr],@"beginAddr",[NSNumber numberWithInteger:allImages.imageInfos[i]->endAddr],@"endAddr",nil];
            [result addObject:app_image];
        }
        NSString *save_path = [saveDir stringByAppendingPathComponent:@"app.images"];
        [result writeToFile:save_path atomically:YES];
    });
}

AppImages* CStackHelper::parseImages(NSArray *imageArray)
{
    AppImages *result = new AppImages();
    result->size = 0;
    result->imageInfos = (segImageInfo **)malloc([imageArray count]*sizeof(segImageInfo*));
    for(NSDictionary *image in imageArray){
        NSNumber *beginAddr = [image objectForKey:@"beginAddr"];
        NSNumber *endAddr = [image objectForKey:@"endAddr"];
        NSString *name = [image objectForKey:@"name"];
        if(beginAddr && endAddr && name){
            segImageInfo *image = (segImageInfo *)malloc(sizeof(segImageInfo));
            image->loadAddr = [beginAddr integerValue];
            image->beginAddr = [beginAddr integerValue];;
            image->endAddr = [endAddr integerValue];;
            image->name = [name UTF8String];
            result->imageInfos[result->size++] = image;
        }
    }
    return result;
}

bool CStackHelper::parseAddrOfImages(AppImages *images,vm_address_t addr,segImageInfo *image){
    for (size_t i = 0; i < images->size; i++)
    {
        if (addr > images->imageInfos[i]->beginAddr && addr < images->imageInfos[i]->endAddr) {
            image->name = images->imageInfos[i]->name;
            image->loadAddr = images->imageInfos[i]->loadAddr;
            image->beginAddr = images->imageInfos[i]->beginAddr;
            image->endAddr = images->imageInfos[i]->endAddr;
            return true;
        }
    }
    return false;
}

bool CStackHelper::isInAppAddress(vm_address_t addr){
    if((addr >= app_addrs[0].beginAddr && addr < app_addrs[0].endAddr)
#ifdef build_for_QQ
       || (addr >= app_addrs[1].beginAddr && addr < app_addrs[1].endAddr) || (addr >= app_addrs[2].beginAddr && addr < app_addrs[2].endAddr)
#endif
       )
    {
        return true;
    }
    return false;
}

bool CStackHelper::getImageByAddr(vm_address_t addr,segImageInfo *image){
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

size_t CStackHelper::recordBacktrace(BOOL needSystemStack,uint32_t type ,size_t needAppStackCount,size_t backtrace_to_skip, vm_address_t **app_stack,uint64_t *digest,size_t max_stack_depth)
{
    vm_address_t *orig_stack[max_stack_depth_sys];
    size_t depth = backtrace((void**)orig_stack, max_stack_depth_sys);
    size_t orig_depth = depth;
    if(depth > max_stack_depth){
        depth = max_stack_depth;
    }
    uint32_t compress_stacks[max_stack_depth_sys] = {'\0'};
    size_t offset = 0;
    size_t appstack_count = 0;
    if(depth <= 3 + backtrace_to_skip){
        return 0;
    }
    size_t real_length = depth - 2 - backtrace_to_skip;
    size_t index = 0;
    compress_stacks[index++] = type;
    for(size_t j = backtrace_to_skip;j < backtrace_to_skip + real_length;j++){
        if(needAppStackCount != 0){
            if(isInAppAddress((vm_address_t)orig_stack[j])){
                appstack_count++;
                app_stack[offset++] = orig_stack[j];
                compress_stacks[index++] = (uint32_t)(uint64_t)orig_stack[j];
            }
            else {
                if(needSystemStack){
                    app_stack[offset++] = orig_stack[j];
                    compress_stacks[index++] = (uint32_t)(uint64_t)orig_stack[j];
                }
            }
        }
        else{
            app_stack[offset++] = orig_stack[j];
            compress_stacks[index++] = (uint32_t)(uint64_t)orig_stack[j];
        }
    }
    app_stack[offset] = orig_stack[orig_depth - 2];
    if((needAppStackCount > 0 && appstack_count > 0) || (needAppStackCount == 0 && offset > 0)){
        size_t remainder = (index*4)%8;
        size_t compress_len = index*4 + (remainder == 0 ? 0 : (8 - remainder));
        //    CC_MD5(&compress_stacks,(CC_LONG)2*depth,md5);
        //    memcpy(md5, &compress_stacks, 16);
        //    uint8_t digest[CC_SHA1_DIGEST_LENGTH];
        //    CC_SHA1(&compress_stacks,(CC_LONG)2*depth, md5);
        uint64_t crc = 0;
        crc = rapid_crc64(crc, (const char *)&compress_stacks, compress_len);
        *digest = crc;
        return offset + 1;
    }
    return 0;
}
