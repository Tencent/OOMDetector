//
//  CObjcManager.h
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

#ifndef CObjcManager_h
#define CObjcManager_h

#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <malloc/malloc.h>
#include "QQLeakPredefines.h"

#ifdef __cplusplus
extern "C" {
#endif
    void initBlackClass();
    void initCurrentClass();
    void clearCurrentClass();
    bool isClassInBlackList(Class cl);
    const char *getObjectNameExceptBlack(void *obj);
    const char *getObjectName(void *obj);
#ifdef __cplusplus
}
#endif

#endif /* CObjcManager_h */
