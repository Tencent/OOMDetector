//
//  CStacksHashmap.h
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

#ifndef CStacksHashmap_h
#define CStacksHashmap_h

#import "CBaseHashmap.h"

class CStackHighSpeedLogger;

typedef struct base_stack_t{
    uint32_t            depth;
    vm_address_t        **stack;
    uint32_t            size;
    uint32_t            type;
    uint32_t            count;
}base_stack_t;

typedef struct merge_stack_t{
    uint64_t            digest;
    uint32_t            depth;
    uint32_t            count;
    uint32_t            cache_flag;
    uint32_t            size;
    merge_stack_t       *next;
} merge_stack_t;

class CStacksHashmap : public CBaseHashmap
{
public:
    CStacksHashmap(size_t entrys,malloc_zone_t *memory_zone,NSString *path, size_t mmap_size);
    void insertStackAndIncreaseCountIfExist(uint64_t digest,base_stack_t *stack);
    void removeIfCountIsZero(uint64_t digest,uint32_t size,uint32_t count);
    merge_stack_t *lookupStack(uint64_t digest);
    ~CStacksHashmap();
public:
    size_t oom_threshold;
    bool is_vm = false;
protected:
    merge_stack_t *create_hashmap_data(uint64_t digest,base_stack_t *stack);
private:
    CStackHighSpeedLogger *logger;
};

#endif /* CMergestackHashmap_h */
