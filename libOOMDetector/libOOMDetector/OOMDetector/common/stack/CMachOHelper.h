//
//  CMachOHelper.h
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


#ifndef CMachOHelper_h
#define CMachOHelper_h

#include <mach-o/dyld.h>
#include <dlfcn.h>
#include <vector>
#include <mach/mach.h>
#include <malloc/malloc.h>
#include "CSegmentChecker.h"
#include "QQLeakPredefines.h"

typedef struct
{
    const char* name;
    long loadAddr;
    long beginAddr;
    long endAddr;
}segImageInfo;

#ifdef __cplusplus
extern "C" {
#endif
    void initAllImages();
    bool isInAppAddress(vm_address_t addr);
    bool getImageByAddr(vm_address_t addr,segImageInfo *image);
    void removeAllImages();
#ifdef __cplusplus
}
#endif

#endif /* CMachOHelpler_h */
