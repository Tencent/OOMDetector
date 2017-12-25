//
//  ViewController.h
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

#import <UIKit/UIKit.h>

#define TOSTRING(text) #text
#define TONSSTRING(text) @ TOSTRING(text)

#define STR1(R)  #R
#define STR2(R)  STR1(R)  

@interface BaseDemoViewController : UIViewController

// 子类重写demoCodeText返回用于演示的代码片段
- (NSString *)demoCodeText;

// 子类重写runDemoCode实现代码逻辑
- (void)runDemoCode;

@property (nonatomic, retain) UILabel *resultLabel;
@property (nonatomic, retain) UIButton *runButton;
@property (nonatomic, retain) UIButton *checkButton;
@property (nonatomic, retain) UILabel *desLabel;

@property (nonatomic, assign) BOOL isOOMDemo;

// 格式化demo代码字符串
- (NSString *)formatDemoString:(NSString *)string;

// 子类重写此方法填充demo介绍
- (NSString *)demoDescriptionString;

- (void)onReceiveChunkMallocNoti:(NSNotification *)noti;

- (void)checkLeak;

@end
