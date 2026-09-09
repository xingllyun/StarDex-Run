/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

#import "SDRAppComponents.h"

#pragma mark - SDRIntent

@implementation SDRIntent

+ (instancetype)intentWithComponent:(NSString *)component {
    SDRIntent *i = [SDRIntent new];
    i.component = component;
    return i;
}

+ (instancetype)intentWithAction:(NSString *)action {
    SDRIntent *i = [SDRIntent new];
    i.action = action;
    return i;
}

- (instancetype)init {
    if (self = [super init]) {
        _extras = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)putExtra:(id)value forKey:(NSString *)key {
    if (value && key) _extras[key] = value;
}

- (id)extraForKey:(NSString *)key {
    return key ? _extras[key] : nil;
}

@end

#pragma mark - SDRComponent

@interface SDRComponent ()
@property (nonatomic, assign, readwrite) BOOL started;
@end

@implementation SDRComponent

- (instancetype)initWithPackageName:(NSString *)packageName className:(NSString *)className {
    if (self = [super init]) {
        _packageName = [packageName copy];
        _className = [className copy];
    }
    return self;
}

@end

#pragma mark - SDRActivity

@implementation SDRActivity {
    SDRActivityLifecycleState _state;
}

- (SDRActivityLifecycleState)lifecycleState { return _state; }
- (void)onCreate    { _state = SDRActivityStateCreated; }
- (void)onStart     { _state = SDRActivityStateStarted; self.started = YES; }
- (void)onResume    { _state = SDRActivityStateResumed; }
- (void)onPause     { _state = SDRActivityStatePaused; }
- (void)onStop      { _state = SDRActivityStateStopped; self.started = NO; }
- (void)onDestroy   { _state = SDRActivityStateDestroyed; }

@end

#pragma mark - SDRService

@implementation SDRService

- (void)onCreateService { self.started = YES; }
- (void)onStartWithIntent:(SDRIntent *)intent {}
- (void)onBind { _bound = YES; self.started = YES; }
- (void)onUnbind { _bound = NO; }
- (void)onDestroyService { self.started = NO; }

@end

#pragma mark - SDRBroadcastReceiver

@implementation SDRBroadcastReceiver
- (void)onReceiveIntent:(SDRIntent *)intent {}
@end