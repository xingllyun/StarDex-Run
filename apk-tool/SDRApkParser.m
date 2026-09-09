/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

#import "SDRApkParser.h"
#import "SDRZipArchive.h"

// ============================================================================
// 二进制 XML (AXML) 轻量解析器
// ============================================================================

typedef NS_ENUM(uint8_t, SDRXmlValueType) {
    SDRXmlTypeNull      = 0x00,
    SDRXmlTypeReference = 0x01,
    SDRXmlTypeAttribute = 0x02,
    SDRXmlTypeString    = 0x03,
    SDRXmlTypeFloat     = 0x04,
    SDRXmlTypeDimension = 0x05,
    SDRXmlTypeFraction  = 0x06,
    SDRXmlTypeIntDec    = 0x10,
    SDRXmlTypeIntHex    = 0x11,
    SDRXmlTypeBool      = 0x12,
    SDRXmlTypeColorInt  = 0x1c,
    SDRXmlTypeColorRGB  = 0x1d,
    SDRXmlTypeColorARGB = 0x1e
};

// AXML chunk 类型
#define SDR_CHUNK_STRING_POOL   0x0001
#define SDR_CHUNK_RES_MAP       0x0180
#define SDR_CHUNK_START_NS      0x0100
#define SDR_CHUNK_END_NS        0x0101
#define SDR_CHUNK_START_ELEMENT 0x0102
#define SDR_CHUNK_END_ELEMENT   0x0103
#define SDR_CHUNK_CDATA         0x0104

static NSString *const kSDRAndroidNS = @"http://schemas.android.com/apk/res/android";

@interface SDRXmlAttribute : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy, nullable) NSString *value;
@property (nonatomic, assign) uint8_t dataType;
@property (nonatomic, assign) uint32_t data;
- (BOOL)isReference;
@end

@implementation SDRXmlAttribute
- (BOOL)isReference { return _dataType == SDRXmlTypeReference; }
- (NSString *)description {
    return [NSString stringWithFormat:@"<%@=%@(%s,%08x)>", _name, _value, 
            _dataType == SDRXmlTypeString ? "str" : "num", _data];
}
@end

@interface SDRXmlElement : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) NSDictionary<NSString *, SDRXmlAttribute *> *attributes;
@property (nonatomic, strong) NSMutableArray<SDRXmlElement *> *children;
- (nullable SDRXmlAttribute *)attr:(NSString *)name;
@end

@implementation SDRXmlElement
- (nullable SDRXmlAttribute *)attr:(NSString *)name {
    SDRXmlAttribute *a = _attributes[name];
    if (a) return a;
    return _attributes[[@"android:" stringByAppendingString:name]];
}
- (NSString *)description { return [NSString stringWithFormat:@"<%@>", _name]; }
@end

@interface SDRBinaryXml : NSObject
@property (nonatomic, strong) NSArray<NSString *> *strings;
@property (nonatomic, strong, nullable) SDRXmlElement *root;
- (nullable instancetype)initWithData:(NSData *)data error:(NSError **)error;
@end

@implementation SDRBinaryXml {
    const uint8_t *_base;
    NSUInteger _len;
}

- (uint16_t)u2:(const uint8_t *)p { return (uint16_t)(p[0] | (p[1] << 8)); }
- (uint32_t)u4:(const uint8_t *)p {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

- (nullable instancetype)initWithData:(NSData *)data error:(NSError **)error {
    if (self = [super init]) {
        _base = (const uint8_t *)data.bytes;
        _len = data.length;
        if (![self parse:error]) return nil;
    }
    return self;
}

- (BOOL)parse:(NSError **)error {
    if (_len < 8 || [self u2:_base] != 0x0003) {
        if (error) *error = [NSError errorWithDomain:@"SDRApkParser" code:100
            userInfo:@{NSLocalizedDescriptionKey: @"无效的二进制 XML 头"}];
        return NO;
    }
    NSUInteger off = 8;  // 跳过 XML 头部(8字节: type,headerSize,size)
    NSMutableArray<SDRXmlElement *> *stack = [NSMutableArray array];
    SDRXmlElement *root = nil;

    while (off + 8 <= _len) {
        const uint8_t *chunk = _base + off;
        uint16_t type = [self u2:chunk];
        uint16_t headerSize = [self u2:chunk + 2];
        uint32_t size = [self u4:chunk + 4];
        if (size < headerSize || off + size > _len) break;

        if (type == SDR_CHUNK_STRING_POOL) {
            NSArray<NSString *> *poolStrings = nil;
            [self parseStringPool:off stringsOut:&poolStrings];
            _strings = poolStrings;
        } else if (type == SDR_CHUNK_START_ELEMENT) {
            SDRXmlElement *el = [self parseStartElement:off];
            if (el) {
                if (stack.count == 0) root = el;
                else [stack.lastObject.children addObject:el];
                [stack addObject:el];
            }
        } else if (type == SDR_CHUNK_END_ELEMENT) {
            [stack removeLastObject];
        }
        // RES_MAP / START_NS / END_NS / CDATA 直接跳过。

        off += size;
    }

    _root = root;
    return root != nil;
}

- (NSString *)stringAt:(uint32_t)idx {
    if (idx == 0xFFFFFFFF || !_strings || idx >= _strings.count) return nil;
    return _strings[idx];
}

// 读取 string pool 内第 idx 个字符串。
- (NSString *)poolString:(const uint8_t *)sp idx:(uint32_t)idx {
    uint32_t stringCount = [self u4:sp + 8];
    uint32_t flags = [self u4:sp + 16];
    uint32_t stringsStart = [self u4:sp + 20];
    if (idx >= stringCount) return nil;
    uint32_t strOff = [self u4:sp + 28 + idx * 4] + stringsStart;
    const uint8_t *s = sp + strOff;
    BOOL utf8 = (flags & 0x100) != 0;
    if (utf8) {
        uint32_t len;
        uint8_t b0 = s[0];
        if (b0 & 0x80) {
            len = ((b0 & 0x7F) << 8) | s[1];
            s += 2;
        } else {
            len = b0;
            s += 1;
        }
        return [[NSString alloc] initWithBytes:s length:len encoding:NSUTF8StringEncoding];
    } else {
        uint32_t len = [self u2:s];
        s += 2;
        return [[NSString alloc] initWithBytes:s length:len * 2 encoding:NSUTF16LittleEndianStringEncoding];
    }
}

- (void)parseStringPool:(NSUInteger)off stringsOut:(NSArray<__kindof NSString *> **)out {
    const uint8_t *sp = _base + off;
    uint32_t stringCount = [self u4:sp + 8];
    NSMutableArray<NSString *> *res = [NSMutableArray arrayWithCapacity:stringCount];
    for (uint32_t i = 0; i < stringCount; i++) {
        [res addObject:[self poolString:sp idx:i] ?: @""];
    }
    if (out) *out = res;
}

- (SDRXmlElement *)parseStartElement:(NSUInteger)off {
    const uint8_t *chunk = _base + off;
    // 节点头 16 字节后依次为 attrExt：ns/name/attributeStart/attributeSize/attributeCount/...
    uint32_t nsIdx = [self u4:chunk + 16];
    uint32_t nameIdx = [self u4:chunk + 20];
    uint16_t attributeCount = [self u2:chunk + 28];

    SDRXmlElement *el = [SDRXmlElement new];
    el.name = [self stringAt:nameIdx] ?: @"";
    el.children = [NSMutableArray array];

    NSMutableDictionary<NSString *, SDRXmlAttribute *> *attrs = [NSMutableDictionary dictionary];
    const uint8_t *ap = chunk + 36;
    for (uint16_t i = 0; i < attributeCount; i++) {
        uint32_t aNs = [self u4:ap];
        uint32_t aName = [self u4:ap + 4];
        uint32_t aRawValue = [self u4:ap + 8];
        uint16_t vsize = [self u2:ap + 12];
        uint8_t dataType = *(ap + 15);
        uint32_t data = [self u4:ap + 16];

        NSString *shortName = [self stringAt:aName] ?: @"";
        NSString *ns = [self stringAt:aNs];
        NSString *fullName = shortName;
        if (ns.length && ![ns isEqualToString:kSDRAndroidNS]) {
            fullName = [NSString stringWithFormat:@"%@:%@", [ns lastPathComponent], shortName];
            // 简化：仅对有命名空间的属性保留 "android:" 前缀，其它命名空间用原样
        }
        if ([ns isEqualToString:kSDRAndroidNS]) {
            fullName = [@"android:" stringByAppendingString:shortName];
        }

        SDRXmlAttribute *attr = [SDRXmlAttribute new];
        attr.name = fullName;
        attr.dataType = dataType;
        attr.data = data;
        if (dataType == SDRXmlTypeString) {
            attr.value = [self stringAt:data] ?: @"";
        } else if (dataType == SDRXmlTypeIntDec) {
            attr.value = [NSString stringWithFormat:@"%d", (int32_t)data];
        } else if (dataType == SDRXmlTypeIntHex) {
            attr.value = [NSString stringWithFormat:@"0x%08x", data];
        } else if (dataType == SDRXmlTypeBool) {
            attr.value = data ? @"true" : @"false";
        } else if (dataType == SDRXmlTypeReference) {
            attr.value = [NSString stringWithFormat:@"@0x%08x", data];
        } else if (dataType == SDRXmlTypeNull) {
            attr.value = @"";  // 可能为资源引用，name 已是明确的字符串
        } else {
            attr.value = [NSString stringWithFormat:@"%d", (int32_t)data];
        }
        (void)aRawValue; (void)vsize;
        attrs[fullName] = attr;
        ap += 20;
    }
    el.attributes = attrs;
    (void)nsIdx;
    return el;
}

@end

// ============================================================================
// APK 解析器
// ============================================================================

@interface SDRApkParser ()
@property (nonatomic, strong) SDRZipArchive *zip;
@property (nonatomic, strong) SDRApkInfo *info;
@end

@implementation SDRApkParser

- (instancetype)initWithApkData:(NSData *)apkData error:(NSError **)error {
    if (self = [super init]) {
        _zip = [[SDRZipArchive alloc] initWithData:apkData error:error];
        if (!_zip) return nil;
        _info = [SDRApkInfo new];
    }
    return self;
}

- (NSData *)entryDataNamed:(NSString *)name error:(NSError **)error {
    return [_zip dataForEntryNamed:name error:error];
}

- (SDRApkInfo *)parseInfo:(NSError **)error {
    // 1. 解析 AndroidManifest.xml
    NSData *manifest = [_zip dataForEntryNamed:@"AndroidManifest.xml" error:error];
    if (!manifest) return nil;

    SDRBinaryXml *xml = [[SDRBinaryXml alloc] initWithData:manifest error:error];
    if (!xml || !xml.root) return nil;

    [self fillManifestFromElement:xml.root];

    // 2. 枚举 DEX / SO / 资源 / 资产
    for (SDRZipEntry *e in _zip.entries) {
        NSString *n = e.name;
        if ([n hasPrefix:@"classes"] && [n hasSuffix:@".dex"]) {
            _info.dexFiles = [_info.dexFiles arrayByAddingObject:n];
        } else if ([n hasPrefix:@"lib/"] && [n hasSuffix:@".so"]) {
            _info.nativeLibs = [_info.nativeLibs arrayByAddingObject:n];
        } else if ([n hasPrefix:@"assets/"]) {
            _info.assetFiles = [_info.assetFiles arrayByAddingObject:n];
        } else if ([n hasPrefix:@"res/"]) {
            _info.resourceFiles = [_info.resourceFiles arrayByAddingObject:n];
        }
    }

    // 3. 观察排序：主 DEX 在前（classes.dex 已是前缀匹配顺序近似）
    _info.dexFiles = [_info.dexFiles sortedArrayUsingSelector:@selector(compare:)];

    // 4. 图标启发式解析
    _info.iconData = [self resolveIcon];

    return _info;
}

- (void)fillManifestFromElement:(SDRXmlElement *)manifest {
    _info.packageName = [manifest attr:@"package"].value;
    _info.versionName = [manifest attr:@"versionName"].value;
    _info.versionCode = [[manifest attr:@"versionCode"].value longLongValue];

    NSMutableArray<NSString *> *perms = [NSMutableArray array];
    NSMutableArray<NSString *> *activities = [NSMutableArray array];
    NSMutableArray<NSString *> *services = [NSMutableArray array];
    NSMutableArray<NSString *> *receivers = [NSMutableArray array];
    NSMutableArray<NSString *> *providers = [NSMutableArray array];

    for (SDRXmlElement *child in manifest.children) {
        NSString *name = child.name;
        if ([name isEqualToString:@"uses-permission"]) {
            NSString *p = [child attr:@"name"].value;
            if (p.length) [perms addObject:p];
        } else if ([name isEqualToString:@"uses-sdk"]) {
            SDRXmlAttribute *min = [child attr:@"minSdkVersion"];
            SDRXmlAttribute *tgt = [child attr:@"targetSdkVersion"];
            if (min) _info.minSdkVersion = (uint32_t)[min.value intValue];
            if (tgt) _info.targetSdkVersion = (uint32_t)[tgt.value intValue];
        } else if ([name isEqualToString:@"application"]) {
            NSString *label = [child attr:@"label"].value ?: _info.packageName ?: @"";
            _info.appLabel = label;
            NSMutableArray<NSString *> *acts = [NSMutableArray array];
            NSMutableArray<NSString *> *svcs = [NSMutableArray array];
            NSMutableArray<NSString *> *recvs = [NSMutableArray array];
            NSMutableArray<NSString *> *provs = [NSMutableArray array];
            for (SDRXmlElement *c in child.children) {
                NSString *cn = [c attr:@"name"].value;
                if (!cn.length) continue;
                if ([c.name isEqualToString:@"activity"]) [acts addObject:cn];
                else if ([c.name isEqualToString:@"service"]) [svcs addObject:cn];
                else if ([c.name isEqualToString:@"receiver"]) [recvs addObject:cn];
                else if ([c.name isEqualToString:@"provider"]) [provs addObject:cn];
            }
            [activities addObjectsFromArray:acts];
            [services addObjectsFromArray:svcs];
            [receivers addObjectsFromArray:recvs];
            [providers addObjectsFromArray:provs];
        }
    }

    _info.permissions = perms;
    _info.activities = activities;
    _info.services = services;
    _info.receivers = receivers;
    _info.providers = providers;
}

// 启发式寻找启动图标：优先 ic_launcher，其次任意 png/jpg。
- (nullable NSData *)resolveIcon {
    NSArray<NSString *> *candidates = @[
        @"res/mipmap-xxxhdpi/ic_launcher.png",
        @"res/mipmap-xxhdpi/ic_launcher.png",
        @"res/mipmap-xhdpi/ic_launcher.png",
        @"res/mipmap-hdpi/ic_launcher.png",
        @"res/mipmap-mdpi/ic_launcher.png",
        @"res/drawable/icon.png", @"res/drawable/app_icon.png"
    ];
    for (NSString *c in candidates) {
        NSData *d = [_zip dataForEntryNamed:c error:nil];
        if (d.length) return d;
    }
    // 兜底：任意 res 下 ic_launcher 前缀的 png
    for (SDRZipEntry *e in _zip.entries) {
        if ([e.name hasPrefix:@"res/"] && [e.name containsString:@"ic_launcher"] &&
            [e.name hasSuffix:@".png"]) {
            return [_zip dataForEntry:e error:nil];
        }
    }
    return nil;
}

@end