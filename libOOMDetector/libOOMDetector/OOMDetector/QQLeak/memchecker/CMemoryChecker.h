//
//  CMemoryChecker.h
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
#ifndef C_MEMORY_CHECKER
#define C_MEMORY_CHECKER

#import <Foundation/Foundation.h>
#import "QQLeakPredefines.h"
#include <stdio.h>
#include <pthread.h>
#include <mach/mach.h>
#include "QQLeakStackLogging.h"

typedef enum{
    HEAP_TYPE,
    STACK_TYPE,
    SEGMENT_TYPE,
    REGISTER_TYPE,
    VM_TYPE
}memory_type;

typedef struct leak_range_t{
    vm_range_t range;
    memory_type type;
}leak_range_t;

typedef struct{
    size_t total_num;
    size_t record_num;
    leak_range_t *entry;
}leak_range_list_t;

extern leak_range_list_t *leak_range_list;
extern malloc_zone_t *memorycheck_zone;
extern kern_return_t memory_reader (task_t task, vm_address_t remote_address, vm_size_t size, void **local_memory);

static const char *region_names[5]={
    "Heap",
    "Stack",
    "Segment",
    "Register",
    "VM"
};

class CMemoryChecker
{
public:
    CMemoryChecker();
    void check_ptr_in_vmrange(vm_range_t range,memory_type type);
};

#endif
