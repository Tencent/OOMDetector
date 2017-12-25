//
//  BackTraceManager.h
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

#ifndef BackTraceManager_h
#define BackTraceManager_h
#import <Foundation/Foundation.h>
#import <mach/vm_types.h>
#import "execinfo.h"
#import <CommonCrypto/CommonDigest.h>
#import "QQLeakPredefines.h"
#import "CMachOHelper.h"
#import "CbaseHashmap.h"
#include "CStacksHashmap.h"
#include "CPtrsHashmap.h"

#ifdef __cplusplus
extern "C" {
#endif
    typedef void (malloc_logger_t)(uint32_t type, uintptr_t arg1, uintptr_t arg2, uintptr_t arg3, uintptr_t result, uint32_t num_hot_frames_to_skip);
    extern malloc_logger_t* malloc_logger;
//    extern CPtrsHashmap *ptrs_hashmap;
//    extern CStacksHashmap *stacks_hashmap;
    extern OSSpinLock hashmap_spinlock;
    extern malloc_zone_t *default_zone;
    extern monitor_mode current_mode;
    
    size_t recordBacktrace(BOOL needSystemStack,size_t needAppStackCount,size_t backtrace_to_skip, vm_address_t **app_stack,unsigned char *md5);
    
#ifdef __cplusplus
}
#endif

#endif /* BackTraceManager_h */
