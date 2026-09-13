/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

#import "SDRPackageInstaller.h"
#import "SDRApkParser.h"
#import "SDRApkInfo.h"
#import "SDRZipArchive.h"
#import "SDRSandboxDirectory.h"

static NSError *SDRInstallError(NSString *message) {
    return [NSError errorWithDomain:@"SDRPackageInstaller" code:1
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static NSString *const kMetadataFileName = @"metadata.plist";

// 判断一个条目路径是否属于资源类（res/ 与 resources.arsc）。
static BOOL SDR_IsResourceEntry(NSString *name) {
    if ([name caseInsensitiveCompare:@"resources.arsc"] == NSOrderedSame) return YES;
    return [name hasPrefix:@"res/"];
}

// 判断条目是否为 dex 主包 / 分包。
static BOOL SDR_IsDexEntry(NSString *name) {
    NSString *base = [name lastPathComponent];
    return [base hasPrefix:@"classes"] && [base hasSuffix:@".dex"];
}

@implementation SDRPackageInstaller {
    NSFileManager *_fm;
}

+ (instancetype)sharedInstaller { static id s; static dispatch_once_t t; dispatch_once(&t, ^{ s = [self new]; }); return s; }

- (instancetype)init {
    if (self = [super init]) {
        _fm = [NSFileManager defaultManager];
    }
    return self;
}

- (void)installApkAtPath:(NSString *)apkPath
              completion:(void (^)(SDRApkInfo *, NSError *))completion {
    if (!completion) return;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        SDRApkInfo *info = [self installApkAtPath:apkPath error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(info, error);
        });
    });
}

- (SDRApkInfo *)installApkAtPath:(NSString *)apkPath error:(NSError **)error {
    // 空路径保护
    if (!apkPath || apkPath.length == 0) {
        if (error) *error = SDRInstallError(@"APK 路径为空");
        return nil;
    }

    // 1. 解析 APK（只读分析，提取包名/版本/组件/图标等）
    NSData *apkData = [NSData dataWithContentsOfFile:apkPath options:NSDataReadingMappedIfSafe error:error];
    if (apkData.length == 0) {
        if (error) *error = SDRInstallError(@"APK 文件不可读或为空");
        return nil;
    }
    SDRApkParser *parser = [[SDRApkParser alloc] initWithApkData:apkData error:error];
    if (!parser) return nil;
    SDRApkInfo *info = [parser parseInfo:error];
    if (!info) return nil;
    if (info.packageName.length == 0) {
        if (error) *error = SDRInstallError(@"Manifest 中未解析到包名");
        return nil;
    }

    // 2. 文件模式打开 ZIP（流式，控制内存峰值）
    SDRZipArchive *zip = [[SDRZipArchive alloc] initWithFileURL:[NSURL fileURLWithPath:apkPath] error:error];
    if (!zip) return nil;

    // 3. 建立沙盒目录结构 /data/data/[包名]/ 下标准子目录 + 分类目录
    NSString *dataRoot = [[SDRSandboxDirectory sharedDirectory] ensureDataRootForPackage:info.packageName];
    // 安卓标准子目录（files/cache/databases/shared_prefs）
    [[SDRSandboxDirectory sharedDirectory] ensureSubdirectory:@"files" forPackage:info.packageName];
    [[SDRSandboxDirectory sharedDirectory] ensureSubdirectory:@"cache" forPackage:info.packageName];
    [[SDRSandboxDirectory sharedDirectory] ensureSubdirectory:@"databases" forPackage:info.packageName];
    [[SDRSandboxDirectory sharedDirectory] ensureSubdirectory:@"shared_prefs" forPackage:info.packageName];
    // 分类目录（dex/lib/res/assets/manifest）
    [[SDRSandboxDirectory sharedDirectory] ensureSubdirectory:@"dex" forPackage:info.packageName];
    [[SDRSandboxDirectory sharedDirectory] ensureSubdirectory:@"lib" forPackage:info.packageName];
    [[SDRSandboxDirectory sharedDirectory] ensureSubdirectory:@"res" forPackage:info.packageName];
    [[SDRSandboxDirectory sharedDirectory] ensureSubdirectory:@"assets" forPackage:info.packageName];
    [[SDRSandboxDirectory sharedDirectory] ensureSubdirectory:@"manifest" forPackage:info.packageName];

    NSMutableArray<NSString *> *libNames = [NSMutableArray array];

    // 4. 逐条目分类解压（流式，每个条目独立读取）
    for (SDRZipEntry *entry in zip.entries) {
        if (entry.isDirectory) continue;
        NSString *name = entry.name;
        if (name.length == 0) continue;

        NSString *relativePath = nil;
        if (SDR_IsDexEntry(name)) {
            relativePath = [@"dex" stringByAppendingPathComponent:[name lastPathComponent]];
        } else if ([name hasPrefix:@"lib/"] && [name hasSuffix:@".so"]) {
            // SO 保留子目录（lib/<abi>/xxx.so）
            relativePath = [@"lib" stringByAppendingPathComponent:
                            [name substringFromIndex:[@"lib/" length]]];
            [libNames addObject:name];
        } else if ([name isEqualToString:@"AndroidManifest.xml"]) {
            relativePath = [@"manifest" stringByAppendingPathComponent:name];
        } else if (SDR_IsResourceEntry(name)) {
            relativePath = [@"res" stringByAppendingPathComponent:name];
        } else if ([name hasPrefix:@"assets/"]) {
            relativePath = [@"assets" stringByAppendingPathComponent:
                            [name substringFromIndex:[@"assets/" length]]];
        } else {
            // 其余（META-INF 等）归入 files，跳过大体积签名段之外的无关条目
            relativePath = [@"files" stringByAppendingPathComponent:name];
        }

        NSData *entryData = [zip dataForEntry:entry error:nil];
        if (!entryData) continue;  // 损坏条目跳过，不影响整体安装

        NSString *fullPath = [dataRoot stringByAppendingPathComponent:relativePath];
        NSString *dir = [fullPath stringByDeletingLastPathComponent];
        if (![_fm fileExistsAtPath:dir]) {
            [_fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
        }
        [entryData writeToFile:fullPath options:NSDataWritingAtomic error:NULL];
    }

    // 5. 保存应用图标（若可解析）
    NSString *iconRel = nil;
    if (info.iconData.length > 0) {
        iconRel = @"res/app_icon.png";
        NSString *iconPath = [dataRoot stringByAppendingPathComponent:iconRel];
        [info.iconData writeToFile:iconPath options:NSDataWritingAtomic error:NULL];
    }

    // 6. 写入包元数据 plist
    NSMutableDictionary *meta = [NSMutableDictionary dictionary];
    meta[@"packageName"] = info.packageName;
    meta[@"versionName"] = info.versionName ?: @"";
    meta[@"versionCode"] = @(info.versionCode);
    meta[@"appLabel"] = info.appLabel ?: info.packageName;
    meta[@"minSdkVersion"] = @(info.minSdkVersion);
    meta[@"targetSdkVersion"] = @(info.targetSdkVersion);
    meta[@"permissions"] = info.permissions ?: @[];
    meta[@"activities"] = info.activities ?: @[];
    meta[@"services"] = info.services ?: @[];
    meta[@"receivers"] = info.receivers ?: @[];
    meta[@"providers"] = info.providers ?: @[];
    meta[@"dexFiles"] = info.dexFiles ?: @[];
    meta[@"nativeLibs"] = libNames;
    meta[@"iconPath"] = iconRel ?: @"";
    meta[@"installedAt"] = @([[NSDate date] timeIntervalSince1970]);

    NSString *metaPath = [dataRoot stringByAppendingPathComponent:kMetadataFileName];
    [meta writeToFile:metaPath atomically:YES];

    return info;
}

- (NSDictionary<NSString *, id> *)metadataForPackage:(NSString *)packageName {
    if (!packageName.length) return nil;
    NSString *root = [[SDRSandboxDirectory sharedDirectory] appsRoot];
    NSString *metaPath = [[root stringByAppendingPathComponent:packageName]
                          stringByAppendingPathComponent:kMetadataFileName];
    return [NSDictionary dictionaryWithContentsOfFile:metaPath];
}

- (NSArray<SDRApkInfo *> *)installedApkInfos {
    NSMutableArray<SDRApkInfo *> *result = [NSMutableArray array];
    NSArray<NSString *> *pkgs = [[SDRSandboxDirectory sharedDirectory] installedPackageNames];
    for (NSString *pkg in pkgs) {
        NSDictionary *meta = [self metadataForPackage:pkg];
        if (!meta) continue;
        SDRApkInfo *info = [SDRApkInfo new];
        info.packageName = meta[@"packageName"] ?: pkg;
        info.versionName = meta[@"versionName"];
        info.versionCode = [meta[@"versionCode"] longLongValue];
        info.appLabel = meta[@"appLabel"];
        info.minSdkVersion = (uint32_t)[meta[@"minSdkVersion"] unsignedIntValue];
        info.targetSdkVersion = (uint32_t)[meta[@"targetSdkVersion"] unsignedIntValue];
        info.permissions = meta[@"permissions"] ?: @[];
        info.activities = meta[@"activities"] ?: @[];
        info.services = meta[@"services"] ?: @[];
        info.receivers = meta[@"receivers"] ?: @[];
        info.providers = meta[@"providers"] ?: @[];
        info.dexFiles = meta[@"dexFiles"] ?: @[];
        info.nativeLibs = meta[@"nativeLibs"] ?: @[];
        [result addObject:info];
    }
    return result;
}

@end