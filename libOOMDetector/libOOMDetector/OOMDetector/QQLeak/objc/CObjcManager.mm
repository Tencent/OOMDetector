//
//  CObjcManager.m
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

#import "CObjcManager.h"
#include <ext/hash_set>
#include <objc/runtime.h>

#if __has_feature(objc_arc)
#error  this file should use MRC
#endif

#define ISA_MASK        0x0000000ffffffff8ULL

typedef struct{
    void* isa;
}objc_class_ptr;

static __gnu_cxx::hash_set<vm_address_t> *black_class_set;
static __gnu_cxx::hash_set<vm_address_t> *current_class_set;

void initBlackClass(){
    static dispatch_once_t sys_once;
    dispatch_once(&sys_once, ^{
        black_class_set = new __gnu_cxx::hash_set<vm_address_t>();
        current_class_set = new __gnu_cxx::hash_set<vm_address_t>();
        int num = objc_getClassList(NULL, 0);
        if(num > 0){
            Class *classList = (Class *)malloc(num * sizeof(Class));
            num = objc_getClassList(classList, num);
            for(int i = 0;i < num;i++){
                const char* name = class_getName(classList[i]);
                if(name != NULL){
                    if((strncmp(name, "_", 1) == 0 && strncmp(name, "__NS", 4) != 0 && strncmp(name,"_NS",3) != 0) || strncmp(name,"__NSCFType",10) == 0){
                        black_class_set->insert((vm_address_t)classList[i]);
                    }
                }
            }
            free(classList);
        }
    });
}

void initCurrentClass(){
    int num = objc_getClassList(NULL, 0);
    if(num > 0){
        Class *classList = (Class *)malloc(num * sizeof(Class));
        num = objc_getClassList(classList, num);
        for(int i = 0;i < num;i++){
            current_class_set->insert((vm_address_t)classList[i]);
        }
        free(classList);
    }
}

void clearCurrentClass()
{
    current_class_set->clear();
}

bool isClassInBlackList(Class cl)
{
    auto it = black_class_set->find((vm_address_t)cl);
    if(it != black_class_set->end()){
        return true;
    }
    return false;
}

const char *getObjectNameExceptBlack(void *obj)
{
    objc_class_ptr *objc_ptr = (objc_class_ptr *)obj;
    Class isa = (Class)((vm_address_t)objc_ptr->isa & ISA_MASK);
    if(isClassInBlackList(isa)){
        return NULL;
    }
    auto it = current_class_set->find((vm_address_t)isa);
    if(it != current_class_set->end()){
        return class_getName(isa);
    }
    return NULL;
}

const char *getObjectName(void *obj)
{
    objc_class_ptr *objc_ptr = (objc_class_ptr *)obj;
    Class isa = (Class)((vm_address_t)objc_ptr->isa & ISA_MASK);
    auto it = current_class_set->find((vm_address_t)isa);
    if(it != current_class_set->end()){
        return class_getName(isa);
    }
    return NULL;
}
