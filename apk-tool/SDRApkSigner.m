/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

#import "SDRApkSigner.h"
#import "SDRZipArchive.h"
#import <CommonCrypto/CommonDigest.h>
#import <Security/Security.h>
#import <zlib.h>

// ============================================================================
// 最小 DER 编码
// ============================================================================

static NSData *SDR_DER_TLV(uint8_t tag, NSData *content) {
    NSMutableData *out = [NSMutableData data];
    [out appendBytes:&tag length:1];
    NSUInteger len = content.length;
    if (len < 0x80) {
        uint8_t l = (uint8_t)len;
        [out appendBytes:&l length:1];
    } else {
        uint8_t cnt = 0; NSUInteger t = len; uint8_t tmp[8];
        while (t) { tmp[cnt++] = t & 0xFF; t >>= 8; }
        uint8_t h = 0x80 | cnt;
        [out appendBytes:&h length:1];
        for (int k = (int)cnt - 1; k >= 0; k--) { uint8_t b = tmp[k]; [out appendBytes:&b length:1]; }
    }
    [out appendData:content];
    return out;
}

static NSData *SDR_DER_Join(NSArray<NSData *> *parts) {
    NSMutableData *d = [NSMutableData data];
    for (NSData *p in parts) [d appendData:p];
    return d;
}
static NSData *SDR_DER_Seq(NSData *c) { return SDR_DER_TLV(0x30, c); }
static NSData *SDR_DER_Set(NSData *c) { return SDR_DER_TLV(0x31, c); }
static NSData *SDR_DER_Int(uint64_t v) {
    uint8_t bytes[8]; int n = 0;
    if (v == 0) { bytes[n++] = 0; }
    else { uint64_t t = v; while (t) { bytes[n++] = t & 0xFF; t >>= 8; } }
    NSMutableData *d = [NSMutableData data];
    if (bytes[n - 1] & 0x80) { uint8_t z = 0; [d appendBytes:&z length:1]; }
    for (int i = n - 1; i >= 0; i--) { uint8_t b = bytes[i]; [d appendBytes:&b length:1]; }
    return SDR_DER_TLV(0x02, d);
}
static NSData *SDR_DER_OID(const uint8_t *oid, NSUInteger len) {
    return SDR_DER_TLV(0x06, [NSData dataWithBytes:oid length:len]);
}
static NSData *SDR_DER_Null(void) { return SDR_DER_TLV(0x05, [NSData data]); }
static NSData *SDR_DER_BitString(NSData *content) {
    NSMutableData *d = [NSMutableData data];
    uint8_t z = 0; [d appendBytes:&z length:1];
    [d appendData:content];
    return SDR_DER_TLV(0x03, d);
}
static NSData *SDR_DER_UTF8(NSString *s) {
    return SDR_DER_TLV(0x0C, [s dataUsingEncoding:NSUTF8StringEncoding]);
}
static NSData *SDR_DER_Context(uint8_t tag, NSData *content) {
    return SDR_DER_TLV(0xA0 | (tag & 0x1F), content);
}

// OID 常量
static const uint8_t kOID_rsaEncryption[]        = {0x2a,0x86,0x48,0x86,0xf7,0x0d,0x01,0x01,0x01};
static const uint8_t kOID_sha256WithRSA[]        = {0x2a,0x86,0x48,0x86,0xf7,0x0d,0x01,0x01,0x0b};
static const uint8_t kOID_sha256[]               = {0x60,0x86,0x48,0x01,0x65,0x03,0x04,0x02,0x01};
static const uint8_t kOID_commonName[]           = {0x55,0x04,0x03};
static const uint8_t kOID_signedData[]           = {0x2a,0x86,0x48,0x86,0xf7,0x0d,0x01,0x07,0x02};
static const uint8_t kOID_data[]                 = {0x2a,0x86,0x48,0x86,0xf7,0x0d,0x01,0x07,0x01};

// ============================================================================
// 时间 / 摘要 / base64 工具
// ============================================================================

static NSData *SDR_FormattedTime(NSDate *d, NSString *format) {
    NSDateFormatter *f = [[NSDateFormatter alloc] init];
    f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    f.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    f.dateFormat = format;
    return [[f stringFromDate:d] dataUsingEncoding:NSASCIIStringEncoding];
}

static NSData *SDR_SHA256(NSData *d) {
    uint8_t md[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(d.bytes, (CC_LONG)d.length, md);
    return [NSData dataWithBytes:md length:CC_SHA256_DIGEST_LENGTH];
}

static NSString *SDR_Base64(NSData *d) {
    return [d base64EncodedStringWithOptions:0];
}

// ============================================================================
// 证书 / PKCS7 构造
// ============================================================================

static NSData *SDR_DER_Name(NSString *commonName) {
    // RDNSequence ::= SEQUENCE OF SET OF ATV；仅含一个 CN。
    NSData *atv = SDR_DER_TLV(0x30, SDR_DER_Join(@[SDR_DER_OID(kOID_commonName, sizeof(kOID_commonName)),
                                                   SDR_DER_UTF8(commonName)]));
    NSData *rdn = SDR_DER_Set(atv);
    return SDR_DER_Seq(rdn);
}

// 生成自签名 X.509 v3 证书（DER）。
static NSData *SDR_CreateSelfSignedCert(NSString *commonName, SecKeyRef privKey, SecKeyRef pubKey, NSError **error) {
    // 取公钥 PKCS#1 DER（RSAPublicKey SEQUENCE）
    CFErrorRef keyErr = NULL;
    NSData *pubDER = CFBridgingRelease(SecKeyCopyExternalRepresentation(pubKey, &keyErr));
    if (!pubDER) { if (error) *error = (__bridge_transfer NSError *)keyErr; return nil; }

    DataRow: ;
    // subjectPublicKeyInfo
    NSData *spkiAlg = SDR_DER_Seq(SDR_DER_Join(@[SDR_DER_OID(kOID_rsaEncryption, sizeof(kOID_rsaEncryption)), SDR_DER_Null()]));
    NSData *spki = SDR_DER_Seq(SDR_DER_Join(@[spkiAlg, SDR_DER_BitString(pubDER)]));
    (void)spkiAlg;

    // 名称（issuer = subject）
    NSData *name = SDR_DER_Name(commonName);

    // 有效期：notBefore 前一天，notAfter 30 年
    NSDate *notBefore = [[NSDate date] dateByAddingTimeInterval:-86400];
    NSDate *notAfter = [[NSDate date] dateByAddingTimeInterval:30 * 365.25 * 86400];
    NSData *validity = SDR_DER_Seq(SDR_DER_Join(@[
        SDR_DER_TLV(0x17, SDR_FormattedTime(notBefore, @"yyMMddHHmmss'Z'")),
        SDR_DER_TLV(0x18, SDR_FormattedTime(notAfter, @"yyyyMMddHHmmss'Z'"))
    ]));

    uint64_t serial = (((uint64_t)arc4random() << 32) | arc4random()) & 0x7FFFFFFFFFFFFFFFULL;
    serial |= 1;

    // TBS
    NSData *sigAlg = SDR_DER_Seq(SDR_DER_Join(@[SDR_DER_OID(kOID_sha256WithRSA, sizeof(kOID_sha256WithRSA)), SDR_DER_Null()]));
    NSData *tbs = SDR_DER_Seq(SDR_DER_Join(@[
        SDR_DER_Context(0, SDR_DER_Int(2)),       // version v3
        SDR_DER_Int(serial),
        sigAlg,
        name,
        validity,
        name,
        spki
    ]));

    // 签名 TBS
    CFErrorRef sigErr = NULL;
    NSData *tbsSig = CFBridgingRelease(SecKeyCreateSignature(privKey, kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA256,
                                                             (__bridge CFDataRef)tbs, &sigErr));
    if (!tbsSig) { if (error) *error = (__bridge_transfer NSError *)sigErr; return nil; }

    // Certificate
    return SDR_DER_Seq(SDR_DER_Join(@[tbs, sigAlg, SDR_DER_BitString(tbsSig)]));
}

// 构造 PKCS7 SignedData（无 signed attributes，签名覆盖 SF 内容）。
static NSData *SDR_BuildPKCS7(NSData *certDER, NSData *name, uint64_t serial, NSData *sfSig) {
    NSData *issuerAndSerial = SDR_DER_Seq(SDR_DER_Join(@[name, SDR_DER_Int(serial)]));
    NSData *sha256Alg = SDR_DER_Seq(SDR_DER_Join(@[SDR_DER_OID(kOID_sha256, sizeof(kOID_sha256)), SDR_DER_Null()]));
    NSData *sigAlg = SDR_DER_Seq(SDR_DER_Join(@[SDR_DER_OID(kOID_sha256WithRSA, sizeof(kOID_sha256WithRSA)), SDR_DER_Null()]));

    NSData *signerInfo = SDR_DER_Seq(SDR_DER_Join(@[
        SDR_DER_Int(1),
        issuerAndSerial,
        sha256Alg,
        sigAlg,
        SDR_DER_TLV(0x04, sfSig)
    ]));

    NSData *signedData = SDR_DER_Seq(SDR_DER_Join(@[
        SDR_DER_Int(1),                                   // version
        SDR_DER_Set(sha256Alg),                           // digestAlgorithms
        SDR_DER_Seq(SDR_DER_OID(kOID_data, sizeof(kOID_data))), // encapContentInfo
        SDR_DER_Context(0, certDER),                      // certificates [0]
        SDR_DER_Set(signerInfo)                           // signerInfos
    ]));

    return SDR_DER_Seq(SDR_DER_Join(@[
        SDR_DER_OID(kOID_signedData, sizeof(kOID_signedData)),
        SDR_DER_Context(0, signedData)
    ]));
}

// ============================================================================
// ZIP 写入（STORE 无压缩）
// ============================================================================

static void SDR_AppendLE16(NSMutableData *d, uint16_t v) {
    uint8_t b[2] = { v & 0xFF, (v >> 8) & 0xFF };
    [d appendBytes:b length:2];
}
static void SDR_AppendLE32(NSMutableData *d, uint32_t v) {
    uint8_t b[4] = { v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF };
    [d appendBytes:b length:4];
}

static uint32_t SDR_CRC32(NSData *d) {
    return (uint32_t)crc32(0L, Z_NULL, 0) ^ (uint32_t)crc32((uLong)crc32(0L, Z_NULL, 0), d.bytes, (uInt)d.length);
}

@interface SDRZipOutEntry : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) NSData *data;
@property (nonatomic, assign) uint32_t crc;
@property (nonatomic, assign) uint32_t offset;
@end

@implementation SDRZipOutEntry
+ (instancetype)entryWithName:(NSString *)name data:(NSData *)data crc:(uint32_t)crc {
    SDRZipOutEntry *e = [self new];
    e.name = name;
    e.data = data;
    e.crc = crc;
    e.offset = 0;
    return e;
}
@end

static NSData *SDR_WriteZip(NSArray<SDRZipOutEntry *> *entries) {
    NSMutableData *out = [NSMutableData data];
    NSMutableArray<SDRZipOutEntry *> *recs = [NSMutableArray array];
    uint32_t centralStart = 0;

    for (SDRZipOutEntry *e in entries) {
        uint32_t localOff = (uint32_t)out.length;
        NSData *nameData = [e.name dataUsingEncoding:NSUTF8StringEncoding];
        uint32_t crc = e.crc;
        uint32_t size = (uint32_t)e.data.length;

        NSMutableData *local = [NSMutableData data];
        SDR_AppendLE32(local, 0x04034b50);
        SDR_AppendLE16(local, 20);         // version needed
        SDR_AppendLE16(local, 0x0800);     // UTF-8 name flag
        SDR_AppendLE16(local, 0);          // STORE
        SDR_AppendLE16(local, 0);          // mod time
        SDR_AppendLE16(local, 0x0021);     // mod date = 1980-01-01
        SDR_AppendLE32(local, crc);
        SDR_AppendLE32(local, size);       // compressed
        SDR_AppendLE32(local, size);       // uncompressed
        SDR_AppendLE16(local, (uint16_t)nameData.length);
        SDR_AppendLE16(local, 0);          // extra
        [local appendData:nameData];
        [local appendData:e.data];
        [out appendData:local];

        e.offset = localOff;
        [recs addObject:e];
    }

    centralStart = (uint32_t)out.length;
    for (SDRZipOutEntry *e in recs) {
        NSData *nameData = [e.name dataUsingEncoding:NSUTF8StringEncoding];
        NSMutableData *central = [NSMutableData data];
        SDR_AppendLE32(central, 0x02014b50);
        SDR_AppendLE16(central, 20);         // version made by
        SDR_AppendLE16(central, 20);         // version needed
        SDR_AppendLE16(central, 0x0800);
        SDR_AppendLE16(central, 0);          // STORE
        SDR_AppendLE16(central, 0);
        SDR_AppendLE16(central, 0x0021);
        SDR_AppendLE32(central, e.crc);
        SDR_AppendLE32(central, (uint32_t)e.data.length);
        SDR_AppendLE32(central, (uint32_t)e.data.length);
        SDR_AppendLE16(central, (uint16_t)nameData.length);
        SDR_AppendLE16(central, 0);          // extra
        SDR_AppendLE16(central, 0);          // comment
        SDR_AppendLE16(central, 0);          // disk
        SDR_AppendLE16(central, 0);          // internal attrs
        SDR_AppendLE32(central, 0);          // external attrs
        SDR_AppendLE32(central, e.offset);
        [central appendData:nameData];
        [out appendData:central];
    }

    uint32_t centralSize = (uint32_t)(out.length - centralStart);
    uint32_t count = (uint32_t)recs.count;
    NSMutableData *eocd = [NSMutableData data];
    SDR_AppendLE32(eocd, 0x06054b50);
    SDR_AppendLE16(eocd, 0);
    SDR_AppendLE16(eocd, 0);
    SDR_AppendLE16(eocd, count);
    SDR_AppendLE16(eocd, count);
    SDR_AppendLE32(eocd, centralSize);
    SDR_AppendLE32(eocd, centralStart);
    SDR_AppendLE16(eocd, 0);
    [out appendData:eocd];

    return out;
}

// ============================================================================
// 签名器
// ============================================================================

@implementation SDRApkSigner

- (NSData *)resignApkData:(NSData *)apkData commonName:(NSString *)commonName error:(NSError **)error {
    NSError *zipErr = nil;
    SDRZipArchive *zip = [[SDRZipArchive alloc] initWithData:apkData error:&zipErr];
    if (!zip) { if (error) *error = zipErr; return nil; }

    // 1. 生成密钥对
    CFErrorRef keyErr = NULL;
    NSDictionary *attrs = @{
        (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeRSA,
        (__bridge id)kSecAttrKeySizeInBits: @2048,
        (__bridge id)kSecAttrIsPermanent: @NO
    };
    SecKeyRef privKey = SecKeyCreateRandomKey((__bridge CFDictionaryRef)attrs, &keyErr);
    if (!privKey) { if (error) *error = (__bridge_transfer NSError *)keyErr; return nil; }
    SecKeyRef pubKey = SecKeyCopyPublicKey(privKey);

    // 2. 自签名证书
    NSData *certDER = SDR_CreateSelfSignedCert(commonName, privKey, pubKey, error);
    if (!certDER) { CFRelease(privKey); CFRelease(pubKey); return nil; }
    NSData *nameDER = SDR_DER_Name(commonName);

    // 3. 待签名条目（排除目录与旧签名文件）
    NSMutableArray<SDRZipOutEntry *> *sigEntries = [NSMutableArray array];
    for (SDRZipEntry *e in zip.entries) {
        if (e.isDirectory) continue;
        if ([e.name hasPrefix:@"META-INF/"]) continue;
        NSData *data = [zip dataForEntry:e error:nil];
        if (!data) continue;
        SDRZipOutEntry *o = [SDRZipOutEntry entryWithName:e.name data:data crc:SDR_CRC32(data)];
        [sigEntries addObject:o];
    }
    // 按名排序，保证输出确定性
    [sigEntries sortUsingComparator:^NSComparisonResult(SDRZipOutEntry *a, SDRZipOutEntry *b) {
        return [a.name compare:b.name];
    }];

    // 4. 构造 MANIFEST.MF
    NSMutableData *mf = [NSMutableData data];
    [mf appendData:[@"Manifest-Version: 1.0\r\nCreated-By: 1.0 (StarDex-Run)\r\n\r\n"
                     dataUsingEncoding:NSASCIIStringEncoding]];
    NSMutableArray<NSData *> *mfSections = [NSMutableArray array];
    for (NSUInteger i = 0; i < sigEntries.count; i++) {
        SDRZipOutEntry *e = sigEntries[i];
        NSString *b64 = SDR_Base64(SDR_SHA256(e.data));
        NSData *section = [[NSString stringWithFormat:@"Name: %@\r\nSHA-256-Digest: %@\r\n", e.name, b64]
                           dataUsingEncoding:NSASCIIStringEncoding];
        [mfSections addObject:section];
        [mf appendData:section];
        if (i + 1 < sigEntries.count) [mf appendData:[@"\r\n" dataUsingEncoding:NSASCIIStringEncoding]];
    }

    // 5. 构造 CERT.SF
    NSMutableData *sf = [NSMutableData data];
    NSString *manifestDigest = SDR_Base64(SDR_SHA256(mf));
    [sf appendData:[[NSString stringWithFormat:@"Signature-Version: 1.0\r\nCreated-By: 1.0 (StarDex-Run)\r\nSHA-256-Digest-Manifest: %@\r\n\r\n", manifestDigest]
                    dataUsingEncoding:NSASCIIStringEncoding]];
    for (NSUInteger i = 0; i < sigEntries.count; i++) {
        SDRZipOutEntry *e = sigEntries[i];
        NSString *b64 = SDR_Base64(SDR_SHA256(mfSections[i]));
        [sf appendData:[[NSString stringWithFormat:@"Name: %@\r\nSHA-256-Digest: %@\r\n", e.name, b64]
                        dataUsingEncoding:NSASCIIStringEncoding]];
        if (i + 1 < sigEntries.count) [sf appendData:[@"\r\n" dataUsingEncoding:NSASCIIStringEncoding]];
    }

    // 6. 对 SF 签名，构造 CERT.RSA (PKCS7)
    CFErrorRef sfSigErr = NULL;
    NSData *sfSig = CFBridgingRelease(SecKeyCreateSignature(privKey, kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA256,
                                                            (__bridge CFDataRef)sf, &sfSigErr));
    if (!sfSig) { if (error) *error = (__bridge_transfer NSError *)sfSigErr; CFRelease(privKey); CFRelease(pubKey); return nil; }
    uint64_t serial = (((uint64_t)arc4random() << 32) | arc4random()) & 0x7FFFFFFFFFFFFFFFULL | 1;
    NSData *pkcs7 = SDR_BuildPKCS7(certDER, nameDER, serial, sfSig);

    CFRelease(privKey);
    CFRelease(pubKey);

    // 7. 组装输出条目
    NSMutableArray<SDRZipOutEntry *> *outEntries = [NSMutableArray array];
    for (SDRZipEntry *e in zip.entries) {
        if (e.isDirectory) continue;
        NSString *n = e.name;
        NSString *ext = [n pathExtension].uppercaseString;
        BOOL isOldSig = [n isEqualToString:@"META-INF/MANIFEST.MF"] ||
                        [ext isEqualToString:@"SF"] || [ext isEqualToString:@"RSA"] ||
                        [ext isEqualToString:@"DSA"] || [ext isEqualToString:@"EC"];
        if ([n hasPrefix:@"META-INF/"] && isOldSig) continue;
        NSData *data = [zip dataForEntry:e error:nil];
        if (!data) continue;
        SDRZipOutEntry *o = [SDRZipOutEntry entryWithName:n data:data crc:SDR_CRC32(data)];
        [outEntries addObject:o];
    }
    NSData *mfName = [@"META-INF/MANIFEST.MF" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *sfName = [@"META-INF/CERT.SF" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *rsaName = [@"META-INF/CERT.RSA" dataUsingEncoding:NSUTF8StringEncoding];
    SDRZipOutEntry *mfEntry = [SDRZipOutEntry entryWithName:@"META-INF/MANIFEST.MF" data:mf crc:SDR_CRC32(mf)];
    SDRZipOutEntry *sfEntry = [SDRZipOutEntry entryWithName:@"META-INF/CERT.SF" data:sf crc:SDR_CRC32(sf)];
    SDRZipOutEntry *rsaEntry = [SDRZipOutEntry entryWithName:@"META-INF/CERT.RSA" data:pkcs7 crc:SDR_CRC32(pkcs7)];
    (void)mfName; (void)sfName; (void)rsaName;
    [outEntries addObject:mfEntry];
    [outEntries addObject:sfEntry];
    [outEntries addObject:rsaEntry];
    [outEntries sortUsingComparator:^NSComparisonResult(SDRZipOutEntry *a, SDRZipOutEntry *b) {
        return [a.name compare:b.name];
    }];

    return SDR_WriteZip(outEntries);
}

@end