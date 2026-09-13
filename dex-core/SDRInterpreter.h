/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

#import <Foundation/Foundation.h>
#import "SDRDexTypes.h"
#import "SDRDexParser.h"

@class SDRClassLoader;

NS_ASSUME_NONNULL_BEGIN

// 一次方法调用的执行结果（正常返回值或异常）。
@interface SDRExecOutcome : NSObject
@property (nonatomic, assign) SDRValue value;
@property (nonatomic, assign) uint8_t kind;               // SDRReturnKind
@property (nonatomic, strong, nullable) SDRDexObject *exception;  // 非 nil 表示抛异常
@property (nonatomic, strong, nullable) NSError *error;   // 致命错误（指令越界/超限等）
+ (instancetype)outcomeWithValue:(SDRValue)value kind:(uint8_t)kind;
+ (instancetype)outcomeWithException:(SDRDexObject *)exception;
+ (instancetype)outcomeWithError:(NSString *)message;
@end

// 字节码解释器：以 64bit 寄存器槽模型执行 Dalvik 指令。
// 宽类型（long/double）在单个槽内完整存放，对象引用直接存指针，
// 由 heapObjects 统一持有保证对象生命周期。
@interface SDRInterpreter : NSObject

@property (nonatomic, weak) SDRClassLoader *classLoader;
@property (nonatomic, assign) uint64_t instructionLimit;   // 死循环保护阈值
@property (nonatomic, readonly) uint64_t instructionCount;
@property (nonatomic, readonly) uint32_t frameDepth;       // 当前调用栈深度
@property (nonatomic, strong) NSMutableArray<id> *heapObjects;  // 根引用集合

- (instancetype)initWithClassLoader:(SDRClassLoader *)classLoader;

// 顶层入口：调用静态方法（如入口 main / 测试方法）。
- (SDRExecOutcome *)invokeStaticMethod:(NSString *)methodName
                            descriptor:(NSString *)descriptor
                               inClass:(SDRDexClass *)clazz
                                  args:(NSArray<NSValue *> *)args;

// 顶层入口：调用实例方法（自动完成类 <clinit> 初始化，首参为接收者）。
- (SDRExecOutcome *)invokeInstanceMethod:(NSString *)methodName
                              descriptor:(NSString *)descriptor
                                  object:(SDRDexObject *)object
                                    args:(NSArray<NSValue *> *)args;

// 通用调用：args 为 SDRValueBox 数组（按 descriptor 顺序）。
- (SDRExecOutcome *)invokeMethod:(SDRDexMethod *)method args:(NSArray<NSValue *> *)args;

// 重置执行保护计数（每次顶层运行前调用）。
- (void)resetInstructionCount;

@end

NS_ASSUME_NONNULL_END