//
//  QQLeakChecker.mm
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

#import <objc/runtime.h>
#import <libkern/OSAtomic.h>
#import "QQLeakChecker.h"
#import "AllocationTracker.h"
#include "QQLeakStackLogging.h"
#include "CStackChecker.h"
#include "CRegisterChecker.h"
#include "CSegmentChecker.h"
#include "CHeapChecker.h"
#include "QQLeakPredefines.h"
#include "CMallocHook.h"
#include "CThreadTrackingHashmap.h"
#include "CStacksHashmap.h"
#include "CPtrsHashmap.h"
#include "CLeakedHashmap.h"
#include "CObjcManager.h"
#include <malloc/malloc.h>

#if __has_feature(objc_arc)
#error  this file should use MRC
#endif

//memory checker
static CStackChecker *stackChecker;
static CSegmentChecker *segmentChecker;
static CHeapChecker *heapChecker;
static CRegisterChecker *registerChecker;
//static CVMChecker *vmChecker;
//hashmaps
extern CPtrsHashmap *qleak_ptrs_hashmap;
extern CStacksHashmap *qleak_stacks_hashmap;
extern CThreadTrackingHashmap *threadTracking_hashmap;


//flag
static bool isChecking;
static bool isStackLogging;
extern BOOL needSysStack;
//zone
extern malloc_zone_t *memory_zone;
//lock
extern OSSpinLock hashmap_spinlock;
//
extern size_t max_stack_depth;

static QQLeakChecker* qqleak;

@implementation QQLeakChecker

+(QQLeakChecker *)getInstance{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        qqleak = [[QQLeakChecker alloc] init];
    });
    return qqleak;
}

-(id)init{
    if(self = [super init]){
        stackChecker = new CStackChecker();
        segmentChecker = new CSegmentChecker();
        heapChecker = new CHeapChecker();
        registerChecker = new CRegisterChecker();
    }
    return self;
}

-(void)dealloc{
    [super dealloc];
    delete stackChecker;
    delete segmentChecker;
    delete heapChecker;
    delete registerChecker;
}

-(void)executeLeakCheck:(QQLeakCheckCallback)callback{
    if(!isChecking && isStackLogging){
        printf("QQLeakChecker record %lu object and %lu stacks!!! Record average collision:%.2f, stack average collision:%.2f\n",qleak_ptrs_hashmap->getRecordNum(),qleak_stacks_hashmap->getRecordNum(),(double)qleak_ptrs_hashmap->getCollisionNum()/qleak_ptrs_hashmap->getAccessNum(),(double)qleak_stacks_hashmap->getCollisionNum()/qleak_stacks_hashmap->getAccessNum());
        segmentChecker->initAllSegments();
        initCurrentClass();
        leakCheckingWillStart();
        if(stackChecker->suspendAllChildThreads()){
            OSSpinLockUnlock(&hashmap_spinlock);
//            vmChecker->startPtrCheck();
            registerChecker->startPtrCheck();
            stackChecker->startPtrCheck(2);
            segmentChecker->startPtrcheck();
            heapChecker->startPtrCheck();
            size_t total_size = 0;
            NSString *stackData = get_all_leak_stack(&total_size);
            stackChecker->resumeAllChildThreads();
            segmentChecker->removeAllSegments();
            clearCurrentClass();
            leakCheckingWillFinish();
            callback(stackData,total_size);
        }
    }
}

-(void)startStackLogging{
    if(!isStackLogging){
        initStackLogging();
        beginMallocStackLogging();
        isStackLogging = true;
    }
}

-(void)stopStackLogging{
    if(isStackLogging){
        clearMallocStackLogging();
        isStackLogging = false;
    }
}

- (BOOL)isStackLogging
{
    return isStackLogging;
}

-(void)setMaxStackDepth:(size_t)depth
{
    if(depth > 0) max_stack_depth = depth;
}

-(void)setNeedSystemStack:(BOOL)isNeedSys
{
    needSysStack = isNeedSys;
}

#pragma -mark getter
-(size_t)getRecordObjNumber
{
    return qleak_ptrs_hashmap->getRecordNum();
}

-(size_t)getRecordStackNumber
{
    return qleak_stacks_hashmap->getRecordNum();
}

-(double)getOccupyMemory
{
    malloc_statistics_t stat;
    malloc_zone_statistics(memory_zone, &stat);
    double memory = (double)stat.size_in_use/(1024*1024);
    return memory;
}

@end
