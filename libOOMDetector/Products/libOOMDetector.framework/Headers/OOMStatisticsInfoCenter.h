//
//  OOMStatisticsInfoCenter.h
//  QQLeak
//
//  Created by rosen on 16/12/29.
//  Copyright © 2016年 tencent. All rights reserved.
//

#ifndef OOMStaticsInfoCenter_h
#define OOMStaticsInfoCenter_h

#import <Foundation/Foundation.h>

typedef void (^StatisticsInfoBlock)(NSInteger memorySize_M);

@interface OOMStatisticsInfoCenter : NSObject

+(OOMStatisticsInfoCenter *)getInstance;

-(void)startMemoryOverFlowMonitor:(double)overFlowLimit;

-(void)stopMemoryOverFlowMonitor;

@property (nonatomic, copy) StatisticsInfoBlock statisticsInfoBlock;

- (void)showMemoryIndicatorView:(BOOL)yn;
-(void)updateMemory;

@end

#endif /* OOMStaticsInfoCenter_h */
