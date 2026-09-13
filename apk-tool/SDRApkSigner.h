/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// 内置 APK 签名工具：本地生成 RSA 密钥对与自签名 X.509 证书，
// 构造 MANIFEST.MF / CERT.SF / CERT.RSA 完成 V1 重签名，全程无需联网。
// 仅处理合法原始安装包；不支持脱壳、不支持破解加固包。
@interface SDRApkSigner : NSObject

// 对原始（未签名或需重签名）APK 数据执行重签名，返回新的 APK 字节流。
// 失败返回 nil 并写 error。
- (nullable NSData *)resignApkData:(NSData *)apkData
               commonName:(NSString *)commonName
                    error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END