/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Intent

// 组件间通信意图：模拟 android.content.Intent 的跳转与投递。
@interface SDRIntent : NSObject
@property (nonatomic, copy, nullable) NSString *action;
@property (nonatomic, copy, nullable) NSString *component;      // "包名/类名"
@property (nonatomic, strong) NSMutableDictionary<NSString *, id> *extras;
@property (nonatomic, assign) BOOL hasFlags;
@property (nonatomic, assign) uint32_t flags;
+ (instancetype)intentWithComponent:(NSString *)component;
+ (instancetype)intentWithAction:(NSString *)action;
- (void)putExtra:(id)value forKey:(NSString *)key;
- (nullable id)extraForKey:(NSString *)key;
@end

#pragma mark - 组件基类

// 应用组件基类：持有所属包信息与运行状态。
@interface SDRComponent : NSObject
@property (nonatomic, copy) NSString *packageName;
@property (nonatomic, copy) NSString *className;
@property (nonatomic, assign, readonly) BOOL started;
- (instancetype)initWithPackageName:(NSString *)packageName className:(NSString *)className;
@end

#pragma mark - Activity

// Activity 生命周期：onCreate/onStart/onResume/onPause/onStop/onDestroy。
typedef NS_ENUM(NSInteger, SDRActivityLifecycleState) {
    SDRActivityStateCreated = 0,
    SDRActivityStateStarted,
    SDRActivityStateResumed,
    SDRActivityStatePaused,
    SDRActivityStateStopped,
    SDRActivityStateDestroyed
};

@interface SDRActivity : SDRComponent
@property (nonatomic, assign, readonly) SDRActivityLifecycleState lifecycleState;
// 生命周期回调（由框架调度器按序调用）。
- (void)onCreate;
- (void)onStart;
- (void)onResume;
- (void)onPause;
- (void)onStop;
- (void)onDestroy;
@end

#pragma mark - Service

// Service 基础生命周期：启动 / 绑定两种模式。
@interface SDRService : SDRComponent
@property (nonatomic, assign, readonly) BOOL bound;
- (void)onCreateService;
- (void)onStartWithIntent:(SDRIntent *)intent;
- (void)onBind;
- (void)onUnbind;
- (void)onDestroyService;
@end

#pragma mark - BroadcastReceiver

// 广播接收器：基础广播分发。
@interface SDRBroadcastReceiver : NSObject
@property (nonatomic, copy, nullable) NSString *action;
- (void)onReceiveIntent:(SDRIntent *)intent;
@end

NS_ASSUME_NONNULL_END