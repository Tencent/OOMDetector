//
//  VMStackLogger.h
//  QQMSFContact
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

#ifndef VMStackLogger_h
#define VMStackLogger_h

#import <Foundation/Foundation.h>
#import "BackTraceManager.h"

#ifdef __cplusplus
extern "C" {
#endif
    
    void oom_vm_logger(uint32_t type, uintptr_t arg1, uintptr_t arg2, uintptr_t arg3, uintptr_t result, uint32_t backtrace_to_skip);
    
    void oom_malloc_logger(uint32_t type, uintptr_t arg1, uintptr_t arg2, uintptr_t arg3, uintptr_t result, uint32_t backtrace_to_skip);
    
    void flush_allocation_stack();
    
    void recordMallocStack(vm_address_t address,uint32_t size,const char*name,size_t stack_num_to_skip,monitor_mode mode);
    
    void removeMallocStack(vm_address_t address,monitor_mode mode);
    
#ifdef __cplusplus
}
#endif

#endif /* VMStackLogger_h */
