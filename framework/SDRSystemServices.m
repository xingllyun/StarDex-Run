/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

#import "SDRSystemServices.h"
#import "SDRApkInfo.h"
#import <UserNotifications/UserNotifications.h>
#import <UIKit/UIKit.h>

@implementation SDRPackageManager
+ (instancetype)sharedInstance { static id s; static dispatch_once_t t; dispatch_once(&t, ^{ s = [self new]; }); return s; }
- (nullable SDRApkInfo *)installedPackageNamed:(NSString *)packageName { return nil; }
- (NSArray<SDRApkInfo *> *)installedPackages { return @[]; }
@end

@implementation SDRWindowManager
+ (instancetype)sharedInstance { static id s; static dispatch_once_t t; dispatch_once(&t, ^{ s = [self new]; }); return s; }
- (void)attachWindow:(id)window {}
- (void)detachWindow:(id)window {}
- (nullable id)frontWindow { return nil; }
@end

@implementation SDRSystemStatusService
+ (instancetype)sharedInstance { static id s; static dispatch_once_t t; dispatch_once(&t, ^{ s = [self new]; }); return s; }
- (float)batteryLevel { [UIDevice currentDevice].batteryMonitoringEnabled = YES; return [UIDevice currentDevice].batteryLevel; }
- (SDRNetworkStatus)networkStatus {
    // TODO: 骨架阶段返回 Unknown，后续接入网络状态监控。
    return SDRNetworkStatusUnknown;
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