/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SDRApkInfo;

#pragma mark - 包管理服务

// 包管理服务（PackageManager）：应用信息查询与已安装包列表。
@interface SDRPackageManager : NSObject
+ (instancetype)sharedInstance;
- (nullable SDRApkInfo *)installedPackageNamed:(NSString *)packageName;
- (NSArray<SDRApkInfo *> *)installedPackages;
@end

#pragma mark - 窗口管理服务

// 窗口管理服务（WindowManager）：窗口层级与生命周期管理。
@interface SDRWindowManager : NSObject
+ (instancetype)sharedInstance;
// 注册 / 注销一个窗口（绑定到当前 Activity）。
- (void)attachWindow:(id)window;
- (void)detachWindow:(id)window;
- (nullable id)frontWindow;
@end

#pragma mark - 系统状态服务（电量/网络/传感器）

// 网络状态。
typedef NS_ENUM(NSInteger, SDRNetworkStatus) {
    SDRNetworkStatusUnknown = 0,
    SDRNetworkStatusOffline,
    SDRNetworkStatusCellular,
    SDRNetworkStatusWiFi
};

// 系统状态服务：电量、网络状态、传感器基础模拟。
@interface SDRSystemStatusService : NSObject
+ (instancetype)sharedInstance;
@property (nonatomic, readonly) float batteryLevel;         // 0.0 ~ 1.0
@property (nonatomic, readonly) SDRNetworkStatus networkStatus;
- (void)startMonitoring;
- (void)stopMonitoring;
@end

#pragma mark - 通知服务

// 通知服务：映射 iOS 本地通知系统。
@interface SDRNotificationService : NSObject
+ (instancetype)sharedInstance;
- (void)postLocalNotificationWithTitle:(NSString *)title body:(NSString *)body;
- (void)requestAuthorizationWithCompletion:(void (^)(BOOL granted))completion;
@end

#pragma mark - Toast 服务

// Toast 短提示：映射 Android Toast，等价 iOS 原生悬浮提示（非阻塞、自动消失）。
typedef NS_ENUM(NSInteger, SDRToastDuration) {
    SDRToastDurationShort = 0,   // 约 2.0s
    SDRToastDurationLong         // 约 3.5s
};

@interface SDRToastService : NSObject
+ (instancetype)sharedInstance;
// 主线程安全调用；内部自动切主线程展示。
- (void)showToast:(NSString *)message duration:(SDRToastDuration)duration;
@end

NS_ASSUME_NONNULL_END