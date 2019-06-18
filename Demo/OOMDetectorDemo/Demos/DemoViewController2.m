//
//  DemoViewController2.m
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

#import "DemoViewController2.h"

@import libOOMDetector;

#define DemoCode2 \
int size = 51 * 1024 * 1024;\
char *info = malloc(size);\
memset(info, 1, size);\
dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{\
free(info);\
});

@interface DemoViewController2 ()

@property (nonatomic, strong) UIView *testView;
@property (nonatomic, assign) int flag;

@end

@implementation DemoViewController2

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.isOOMDemo = YES;
    
    [self.checkButton setTitle:@"内存监测" forState:UIControlStateNormal];
}

- (NSString *)demoDescriptionString
{
    return @"1.点击<运行Demo代码>按钮运行示例代码；\n2.可通过悬浮球观察实时内存波动；\n3.大内存分配的堆栈信息会自动打印到页面下方的文本框内";
}

- (void)onReceiveChunkMallocNoti:(NSNotification *)noti
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.resultLabel setText:noti.object];
        [self.view setNeedsLayout];
    });
}

- (void)runDemoCode
{
    int size = 51 * 1024 * 1024;
    char *info = malloc(size);
    memset(info, 1, size);
//    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{\
//        free(info);
//    });
}

- (NSString *)demoCodeText
{
    
    return [self formatDemoString:TONSSTRING(DemoCode2)];
}

@end
