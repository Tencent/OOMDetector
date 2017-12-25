//
//  QQLeakStackLogging.m
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


#import "AllocationTracker.h"
#import <libkern/OSAtomic.h>
#include <pthread.h>
#include <execinfo.h>
#include <mach/vm_map.h>
#include <mach/thread_act.h>
#include <mach/mach_port.h>
#include <mach/mach_init.h>
#include <pthread.h>
#include <ext/hash_set>
#include "CMachOHelper.h"
#include "QQLeakStackLogging.h"
#include "CMallocHook.h"
#include "CObjcManager.h"
#include "CThreadTrackingHashmap.h"
#include "CHeapChecker.h"
#include "CLeakedHashmap.h"
#import "BackTraceManager.h"
#import "AllocationStackLogger.h"
#import "QQLeakFileUploadCenter.h"
#import "QQLeakDeviceInfo.h"

#if __has_feature(objc_arc)
#error  this file should use MRC
#endif

//static
static bool enableStackTracking;
static bool isLeakChecking;

//extern
extern malloc_zone_t *memory_zone;
extern malloc_zone_t *default_zone;
extern monitor_mode current_mode;
extern OSSpinLock hashmap_spinlock;

//global
CLeakedHashmap *leaked_hashmap;
CThreadTrackingHashmap *threadTracking_hashmap;
OSSpinLock threadTracking_spinlock = OS_SPINLOCK_INIT;
CPtrsHashmap *qleak_ptrs_hashmap;
CStacksHashmap *qleak_stacks_hashmap;

void uploadLeakData(NSString *leakStr);

bool findPtrInMemoryRegion(vm_address_t address){
    ptr_log_t *ptr_log = qleak_ptrs_hashmap->lookupPtr(address);
    if(ptr_log != NULL){
        ptr_log->size_or_refer++;
        return true;
    }
    return false;
}

void markedThreadToTrackingNextMalloc(const char* name){
    thread_t thread = mach_thread_self();
    OSSpinLockLock(&threadTracking_spinlock);
    threadTracking_hashmap->insertThreadAndUpdateIfExist(thread, name);
    OSSpinLockUnlock(&threadTracking_spinlock);
}

static bool isThreadNeedTracking(const char **name){
    thread_t thread = mach_thread_self();
    OSSpinLockLock(&threadTracking_spinlock);
    thread_data_t *thread_data = threadTracking_hashmap->lookupThread(thread);
    if(thread_data != NULL){
        if(thread_data->needTrack){
            thread_data->needTrack = false;
            if(name != NULL) *name = thread_data->name;
            OSSpinLockUnlock(&threadTracking_spinlock);
            return true;
        }
    }
    OSSpinLockUnlock(&threadTracking_spinlock);
    return false;
}

void malloc_stack_logger(uint32_t type, uintptr_t arg1, uintptr_t arg2, uintptr_t arg3, uintptr_t result, uint32_t backtrace_to_skip)
{
    if(!enableStackTracking){
        return;
    }
    if(arg1 == (uintptr_t)memory_zone){
        isThreadNeedTracking(NULL);
        return ;
    }
    if (type & stack_logging_flag_zone) {
        type &= ~stack_logging_flag_zone;
    }
    if (type == (stack_logging_type_dealloc|stack_logging_type_alloc)) {
        if (arg2 == result) {
            return;
        }
        if (!arg2) {
            if(!isLeakChecking){
                const char *name = NULL;
                if(!isThreadNeedTracking(&name)) return;
                recordMallocStack(result, (uint32_t)arg3,name,4,QQLeakMode);
            }
            return;
        } else {
            removeMallocStack((vm_address_t)arg2,QQLeakMode);
            if(!isLeakChecking){
                const char *name = NULL;
                if(!isThreadNeedTracking(&name)) return;
                recordMallocStack(result, (uint32_t)arg3,name,4,QQLeakMode);
            }
            return;
        }
    }
    if (type == stack_logging_type_dealloc) {
        if (!arg2) return;
        removeMallocStack((vm_address_t)arg2,QQLeakMode);
    }
    else if((type & stack_logging_type_alloc) != 0){
        if(!isLeakChecking){
            const char *name = NULL;
            if(!isThreadNeedTracking(&name)) return;
            recordMallocStack(result, (uint32_t)arg2,name,4,QQLeakMode);
        }
    }
}

void initStackLogging(){
    if(memory_zone == nil){
        memory_zone = malloc_create_zone(0, 0);
        malloc_set_zone_name(memory_zone, "QQLeak");
    }
    current_mode = QQLeakMode;
    default_zone = malloc_default_zone();
    threadTracking_hashmap = new CThreadTrackingHashmap(40);
    initAllImages();
    initBlackClass();
    qleak_ptrs_hashmap = new CPtrsHashmap(100000,QQLeakMode);
    qleak_stacks_hashmap = new CStacksHashmap(50000,QQLeakMode);
}

void beginMallocStackLogging(){
    enableStackTracking = false;
    malloc_logger = (malloc_logger_t *)common_stack_logger;
    hookMalloc();
    [[AllocationTracker getInstance] beginRecord];
    enableStackTracking = true;
    isLeakChecking = false;
}

void clearMallocStackLogging(){
    enableStackTracking = false;
    [[AllocationTracker getInstance] stopRecord];
    unHookMalloc();
//    malloc_logger = NULL;
    OSSpinLockLock(&hashmap_spinlock);
    delete qleak_ptrs_hashmap;
    delete qleak_stacks_hashmap;
    qleak_ptrs_hashmap = NULL;
    qleak_stacks_hashmap = NULL;
    delete threadTracking_hashmap;
    OSSpinLockUnlock(&hashmap_spinlock);
}

void leakCheckingWillStart(){
    [[AllocationTracker getInstance] pausedRecord];
    pausedMallocTracking();
    isLeakChecking = true;
    leaked_hashmap = new CLeakedHashmap(200);
    OSSpinLockUnlock(&hashmap_spinlock);
}
void leakCheckingWillFinish(){
    isLeakChecking = false;
    resumeMallocTracking();
     delete leaked_hashmap;
    [[AllocationTracker getInstance] resumeRecord];
}

void get_all_leak_ptrs()
{
    for(size_t i = 0; i < qleak_ptrs_hashmap->getEntryNum(); i++)
    {
        base_entry_t *entry = qleak_ptrs_hashmap->getHashmapEntry() + i;
        ptr_log_t *current = (ptr_log_t *)entry->root;
        while(current != NULL){
            merge_stack_t *merge_stack = qleak_stacks_hashmap->lookupStack(current->md5);
            if(merge_stack == NULL) {
                current = current->next;
                continue;
            }
            if(merge_stack->extra.name != NULL){
                if(current->size_or_refer == 0){
                    leaked_hashmap->insertLeakPtrAndIncreaseCountIfExist(current->md5, current);
                    qleak_ptrs_hashmap->removePtr(current->address);
                }
                current->size_or_refer = 0;
            }
            else{
                const char* name = getObjectNameExceptBlack((void *)current->address);
                if(name != NULL){
                    merge_stack->extra.name = name;
                    if(current->size_or_refer == 0){
                        leaked_hashmap->insertLeakPtrAndIncreaseCountIfExist(current->md5, current);
                        qleak_ptrs_hashmap->removePtr(current->address);
                    }
                    current->size_or_refer = 0;
                }
                else {
                    qleak_ptrs_hashmap->removePtr(current->address);
                }
            }
            current = current->next;
        }
    }
}

NSString* get_all_leak_stack(size_t *total_count)
{
    get_all_leak_ptrs();
    NSMutableString *stackData = [[[NSMutableString alloc] init] autorelease];
    size_t total = 0;
    for(size_t i = 0; i <leaked_hashmap->getEntryNum(); i++){
        base_entry_t *entry = leaked_hashmap->getHashmapEntry() + i;
        leaked_ptr_t *current = (leaked_ptr_t *)entry->root;
        while(current != NULL){
            merge_stack_t *merge_stack = qleak_stacks_hashmap->lookupStack(current->md5);
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
                if(getImageByAddr(addr, &segImage)){
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

void uploadLeakData(NSString *leakStr)
{
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
