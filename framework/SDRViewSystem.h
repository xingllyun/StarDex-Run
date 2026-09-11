/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - 布局

// 布局容器类型（映射安卓基础布局）。
typedef NS_ENUM(NSInteger, SDRLayoutType) {
    SDRLayoutLinear = 0,
    SDRLayoutFrame,
    SDRLayoutRelative
};

// 布局参数：位置与尺寸约束。
@interface SDRLayoutParams : NSObject
@property (nonatomic, assign) SDRLayoutType layoutType;
@property (nonatomic, assign) CGFloat x;
@property (nonatomic, assign) CGFloat y;
@property (nonatomic, assign) CGFloat width;
@property (nonatomic, assign) CGFloat height;
@end

#pragma mark - 视图基类

// 视图基类：持有一个宿主 iOS 原生视图，映射安卓 View 的基础能力。
@interface SDRView : NSObject
@property (nonatomic, strong, readonly) UIView *nativeView;
@property (nonatomic, assign) CGRect frame;
@property (nonatomic, assign) BOOL hidden;
@property (nonatomic, assign) NSInteger tag;
- (UIView *)nativeViewForDisplay;   // 返回可渲染的原生视图
// 供子类在其自定义 init 中将占位视图替换为具体原生控件（UILabel/UIButton/...）。
- (void)replaceNativeView:(UIView *)view;
@end

#pragma mark - 基础控件（映射 iOS 原生控件）

@interface SDRTextView : SDRView
@property (nonatomic, copy) NSString *text;
@property (nonatomic, strong) UIColor *textColor;
@property (nonatomic, assign) CGFloat fontSize;
@property (nonatomic, assign) NSTextAlignment textAlignment;
@end

@interface SDRButton : SDRView
@property (nonatomic, copy) NSString *text;
@property (nonatomic, strong) UIColor *textColor;
@property (nonatomic, copy, nullable) void (^onClick)(void);
@end

@interface SDRImageView : SDRView
@property (nonatomic, strong, nullable) UIImage *image;
- (void)loadImageFromData:(NSData *)data;
@end

@interface SDREditText : SDRView
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy) NSString *placeholder;
@end

@interface SDRListView : SDRView
@property (nonatomic, strong) NSArray<NSString *> *items;
@end

#pragma mark - 布局解析器

// 布局解析器：解析安卓基础布局并排版到 iOS 原生视图树。
@interface SDRLayoutInflater : NSObject
// 解析 XML 布局描述，返回根视图（骨架阶段提供基础接口）。
- (nullable SDRView *)inflateLayoutData:(NSData *)xmlData error:(NSError **)error;
@end

#pragma mark - 事件分发

// 事件类型。
typedef NS_ENUM(NSInteger, SDRTouchEventType) {
    SDRTouchEventDown = 0,
    SDRTouchEventMove,
    SDRTouchEventUp,
    SDRTouchEventCancel
};

// 触摸事件对象。
@interface SDRTouchEvent : NSObject
@property (nonatomic, assign) SDRTouchEventType type;
@property (nonatomic, assign) CGPoint location;
@end

NS_ASSUME_NONNULL_END