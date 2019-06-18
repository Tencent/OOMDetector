//
//  FOOMMonitor.mm
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


#import "FOOMMonitor.h"
#import "HighSpeedLogger.h"
#import <malloc/malloc.h>
#import "fishhook.h"
#import "QQLeakFileUploadCenter.h"
#import "OOMDetector.h"
#import "OOMDetectorLogger.h"
#import <mach/mach.h>
#import "NSObject+FOOMSwizzle.h"

#if !__has_feature(objc_arc)
#error This file must be compiled with ARC. Use -fobjc-arc flag.
#endif

//#undef DEBUG
#define no_crash 0
#define normal_crash 1
#define deadlock_crash 2
#define foom_crash 3
#define foom_mmap_size 160*1024

static FOOMMonitor* monitor;

static void (*_orig_exit)(int);
static void (*orig_exit)(int);

void my_exit(int value)
{
    [[FOOMMonitor getInstance] appExit];
    orig_exit(value);
}

void _my_exit(int value)
{
    [[FOOMMonitor getInstance] appExit];
    _orig_exit(value);
}


typedef enum{
    APPENTERBACKGROUND,
    APPENTERFORGROUND,
    APPDIDTERMINATE
}App_State;

@interface UIViewController(FOOM)

- (void)foom_viewDidAppear:(BOOL)animated;

@end

@implementation UIViewController(FOOM)

- (void)foom_viewDidAppear:(BOOL)animated
{
    [self foom_viewDidAppear:animated];
    NSString *name = NSStringFromClass([self class]);
    if(
#ifdef build_for_QQ
       ![name hasPrefix:@"QUI"] &&
#endif
       ![name hasPrefix:@"_"] && ![name hasPrefix:@"UI"] && ![self isKindOfClass:[UINavigationController class]])
    {
        [[FOOMMonitor getInstance] updateStage:name];
    }
}

@end

@interface FOOMMonitor()
{
    NSString *_uuid;
    NSThread *_thread;
    NSTimer *_timer;
    NSUInteger _memWarningTimes;
    NSUInteger _residentMemSize;
    App_State _appState;
    HighSpeedLogger *_foomLogger;
    BOOL _isCrashed;
    BOOL _isDeadLock;
    BOOL _isExit;
    NSDictionary *_deadLockStack;
    NSString *_systemVersion;
    NSString *_appVersion;
    NSTimeInterval _ocurTime;
    NSTimeInterval _startTime;
    NSRecursiveLock *_logLock;
    NSString *_currentLogPath;
    BOOL _isDetectorStarted;
    BOOL _isOOMDetectorOpen;
    NSString *_crash_stage;
}

@end

@implementation FOOMMonitor

+(FOOMMonitor *)getInstance
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        monitor = [FOOMMonitor new];
    });
    return monitor;
}

-(id)init{
    if(self = [super init]){
        _uuid = [self uuid];
        _logLock = [NSRecursiveLock new];
        _thread = [[NSThread alloc] initWithTarget:self selector:@selector(threadMain) object:nil];
        [_thread setName:@"foomMonitor"];
        _timer = [NSTimer timerWithTimeInterval:1 target:self selector:@selector(updateMemory) userInfo:nil repeats:YES];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appReceiveMemoryWarning) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
        [_thread start];
    }
    return self;
}

-(void)createmmapLogger
{
    [_logLock lock];
    [self hookExitAndAbort];
    [self swizzleMethods];
    NSString *dir = [self foomMemoryDir];
    _systemVersion = [[NSProcessInfo processInfo] operatingSystemVersionString];
    _currentLogPath = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.oom",_uuid]];
    _foomLogger = new HighSpeedLogger(malloc_default_zone(), _currentLogPath, foom_mmap_size);
    _crash_stage = @" ";
    int32_t length = 0;
    if(_foomLogger && _foomLogger->isValid()){
        _foomLogger->memcpyLogger((const char *)&length, 4);
    }
    [self updateFoomData];
    [self uploadLastData];
    [_logLock unlock];
}

-(NSString *)uuid
{
    CFUUIDRef uuid = CFUUIDCreate(kCFAllocatorDefault);
    CFStringRef strUuid = CFUUIDCreateString(kCFAllocatorDefault,uuid);
    NSString * str = [NSString stringWithString:(__bridge NSString *)strUuid];
    CFRelease(strUuid);
    CFRelease(uuid);
    return str;
}

-(NSString *)getLogUUID
{
    return _uuid;
}

-(NSString *)getLogPath {
    return _currentLogPath;
}

-(void)start
{
    _isDetectorStarted = YES;
    if([UIApplication sharedApplication].applicationState == UIApplicationStateBackground)
    {
        _appState = APPENTERBACKGROUND;
    }
    else {
        _appState = APPENTERFORGROUND;
    }
    _isCrashed = NO;
    _isExit = NO;
    _isDeadLock = NO;
    _ocurTime = [[NSDate date] timeIntervalSince1970];
    _startTime = _ocurTime;
    [self performSelector:@selector(createmmapLogger) onThread:_thread withObject:nil waitUntilDone:NO];
}

-(void)hookExitAndAbort
{
    rebind_symbols((struct rebinding[2]){{"_exit", (void *)_my_exit, (void **)&_orig_exit}, {"exit", (void *)my_exit, (void **)&orig_exit}}, 2);
}

-(void)swizzleMethods
{
    [UIViewController swizzleMethod:@selector(viewDidAppear:) withMethod:@selector(foom_viewDidAppear:)];
}


-(void)threadMain
{
    [[NSRunLoop currentRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
    [[NSRunLoop currentRunLoop] run];
    [_timer fire];
}

-(void)updateMemory
{
    [_logLock lock];
    if(_appState == APPENTERFORGROUND){
        NSUInteger memSize = (NSUInteger)[self appResidentMemory];
        if(_isDeadLock){
            if(abs((int)(_residentMemSize - memSize)) < 5){
                //卡死状态下内存无明显变化就不update了，避免CPU过高发热
                [_logLock unlock];
                return ;
            }
        }
        _residentMemSize = memSize;
    }
    _ocurTime = [[NSDate date] timeIntervalSince1970];
    [self updateFoomData];
    [_logLock unlock];
}

-(void)updateFoomData{
    if(_foomLogger && _foomLogger->isValid()){
        NSString* residentMemory = [NSString stringWithFormat:@"%lu", (unsigned long)_residentMemSize];
        NSDictionary *foomDict = [NSDictionary dictionaryWithObjectsAndKeys:residentMemory,@"lastMemory",[NSNumber numberWithUnsignedLongLong:_memWarningTimes],@"memWarning",_uuid,@"uuid",_systemVersion,@"systemVersion",_appVersion,@"appVersion",[NSNumber numberWithInt:(int)_appState],@"appState",[NSNumber numberWithBool:_isCrashed],@"isCrashed",[NSNumber numberWithBool:_isDeadLock],@"isDeadLock",_deadLockStack ? _deadLockStack : @"",@"deadlockStack",[NSNumber numberWithBool:_isExit],@"isExit",[NSNumber numberWithDouble:_ocurTime],@"ocurTime",[NSNumber numberWithDouble:_startTime],@"startTime",[NSNumber numberWithBool:_isOOMDetectorOpen],@"isOOMDetectorOpen",_crash_stage,@"crash_stage",nil];
        NSData *foomData = [NSKeyedArchiver archivedDataWithRootObject:foomDict];
        if(foomData && [foomData length] > 0){
            _foomLogger->cleanLogger();
            int32_t length = (int32_t)[foomData length];
            if(!_foomLogger->memcpyLogger((const char *)&length, 4)){
                [[NSFileManager defaultManager] removeItemAtPath:_currentLogPath error:nil];
                delete _foomLogger;
                _foomLogger = NULL;
            }
            else {
                if(!_foomLogger->memcpyLogger((const char *)[foomData bytes],[foomData length])){
                    [[NSFileManager defaultManager] removeItemAtPath:_currentLogPath error:nil];
                    delete _foomLogger;
                    _foomLogger = NULL;
                }
            }
        }
    }
}

-(void)uploadLastData
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *foomDir = [self foomMemoryDir];
        NSFileManager *fm = [NSFileManager defaultManager];
        NSArray *paths = [fm contentsOfDirectoryAtPath:foomDir error:nil];
        for(NSString *path in paths)
        {
            if([path hasSuffix:@".oom"]){
                NSString *fullPath = [foomDir stringByAppendingPathComponent:path];
                if([fullPath isEqualToString:_currentLogPath]){
                    continue;
                }
                NSData *metaData = [NSData dataWithContentsOfFile:fullPath];
                if(metaData.length <= 4){
                    [fm removeItemAtPath:fullPath error:nil];
                    continue;
                }
                int32_t length = *(int32_t *)metaData.bytes;
                if(length <= 0 || length > [metaData length] - 4){
                    [fm removeItemAtPath:fullPath error:nil];
                }
                else {
                    NSData *foomData = [NSData dataWithBytes:(const char *)metaData.bytes + 4 length:(NSUInteger)length];
                    NSDictionary *foomDict = nil;
                    @try {
                        foomDict = [NSKeyedUnarchiver unarchiveObjectWithData:foomData];
                    }
                    @catch (NSException *e) {
                        foomDict = nil;
                        OOM_Log("unarchive FOOMData failed,length:%d,exception:%s!",length,[[e description] UTF8String]);
                    }
                    @finally{
                        if(foomDict && [foomDict isKindOfClass:[NSDictionary class]]){
                            NSString *uin = [foomDict objectForKey:@"uin"];
                            if(uin == nil || uin.length <= 0){
                                uin = @"10000";
                            }
                            NSDictionary *uploadData = [self parseFoomData:foomDict];
                            NSDictionary *aggregatedData = [NSDictionary dictionaryWithObjectsAndKeys:[NSArray arrayWithObject:uploadData],@"parts",nil];
                            NSString *uuid = [foomDict objectForKey:@"uuid"];
                            NSDictionary *basicParameter = [NSDictionary dictionaryWithObjectsAndKeys:uin,@"uin",uuid,@"client_identify",[foomDict objectForKey:@"ocurTime"],@"occur_time",nil];
                            [[QQLeakFileUploadCenter defaultCenter] fileData:aggregatedData extra:basicParameter type:QQStackReportTypeOOMLog completionHandler:nil];
                        }
                        [fm removeItemAtPath:fullPath error:nil];
                    }
                }
            }
        }
        [[OOMDetector getInstance] clearOOMLog];
    });
}

-(NSDictionary *)parseFoomData:(NSDictionary *)foomDict
{
    NSMutableDictionary *result = [NSMutableDictionary new];
    [result setObject:@"sigkill" forKey:@"category"];
    NSNumber *startTime = [foomDict objectForKey:@"startTime"];
    if(startTime){
        [result setObject:startTime forKey:@"s"];
    }
    [result setObject:[foomDict objectForKey:@"ocurTime"] forKey:@"e"];
    [result setObject:[foomDict objectForKey:@"lastMemory"] forKey:@"mem_used"];
    [result setObject:[foomDict objectForKey:@"memWarning"] forKey:@"mem_warning_cnt"];
    NSString *crash_stage = [foomDict objectForKey:@"crash_stage"];
    if(crash_stage){
        [result setObject:crash_stage forKey:@"crash_stage"];
    }
    NSNumber *isOOMDetectorOpen_num = [foomDict objectForKey:@"isOOMDetectorOpen"];
    if(isOOMDetectorOpen_num){
        [result setObject:isOOMDetectorOpen_num forKey:@"enable_oom"];
    }
    else {
        [result setObject:@NO forKey:@"enable_oom"];
    }
    App_State appState = (App_State)[[foomDict objectForKey:@"appState"] intValue];
    BOOL isCrashed = [[foomDict objectForKey:@"isCrashed"] boolValue];
    if(appState == APPENTERFORGROUND){
        BOOL isExit = [[foomDict objectForKey:@"isExit"] boolValue];
        BOOL isDeadLock = [[foomDict objectForKey:@"isDeadLock"] boolValue];
        NSString *lastSysVersion = [foomDict objectForKey:@"systemVersion"];
        NSString *lastAppVersion = [foomDict objectForKey:@"appVersion"];
        if(!isCrashed && !isExit && [_systemVersion isEqualToString:lastSysVersion] && [_appVersion isEqualToString:lastAppVersion]){
            if(isDeadLock){
                OOM_Log("The app ocurred deadlock lastTime,detail info:%s",[[foomDict description] UTF8String]);
                [result setObject:@deadlock_crash forKey:@"crash_type"];
                NSDictionary *stack = [foomDict objectForKey:@"deadlockStack"];
                if(stack && stack.count > 0){
                    [result setObject:stack forKey:@"stack_deadlock"];
                    OOM_Log("The app deadlock stack:%s",[[stack description] UTF8String]);
                }
            }
            else {
                OOM_Log("The app ocurred foom lastTime,detail info:%s",[[foomDict description] UTF8String]);
                [result setObject:@foom_crash forKey:@"crash_type"];
                NSString *uuid = [foomDict objectForKey:@"uuid"];
                NSArray *oomStack = [[OOMDetector getInstance] getOOMDataByUUID:uuid];
                if(oomStack && oomStack.count > 0)
                {
                    NSData *oomData = [NSJSONSerialization dataWithJSONObject:oomStack options:0 error:nil];
                    if(oomData.length > 0){
//                        NSString *stackStr = [NSString stringWithUTF8String:(const char *)oomData.bytes];
                        OOM_Log("The app foom stack:%s",[[oomStack description] UTF8String]);
                    }
                    [result setObject:[self getAPMOOMStack:oomStack] forKey:@"stack_oom"];
                }
            }
            return result;
        }
    }
    if(isCrashed){
        OOM_Log("The app ocurred rqd crash lastTime,detail info:%s",[[foomDict description] UTF8String]);
        [result setObject:@normal_crash forKey:@"crash_type"];
    }
    else {
        OOM_Log("The app ocurred no crash lastTime,detail info:%s!",[[foomDict description] UTF8String]);
        [result setObject:@no_crash forKey:@"crash_type"];
    }
    [result setObject:@"" forKey:@"stack_deadlock"];
    [result setObject:@"" forKey:@"stack_oom"];
    return result;
}

-(NSDictionary *)getAPMOOMStack:(NSArray *)stack
{
    NSDictionary *slice = [NSDictionary dictionaryWithObjectsAndKeys:stack,@"threads",nil];
    NSArray *slicesArray = [NSArray arrayWithObject:slice];
    NSDictionary *result = [NSDictionary dictionaryWithObjectsAndKeys:slicesArray,@"time_slices",nil];
    return result;
}

-(NSString*)foomMemoryDir
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
    NSString *LibDirectory = [paths objectAtIndex:0];
    NSString *path = [LibDirectory stringByAppendingPathComponent:@"/Foom"];
    if(![[NSFileManager defaultManager] fileExistsAtPath:path]){
        [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    }
    return path;
}

- (double)appResidentMemory
{
    mach_task_basic_info_data_t taskInfo;
    unsigned infoCount = sizeof(taskInfo);
    kern_return_t kernReturn = task_info(mach_task_self(),
                                         MACH_TASK_BASIC_INFO,
                                         (task_info_t)&taskInfo,
                                         &infoCount);
    
    if (kernReturn != KERN_SUCCESS
        ) {
        return 0;
    }
    return taskInfo.resident_size / 1024.0 / 1024.0;
}

-(void)setOOMDetectorOpen:(BOOL)isOpen
{
    [_logLock lock];
    _isOOMDetectorOpen = isOpen;
    [self updateFoomData];
    [_logLock unlock];
}

-(void)updateStage:(NSString *)stage
{
    [self performSelector:@selector(_updateStage:) onThread:_thread withObject:stage waitUntilDone:NO];
}

-(void)_updateStage:(NSString *)stage
{
    [_logLock lock];
    _crash_stage = stage;
    [self updateFoomData];
    [_logLock unlock];
}

-(void)appReceiveMemoryWarning
{
    [self performSelector:@selector(_appReceiveMemoryWarning) onThread:_thread withObject:nil waitUntilDone:NO];
}

-(void)_appReceiveMemoryWarning
{
    [_logLock lock];
    _memWarningTimes++;
    [self updateFoomData];
    [_logLock unlock];
}

-(void)appDidEnterBackground
{
    [self performSelector:@selector(_appDidEnterBackground) onThread:_thread withObject:nil waitUntilDone:NO];
}

-(void)_appDidEnterBackground
{
    [_logLock lock];
    _appState = APPENTERBACKGROUND;
    [self updateFoomData];
    [_logLock unlock];
}

-(void)appWillEnterForground
{
    [self performSelector:@selector(_appWillEnterForground) onThread:_thread withObject:nil waitUntilDone:NO];
}

-(void)_appWillEnterForground
{
    [_logLock lock];
    if(_appState != APPDIDTERMINATE)
    {
        _appState = APPENTERFORGROUND;
        [self updateFoomData];
    }
    [_logLock unlock];
}

-(void)appWillTerminate
{
    [self _appWillTerminate];
}

-(void)_appWillTerminate
{
    [_logLock lock];
    _appState = APPDIDTERMINATE;
    [self updateFoomData];
    [_logLock unlock];
}

-(void)appDidCrashed
{
    [_logLock lock];
    _isCrashed = YES;
    [self updateFoomData];
    [_logLock unlock];
}


-(void)appExit
{
    [_logLock lock];
    _isExit = YES;
    [self updateFoomData];
    [_logLock unlock];
}

-(void)appDetectDeadLock:(NSDictionary *)stack
{
    [_logLock lock];
    _isDeadLock = YES;
    _deadLockStack = stack;
//    _deadLockStack = stack;
    [self updateFoomData];
    [_logLock unlock];
}

-(void)appResumeFromDeadLock
{
    [_logLock lock];
    _isDeadLock = NO;
    _deadLockStack = nil;
    [self updateFoomData];
    [_logLock unlock];
}

-(void)setAppVersion:(NSString *)appVersion
{
    [_logLock lock];
    _appVersion = appVersion;
    [_logLock unlock];
}

@end
