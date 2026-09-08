/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

#import "SDRDexParser.h"

// DEX header 定长部分偏移
#define DEX_HDR_MAGIC           0x00
#define DEX_HDR_CHECKSUM        0x08
#define DEX_HDR_SIGNATURE       0x0C
#define DEX_HDR_FILE_SIZE       0x20
#define DEX_HDR_HEADER_SIZE     0x24
#define DEX_HDR_ENDIAN_TAG      0x28
#define DEX_HDR_MAP_OFF         0x34
#define DEX_HDR_STRING_IDS_SIZE 0x38
#define DEX_HDR_STRING_IDS_OFF  0x3C
#define DEX_HDR_TYPE_IDS_SIZE   0x40
#define DEX_HDR_TYPE_IDS_OFF    0x44
#define DEX_HDR_PROTO_IDS_SIZE  0x48
#define DEX_HDR_PROTO_IDS_OFF   0x4C
#define DEX_HDR_FIELD_IDS_SIZE  0x50
#define DEX_HDR_FIELD_IDS_OFF   0x54
#define DEX_HDR_METHOD_IDS_SIZE 0x58
#define DEX_HDR_METHOD_IDS_OFF  0x5C
#define DEX_HDR_CLASS_DEFS_SIZE 0x60
#define DEX_HDR_CLASS_DEFS_OFF  0x64
#define DEX_HDR_DATA_SIZE       0x68
#define DEX_HDR_DATA_OFF        0x6C
#define DEX_HDR_SIZE            0x70

SDRDexPrimitiveType SDRDexPrimitiveTypeFromDescriptor(NSString *desc) {
    if (desc.length == 0) return SDRDexTypeObject;
    unichar c = [desc characterAtIndex:0];
    switch (c) {
        case 'Z': return SDRDexTypeBoolean;
        case 'B': return SDRDexTypeByte;
        case 'S': return SDRDexTypeShort;
        case 'C': return SDRDexTypeChar;
        case 'I': return SDRDexTypeInt;
        case 'J': return SDRDexTypeLong;
        case 'F': return SDRDexTypeFloat;
        case 'D': return SDRDexTypeDouble;
        default:  return SDRDexTypeObject;  // L开头 / [ 数组
    }
}

@implementation SDRDexFile {
    uint32_t _stringIdsSize, _stringIdsOff;
    uint32_t _typeIdsSize, _typeIdsOff;
    uint32_t _protoIdsSize, _protoIdsOff;
    uint32_t _fieldIdsSize, _fieldIdsOff;
    uint32_t _methodIdsSize, _methodIdsOff;
    uint32_t _classDefsSize, _classDefsOff;
    uint32_t _dataSize, _dataOff;
}

#pragma mark - 初始化

- (nullable instancetype)initWithData:(NSData *)data error:(NSError **)error {
    if (self = [super init]) {
        _data = data;
        _base = (const uint8_t *)data.bytes;
        _size = (uint32_t)data.length;

        if (_size < DEX_HDR_SIZE) {
            if (error) *error = [self err:@"文件过小，非法 DEX"];
            return nil;
        }

        // magic
        char magicBytes[9] = {0};
        memcpy(magicBytes, _base + DEX_HDR_MAGIC, 8);
        _magic = [NSString stringWithFormat:@"%s", magicBytes];

        if (strncmp(magicBytes, "dex\n", 4) != 0) {
            if (error) *error = [self err:@"魔数不合法，非 DEX 文件"];
            return nil;
        }
        // 解析版本号 "dex\n035\0"
        if (magicBytes[4] >= '0' && magicBytes[4] <= '9') {
            _versionMajor = (uint8_t)(magicBytes[4] - '0');
        }
        if (magicBytes[5] >= '0' && magicBytes[5] <= '9') {
            _versionMinor = (uint8_t)(magicBytes[5] - '0');
        }
        if (magicBytes[4] == '0') { _versionMajor = (uint8_t)(magicBytes[5] - '0'); _versionMinor = (uint8_t)(magicBytes[6] - '0'); }

        _stringIdsSize = [self u4:DEX_HDR_STRING_IDS_SIZE];
        _stringIdsOff  = [self u4:DEX_HDR_STRING_IDS_OFF];
        _typeIdsSize   = [self u4:DEX_HDR_TYPE_IDS_SIZE];
        _typeIdsOff    = [self u4:DEX_HDR_TYPE_IDS_OFF];
        _protoIdsSize  = [self u4:DEX_HDR_PROTO_IDS_SIZE];
        _protoIdsOff   = [self u4:DEX_HDR_PROTO_IDS_OFF];
        _fieldIdsSize  = [self u4:DEX_HDR_FIELD_IDS_SIZE];
        _fieldIdsOff   = [self u4:DEX_HDR_FIELD_IDS_OFF];
        _methodIdsSize = [self u4:DEX_HDR_METHOD_IDS_SIZE];
        _methodIdsOff  = [self u4:DEX_HDR_METHOD_IDS_OFF];
        _classDefsSize = [self u4:DEX_HDR_CLASS_DEFS_SIZE];
        _classDefsOff  = [self u4:DEX_HDR_CLASS_DEFS_OFF];
        _dataSize      = [self u4:DEX_HDR_DATA_SIZE];
        _dataOff       = [self u4:DEX_HDR_DATA_OFF];
    }
    return self;
}

- (NSError *)err:(NSString *)msg {
    return [NSError errorWithDomain:@"SDRDexParser" code:1
                           userInfo:@{NSLocalizedDescriptionKey: msg}];
}

#pragma mark - 基础读取

- (uint8_t)u1:(uint32_t)off {
    if (off + 1 > _size) return 0;
    return _base[off];
}

- (uint16_t)u2:(uint32_t)off {
    if (off + 2 > _size) return 0;
    return (uint16_t)(_base[off] | (_base[off + 1] << 8));
}

- (uint32_t)u4:(uint32_t)off {
    if (off + 4 > _size) return 0;
    return (uint32_t)_base[off] | ((uint32_t)_base[off + 1] << 8) |
           ((uint32_t)_base[off + 2] << 16) | ((uint32_t)_base[off + 3] << 24);
}

#pragma mark - ULEB / SLEB / MUTF-8

- (uint32_t)readUlebAt:(uint32_t)off outNext:(uint32_t *)next {
    uint32_t result = 0;
    uint32_t shift = 0;
    uint32_t p = off;
    while (p < _size) {
        uint8_t b = _base[p++];
        result |= (uint32_t)(b & 0x7F) << shift;
        if ((b & 0x80) == 0) break;
        shift += 7;
    }
    if (next) *next = p;
    return result;
}

- (int32_t)readSlebAt:(uint32_t)off outNext:(uint32_t *)next {
    int32_t result = 0;
    uint32_t shift = 0;
    uint8_t b = 0;
    uint32_t p = off;
    while (p < _size) {
        b = _base[p++];
        result |= (int32_t)(b & 0x7F) << shift;
        shift += 7;
        if ((b & 0x80) == 0) break;
    }
    if (shift < 32 && (b & 0x40)) {
        result |= (-1 << shift);
    }
    if (next) *next = p;
    return result;
}

// 从 off 处（string_data_item）解码 MUTF-8 字符串，续 utf16_size 个 UTF-16 编码单元。
- (NSString *)decodeMUTF8At:(uint32_t)off outNext:(uint32_t *)next {
    uint32_t p = off;
    uint32_t utf16Size = [self readUlebAt:p outNext:&p];
    NSMutableString *result = [NSMutableString stringWithCapacity:utf16Size];
    for (uint32_t i = 0; i < utf16Size && p < _size; i++) {
        uint8_t b0 = _base[p];
        if (b0 == 0x00) break;                 // 终止符
        if (b0 == 0xC0 && p + 1 < _size && _base[p + 1] == 0x80) {
            [result appendFormat:@"%C", (unichar)0];  // U+0000
            p += 2;
        } else if (b0 < 0x80) {
            [result appendFormat:@"%C", (unichar)b0];
            p += 1;
        } else if ((b0 & 0xE0) == 0xC0) {      // 2 字节 BMP（含高代理）
            uint16_t c = (uint16_t)(((b0 & 0x1F) << 6) | (_base[p + 1] & 0x3F));
            [result appendFormat:@"%C", (unichar)c];
            p += 2;
        } else if ((b0 & 0xF0) == 0xE0) {      // 3 字节 BMP
            uint16_t c = (uint16_t)(((b0 & 0x0F) << 12) | ((_base[p + 1] & 0x3F) << 6) | (_base[p + 2] & 0x3F));
            [result appendFormat:@"%C", (unichar)c];
            p += 3;
        } else { break; }
    }
    if (next) *next = p;
    return result;
}

#pragma mark - 表计数

- (uint32_t)stringIdsSize { return _stringIdsSize; }
- (uint32_t)typeIdsSize   { return _typeIdsSize; }
- (uint32_t)protoIdsSize  { return _protoIdsSize; }
- (uint32_t)fieldIdsSize  { return _fieldIdsSize; }
- (uint32_t)methodIdsSize { return _methodIdsSize; }
- (uint32_t)classDefsSize { return _classDefsSize; }

#pragma mark - 字符串 / 类型

- (NSString *)stringByIdx:(uint32_t)stringIdx {
    if (stringIdx >= _stringIdsSize) return @"";
    uint32_t stringDataOff = [self u4:_stringIdsOff + stringIdx * 4];
    return [self decodeMUTF8At:stringDataOff outNext:NULL];
}

- (NSString *)typeDescriptor:(uint16_t)typeIdx {
    if (typeIdx >= _typeIdsSize) return @"";
    uint32_t descriptorIdx = [self u4:_typeIdsOff + typeIdx * 4];
    return [self stringByIdx:descriptorIdx];
}

#pragma mark - field id

- (uint16_t)fieldClassIdx:(uint32_t)fieldIdx {
    if (fieldIdx >= _fieldIdsSize) return 0;
    return [self u2:_fieldIdsOff + fieldIdx * 8];
}
- (uint16_t)fieldTypeIdx:(uint32_t)fieldIdx {
    if (fieldIdx >= _fieldIdsSize) return 0;
    return [self u2:_fieldIdsOff + fieldIdx * 8 + 2];
}
- (uint32_t)fieldNameIdx:(uint32_t)fieldIdx {
    if (fieldIdx >= _fieldIdsSize) return 0;
    return [self u4:_fieldIdsOff + fieldIdx * 8 + 4];
}

#pragma mark - method id

- (uint16_t)methodClassIdx:(uint32_t)methodIdx {
    if (methodIdx >= _methodIdsSize) return 0;
    return [self u2:_methodIdsOff + methodIdx * 8];
}
- (uint16_t)methodProtoIdx:(uint32_t)methodIdx {
    if (methodIdx >= _methodIdsSize) return 0;
    return [self u2:_methodIdsOff + methodIdx * 8 + 2];
}
- (uint32_t)methodNameIdx:(uint32_t)methodIdx {
    if (methodIdx >= _methodIdsSize) return 0;
    return [self u4:_methodIdsOff + methodIdx * 8 + 4];
}
- (NSString *)methodName:(uint32_t)methodIdx {
    return [self stringByIdx:[self methodNameIdx:methodIdx]];
}

// 重建方法描述符：由 proto_id 的 shorty + 参数 type_list + 返回类型。
- (NSString *)methodDescriptor:(uint32_t)methodIdx {
    if (methodIdx >= _methodIdsSize) return @"";
    uint16_t protoIdx = [self methodProtoIdx:methodIdx];
    if (protoIdx >= _protoIdsSize) return @"";
    uint32_t protoOff = _protoIdsOff + protoIdx * 12;
    uint32_t returnTypeIdx = [self u4:protoOff + 4];
    uint32_t parametersOff = [self u4:protoOff + 8];

    NSMutableString *desc = [NSMutableString stringWithString:@"("];
    if (parametersOff != 0) {
        uint32_t count = [self u4:parametersOff];
        for (uint32_t i = 0; i < count; i++) {
            uint16_t typeIdx = [self u2:parametersOff + 4 + i * 2];
            [desc appendString:[self typeDescriptor:typeIdx]];
        }
    }
    [desc appendString:@")"];
    [desc appendString:[self typeDescriptor:(uint16_t)returnTypeIdx]];
    return desc;
}

#pragma mark - class def

- (uint32_t)classDefClassIdx:(uint16_t)classDefIdx {
    if (classDefIdx >= _classDefsSize) return 0;
    return [self u4:_classDefsOff + classDefIdx * 32];
}
- (uint32_t)classDefAccessFlags:(uint16_t)classDefIdx {
    if (classDefIdx >= _classDefsSize) return 0;
    return [self u4:_classDefsOff + classDefIdx * 32 + 4];
}
- (uint16_t)classDefSuperclassIdx:(uint16_t)classDefIdx {
    if (classDefIdx >= _classDefsSize) return 0xFFFF;
    return (uint16_t)[self u4:_classDefsOff + classDefIdx * 32 + 8];
}
- (uint32_t)classDefClassDataOff:(uint16_t)classDefIdx {
    if (classDefIdx >= _classDefsSize) return 0;
    return [self u4:_classDefsOff + classDefIdx * 32 + 24];
}

#pragma mark - class data 遍历

- (void)forEachFieldAtClassDataOff:(uint32_t)off
                             block:(void (^)(uint32_t fieldIdx, uint32_t accessFlags))block {
    if (off == 0 || !block) return;
    uint32_t p = off;
    uint32_t staticSize = [self readUlebAt:p outNext:&p];
    uint32_t instanceSize = [self readUlebAt:p outNext:&p];
    uint32_t directMethods = [self readUlebAt:p outNext:&p];
    uint32_t virtualMethods = [self readUlebAt:p outNext:&p];

    uint32_t fieldIdx = 0;
    for (uint32_t i = 0; i < staticSize + instanceSize; i++) {
        fieldIdx += [self readUlebAt:p outNext:&p];
        uint32_t flags = [self readUlebAt:p outNext:&p];
        block(fieldIdx, flags);
    }
    (void)directMethods; (void)virtualMethods;
}

- (void)forEachMethodAtClassDataOff:(uint32_t)off
                              block:(void (^)(uint32_t methodIdx, uint32_t accessFlags, uint32_t codeOff))block {
    if (off == 0 || !block) return;
    uint32_t p = off;
    uint32_t staticSize = [self readUlebAt:p outNext:&p];
    uint32_t instanceSize = [self readUlebAt:p outNext:&p];
    uint32_t directMethods = [self readUlebAt:p outNext:&p];
    uint32_t virtualMethods = [self readUlebAt:p outNext:&p];

    // 跳过字段
    uint32_t fieldIdx = 0;
    for (uint32_t i = 0; i < staticSize + instanceSize; i++) {
        fieldIdx += [self readUlebAt:p outNext:&p];
        (void)fieldIdx;
        (void)[self readUlebAt:p outNext:&p]; // access_flags
    }
    // 方法
    uint32_t methodIdx = 0;
    for (uint32_t i = 0; i < directMethods + virtualMethods; i++) {
        methodIdx += [self readUlebAt:p outNext:&p];
        uint32_t flags = [self readUlebAt:p outNext:&p];
        uint32_t codeOff = [self readUlebAt:p outNext:&p];
        block(methodIdx, flags, codeOff);
    }
}

#pragma mark - code_item 解析

- (BOOL)parseCodeItemAtOff:(uint32_t)codeOff into:(SDRDexMethod *)method error:(NSError **)error {
    if (codeOff + 16 > _size) {
        if (error) *error = [self err:@"code_item 越界"];
        return NO;
    }
    uint16_t registersSize = [self u2:codeOff];
    uint16_t insSize = [self u2:codeOff + 2];
    uint16_t outsSize = [self u2:codeOff + 4];
    uint16_t triesSize = [self u2:codeOff + 6];
    // +8 debug_info_off(4)
    uint32_t insnsSize = [self u4:codeOff + 12];

    method.registersSize = registersSize;
    method.insSize = insSize;
    method.outsSize = outsSize;
    method.triesSize = triesSize;
    method.insnsSize = insnsSize;
    method.insns = (const uint16_t *)(_base + codeOff + 16);

    uint32_t cursor = codeOff + 16 + insnsSize * 2;
    NSMutableArray<SDRTryRegion *> *regions = [NSMutableArray array];

    if (triesSize > 0) {
        if ((insnsSize & 1) != 0) cursor += 2;  // 对齐填充
        uint32_t handlerListOff = cursor + triesSize * 8; // try_item 每条 8 字节
        for (uint32_t t = 0; t < triesSize; t++) {
            uint32_t itemOff = cursor + t * 8;
            uint32_t startAddr = [self u4:itemOff];
            uint16_t insnCount = [self u2:itemOff + 4];
            uint16_t handlerOff = [self u2:itemOff + 6];

            SDRTryRegion *region = [SDRTryRegion new];
            region.startAddr = startAddr;
            region.endAddr = startAddr + insnCount;
            region.handlers = [self parseCatchHandlersAt:handlerListOff + handlerOff];
            [regions addObject:region];
        }
    }
    method.tryRegions = regions;
    return YES;
}

- (NSArray<SDRCatchHandler *> *)parseCatchHandlersAt:(uint32_t)off {
    NSMutableArray<SDRCatchHandler *> *result = [NSMutableArray array];
    uint32_t p = off;
    int32_t ssize = [self readSlebAt:p outNext:&p];
    int32_t count = ssize < 0 ? -ssize : ssize;
    BOOL hasCatchAll = ssize < 0;

    for (int32_t i = 0; i < count; i++) {
        SDRCatchHandler *handler = [SDRCatchHandler new];
        if (i == 0 && hasCatchAll) {
            handler.catchAll = YES;
            handler.typeIdx = 0xFFFF;
        } else {
            handler.typeIdx = (uint16_t)[self readUlebAt:p outNext:&p];
            handler.typeDescriptor = [self typeDescriptor:handler.typeIdx];
        }
        handler.handlerAddr = [self readUlebAt:p outNext:&p];
        [result addObject:handler];
    }
    return result;
}

@end