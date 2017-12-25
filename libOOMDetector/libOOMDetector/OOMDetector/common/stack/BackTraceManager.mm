//
//  BackTraceManager.m
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

#import "BackTraceManager.h"

#if __has_feature(objc_arc)
#error  this file should use MRC
#endif

//global
size_t max_stack_depth = 10;
malloc_zone_t *memory_zone;
malloc_zone_t *default_zone;
monitor_mode current_mode;
OSSpinLock hashmap_spinlock = OS_SPINLOCK_INIT;

size_t recordBacktrace(BOOL needSystemStack,size_t needAppStackCount,size_t backtrace_to_skip, vm_address_t **app_stack,unsigned char *md5)
{
    CC_MD5_CTX mc;
    CC_MD5_Init(&mc);
    vm_address_t *orig_stack[max_stack_depth_sys];
    size_t depth = backtrace((void**)orig_stack, max_stack_depth_sys);
    size_t appstack_count = 0;
    size_t offset = 0;
    vm_address_t *last_stack = NULL;
    for(size_t i = backtrace_to_skip;i < depth;i++){
        if(appstack_count == 0){
            if(isInAppAddress((vm_address_t)orig_stack[i])){
                if(i < depth - 2) {
                    appstack_count++;
                }
                if(last_stack != NULL){
                    app_stack[offset++] = last_stack;
                }
                app_stack[offset++] = orig_stack[i];
            }
            else {
                if(needSystemStack){
                    app_stack[offset++] = orig_stack[i];
                }
                else {
                    last_stack = orig_stack[i];
                }
            }
            if(offset >= max_stack_depth) break;
        }
        else{
            if(isInAppAddress((vm_address_t)orig_stack[i]) || i == depth -1 || needSystemStack)
            {
                if(i != depth - 2) appstack_count++;
                app_stack[offset++] = orig_stack[i];
            }
            if(offset >= max_stack_depth) break;
        }
        CC_MD5_Update(&mc, &orig_stack[i], sizeof(void*));
    }
    CC_MD5_Final(md5, &mc);
    if(appstack_count >= needAppStackCount) return offset;
    return 0;
}
