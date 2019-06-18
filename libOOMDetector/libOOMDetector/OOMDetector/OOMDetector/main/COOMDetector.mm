//
//  COOMDetector.m
//  libOOMDetector
//
//  Created by rosen on 2017/12/26.
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

#import "COOMDetector.h"
#import "fishhook.h"
#import <dlfcn.h>

#define do_lockHashmap \
    if(use_unfair_lock){ \
        os_unfair_lock_lock(&hashmap_unfair_lock); \
    } \
    else { \
        dispatch_semaphore_wait(hashmap_sema, DISPATCH_TIME_FOREVER); \
    }

#define do_unlockHashmap \
    if(use_unfair_lock){ \
        os_unfair_lock_unlock(&hashmap_unfair_lock); \
    } \
    else { \
        dispatch_semaphore_signal(hashmap_sema);\
    }

#define do_lockVMHashmap \
if(use_unfair_lock){ \
os_unfair_lock_lock(&vm_hashmap_unfair_lock); \
} \
else { \
dispatch_semaphore_wait(vm_hashmap_sema, DISPATCH_TIME_FOREVER); \
}

#define do_unlockVMHashmap \
if(use_unfair_lock){ \
os_unfair_lock_unlock(&vm_hashmap_unfair_lock); \
} \
else { \
dispatch_semaphore_signal(vm_hashmap_sema);\
}

extern COOMDetector* global_oomdetector;

static void* (*orig_mmap)(void *, size_t, int, int, int, off_t);
static int (*orig_munmap)(void *, size_t);

//static void* orig_mmap = NULL;
//static void* orig_munmap = NULL;

void *new_mmap(void *dest, size_t size, int author, int type, int fp, off_t offset)
{
    void *ptr = ((void *(*)(void *, size_t, int, int, int, off_t))orig_mmap)(dest, size, author, type, fp, offset);
    if(ptr != NULL && (author & 0x2) != 0){
        global_oomdetector->recordVMStack(vm_address_t(dest), uint32_t(size),2);
    }
    return ptr;
}

int new_munmap(void *dest, size_t size)
{
    int result = ((int(*)(void *, size_t))orig_munmap)(dest,size);
    global_oomdetector->removeVMStack(vm_address_t(dest));
    return result;
}

COOMDetector::~COOMDetector()
{
    if(stackHelper != NULL){
        delete stackHelper;
    }
}

COOMDetector::COOMDetector()
{
    //ios10以上使用安全的unfair lock，ios10以下由于spinlock的系统bug，存在一定概率线程优先级反转问题，可能会引发卡死，建议ios10以下系统谨慎使用
    if(@available(iOS 10.0,*)){
        use_unfair_lock = true;
    }
    else {
        hashmap_sema = dispatch_semaphore_create(1);
        vm_hashmap_sema = dispatch_semaphore_create(1);
    }
}

NSString *COOMDetector::chunkDataZipPath()
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
    NSString *LibDirectory = [paths objectAtIndex:0];
    NSString *dir = [LibDirectory stringByAppendingPathComponent:@"Caches/OOMTmp"];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:dir])
    {
        [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    return [dir stringByAppendingPathComponent:@"ChunkData.zip"];
}

void COOMDetector::get_chunk_stack(size_t size)
{
    if(enableChunkMonitor){
        vm_address_t *stacks[max_stack_depth_sys];
        size_t depth = backtrace((void**)stacks, max_stack_depth_sys);
        NSMutableString *stackInfo = [[[NSMutableString alloc] init] autorelease];
        NSDateFormatter* df1 = [[NSDateFormatter new] autorelease];
        df1.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
        NSString *dateStr1 = [df1 stringFromDate:[NSDate date]];
        [stackInfo appendFormat:@"%@ chunk_malloc:%.2fmb stack:\n",dateStr1,(double)size/(1024*1024)];
        for(size_t j = 2; j < depth; j++){
            vm_address_t addr = (vm_address_t)stacks[j];
            segImageInfo segImage;
            if(chunk_stackHelper->getImageByAddr(addr, &segImage)){
                [stackInfo appendFormat:@"\"%lu %s 0x%lx 0x%lx\" ",j - 2,(segImage.name != NULL) ? segImage.name : "unknown",segImage.loadAddr,(long)addr];
            }
        }
        [stackInfo appendFormat:@"\n"];
        
        if (fileUploadCenter.fileDataDelegate) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                NSData *data = [stackInfo dataUsingEncoding:NSUTF8StringEncoding];
                if (data && data.length > 0) {
                    NSDictionary *extra = [NSDictionary dictionaryWithObjectsAndKeys:[[UIDevice currentDevice] systemVersion],@"systemversion",[QQLeakDeviceInfo platform],@"Device",@"chunk_malloc",@"type",nil];
                    [fileUploadCenter fileData:data extra:extra type:QQStackReportTypeChunkMemory completionHandler:^(BOOL completed) {
                        
                    }];
                }
            });
        }
        if(chunkMallocCallback)
        {
            chunkMallocCallback(size,stackInfo);
        }
    }
}

void COOMDetector::lockHashmap()
{
    do_lockHashmap
}

void COOMDetector::unlockHashmap()
{
    do_unlockHashmap
}

void COOMDetector::recordMallocStack(vm_address_t address,uint32_t size,size_t stack_num_to_skip)
{
    base_stack_t base_stack;
    base_ptr_log base_ptr;
    uint64_t digest;
    vm_address_t  *stack[max_stack_depth];
    if(needStackWithoutAppStack){
        base_stack.depth = (uint32_t)stackHelper->recordBacktrace(needSysStack,0,0,stack_num_to_skip, stack,&digest,max_stack_depth);
    }
    else {
        base_stack.depth = (uint32_t)stackHelper->recordBacktrace(needSysStack,0,1,stack_num_to_skip, stack,&digest,max_stack_depth);
    }
    if(base_stack.depth > 0){
        base_stack.type = 0;
        if(sampleFactor > 1 && size < sampleThreshold){
            base_stack.size = size * sampleFactor;
            base_stack.count = sampleFactor;
        }
        else {
            base_stack.size = size;
            base_stack.count = 1;
        }
        base_stack.stack = stack;
        base_ptr.digest = digest;
        base_ptr.size = size;
        do_lockHashmap
        if(oom_ptrs_hashmap && oom_stacks_hashmap){
            if(oom_ptrs_hashmap->insertPtr(address, &base_ptr)){
                oom_stacks_hashmap->insertStackAndIncreaseCountIfExist(digest, &base_stack);
            }
            if(needCleanStackCache && oom_ptrs_hashmap->getRecordNum() > cache_clean_num){
                removeTinyMallocStacks(cache_clean_threshold);
                cache_clean_num += oom_ptrs_hashmap->getRecordNum();
            }
        }
        do_unlockHashmap
    }
}

void COOMDetector::removeTinyMallocStacks(size_t threshold)
{
    for(size_t i = 0; i < oom_ptrs_hashmap->getEntryNum(); i++){
        base_entry_t *entry = oom_ptrs_hashmap->getHashmapEntry() + i;
        ptr_log_t *current = (ptr_log_t *)entry->root;
        while(current != NULL){
            ptr_log_t *next = current->next;
            merge_stack_t *lookupStack = oom_stacks_hashmap->lookupStack(current->digest);
            if(lookupStack){
                uint32_t size = lookupStack->size;
                uint64_t digest = lookupStack->digest;
                uint32_t count = lookupStack->count;
                vm_address_t address = current->address;
                if(size < threshold){
                    if(oom_ptrs_hashmap->removePtr(address,NULL,NULL)){
                        oom_stacks_hashmap->removeIfCountIsZero(digest, size, count);
                    }
                }
            }
            else {
                vm_address_t address = current->address;
                oom_ptrs_hashmap->removePtr(address,NULL,NULL);
            }
            current = next;
        }
    }
}

void COOMDetector::removeMallocStack(vm_address_t address)
{
    do_lockHashmap
    if(oom_ptrs_hashmap && oom_stacks_hashmap){
        uint32_t size = 0;
        uint64_t digest = 0;
        uint32_t count = 1;
        if(oom_ptrs_hashmap->removePtr(address,&size,&digest)){
            if(sampleFactor > 1 && size < sampleThreshold){
                count = sampleFactor;
                size = size * sampleFactor;
            }
            oom_stacks_hashmap->removeIfCountIsZero(digest, size, count);
        }
    }
    do_unlockHashmap
}

void COOMDetector::recordVMStack(vm_address_t address,uint32_t size,size_t stack_num_to_skip)
{
    base_stack_t base_stack;
    base_ptr_log base_ptr;
    uint64_t digest;
    vm_address_t  *stack[max_stack_depth];
    base_stack.depth = (uint32_t)stackHelper->recordBacktrace(YES,1,0,stack_num_to_skip, stack,&digest,max_stack_depth);
    if(base_stack.depth > 0){
        base_stack.type = 1;
        base_stack.size = size;
        base_stack.count = 1;
        base_stack.stack = stack;
        base_ptr.digest = digest;
        base_ptr.size = size;
        do_lockVMHashmap
        if(oom_vm_ptrs_hashmap && oom_vm_stacks_hashmap){
            oom_vm_ptrs_hashmap->insertPtr(address, &base_ptr);
            oom_vm_stacks_hashmap->insertStackAndIncreaseCountIfExist(digest, &base_stack);
        }
        do_unlockVMHashmap
    }
}

void COOMDetector::removeVMStack(vm_address_t address)
{
    do_lockVMHashmap
    if(oom_vm_ptrs_hashmap && oom_vm_stacks_hashmap){
        uint32_t size = 0;
        uint64_t digest = 0;
        if(oom_vm_ptrs_hashmap->removePtr(address,&size,&digest)){
            oom_vm_stacks_hashmap->removeIfCountIsZero(digest, size, 1);
        }
    }
    do_unlockVMHashmap
}



void COOMDetector::initLogger(malloc_zone_t *zone, NSString *path, size_t mmap_size)
{
    NSString *dir = [path stringByDeletingLastPathComponent];
    stackHelper = new CStackHelper(dir);
    log_path = [path retain];
    log_mmap_size = mmap_size;
}

void COOMDetector::initVMLogger(malloc_zone_t *zone, NSString *path, size_t mmap_size)
{
    NSString *dir = [path stringByDeletingLastPathComponent];
    if(stackHelper == NULL){
        stackHelper = new CStackHelper(dir);
    }
    vm_log_path = [path retain];
    vm_log_mmap_size = mmap_size;
}

BOOL COOMDetector::startMallocStackMonitor(size_t threshholdInBytes)
{
    oom_stacks_hashmap = new CStacksHashmap(50000,global_memory_zone,log_path,log_mmap_size);
    oom_stacks_hashmap->oom_threshold = threshholdInBytes;
    oom_ptrs_hashmap = new CPtrsHashmap(500000,global_memory_zone);
    enableOOMMonitor = YES;
    oom_threshold = threshholdInBytes;
    return YES;
}

void COOMDetector::stopMallocStackMonitor()
{
    lockHashmap();
    CPtrsHashmap *tmp_ptr = oom_ptrs_hashmap;
    CStacksHashmap *tmp_stack = oom_stacks_hashmap;
    oom_stacks_hashmap = NULL;
    oom_ptrs_hashmap = NULL;
    unlockHashmap();
    delete tmp_ptr;
    delete tmp_stack;
}

BOOL COOMDetector::startVMStackMonitor(size_t threshholdInBytes)
{
    oom_vm_stacks_hashmap = new CStacksHashmap(1000,global_memory_zone,log_path,log_mmap_size);
    oom_vm_stacks_hashmap->oom_threshold = threshholdInBytes;
    oom_vm_ptrs_hashmap = new CPtrsHashmap(10000,global_memory_zone);
    enableVMMonitor = YES;
    vm_threshold = threshholdInBytes;
//    rebind_symbols((struct rebinding[2]){
//        {"mmap",(void*)new_mmap,(void**)&orig_mmap},
//        {"munmap", (void*)new_munmap, (void **)&orig_munmap}},
//                   2);
    return YES;
}

void COOMDetector::stopVMStackMonitor()
{
    enableVMMonitor = NO;
    do_lockVMHashmap
    CPtrsHashmap *tmp_ptr = oom_vm_ptrs_hashmap;
    CStacksHashmap *tmp_stack = oom_vm_stacks_hashmap;
    oom_vm_stacks_hashmap = NULL;
    oom_vm_ptrs_hashmap = NULL;
    do_unlockVMHashmap
    delete tmp_ptr;
    delete tmp_stack;
}

void COOMDetector::startSingleChunkMallocDetector(size_t threshholdInBytes,ChunkMallocBlock mallocBlock)
{
    chunk_threshold = threshholdInBytes;
    enableChunkMonitor = YES;
    if(chunkMallocCallback != NULL){
        Block_release(chunkMallocCallback);
    }
    if(chunk_stackHelper == NULL){
        chunk_stackHelper = new CStackHelper(nil);
    }
    chunkMallocCallback = Block_copy(mallocBlock);
    fileUploadCenter = [QQLeakFileUploadCenter defaultCenter];
}

void COOMDetector::stopSingleChunkMallocDetector()
{
    enableChunkMonitor = NO;
}

