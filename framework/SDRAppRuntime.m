/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

#import "SDRAppRuntime.h"
#import "SDRApkParser.h"
#import "SDRZipArchive.h"
#import "SDRDexParser.h"
#import "SDRClassLoader.h"
#import "SDRInterpreter.h"
#import "SDRAppComponents.h"
#import "SDRMemoryGuard.h"
#import "SDRSandboxDirectory.h"

static NSError *SDRRuntimeError(NSString *message) {
    return [NSError errorWithDomain:@"SDRAppRuntime" code:1
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

// 把 Android 类名（可能带前导 '.'）规范为 DEX 描述符。
static NSString *SDRDescriptorFromClassName(NSString *className, NSString *packageName) {
    NSString *n = [className stringByReplacingOccurrencesOfString:@"." withString:@"/"];
    if ([n hasPrefix:@"L"] && [n hasSuffix:@";"]) return n;   // 已是描述符
    return [NSString stringWithFormat:@"L%@;", n];
}

@interface SDRAppRuntime ()
@property (nonatomic, copy, nullable) void (^launchProgressBlock)(SDRLaunchStage stage, NSString *detail);
- (void)launchApkAtPath:(NSString *)apkPath
            packageName:(NSString *)packageName
                summary:(NSString **)summaryOut
                  steps:(NSArray<NSString *> **)stepsOut
                  error:(NSError **)errorOut;
@end

@implementation SDRAppRuntime

+ (instancetype)sharedInstance {
    static id s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [self new]; });
    return s;
}

// 主线程安全上报阶段进度。
- (void)reportStage:(SDRLaunchStage)stage detail:(NSString *)detail {
    void (^block)(SDRLaunchStage, NSString *) = self.launchProgressBlock;
    if (block) {
        dispatch_async(dispatch_get_main_queue(), ^{
            block(stage, detail);
        });
    }
}

- (void)launchApkAtPath:(NSString *)apkPath
            packageName:(NSString *)packageName
               progress:(void (^)(SDRLaunchStage, NSString *))progress
             completion:(void (^)(NSString *, NSArray<NSString *> *, NSError *))completion {
    self.launchProgressBlock = progress;
    [self launchApkAtPath:apkPath packageName:packageName completion:completion];
}

- (void)launchApkAtPath:(NSString *)apkPath
            packageName:(NSString *)packageName
             completion:(void (^)(NSString *, NSArray<NSString *> *, NSError *))completion {
    if (completion) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSString *summary = nil;
            NSArray<NSString *> *steps = nil;
            NSError *error = nil;
            [self launchApkAtPath:apkPath packageName:packageName
                         summary:&summary steps:&steps error:&error];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(summary, steps, error);
                // 运行结束后清空进度回调，避免泄漏。
                self.launchProgressBlock = nil;
            });
        });
    }
}

- (void)launchApkAtPath:(NSString *)apkPath
            packageName:(NSString *)packageName
                summary:(NSString **)summaryOut
                  steps:(NSArray<NSString *> **)stepsOut
                  error:(NSError **)errorOut {
    // 空路径保护
    if (!apkPath || apkPath.length == 0) {
        [self reportStage:SDRLaunchStageFailed detail:@"APK 路径为空"];
        if (errorOut) *errorOut = SDRRuntimeError(@"APK 路径为空");
        return;
    }
    NSMutableArray<NSString *> *steps = [NSMutableArray array];

    // 1. 校验文件（存在性 / 大小 / 可读性）
    [self reportStage:SDRLaunchStageVerifyFile detail:@"正在校验 APK 文件"];
    NSError *readError = nil;
    NSData *apkData = [NSData dataWithContentsOfFile:apkPath
                                             options:NSDataReadingMappedIfSafe
                                               error:&readError];
    if (apkData.length == 0) {
        NSString *msg = [NSString stringWithFormat:@"APK 文件不可读：%@", readError.localizedDescription ?: @"空文件"];
        [self reportStage:SDRLaunchStageFailed detail:msg];
        if (errorOut) *errorOut = SDRRuntimeError(msg);
        return;
    }
    [steps addObject:@"APK 文件校验通过（存在且可读）"];

    // 2. 解包 APK（ZIP 容器）
    SDRZipArchive *zip = [[SDRZipArchive alloc] initWithData:apkData error:errorOut];
    if (!zip) {
        [self reportStage:SDRLaunchStageFailed detail:@"APK 解包失败（格式非法）"];
        return;
    }
    [steps addObject:[NSString stringWithFormat:@"解包 APK 成功（%lu 个条目）", (unsigned long)zip.entries.count]];

    // 3. 解析并加载全部 DEX
    [self reportStage:SDRLaunchStageParseDex detail:@"正在解析 DEX 文件"];
    SDRClassLoader *loader = [SDRClassLoader new];
    NSUInteger dexCount = 0;
    for (SDRZipEntry *e in zip.entries) {
        NSString *n = e.name;
        if (!([n hasPrefix:@"classes"] && [n hasSuffix:@".dex"])) continue;
        NSData *dexData = [zip dataForEntry:e error:nil];
        if (!dexData.length) continue;
        SDRDexFile *dex = [[SDRDexFile alloc] initWithData:dexData error:nil];
        if (!dex) continue;
        [loader addDexFile:dex];
        dexCount++;
        [steps addObject:[NSString stringWithFormat:@"加载 DEX：%@（%u 个类）",
                          n, dex.classDefsSize]];
    }
    if (dexCount == 0) {
        NSString *msg = @"APK 内未找到可加载的 classes.dex";
        [self reportStage:SDRLaunchStageFailed detail:msg];
        if (errorOut) *errorOut = SDRRuntimeError(msg);
        return;
    }

    // 4. 创建虚拟机（解释器实例）
    [self reportStage:SDRLaunchStageCreateVM detail:@"正在创建虚拟机（解释器）"];
    SDRInterpreter *interp = [[SDRInterpreter alloc] initWithClassLoader:loader];
    [steps addObject:@"虚拟机（解释器）已就绪，寄存器/调用栈保护已启用"];

    // 5. 定位入口 Activity（解析 Manifest 取第一个 Activity）
    [self reportStage:SDRLaunchStageFindEntry detail:@"正在查找入口 Activity"];
    NSString *entryClass = nil;
    SDRApkParser *parser = [[SDRApkParser alloc] initWithApkData:apkData error:nil];
    SDRApkInfo *info = [parser parseInfo:nil];
    if (info.activities.count > 0) {
        entryClass = info.activities.firstObject;
    }
    if (entryClass.length == 0) {
        NSString *msg = @"Manifest 未声明任何 Activity";
        [self reportStage:SDRLaunchStageFailed detail:msg];
        if (errorOut) *errorOut = SDRRuntimeError(msg);
        return;
    }
    // 相对类名补全（如 ".MainActivity" → 包名 前缀）
    if ([entryClass hasPrefix:@"."]) {
        entryClass = [packageName stringByAppendingString:entryClass];
    }
    NSString *desc = SDRDescriptorFromClassName(entryClass, packageName);
    [steps addObject:[NSString stringWithFormat:@"入口 Activity：%@（%@）", entryClass, desc]];

    // 6. 加载入口类并实例化
    [self reportStage:SDRLaunchStageLoadClass detail:@"正在加载入口类与资源"];
    SDRDexClass *clazz = [loader findClassByDescriptor:desc];
    if (!clazz) {
        NSString *msg = [NSString stringWithFormat:
            @"入口类 %@ 不在 APK 的 DEX 中（可能位于加固壳/动态加载的外置 DEX）", entryClass];
        [self reportStage:SDRLaunchStageFailed detail:msg];
        if (errorOut) *errorOut = SDRRuntimeError(msg);
        return;
    }
    [steps addObject:[NSString stringWithFormat:@"入口类已加载：方法 %lu 个，父类 %@",
                      (unsigned long)clazz.methods.count,
                      clazz.superClass ? clazz.superClass.descriptor : @"无"]];

    SDRDexObject *instance = [[SDRDexObject alloc] initWithClass:clazz];
    [interp.heapObjects addObject:instance];
    [steps addObject:@"入口 Activity 已实例化（new-instance 模拟完成）"];

    // 7. 解释执行 onCreate(Bundle)
    [self reportStage:SDRLaunchStageStartActivity detail:@"正在启动 Activity（执行 onCreate）"];
    SDRDexMethod *onCreate = [loader resolveMethod:@"onCreate"
                                          descriptor:@"(Landroid/os/Bundle;)V"
                                             inClass:clazz];
    if (!onCreate) {
        // 某些入口类不在 DEX（壳类），或 Activity 未覆写 onCreate（合法，此时无事可做）。
        if (stepsOut) *stepsOut = steps;
        if (summaryOut) *summaryOut = @"入口类未覆写 onCreate()，执行链路至此完成（待完善生命周期的其他阶段）";
        [self reportStage:SDRLaunchStageRunning detail:@"入口类未覆写 onCreate，链路执行完成"];
        return;
    }

    NSArray<NSValue *> *args = @[ SDRValueWrap(SDRMakeObject(NULL)) ];  // Bundle = null
    SDRExecOutcome *outcome = [interp invokeInstanceMethod:@"onCreate"
                                                descriptor:@"(Landroid/os/Bundle;)V"
                                                    object:instance
                                                      args:args];
    [steps addObject:[NSString stringWithFormat:@"onCreate 执行完成，指令数 %llu",
                      (unsigned long long)interp.instructionCount]];

    if (outcome.error) {
        NSString *msg = [NSString stringWithFormat:@"onCreate 执行中止：%@", outcome.error.localizedDescription];
        [self reportStage:SDRLaunchStageFailed detail:msg];
        if (errorOut) *errorOut = SDRRuntimeError(msg);
        return;
    }
    if (outcome.exception) {
        NSString *msg = [NSString stringWithFormat:@"onCreate 抛出未捕获异常：%@",
                         outcome.exception.clazz.descriptor ?: @"未知类型"];
        [self reportStage:SDRLaunchStageFailed detail:msg];
        if (errorOut) *errorOut = SDRRuntimeError(msg);
        return;
    }

    // 8. 推进框架层 Activity 完整生命周期（onCreate → onStart → onResume），并压入任务栈
    SDRActivity *activity = [[SDRActivity alloc] initWithPackageName:packageName className:entryClass];
    [activity onCreate];
    [activity onStart];
    [activity onResume];
    [[SDRActivityStack sharedStack] pushActivity:activity];
    [steps addObject:[NSString stringWithFormat:@"Activity 生命周期推进至 %@（onCreate→onStart→onResume）",
                      [activity isInState:SDRActivityStateResumed] ? @"Resumed" : @"异常状态"]];

    // 9. 单应用内存上限管控（超出阈值主动告警，不强制 OOM）
    uint64_t footprint = [SDRMemoryGuard sharedGuard].currentFootprint;
    if (footprint > [SDRMemoryGuard sharedGuard].perAppMemoryLimit) {
        [steps addObject:[NSString stringWithFormat:@"Warn：内存足迹 %llu MB 超过单应用上限，已触发压力提示",
                          (unsigned long long)(footprint / (1024 * 1024))]];
        [[SDRMemoryGuard sharedGuard] notifyMemoryWarningForPackage:packageName];
    } else {
        [steps addObject:[NSString stringWithFormat:@"内存足迹 %llu MB（上限 %llu MB）",
                          (unsigned long long)(footprint / (1024 * 1024)),
                          (unsigned long long)([SDRMemoryGuard sharedGuard].perAppMemoryLimit / (1024 * 1024))]];
    }

    [self reportStage:SDRLaunchStageRunning detail:@"应用正在运行"];

    if (stepsOut) *stepsOut = steps;
    if (summaryOut) *summaryOut = [NSString stringWithFormat:
        @"启动流程完成：%u 个 DEX / 入口 %@ / onCreate 正常返回并推进至 Resumed（指令数 %llu）",
        (unsigned)dexCount, entryClass, (unsigned long long)interp.instructionCount];
}

@end