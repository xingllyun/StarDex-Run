/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - 图片解码

// Bitmap 基础实现：映射 iOS CoreGraphics（UIImage 封装）。
@interface SDRBitmap : NSObject
@property (nonatomic, strong, readonly) UIImage *image;
@property (nonatomic, readonly) NSUInteger width;
@property (nonatomic, readonly) NSUInteger height;
- (nullable instancetype)initWithData:(NSData *)data;
- (nullable instancetype)initWithImage:(UIImage *)image;
@end

#pragma mark - 音频播放

// MediaPlayer 基础功能：映射 AVFoundation。
@interface SDRMediaPlayer : NSObject
@property (nonatomic, readonly) BOOL isPlaying;
- (instancetype)initWithContentsOfFile:(NSString *)path;
- (BOOL)prepareToPlay:(NSError **)error;
- (void)play;
- (void)pause;
- (void)stop;
@end

#pragma mark - 相机

// 相机基础调用：映射 iOS 相机权限与系统接口。
@interface SDRCamera : NSObject
+ (void)requestAccessWithCompletion:(void (^)(BOOL granted))completion;
+ (BOOL)hasCameraAccess;
@end

NS_ASSUME_NONNULL_END