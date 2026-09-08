/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

#import "SDRZipArchive.h"
#import <zlib.h>

#define SDRZIP_EOCD_SIG         0x06054b50
#define SDRZIP_CENTRAL_SIG      0x02014b50
#define SDRZIP_LOCAL_SIG        0x04034b50

@implementation SDRZipEntry
- (BOOL)isDirectory {
    return [self.name hasSuffix:@"/"];
}
@end

@implementation SDRZipArchive

- (instancetype)initWithData:(NSData *)data error:(NSError **)error {
    if (self = [super init]) {
        _data = data;
        if (![self parseCentralDirectory:error]) {
            return nil;
        }
    }
    return self;
}

#pragma mark - 读取工具

// reader: 返回读取 count 字节失败时的定长结果（带越界保护）
- (uint16_t)u2:(const uint8_t *)p {
    return (uint16_t)(p[0] | (p[1] << 8));
}
- (uint32_t)u4:(const uint8_t *)p {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

// 从尾部反向查找 EOCD 签名。
- (NSRange)locateEOCD:(NSError **)error {
    const uint8_t *base = (const uint8_t *)_data.bytes;
    NSUInteger len = _data.length;
    NSUInteger minLen = 22;
    NSUInteger searchLen = len > 65557 ? 65557 : len;  // EOCD + 注释最大 64K
    if (searchLen < minLen) {
        if (error) *error = [NSError errorWithDomain:@"SDRZipArchive" code:1
            userInfo:@{NSLocalizedDescriptionKey: @"数据过短，非有效 ZIP"}];
        return NSMakeRange(NSNotFound, 0);
    }
    NSUInteger start = len - searchLen;
    for (NSUInteger i = len - minLen; ; i--) {
        if (i < start) break;
        if ([self u4:base + i] == SDRZIP_EOCD_SIG) {
            // 校验注释长度与 EOCD 长度匹配
            uint16_t commentLen = [self u2:base + i + 20];
            if (i + 22 + commentLen == len) {
                return NSMakeRange(i, 22 + commentLen);
            }
        }
    }
    if (error) *error = [NSError errorWithDomain:@"SDRZipArchive" code:2
        userInfo:@{NSLocalizedDescriptionKey: @"未找到 ZIP 结束记录"}];
    return NSMakeRange(NSNotFound, 0);
}

- (BOOL)parseCentralDirectory:(NSError **)error {
    NSRange eocdRange = [self locateEOCD:error];
    if (eocdRange.location == NSNotFound) return NO;

    const uint8_t *base = (const uint8_t *)_data.bytes;
    const uint8_t *eocd = base + eocdRange.location;
    uint32_t entryCount = [self u4:eocd + 10];
    uint32_t centralOff = [self u4:eocd + 16];

    if (centralOff + 4 > _data.length) {
        if (error) *error = [NSError errorWithDomain:@"SDRZipArchive" code:3
            userInfo:@{NSLocalizedDescriptionKey: @"中心目录偏移越界"}];
        return NO;
    }

    NSMutableArray<SDRZipEntry *> *entries = [NSMutableArray arrayWithCapacity:entryCount];
    uint32_t off = centralOff;
    for (uint32_t i = 0; i < entryCount; i++) {
        if (off + 46 > _data.length) break;
        const uint8_t *rec = base + off;
        if ([self u4:rec] != SDRZIP_CENTRAL_SIG) break;
        uint16_t method = [self u2:rec + 10];
        uint32_t crc = [self u4:rec + 16];
        uint32_t compSize = [self u4:rec + 20];
        uint32_t uncompSize = [self u4:rec + 24];
        uint16_t nameLen = [self u2:rec + 28];
        uint16_t extraLen = [self u2:rec + 30];
        uint16_t commentLen = [self u2:rec + 32];
        uint32_t localOff = [self u4:rec + 42];

        if (off + 46 + nameLen > _data.length) break;
        NSString *name = [[NSString alloc] initWithBytes:rec + 46 length:nameLen
                                                encoding:NSUTF8StringEncoding];
        if (!name) name = @"";

        SDRZipEntry *e = [SDRZipEntry new];
        e.name = name;
        e.method = (SDRZipMethod)method;
        e.crc32 = crc;
        e.compressedSize = compSize;
        e.uncompressedSize = uncompSize;
        e.localHeaderOffset = localOff;
        [entries addObject:e];

        off += 46 + nameLen + extraLen + commentLen;
    }
    _entries = entries;
    return YES;
}

- (SDRZipEntry *)entryNamed:(NSString *)name {
    for (SDRZipEntry *e in _entries) {
        if ([e.name isEqualToString:name]) return e;
    }
    return nil;
}

- (NSArray<SDRZipEntry *> *)entriesWithPrefix:(NSString *)prefix {
    NSMutableArray<SDRZipEntry *> *out = [NSMutableArray array];
    for (SDRZipEntry *e in _entries) {
        if ([e.name hasPrefix:prefix]) [out addObject:e];
    }
    return out;
}

- (NSData *)dataForEntryNamed:(NSString *)name error:(NSError **)error {
    SDRZipEntry *e = [self entryNamed:name];
    if (!e) {
        if (error) *error = [NSError errorWithDomain:@"SDRZipArchive" code:4
            userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"条目不存在: %@", name]}];
        return nil;
    }
    return [self dataForEntry:e error:error];
}

- (NSData *)dataForEntry:(SDRZipEntry *)entry error:(NSError **)error {
    const uint8_t *base = (const uint8_t *)_data.bytes;
    uint32_t off = entry.localHeaderOffset;
    if (off + 30 > _data.length) {
        if (error) *error = [NSError errorWithDomain:@"SDRZipArchive" code:5
            userInfo:@{NSLocalizedDescriptionKey: @"本地文件头越界"}];
        return nil;
    }
    const uint8_t *lh = base + off;
    if ([self u4:lh] != SDRZIP_LOCAL_SIG) {
        if (error) *error = [NSError errorWithDomain:@"SDRZipArchive" code:6
            userInfo:@{NSLocalizedDescriptionKey: @"本地文件头签名错误"}];
        return nil;
    }
    uint16_t nameLen = [self u2:lh + 26];
    uint16_t extraLen = [self u2:lh + 28];
    uint32_t dataOff = off + 30 + nameLen + extraLen;
    uint32_t compSize = entry.compressedSize;
    uint32_t uncompSize = entry.uncompressedSize;

    if (dataOff + compSize > _data.length) {
        if (error) *error = [NSError errorWithDomain:@"SDRZipArchive" code:7
            userInfo:@{NSLocalizedDescriptionKey: @"条目数据越界"}];
        return nil;
    }
    const uint8_t *raw = base + dataOff;

    if (entry.method == SDRZipMethodStore) {
        return [NSData dataWithBytes:raw length:compSize];
    }
    if (entry.method == SDRZipMethodDeflate) {
        return [self inflateRawDeflate:raw compressedSize:compSize
                      uncompressedSize:uncompSize error:error];
    }
    if (error) *error = [NSError errorWithDomain:@"SDRZipArchive" code:8
        userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"不支持的压缩方法: %u", entry.method]}];
    return nil;
}

- (NSData *)inflateRawDeflate:(const uint8_t *)src compressedSize:(uint32_t)compSize
             uncompressedSize:(uint32_t)uncompSize error:(NSError **)error {
    z_stream strm;
    memset(&strm, 0, sizeof(strm));
    // 负 windowBits：原始 deflate，无 zlib 头。
    if (inflateInit2(&strm, -MAX_WBITS) != Z_OK) {
        if (error) *error = [NSError errorWithDomain:@"SDRZipArchive" code:9
            userInfo:@{NSLocalizedDescriptionKey: @"inflate 初始化失败"}];
        return nil;
    }

    NSMutableData *out = [NSMutableData dataWithLength:uncompSize];
    strm.next_in = (Bytef *)src;
    strm.avail_in = compSize;
    strm.next_out = out.mutableBytes;
    strm.avail_out = uncompSize;

    int ret = inflate(&strm, Z_FINISH);
    inflateEnd(&strm);

    if (ret != Z_STREAM_END) {
        if (error) *error = [NSError errorWithDomain:@"SDRZipArchive" code:10
            userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"inflate 解压失败: %d", ret]}];
        return nil;
    }
    [out setLength:(NSUInteger)strm.total_out];
    return out;
}

@end