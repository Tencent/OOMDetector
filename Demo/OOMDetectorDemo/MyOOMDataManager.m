//
//  MyOOMDataManager.m
//  OOMDetector
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

#import "MyOOMDataManager.h"

@import libOOMDetector;

@implementation MyOOMDataManager

+ (instancetype)getInstance
{
    static MyOOMDataManager *manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [MyOOMDataManager new];
    });
    return manager;
}

- (void)performanceData:(NSDictionary *)data completionHandler:(void (^)(BOOL))completionHandler
{
//    NSLog(@"%@ \n", data);
    
    completionHandler(YES);
}

- (void)fileData:(NSData *)data extra:(NSDictionary<NSString *,NSString *> *)extra type:(QQStackReportType)type completionHandler:(void (^)(BOOL))completionHandler
{
//    NSLog(@"\n %@ \n %ld \n %@\n", extra, type, [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
    
    if (type == QQStackReportTypeOOMLog) {
        // 此处为了Demo演示需要传参数NO，NO表示我们自己业务对data处理尚未完成或者失败，OOMDetector内部暂时不会删除临时文件
        if(completionHandler){
            completionHandler(NO);
        }
    } else {
        if(completionHandler){
            completionHandler(YES);
        }
    }
}


@end
