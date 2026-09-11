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

- (instancetype)initWithPackageName:(NSString *)packageName className:(NSString *)className {
    if (self = [super initWithPackageName:packageName className:className]) {
        _state = (SDRActivityLifecycleState)-1;  // 未创建
    }
    return self;
}

- (SDRActivityLifecycleState)lifecycleState { return _state; }
- (BOOL)isInState:(SDRActivityLifecycleState)state { return _state == state; }

- (void)setContentView:(SDRView *)view { _contentView = view; }

- (void)onCreate {
    if (_state != (SDRActivityLifecycleState)-1) return;  // 非法重复调用拦截
    _state = SDRActivityStateCreated;
}
- (void)onStart {
    if (_state != SDRActivityStateCreated && _state != SDRActivityStateStopped) return;
    _state = SDRActivityStateStarted; self.started = YES;
}
- (void)onResume {
    if (_state != SDRActivityStateStarted && _state != SDRActivityStatePaused) return;
    _state = SDRActivityStateResumed;
}
- (void)onPause {
    if (_state != SDRActivityStateResumed) return;
    _state = SDRActivityStatePaused;
}
- (void)onStop {
    if (_state != SDRActivityStateStarted && _state != SDRActivityStatePaused) return;
    _state = SDRActivityStateStopped; self.started = NO;
}
- (void)onDestroy {
    _state = SDRActivityStateDestroyed;
    self.started = NO;
}

@end

#pragma mark - SDRActivityStack

@implementation SDRActivityStack {
    NSMutableArray<SDRActivity *> *_stack;
}

+ (instancetype)sharedStack { static id s; static dispatch_once_t t; dispatch_once(&t, ^{ s = [self new]; }); return s; }

- (instancetype)init {
    if (self = [super init]) { _stack = [NSMutableArray array]; }
    return self;
}

- (void)pushActivity:(SDRActivity *)activity {
    @synchronized (_stack) {
        if (activity && ![_stack containsObject:activity]) [_stack addObject:activity];
    }
}
- (void)popActivity {
    @synchronized (_stack) {
        if (_stack.count) [_stack removeLastObject];
    }
}
- (nullable SDRActivity *)topActivity {
    @synchronized (_stack) { return _stack.lastObject; }
}
- (NSArray<SDRActivity *> *)activityList {
    @synchronized (_stack) { return [_stack copy]; }
}
- (void)removeAll {
    @synchronized (_stack) { [_stack removeAllObjects]; }
}

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