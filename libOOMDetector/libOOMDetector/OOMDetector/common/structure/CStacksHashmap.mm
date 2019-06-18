//
//  CStacksHashmap.m
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

#import "CStacksHashmap.h"
#import "QQLeakMallocStackTracker.h"
#import "CStackHighSpeedLogger.h"

#if __has_feature(objc_arc)
#error This file must be compiled without ARC. Use -fno-objc-arc flag.
#endif

CStacksHashmap::CStacksHashmap(size_t entrys,malloc_zone_t *zone,NSString *path, size_t mmap_size):CBaseHashmap(entrys,zone)
{
    logger = new CStackHighSpeedLogger(500,zone,path);
}

CStacksHashmap::~CStacksHashmap()
{
    for(size_t i = 0; i < entry_num; i++){
        base_entry_t *entry = hashmap_entry + i;
        merge_stack_t *current = (merge_stack_t *)entry->root;
        entry->root = NULL;
        while(current != NULL){
            merge_stack_t *next = current->next;
            hashmap_free(current);
            current = next;
        }
    }
    if(logger != NULL){
        delete logger;
    }
}

void CStacksHashmap::insertStackAndIncreaseCountIfExist(uint64_t digest,base_stack_t *stack)
{
    size_t offset = (size_t)digest%(entry_num - 1);
    base_entry_t *entry = hashmap_entry + offset;
    merge_stack_t *parent = (merge_stack_t *)entry->root;
    access_num++;
    collision_num++;
    if(parent == NULL){
        merge_stack_t *insert_data = create_hashmap_data(digest,stack);
        entry->root = insert_data;
        if(insert_data->size > oom_threshold)
        {
            insert_data->cache_flag = 1;
            logger->updateStack(insert_data, stack);
        }
        record_num++;
        return ;
    }
    else{
        if(parent->digest == digest){
            parent->count += stack->count;
            parent->size += stack->size;
            if(parent->size > oom_threshold)
            {
                parent->cache_flag = 1;
                logger->updateStack(parent, stack);
            }
            return;
        }
        merge_stack_t *current = parent->next;
        while(current != NULL){
            collision_num++;
            if(current->digest == digest){
                current->count += stack->count;
                current->size += stack->size;
                if(current->size > oom_threshold)
                {
                    current->cache_flag = 1;
                    logger->updateStack(current, stack);
                }
                return ;
            }
            parent = current;
            current = current->next;
        }
        merge_stack_t *insert_data = create_hashmap_data(digest,stack);
        parent->next = insert_data;
        current = parent->next;
        if(current->size > oom_threshold)
        {
            current->cache_flag = 1;
            logger->updateStack(current, stack);
        }
        record_num++;
        return ;
    }
}

void CStacksHashmap::removeIfCountIsZero(uint64_t digest,uint32_t size,uint32_t count)
{
    size_t offset = (size_t)digest%(entry_num - 1);
    base_entry_t *entry = hashmap_entry + offset;
    merge_stack_t *parent = (merge_stack_t *)entry->root;
    if(parent == NULL){
        return ;
    }
    else{
        if(parent->digest == digest){
            if(parent->size < size) {
                parent->size = 0;
            }
            else {
                parent->size -= size;
            }
            if(parent->count < count){
                parent->count = 0;
            }
            else {
                parent->count -= count;
            }
            if(parent->cache_flag == 1){
                if(parent->size < oom_threshold){
                    logger->removeStack(parent,true);
                    parent->cache_flag = 0;
                }
                else {
                    logger->removeStack(parent,false);
                }
            }
            if(parent->count <= 0)
            {
                entry->root = parent->next;
                hashmap_free(parent);
                record_num--;
            }
            return ;
        }
        merge_stack_t *current = parent->next;
        while(current != NULL){
            if(current->digest == digest){
                if(current->size < size)
                {
                    current->size = 0;
                }
                else
                {
                    current->size -= size;
                }
                if(current->count < count){
                    current->count = 0;
                }
                else {
                    current->count -= count;
                }
                if(current->cache_flag == 1){
                    if(current->size < oom_threshold){
                        logger->removeStack(current,true);
                        current->cache_flag = 0;
                    }
                    else {
                        logger->removeStack(current,false);
                    }
                }
                if((current->count) <= 0)
                {
                    parent->next = current->next;
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

merge_stack_t *CStacksHashmap::lookupStack(uint64_t digest)
{
    size_t offset = (size_t)digest%(entry_num - 1);
    base_entry_t *entry = hashmap_entry + offset;
    merge_stack_t *parent = (merge_stack_t *)entry->root;
    if(parent == NULL){
        return NULL;
    }
    else{
        if(parent->digest == digest){
            return parent;
        }
        merge_stack_t *current = parent->next;
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

merge_stack_t *CStacksHashmap::create_hashmap_data(uint64_t digest,base_stack_t *base_stack)
{
    merge_stack_t *merge_data = (merge_stack_t *)hashmap_malloc(sizeof(merge_stack_t));
    merge_data->digest = digest;
    merge_data->count = base_stack->count;
    merge_data->cache_flag = 0;
    merge_data->size = base_stack->size;
    merge_data->depth = 0;
    merge_data->next = NULL;
    return merge_data;
}

