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
            });
        });
    }
}

- (void)launchApkAtPath:(NSString *)apkPath
            packageName:(NSString *)packageName
                summary:(NSString **)summaryOut
                  steps:(NSArray<NSString *> **)stepsOut
                  error:(NSError **)errorOut {
    NSMutableArray<NSString *> *steps = [NSMutableArray array];

    // 1. 读取 APK
    NSData *apkData = [NSData dataWithContentsOfFile:apkPath];
    if (apkData.length == 0) {
        if (errorOut) *errorOut = SDRRuntimeError(@"APK 文件不可读");
        return;
    }
    SDRZipArchive *zip = [[SDRZipArchive alloc] initWithData:apkData error:errorOut];
    if (!zip) return;
    [steps addObject:[NSString stringWithFormat:@"解包 APK 成功（%lu 个条目）", (unsigned long)zip.entries.count]];

    // 2. 加载全部 DEX
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
        if (errorOut) *errorOut = SDRRuntimeError(@"APK 内未找到可加载的 classes.dex");
        return;
    }

    // 3. 定位入口 Activity（骨架阶段：解析 Manifest 取第一个 Activity）
    NSString *entryClass = nil;
    SDRApkParser *parser = [[SDRApkParser alloc] initWithApkData:apkData error:nil];
    SDRApkInfo *info = [parser parseInfo:nil];
    if (info.activities.count > 0) {
        entryClass = info.activities.firstObject;
    }
    if (entryClass.length == 0) {
        if (errorOut) *errorOut = SDRRuntimeError(@"Manifest 未声明任何 Activity");
        return;
    }
    // 相对类名补全（如 ".MainActivity" → 包名 前缀）
    if ([entryClass hasPrefix:@"."]) {
        entryClass = [packageName stringByAppendingString:entryClass];
    }
    NSString *desc = SDRDescriptorFromClassName(entryClass, packageName);
    [steps addObject:[NSString stringWithFormat:@"入口 Activity：%@（%@）", entryClass, desc]];

    // 4. 加载入口类并实例化
    SDRDexClass *clazz = [loader findClassByDescriptor:desc];
    if (!clazz) {
        if (errorOut) *errorOut = SDRRuntimeError(
            [NSString stringWithFormat:@"入口类 %@ 不在 APK 的 DEX 中（可能位于加固壳/动态加载的外置 DEX）", entryClass]);
        return;
    }
    [steps addObject:[NSString stringWithFormat:@"入口类已加载：方法 %lu 个，父类 %@",
                      (unsigned long)clazz.methods.count,
                      clazz.superClass ? clazz.superClass.descriptor : @"无"]];

    SDRInterpreter *interp = [[SDRInterpreter alloc] initWithClassLoader:loader];
    SDRDexObject *instance = [[SDRDexObject alloc] initWithClass:clazz];
    [interp.heapObjects addObject:instance];
    [steps addObject:@"入口 Activity 已实例化（new-instance 模拟完成）"];

    // 5. 解释执行 onCreate(Bundle)
    SDRDexMethod *onCreate = [loader resolveMethod:@"onCreate"
                                          descriptor:@"(Landroid/os/Bundle;)V"
                                             inClass:clazz];
    if (!onCreate) {
        // 某些入口类不在 DEX（壳类），或 Activity 未覆写 onCreate（合法，此时无事可做）。
        if (stepsOut) *stepsOut = steps;
        if (summaryOut) *summaryOut = @"入口类未覆写 onCreate()，执行链路至此完成（待完善生命周期的其他阶段）";
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
        if (errorOut) *errorOut = SDRRuntimeError(
            [NSString stringWithFormat:@"onCreate 执行中止：%@", outcome.error.localizedDescription]);
        return;
    }
    if (outcome.exception) {
        if (errorOut) *errorOut = SDRRuntimeError(
            [NSString stringWithFormat:@"onCreate 抛出未捕获异常：%@",
             outcome.exception.clazz.descriptor ?: @"未知类型"]);
        return;
    }

    if (stepsOut) *stepsOut = steps;
    if (summaryOut) *summaryOut = [NSString stringWithFormat:
        @"启动流程完成：%u 个 DEX / 入口 %@ / onCreate 正常返回（指令数 %llu）",
        (unsigned)dexCount, entryClass, (unsigned long long)interp.instructionCount];
}

@end