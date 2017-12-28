//
//  DemoViewController3.m
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

#import "DemoViewController3.h"
#import "MyOOMDataManager.h"

@import libOOMDetector;


#define DemoCode3 \
int i = 0;\
while (i < 3000) {\
    [self.arr addObject:[[NSObject alloc] init]];\
    ++i;\
}\

@interface DemoViewController3 ()

@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, strong) NSMutableArray *arr;

@end

@implementation DemoViewController3

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.isOOMDemo = YES;
    self.resultLabel.hidden = YES;
    self.arr = [NSMutableArray new];
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
    
    [self.timer invalidate];
    self.timer = nil;
    
    [self.arr removeAllObjects];
    self.arr = nil;
}

- (NSString *)demoDescriptionString
{
    return [NSString stringWithFormat:@"1.点击<运行Demo代码>按钮启动timer重复运行示例代码；\n2.内存增长到一定程度之后系统会杀掉当前进程；\n3.可以在目录%@查看相关log", [[OOMDetector getInstance] currentStackLogDir]];
}

- (void)runDemoCode
{
    if (!self.timer) {
        self.timer = [NSTimer scheduledTimerWithTimeInterval:0.01 target:self selector:@selector(test) userInfo:nil repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
    }
}

- (void)test
{
    DemoCode3
}

- (NSString *)demoCodeText
{
    return [self formatDemoString:TONSSTRING(DemoCode3)];
}


@end
