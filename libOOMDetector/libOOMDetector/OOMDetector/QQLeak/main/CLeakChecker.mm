//
//  CLeakChecker.m
//  libOOMDetector
//
//  Created by rosen on 2017/12/25.
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

#import "CLeakChecker.h"
#import "QQLeakChecker.h"
#import "CommonMallocLogger.h"
#import "RapidCRC.h"
#import "CLeakedStacksHashmap.h"

CLeakChecker::CLeakChecker()
{
    stackHelper = new CStackHelper(nil);
    pthread_mutex_init(&hashmap_mutex,NULL);
    hashmap_mutex = PTHREAD_MUTEX_INITIALIZER;
    pthread_mutex_init(&threadTracking_mutex,NULL);
    threadTracking_mutex = PTHREAD_MUTEX_INITIALIZER;
}

CLeakChecker::~CLeakChecker()
{
    if(leaked_hashmap != NULL){
        delete leaked_hashmap;
    }
    if(threadTracking_hashmap != NULL){
        delete threadTracking_hashmap;
    }
    if(qleak_ptrs_hashmap != NULL){
        delete qleak_ptrs_hashmap;
    }
    if(qleak_stacks_hashmap != NULL){
        delete qleak_stacks_hashmap;
    }
    if(objcFilter != NULL){
        delete objcFilter;
    }
    if(stackHelper != NULL){
        delete stackHelper;
    }
}

bool CLeakChecker::findPtrInMemoryRegion(vm_address_t address){
    ptr_log_t *ptr_log = qleak_ptrs_hashmap->lookupPtr(address);
    if(ptr_log != NULL){
        ptr_log->size++;
        return true;
    }
    return false;
}

void CLeakChecker::markedThreadToTrackingNextMalloc(const char* name){
    thread_t thread = mach_thread_self();
    lockThreadTracking();
    threadTracking_hashmap->insertThreadAndUpdateIfExist(thread, name);
    unlockThreadTracking();
}

bool CLeakChecker::isThreadNeedTracking(const char **name){
    thread_t thread = mach_thread_self();
    lockThreadTracking();
    thread_data_t *thread_data = threadTracking_hashmap->lookupThread(thread);
    if(thread_data != NULL){
        if(thread_data->needTrack){
            thread_data->needTrack = false;
            if(name != NULL) *name = thread_data->name;
            unlockThreadTracking();
            return true;
        }
    }
    unlockThreadTracking();
    return false;
}

void CLeakChecker::initLeakChecker(){
    if(global_memory_zone == NULL){
        global_memory_zone = malloc_create_zone(0, 0);
        malloc_set_zone_name(global_memory_zone, "QQLeak");
    }
    malloc_zone = global_memory_zone;
    threadTracking_hashmap = new CThreadTrackingHashmap(40,global_memory_zone);
    objcFilter = new CObjcFilter();
    objcFilter->initBlackClass();
    qleak_ptrs_hashmap = new CPtrsHashmap(100000,global_memory_zone);
    qleak_stacks_hashmap = new CLeakedStacksHashmap(50000,global_memory_zone);
    init_crc_table_for_oom();
}

void CLeakChecker::beginLeakChecker(){
    enableStackTracking = false;
    malloc_logger = (malloc_logger_t *)common_stack_logger;
    hookMalloc();
    [[AllocationTracker getInstance] beginRecord];
    enableStackTracking = true;
    isLeakChecking = false;
}

void CLeakChecker::clearLeakChecker(){
    enableStackTracking = false;
    [[AllocationTracker getInstance] stopRecord];
    unHookMalloc();
    //    malloc_logger = NULL;
    lockHashmap();
    delete qleak_ptrs_hashmap;
    delete qleak_stacks_hashmap;
    qleak_ptrs_hashmap = NULL;
    qleak_stacks_hashmap = NULL;
    delete threadTracking_hashmap;
    unlockHashmap();
}

void CLeakChecker::leakCheckingWillStart(){
    pausedMallocTracking();
    isLeakChecking = true;
    leaked_hashmap = new CLeakedHashmap(200,global_memory_zone);
    objcFilter->updateCurrentClass();
    unlockHashmap();
}
void CLeakChecker::leakCheckingWillFinish(){
    isLeakChecking = false;
    resumeMallocTracking();
    objcFilter->clearCurrentClass();
    delete leaked_hashmap;
}

void CLeakChecker::lockHashmap()
{
    pthread_mutex_lock(&hashmap_mutex);
}

void CLeakChecker::unlockHashmap()
{
    pthread_mutex_unlock(&hashmap_mutex);
}

void CLeakChecker::lockThreadTracking()
{
    pthread_mutex_lock(&threadTracking_mutex);
}

void CLeakChecker::unlockThreadTracking()
{
    pthread_mutex_unlock(&threadTracking_mutex);
}

void CLeakChecker::recordMallocStack(vm_address_t address,uint32_t size,const char*name,size_t stack_num_to_skip)
{
    base_leaked_stack_t base_stack;
    base_ptr_log base_ptr;
    uint64_t digest;
    vm_address_t *stack[max_stack_depth];
    base_stack.depth = stackHelper->recordBacktrace(needSysStack,0,0,stack_num_to_skip + 1, stack,&digest,max_stack_depth);
    if(base_stack.depth > 0){
        base_stack.stack = stack;
        base_stack.extra.name = name;
        base_stack.extra.size = size;
        base_ptr.digest = digest;
        base_ptr.size = 0;
        lockHashmap();
        if(qleak_ptrs_hashmap && qleak_stacks_hashmap){
            if(qleak_ptrs_hashmap->insertPtr(address, &base_ptr)){
                qleak_stacks_hashmap->insertStackAndIncreaseCountIfExist(digest, &base_stack);
            }
        }
        unlockHashmap();
    }
}

void CLeakChecker::removeMallocStack(vm_address_t address)
{
    lockHashmap();
    if(qleak_ptrs_hashmap && qleak_stacks_hashmap){
        uint32_t size = 0;
        uint64_t digest = 0;
        if(qleak_ptrs_hashmap->removePtr(address,&size,&digest)){
            qleak_stacks_hashmap->removeIfCountIsZero(digest,size);
        }
    }
    unlockHashmap();
}

void CLeakChecker::get_all_leak_ptrs()
{
    for(size_t i = 0; i < qleak_ptrs_hashmap->getEntryNum(); i++)
    {
        base_entry_t *entry = qleak_ptrs_hashmap->getHashmapEntry() + i;
        ptr_log_t *current = (ptr_log_t *)entry->root;
        while(current != NULL){
            merge_leaked_stack_t *merge_stack = qleak_stacks_hashmap->lookupStack(current->digest);
            if(merge_stack == NULL) {
                current = current->next;
                continue;
            }
            if(merge_stack->extra.name != NULL){
                if(current->size == 0){
                    leaked_hashmap->insertLeakPtrAndIncreaseCountIfExist(current->digest, current);
                    vm_address_t address = current->address;
                    qleak_ptrs_hashmap->removePtr(address,NULL,NULL);
                }
                current->size = 0;
            }
            else{
                vm_address_t address = current->address;
                const char* name = objcFilter->getObjectNameExceptBlack((void *)address);
                if(name != NULL){
                    if(current->size == 0){
                        merge_stack->extra.name = name;
                        leaked_hashmap->insertLeakPtrAndIncreaseCountIfExist(current->digest, current);
                        vm_address_t address = (vm_address_t)(0x100000000 | current->address);
                        qleak_ptrs_hashmap->removePtr(address,NULL,NULL);
                    }
                    current->size = 0;
                }
                else {
                    qleak_ptrs_hashmap->removePtr(current->address,NULL,NULL);
                }
            }
            current = current->next;
        }
    }
}

NSString* CLeakChecker::get_all_leak_stack(size_t *total_count)
{
    get_all_leak_ptrs();
    NSMutableString *stackData = [[[NSMutableString alloc] init] autorelease];
    size_t total = 0;
    for(size_t i = 0; i <leaked_hashmap->getEntryNum(); i++){
        base_entry_t *entry = leaked_hashmap->getHashmapEntry() + i;
        leaked_ptr_t *current = (leaked_ptr_t *)entry->root;
        while(current != NULL){
            merge_leaked_stack_t *merge_stack = qleak_stacks_hashmap->lookupStack(current->digest);
            if(merge_stack == NULL) {
                current = current->next;
                continue;
            }
            total += current->leak_count;
            [stackData appendString:@"********************************\n"];
            [stackData appendFormat:@"[**LeakCheck**] Leak addr:0x%lx name:%s leak num:%u, stack:\n",(long)current->address, merge_stack->extra.name, current->leak_count];
            for(size_t j = 0; j < merge_stack->depth; j++){
                vm_address_t addr = (vm_address_t)merge_stack->stack[j];
                segImageInfo segImage;
                if(stackHelper->getImageByAddr(addr, &segImage)){
                    [stackData appendFormat:@"\"%lu %s 0x%lx 0x%lx\" ",j,(segImage.name != NULL) ? segImage.name : "unknown",segImage.loadAddr,(long)addr];
                }
            }
            [stackData appendString:@"\n"];
            current = current->next;
        }
    }
    [stackData insertString:[NSString stringWithFormat:@"QQLeakChecker find %lu leak object!!!\n",total] atIndex:0];
    *total_count = total;
    
    if(total > 0){
        uploadLeakData(stackData);
    }
    
    return stackData;
}

void CLeakChecker::uploadLeakData(NSString *leakStr)
{
 //   NSLog(@"%@",leakStr);
    if ([QQLeakFileUploadCenter defaultCenter].fileDataDelegate) {
        NSMutableString *leakData = [[[NSMutableString alloc] initWithString:leakStr] autorelease];
        [leakData insertString:[NSString stringWithFormat:@"QQLeak montitor: os:%@, device_type:%@\n", [[NSProcessInfo processInfo] operatingSystemVersionString], [QQLeakDeviceInfo platform]] atIndex:0];
        if(leakData && leakData.length > 0){
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),^{
                NSMutableDictionary *extra = [NSMutableDictionary dictionaryWithObjectsAndKeys:@"QQLeak",@"name",@"QQLeak",@"leakType",nil];
                
                
                if ([[NSProcessInfo processInfo] operatingSystemVersionString]) {
                    [extra setValue:[[NSProcessInfo processInfo] operatingSystemVersionString] forKey:@"os"];
                }
                
                if ([QQLeakDeviceInfo platform]) {
                    [extra setValue:[QQLeakDeviceInfo platform] forKey:@"device_type"];
                }
                
                
                
                [[QQLeakFileUploadCenter defaultCenter] fileData:[leakData dataUsingEncoding:NSUTF8StringEncoding] extra:extra type:QQStackReportTypeLeak completionHandler:^(BOOL completed) {
                    
                }];
            });
        }
    }
}

bool CLeakChecker::isNeedTrackClass(Class cl)
{
    return !(objcFilter->isClassInBlackList(cl));
}

malloc_zone_t *CLeakChecker::getMemoryZone()
{
    return malloc_zone;
}

CPtrsHashmap *CLeakChecker::getPtrHashmap()
{
    return qleak_ptrs_hashmap;
}

CLeakedStacksHashmap *CLeakChecker::getStackHashmap()
{
    return qleak_stacks_hashmap;
}

void CLeakChecker::setMaxStackDepth(size_t depth)
{
    max_stack_depth = depth;
}

void CLeakChecker::setNeedSysStack(BOOL need)
{
    needSysStack = need;
}

