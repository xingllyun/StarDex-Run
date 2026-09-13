/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// APK 加固检测：识别主流加固方案的特征（文件名 / DEX 壳标记 / SO 壳特征 / 专属资源）。
// 检测到任何加固特征即返回对应加固方案名称；无特征返回 nil。
@interface SDRHardeningDetector : NSObject

// 直接对原始 APK 字节流做特征扫描（无需解包）。
- (nullable NSString *)detectInRawData:(NSData *)apkData;

// 对已解包的 ZIP 条目名做特征匹配（可与 raw 检测结合）。
- (nullable NSString *)detectInEntryNames:(NSArray<NSString *> *)entryNames;

// 综合检测：同时使用原始字节 + 条目名，给出首个命中的加固方案。
- (nullable NSString *)detect:(NSData *)apkData entryNames:(NSArray<NSString *> *)entryNames;

@end

NS_ASSUME_NONNULL_END