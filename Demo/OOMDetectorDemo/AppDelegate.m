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

@import libOOMDetector;

NSString *const kChunkMallocNoti = @"kChunkMallocNoti";

@interface AppDelegate ()

@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    
    [self setupOOMDetector];
    [self setupWindow];
    
    return YES;
}

- (void)setupWindow
{
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    DemoListViewController *demoVC = [DemoListViewController new];
    self.window.rootViewController = [[UINavigationController alloc] initWithRootViewController:demoVC];
    [self.window makeKeyAndVisible];
}

- (void)setupOOMDetector
{
    OOMDetector *detector = [OOMDetector getInstance];
    [detector setupWithDefaultConfig];
    
    
/*********************下面的几项可以根据自己的实际需要选择性设置******************/
    
    // 设置捕获堆栈数据、内存log代理，在出现单次大块内存分配、检查到内存泄漏且时、调用uploadAllStack方法时会触发此回调
    [detector setFileDataDelegate:[MyOOMDataManager getInstance]];
    
    // 设置app内存触顶监控数据代理，在调用startMaxMemoryStatistic:开启内存触顶监控后会触发此回调，返回前一次app运行时单次生命周期内的最大物理内存数据
    [detector setPerformanceDataDelegate:[MyOOMDataManager getInstance]];
    
    // 单次大块内存分配监控
    [detector startSingleChunkMallocDetector:50 * 1024 * 1024 callback:^(size_t bytes, NSString *stack) {
        [[NSNotificationCenter defaultCenter] postNotificationName:kChunkMallocNoti object:stack];
    }];

    // 开启内存泄漏监控，目前只可检测真机运行时的内存泄漏，模拟器暂不支持
    [detector setupLeakChecker];

    // 开启MallocStackMonitor用以监控通过malloc方式分配的内存
    [detector startMallocStackMonitor:10 * 1024 * 1024 needAutoDumpWhenOverflow:YES dumpLimit:300 sampleInterval:0.1];
    
    // 开启VMStackMonitor用以监控非直接通过malloc方式分配的内存
    // 因为startVMStackMonitor:方法用到了私有API __syscall_logger会带来app store审核不通过的风险，此方法默认只在DEBUG模式下生效，如果
    // 需要在RELEASE模式下也可用，请打开USE_VM_LOGGER_FORCEDLY宏，但是切记在提交appstore前将此宏关闭，否则可能会审核不通过
    [detector startVMStackMonitor:10 * 1024 * 1024];
    
    // 调用该接口上报所有缓存的OOM相关log给通过setFileDataDelegate:方法设置的代理，建议在启动的时候调用
    [detector uploadAllStack];

 /*************************************************************************/
    
}

@end
