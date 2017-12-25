//
//  QQLeakStackLogging.h
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

#ifndef CMallocStackLogging_h
#define CMallocStackLogging_h

#import <UIKit/UIKit.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <malloc/malloc.h>
#include <stdarg.h>
#include <mach/mach_init.h>
#include <libkern/OSAtomic.h>
#include <sys/mman.h>
#include <mach/vm_statistics.h>
#include <malloc/malloc.h>
#include "QQLeakPredefines.h"
#include "CommonMallocLogger.h"

#ifdef __cplusplus
extern "C" {
#endif
    //initialize
    void initStackLogging();
    //begin tracking malloc logging
    void beginMallocStackLogging();
    //clear tracking
    void clearMallocStackLogging();
    //called before leak checking
    void leakCheckingWillStart();
    //called after leak checking
    void leakCheckingWillFinish();
    //find ptr of address in memory
    bool findPtrInMemoryRegion(vm_address_t address);
    //marked the current thread need tracking the next malloc
    void markedThreadToTrackingNextMalloc(const char* name);
    //get the result of leak checking
    NSString* get_all_leak_stack(size_t *total_count);
    
    void malloc_stack_logger(uint32_t type, uintptr_t arg1, uintptr_t arg2, uintptr_t arg3, uintptr_t result, uint32_t backtrace_to_skip);

#ifdef __cplusplus
}
#endif

#endif /* CMallocStackLogging_h */

