/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

#import "SDRSignatureVerifier.h"
#import "SDRZipArchive.h"
#import <CommonCrypto/CommonDigest.h>
#import <Security/Security.h>

// ============================================================================
// 结果模型实现
// ============================================================================

@implementation SDRApkCertificateInfo
@end

@implementation SDRApkSignatureResult
@end

// ============================================================================
// 摘要工具
// ============================================================================

static NSData *SDR_SHA1(NSData *d) {
    uint8_t md[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(d.bytes, (CC_LONG)d.length, md);
    return [NSData dataWithBytes:md length:CC_SHA1_DIGEST_LENGTH];
}
static NSData *SDR_SHA256(NSData *d) {
    uint8_t md[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(d.bytes, (CC_LONG)d.length, md);
    return [NSData dataWithBytes:md length:CC_SHA256_DIGEST_LENGTH];
}
static NSData *SDR_Digest(NSData *d, BOOL sha256) { return sha256 ? SDR_SHA256(d) : SDR_SHA1(d); }

static NSData *SDRBase64Decode(NSString *s) {
    return [[NSData alloc] initWithBase64EncodedString:[s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
                                               options:NSDataBase64DecodingIgnoreUnknownCharacters];
}
static BOOL SDRBytesEqual(NSData *a, NSData *b) {
    if (!a || !b) return NO;
    return a.length == b.length && (a.length == 0 || memcmp(a.bytes, b.bytes, a.length) == 0);
}

// ============================================================================
// MANIFEST / SF 文本解析（按“段落”切分，保留原始字节用于摘要）
// ============================================================================

// 返回每个非空段落（连续非空物理行）的原始字节，含行终止符、不含空行分隔。
static NSArray<NSData *> *SDR_SplitParagraphs(NSData *raw) {
    const uint8_t *p = raw.bytes;
    NSUInteger len = raw.length, i = 0;
    NSMutableArray<NSData *> *result = [NSMutableArray array];
    NSMutableData *cur = [NSMutableData data];

    while (i < len) {
        NSUInteger lineEnd = i;
        uint8_t term = 0;
        while (lineEnd < len) {
            if (p[lineEnd] == '\n') { term = 1; break; }
            if (p[lineEnd] == '\r' && lineEnd + 1 < len && p[lineEnd + 1] == '\n') { term = 2; break; }
            lineEnd++;
        }
        NSUInteger contentLen = lineEnd - i;
        BOOL blank = (contentLen == 0) || (contentLen == 1 && p[i] == '\r');

        if (blank) {
            if (cur.length) [result addObject:[cur copy]];
            cur.length = 0;
        } else {
            NSUInteger segLen = (lineEnd - i) + term;
            [cur appendBytes:p + i length:segLen];
        }

        if (term == 0) break;
        i = lineEnd + term;
    }
    if (cur.length) [result addObject:[cur copy]];
    return result;
}

// 解析段落为 key->value（处理 72 字节折行：续行以单个空格开头）。
static NSDictionary<NSString *, NSString *> *SDR_ParseSectionAttributes(NSData *paragraph) {
    NSString *text = [[NSString alloc] initWithData:paragraph encoding:NSUTF8StringEncoding];
    if (!text) return @{};
    NSArray<NSString *> *physical = [text componentsSeparatedByString:@"\n"];
    NSMutableArray<NSString *> *logical = [NSMutableArray array];
    for (NSString *line in physical) {
        NSString *l = ([line hasSuffix:@"\r"]) ? [line substringToIndex:line.length - 1] : line;
        if ([l hasPrefix:@" "] && logical.count) {
            logical[logical.count - 1] = [logical.lastObject stringByAppendingString:[l substringFromIndex:1]];
        } else if (l.length) {
            [logical addObject:l];
        }
    }
    NSMutableDictionary<NSString *, NSString *> *out = [NSMutableDictionary dictionary];
    for (NSString *l in logical) {
        NSRange colon = [l rangeOfString:@":"];
        if (colon.location == NSNotFound) continue;
        NSString *key = [l substringToIndex:colon.location];
        NSString *val = [[l substringFromIndex:colon.location + 1]
                         stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        out[key] = val;
    }
    return out;
}

// ============================================================================
// 最小 DER 解析（提取 PKCS7 签名值与 signed attributes）
// ============================================================================

static BOOL SDR_DER_TLV(const uint8_t *p, NSUInteger len, NSUInteger off,
                        NSUInteger *tagOut, NSUInteger *valOff, NSUInteger *valLen, NSUInteger *next) {
    if (off >= len) return NO;
    NSUInteger pos = off;
    NSUInteger tag = p[pos++];
    if (pos >= len) return NO;
    uint8_t l0 = p[pos++];
    NSUInteger l;
    if (l0 < 0x80) {
        l = l0;
    } else if (l0 == 0x80) {
        return NO;
    } else {
        NSUInteger n = l0 & 0x7F;
        if (n > 4 || pos + n > len) return NO;
        l = 0;
        for (NSUInteger i = 0; i < n; i++) l = (l << 8) | p[pos++];
    }
    if (pos + l > len) return NO;
    *tagOut = tag; *valOff = pos; *valLen = l; *next = pos + l;
    return YES;
}

static void SDR_DER_ForEachChild(const uint8_t *p, NSUInteger valOff, NSUInteger valLen,
                                 void (^blk)(NSUInteger tag, NSUInteger vOff, NSUInteger vLen, NSUInteger next)) {
    NSUInteger off = valOff, end = valOff + valLen;
    while (off < end) {
        NSUInteger tag, vOff, vLen, next;
        if (!SDR_DER_TLV(p, end, off, &tag, &vOff, &vLen, &next)) break;
        blk(tag, vOff, vLen, next);
        off = next;
    }
}

static BOOL SDR_OID_Match(const uint8_t *p, NSUInteger off, NSUInteger len, const uint8_t *oid, NSUInteger oidLen) {
    return len == oidLen && memcmp(p + off, oid, oidLen) == 0;
}
static const uint8_t kOID_SHA1[]      = {0x2b,0x0e,0x03,0x02,0x1a};
static const uint8_t kOID_SHA256[]    = {0x60,0x86,0x48,0x01,0x65,0x03,0x04,0x02,0x01};
static const uint8_t kOID_MsgDigest[] = {0x2a,0x86,0x48,0x86,0xf7,0x0d,0x01,0x09,0x04};

// 从 PKCS7 提取签名值、signedAttrs（重打 0x31 标签）、messageDigest，并判定摘要算法。
static void SDR_ExtractPKCS7Signer(NSData *pkcs7,
                                   NSData **sigOut,
                                   NSData **signedAttrsSetOut,
                                   NSData **msgDigestOut,
                                   BOOL *isSHA256) {
    const uint8_t *p = pkcs7.bytes;
    NSUInteger len = pkcs7.length;

    NSUInteger tag, vOff, vLen, next;
    if (!SDR_DER_TLV(p, len, 0, &tag, &vOff, &vLen, &next)) return; // ContentInfo

    // ContentInfo → [A0] SignedData
    __block NSUInteger sdOff = 0, sdLen = 0;
    SDR_DER_ForEachChild(p, vOff, vLen, ^(NSUInteger t, NSUInteger vo, NSUInteger vl, NSUInteger nx) {
        if (t == 0xA0) { sdOff = vo; sdLen = vl; }
    });
    if (!sdLen) return;

    // [A0] 的内容是一个 SignedData SEQUENCE
    NSUInteger sdtag, sdvOff, sdvLen, sdnext;
    if (!SDR_DER_TLV(p, len, sdOff, &sdtag, &sdvOff, &sdvLen, &sdnext)) return;

    // SignedData → 找 signerInfos SET(0x31)
    __block NSUInteger siOff = 0, siLen = 0;
    SDR_DER_ForEachChild(p, sdvOff, sdvLen, ^(NSUInteger t, NSUInteger vo, NSUInteger vl, NSUInteger nx) {
        if (t == 0x31) { siOff = vo; siLen = vl; }
    });
    if (!siLen) return;

    // signerInfos SET → 第一个 SignerInfo SEQUENCE
    NSUInteger sitag, sivOff, sivLen, sinext;
    if (!SDR_DER_TLV(p, len, siOff, &sitag, &sivOff, &sivLen, &sinext)) return;

    __block NSUInteger sigVal = 0, sigLen = 0, sattrsVal = 0, sattrsLen = 0, dgstAlgOff = 0, dgstAlgLen = 0;
    SDR_DER_ForEachChild(p, sivOff, sivLen, ^(NSUInteger t, NSUInteger vo, NSUInteger vl, NSUInteger nx) {
        if (t == 0x04) { sigVal = vo; sigLen = vl; }
        else if (t == 0xA0) { sattrsVal = vo; sattrsLen = vl; }
        else if (t == 0x30 && dgstAlgLen == 0) {
            // 区分 signerId 与 digestAlgorithm：后者第一子节点是 OID
            NSUInteger subTag, subOff, subLen, subNext;
            if (SDR_DER_TLV(p, len, vo, &subTag, &subOff, &subLen, &subNext) && subTag == 0x06) {
                dgstAlgOff = subOff; dgstAlgLen = subLen;
            }
        }
    });

    if (sigLen) *sigOut = [NSData dataWithBytes:p + sigVal length:sigLen];

    if (dgstAlgLen) {
        if (SDR_OID_Match(p, dgstAlgOff, dgstAlgLen, kOID_SHA256, sizeof(kOID_SHA256))) *isSHA256 = YES;
        else if (SDR_OID_Match(p, dgstAlgOff, dgstAlgLen, kOID_SHA1, sizeof(kOID_SHA1))) *isSHA256 = NO;
    }

    if (sattrsLen) {
        // signedAttrs = A0{ SET OF Attributes }；验签需重打为 0x31 SET。
        NSUInteger setLen = sattrsLen;
        NSMutableData *set = [NSMutableData data];
        uint8_t tagByte = 0x31;
        [set appendBytes:&tagByte length:1];
        // 长形式长度编码
        if (setLen < 0x80) {
            uint8_t lb = (uint8_t)setLen;
            [set appendBytes:&lb length:1];
        } else {
            uint8_t cnt = 0; NSUInteger t = setLen; uint8_t tmp[4];
            while (t) { tmp[cnt++] = t & 0xFF; t >>= 8; }
            [set appendBytes:(uint8_t[]){0x80 | cnt} length:1];
            for (int k = cnt - 1; k >= 0; k--) { uint8_t b = tmp[k]; [set appendBytes:&b length:1]; }
        }
        [set appendBytes:p + sattrsVal length:setLen];
        *signedAttrsSetOut = set;

        // 提取 messageDigest（属性 OID = 1.2.840.113549.1.9.4）
        __block NSData *md = nil;
        SDR_DER_ForEachChild(p, sattrsVal, sattrsLen, ^(NSUInteger t, NSUInteger vo, NSUInteger vl, NSUInteger nx) {
            if (t != 0x30 || md) return;
            // Attribute SEQUENCE：OID + SET；先判定 OID
            NSUInteger oidTag, oidOff, oidLen, oidNext;
            if (SDR_DER_TLV(p, len, vo, &oidTag, &oidOff, &oidLen, &oidNext)) {
                NSUInteger oPartTag, oPartOff, oPartLen, oPartNext;
                if (SDR_DER_TLV(p, len, oidOff, &oPartTag, &oPartOff, &oPartLen, &oPartNext) &&
                    oPartTag == 0x06 && SDR_OID_Match(p, oPartOff, oPartLen, kOID_MsgDigest, sizeof(kOID_MsgDigest))) {
                    // 该属性的 values SET 里的 OCTET STRING 即 messageDigest
                    __block NSData *found = nil;
                    SDR_DER_ForEachChild(p, vo, vl, ^(NSUInteger at2, NSUInteger avo2, NSUInteger avl2, NSUInteger anx2) {
                        if (at2 == 0x31 && !found) {
                            NSUInteger vtag, vvo, vvl, vnx;
                            if (SDR_DER_TLV(p, len, avo2, &vtag, &vvo, &vvl, &vnx) && vtag == 0x04) {
                                found = [NSData dataWithBytes:p + vvo length:vvl];
                            }
                        }
                    });
                    md = found;
                }
            }
        });
        *msgDigestOut = md;
    }
}

// 从 PKCS7 提取全部证书 DER（利用 SecCertificateCreateWithData 识别）。
static NSArray<NSData *> *SDR_ExtractCertificates(NSData *pkcs7) {
    NSMutableArray<NSData *> *out = [NSMutableArray array];
    const uint8_t *p = pkcs7.bytes;
    NSUInteger len = pkcs7.length;
    for (NSUInteger i = 0; i + 4 <= len; i++) {
        if (p[i] != 0x30 || p[i+1] != 0x82) continue;
        NSUInteger certLen = ((NSUInteger)p[i+2] << 8) | p[i+3];
        NSUInteger total = certLen + 4;
        if (i + total > len) continue;
        NSData *candidate = [NSData dataWithBytes:p + i length:total];
        SecCertificateRef cert = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)candidate);
        if (cert) { [out addObject:candidate]; CFRelease(cert); }
    }
    return out;
}

// ============================================================================
// 校验器
// ============================================================================

@implementation SDRSignatureVerifier {
    NSData *_apkData;
    SDRZipArchive *_zip;
    NSData *_certificateForVerify; // 签名者证书 DER（供 RSA 验签）
}

- (SDRApkSignatureResult *)verifyApkData:(NSData *)apkData error:(NSError **)error {
    _apkData = apkData;
    _zip = [[SDRZipArchive alloc] initWithData:apkData error:error];
    if (!_zip) return nil;

    SDRApkSignatureResult *res = [SDRApkSignatureResult new];
    res.certificates = @[];

    // 1. V2/V3 方案检测（APK Signing Block 魔术）
    res.schemes = [self detectSchemeMagics];

    // 2. V1 校验
    NSArray<NSString *> *sfFiles = [self signatureBlockFiles];
    if (sfFiles.count == 0) {
        res.v1DigestIntegrity = NO;
        res.v1SignatureVerified = NO;
    } else {
        res.schemes |= SDRApkSchemeV1;
        res.isSigned = YES;
        [self verifyV1:res sfFile:sfFiles.firstObject];
    }

    if (res.schemes & (SDRApkSchemeV2 | SDRApkSchemeV3)) res.isSigned = YES;

    [self summarize:res];
    return res;
}

- (void)summarize:(SDRApkSignatureResult *)res {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (res.schemes == 0) {
        [parts addObject:@"未签名"];
    } else {
        NSMutableArray<NSString *> *s = [NSMutableArray array];
        if (res.schemes & SDRApkSchemeV1) [s addObject:@"V1"];
        if (res.schemes & SDRApkSchemeV2) [s addObject:@"V2"];
        if (res.schemes & SDRApkSchemeV3) [s addObject:@"V3"];
        [parts addObject:[NSString stringWithFormat:@"签名方案:%@", [s componentsJoinedByString:@"/"]]];
    }
    if (res.certificates.count) {
        SDRApkCertificateInfo *c = res.certificates.firstObject;
        if (!c.withinValidityPeriod) [parts addObject:@"证书已过期或未生效"];
        else [parts addObject:[NSString stringWithFormat:@"证书:%@", c.commonName ?: @"(未知)"]];
    }
    if (res.schemes & SDRApkSchemeV1) {
        [parts addObject:res.v1DigestIntegrity ? @"摘要链完整" : @"摘要链失败(被篡改)"];
        if (res.v1SignatureVerified) [parts addObject:@"RSA签名通过"];
    }
    res.summaryMessage = [parts componentsJoinedByString:@"; "];
}

- (SDRApkSignedScheme)detectSchemeMagics {
    SDRApkSignedScheme schemes = 0;
    const uint8_t *p = _apkData.bytes;
    NSUInteger len = _apkData.length;
    for (NSUInteger i = 0; i + 4 <= len; i++) {
        uint32_t m = (uint32_t)p[i] | ((uint32_t)p[i+1] << 8) | ((uint32_t)p[i+2] << 16) | ((uint32_t)p[i+3] << 24);
        if (m == 0x7109871a) schemes |= SDRApkSchemeV2;
        else if (m == 0xf05368c0) schemes |= SDRApkSchemeV3;
    }
    return schemes;
}

- (NSArray<NSString *> *)signatureBlockFiles {
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    for (SDRZipEntry *e in _zip.entries) {
        NSString *n = e.name;
        NSString *ext = [n pathExtension].uppercaseString;
        if ([n hasPrefix:@"META-INF/"] &&
            ([ext isEqualToString:@"RSA"] || [ext isEqualToString:@"DSA"] || [ext isEqualToString:@"EC"])) {
            [out addObject:n];
        }
    }
    return out;
}

- (void)verifyV1:(SDRApkSignatureResult *)res sfFile:(NSString *)sfFile {
    NSData *mf = [_zip dataForEntryNamed:@"META-INF/MANIFEST.MF" error:nil];
    NSData *sf = [_zip dataForEntryNamed:sfFile error:nil];
    // 签名块与 SF 同名、不同扩展名（*.RSA/.DSA/.EC）
    NSString *base = [sfFile stringByDeletingPathExtension];
    NSData *pkcs7 = nil;
    for (SDRZipEntry *e in _zip.entries) {
        if ([[e.name stringByDeletingPathExtension] isEqualToString:base] &&
            ![e.name isEqualToString:sfFile] && [e.name hasPrefix:@"META-INF/"]) {
            pkcs7 = [_zip dataForEntry:e error:nil];
            break;
        }
    }

    if (pkcs7) res.certificates = [self parseCertificates:pkcs7];

    if (!mf || !sf) return;

    NSArray<NSData *> *mfParas = SDR_SplitParagraphs(mf);
    NSArray<NSData *> *sfParas = SDR_SplitParagraphs(sf);
    if (mfParas.count == 0 || sfParas.count == 0) return;

    NSDictionary<NSString *, NSString *> *sfMain = SDR_ParseSectionAttributes(sfParas.firstObject);
    BOOL sha256 = sfMain[@"SHA-256-Digest-Manifest"] != nil || sfMain[@"SHA-256-Digest"] != nil;
    NSString *algo = sha256 ? @"SHA-256-Digest" : @"SHA1-Digest";

    BOOL ok = YES;

    // 摘要链 1：zip 条目 → MANIFEST.MF
    for (NSUInteger i = 1; i < mfParas.count; i++) {
        NSDictionary *a = SDR_ParseSectionAttributes(mfParas[i]);
        NSString *name = a[@"Name"];
        NSString *ds = a[algo] ?: a[@"SHA1-Digest"];
        if (!name || !ds) continue;
        NSData *entryData = [_zip dataForEntryNamed:name error:nil];
        NSData *expected = SDRBase64Decode(ds);
        if (entryData && !SDRBytesEqual(expected, SDR_Digest(entryData, sha256))) ok = NO;
    }

    // 摘要链 2：MANIFEST.MF 段落 → SF 每条目摘要
    NSMutableDictionary<NSString *, NSData *> *mfSections = [NSMutableDictionary dictionary];
    for (NSUInteger i = 1; i < mfParas.count; i++) {
        NSDictionary *a = SDR_ParseSectionAttributes(mfParas[i]);
        if (a[@"Name"]) mfSections[a[@"Name"]] = mfParas[i];
    }
    for (NSUInteger i = 1; i < sfParas.count; i++) {
        NSDictionary *a = SDR_ParseSectionAttributes(sfParas[i]);
        NSString *name = a[@"Name"];
        NSString *ds = a[algo] ?: a[@"SHA1-Digest"];
        if (!name || !ds) continue;
        NSData *mfSection = mfSections[name];
        NSData *expected = SDRBase64Decode(ds);
        if (mfSection && !SDRBytesEqual(expected, SDR_Digest(mfSection, sha256))) ok = NO;
    }

    // 摘要链 3：整个 MANIFEST.MF → SF 主属性 Digest-Manifest
    NSString *manifestDigestStr = sfMain[@"SHA-256-Digest-Manifest"] ?: sfMain[@"SHA1-Digest-Manifest"];
    if (manifestDigestStr) {
        NSData *expected = SDRBase64Decode(manifestDigestStr);
        NSData *actual = sfMain[@"SHA-256-Digest-Manifest"] ? SDR_SHA256(mf) : SDR_SHA1(mf);
        if (!SDRBytesEqual(expected, actual)) ok = NO;
    }

    res.v1DigestIntegrity = ok;

    // RSA 签名验证（最佳努力，覆盖多数 JAR/APK 签名）
    res.v1SignatureVerified = NO;
    if (pkcs7 && res.certificates.count) {
        res.v1SignatureVerified = [self verifyRSA:pkcs7 sfContent:sf sha256:sha256];
    }
}

- (BOOL)verifyRSA:(NSData *)pkcs7 sfContent:(NSData *)sf sha256:(BOOL)sha256 {
    NSData *sig = nil, *sattrs = nil, *msgDigest = nil;
    BOOL sigSha256 = sha256;
    SDR_ExtractPKCS7Signer(pkcs7, &sig, &sattrs, &msgDigest, &sigSha256);
    if (!sig) return NO;

    NSData *signedBytes = nil;
    if (sattrs) {
        // 存在 signed attributes：待验签数据 = SET(0x31 重标注)
        signedBytes = sattrs;
        // 校验 messageDigest 是否等于 SF 内容摘要
        if (msgDigest && !SDRBytesEqual(msgDigest, SDR_Digest(sf, sigSha256))) return NO;
    } else {
        signedBytes = sf;
    }

    SecCertificateRef cert = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)_certificateForVerify);
    if (!cert) return NO;
    SecKeyRef pubKey = SecCertificateCopyPublicKey(cert);
    if (!pubKey) { CFRelease(cert); return NO; }

    CFStringRef algorithm = sigSha256 ? kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA256
                                      : kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA1;
    CFErrorRef err = NULL;
    BOOL verified = SecKeyVerifySignature(pubKey, algorithm,
                                          (__bridge CFDataRef)signedBytes,
                                          (__bridge CFDataRef)sig, &err);
    if (err) CFRelease(err);
    CFRelease(pubKey);
    CFRelease(cert);
    return verified;
}

- (NSArray<SDRApkCertificateInfo *> *)parseCertificates:(NSData *)pkcs7 {
    NSArray<NSData *> *ders = SDR_ExtractCertificates(pkcs7);
    NSMutableArray<SDRApkCertificateInfo *> *out = [NSMutableArray array];
    for (NSData *d in ders) {
        SDRApkCertificateInfo *info = [self parseCertificate:d];
        if (info) [out addObject:info];
    }
    return out;
}

- (SDRApkCertificateInfo *)parseCertificate:(NSData *)certDER {
    SecCertificateRef cert = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)certDER);
    if (!cert) return nil;

    SDRApkCertificateInfo *info = [SDRApkCertificateInfo new];
    info.commonName = CFBridgingRelease(SecCertificateCopySubjectSummary(cert));

    // 序列号（iOS 11+）
    CFErrorRef serr = NULL;
    NSData *serial = CFBridgingRelease(SecCertificateCopySerialNumberData(cert, &serr));
    if (serr) CFRelease(serr);
    if (serial) info.serialNumber = [serial description];

    // 有效期：iOS 18+ 提供公开 API；更低版本无法便捷获取，跳过并视为有效。
    if (@available(iOS 18.0, *)) {
        CFDateRef nb = SecCertificateCopyNotValidBeforeDate(cert);
        CFDateRef na = SecCertificateCopyNotValidAfterDate(cert);
        if (nb) info.notBefore = CFBridgingRelease(nb);
        if (na) info.notAfter = CFBridgingRelease(na);
    }

    NSDate *now = [NSDate date];
    if (info.notBefore && info.notAfter) {
        info.withinValidityPeriod = ([now compare:info.notBefore] != NSOrderedAscending &&
                                      [now compare:info.notAfter] != NSOrderedDescending);
    } else if (info.notAfter) {
        info.withinValidityPeriod = ([now compare:info.notAfter] != NSOrderedDescending);
    } else if (info.notBefore) {
        info.withinValidityPeriod = ([now compare:info.notBefore] != NSOrderedAscending);
    } else {
        info.withinValidityPeriod = YES;
    }

    // 缓存首个证书 DER 供 RSA 验签使用
    if (!_certificateForVerify) _certificateForVerify = [certDER copy];

    CFRelease(cert);
    return info;
}

- (NSDate *)dateFromValues:(id)v {
    if ([v isKindOfClass:[NSDictionary class]]) return ((NSDictionary *)v)[(__bridge id)kSecPropertyKeyValue];
    return nil;
}
- (NSString *)dnString:(id)v {
    if ([v isKindOfClass:[NSDictionary class]]) {
        id value = ((NSDictionary *)v)[(__bridge id)kSecPropertyKeyValue];
        if ([value isKindOfClass:[NSDictionary class]]) return [value description];
    }
    return @"";
}
- (NSString *)cnFromValues:(id)v {
    if ([v isKindOfClass:[NSDictionary class]]) {
        id value = ((NSDictionary *)v)[(__bridge id)kSecPropertyKeyValue];
        if ([value isKindOfClass:[NSDictionary class]]) {
            NSArray *cns = value[(__bridge id)kSecOIDCommonName];
            if ([cns isKindOfClass:[NSArray class]] && cns.count) return cns.firstObject;
        }
    }
    return @"";
}
- (NSString *)serialString:(id)v {
    if ([v isKindOfClass:[NSDictionary class]]) {
        id value = ((NSDictionary *)v)[(__bridge id)kSecPropertyKeyValue];
        if ([value isKindOfClass:[NSNumber class]]) {
            return [NSString stringWithFormat:@"0x%llx", ((NSNumber *)value).unsignedLongLongValue];
        }
        if ([value isKindOfClass:[NSData class]]) return [value description];
    }
    return @"";
}

@end