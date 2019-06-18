//
//  CStackHighSpeedLogger.h
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

#import "CStacksHashmap.h"
#import <malloc/malloc.h>

typedef struct cache_stack_t{
    uint32_t            count;
    uint32_t            size;
    uint32_t            type;       //0:malloc 1:vm
    uint32_t            stack_depth;
    uint64_t            digest;
    vm_address_t        *stacks[64];
} cache_stack_t;

class CStackHighSpeedLogger
{
public:
    CStackHighSpeedLogger(size_t num,malloc_zone_t *memory_zone,NSString *path);
    void updateStack(merge_stack_t *current,base_stack_t *stack);
    void removeStack(merge_stack_t *current,bool needRemove);
    ~CStackHighSpeedLogger();
private:
    cache_stack_t *mmap_ptr;
    size_t mmap_size;
    malloc_zone_t *memory_zone;
    FILE *mmap_fp;
    bool isFailed;
    size_t entry_num;
    size_t total_logger_cnt;
};
