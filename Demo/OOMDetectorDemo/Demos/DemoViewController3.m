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


@implementation DemoViewController3

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.isOOMDemo = YES;
    self.resultLabel.hidden = YES;
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
}

- (NSString *)demoDescriptionString
{
    return [NSString stringWithFormat:@"1.点击<运行Demo代码>按钮启动timer重复运行示例代码；\n2.内存增长到一定程度之后系统会杀掉当前进程；\n3.可以在目录%@查看相关log", [[OOMDetector getInstance] currentStackLogDir]];
}

- (void)runDemoCode
{
    [self test];
}

- (void)test
{
    while (1) {
        NSObject *obj = [[[NSObject alloc] init] retain];
        [obj class];
    }
}

- (NSString *)demoCodeText
{
    return [self formatDemoString:TONSSTRING(DemoCode3)];
}


@end
