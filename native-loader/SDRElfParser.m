/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

#import "SDRElfParser.h"

// ELF 常量。
#define SDR_ELF_CLASS_OFF  4
#define SDR_ELF_DATA_OFF   5
#define SDR_ELF_EI_NIDENT  16

typedef NS_ENUM(uint8_t, SDRElfSymBinding) {
    SDRElfSTB_LOCAL = 0,
    SDRElfSTB_GLOBAL = 1,
    SDRElfSTB_WEAK = 2,
};

typedef NS_ENUM(uint8_t, SDRElfSymType) {
    SDRElfSTT_NOTYPE = 0,
    SDRElfSTT_OBJECT = 1,
    SDRElfSTT_FUNC = 2,
    SDRElfSTT_SECTION = 3,
};

// 32 位符号表条目布局：st_name(4) st_value(4) st_size(4) st_info(1) st_other(1) st_shndx(2)
#define SDR_ELF32_SYM_SIZE 16
// 64 位符号表条目布局：st_name(4) st_info(1) st_other(1) st_shndx(2) st_value(8) st_size(8)
#define SDR_ELF64_SYM_SIZE 24

@implementation SDRElfSymbol
@end
@implementation SDRElfSegment
@end

@implementation SDRElfParser {
    const uint8_t *_base;
    NSUInteger _len;
    uint8_t _class;
    uint8_t _endianness;
    uint16_t _machine;
    uint64_t _entry;
    uint16_t _eType;
    // 动态段（.dynamic）相关项
    uint64_t _dynStrOff;      // DT_STRTAB 对应的字符串表虚拟地址
    uint64_t _dynStrSize;
    uint64_t _dynSymOff;      // DT_SYMTAB 符号表虚拟地址
    uint64_t _dynHashOff;     // DT_HASH 或 DT_GNU_HASH
    uint64_t _dynSymEntSize;
    uint64_t _dynSymCount;
}

- (instancetype)initWithData:(NSData *)data error:(NSError **)error {
    if (self = [super init]) {
        _data = data;
        _base = data.bytes;
        _len = data.length;
        if (_len < SDR_ELF_EI_NIDENT + 36) {
            if (error) *error = [NSError errorWithDomain:@"SDRElfParser" code:1
                userInfo:@{NSLocalizedDescriptionKey: @"数据过短，非有效 ELF"}];
            return nil;
        }
        if (!(_base[0] == 0x7F && _base[1] == 'E' && _base[2] == 'L' && _base[3] == 'F')) {
            if (error) *error = [NSError errorWithDomain:@"SDRElfParser" code:2
                userInfo:@{NSLocalizedDescriptionKey: @"缺少 ELF 魔数"}];
            return nil;
        }
        _class = _base[SDR_ELF_CLASS_OFF];
        _endianness = _base[SDR_ELF_DATA_OFF];
        if ((_class != SDRElfClass32 && _class != SDRElfClass64) || _endianness != SDRElfDataLittleEndian) {
            if (error) *error = [NSError errorWithDomain:@"SDRElfParser" code:3
                userInfo:@{NSLocalizedDescriptionKey: @"仅支持小端 32/64 位 ELF"}];
            return nil;
        }
        [self parseHeader];
        [self parseSegments];
        [self parseDynamicSymbols];
    }
    return self;
}

- (BOOL)is64Bit { return _class == SDRElfClass64; }
- (BOOL)isLittleEndian { return _endianness == SDRElfDataLittleEndian; }
- (BOOL)isSharedObject { return _eType == 3; } // ET_DYN
- (SDRElfClass)elfClass { return (SDRElfClass)_class; }
- (SDRElfData)endianness { return (SDRElfData)_endianness; }
- (uint16_t)machine { return _machine; }
- (uint64_t)entryPoint { return _entry; }

#pragma mark - 基本读取

- (uint16_t)readU16At:(uint64_t)off {
    if (off + 2 > _len) return 0;
    return (uint16_t)(_base[off] | (_base[off + 1] << 8));
}
- (uint32_t)readU32At:(uint64_t)off {
    if (off + 4 > _len) return 0;
    return (uint32_t)(_base[off]) | ((uint32_t)_base[off + 1] << 8) |
           ((uint32_t)_base[off + 2] << 16) | ((uint32_t)_base[off + 3] << 24);
}
- (uint64_t)readU64At:(uint64_t)off {
    if (off + 8 > _len) return 0;
    uint64_t v = 0;
    for (int i = 7; i >= 0; i--) v = (v << 8) | _base[off + i];
    return v;
}

#pragma mark - 文件头

- (void)parseHeader {
    _eType = [self readU16At:16];
    _machine = [self readU16At:18];
    if (_class == SDRElfClass64) {
        _entry = [self readU64At:24];
    } else {
        _entry = [self readU32At:24];
    }
}

#pragma mark - 程序头

- (void)parseSegments {
    NSMutableArray<SDRElfSegment *> *out = [NSMutableArray array];
    uint64_t phOff, phEntSize;
    uint16_t phCount;
    if (_class == SDRElfClass64) {
        phOff = [self readU64At:32];
        phEntSize = [self readU16At:54];
        phCount = [self readU16At:56];
    } else {
        phOff = [self readU32At:28];
        phEntSize = [self readU16At:42];
        phCount = [self readU16At:44];
    }
    for (uint16_t i = 0; i < phCount; i++) {
        SDRElfSegment *seg = [SDRElfSegment new];
        uint64_t off = phOff + (uint64_t)i * phEntSize;
        seg.type = [self readU32At:off];
        if (_class == SDRElfClass64) {
            seg.flags = [self readU32At:off + 4];
            seg.fileOffset = [self readU64At:off + 8];
            seg.vaddr = [self readU64At:off + 16];
            seg.fileSize = [self readU64At:off + 32];
            seg.memSize = [self readU64At:off + 40];
            seg.align = [self readU64At:off + 48];
        } else {
            seg.fileOffset = [self readU32At:off + 4];
            seg.vaddr = [self readU32At:off + 8];
            seg.fileSize = [self readU32At:off + 16];
            seg.memSize = [self readU32At:off + 20];
            seg.flags = [self readU32At:off + 24];
            seg.align = [self readU32At:off + 28];
        }
        // DT_DYNAMIC 段：定位动态段，供解析 .dynamic。
        if (seg.type == 2 /* PT_DYNAMIC */) {
            [self parseDynamicSegmentAtFileOffset:seg.fileOffset];
        }
        [out addObject:seg];
    }
    _segments = out;
}

#pragma mark - 动态段

- (void)parseDynamicSegmentAtFileOffset:(uint64_t)fileOff {
    // 解析 DT_* 项，收集 STRTAB/SYMTAB/HASH 等。虚拟地址与文件偏移按简单基址映射。
    // 最大迭代次数保护，防止畸形 .dynamic 段导致死循环。
    const uint64_t maxIter = 4096;
    uint64_t iter = 0;
    while (iter++ < maxIter) {
        NSUInteger entrySize = [self is64Bit] ? 16 : 8;
        if (fileOff + entrySize > _len) break;
        int64_t tag = (int64_t)([self is64Bit] ? [self readU64At:fileOff] : [self readU32At:fileOff]);
        uint64_t val = [self is64Bit] ? [self readU64At:fileOff + 8] : [self readU32At:fileOff + 4];
        fileOff += entrySize;
        if (tag == 0) break; // DT_NULL

        switch (tag) {
            case 5:  // DT_STRTAB
                _dynStrOff = val; break;
            case 10: // DT_STRSZ
                _dynStrSize = val; break;
            case 6:  // DT_SYMTAB
                _dynSymOff = val; break;
            case 11: // DT_SYMENT
                _dynSymEntSize = val; break;
            case 4:  // DT_HASH
                _dynHashOff = val; break;
            case 0x6ffffef5: // DT_GNU_HASH
                _dynHashOff = val; break;
            default: break;
        }
    }
}

#pragma mark - 符号表

- (void)parseDynamicSymbols {
    NSMutableArray<SDRElfSymbol *> *defined = [NSMutableArray array];
    NSMutableArray<SDRElfSymbol *> *undefined = [NSMutableArray array];
    _definedSymbols = defined;
    _undefinedSymbols = undefined;

    if (!_dynSymOff || !_dynStrOff) return;

    // 计算符号数量：优先 DT_HASH 的 nchain，否则按名称范围估算（骨架阶段仅做基础遍历）。
    uint64_t count = 0;
    if (_dynHashOff) {
        // SysV hash：nbucket(4) nchain(4) ...
        count = [self readU32At:[self vaddrToFileOffset:_dynHashOff] + 4];
    }
    uint64_t entSize = _dynSymEntSize ?: ([self is64Bit] ? SDR_ELF64_SYM_SIZE : SDR_ELF32_SYM_SIZE);

    // 没有可靠符号数时的兜底：仅解析前 4096 条。
    if (count == 0) count = 4096;

    uint64_t symFileOff = [self vaddrToFileOffset:_dynSymOff];
    uint64_t strFileOff = [self vaddrToFileOffset:_dynStrOff];

    for (uint64_t i = 0; i < count; i++) {
        uint64_t off = symFileOff + i * entSize;
        if (off + entSize > _len) break;
        uint32_t nameOff = [self readU32At:off];
        NSString *name = [self stringAt:strFileOff + nameOff];
        if (!name || name.length == 0) continue;

        SDRElfSymbol *sym = [SDRElfSymbol new];
        sym.name = name;
        sym.value = [self is64Bit] ? [self readU64At:off + 8] : [self readU32At:off + 4];
        sym.size = [self is64Bit] ? [self readU64At:off + 16] : [self readU32At:off + 8];
        sym.binding = [self is64Bit] ? (_base[off + 4] >> 4) : (_base[off + 12] >> 4);
        sym.type = [self is64Bit] ? (_base[off + 4] & 0x0F) : (_base[off + 12] & 0x0F);
        sym.sectionIndex = [self is64Bit] ? [self readU16At:off + 6] : [self readU16At:off + 14];

        if (sym.sectionIndex == 0 /* SHN_UNDEF */) {
            [undefined addObject:sym];
        } else {
            [defined addObject:sym];
        }
    }
}

- (NSString *)stringAt:(uint64_t)off {
    if (off >= _len) return nil;
    const uint8_t *start = _base + off;
    NSUInteger max = _len - (NSUInteger)off;
    NSUInteger n = 0;
    while (n < max && start[n] != 0) n++;
    return [[NSString alloc] initWithBytes:start length:n encoding:NSUTF8StringEncoding];
}

// 虚拟地址 → 文件偏移（基础：假定加载段 vaddr 与 fileOffset 基址一致，绝大多数简单 SO 成立）。
- (uint64_t)vaddrToFileOffset:(uint64_t)vaddr {
    for (SDRElfSegment *seg in _segments) {
        if (seg.type != 1 /* PT_LOAD */) continue;
        if (vaddr >= seg.vaddr && vaddr < seg.vaddr + seg.fileSize) {
            return seg.fileOffset + (vaddr - seg.vaddr);
        }
    }
    return vaddr; // 兜底：直接按偏移（节表场景）
}

- (SDRElfSymbol *)definedSymbolNamed:(NSString *)name {
    for (SDRElfSymbol *s in _definedSymbols) {
        if ([s.name isEqualToString:name]) return s;
    }
    return nil;
}

@end