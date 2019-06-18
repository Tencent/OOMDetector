//
//  COOMDetector.h
//  libOOMDetector
//
//  Created by rosen on 2017/12/26.
//

#import <Foundation/Foundation.h>
#import <libkern/OSAtomic.h>
#import <sys/mman.h>
#import <mach/mach_init.h>
#import <mach/vm_statistics.h>
#import "zlib.h"
#import "stdio.h"
#import "OOMMemoryStackTracker.h"
#import "QQLeakPredefines.h"
#import "CStackHelper.h"
#import "OOMDetector.h"
#import "CStacksHashmap.h"
#import "QQLeakMallocStackTracker.h"
#import "OOMDetectorLogger.h"
#import "QQLeakFileUploadCenter.h"
#import "QQLeakDeviceInfo.h"
#import "CStackHelper.h"
#import "CommonMallocLogger.h"
#import <pthread.h>
#import <libkern/OSAtomic.h>
#import <os/lock.h>

typedef void (*LogPrinter)(char *log);

typedef enum{
    Malloc_Type,
    VM_Type
}malloc_type;

class COOMDetector
{
public:
    COOMDetector();
    ~COOMDetector();
    void recordMallocStack(vm_address_t address,uint32_t size,size_t stack_num_to_skip);
    void removeMallocStack(vm_address_t address);
    void recordVMStack(vm_address_t address,uint32_t size,size_t stack_num_to_skip);
    void removeVMStack(vm_address_t address);
    void initLogger(malloc_zone_t *zone, NSString *path, size_t mmap_size);
    void initVMLogger(malloc_zone_t *zone, NSString *path, size_t mmap_size);
    BOOL startMallocStackMonitor(size_t threshholdInBytes);
    void stopMallocStackMonitor();
    BOOL startVMStackMonitor(size_t threshholdInBytes);
    void stopVMStackMonitor();
    void startSingleChunkMallocDetector(size_t threshholdInBytes,ChunkMallocBlock mallocBlock);
    void stopSingleChunkMallocDetector();
    void get_chunk_stack(size_t size);
public:
    malloc_zone_t *getMemoryZone();
    CPtrsHashmap *getPtrHashmap();
    CStacksHashmap *getStackHashmap();
public:
    size_t max_stack_depth = 64;
    BOOL needSysStack = YES;
    BOOL enableOOMMonitor = NO;
    BOOL enableChunkMonitor = NO;
    BOOL enableVMMonitor = NO;
    BOOL needStackWithoutAppStack = YES;
    size_t oom_threshold;
    size_t chunk_threshold;
    size_t vm_threshold;
    BOOL needCleanStackCache = YES;
    size_t cache_clean_threshold = 1024*1000;
    size_t cache_clean_num = 300000;
    bool use_unfair_lock = false;
    uint32_t sampleFactor = 1;
    uint32_t sampleThreshold = 1024*3;
public:
    malloc_logger_t** vm_sys_logger = NULL;
public:
    NSString* chunkDataZipPath();
    void lockHashmap();
    void unlockHashmap();
private:
    void removeTinyMallocStacks(size_t threshold);
private:
    CPtrsHashmap *oom_ptrs_hashmap;
    CStacksHashmap *oom_stacks_hashmap;
    CPtrsHashmap *oom_vm_ptrs_hashmap;
    CStacksHashmap *oom_vm_stacks_hashmap;
    ChunkMallocBlock chunkMallocCallback = NULL;
    CStackHelper *stackHelper = NULL;
    CStackHelper *chunk_stackHelper = NULL;
    QQLeakFileUploadCenter *fileUploadCenter = nil;
    NSString *log_path;
    size_t log_mmap_size;
    NSString *vm_log_path;
    size_t vm_log_mmap_size;
    os_unfair_lock hashmap_unfair_lock = OS_UNFAIR_LOCK_INIT;
    dispatch_semaphore_t hashmap_sema;
    os_unfair_lock vm_hashmap_unfair_lock = OS_UNFAIR_LOCK_INIT;
    dispatch_semaphore_t vm_hashmap_sema;
};

