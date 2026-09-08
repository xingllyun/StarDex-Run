/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(uint8_t, SDRElfClass) {
    SDRElfClass32 = 1,
    SDRElfClass64 = 2
};

typedef NS_ENUM(uint8_t, SDRElfData) {
    SDRElfDataLittleEndian = 1,
    SDRElfDataBigEndian = 2
};

// 动态符号条目。
@interface SDRElfSymbol : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) uint64_t value;      // 符号地址（重定位后偏移）
@property (nonatomic, assign) uint64_t size;
@property (nonatomic, assign) uint8_t binding;     // STB_*
@property (nonatomic, assign) uint8_t type;        // STT_*
@property (nonatomic, assign) uint16_t sectionIndex;
@end

// 程序头（加载段）描述。
@interface SDRElfSegment : NSObject
@property (nonatomic, assign) uint32_t type;
@property (nonatomic, assign) uint32_t flags;
@property (nonatomic, assign) uint64_t fileOffset;
@property (nonatomic, assign) uint64_t fileSize;
@property (nonatomic, assign) uint64_t vaddr;
@property (nonatomic, assign) uint64_t memSize;
@property (nonatomic, assign) uint64_t align;
@end

// ELF 文件解析器：支持 32/64 位 ELF，解析文件头、程序头、节表与动态符号表。
@interface SDRElfParser : NSObject

@property (nonatomic, strong, readonly) NSData *data;
@property (nonatomic, readonly) SDRElfClass elfClass;
@property (nonatomic, readonly) SDRElfData endianness;
@property (nonatomic, readonly) uint16_t machine;       // 目标架构（EM_*）
@property (nonatomic, readonly) uint64_t entryPoint;
@property (nonatomic, readonly) BOOL is64Bit;
@property (nonatomic, readonly) BOOL isLittleEndian;
@property (nonatomic, readonly) BOOL isSharedObject;    // e_type == ET_DYN

@property (nonatomic, readonly) NSArray<SDRElfSegment *> *segments;
@property (nonatomic, readonly) NSArray<SDRElfSymbol *> *definedSymbols;   // 已定义（导出）
@property (nonatomic, readonly) NSArray<SDRElfSymbol *> *undefinedSymbols; // 未定义（待导入）

- (nullable instancetype)initWithData:(NSData *)data error:(NSError **)error;

// 基础按字节序读取。
- (uint16_t)readU16At:(uint64_t)offset;
- (uint32_t)readU32At:(uint64_t)offset;
- (uint64_t)readU64At:(uint64_t)offset;

// 查找导出符号。
- (nullable SDRElfSymbol *)definedSymbolNamed:(NSString *)name;

@end

NS_ASSUME_NONNULL_END