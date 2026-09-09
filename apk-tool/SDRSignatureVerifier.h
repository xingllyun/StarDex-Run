/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// APK 签名方案位掩码。
typedef NS_OPTIONS(NSUInteger, SDRApkSignedScheme) {
    SDRApkSchemeV1 = 1 << 0,   // JAR 签名 (META-INF/*.RSA|DSA|EC)
    SDRApkSchemeV2 = 1 << 1,   // APK Signature Scheme v2（签名块）
    SDRApkSchemeV3 = 1 << 2    // APK Signature Scheme v3（签名块）
};

// 单个签名证书信息。
@interface SDRApkCertificateInfo : NSObject
@property (nonatomic, copy) NSString *subject;      // 完整 DN 摘要
@property (nonatomic, copy) NSString *commonName;   // CN
@property (nonatomic, copy) NSString *issuerCN;
@property (nonatomic, copy) NSString *serialNumber;
@property (nonatomic, strong, nullable) NSDate *notBefore;
@property (nonatomic, strong, nullable) NSDate *notAfter;
@property (nonatomic, assign) BOOL withinValidityPeriod;  // 当前时间在有效期内
@property (nonatomic, assign) BOOL selfSigned;
@end

// 一次签名校验的结果。
@interface SDRApkSignatureResult : NSObject
@property (nonatomic, assign) SDRApkSignedScheme schemes;  // 命中的方案位掩码
@property (nonatomic, assign) BOOL isSigned;              // 至少存在一种签名
@property (nonatomic, assign) BOOL v1DigestIntegrity;       // V1 摘要链(条目→MF→SF)是否完整
@property (nonatomic, assign) BOOL v1SignatureVerified;     // V1 证书 RSA 签名是否校验通过
@property (nonatomic, strong) NSArray<SDRApkCertificateInfo *> *certificates;
@property (nonatomic, copy) NSString *summaryMessage;       // 人类可读状态汇总
@end

// APK 签名校验：V1 完整性/摘要链/证书有效期，V2/V3 方案检测。
// 说明：V2/V3 完整密码学验证依赖 APK Signing Block 的复杂结构，
// 当前实现为“方案存在性检测 + 结构解析”，V1 做完整摘要链与证书校验。
@interface SDRSignatureVerifier : NSObject

- (SDRApkSignatureResult *)verifyApkData:(NSData *)apkData error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END