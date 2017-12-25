//
//  OOMDetector.mm
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

#import <libkern/OSAtomic.h>
#include <sys/mman.h>
#include <mach/mach_init.h>
#import <mach/vm_statistics.h>
#import "zlib.h"
#import "stdio.h"
#import "AllocationStackLogger.h"
#import "QQLeakPredefines.h"
#import "HighSpeedLogger.h"
#include "CMachOHelper.h"
#import "OOMDetector.h"
#include "CStacksHashmap.h"
#include "QQLeakStackLogging.h"
#import "OOMDetectorLogger.h"
#import "QQLeakFileUploadCenter.h"
#import "QQLeakDeviceInfo.h"
#import "QQLeakDeviceInfo.h"

#if __has_feature(objc_arc)
#error  this file should use MRC
#endif

#if defined(USE_VM_LOGGER_FORCEDLY) || defined(DEBUG)
#define USE_VM_LOGGER
#endif

#ifdef USE_VM_LOGGER

#if defined(USE_VM_LOGGER_FORCEDLY)
#warning 请务必在提交app store审核之前注释掉“USE_VM_LOGGER_FORCEDLY”宏！！！
#endif

//__syscall_logger是系统私有API，在appstore版本千万不要引用!!!!!
extern malloc_logger_t* __syscall_logger;

#endif

//static
static OOMDetector *catcher;
static NSString *currentDir;

//global
size_t oom_threshold;
size_t chunk_threshold;
size_t vm_threshold;
HighSpeedLogger *normal_stack_logger;
BOOL enableOOMMonitor;
BOOL enableChunkMonitor;
BOOL enableVMMonitor;
BOOL needSysStack;
BOOL needStackWithoutAppStack;
size_t normal_size = 512*1024;
size_t chunk_size = 10*1024;
ChunkMallocCallback chunkMallocCallback;
malloc_logger_t** vm_sys_logger;

//extern
extern malloc_zone_t *memory_zone;
extern size_t max_stack_depth;
extern size_t vm_threshold;
extern CPtrsHashmap *vm_ptrs_hashmap;
extern CStacksHashmap *vm_stacks_hashmap;
extern CPtrsHashmap *oom_ptrs_hashmap;
extern CStacksHashmap *oom_stacks_hashmap;
extern OSSpinLock hashmap_spinlock;
extern OSSpinLock vm_hashmap_spinlock;
extern pthread_mutex_t vm_mutex;
extern pthread_mutex_t malloc_mutex;

void printLog(char *log)
{
    if ([OOMDetector getInstance].logPrintBlock) {
        [OOMDetector getInstance].logPrintBlock([NSString stringWithUTF8String:log]);
    }
}

void myChunkMallocCallback(size_t bytes, NSString *stack)
{
    if ([OOMDetector getInstance].chunkMallocBlock) {
        [OOMDetector getInstance].chunkMallocBlock(bytes, stack);
    }
}


@interface OOMDetector()
{
    NSString *_normal_path;
    NSRecursiveLock *_flushLock;

    NSTimer *_timer;
    double _dumpLimit;
    BOOL _needAutoDump;
    QQLeakChecker *_leakChecker;
}

@end

@implementation OOMDetector

+(OOMDetector *)getInstance
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        catcher = [OOMDetector new];
    });
    return catcher;
}

-(id)init
{
    if(self = [super init]){
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
        NSString *LibDirectory = [paths objectAtIndex:0];
        NSDateFormatter* df = [[NSDateFormatter new] autorelease];
        df.dateFormat = @"yyyyMMdd_HHmmssSSS";
        NSString *dateStr = [df stringFromDate:[NSDate date]];
        currentDir = [[LibDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"OOMDetector/%@",dateStr]] retain];
        _normal_path = [[currentDir stringByAppendingPathComponent:[NSString stringWithFormat:@"normal_malloc%@.log",dateStr]] retain];
        if(memory_zone == nil){
            memory_zone = malloc_create_zone(0, 0);
            malloc_set_zone_name(memory_zone, "OOMDetector");
        }
        _flushLock = [NSRecursiveLock new];

    }
    return self;
}

- (void)setupWithDefaultConfig
{
    CGFloat OOMThreshhold = 300.f;
    NSString *platform = [QQLeakDeviceInfo platform];
    NSString *prefix = @"iPhone";
    if ([platform hasPrefix:prefix]) {
        if ([[[[platform substringFromIndex:prefix.length] componentsSeparatedByString:@","] firstObject] intValue] > 7) {
            OOMThreshhold = 800.f;
        }
    }
    [self setMaxStackDepth:50];
    [self setNeedSystemStack:YES];
    [self setNeedStacksWithoutAppStack:YES];
    // 开启内存触顶监控
    [self startMaxMemoryStatistic:OOMThreshhold];
    
    // 显示内存悬浮球
    [self showMemoryIndicatorView:YES];
}

- (void)showMemoryIndicatorView:(BOOL)yn
{
    [[OOMStatisticsInfoCenter getInstance] showMemoryIndicatorView:yn];
}

- (void)setupLeakChecker
{
    QQLeakChecker *leakChecker = [QQLeakChecker getInstance];
    _leakChecker = leakChecker;
    
    //设置堆栈最大长度为10，超过10将被截断
    [leakChecker setMaxStackDepth:10];
    //开始记录对象分配堆栈
    [leakChecker startStackLogging];
}

- (QQLeakChecker *)currentLeakChecker
{
    return _leakChecker;
}

- (void)executeLeakCheck:(QQLeakCheckCallback)callback
{
    [[self currentLeakChecker] executeLeakCheck:callback];
}

-(void)registerLogCallback:(logCallback)logger
{
    oom_logger = logger;
}

-(void)startMaxMemoryStatistic:(double)overFlowLimit
{

    [[OOMStatisticsInfoCenter getInstance] startMemoryOverFlowMonitor:overFlowLimit];

}

-(BOOL)startMallocStackMonitor:(size_t)threshholdInBytes needAutoDumpWhenOverflow:(BOOL)needAutoDump dumpLimit:(double)dumpLimit sampleInterval:(NSTimeInterval)sampleInterval
{
    if(!enableOOMMonitor){
        NSFileManager *fileManager = [NSFileManager defaultManager];
        if (![fileManager fileExistsAtPath:currentDir]) {
            [fileManager createDirectoryAtPath:currentDir withIntermediateDirectories:YES attributes:nil error:nil];
        }
        if (![fileManager fileExistsAtPath:_normal_path]) {
            [fileManager createFileAtPath:_normal_path contents:nil attributes:nil];
        }
        normal_stack_logger = createLogger(memory_zone, _normal_path, normal_size);
        if(normal_stack_logger != NULL){
            oom_stacks_hashmap = new CStacksHashmap(50000,OOMDetectorMode);
            oom_ptrs_hashmap = new CPtrsHashmap(250000,OOMDetectorMode);
            enableOOMMonitor = YES;
            normal_stack_logger->logPrinterCallBack = printLog;
        }
        else {
            enableOOMMonitor = NO;
        }
        if(enableOOMMonitor){
            default_zone = malloc_default_zone();
            current_mode = OOMDetectorMode;
            initAllImages();
            oom_threshold = threshholdInBytes;
            malloc_logger = (malloc_logger_t *)common_stack_logger;//(malloc_logger_t *)oom_malloc_logger;
        }
    }

    if(needAutoDump){
        _dumpLimit = dumpLimit;
        _timer = [NSTimer timerWithTimeInterval:sampleInterval target:self selector:@selector(detectorTask) userInfo:nil repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
        [_timer fire];
    }

    return enableOOMMonitor;
}


-(void)detectorTask
{
    double currentMemory = [QQLeakDeviceInfo appUsedMemory];
    //flush stack
    if(currentMemory > _dumpLimit){
        [self flush_allocation_stack];
    }
}


-(void)stopMallocStackMonitor
{
    if(enableOOMMonitor){
//        malloc_logger = NULL;
        OSSpinLockLock(&hashmap_spinlock);
        CPtrsHashmap *tmp_ptr = oom_ptrs_hashmap;
        CStacksHashmap *tmp_stack = oom_stacks_hashmap;
        oom_stacks_hashmap = NULL;
        oom_ptrs_hashmap = NULL;
        OSSpinLockUnlock(&hashmap_spinlock);
        delete tmp_ptr;
        delete tmp_stack;
    }

    if(_timer){
        [_timer invalidate];
    }

}

-(void)setupVMLogger
{
#ifdef USE_VM_LOGGER
    vm_sys_logger = (malloc_logger_t**)&__syscall_logger;
#else
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"提示" message:@"你在Release模式下调用了startVMStackMonitor:方法，Release模式下只有打开了USE_VM_LOGGER_FORCEDLY宏之后startVMStackMonitor:方法才会生效，不过切记不要在app store版本中打开USE_VM_LOGGER_FORCEDLY宏" delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil, nil];
    [alert show];
#endif
    
}

-(BOOL)startVMStackMonitor:(size_t)threshHoldInbytes
{
    if (NULL == vm_sys_logger) {
        [self setupVMLogger];
    }
    if(!enableVMMonitor && vm_sys_logger){
        if(!normal_stack_logger){
            NSFileManager *fileManager = [NSFileManager defaultManager];
            if (![fileManager fileExistsAtPath:currentDir]) {
                [fileManager createDirectoryAtPath:currentDir withIntermediateDirectories:YES attributes:nil error:nil];
            }
            if (![fileManager fileExistsAtPath:_normal_path]) {
                [fileManager createFileAtPath:_normal_path contents:nil attributes:nil];
            }
            normal_stack_logger = createLogger(memory_zone, _normal_path, normal_size);
        }
        if(normal_stack_logger != NULL){
            vm_stacks_hashmap = new CStacksHashmap(1000,OOMDetectorMode);
            vm_ptrs_hashmap = new CPtrsHashmap(2000,OOMDetectorMode);
            enableVMMonitor = YES;
        }
        else {
            enableVMMonitor = NO;
        }
        if(enableVMMonitor){
            current_mode = OOMDetectorMode;
            initAllImages();
            vm_threshold = threshHoldInbytes;
            *vm_sys_logger = oom_vm_logger;
        }
    }
    return YES;
}

-(void)stopVMStackMonitor
{
    if(enableVMMonitor && vm_sys_logger){
        if(normal_stack_logger != NULL){
            OSSpinLockLock(&vm_hashmap_spinlock);
            CPtrsHashmap *tmp_ptr = vm_ptrs_hashmap;
            CStacksHashmap *tmp_stack = vm_stacks_hashmap;
            vm_ptrs_hashmap = NULL;
            vm_stacks_hashmap = NULL;
            OSSpinLockUnlock(&vm_hashmap_spinlock);
            delete tmp_ptr;
            delete tmp_stack;
        }
        *vm_sys_logger = NULL;
        enableVMMonitor = NO;
    }
}

-(BOOL)startSingleChunkMallocDetector:(size_t)threshholdInBytes callback:(ChunkMallocBlock)callback
{
    if(!enableChunkMonitor){
        enableChunkMonitor = YES;
        if(enableChunkMonitor){
            default_zone = malloc_default_zone();
            current_mode = OOMDetectorMode;
            initAllImages();
            chunk_threshold = threshholdInBytes;
            chunkMallocCallback = myChunkMallocCallback;
            self.chunkMallocBlock = callback;
            malloc_logger = (malloc_logger_t *)common_stack_logger;//(malloc_logger_t *)oom_malloc_logger;
        }
    }
    return enableChunkMonitor;
}

-(void)stopSingleChunkMallocDetector
{
    if(!enableOOMMonitor && enableChunkMonitor){
        malloc_logger = NULL;
    }
    enableChunkMonitor = NO;
}

-(void)flush_allocation_stack
{
    [_flushLock lock];
    flush_allocation_stack();
    [_flushLock unlock];
}


-(void)uploadAllStack
{
    if ([QQLeakFileUploadCenter defaultCenter].fileDataDelegate) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSFileManager *fm = [NSFileManager defaultManager];
            NSString *OOMDataPath = [self OOMDataPath];
            NSString *currentLogDir = [self currentStackLogDir];
            NSArray *paths = [fm contentsOfDirectoryAtPath:OOMDataPath error:nil];
            for(NSString *path in paths)
            {
                NSString *fullPath = [OOMDataPath stringByAppendingPathComponent:path];
                BOOL isDir = NO;
                if([fm fileExistsAtPath:fullPath isDirectory:&isDir]){
                    if(!isDir) continue;
                    
                    if(currentLogDir == nil || (currentLogDir != nil && ![fullPath isEqualToString:currentLogDir])){
                        
                        NSDirectoryEnumerator *internal_enumerator = [fm enumeratorAtPath:fullPath];
                        NSString *internal_path = [internal_enumerator nextObject];
                        
                        while(internal_path != nil){
                            QQStackReportType reportType = QQStackReportTypeOOMLog;
                            NSString *internal_full_path = [fullPath stringByAppendingPathComponent:internal_path];
                            NSData *data = [NSData dataWithContentsOfFile:internal_full_path];
                            size_t stack_size = strlen((char *)data.bytes);
                            
                            if(stack_size == 0){
                                [fm removeItemAtPath:fullPath error:nil];
                            }
                            
                            if(![internal_path hasPrefix:@"normal_malloc"]){
                                reportType = QQStackReportTypeChunkMemory;
                            }
                            
                            if (stack_size > 0 && data.length > 0) {
                                NSDictionary *extra = [NSDictionary dictionaryWithObjectsAndKeys:[[UIDevice currentDevice] systemVersion],@"systemversion",[QQLeakDeviceInfo platform],@"Device",@"normal_malloc",@"type",nil];
                                [[QQLeakFileUploadCenter defaultCenter] fileData:data extra:extra type:reportType completionHandler:^(BOOL completed) {
                                    if (completed) {
                                        [fm removeItemAtPath:fullPath error:nil];
                                    }
                                }];
                            }
                            
                            internal_path = [internal_enumerator nextObject];
                        }
                    }
                }
            }
        });
    }
}

-(NSString *)OOMDataPath
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
    NSString *LibDirectory = [paths objectAtIndex:0];
    return [LibDirectory stringByAppendingPathComponent:@"OOMDetector"];
}
                   
-(NSString *)OOMZipPath
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
    NSString *LibDirectory = [paths objectAtIndex:0];
    NSString *dir = [LibDirectory stringByAppendingPathComponent:@"Caches/OOMTmp"];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:dir])
    {
        [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    return [dir stringByAppendingPathComponent:@"OOMData.zip"];
}


-(void)setMaxStackDepth:(size_t)depth
{
    if(depth > 0) max_stack_depth = depth;
}

-(void)setNeedSystemStack:(BOOL)isNeedSys
{
    needSysStack = isNeedSys;
}

-(void)setNeedStacksWithoutAppStack:(BOOL)isNeedStackWithoutAppStack
{
    needStackWithoutAppStack = isNeedStackWithoutAppStack;
}

-(NSString *)currentStackLogDir;
{
    return currentDir;
}

- (void)setStatisticsInfoBlock:(StatisticsInfoBlock)block
{
    [[OOMStatisticsInfoCenter getInstance] setStatisticsInfoBlock:block];
}

-(void)dealloc
{
    if(normal_stack_logger != NULL){
        munmap(normal_stack_logger->mmap_ptr , normal_stack_logger->mmap_size);
        normal_stack_logger->memory_zone->free(normal_stack_logger->memory_zone,normal_stack_logger);
    }

    self.logPrintBlock = nil;
    self.chunkMallocBlock = nil;
    [super dealloc];
}

- (void)setPerformanceDataDelegate:(id<QQOOMPerformanceDataDelegate>)delegate
{
    [[QQLeakDataUploadCenter defaultCenter] setPerformanceDataDelegate:delegate];
}

- (void)setFileDataDelegate:(id<QQOOMFileDataDelegate>)delegate
{
    [[QQLeakFileUploadCenter defaultCenter] setFileDataDelegate:delegate];
}

@end

