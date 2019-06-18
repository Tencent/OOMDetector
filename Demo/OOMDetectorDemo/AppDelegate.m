//
//  AppDelegate.m
//  QQLeakDemo
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

#import "AppDelegate.h"
#import "MyOOMDataManager.h"
#import "DemoListViewController.h"
#import <objc/runtime.h>
#import <sys/mman.h>
#import <mach/mach.h>
#import <libOOMDetector/FOOMMonitor.h>

#define USE_VM_LOGGER

#ifdef USE_VM_LOGGER
typedef void (malloc_logger_t)(uint32_t type, uintptr_t arg1, uintptr_t arg2, uintptr_t arg3, uintptr_t result, uint32_t num_hot_frames_to_skip);

extern malloc_logger_t* __syscall_logger;
#endif

static void oom_log_callback(char *info)
{
    NSLog(@"%s",info);
}

@import libOOMDetector;

NSString *const kChunkMallocNoti = @"kChunkMallocNoti";

@interface AppDelegate ()

@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    [self setupWindow];
    [[OOMDetector getInstance] registerLogCallback:oom_log_callback];
    [self setupFOOMMonitor];
    [self setupOOMDetector];
    return YES;
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    [[FOOMMonitor getInstance] appWillTerminate];
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    [[FOOMMonitor getInstance] appDidEnterBackground];
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    [[FOOMMonitor getInstance] appWillEnterForground];
}

- (void)applicationDidCrashed
{
    //crash 捕获组件的回调
    [[FOOMMonitor getInstance] appDidCrashed];
}

- (void)applicationDetectedDeadlock
{
    //检测到死锁，可以使用blue组件捕获
    //[[QQBlueFrameMonitor getInstance] startDeadLockMonitor:^(double cost, NSArray *stacks) {
//    [[FOOMMonitor getInstance] appDetectDeadLock:stacks];
//}];
    [[FOOMMonitor getInstance] appDetectDeadLock:nil];
}

- (void)applicationResumeFromDeadlock
{
    //从死锁恢复
    [[FOOMMonitor getInstance] appResumeFromDeadLock];
}

- (void)setupWindow
{
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    DemoListViewController *demoVC = [DemoListViewController new];
    self.window.rootViewController = [[UINavigationController alloc] initWithRootViewController:demoVC];
    [self.window makeKeyAndVisible];
}

- (void)setupFOOMMonitor
{
    [[FOOMMonitor getInstance] setAppVersion:@"OOMDetector_demo"];
    //设置爆内存监控，爆内存监控用于监控App前台爆内存和卡死，这个可以全量开启
    [[FOOMMonitor getInstance] start];
}

- (void)setupOOMDetector
{
    OOMDetector *detector = [OOMDetector getInstance];
    [detector setupWithDefaultConfig];
    
    
/*********************下面的几项可以根据自己的实际需要选择性设置******************/
    
    // 设置捕获堆栈数据、内存log代理，在出现单次大块内存分配、检查到内存泄漏且时、调用uploadAllStack方法时会触发此回调
    [detector setFileDataDelegate:[MyOOMDataManager getInstance]];
//
//    // 设置app内存触顶监控数据代理，在调用startMaxMemoryStatistic:开启内存触顶监控后会触发此回调，返回前一次app运行时单次生命周期内的最大物理内存数据
    [detector setPerformanceDataDelegate:[MyOOMDataManager getInstance]];
//
//    // 单次大块内存分配监控
    [detector startSingleChunkMallocDetector:50 * 1024 * 1024 callback:^(size_t bytes, NSString *stack) {
        [[NSNotificationCenter defaultCenter] postNotificationName:kChunkMallocNoti object:stack];
    }];

    // 开启内存泄漏监控，目前只可检测真机运行时的内存泄漏，模拟器暂不支持,这个功能占用的内存较大，建议只在测试阶段使用
 //   [detector setupLeakChecker];

    // 开启MallocStackMonitor用以监控通过malloc方式分配的内存,会增加8%左右的cpu开销和10Mb内存,所以建议抽样开启
    [detector startMallocStackMonitor:30 * 1024 * 1024 logUUID:[[FOOMMonitor getInstance] getLogUUID]];
    //30K以下堆栈按10%抽样监控
//    OOMDetector *oomdetector = [OOMDetector getInstance];
//    [oomdetector setMallocSampleFactor:10];
//    [oomdetector setMallocNoSampleThreshold:30*1024];
//    // 开启VMStackMonitor用以监控非直接通过malloc方式分配的内存
//    // 因为startVMStackMonitor:方法用到了私有API __syscall_logger会带来app store审核不通过的风险，此方法默认只在DEBUG模式下生效，如果
//    // 需要在RELEASE模式下也可用，请打开USE_VM_LOGGER_FORCEDLY宏，但是切记在提交appstore前将此宏关闭，否则可能会审核不通过
//    [detector setVMLogger:(void**)&__syscall_logger];
//    [detector startVMStackMonitor:30 * 1024 * 1024 logUUID:[[FOOMMonitor getInstance] getLogUUID]];

 /*************************************************************************/
    
}

-(void)testmmap
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
    NSString *LibDirectory = [paths objectAtIndex:0];
    NSString *path = [LibDirectory stringByAppendingPathComponent:@"test.log"];
    FILE *fp = fopen ( [path fileSystemRepresentation] , "wb+" ) ;
    char *ptr = (char *)mmap(0, 50*1024*1024, PROT_WRITE | PROT_READ, (MAP_FILE|MAP_SHARED), fileno(fp), 0);
    munmap(ptr,50*1024*1024);
}

-(void)performanceData:(NSDictionary *)data completionHandler:(void (^)(BOOL))completionHandler
{
    //上报
}

/** 在出现单次大块内存分配、检查到内存泄漏且时、调用uploadAllStack方法时触发回调 */
-(void)fileData:(id)data extra:(NSDictionary<NSString*,NSString*> *)extra type:(QQStackReportType)type completionHandler:(void (^)(BOOL))completionHandler
{
    //上报
}

@end
