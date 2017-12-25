//
//  VMStackLogger.mm
//  QQMSFContact
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

#import "execinfo.h"
#import "CMachOHelper.h"
#import "HighSpeedLogger.h"
#import "QQLeakStackLogging.h"
#import "BackTraceManager.h"
#import "AllocationStackLogger.h"
#import "OOMDetector.h"
#import "QQLeakFileUploadCenter.h"
#import "QQLeakDeviceInfo.h"

#if __has_feature(objc_arc)
#error  this file should use MRC
#endif


//extern
extern size_t normal_size;
extern size_t chunk_size;
extern size_t vm_threshold;
extern size_t oom_threshold;
extern size_t chunk_threshold;
extern size_t max_stack_depth;
extern BOOL needSysStack;
extern BOOL enableVMMonitor;
extern BOOL enableOOMMonitor;
extern BOOL enableChunkMonitor;
extern BOOL needStackWithoutAppStack;
extern malloc_zone_t *memory_zone;
extern malloc_logger_t** vm_sys_logger;
extern HighSpeedLogger *normal_stack_logger;
extern ChunkMallocCallback chunkMallocCallback;

//global
malloc_zone_t *nano_gurd_zone;
CPtrsHashmap *vm_ptrs_hashmap;
CStacksHashmap *vm_stacks_hashmap;
OSSpinLock vm_hashmap_spinlock = OS_SPINLOCK_INIT;
CPtrsHashmap *oom_ptrs_hashmap;
CStacksHashmap *oom_stacks_hashmap;
extern CPtrsHashmap *qleak_ptrs_hashmap;
extern CStacksHashmap *qleak_stacks_hashmap;

static const char *vm_flags[] = {
    "0","MALLOC","MALLOC_SMALL","MALLOC_LARGE","MALLOC_HUGE","SBRK",
    "REALLOC","TINY","ALLOC_LARGE_REUSABLE","MALLOC_LARGE_REUSED",
    "ANALYSIS_TOOL","MALLOC_NANO","12","13","14",
    "15","16","17","18","19",
    "MACH_MSG","IOKIT","22","23","24",
    "25","26","27","28","29",
    "STACK","GUARD","SHARED_PMAP","DYLIB","OBJC_DISPATCHERS",
    "UNSHARED_PMAP","36","37","38","39",
    "APPKIT","FOUNDATION","COREGRAPHICS","CARBON_OR_CORESERVICES_OR_MISC","JAVA",
    "COREDATA","COREDATA_OBJECTIDS","47","48","49",
    "ATS","LAYERKIT","CGIMAGE","TCMALLOC","COREGRAPHICS_DATA",
    "COREGRAPHICS_SHARED","COREGRAPHICS_FRAMEBUFFERS","COREGRAPHICS_BACKINGSTORES","COREGRAPHICS_XALLOC","59",
    "DYLD","DYLD_MALLOC","SQLITE","JAVASCRIPT_CORE","JAVASCRIPT_JIT_EXECUTABLE_ALLOCATOR",
    "JAVASCRIPT_JIT_REGISTER_FILE","GLSL","OPENCL","COREIMAGE","COREIMAGE",
    "IMAGEIO","COREPROFILE","ASSETSD","OS_ALLOC_ONCE","LIBDISPATCH",
    "ACCELERATE","COREUI","COREUIFILE","GENEALOGY","RAWCAMERA",
    "CORPSEINFO","ASL","SWIFT_RUNTIME","SWIFT_METADATA","DHMM",
    "85","SCENEKIT","SKYWALK","88","89"
};

NSString *chunkDataZipPath()
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
    NSString *LibDirectory = [paths objectAtIndex:0];
    NSString *dir = [LibDirectory stringByAppendingPathComponent:@"Caches/OOMTmp"];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:dir])
    {
        [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    return [dir stringByAppendingPathComponent:@"ChunkData.zip"];
}

static void get_chunk_stack(size_t size)
{
    if(enableChunkMonitor){
        vm_address_t *stacks[max_stack_depth_sys];
        size_t depth = backtrace((void**)stacks, max_stack_depth_sys);
        //     OSSpinLockLock(&hashmap_spinlock);
        NSMutableString *stackInfo = [[[NSMutableString alloc] init] autorelease];
        NSDateFormatter* df1 = [[NSDateFormatter new] autorelease];
        df1.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
        NSString *dateStr1 = [df1 stringFromDate:[NSDate date]];
        [stackInfo appendFormat:@"%@ chunk_malloc:%.2fmb stack:\n",dateStr1,(double)size/(1024*1024)];
        for(size_t j = 2; j < depth; j++){
            vm_address_t addr = (vm_address_t)stacks[j];
            segImageInfo segImage;
            if(getImageByAddr(addr, &segImage)){
                [stackInfo appendFormat:@"\"%lu %s 0x%lx 0x%lx\" ",j - 2,(segImage.name != NULL) ? segImage.name : "unknown",segImage.loadAddr,(long)addr];
            }
        }
        [stackInfo appendFormat:@"\n"];

        if ([QQLeakFileUploadCenter defaultCenter].fileDataDelegate) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                NSData *data = [stackInfo dataUsingEncoding:NSUTF8StringEncoding];
                if (data && data.length > 0) {
                    NSDictionary *extra = [NSDictionary dictionaryWithObjectsAndKeys:[[UIDevice currentDevice] systemVersion],@"systemversion",[QQLeakDeviceInfo platform],@"Device",@"chunk_malloc",@"type",nil];
                    [[QQLeakFileUploadCenter defaultCenter] fileData:data extra:extra type:QQStackReportTypeChunkMemory completionHandler:^(BOOL completed) {
                        
                    }];
                }
            });
        }

        if(chunkMallocCallback)
        {
            chunkMallocCallback(size,stackInfo);
        }
     //   OSSpinLockUnlock(&hashmap_spinlock);
    }
}

static void recordVMStack(vm_address_t address,uint32_t size,const char*type,size_t stack_num_to_skip)
{
    base_stack_t base_stack;
    base_ptr_log base_ptr;
    unsigned char md5[16];
    vm_address_t  *stack[max_stack_depth];
    if(needStackWithoutAppStack){
        base_stack.depth = recordBacktrace(needSysStack,0,stack_num_to_skip, stack,md5);
    }
    else {
        base_stack.depth = recordBacktrace(needSysStack,1,stack_num_to_skip, stack,md5);
    }
    if(base_stack.depth > 0){
        base_stack.stack = stack;
        base_stack.extra.size = size;
        base_stack.extra.name = type;
        base_ptr.md5 = md5;
        base_ptr.size = size;
        OSSpinLockLock(&vm_hashmap_spinlock);
        if(vm_ptrs_hashmap && vm_stacks_hashmap){
            if(vm_ptrs_hashmap->insertPtr(address, &base_ptr)){
                vm_stacks_hashmap->insertStackAndIncreaseCountIfExist(md5, &base_stack);
            }
        }
        OSSpinLockUnlock(&vm_hashmap_spinlock);
    }
}


static void removeVMStack(vm_address_t address)
{
    OSSpinLockLock(&vm_hashmap_spinlock);
    if(vm_ptrs_hashmap && vm_stacks_hashmap){
        ptr_log_t *ptr_log = vm_ptrs_hashmap->lookupPtr(address);
        if(ptr_log != NULL)
        {
            unsigned char *md5 = ptr_log->md5;
            if(vm_ptrs_hashmap->removePtr(address)){
                vm_stacks_hashmap->removeIfCountIsZero(md5,(size_t)ptr_log->size_or_refer);
            }
        }
    }
    OSSpinLockUnlock(&vm_hashmap_spinlock);
}

void recordMallocStack(vm_address_t address,uint32_t size,const char*name,size_t stack_num_to_skip,monitor_mode mode)
{
    base_stack_t base_stack;
    base_ptr_log base_ptr;
    unsigned char md5[16];
    vm_address_t  *stack[max_stack_depth];
    if(mode == QQLeakMode){
        base_stack.depth = recordBacktrace(needSysStack,1,stack_num_to_skip + 1, stack,md5);
    }
    else {
        if(needStackWithoutAppStack){
            base_stack.depth = recordBacktrace(needSysStack,0,stack_num_to_skip, stack,md5);
        }
        else {
            base_stack.depth = recordBacktrace(needSysStack,1,stack_num_to_skip, stack,md5);
        }
    }
    
    if(base_stack.depth > 0){
        base_stack.stack = stack;
        if(mode == QQLeakMode){
            base_stack.extra.name = name;
        }
        else {
            base_stack.extra.size = size;
        }
        base_ptr.md5 = md5;
        base_ptr.size = size;
        OSSpinLockLock(&hashmap_spinlock);
        if(mode == OOMDetectorMode){
            if(oom_ptrs_hashmap && oom_stacks_hashmap){
                if(oom_ptrs_hashmap->insertPtr(address, &base_ptr)){
                    oom_stacks_hashmap->insertStackAndIncreaseCountIfExist(md5, &base_stack);
                }
            }
        }
        else {
            if(qleak_ptrs_hashmap && qleak_stacks_hashmap){
                if(qleak_ptrs_hashmap->insertPtr(address, &base_ptr)){
                    qleak_stacks_hashmap->insertStackAndIncreaseCountIfExist(md5, &base_stack);
                }
            }
        }

        OSSpinLockUnlock(&hashmap_spinlock);
    }
}

void removeMallocStack(vm_address_t address,monitor_mode mode)
{
    OSSpinLockLock(&hashmap_spinlock);
    if(mode == OOMDetectorMode){
        if(oom_ptrs_hashmap && oom_stacks_hashmap){
            ptr_log_t *ptr_log = oom_ptrs_hashmap->lookupPtr(address);
            if(ptr_log != NULL)
            {
                unsigned char md5[16];
                strncpy((char *)md5, (const char *)ptr_log->md5, 16);
                size_t size_or_refer = (size_t)ptr_log->size_or_refer;
                if(oom_ptrs_hashmap->removePtr(address)){
                    oom_stacks_hashmap->removeIfCountIsZero(md5, size_or_refer);
                }
            }
        }
    }
    else {
        if(qleak_ptrs_hashmap && qleak_stacks_hashmap){
            ptr_log_t *ptr_log = qleak_ptrs_hashmap->lookupPtr(address);
            if(ptr_log != NULL)
            {
                unsigned char *md5 = ptr_log->md5;
                if(qleak_ptrs_hashmap->removePtr(address)){
                    qleak_stacks_hashmap->removeIfCountIsZero(md5,(size_t)ptr_log->size_or_refer);
                }
            }
        }
    }
    OSSpinLockUnlock(&hashmap_spinlock);
}

void oom_malloc_logger(uint32_t type, uintptr_t arg1, uintptr_t arg2, uintptr_t arg3, uintptr_t result, uint32_t backtrace_to_skip)
{
    if (type & stack_logging_flag_zone) {
        type &= ~stack_logging_flag_zone;
    }
    if (type == (stack_logging_type_dealloc|stack_logging_type_alloc)) {
        if(enableChunkMonitor && arg3 > chunk_threshold){
            get_chunk_stack((size_t)arg3);
        }
        if (arg2 == result) {
            if(enableOOMMonitor){
                removeMallocStack((vm_address_t)arg2,OOMDetectorMode);
                recordMallocStack(result, (uint32_t)arg3,NULL,2,OOMDetectorMode);
            }
            return;
        }
        if (!arg2) {
            if(enableOOMMonitor){
                recordMallocStack(result, (uint32_t)arg3,NULL,2,OOMDetectorMode);
            }
            return;
        } else {
            if(enableOOMMonitor){
                removeMallocStack((vm_address_t)arg2,OOMDetectorMode);
                recordMallocStack(result, (uint32_t)arg3,NULL,2,OOMDetectorMode);
            }
            return;
        }
    }
    else if (type == stack_logging_type_dealloc) {
        if (!arg2) return;
        if(enableOOMMonitor){
            removeMallocStack((vm_address_t)arg2,OOMDetectorMode);
        }
    }
    else if((type & stack_logging_type_alloc) != 0){
        if(arg1 == (uintptr_t)nano_gurd_zone){
            return ;
        }
        if(enableChunkMonitor && arg2 > chunk_threshold){
            get_chunk_stack((size_t)arg2);
        }
        if(enableOOMMonitor){
            recordMallocStack(result, (uint32_t)arg2,NULL,2,OOMDetectorMode);
        }
    }
}

void oom_vm_logger(uint32_t type, uintptr_t arg1, uintptr_t arg2, uintptr_t arg3, uintptr_t result, uint32_t backtrace_to_skip)
{
    if(type & stack_logging_type_vm_allocate){   //vm_mmap or vm_allocate
        type = (type & ~stack_logging_type_vm_allocate);
        type = type >> 24;
        if((type >= 1 && type <= 11) || arg2 == 0){
            return;
        }
        const char *flag = "unknown";
        if(type <= 89){
            flag = vm_flags[type];
        }
        recordVMStack(vm_address_t(result), uint32_t(arg2), flag, 2);
    }
    else if(type & stack_logging_type_vm_deallocate){  //vm_deallocate or munmap
        removeVMStack(vm_address_t(arg2));
    }
}

void flush_allocation_stack()
{
    normal_stack_logger->current_len = 0;
    NSDateFormatter* df = [[NSDateFormatter new] autorelease];
    df.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
    NSString *dateStr = [df stringFromDate:[NSDate date]];
    int exceedNum = 0;
    //flush malloc stack
    if(enableOOMMonitor){
        OSSpinLockLock(&hashmap_spinlock);
        malloc_logger = NULL;
        sprintfLogger(normal_stack_logger,normal_size,"%s normal_malloc_num:%ld stack_num:%ld\n",[dateStr UTF8String],oom_ptrs_hashmap->getRecordNum(),oom_stacks_hashmap->getRecordNum());
        for(size_t i = 0; i < oom_stacks_hashmap->getEntryNum(); i++){
            base_entry_t *entry = oom_stacks_hashmap->getHashmapEntry() + i;
            merge_stack_t *current = (merge_stack_t *)entry->root;
            while(current != NULL){
                if(current->extra.size > oom_threshold){
                    exceedNum++;
                    sprintfLogger(normal_stack_logger,normal_size,"Malloc_size:%lfmb num:%u stack:\n",(double)(current->extra.size)/(1024*1024), current->count);
                    for(size_t j = 0; j < current ->depth; j++){
                        vm_address_t addr = (vm_address_t)current->stack[j];
                        segImageInfo segImage;
                        if(getImageByAddr(addr, &segImage)){
                            sprintfLogger(normal_stack_logger,normal_size,"\"%lu %s 0x%lx 0x%lx\" ",j,(segImage.name != NULL) ? segImage.name : "unknown",segImage.loadAddr,(long)addr);
                        }
                    }
                    sprintfLogger(normal_stack_logger,normal_size,"\n");
                }
                current = current->next;
            }
        }
        malloc_logger = (malloc_logger_t *)common_stack_logger;//oom_malloc_logger;
        OSSpinLockUnlock(&hashmap_spinlock);
    }
    sprintfLogger(normal_stack_logger,normal_size,"\n");
    //flush vm
    if(enableVMMonitor){
        OSSpinLockLock(&vm_hashmap_spinlock);
        *vm_sys_logger = NULL;
        sprintfLogger(normal_stack_logger,normal_size,"%s vm_allocate_num:%ld stack_num:%ld\n",[dateStr UTF8String],vm_ptrs_hashmap->getRecordNum(),vm_stacks_hashmap->getRecordNum());
        for(size_t i = 0; i < vm_stacks_hashmap->getEntryNum(); i++){
            base_entry_t *entry = vm_stacks_hashmap->getHashmapEntry() + i;
            merge_stack_t *current = (merge_stack_t *)entry->root;
            while(current != NULL){
                if(current->extra.size > vm_threshold){
                    exceedNum++;
                    sprintfLogger(normal_stack_logger,normal_size,"vm_allocate_size:%.2fmb num:%u type:%s stack:\n",(double)(current->extra.size)/(1024*1024), current->count,current->extra.name);
                    for(size_t j = 0; j < current ->depth; j++){
                        vm_address_t addr = (vm_address_t)current->stack[j];
                        segImageInfo segImage;
                        if(getImageByAddr(addr, &segImage)){
                            sprintfLogger(normal_stack_logger,normal_size,"\"%lu %s 0x%lx 0x%lx\" ",j,(segImage.name != NULL) ? segImage.name : "unknown",segImage.loadAddr,(long)addr);
                        }
                    }
                    sprintfLogger(normal_stack_logger,normal_size,"\n");
                }
                current = current->next;
            }
        }
    }
    if(exceedNum == 0){
        cleanLogger(normal_stack_logger);
    }
    if(enableVMMonitor){
        *vm_sys_logger = oom_vm_logger;
    }
    OSSpinLockUnlock(&vm_hashmap_spinlock);
    syncLogger(normal_stack_logger);
}
