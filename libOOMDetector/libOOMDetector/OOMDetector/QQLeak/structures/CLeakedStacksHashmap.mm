//
//  CLeakedStacksHashmap.mm
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

#import "CLeakedStacksHashmap.h"
#import "QQLeakMallocStackTracker.h"

#if __has_feature(objc_arc)
#error This file must be compiled without ARC. Use -fno-objc-arc flag.
#endif

CLeakedStacksHashmap::CLeakedStacksHashmap(size_t entrys,malloc_zone_t *zone):CBaseHashmap(entrys,zone)
{

}

CLeakedStacksHashmap::~CLeakedStacksHashmap()
{
    for(size_t i = 0; i < entry_num; i++){
        base_entry_t *entry = hashmap_entry + i;
        merge_leaked_stack_t *current = (merge_leaked_stack_t *)entry->root;
        entry->root = NULL;
        while(current != NULL){
            merge_leaked_stack_t *next = current->next;
            if(current->stack != NULL){
                hashmap_free(current->stack);
            }
            hashmap_free(current);
            current = next;
        }
    }
}

void CLeakedStacksHashmap::insertStackAndIncreaseCountIfExist(uint64_t digest,base_leaked_stack_t *stack)
{
    size_t offset = (size_t)digest%(entry_num - 1);
    base_entry_t *entry = hashmap_entry + offset;
    merge_leaked_stack_t *parent = (merge_leaked_stack_t *)entry->root;
    access_num++;
    collision_num++;
    if(parent == NULL){
        merge_leaked_stack_t *insert_data = create_hashmap_data(digest,stack);
        entry->root = insert_data;
        record_num++;
        return ;
    }
    else{
        if(parent->digest == digest){
            parent->count++;
            parent->extra.name = stack->extra.name;
            parent->extra.size += stack->extra.size;
            if(parent->stack == NULL)
            {
                parent->stack = (vm_address_t **)hashmap_malloc(stack->depth*sizeof(vm_address_t*));
                memcpy(parent->stack, stack->stack, stack->depth * sizeof(vm_address_t *));
                parent->depth = stack->depth;
            }
            return;
        }
        merge_leaked_stack_t *current = parent->next;
        while(current != NULL){
            collision_num++;
            if(current->digest == digest){
                current->count++;
                current->extra.name = stack->extra.name;
                current->extra.size += stack->extra.size;
                if(current->stack == NULL)
                {
                    current->stack = (vm_address_t **)hashmap_malloc(stack->depth*sizeof(vm_address_t*));
                    memcpy(current->stack, stack->stack, stack->depth * sizeof(vm_address_t *));
                    current->depth = stack->depth;
                }
                return ;
            }
            parent = current;
            current = current->next;
        }
        merge_leaked_stack_t *insert_data = create_hashmap_data(digest,stack);
        parent->next = insert_data;
        record_num++;
        return ;
    }
}

void CLeakedStacksHashmap::removeIfCountIsZero(uint64_t digest,size_t size)
{
    size_t offset = (size_t)digest%(entry_num - 1);
    base_entry_t *entry = hashmap_entry + offset;
    merge_leaked_stack_t *parent = (merge_leaked_stack_t *)entry->root;
    if(parent == NULL){
        return ;
    }
    else{
        if(parent->digest == digest){
            if(parent->extra.size < size) parent->extra.size = 0;
            else parent->extra.size -= size;
            if(--(parent->count) <= 0 || parent->extra.size == 0)
            {
                entry->root = parent->next;
                if(parent->stack != NULL){
                    hashmap_free(parent->stack);
                }
                hashmap_free(parent);
                record_num--;
            }
            return ;
        }
        merge_leaked_stack_t *current = parent->next;
        while(current != NULL){
            if(current->digest == digest){
                if(current->extra.size < size) current->extra.size = 0;
                else current->extra.size -= size;
                if(--(current->count) <= 0 || current->extra.size == 0)
                {
                    parent->next = current->next;
                    if(current->stack != NULL){
                        hashmap_free(current->stack);
                    }
                    hashmap_free(current);
                    record_num--;
                }
                return ;
            }
            parent = current;
            current = current->next;
        }
    }
}

merge_leaked_stack_t *CLeakedStacksHashmap::lookupStack(uint64_t digest)
{
    size_t offset = (size_t)digest%(entry_num - 1);
    base_entry_t *entry = hashmap_entry + offset;
    merge_leaked_stack_t *parent = (merge_leaked_stack_t *)entry->root;
    if(parent == NULL){
        return NULL;
    }
    else{
        if(parent->digest == digest){
            return parent;
        }
        merge_leaked_stack_t *current = parent->next;
        while(current != NULL){
            if(current->digest == digest){
                return current;
            }
            parent = current;
            current = current->next;
        }
    }
    return NULL;
}

merge_leaked_stack_t *CLeakedStacksHashmap::create_hashmap_data(uint64_t digest,base_leaked_stack_t *base_stack)
{
    merge_leaked_stack_t *merge_data = (merge_leaked_stack_t *)hashmap_malloc(sizeof(merge_leaked_stack_t));
    merge_data->digest = digest;
    merge_data->count = 1;
    merge_data->extra.name = base_stack->extra.name;
    merge_data->stack = (vm_address_t **)hashmap_malloc(base_stack->depth*sizeof(vm_address_t*));
    memcpy(merge_data->stack, base_stack->stack, base_stack->depth * sizeof(vm_address_t *));
    merge_data->depth = base_stack->depth;
    merge_data->next = NULL;
    return merge_data;
}

