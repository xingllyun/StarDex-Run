/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

// Swift ↔ Objective-C 桥接头文件。
// 在 Xcode 的 Build Settings 中将 SWIFT_OBJC_BRIDGING_HEADER 指向本文件，
// 并将 apk-tool / dex-core / ios-adapter / framework / native-loader / sandbox
// 各目录加入 HEADER_SEARCH_PATHS。

#import "SDREntitlementChecker.h"
#import "SDRVersionAdapter.h"
#import "SDRApkParser.h"
#import "SDRApkInfo.h"
#import "SDRHardeningDetector.h"
#import "SDRSignatureVerifier.h"
#import "SDRApkSigner.h"
#import "SDRSandboxDirectory.h"
#import "SDRSandboxCache.h"
#import "SDRPackageInstaller.h"
#import "SDRAppRuntime.h"