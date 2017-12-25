//
//  QQLeakDataUploadCenter.h
//
//
//  Created by rosenluo on 16/1/27.
//  Copyright © 2016年 com.tencent. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol QQOOMPerformanceDataDelegate <NSObject>

/*! @brief 在调用startMaxMemoryStatistic:开启内存触顶监控后会触发此回调，返回前一次app运行时单次生命周期内的最大物理内存数据
 *  @param data 性能数据
 */
-(void)performanceData:(NSDictionary *)data completionHandler:(void (^)(BOOL))completionHandler;

@end

@interface QQLeakDataUploadCenter : NSObject

+(QQLeakDataUploadCenter *)defaultCenter;

@property (nonatomic, weak) id<QQOOMPerformanceDataDelegate> performanceDataDelegate;

/*! @brief 在调用startMaxMemoryStatistic:开启内存触顶监控后会触发此回调，返回前一次app运行时单次生命周期内的最大物理内存数据
 *  @param data 性能数据
 */
-(void)performanceData:(NSDictionary *)data completionHandler:(void (^)(BOOL))completionHandler;

@end
