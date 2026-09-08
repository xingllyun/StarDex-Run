/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

#import <Foundation/Foundation.h>

#ifndef SDRDexTypes_h
#define SDRDexTypes_h

@class SDRDexFile;
@class SDRDexClass;
@class SDRDexObject;
@class SDRDexArray;
@class SDRTryRegion;
@class SDRCatchHandler;

#pragma mark - 值表示

// Dalvik 寄存器为 64bit 槽位，宽类型（long/double）与对象引用占满，
// 窄类型（int/float/short/byte/char/boolean）占用低 32bit。
typedef union {
    int64_t  j;   // long / double(按位) 整段
    int32_t  i;   // int / float(按位) 低 32bit
    uint32_t u;
    float    f;
    double   d;
    void    *l;   // 对象引用
    uint64_t bits;
} SDRValue;

// 用于将 SDRValue 放入 NSValue / NSDictionary 的包装结构。
typedef struct {
    SDRValue v;
} SDRValueBox;

FOUNDATION_EXPORT NSValue *SDRValueWrap(SDRValue v);
FOUNDATION_EXPORT SDRValue SDRValueUnwrap(NSValue *box);
FOUNDATION_EXPORT SDRValue SDRMakeInt(int32_t v);
FOUNDATION_EXPORT SDRValue SDRMakeLong(int64_t v);
FOUNDATION_EXPORT SDRValue SDRMakeFloat(float v);
FOUNDATION_EXPORT SDRValue SDRMakeDouble(double v);
FOUNDATION_EXPORT SDRValue SDRMakeObject(void *ref);

#pragma mark - 基本类型

typedef NS_ENUM(uint8_t, SDRDexPrimitiveType) {
    SDRDexTypeBoolean = 0,
    SDRDexTypeByte,
    SDRDexTypeShort,
    SDRDexTypeChar,
    SDRDexTypeInt,
    SDRDexTypeFloat,
    SDRDexTypeLong,
    SDRDexTypeDouble,
    SDRDexTypeObject   // 引用类型（数组元素或对象引用）
};

// 方法/类访问标志（DEX spec access_flags）
typedef NS_OPTIONS(uint32_t, SDRDexAccessFlags) {
    SDR_ACC_PUBLIC       = 0x0001,
    SDR_ACC_PRIVATE      = 0x0002,
    SDR_ACC_PROTECTED    = 0x0004,
    SDR_ACC_STATIC       = 0x0008,
    SDR_ACC_FINAL        = 0x0010,
    SDR_ACC_SYNCHRONIZED = 0x0020,
    SDR_ACC_VOLATILE     = 0x0040,
    SDR_ACC_BRIDGE       = 0x0040,
    SDR_ACC_TRANSIENT    = 0x0080,
    SDR_ACC_VARARGS      = 0x0080,
    SDR_ACC_NATIVE       = 0x0100,
    SDR_ACC_INTERFACE    = 0x0200,
    SDR_ACC_ABSTRACT     = 0x0400,
    SDR_ACC_STRICT       = 0x0800,
    SDR_ACC_SYNTHETIC    = 0x1000,
    SDR_ACC_ANNOTATION   = 0x2000,
    SDR_ACC_ENUM         = 0x4000,
    SDR_ACC_CONSTRUCTOR  = 0x10000,
    SDR_ACC_DECLARED_SYNCHRONIZED = 0x20000
};

#pragma mark - 运行时对象

// 引用类型的实例对象（对应 new-instance 结果）。
@interface SDRDexObject : NSObject
@property (nonatomic, weak) SDRDexClass *clazz;
// field_id index(number) -> SDRValueBox；宽字段存完整 64bit。
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSValue *> *instanceFields;
- (instancetype)initWithClass:(SDRDexClass *)clazz;
@end

// 基础类型数组（new-array / filled-new-array 结果）。
@interface SDRDexArray : NSObject
@property (nonatomic, assign) SDRDexPrimitiveType elementType;
@property (nonatomic, assign) uint32_t length;
// 元素存储：非对象类型用 bridge 的连续内存，对象类型存 NSMutableArray。
@property (nonatomic, strong) NSMutableData *primitiveData;   // 每元素宽度按类型
@property (nonatomic, strong) NSMutableArray *objectElements; // SDRDexObject*
- (instancetype)initWithType:(SDRDexPrimitiveType)type length:(uint32_t)length;
- (uint32_t)elementWidth;
- (SDRValue)getAt:(uint32_t)index;
- (void)put:(SDRValue)value at:(uint32_t)index;
@end

#pragma mark - 运行时元数据

// 已解析的类定义。
@interface SDRDexClass : NSObject
@property (nonatomic, weak) SDRDexFile *dexFile;
@property (nonatomic, copy) NSString *descriptor;     // 如 "Lcom/example/Foo;"
@property (nonatomic, assign) uint16_t classIdx;
@property (nonatomic, assign) uint16_t superclassIdx; // 0xFFFF 表示无
@property (nonatomic, assign) uint32_t accessFlags;
@property (nonatomic, weak) SDRDexClass *superClass;
@property (nonatomic, strong) NSDictionary<NSString *, SDRDexField *> *fields;
@property (nonatomic, strong) NSDictionary<NSString *, SDRDexMethod *> *methods;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSValue *> *staticFields; // field_id -> box
@property (nonatomic, assign) BOOL initialized;
- (SDRDexMethod *)methodByName:(NSString *)name;
- (SDRDexField *)fieldByName:(NSString *)name;
@end

// 字段定义。
@interface SDRDexField : NSObject
@property (nonatomic, weak) SDRDexClass *owner;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *typeDescriptor;
@property (nonatomic, assign) SDRDexPrimitiveType primitiveType;
@property (nonatomic, assign) uint32_t accessFlags;
@property (nonatomic, assign) uint32_t fieldIdx;
@end

// 方法定义（含代码）。
@interface SDRDexMethod : NSObject
@property (nonatomic, weak) SDRDexClass *owner;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *descriptor;   // 完整方法描述符
@property (nonatomic, assign) uint32_t accessFlags;
@property (nonatomic, assign) uint32_t methodIdx;
// 代码项（native/abstract 方法以下字段无效）
@property (nonatomic, assign) uint16_t registersSize;
@property (nonatomic, assign) uint16_t insSize;
@property (nonatomic, assign) uint16_t outsSize;
@property (nonatomic, assign) const uint16_t *insns;  // 指向 dex data 段，需随 dexFile 存活
@property (nonatomic, assign) uint32_t insnsSize;
@property (nonatomic, assign) uint32_t triesSize;
@property (nonatomic, strong) NSArray<SDRTryRegion *> *tryRegions;  // 异常处理区域
- (BOOL)isNative;
- (BOOL)isAbstract;
@end

// 单个 catch 处理器（catch-all 时 typeDescriptor 为空）。
@interface SDRCatchHandler : NSObject
@property (nonatomic, copy) NSString *typeDescriptor;
@property (nonatomic, assign) uint16_t typeIdx;     // 0xFFFF 表示 catch-all
@property (nonatomic, assign) uint32_t handlerAddr; // code unit 地址
@property (nonatomic, assign) BOOL catchAll;
@end

// 一个 try 区域及其 catch 处理器列表。
@interface SDRTryRegion : NSObject
@property (nonatomic, assign) uint32_t startAddr;   // 包含，code unit
@property (nonatomic, assign) uint32_t endAddr;     // 不包含，code unit
@property (nonatomic, strong) NSArray<SDRCatchHandler *> *handlers;
- (BOOL)containsPc:(uint32_t)pc;
@end

#pragma mark - 执行帧

// 一次方法调用的栈帧。
@interface SDRFrame : NSObject
@property (nonatomic, weak) SDRDexMethod *method;
@property (nonatomic, assign) uint32_t pc;           // 当前指令在 insns 中的下标（以 code unit 计）
@property (nonatomic, assign) SDRValue *registers;   // 长度 = registersSize
@property (nonatomic, assign) uint32_t registersSize;
@property (nonatomic, assign) SDRValue result;       // 调用返回值
@property (nonatomic, assign) uint8_t resultKind;    // SDRReturnKind
@property (nonatomic, strong) SDRDexObject *caughtException;  // move-exception 读取
- (instancetype)initWithMethod:(SDRDexMethod *)method;
@end

// 返回结果类型。
typedef NS_ENUM(uint8_t, SDRReturnKind) {
    SDRReturnVoid = 0,
    SDRReturnInt,
    SDRReturnLong,
    SDRReturnFloat,
    SDRReturnDouble,
    SDRReturnObject
};

#endif /* SDRDexTypes_h */