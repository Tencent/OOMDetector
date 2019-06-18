//
//  CLeakedStacksHashmap.h
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

#ifndef CLeakedStacksHashmap_h
#define CLeakedStacksHashmap_h

#import "CBaseHashmap.h"

typedef struct extra_t{
    const char      *name;
    uint32_t        size;
}extra_t;

typedef struct base_leaked_stack_t{
    uint16_t            depth;
    vm_address_t        **stack;
    extra_t             extra;
}base_leaked_stack_t;

typedef struct merge_leaked_stack_t{
    uint64_t                digest;
    uint32_t                depth;
    uint32_t                count;
    vm_address_t            **stack;
    merge_leaked_stack_t    *next;
    extra_t                 extra;
} merge_leaked_stack_t;

class CLeakedStacksHashmap : public CBaseHashmap
{
public:
    CLeakedStacksHashmap(size_t entrys,malloc_zone_t *memory_zone);
    void insertStackAndIncreaseCountIfExist(uint64_t digest,base_leaked_stack_t *stack);
    void removeIfCountIsZero(uint64_t digest, size_t size);
    merge_leaked_stack_t *lookupStack(uint64_t digest);
    ~CLeakedStacksHashmap();
public:
    size_t oom_threshold;
protected:
    merge_leaked_stack_t *create_hashmap_data(uint64_t digest,base_leaked_stack_t *stack);
};

#endif /* CMergestackHashmap_h */
