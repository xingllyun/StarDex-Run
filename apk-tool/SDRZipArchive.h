/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// 压缩方法（APK 常见两种，其余不支持直接报错）。
typedef NS_ENUM(uint16_t, SDRZipMethod) {
    SDRZipMethodStore   = 0,  // 无压缩
    SDRZipMethodDeflate = 8   // 原始 deflate（经 libz inflate）
};

// ZIP 内单个条目元数据。
@interface SDRZipEntry : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) SDRZipMethod method;
@property (nonatomic, assign) uint32_t compressedSize;
@property (nonatomic, assign) uint32_t uncompressedSize;
@property (nonatomic, assign) uint32_t crc32;
@property (nonatomic, assign) uint32_t localHeaderOffset;  // 本地文件头偏移
- (BOOL)isDirectory;
@end

// 极简只读 ZIP 解析器：只依赖中心目录 + 本地文件头，
// 支持 STORE 与 DEFLATE（zlib raw inflate），专用于读 APK。
// 两种模式：
//   1) 内存模式 initWithData：全量数据已在内存（签名工具等场景）。
//   2) 文件模式 initWithFileURL：仅加载尾部 EOCD + 中央目录元数据，
//      条目数据按需经独立 FileHandle 分片读取（导入/运行大 APK 场景，
//      控制内存峰值，避免全量加载被系统强杀）。
@interface SDRZipArchive : NSObject

@property (nonatomic, strong, readonly, nullable) NSData *data;         // 文件模式为 nil
@property (nonatomic, strong, readonly) NSArray<SDRZipEntry *> *entries;

- (nullable instancetype)initWithData:(NSData *)data error:(NSError **)error;
- (nullable instancetype)initWithFileURL:(NSURL *)fileURL error:(NSError **)error;

- (nullable SDRZipEntry *)entryNamed:(NSString *)name;
- (nullable NSArray<SDRZipEntry *> *)entriesWithPrefix:(NSString *)prefix;

// 解压条目内容；越界/损坏返回 nil 并写 error。
// 文件模式下每次读取独立打开 FileHandle（线程安全）。
- (nullable NSData *)dataForEntry:(SDRZipEntry *)entry error:(NSError **)error;
- (nullable NSData *)dataForEntryNamed:(NSString *)name error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END