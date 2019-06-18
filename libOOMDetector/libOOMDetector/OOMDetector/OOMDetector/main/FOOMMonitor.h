//
//  FOOMMonitor.h
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

#import <Foundation/Foundation.h>

@interface FOOMMonitor : NSObject

/*! @brief 监控前台爆内存，原理参考：https://code.facebook.com/posts/1146930688654547/reducing-fooms-in-the-facebook-ios-app/
 *
 */
+(FOOMMonitor *)getInstance;

/*! @brief 开始爆内存监控，不会影响性能，可以全网开启
 *
 */
-(void)start;

/*! @brief 获取日志uuid，uuid每次启动会唯一生成
 *
 */
-(NSString *)getLogUUID;

/*! @brief 获取当前记录的日志信息目录
 *
 */
-(NSString *)getLogPath;

/*! @brief 为了保证数据准确，请在UIApplication delegate的applicationDidEnterBackground:回调第一时间调用该方法
 *
 */
-(void)appDidEnterBackground;

/*! @brief 为了保证数据准确，请在UIApplication delegate的applicationWillEnterForeground:回调第一时间调用该方法
 *
 */
-(void)appWillEnterForground;

/*! @brief 为了保证数据准确，请在UIApplication delegate的applicationWillTerminate:回调第一时间调用该方法
 *
 */
-(void)appWillTerminate;

/*! @brief 请在Crash组件捕获到crash后调用该方法
 *
 */
-(void)appDidCrashed;

/*! @brief 请在卡死检测组件检测到5秒以上卡顿时调用该方法
 *
 */
-(void)appDetectDeadLock:(NSDictionary *)stack;

/*! @brief 请在卡死检测组件从5秒以上卡顿恢复时回调该方法
 *
 */
-(void)appResumeFromDeadLock;

/*! @brief 如果开启了OOMDetector爆内存堆栈检测请设置该方法
 *
 * @param isOpen YES表示开启了OOMDetector爆内存堆栈检测
 *
 */
-(void)setOOMDetectorOpen:(BOOL)isOpen;


/*! @brief 设置appVersion
 *
 * @param appVersion app版本号
 *
 */
-(void)setAppVersion:(NSString *)appVersion;

/*! @brief SDK内部方法，不要直接调用
 *
 */
-(void)updateStage:(NSString *)stage;

/*! @brief SDK内部方法，不要直接调用
 *
 */
-(void)appExit;

@end
