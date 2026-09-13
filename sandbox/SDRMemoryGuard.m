/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

#import "SDRMemoryGuard.h"
#import <mach/mach.h>

// 读取当前进程物理内存足迹（iOS 上最接近真实占用的指标）。
static uint64_t SDR_CurrentFootprint(void) {
    task_vm_info_data_t info;
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    kern_return_t kr = task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &count);
    if (kr == KERN_SUCCESS) return (uint64_t)info.phys_footprint;
    return 0;
}

static uint64_t const kDefaultPerAppLimit = 256ULL * 1024ULL * 1024ULL;  // 256MB

@implementation SDRMemoryGuard

+ (instancetype)sharedGuard { static id s; static dispatch_once_t t; dispatch_once(&t, ^{ s = [self new]; }); return s; }

- (instancetype)init {
    if (self = [super init]) {
        _perAppMemoryLimit = kDefaultPerAppLimit;
    }
    return self;
}

- (uint64_t)currentFootprint { return SDR_CurrentFootprint(); }

- (BOOL)checkMemoryForPackage:(NSString *)packageName reason:(NSString **)reason {
    uint64_t fp = SDR_CurrentFootprint();
    if (fp > _perAppMemoryLimit) {
        if (reason) {
            *reason = [NSString stringWithFormat:@"应用 %@ 内存占用 %llu MB 超过上限 %llu MB",
                       packageName ?: @"unknown",
                       (unsigned long long)(fp / (1024 * 1024)),
                       (unsigned long long)(_perAppMemoryLimit / (1024 * 1024))];
        }
        [self notifyMemoryWarningForPackage:packageName];
        return NO;
    }
    return YES;
}

- (void)notifyMemoryWarningForPackage:(NSString *)packageName {
    if (!self.onMemoryPressure) return;
    uint64_t fp = SDR_CurrentFootprint();
    void (^cb)(NSString *, uint64_t, uint64_t) = self.onMemoryPressure;
    dispatch_async(dispatch_get_main_queue(), ^{
        cb(packageName, fp, self->_perAppMemoryLimit);
    });
}

@end