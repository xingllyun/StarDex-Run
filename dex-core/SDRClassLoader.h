/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

#import <Foundation/Foundation.h>
#import "SDRDexTypes.h"
#import "SDRDexParser.h"

NS_ASSUME_NONNULL_BEGIN

// 类加载器：聚合多个 DEX（主 DEX + 分包 DEX），惰性构建运行时类元数据。
// 职责：类查找 → 验证(基础) → 准备 → 解析（继承链）→ 提供 <clinit> 供解释器初始化。
@interface SDRClassLoader : NSObject

@property (nonatomic, strong) NSMutableArray<SDRDexFile *> *dexFiles;

- (instancetype)init;

// 添加一个 DEX（主包或分包），统一类加载命名空间。
- (void)addDexFile:(SDRDexFile *)dexFile;

// 按描述符查找类（如 "Lcom/example/Foo;"）；惰性构建并串联继承链，但不执行 <clinit>。
- (nullable SDRDexClass *)findClassByDescriptor:(NSString *)descriptor;

// 返回指定类的 <clinit> 静态初始化方法（若存在）。
- (nullable SDRDexMethod *)clinitMethodForClass:(SDRDexClass *)clazz;

// 在类及其继承链上按方法名（+ 可选描述符）解析方法。
- (nullable SDRDexMethod *)resolveMethod:(NSString *)name
                              descriptor:(nullable NSString *)descriptor
                                 inClass:(SDRDexClass *)clazz;

@end

NS_ASSUME_NONNULL_END