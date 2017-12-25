//
//  DemoViewController1.m
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

#import "DemoViewController1.h"

#define DemoCode1 \
int i = 0;\
while (i < 1000) {\
    NSObject *obj = [[[NSObject alloc] init] retain];\
    [obj class];\
    ++i;\
}

@interface DemoViewController1 ()

@end

@implementation DemoViewController1

- (NSString *)demoDescriptionString
{
    return @"1.点击<运行Demo代码>按钮运行示例代码；\n2.可通过悬浮球观察实时内存波动；\n3.可点击<检查是否有内存泄漏>按钮检查内存泄漏";
}

- (void)checkLeak
{
    // 检查内存泄漏时会调用这里的代码，具体实现可以跳转到父类查看
    [super checkLeak];
}

- (void)runDemoCode
{
    DemoCode1
}

- (NSString *)demoCodeText
{
    return [self formatDemoString:TONSSTRING(DemoCode1)];
}

@end
