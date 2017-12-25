//
//  lianxi
//
//  Created by rosen on 16/3/17.
//  Copyright © 2016年 tencent. All rights reserved.
//

#import <Foundation/Foundation.h>


typedef enum : NSUInteger {
    QQStackReportTypeChunkMemory,   // 单次大块内存分配
    QQStackReportTypeLeak,          // 内存泄漏
    QQStackReportTypeOOMLog,        // OOM日志
} QQStackReportType;

@protocol QQOOMFileDataDelegate <NSObject>

/** 在出现单次大块内存分配、检查到内存泄漏且时、调用uploadAllStack方法时触发回调 */
-(void)fileData:(NSData *)data extra:(NSDictionary<NSString*,NSString*> *)extra type:(QQStackReportType)type completionHandler:(void (^)(BOOL))completionHandler;

@end

@interface QQLeakFileUploadCenter : NSObject

+(QQLeakFileUploadCenter *)defaultCenter;

@property (nonatomic, assign) id<QQOOMFileDataDelegate> fileDataDelegate;

-(void)fileData:(NSData *)data extra:(NSDictionary<NSString*,NSString*> *)extra type:(QQStackReportType)type completionHandler:(void(^)(BOOL completed))completionHandler;

@end
