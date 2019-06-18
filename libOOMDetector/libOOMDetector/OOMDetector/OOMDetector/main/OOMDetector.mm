//
//  OOMDetector.mm
//  libOOMDetector
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
#import "CommonMallocLogger.h"
#import "RapidCRC.h"
#import "CStackHighSpeedLogger.h"
#import "CStackHelper.h"
#import "COOMDetector.h"

#if __has_feature(objc_arc)
#error This file must be compiled without ARC. Use -fno-objc-arc flag.
#endif

#ifdef build_for_QQ
malloc_zone_t *nano_gurd_zone;
#endif
extern malloc_zone_t *global_memory_zone;
extern logCallback oom_logger;

//static
static OOMDetector *catcher;
static size_t normal_size = 512*1024;
COOMDetector* global_oomdetector;

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
    QQLeakChecker *_leakChecker;
    NSString *_currentDir;
    NSString *_normal_vm_path;
    BOOL _enableOOMMonitor;
    BOOL _enableChunkMonitor;
    BOOL _enableVMMonitor;
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
        global_oomdetector = new COOMDetector();
        if(global_memory_zone == nil){
            global_memory_zone = malloc_create_zone(0, 0);
            malloc_set_zone_name(global_memory_zone, "OOMDetector");
        }
    }
    return self;
}

-(void)registerLogCallback:(logCallback)logger
{
    oom_logger = logger;
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

- (void)setupMemoryIndicatorFrame:(CGRect)frame
{
    CGFloat wh = MAX(frame.size.width, frame.size.height);
    CGRect newFrame = frame;
    newFrame.size.width = wh;
    newFrame.size.height = wh;
    [[OOMStatisticsInfoCenter getInstance] setupMemoryIndicatorFrame:newFrame];
}

- (void)setupLeakChecker
{
    QQLeakChecker *leakChecker = [QQLeakChecker getInstance];
    _leakChecker = leakChecker;
    
    //设置堆栈最大长度为25，超过25将被截断
    [leakChecker setMaxStackDepth:25];
    [leakChecker setNeedSystemStack:YES];
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

-(void)startMaxMemoryStatistic:(double)overFlowLimit
{

    [[OOMStatisticsInfoCenter getInstance] startMemoryOverFlowMonitor:overFlowLimit];

}


-(BOOL)startMallocStackMonitor:(size_t)threshholdInBytes logUUID:(NSString *)uuid
{
    if(!_enableOOMMonitor){
        _currentDir = [[[self OOMDataPath] stringByAppendingPathComponent:uuid] retain];
        _normal_path = [[_currentDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.mmap",uuid]] retain];
        init_crc_table_for_oom();
        NSFileManager *fileManager = [NSFileManager defaultManager];
        if (![fileManager fileExistsAtPath:_currentDir]) {
            [fileManager createDirectoryAtPath:_currentDir withIntermediateDirectories:YES attributes:nil error:nil];
        }
        if (![fileManager fileExistsAtPath:_normal_path]) {
            [fileManager createFileAtPath:_normal_path contents:nil attributes:nil];
        }
        global_oomdetector->initLogger(global_memory_zone, _normal_path, normal_size);
        _enableOOMMonitor = global_oomdetector->startMallocStackMonitor(threshholdInBytes);
        if(_enableOOMMonitor){
            malloc_logger = (malloc_logger_t *)common_stack_logger;
        }
    }

    return _enableOOMMonitor;
}


-(void)stopMallocStackMonitor
{
    if(_enableOOMMonitor){
        malloc_logger = NULL;
        global_oomdetector->stopMallocStackMonitor();
    }

}

-(void)setMallocSampleFactor:(uint32_t)factor
{
    global_oomdetector->sampleFactor = factor;
}

-(void)setMallocNoSampleThreshold:(uint32_t)threshhold
{
    global_oomdetector->sampleThreshold = threshhold;
}

-(void)setNeedCleanStack:(BOOL)isNeed maxStackNum:(size_t)maxNum minimumStackSize:(size_t)mininumSize
{
    if(_enableOOMMonitor){
        global_oomdetector->needCleanStackCache = isNeed;
        global_oomdetector->cache_clean_num = maxNum;
        global_oomdetector->cache_clean_threshold = mininumSize;
    }
}

-(void)setVMLogger:(void**)logger
{
    global_oomdetector->vm_sys_logger = (malloc_logger_t**)logger;
}

-(BOOL)startVMStackMonitor:(size_t)threshHoldInbytes logUUID:(NSString *)uuid
{
    if(!_enableVMMonitor){
        _normal_vm_path = [[_currentDir stringByAppendingPathComponent:[NSString stringWithFormat:@"vm_%@.mmap",uuid]] retain];
        NSFileManager *fileManager = [NSFileManager defaultManager];
        if (![fileManager fileExistsAtPath:_currentDir]) {
            [fileManager createDirectoryAtPath:_currentDir withIntermediateDirectories:YES attributes:nil error:nil];
        }
        if (![fileManager fileExistsAtPath:_normal_vm_path]) {
            [fileManager createFileAtPath:_normal_vm_path contents:nil attributes:nil];
        }
        global_oomdetector->initLogger(global_memory_zone, _normal_vm_path, normal_size);
        _enableVMMonitor = global_oomdetector->startVMStackMonitor(threshHoldInbytes);
        if(_enableVMMonitor){
            if(global_oomdetector->vm_sys_logger != NULL)
            {
                *(global_oomdetector->vm_sys_logger) = oom_vm_logger;
            }
        }
    }
    return YES;
}

-(void)stopVMStackMonitor
{
    if(_enableVMMonitor){
        if(global_oomdetector->vm_sys_logger != NULL)
        {
            *(global_oomdetector->vm_sys_logger) = NULL;
        }
        global_oomdetector->stopVMStackMonitor();
        _enableVMMonitor = NO;
    }
}

-(BOOL)startSingleChunkMallocDetector:(size_t)threshholdInBytes callback:(ChunkMallocBlock)callback
{
    if(!_enableChunkMonitor){
        _enableChunkMonitor = YES;
        if(_enableChunkMonitor){
            global_oomdetector->startSingleChunkMallocDetector(threshholdInBytes,callback);
            self.chunkMallocBlock = callback;
            malloc_logger = (malloc_logger_t *)common_stack_logger;
        }
    }
    return _enableChunkMonitor;
}

-(void)stopSingleChunkMallocDetector
{
    if(!_enableOOMMonitor && _enableChunkMonitor){
        global_oomdetector->stopSingleChunkMallocDetector();
        malloc_logger = NULL;
    }
    _enableChunkMonitor = NO;
}

-(NSArray *)getOOMDataByUUID:(NSString *)uuid
{
    NSArray *images = [self getOOMImageDataByUUID:uuid];
    NSMutableArray *stacks = [[[NSMutableArray alloc] init] autorelease];
    if(images){
        NSData *mallocData = [self getOOMMallocDataByUUID:uuid];
        NSData *vmData = [self getOOMVMDataByUUID:uuid];
        if(mallocData.length > 0){
            NSArray *mallocStack = [self parseOOMData:mallocData images:images isVM:NO];
            [stacks addObjectsFromArray:mallocStack];
        }
        if(vmData.length > 0){
            NSArray *vmStack = [self parseOOMData:vmData images:images isVM:YES];
            [stacks addObjectsFromArray:vmStack];
        }
    }
    [self removeOOMDataByUUID:uuid];
    return stacks;
}

-(NSArray *)parseOOMData:(NSData *)oomData images:(NSArray *)images isVM:(BOOL)isVM
{
    AppImages *app_images = CStackHelper::parseImages(images);
    cache_stack_t *mmap_ptr = (cache_stack_t *)oomData.bytes;
    size_t stack_num = oomData.length/sizeof(cache_stack_t);
    NSMutableArray *stacks = [[[NSMutableArray alloc] init] autorelease];
    if(oomData && oomData.length > 0 && app_images->size > 0)
    {
        for(size_t offset = 0; offset < stack_num;offset++)
        {
            cache_stack_t *cache_stack = mmap_ptr + offset;
            if(cache_stack->count > 0){
                NSMutableDictionary *stack = [[NSMutableDictionary new] autorelease];
                if(!isVM){
                    [stack setObject:@"malloc" forKey:@"stack_type"];
                }
                else {
                    [stack setObject:@"vm" forKey:@"stack_type"];
                }
                [stack setObject:[NSNumber numberWithInteger:(NSInteger)cache_stack->size] forKey:@"malloc_size"];
                [stack setObject:[NSNumber numberWithInteger:(NSInteger)cache_stack->count] forKey:@"malloc_count"];
                NSMutableArray *calls = [[NSMutableArray new] autorelease];
                for(size_t j = 0; j < cache_stack->stack_depth; j++){
                    vm_address_t addr = (vm_address_t)cache_stack->stacks[j];
                    segImageInfo segImage;
                    if(CStackHelper::parseAddrOfImages(app_images,addr, &segImage)){
                        [calls addObject:[NSString stringWithFormat:@"%lu %s 0x%lx 0x%lx",j,(segImage.name != NULL) ? segImage.name : "unknown",segImage.loadAddr,(long)addr]];
                    }
                }
                NSDictionary *frame = [NSDictionary dictionaryWithObjectsAndKeys:calls,@"calls",nil];
                [stack setObject:frame forKey:@"frame"];
                [stacks addObject:stack];
            }
        }
    }
    for (size_t i = 0; i < app_images->size; i++)
    {
        free(app_images->imageInfos[i]);
    }
    free(app_images->imageInfos);
    delete app_images;
    return stacks;
}
-(NSArray *)getOOMImageDataByUUID:(NSString *)uuid
{
    NSString *OOMDataPath = [[self OOMDataPath] stringByAppendingPathComponent:uuid];
    NSString *imagesDir = [OOMDataPath stringByAppendingPathComponent:@"app.images"];
    NSArray *imageData = [NSArray arrayWithContentsOfFile:imagesDir];
    if(imageData && [imageData isKindOfClass:[NSArray class]]){
        return imageData;
    }
    return nil;
}

-(NSData *)getOOMMallocDataByUUID:(NSString *)uuid
{
    NSString *OOMDataPath = [[self OOMDataPath] stringByAppendingPathComponent:uuid];
    NSString *mallocPath = [OOMDataPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.mmap",uuid]];
    NSData *rawData = [NSData dataWithContentsOfFile:mallocPath];
    if(rawData.length > 0){
        return rawData;
    }
    return nil;
}

-(NSData *)getOOMVMDataByUUID:(NSString *)uuid
{
    NSString *OOMDataPath = [[self OOMDataPath] stringByAppendingPathComponent:uuid];
    NSString *vmPath = [OOMDataPath stringByAppendingPathComponent:[NSString stringWithFormat:@"vm_%@.mmap",uuid]];
    NSData *rawData = [NSData dataWithContentsOfFile:vmPath];
    if(rawData.length > 0){
        return rawData;
    }
    return nil;
}


-(void)removeOOMDataByUUID:(NSString *)uuid
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *OOMDataPath = [[self OOMDataPath] stringByAppendingPathComponent:uuid];
    [fm removeItemAtPath:OOMDataPath error:nil];
}

-(void)clearOOMLog
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *OOMDataPath = [self OOMDataPath];
    NSArray *paths = [fm contentsOfDirectoryAtPath:OOMDataPath error:nil];
    for(NSString *path in paths){
        NSString *fullPath = [OOMDataPath stringByAppendingPathComponent:path];
        if(_currentDir == nil || ![fullPath isEqualToString:_currentDir]){
            [fm removeItemAtPath:fullPath error:nil];
        }
    }
}

-(NSString *)OOMDataPath
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
    NSString *LibDirectory = [paths objectAtIndex:0];
    return [LibDirectory stringByAppendingPathComponent:@"OOMDetector_New"];
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
    if(depth > 0) {
        global_oomdetector->max_stack_depth = depth;
    }
}


-(void)setNeedSystemStack:(BOOL)isNeedSys
{
    global_oomdetector->needSysStack = isNeedSys;
}

-(void)setNeedStacksWithoutAppStack:(BOOL)isNeedStackWithoutAppStack
{
    global_oomdetector->needStackWithoutAppStack = isNeedStackWithoutAppStack;
}

-(NSString *)currentStackLogDir;
{
    return _currentDir;
}

- (void)setStatisticsInfoBlock:(StatisticsInfoBlock)block
{
    [[OOMStatisticsInfoCenter getInstance] setStatisticsInfoBlock:block];
}

-(void)dealloc
{
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

-(double)getOccupyMemory
{
    if(global_memory_zone != NULL){
        malloc_statistics_t stats;
        malloc_zone_statistics(global_memory_zone, &stats);
        return stats.size_in_use/1024.0/1024.0;
    }
    else {
        return 0;
    }
}

@end

