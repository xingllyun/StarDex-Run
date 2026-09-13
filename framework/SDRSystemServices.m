/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

#import "SDRSystemServices.h"
#import "SDRApkInfo.h"
#import "SDRPackageInstaller.h"
#import <UserNotifications/UserNotifications.h>
#import <UIKit/UIKit.h>
#import <SystemConfiguration/SystemConfiguration.h>

@implementation SDRPackageManager
+ (instancetype)sharedInstance { static id s; static dispatch_once_t t; dispatch_once(&t, ^{ s = [self new]; }); return s; }
- (nullable SDRApkInfo *)installedPackageNamed:(NSString *)packageName {
    if (!packageName.length) return nil;
    for (SDRApkInfo *info in [self installedPackages]) {
        if ([info.packageName isEqualToString:packageName]) return info;
    }
    return nil;
}
- (NSArray<SDRApkInfo *> *)installedPackages {
    return [[SDRPackageInstaller sharedInstaller] installedApkInfos];
}
@end

@implementation SDRWindowManager {
    NSMutableArray<id> *_windows;
}
+ (instancetype)sharedInstance { static id s; static dispatch_once_t t; dispatch_once(&t, ^{ s = [self new]; }); return s; }
- (instancetype)init {
    if (self = [super init]) { _windows = [NSMutableArray array]; }
    return self;
}
- (void)attachWindow:(id)window {
    @synchronized (_windows) {
        if (window && ![_windows containsObject:window]) [_windows addObject:window];
    }
}
- (void)detachWindow:(id)window {
    @synchronized (_windows) { [_windows removeObject:window]; }
}
- (nullable id)frontWindow {
    @synchronized (_windows) { return _windows.lastObject; }
}
@end

@implementation SDRSystemStatusService
+ (instancetype)sharedInstance { static id s; static dispatch_once_t t; dispatch_once(&t, ^{ s = [self new]; }); return s; }
- (float)batteryLevel { [UIDevice currentDevice].batteryMonitoringEnabled = YES; return [UIDevice currentDevice].batteryLevel; }

// 网络可达性探测：区分 WiFi / 蜂窝 / 离线，失败降级为 Unknown。
- (SDRNetworkStatus)networkStatus {
    SCNetworkReachabilityRef ref = SCNetworkReachabilityCreateWithName(NULL, "captive.apple.com");
    if (!ref) return SDRNetworkStatusUnknown;
    SCNetworkReachabilityFlags flags = 0;
    BOOL ok = SCNetworkReachabilityGetFlags(ref, &flags);
    CFRelease(ref);
    if (!ok) return SDRNetworkStatusUnknown;
    BOOL reachable = (flags & kSCNetworkReachabilityFlagsReachable);
    if (!reachable) return SDRNetworkStatusOffline;
    BOOL cellularOnly = (flags & kSCNetworkReachabilityFlagsIsWWAN);
    if (cellularOnly) return SDRNetworkStatusCellular;
    return SDRNetworkStatusWiFi;
}

- (void)startMonitoring { [UIDevice currentDevice].batteryMonitoringEnabled = YES; }
- (void)stopMonitoring { [UIDevice currentDevice].batteryMonitoringEnabled = NO; }
@end

@implementation SDRNotificationService
+ (instancetype)sharedInstance { static id s; static dispatch_once_t t; dispatch_once(&t, ^{ s = [self new]; }); return s; }
- (void)requestAuthorizationWithCompletion:(void (^)(BOOL))completion {
    UNUserNotificationCenter *c = [UNUserNotificationCenter currentNotificationCenter];
    [c requestAuthorizationWithOptions:(UNAuthorizationOptionAlert | UNAuthorizationOptionSound | UNAuthorizationOptionBadge)
                     completionHandler:^(BOOL granted, NSError *error) {
        if (completion) completion(granted);
    }];
}
- (void)postLocalNotificationWithTitle:(NSString *)title body:(NSString *)body {
    UNMutableNotificationContent *content = [UNMutableNotificationContent new];
    content.title = title;
    content.body = body;
    UNNotificationRequest *req = [UNNotificationRequest requestWithIdentifier:[[NSUUID UUID] UUIDString]
                                                                       content:content
                                                                       trigger:nil];
    [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:req withCompletionHandler:nil];
}
@end

#pragma mark - ToastService

@implementation SDRToastService

+ (instancetype)sharedInstance { static id s; static dispatch_once_t t; dispatch_once(&t, ^{ s = [self new]; }); return s; }

- (void)showToast:(NSString *)message duration:(SDRToastDuration)duration {
    if (message.length == 0) return;
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showToast:message duration:duration];
        });
        return;
    }

    // 无 key window 可用时降级静默返回，不触发崩溃。
    UIWindow *window = [self _keyWindow];
    if (!window) return;

    NSTimeInterval seconds = (duration == SDRToastDurationLong) ? 3.5 : 2.0;

    UILabel *label = [[UILabel alloc] init];
    label.text = message;
    label.textColor = [UIColor whiteColor];
    label.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.75];
    label.textAlignment = NSTextAlignmentCenter;
    label.font = [UIFont systemFontOfSize:15.0];
    label.numberOfLines = 0;
    label.layer.cornerRadius = 8.0;
    label.layer.masksToBounds = YES;

    CGFloat maxWidth = CGRectGetWidth(window.bounds) - 60.0;
    CGSize size = [label sizeThatFits:CGSizeMake(maxWidth, CGFLOAT_MAX)];
    CGFloat w = MIN(maxWidth, size.width + 24.0);
    CGFloat h = MAX(36.0, size.height + 16.0);
    label.frame = CGRectMake((CGRectGetWidth(window.bounds) - w) / 2.0,
                             CGRectGetHeight(window.bounds) * 0.7,
                             w, h);
    [window addSubview:label];

    [UIView animateWithDuration:0.25
                          delay:seconds
                        options:UIViewAnimationOptionCurveEaseIn
                     animations:^{ label.alpha = 0.0; }
                     completion:^(BOOL finished) { [label removeFromSuperview]; }];
}

- (UIWindow *)_keyWindow {
    // iOS 13+ 使用 connectedScenes 取激活的 key window；失败回退 keyWindow。
    for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        if (scene.activationState == UISceneActivationStateForegroundActive) {
            UIWindow *w = scene.windows.firstObject;
            if (w) return w;
        }
    }
    return [UIApplication sharedApplication].keyWindow;
}

@end