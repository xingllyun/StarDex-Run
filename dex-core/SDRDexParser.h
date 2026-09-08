/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

#import <Foundation/Foundation.h>
#import "SDRDexTypes.h"

NS_ASSUME_NONNULL_BEGIN

// DEX 字节码文件对象：负责解析 DEX header 及各类表，
// 供类加载器构建运行时类元数据、供解释器读取代码。
@interface SDRDexFile : NSObject

@property (nonatomic, strong, readonly) NSData *data;
@property (nonatomic, readonly) const uint8_t *base;
@property (nonatomic, readonly) uint32_t size;
@property (nonatomic, copy, readonly) NSString *magic;
@property (nonatomic, readonly) uint8_t versionMajor;
@property (nonatomic, readonly) uint8_t versionMinor;

- (nullable instancetype)initWithData:(NSData *)data error:(NSError **)error;

// 基础读取（带边界检查，越界返回 0）
- (uint8_t)u1:(uint32_t)off;
- (uint16_t)u2:(uint32_t)off;
- (uint32_t)u4:(uint32_t)off;

// 表计数
@property (nonatomic, readonly) uint32_t stringIdsSize;
@property (nonatomic, readonly) uint32_t typeIdsSize;
@property (nonatomic, readonly) uint32_t protoIdsSize;
@property (nonatomic, readonly) uint32_t fieldIdsSize;
@property (nonatomic, readonly) uint32_t methodIdsSize;
@property (nonatomic, readonly) uint32_t classDefsSize;

// 字符串 / 类型
- (NSString *)stringByIdx:(uint32_t)stringIdx;
- (NSString *)typeDescriptor:(uint16_t)typeIdx;

// field id 三元组
- (uint16_t)fieldClassIdx:(uint32_t)fieldIdx;
- (uint16_t)fieldTypeIdx:(uint32_t)fieldIdx;
- (uint32_t)fieldNameIdx:(uint32_t)fieldIdx;

// method id 三元组 + 派生
- (uint16_t)methodClassIdx:(uint32_t)methodIdx;
- (uint16_t)methodProtoIdx:(uint32_t)methodIdx;
- (uint32_t)methodNameIdx:(uint32_t)methodIdx;
- (NSString *)methodName:(uint32_t)methodIdx;
- (NSString *)methodDescriptor:(uint32_t)methodIdx;   // 由 proto 重建，如 "(II)V"

// class def 访问
- (uint32_t)classDefClassIdx:(uint16_t)classDefIdx;
- (uint32_t)classDefAccessFlags:(uint16_t)classDefIdx;
- (uint16_t)classDefSuperclassIdx:(uint16_t)classDefIdx;
- (uint32_t)classDefClassDataOff:(uint16_t)classDefIdx;

// class_data_item 遍历（编码字段直接/间接方法）
- (void)forEachFieldAtClassDataOff:(uint32_t)off
                             block:(void (^)(uint32_t fieldIdx, uint32_t accessFlags))block;
- (void)forEachMethodAtClassDataOff:(uint32_t)off
                              block:(void (^)(uint32_t methodIdx, uint32_t accessFlags, uint32_t codeOff))block;

// code_item 解析到方法对象（含 try/catch 区域）
- (BOOL)parseCodeItemAtOff:(uint32_t)codeOff into:(SDRDexMethod *)method error:(NSError **)error;

@end

// 基础类型描述符 -> 枚举
FOUNDATION_EXPORT SDRDexPrimitiveType SDRDexPrimitiveTypeFromDescriptor(NSString *desc);

NS_ASSUME_NONNULL_END