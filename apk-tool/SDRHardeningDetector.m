/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

#import "SDRHardeningDetector.h"

// 文件/条目名特征（命中即判定对应加固）。
static NSDictionary<NSString *, NSArray<NSString *> *> *SDRFileSignatures(void) {
    static NSDictionary *dict;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dict = @{
            @"360加固":      @[@"libjiagu.so", @"libjiagu_art.so", @"libjiagu_x86.so",
                               @"libjiagu_a64.so", @"jiagu/"],
            @"腾讯乐固":     @[@"libshellx-", @"libshella-", @"libtprt.so", @"libBugly.so",
                               @"legu", @"libShell.so"],
            @"爱加密":       @[@"libexec.so", @"libexecmain.so", @"ijiami.dat", @"ijiami"],
            @"梆梆加固":     @[@"libsecexe.so", @"libSecShell.so", @"libDexHelper.so",
                               @"SecShell", @"secexe"],
            @"百度加固":     @[@"libbaiduprotect.so", @"baiduprotect"],
            @"娜迦加固":     @[@"libprotectClass.so", @"libnesec.so", @"naga"],
            @"爱加密(兼容)":  @[@"libexec64.so"],
        };
    });
    return dict;
}

// 字节流特征（在原始 APK 数据中做子串匹配）。
static NSDictionary<NSString *, NSArray<NSString *> *> *SDRByteSignatures(void) {
    static NSDictionary *dict;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dict = @{
            @"360加固": @[@"libjiagu", @"jiagu_art", @"qihoo360"],
            @"腾讯乐固": @[@"libshell", @"libtprt", @"legu", @"TencentProtect"],
            @"爱加密": @[@"ijiami", @"libexecmain"],
            @"梆梆加固": @[@"libsecexe", @"SecShell", @"bangcle"],
            @"百度加固": @[@"libbaiduprotect"],
        };
    });
    return dict;
}

@implementation SDRHardeningDetector

- (nullable NSString *)detectInRawData:(NSData *)apkData {
    for (NSString *name in SDRByteSignatures()) {
        for (NSString *sig in SDRByteSignatures()[name]) {
            NSData *needle = [sig dataUsingEncoding:NSASCIIStringEncoding];
            if ([self data:apkData containsData:needle]) {
                return name;
            }
        }
    }
    return nil;
}

- (nullable NSString *)detectInEntryNames:(NSArray<NSString *> *)entryNames {
    NSDictionary<NSString *, NSArray<NSString *> *> *sigs = SDRFileSignatures();
    for (NSString *name in sigs) {
        for (NSString *sig in sigs[name]) {
            BOOL prefixStyle = [sig hasSuffix:@"/"] || [sig hasSuffix:@"-"];
            for (NSString *entry in entryNames) {
                NSString *base = [entry lastPathComponent];
                if (prefixStyle) {
                    if ([entry hasPrefix:sig]) return name;
                } else {
                    if ([base isEqualToString:sig] || [entry containsString:sig]) return name;
                }
            }
        }
    }
    return nil;
}

- (nullable NSString *)detect:(NSData *)apkData entryNames:(NSArray<NSString *> *)entryNames {
    NSString *byName = [self detectInEntryNames:entryNames];
    if (byName) return byName;
    return [self detectInRawData:apkData];
}

- (BOOL)data:(NSData *)haystack containsData:(NSData *)needle {
    if (needle.length == 0 || haystack.length < needle.length) return NO;
    const uint8_t *h = haystack.bytes;
    const uint8_t *n = needle.bytes;
    NSUInteger hl = haystack.length, nl = needle.length;
    for (NSUInteger i = 0; i + nl <= hl; i++) {
        if (memcmp(h + i, n, nl) == 0) return YES;
    }
    return NO;
}

@end