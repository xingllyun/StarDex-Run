/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

#import "SDRInterpreter.h"
#import "SDRClassLoader.h"
#import "SDROpcodes.h"

#pragma mark - 描述符工具

// 解析方法描述符的参数类型列表（完整描述符）。
static NSArray<NSString *> *SDRParseDescriptorParams(NSString *desc) {
    NSInteger open = [desc rangeOfString:@"("].location;
    NSInteger close = [desc rangeOfString:@")"].location;
    if (open == NSNotFound || close == NSNotFound || close <= open) return @[];
    NSString *params = [desc substringWithRange:NSMakeRange(open + 1, close - open - 1)];
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    NSUInteger i = 0, n = params.length;
    while (i < n) {
        unichar c = [params characterAtIndex:i];
        if (c == 'L') {
            NSRange semiRange = [params rangeOfString:@";" options:0 range:NSMakeRange(i, n - i)];
            if (semiRange.location == NSNotFound) break;
            [result addObject:[params substringWithRange:NSMakeRange(i, semiRange.location - i + 1)]];
            i = semiRange.location + 1;
        } else if (c == '[') {
            NSUInteger j = i;
            while (j < n && [params characterAtIndex:j] == '[') j++;
            if (j < n && [params characterAtIndex:j] == 'L') {
                NSRange semiRange = [params rangeOfString:@";" options:0 range:NSMakeRange(j, n - j)];
                if (semiRange.location == NSNotFound) break;
                [result addObject:[params substringWithRange:NSMakeRange(i, semiRange.location - i + 1)]];
                i = semiRange.location + 1;
            } else {
                [result addObject:[params substringWithRange:NSMakeRange(i, j - i + 1)]];
                i = j + 1;
            }
        } else {
            [result addObject:[params substringWithRange:NSMakeRange(i, 1)]];
            i += 1;
        }
    }
    return result;
}

static BOOL SDRIsWideType(NSString *t) { unichar c = [t characterAtIndex:0]; return c == 'J' || c == 'D'; }
static BOOL SDRIsObjectType(NSString *t) { unichar c = [t characterAtIndex:0]; return c == 'L' || c == '['; }

static uint8_t SDRReturnKindForDescriptor(NSString *desc) {
    NSInteger close = [desc rangeOfString:@")"].location;
    if (close == NSNotFound || close + 1 >= (NSInteger)desc.length) return SDRReturnVoid;
    unichar c = [desc characterAtIndex:(NSUInteger)(close + 1)];
    if (c == 'V') return SDRReturnVoid;
    if (c == 'J') return SDRReturnLong;
    if (c == 'D') return SDRReturnDouble;
    if (c == 'F') return SDRReturnFloat;
    if (c == 'L' || c == '[') return SDRReturnObject;
    return SDRReturnInt;
}

static int32_t SDRSignExtend16(uint16_t v) { return (int32_t)(int16_t)v; }
static int32_t SDRSignExtend8(uint8_t v) { return (int32_t)(int8_t)v; }

#pragma mark - 结果对象

@implementation SDRExecOutcome

+ (instancetype)outcomeWithValue:(SDRValue)value kind:(uint8_t)kind {
    SDRExecOutcome *o = [SDRExecOutcome new];
    o.value = value; o.kind = kind;
    return o;
}
+ (instancetype)outcomeWithException:(SDRDexObject *)exception {
    SDRExecOutcome *o = [SDRExecOutcome new];
    o.exception = exception; o.kind = SDRReturnVoid;
    return o;
}
+ (instancetype)outcomeWithError:(NSString *)message {
    SDRExecOutcome *o = [SDRExecOutcome new];
    o.error = [NSError errorWithDomain:@"SDRInterpreter" code:1
                              userInfo:@{NSLocalizedDescriptionKey: message}];
    return o;
}

@end

#pragma mark - 解释器

@implementation SDRInterpreter

- (instancetype)initWithClassLoader:(SDRClassLoader *)classLoader {
    if (self = [super init]) {
        _classLoader = classLoader;
        _instructionLimit = 100000000;  // 默认 1 亿条，防死循环
        _heapObjects = [NSMutableArray array];
    }
    return self;
}

- (void)resetInstructionCount { _instructionCount = 0; }

#pragma mark - 顶层入口

- (SDRExecOutcome *)invokeStaticMethod:(NSString *)methodName
                            descriptor:(NSString *)descriptor
                               inClass:(SDRDexClass *)clazz
                                  args:(NSArray<NSValue *> *)args {
    // 确保类初始化
    [self ensureClassInitialized:clazz];
    SDRDexMethod *m = [_classLoader resolveMethod:methodName descriptor:descriptor inClass:clazz];
    if (!m) {
        return [SDRExecOutcome outcomeWithError:
                [NSString stringWithFormat:@"找不到方法 %@%@", methodName, descriptor]];
    }
    [self resetInstructionCount];
    return [self invokeMethod:m args:args];
}

- (SDRExecOutcome *)invokeMethod:(SDRDexMethod *)method args:(NSArray<NSValue *> *)args {
    if (!method) return [SDRExecOutcome outcomeWithError:@"空方法"];
    if (method.isNative) {
        return [self invokeNativeMethod:method args:args];
    }
    if (method.isAbstract) {
        return [SDRExecOutcome outcomeWithError:[NSString stringWithFormat:@"抽象方法 %@ 不可调用", method.name]];
    }

    SDRFrame *frame = [[SDRFrame alloc] initWithMethod:method];
    // 展开参数到 ins 槽：实例方法首槽为 this（引用，占 1 逻辑槽），随后为参数；
    // 宽类型（long/double）在 DEX 布局中占 2 个逻辑槽，但本模型仅写入低位槽即可。
    NSArray<NSString *> *params = SDRParseDescriptorParams(method.descriptor);
    uint32_t start = method.registersSize - method.insSize;
    uint32_t slot = start;
    NSUInteger argIndex = 0;
    if (!method.isStatic) {
        if (argIndex < args.count) {
            frame.registers[slot] = SDRValueUnwrap(args[argIndex++]);
        }
        slot += 1;
    }
    for (NSUInteger i = 0; i < params.count && argIndex < args.count; i++) {
        frame.registers[slot] = SDRValueUnwrap(args[argIndex++]);
        slot += (SDRIsWideType(params[i]) ? 2 : 1);
    }
    return [self executeFrame:frame];
}

#pragma mark - 类初始化

- (void)ensureClassInitialized:(SDRDexClass *)clazz {
    if (!clazz || clazz.initialized) return;
    if (clazz.superClass) [self ensureClassInitialized:clazz.superClass];
    SDRDexMethod *clinit = [_classLoader clinitMethodForClass:clazz];
    if (clinit) {
        [self invokeMethod:clinit args:@[]];
    }
    clazz.initialized = YES;
}

#pragma mark - 异常与对象工具

- (SDRExecOutcome *)throwException:(NSString *)typeDescriptor {
    SDRDexClass *c = [_classLoader findClassByDescriptor:typeDescriptor];
    SDRDexObject *ex = [[SDRDexObject alloc] initWithClass:c];
    [_heapObjects addObject:ex];
    return [SDRExecOutcome outcomeWithException:ex];
}

- (BOOL)object:(SDRDexObject *)obj isInstanceOfClass:(SDRDexClass *)type {
    if (!obj) return NO;
    SDRDexClass *cur = obj.clazz;
    while (cur) {
        if (cur == type) return YES;
        cur = cur.superClass;
    }
    return NO;
}

- (void)registerHeapObject:(id)obj {
    if (obj) [_heapObjects addObject:obj];
}

#pragma mark - 主执行循环

- (SDRExecOutcome *)executeFrame:(SDRFrame *)frame {
    SDRDexMethod *method = frame.method;
    const uint16_t *insns = method.insns;
    uint32_t insnsSize = method.insnsSize;
    SDRValue *r = frame.registers;

    uint32_t pc = frame.pc;

    while (1) {
        if (pc >= insnsSize) {
            return [SDRExecOutcome outcomeWithError:@"指令指针越界（缺少 return）"];
        }
        // 执行保护
        _instructionCount++;
        if (_instructionLimit > 0 && _instructionCount > _instructionLimit) {
            return [SDRExecOutcome outcomeWithError:@"指令执行数超限，疑似死循环被终止"];
        }

        uint16_t ins = insns[pc];
        uint8_t op = ins & 0xFF;

        switch (op) {
            case SDR_OP_NOP:
                pc += 1;
                break;

            /* ===== move ===== */
            case SDR_OP_MOVE: {
                uint8_t a = (ins >> 8) & 0xF, b = (ins >> 12) & 0xF;
                r[a].i = r[b].i; pc += 1; break;
            }
            case SDR_OP_MOVE_FROM16: {
                uint8_t a = ins >> 8; uint16_t b = insns[pc + 1];
                r[a].i = r[b].i; pc += 2; break;
            }
            case SDR_OP_MOVE_16: {
                uint16_t a = insns[pc + 1], b = insns[pc + 2];
                r[a].i = r[b].i; pc += 3; break;
            }
            case SDR_OP_MOVE_WIDE: {
                uint8_t a = (ins >> 8) & 0xF, b = (ins >> 12) & 0xF;
                r[a].j = r[b].j; pc += 1; break;
            }
            case SDR_OP_MOVE_WIDE_FROM16: {
                uint8_t a = ins >> 8; uint16_t b = insns[pc + 1];
                r[a].j = r[b].j; pc += 2; break;
            }
            case SDR_OP_MOVE_WIDE_16: {
                uint16_t a = insns[pc + 1], b = insns[pc + 2];
                r[a].j = r[b].j; pc += 3; break;
            }
            case SDR_OP_MOVE_OBJECT: {
                uint8_t a = (ins >> 8) & 0xF, b = (ins >> 12) & 0xF;
                r[a].l = r[b].l; pc += 1; break;
            }
            case SDR_OP_MOVE_OBJECT_FROM16: {
                uint8_t a = ins >> 8; uint16_t b = insns[pc + 1];
                r[a].l = r[b].l; pc += 2; break;
            }
            case SDR_OP_MOVE_OBJECT_16: {
                uint16_t a = insns[pc + 1], b = insns[pc + 2];
                r[a].l = r[b].l; pc += 3; break;
            }
            case SDR_OP_MOVE_RESULT: {
                uint8_t a = ins >> 8;
                r[a].i = frame.result.i; pc += 1; break;
            }
            case SDR_OP_MOVE_RESULT_WIDE: {
                uint8_t a = ins >> 8;
                r[a].j = frame.result.j; pc += 1; break;
            }
            case SDR_OP_MOVE_RESULT_OBJECT: {
                uint8_t a = ins >> 8;
                r[a].l = frame.result.l; pc += 1; break;
            }
            case SDR_OP_MOVE_EXCEPTION: {
                uint8_t a = ins >> 8;
                r[a].l = (__bridge void *)frame.caughtException; pc += 1; break;
            }

            /* ===== return ===== */
            case SDR_OP_RETURN_VOID:
                return [SDRExecOutcome outcomeWithValue:SDRMakeInt(0) kind:SDRReturnVoid];
            case SDR_OP_RETURN: {
                uint8_t a = ins >> 8;
                return [SDRExecOutcome outcomeWithValue:r[a] kind:SDRReturnInt];
            }
            case SDR_OP_RETURN_WIDE: {
                uint8_t a = ins >> 8;
                return [SDRExecOutcome outcomeWithValue:r[a] kind:SDRReturnLong];
            }
            case SDR_OP_RETURN_OBJECT: {
                uint8_t a = ins >> 8;
                return [SDRExecOutcome outcomeWithValue:r[a] kind:SDRReturnObject];
            }

            /* ===== const ===== */
            case SDR_OP_CONST_4: {
                uint8_t a = (ins >> 8) & 0xF;
                int32_t v = (ins >> 12) & 0xF;
                if (v & 0x8) v |= ~0xF;  // 符号扩展 4bit
                r[a].i = v; pc += 1; break;
            }
            case SDR_OP_CONST_16: {
                uint8_t a = ins >> 8;
                r[a].i = SDRSignExtend16(insns[pc + 1]); pc += 2; break;
            }
            case SDR_OP_CONST: {
                uint8_t a = ins >> 8;
                uint32_t v = (uint32_t)insns[pc + 1] | ((uint32_t)insns[pc + 2] << 16);
                r[a].i = (int32_t)v; pc += 3; break;
            }
            case SDR_OP_CONST_HIGH16: {
                uint8_t a = ins >> 8;
                r[a].i = (int32_t)((uint32_t)insns[pc + 1] << 16); pc += 2; break;
            }
            case SDR_OP_CONST_WIDE_16: {
                uint8_t a = ins >> 8;
                r[a].j = SDRSignExtend16(insns[pc + 1]); pc += 2; break;
            }
            case SDR_OP_CONST_WIDE_32: {
                uint8_t a = ins >> 8;
                uint32_t v = (uint32_t)insns[pc + 1] | ((uint32_t)insns[pc + 2] << 16);
                r[a].j = (int32_t)v; pc += 3; break;
            }
            case SDR_OP_CONST_WIDE: {
                uint8_t a = ins >> 8;
                uint64_t v = (uint64_t)insns[pc + 1] | ((uint64_t)insns[pc + 2] << 16) |
                             ((uint64_t)insns[pc + 3] << 32) | ((uint64_t)insns[pc + 4] << 48);
                r[a].j = (int64_t)v; pc += 5; break;
            }
            case SDR_OP_CONST_WIDE_HIGH16: {
                uint8_t a = ins >> 8;
                r[a].j = (int64_t)((uint64_t)insns[pc + 1] << 48); pc += 2; break;
            }
            case SDR_OP_CONST_STRING: {
                uint8_t a = ins >> 8;
                uint16_t strIdx = insns[pc + 1];
                NSString *s = [method.owner.dexFile stringByIdx:strIdx];
                [self registerHeapObject:s];
                r[a].l = (__bridge void *)s;
                pc += 2; break;
            }
            case SDR_OP_CONST_CLASS: {
                uint8_t a = ins >> 8;
                uint16_t typeIdx = insns[pc + 1];
                NSString *desc = [method.owner.dexFile typeDescriptor:typeIdx];
                SDRDexClass *c = [_classLoader findClassByDescriptor:desc];
                [self registerHeapObject:c];
                r[a].l = (__bridge void *)c;
                pc += 2; break;
            }

            /* ===== monitor ===== */
            case SDR_OP_MONITOR_ENTER:
            case SDR_OP_MONITOR_EXIT:
                pc += 1; break;  // 单线程建模，锁为 no-op

            /* ===== cast / instance-of ===== */
            case SDR_OP_CHECK_CAST: {
                pc += 2; break;  // no-op（不做运行时强校验）
            }
            case SDR_OP_INSTANCE_OF: {
                uint8_t a = (ins >> 8) & 0xF, b = (ins >> 12) & 0xF;
                uint16_t typeIdx = insns[pc + 1];
                NSString *desc = [method.owner.dexFile typeDescriptor:typeIdx];
                SDRDexClass *t = [_classLoader findClassByDescriptor:desc];
                SDRDexObject *obj = (__bridge SDRDexObject *)r[b].l;
                r[a].i = [self object:obj isInstanceOfClass:t] ? 1 : 0;
                pc += 2; break;
            }
            case SDR_OP_ARRAY_LENGTH: {
                uint8_t a = (ins >> 8) & 0xF, b = (ins >> 12) & 0xF;
                SDRDexArray *arr = (__bridge SDRDexArray *)r[b].l;
                r[a].i = arr ? (int32_t)arr.length : 0;
                pc += 1; break;
            }

            /* ===== new-instance / new-array ===== */
            case SDR_OP_NEW_INSTANCE: {
                uint8_t a = ins >> 8;
                uint16_t typeIdx = insns[pc + 1];
                NSString *desc = [method.owner.dexFile typeDescriptor:typeIdx];
                SDRDexClass *c = [_classLoader findClassByDescriptor:desc];
                SDRDexObject *obj = [[SDRDexObject alloc] initWithClass:c];
                [self ensureClassInitialized:c];
                [self registerHeapObject:obj];
                r[a].l = (__bridge void *)obj;
                pc += 2; break;
            }
            case SDR_OP_NEW_ARRAY: {
                uint8_t a = ins >> 8;
                uint16_t typeIdx = insns[pc + 1];
                NSString *desc = [method.owner.dexFile typeDescriptor:typeIdx];
                uint8_t vb = (ins >> 12) & 0xF;
                int32_t count = r[vb].i;
                if (count < 0) return [self throwException:@"Ljava/lang/NegativeArraySizeException;"];
                SDRDexPrimitiveType elem = SDRIsObjectType(desc)
                    ? SDRDexTypeObject : SDRDexPrimitiveTypeFromDescriptor(desc);
                SDRDexArray *arr = [[SDRDexArray alloc] initWithType:elem length:(uint32_t)count];
                [self registerHeapObject:arr];
                r[a].l = (__bridge void *)arr;
                pc += 2; break;
            }
            case SDR_OP_FILLED_NEW_ARRAY:
            case SDR_OP_FILLED_NEW_ARRAY_RANGE: {
                BOOL range = (op == SDR_OP_FILLED_NEW_ARRAY_RANGE);
                uint16_t typeIdx = insns[pc + 1];
                NSString *desc = [method.owner.dexFile typeDescriptor:typeIdx];
                SDRDexPrimitiveType elem = SDRIsObjectType(desc)
                    ? SDRDexTypeObject : SDRDexPrimitiveTypeFromDescriptor(desc);
                NSMutableArray<NSValue *> *vals = [NSMutableArray array];
                if (range) {
                    uint32_t count = ins >> 8;
                    uint32_t first = insns[pc + 2];
                    // 逐元素宽度判断
                    uint32_t cur = first;
                    for (uint32_t i = 0; i < count; i++) {
                        [vals addObject:SDRValueWrap(r[cur])];
                        cur += (elem == SDRDexTypeLong || elem == SDRDexTypeDouble) ? 2 : 1;
                    }
                } else {
                    uint32_t count = (ins >> 12) & 0xF;
                    uint32_t g = (ins >> 8) & 0xF;
                    uint16_t rw = insns[pc + 2];
                    uint32_t regs[5] = { rw & 0xF, (rw >> 4) & 0xF, (rw >> 8) & 0xF, (rw >> 12) & 0xF, g };
                    for (uint32_t i = 0; i < count; i++) {
                        [vals addObject:SDRValueWrap(r[regs[i]])];
                    }
                }
                SDRDexArray *arr = [[SDRDexArray alloc] initWithType:elem length:(uint32_t)vals.count];
                [self registerHeapObject:arr];
                for (NSUInteger i = 0; i < vals.count; i++) {
                    [arr put:SDRValueUnwrap(vals[i]) at:(uint32_t)i];
                }
                frame.result = SDRMakeObject((__bridge void *)arr);
                frame.resultKind = SDRReturnObject;
                pc += 3; break;
            }

            /* ===== array get/put ===== */
            case SDR_OP_AGET:
            case SDR_OP_AGET_BOOLEAN:
            case SDR_OP_AGET_BYTE:
            case SDR_OP_AGET_CHAR:
            case SDR_OP_AGET_SHORT:
                [self agetElement:ins insns:insns pc:&pc r:r]; break;
            case SDR_OP_AGET_WIDE: {
                uint8_t a = ins >> 8; { uint8_t b = insns[pc + 1]; uint8_t c = insns[pc + 1] >> 8;
                SDRDexArray *arr = (__bridge SDRDexArray *)r[b].l; int32_t idx = r[c].i;
                r[a] = [arr getAt:(uint32_t)idx]; } pc += 2; break;
            }
            case SDR_OP_AGET_OBJECT: {
                uint8_t a = ins >> 8; uint8_t b = insns[pc + 1]; uint8_t c = insns[pc + 1] >> 8;
                SDRDexArray *arr = (__bridge SDRDexArray *)r[b].l; int32_t idx = r[c].i;
                r[a] = [arr getAt:(uint32_t)idx]; pc += 2; break;
            }
            case SDR_OP_APUT:
            case SDR_OP_APUT_BOOLEAN:
            case SDR_OP_APUT_BYTE:
            case SDR_OP_APUT_CHAR:
            case SDR_OP_APUT_SHORT:
                [self aputElement:ins insns:insns pc:&pc r:r]; break;
            case SDR_OP_APUT_WIDE: {
                uint8_t a = ins >> 8; uint8_t b = insns[pc + 1]; uint8_t c = insns[pc + 1] >> 8;
                SDRDexArray *arr = (__bridge SDRDexArray *)r[b].l; int32_t idx = r[c].i;
                [arr put:r[a] at:(uint32_t)idx]; pc += 2; break;
            }
            case SDR_OP_APUT_OBJECT: {
                uint8_t a = ins >> 8; uint8_t b = insns[pc + 1]; uint8_t c = insns[pc + 1] >> 8;
                SDRDexArray *arr = (__bridge SDRDexArray *)r[b].l; int32_t idx = r[c].i;
                [arr put:r[a] at:(uint32_t)idx]; pc += 2; break;
            }

            /* ===== 字段 get/put ===== */
            case SDR_OP_IGET:
            case SDR_OP_IGET_BOOLEAN:
            case SDR_OP_IGET_BYTE:
            case SDR_OP_IGET_CHAR:
            case SDR_OP_IGET_SHORT:
                [self igetField:ins insns:insns pc:&pc r:r]; break;
            case SDR_OP_IGET_WIDE: {
                uint8_t a = (ins >> 8) & 0xF; uint16_t fieldIdx = insns[pc + 1];
                SDRDexObject *obj = [self instObjectForField:op ins:ins r:r];
                r[a] = SDRValueUnwrap(obj.instanceFields[@(fieldIdx)]); pc += 2; break;
            }
            case SDR_OP_IGET_OBJECT: {
                uint8_t a = (ins >> 8) & 0xF; uint16_t fieldIdx = insns[pc + 1];
                SDRDexObject *obj = [self instObjectForField:op ins:ins r:r];
                r[a] = SDRValueUnwrap(obj.instanceFields[@(fieldIdx)]); pc += 2; break;
            }
            case SDR_OP_IPUT:
            case SDR_OP_IPUT_BOOLEAN:
            case SDR_OP_IPUT_BYTE:
            case SDR_OP_IPUT_CHAR:
            case SDR_OP_IPUT_SHORT:
                [self iputField:ins insns:insns pc:&pc r:r]; break;
            case SDR_OP_IPUT_WIDE: {
                uint16_t fieldIdx = insns[pc + 1];
                SDRDexObject *obj = [self instObjectForField:op ins:ins r:r];
                uint8_t src = (ins >> 8) & 0xF;
                obj.instanceFields[@(fieldIdx)] = SDRValueWrap(r[src]); pc += 2; break;
            }
            case SDR_OP_IPUT_OBJECT: {
                uint16_t fieldIdx = insns[pc + 1];
                SDRDexObject *obj = [self instObjectForField:op ins:ins r:r];
                uint8_t src = (ins >> 8) & 0xF;
                obj.instanceFields[@(fieldIdx)] = SDRValueWrap(r[src]); pc += 2; break;
            }
            case SDR_OP_SGET:
            case SDR_OP_SGET_BOOLEAN:
            case SDR_OP_SGET_BYTE:
            case SDR_OP_SGET_CHAR:
            case SDR_OP_SGET_SHORT:
                [self sgetField:ins insns:insns pc:&pc r:r dex:method.owner.dexFile]; break;
            case SDR_OP_SGET_WIDE: {
                uint8_t a = ins >> 8; uint16_t fieldIdx = insns[pc + 1];
                SDRDexClass *c = [self staticClassForField:fieldIdx dex:method.owner.dexFile];
                [self ensureClassInitialized:c];
                r[a] = SDRValueUnwrap(c.staticFields[@(fieldIdx)]); pc += 2; break;
            }
            case SDR_OP_SGET_OBJECT: {
                uint8_t a = ins >> 8; uint16_t fieldIdx = insns[pc + 1];
                SDRDexClass *c = [self staticClassForField:fieldIdx dex:method.owner.dexFile];
                [self ensureClassInitialized:c];
                r[a] = SDRValueUnwrap(c.staticFields[@(fieldIdx)]); pc += 2; break;
            }
            case SDR_OP_SPUT:
            case SDR_OP_SPUT_BOOLEAN:
            case SDR_OP_SPUT_BYTE:
            case SDR_OP_SPUT_CHAR:
            case SDR_OP_SPUT_SHORT:
                [self sputField:ins insns:insns pc:&pc r:r dex:method.owner.dexFile]; break;
            case SDR_OP_SPUT_WIDE: {
                uint16_t fieldIdx = insns[pc + 1];
                SDRDexClass *c = [self staticClassForField:fieldIdx dex:method.owner.dexFile];
                [self ensureClassInitialized:c];
                uint8_t src = ins >> 8;
                c.staticFields[@(fieldIdx)] = SDRValueWrap(r[src]); pc += 2; break;
            }
            case SDR_OP_SPUT_OBJECT: {
                uint16_t fieldIdx = insns[pc + 1];
                SDRDexClass *c = [self staticClassForField:fieldIdx dex:method.owner.dexFile];
                [self ensureClassInitialized:c];
                uint8_t src = ins >> 8;
                c.staticFields[@(fieldIdx)] = SDRValueWrap(r[src]); pc += 2; break;
            }

            /* ===== invoke ===== */
            case SDR_OP_INVOKE_VIRTUAL:
            case SDR_OP_INVOKE_SUPER:
            case SDR_OP_INVOKE_DIRECT:
            case SDR_OP_INVOKE_STATIC:
            case SDR_OP_INVOKE_INTERFACE:
            case SDR_OP_INVOKE_VIRTUAL_RANGE:
            case SDR_OP_INVOKE_SUPER_RANGE:
            case SDR_OP_INVOKE_DIRECT_RANGE:
            case SDR_OP_INVOKE_STATIC_RANGE:
            case SDR_OP_INVOKE_INTERFACE_RANGE: {
                SDRExecOutcome *o = [self performInvoke:op frame:frame atPc:pc];
                if (o.error) return o;
                if (o.exception) {
                    SDRExecOutcome *h = [self dispatchException:o.exception frame:frame atPc:pc];
                    if (h) return h; // 无法继续（要么向上抛，要么致命错误）
                    // 成功捕获后需重新定位到 handler，直接 continue 但 pc 需已设置
                    // dispatchException 成功会设置 frame.pc 与 caughtException 并返回 nil
                } else {
                    frame.result = o.value;
                    frame.resultKind = o.kind;
                }
                // 计算指令长度：range 与普通均为 3 单元
                pc += 3; break;
            }

            /* ===== 单目 ===== */
            case SDR_OP_NEG_INT:  { uint8_t a = ins >> 8; r[a].i = -r[a].i; pc += 1; break; }
            case SDR_OP_NOT_INT:  { uint8_t a = ins >> 8; r[a].i = ~r[a].i; pc += 1; break; }
            case SDR_OP_NEG_LONG: { uint8_t a = ins >> 8; r[a].j = -r[a].j; pc += 1; break; }
            case SDR_OP_NOT_LONG: { uint8_t a = ins >> 8; r[a].j = ~r[a].j; pc += 1; break; }
            case SDR_OP_NEG_FLOAT: { uint8_t a = ins >> 8; r[a].f = -r[a].f; pc += 1; break; }
            case SDR_OP_NEG_DOUBLE:{ uint8_t a = ins >> 8; r[a].d = -r[a].d; pc += 1; break; }

            /* ===== 类型转换 ===== */
            case SDR_OP_INT_TO_LONG:    { uint8_t a=ins>>8, b=(ins>>12)&0xF; r[a].j = (int64_t)r[b].i; pc+=1; break; }
            case SDR_OP_INT_TO_FLOAT:   { uint8_t a=ins>>8, b=(ins>>12)&0xF; r[a].f = (float)r[b].i; pc+=1; break; }
            case SDR_OP_INT_TO_DOUBLE:  { uint8_t a=ins>>8, b=(ins>>12)&0xF; r[a].d = (double)r[b].i; pc+=1; break; }
            case SDR_OP_LONG_TO_INT:    { uint8_t a=ins>>8, b=(ins>>12)&0xF; r[a].i = (int32_t)r[b].j; pc+=1; break; }
            case SDR_OP_LONG_TO_FLOAT:  { uint8_t a=ins>>8, b=(ins>>12)&0xF; r[a].f = (float)r[b].j; pc+=1; break; }
            case SDR_OP_LONG_TO_DOUBLE: { uint8_t a=ins>>8, b=(ins>>12)&0xF; r[a].d = (double)r[b].j; pc+=1; break; }
            case SDR_OP_FLOAT_TO_INT:   { uint8_t a=ins>>8, b=(ins>>12)&0xF; r[a].i = (int32_t)r[b].f; pc+=1; break; }
            case SDR_OP_FLOAT_TO_LONG:  { uint8_t a=ins>>8, b=(ins>>12)&0xF; r[a].j = (int64_t)r[b].f; pc+=1; break; }
            case SDR_OP_FLOAT_TO_DOUBLE:{ uint8_t a=ins>>8, b=(ins>>12)&0xF; r[a].d = (double)r[b].f; pc+=1; break; }
            case SDR_OP_DOUBLE_TO_INT:  { uint8_t a=ins>>8, b=(ins>>12)&0xF; r[a].i = (int32_t)r[b].d; pc+=1; break; }
            case SDR_OP_DOUBLE_TO_LONG: { uint8_t a=ins>>8, b=(ins>>12)&0xF; r[a].j = (int64_t)r[b].d; pc+=1; break; }
            case SDR_OP_DOUBLE_TO_FLOAT:{ uint8_t a=ins>>8, b=(ins>>12)&0xF; r[a].f = (float)r[b].d; pc+=1; break; }
            case SDR_OP_INT_TO_BYTE:    { uint8_t a=ins>>8, b=(ins>>12)&0xF; r[a].i = (int32_t)(int8_t)r[b].i; pc+=1; break; }
            case SDR_OP_INT_TO_CHAR:    { uint8_t a=ins>>8, b=(ins>>12)&0xF; r[a].i = (int32_t)(uint16_t)r[b].i; pc+=1; break; }
            case SDR_OP_INT_TO_SHORT:   { uint8_t a=ins>>8, b=(ins>>12)&0xF; r[a].i = (int32_t)(int16_t)r[b].i; pc+=1; break; }

            /* ===== 比较 ===== */
            case SDR_OP_CMPL_FLOAT: {
                uint8_t a = ins >> 8; uint8_t b = (insns[pc+1] & 0xFF); uint8_t c = insns[pc+1] >> 8;
                float x = r[b].f, y = r[c].f;
                r[a].i = (x > y) ? 1 : ((x < y) ? -1 : 0); pc += 2; break;
            }
            case SDR_OP_CMPG_FLOAT: {
                uint8_t a = ins >> 8; uint8_t b = insns[pc+1] & 0xFF; uint8_t c = insns[pc+1] >> 8;
                float x = r[b].f, y = r[c].f;
                r[a].i = (x > y) ? 1 : ((x < y) ? -1 : 0); pc += 2; break;
            }
            case SDR_OP_CMPL_DOUBLE: {
                uint8_t a = ins >> 8; uint8_t b = insns[pc+1] & 0xFF; uint8_t c = insns[pc+1] >> 8;
                double x = r[b].d, y = r[c].d;
                r[a].i = (x > y) ? 1 : ((x < y) ? -1 : 0); pc += 2; break;
            }
            case SDR_OP_CMPG_DOUBLE: {
                uint8_t a = ins >> 8; uint8_t b = insns[pc+1] & 0xFF; uint8_t c = insns[pc+1] >> 8;
                double x = r[b].d, y = r[c].d;
                r[a].i = (x > y) ? 1 : ((x < y) ? -1 : 0); pc += 2; break;
            }
            case SDR_OP_CMP_LONG: {
                uint8_t a = ins >> 8; uint8_t b = insns[pc+1] & 0xFF; uint8_t c = insns[pc+1] >> 8;
                int64_t x = r[b].j, y = r[c].j;
                r[a].i = (x > y) ? 1 : ((x < y) ? -1 : 0); pc += 2; break;
            }

            /* ===== 分支 ===== */
            case SDR_OP_GOTO: {
                int32_t off = SDRSignExtend8((uint8_t)(ins >> 8));
                pc = (uint32_t)((int32_t)pc + off); break;
            }
            case SDR_OP_GOTO_16: {
                int32_t off = SDRSignExtend16(insns[pc + 1]);
                pc = (uint32_t)((int32_t)pc + off); break;
            }
            case SDR_OP_GOTO_32: {
                int32_t off = (int32_t)((uint32_t)insns[pc + 1] | ((uint32_t)insns[pc + 2] << 16));
                pc = (uint32_t)((int32_t)pc + off); break;
            }
            case SDR_OP_IF_EQ: case SDR_OP_IF_NE:
            case SDR_OP_IF_LT: case SDR_OP_IF_GE:
            case SDR_OP_IF_GT: case SDR_OP_IF_LE: {
                uint8_t a = (ins >> 8) & 0xF, b = (ins >> 12) & 0xF;
                int32_t x = r[a].i, y = r[b].i;
                int32_t off = SDRSignExtend16(insns[pc + 1]);
                BOOL take = NO;
                switch (op) {
                    case SDR_OP_IF_EQ: take = x == y; break;
                    case SDR_OP_IF_NE: take = x != y; break;
                    case SDR_OP_IF_LT: take = x < y; break;
                    case SDR_OP_IF_GE: take = x >= y; break;
                    case SDR_OP_IF_GT: take = x > y; break;
                    case SDR_OP_IF_LE: take = x <= y; break;
                }
                pc = take ? (uint32_t)((int32_t)pc + off) : pc + 2; break;
            }
            case SDR_OP_IF_EQZ: case SDR_OP_IF_NEZ:
            case SDR_OP_IF_LTZ: case SDR_OP_IF_GEZ:
            case SDR_OP_IF_GTZ: case SDR_OP_IF_LEZ: {
                uint8_t a = ins >> 8;
                int32_t x = r[a].i;
                int32_t off = SDRSignExtend16(insns[pc + 1]);
                BOOL take = NO;
                switch (op) {
                    case SDR_OP_IF_EQZ: take = x == 0; break;
                    case SDR_OP_IF_NEZ: take = x != 0; break;
                    case SDR_OP_IF_LTZ: take = x < 0; break;
                    case SDR_OP_IF_GEZ: take = x >= 0; break;
                    case SDR_OP_IF_GTZ: take = x > 0; break;
                    case SDR_OP_IF_LEZ: take = x <= 0; break;
                }
                pc = take ? (uint32_t)((int32_t)pc + off) : pc + 2; break;
            }

            /* ===== switch ===== */
            case SDR_OP_PACKED_SWITCH: {
                uint8_t a = ins >> 8;
                int32_t off = (int32_t)((uint32_t)insns[pc + 1] | ((uint32_t)insns[pc + 2] << 16));
                uint32_t dataOff = (uint32_t)((int32_t)pc + off);
                uint16_t size = insns[dataOff + 1];
                int32_t key = r[a].i;
                int32_t firstKey = (int32_t)((uint32_t)insns[dataOff + 2] | ((uint32_t)insns[dataOff + 3] << 16));
                int32_t index = key - firstKey;
                int32_t targetOff = 0;
                if (size == 0) targetOff = 0;
                else if (index >= 0 && index < size) {
                    targetOff = SDRSignExtend16(insns[dataOff + 4 + index]);
                }
                pc = (uint32_t)((int32_t)pc + targetOff); break;
            }
            case SDR_OP_SPARSE_SWITCH: {
                uint8_t a = ins >> 8;
                int32_t off0 = (int32_t)((uint32_t)insns[pc + 1] | ((uint32_t)insns[pc + 2] << 16));
                uint32_t dataOff = (uint32_t)((int32_t)pc + off0);
                uint16_t size = insns[dataOff + 1];
                int32_t key = r[a].i;
                int32_t off = 0;
                for (int i = 0; i < size; i++) {
                    int32_t k = (int32_t)((uint32_t)insns[dataOff + 2 + i*2] | ((uint32_t)insns[dataOff + 3 + i*2] << 16));
                    if (k == key) {
                        off = SDRSignExtend16(insns[dataOff + 2 + size*2 + i]);
                        break;
                    }
                }
                pc = (uint32_t)((int32_t)pc + off); break;
            }

            /* ===== throw ===== */
            case SDR_OP_THROW: {
                uint8_t a = ins >> 8;
                SDRDexObject *ex = (__bridge SDRDexObject *)r[a].l;
                if (!ex) return [self throwException:@"Ljava/lang/NullPointerException;"];
                SDRExecOutcome *h = [self dispatchException:ex frame:frame atPc:pc];
                if (h) return h;
                pc += 1; break;  // 已被捕获，pc 已在 dispatchException 中设置
            }

            /* ===== fill-array-data ===== */
            case SDR_OP_FILL_ARRAY_DATA: {
                uint8_t a = ins >> 8;
                int32_t off = (int32_t)((uint32_t)insns[pc + 1] | ((uint32_t)insns[pc + 2] << 16));
                uint32_t dataOff = (uint32_t)((int32_t)pc + off);
                [self fillArrayData:dataOff insns:insns arrayReg:a r:r];
                pc += 3; break;
            }

            /* ===== 算术: 整数 3 操作数 ===== */
            case SDR_OP_ADD_INT: { uint8_t a=ins>>8,b=insns[pc+1]&0xFF,c=insns[pc+1]>>8; r[a].i=r[b].i+r[c].i; pc+=2; break; }
            case SDR_OP_SUB_INT: { uint8_t a=ins>>8,b=insns[pc+1]&0xFF,c=insns[pc+1]>>8; r[a].i=r[b].i-r[c].i; pc+=2; break; }
            case SDR_OP_MUL_INT: { uint8_t a=ins>>8,b=insns[pc+1]&0xFF,c=insns[pc+1]>>8; r[a].i=(int32_t)(r[b].i*r[c].i); pc+=2; break; }
            case SDR_OP_DIV_INT: { uint8_t a=ins>>8,b=insns[pc+1]&0xFF,c=insns[pc+1]>>8;
                if (r[c].i == 0) return [self throwException:@"Ljava/lang/ArithmeticException;"];
                r[a].i = r[b].i / r[c].i; pc+=2; break; }
            case SDR_OP_REM_INT: { uint8_t a=ins>>8,b=insns[pc+1]&0xFF,c=insns[pc+1]>>8;
                if (r[c].i == 0) return [self throwException:@"Ljava/lang/ArithmeticException;"];
                r[a].i = r[b].i % r[c].i; pc+=2; break; }
            case SDR_OP_AND_INT: { uint8_t a=ins>>8,b=insns[pc+1]&0xFF,c=insns[pc+1]>>8; r[a].i=r[b].i&r[c].i; pc+=2; break; }
            case SDR_OP_OR_INT:  { uint8_t a=ins>>8,b=insns[pc+1]&0xFF,c=insns[pc+1]>>8; r[a].i=r[b].i|r[c].i; pc+=2; break; }
            case SDR_OP_XOR_INT: { uint8_t a=ins>>8,b=insns[pc+1]&0xFF,c=insns[pc+1]>>8; r[a].i=r[b].i^r[c].i; pc+=2; break; }
            case SDR_OP_SHL_INT: { uint8_t a=ins>>8,b=insns[pc+1]&0xFF,c=insns[pc+1]>>8; r[a].i=r[b].i<<(r[c].i&0x1F); pc+=2; break; }
            case SDR_OP_SHR_INT: { uint8_t a=ins>>8,b=insns[pc+1]&0xFF,c=insns[pc+1]>>8; r[a].i=r[b].i>>(r[c].i&0x1F); pc+=2; break; }
            case SDR_OP_USHR_INT:{ uint8_t a=ins>>8,b=insns[pc+1]&0xFF,c=insns[pc+1]>>8; r[a].i=(int32_t)((uint32_t)r[b].i>>(r[c].i&0x1F)); pc+=2; break; }

            /* ===== 算术: long 3 操作数 ===== */
            case SDR_OP_ADD_LONG: { uint8_t a=ins>>8,b=insns[pc+1]&0xFF,c=insns[pc+1]>>8; r[a].j=r[b].j+r[c].j; pc+=2; break; }
            case SDR_OP_SUB_LONG: { uint8_t a=ins>>8,b=insns[pc+1]&0xFF,c=insns[pc+1]>>8; r[a].j=r[b].j-r[c].j; pc+=2; break; }
            case SDR_OP_MUL_LONG: { uint8_t a=ins>>8,b=insns[pc+1]&0xFF,c=insns[pc+1]>>8; r[a].j=(int64_t)(r[b].j*r[c].j); pc+=2; break; }
            case SDR_OP_DIV_LONG: { uint8_t a=ins>>8,b=insns[pc+1]&0xFF,c=insns[pc+1]>>8;
                if (r[c].j==0) return [self throwException:@"Ljava/lang/ArithmeticException;"];
                r[a].j = r[b].j/r[c].j; pc+=2; break; }
            case SDR_OP_REM_LONG: { uint8_t a=ins>>8,b=insns[pc+1]&0xFF,c=insns[pc+1]>>8;
                if (r[c].j==0) return [self throwException:@"Ljava/lang/ArithmeticException;"];
                r[a].j = r[b].j%r[c].j; pc+=2; break; }
            case SDR_OP_AND_LONG: { uint8_t a=ins>>8,b=insns[pc+1]&0xFF,c=insns[pc+1]>>8; r[a].j=r[b].j&r[c].j; pc+=2; break; }
            case SDR_OP_OR_LONG:  { uint8_t a=ins>>8,b=insns[pc+1]&0xFF,c=insns[pc+1]>>8; r[a].j=r[b].j|r[c].j; pc+=2; break; }
            case SDR_OP_XOR_LONG: { uint8_t a=ins>>8,b=insns[pc+1]&0xFF,c=insns[pc+1]>>8; r[a].j=r[b].j^r[c].j; pc+=2; break; }
            case SDR_OP_SHL_LONG: { uint8_t a=ins>>8,b=insns[pc+1]&0xFF,c=insns[pc+1]>>8; r[a].j=r[b].j<<(r[c].i&0x3F); pc+=2; break; }
            case SDR_OP_SHR_LONG: { uint8_t a=ins>>8,b=insns[pc+1]&0xFF,c=insns[pc+1]>>8; r[a].j=r[b].j>>(r[c].i&0x3F); pc+=2; break; }
            case SDR_OP_USHR_LONG:{ uint8_t a=ins>>8,b=insns[pc+1]&0xFF,c=insns[pc+1]>>8; r[a].j=(int64_t)((uint64_t)r[b].j>>(r[c].i&0x3F)); pc+=2; break; }

            /* ===== 算术: float/double ===== */
            case SDR_OP_ADD_FLOAT: { uint8_t a=ins>>8,b=insns[pc+1]&0xFF,c=insns[pc+1]>>8; r[a].f=r[b].f+r[c].f; pc+=2; break; }
            case SDR_OP_SUB_FLOAT: { uint8_t a=ins>>8,b=insns[pc+1]&0xFF,c=insns[pc+1]>>8; r[a].f=r[b].f-r[c].f; pc+=2; break; }
            case SDR_OP_MUL_FLOAT: { uint8_t a=ins>>8,b=insns[pc+1]&0xFF,c=insns[pc+1]>>8; r[a].f=r[b].f*r[c].f; pc+=2; break; }
            case SDR_OP_DIV_FLOAT: { uint8_t a=ins>>8,b=insns[pc+1]&0xFF,c=insns[pc+1]>>8; r[a].f=r[b].f/r[c].f; pc+=2; break; }
            case SDR_OP_REM_FLOAT: { uint8_t a=ins>>8,b=insns[pc+1]&0xFF,c=insns[pc+1]>>8; r[a].f=fmodf(r[b].f,r[c].f); pc+=2; break; }
            case SDR_OP_ADD_DOUBLE: { uint8_t a=ins>>8,b=insns[pc+1]&0xFF,c=insns[pc+1]>>8; r[a].d=r[b].d+r[c].d; pc+=2; break; }
            case SDR_OP_SUB_DOUBLE: { uint8_t a=ins>>8,b=insns[pc+1]&0xFF,c=insns[pc+1]>>8; r[a].d=r[b].d-r[c].d; pc+=2; break; }
            case SDR_OP_MUL_DOUBLE: { uint8_t a=ins>>8,b=insns[pc+1]&0xFF,c=insns[pc+1]>>8; r[a].d=r[b].d*r[c].d; pc+=2; break; }
            case SDR_OP_DIV_DOUBLE: { uint8_t a=ins>>8,b=insns[pc+1]&0xFF,c=insns[pc+1]>>8; r[a].d=r[b].d/r[c].d; pc+=2; break; }
            case SDR_OP_REM_DOUBLE: { uint8_t a=ins>>8,b=insns[pc+1]&0xFF,c=insns[pc+1]>>8; r[a].d=fmod(r[b].d,r[c].d); pc+=2; break; }

            /* ===== 算术: int 2addr ===== */
            case SDR_OP_ADD_INT_2ADDR: { uint8_t a=(ins>>8)&0xF,b=(ins>>12)&0xF; r[a].i=r[a].i+r[b].i; pc+=1; break; }
            case SDR_OP_SUB_INT_2ADDR: { uint8_t a=(ins>>8)&0xF,b=(ins>>12)&0xF; r[a].i=r[a].i-r[b].i; pc+=1; break; }
            case SDR_OP_MUL_INT_2ADDR: { uint8_t a=(ins>>8)&0xF,b=(ins>>12)&0xF; r[a].i=(int32_t)(r[a].i*r[b].i); pc+=1; break; }
            case SDR_OP_DIV_INT_2ADDR: { uint8_t a=(ins>>8)&0xF,b=(ins>>12)&0xF;
                if (r[b].i==0) return [self throwException:@"Ljava/lang/ArithmeticException;"];
                r[a].i=r[a].i/r[b].i; pc+=1; break; }
            case SDR_OP_REM_INT_2ADDR: { uint8_t a=(ins>>8)&0xF,b=(ins>>12)&0xF;
                if (r[b].i==0) return [self throwException:@"Ljava/lang/ArithmeticException;"];
                r[a].i=r[a].i%r[b].i; pc+=1; break; }
            case SDR_OP_AND_INT_2ADDR: { uint8_t a=(ins>>8)&0xF,b=(ins>>12)&0xF; r[a].i=r[a].i&r[b].i; pc+=1; break; }
            case SDR_OP_OR_INT_2ADDR:  { uint8_t a=(ins>>8)&0xF,b=(ins>>12)&0xF; r[a].i=r[a].i|r[b].i; pc+=1; break; }
            case SDR_OP_XOR_INT_2ADDR: { uint8_t a=(ins>>8)&0xF,b=(ins>>12)&0xF; r[a].i=r[a].i^r[b].i; pc+=1; break; }
            case SDR_OP_SHL_INT_2ADDR: { uint8_t a=(ins>>8)&0xF,b=(ins>>12)&0xF; r[a].i=r[a].i<<(r[b].i&0x1F); pc+=1; break; }
            case SDR_OP_SHR_INT_2ADDR: { uint8_t a=(ins>>8)&0xF,b=(ins>>12)&0xF; r[a].i=r[a].i>>(r[b].i&0x1F); pc+=1; break; }
            case SDR_OP_USHR_INT_2ADDR:{ uint8_t a=(ins>>8)&0xF,b=(ins>>12)&0xF; r[a].i=(int32_t)((uint32_t)r[a].i>>(r[b].i&0x1F)); pc+=1; break; }

            case SDR_OP_ADD_LONG_2ADDR: { uint8_t a=(ins>>8)&0xF,b=(ins>>12)&0xF; r[a].j=r[a].j+r[b].j; pc+=1; break; }
            case SDR_OP_SUB_LONG_2ADDR: { uint8_t a=(ins>>8)&0xF,b=(ins>>12)&0xF; r[a].j=r[a].j-r[b].j; pc+=1; break; }
            case SDR_OP_MUL_LONG_2ADDR: { uint8_t a=(ins>>8)&0xF,b=(ins>>12)&0xF; r[a].j=(int64_t)(r[a].j*r[b].j); pc+=1; break; }
            case SDR_OP_DIV_LONG_2ADDR: { uint8_t a=(ins>>8)&0xF,b=(ins>>12)&0xF;
                if (r[b].j==0) return [self throwException:@"Ljava/lang/ArithmeticException;"];
                r[a].j=r[a].j/r[b].j; pc+=1; break; }
            case SDR_OP_REM_LONG_2ADDR: { uint8_t a=(ins>>8)&0xF,b=(ins>>12)&0xF;
                if (r[b].j==0) return [self throwException:@"Ljava/lang/ArithmeticException;"];
                r[a].j=r[a].j%r[b].j; pc+=1; break; }
            case SDR_OP_AND_LONG_2ADDR: { uint8_t a=(ins>>8)&0xF,b=(ins>>12)&0xF; r[a].j=r[a].j&r[b].j; pc+=1; break; }
            case SDR_OP_OR_LONG_2ADDR:  { uint8_t a=(ins>>8)&0xF,b=(ins>>12)&0xF; r[a].j=r[a].j|r[b].j; pc+=1; break; }
            case SDR_OP_XOR_LONG_2ADDR: { uint8_t a=(ins>>8)&0xF,b=(ins>>12)&0xF; r[a].j=r[a].j^r[b].j; pc+=1; break; }
            case SDR_OP_SHL_LONG_2ADDR: { uint8_t a=(ins>>8)&0xF,b=(ins>>12)&0xF; r[a].j=r[a].j<<(r[b].i&0x3F); pc+=1; break; }
            case SDR_OP_SHR_LONG_2ADDR: { uint8_t a=(ins>>8)&0xF,b=(ins>>12)&0xF; r[a].j=r[a].j>>(r[b].i&0x3F); pc+=1; break; }
            case SDR_OP_USHR_LONG_2ADDR:{ uint8_t a=(ins>>8)&0xF,b=(ins>>12)&0xF; r[a].j=(int64_t)((uint64_t)r[a].j>>(r[b].i&0x3F)); pc+=1; break; }

            case SDR_OP_ADD_FLOAT_2ADDR: { uint8_t a=(ins>>8)&0xF,b=(ins>>12)&0xF; r[a].f=r[a].f+r[b].f; pc+=1; break; }
            case SDR_OP_SUB_FLOAT_2ADDR: { uint8_t a=(ins>>8)&0xF,b=(ins>>12)&0xF; r[a].f=r[a].f-r[b].f; pc+=1; break; }
            case SDR_OP_MUL_FLOAT_2ADDR: { uint8_t a=(ins>>8)&0xF,b=(ins>>12)&0xF; r[a].f=r[a].f*r[b].f; pc+=1; break; }
            case SDR_OP_DIV_FLOAT_2ADDR: { uint8_t a=(ins>>8)&0xF,b=(ins>>12)&0xF; r[a].f=r[a].f/r[b].f; pc+=1; break; }
            case SDR_OP_REM_FLOAT_2ADDR: { uint8_t a=(ins>>8)&0xF,b=(ins>>12)&0xF; r[a].f=fmodf(r[a].f,r[b].f); pc+=1; break; }
            case SDR_OP_ADD_DOUBLE_2ADDR: { uint8_t a=(ins>>8)&0xF,b=(ins>>12)&0xF; r[a].d=r[a].d+r[b].d; pc+=1; break; }
            case SDR_OP_SUB_DOUBLE_2ADDR: { uint8_t a=(ins>>8)&0xF,b=(ins>>12)&0xF; r[a].d=r[a].d-r[b].d; pc+=1; break; }
            case SDR_OP_MUL_DOUBLE_2ADDR: { uint8_t a=(ins>>8)&0xF,b=(ins>>12)&0xF; r[a].d=r[a].d*r[b].d; pc+=1; break; }
            case SDR_OP_DIV_DOUBLE_2ADDR: { uint8_t a=(ins>>8)&0xF,b=(ins>>12)&0xF; r[a].d=r[a].d/r[b].d; pc+=1; break; }
            case SDR_OP_REM_DOUBLE_2ADDR: { uint8_t a=(ins>>8)&0xF,b=(ins>>12)&0xF; r[a].d=fmod(r[a].d,r[b].d); pc+=1; break; }

            /* ===== lit16 ===== */
            case SDR_OP_ADD_INT_LIT16: { uint8_t a=ins>>8,b=(ins>>12)&0xF; int32_t lit=SDRSignExtend16(insns[pc+1]); r[a].i=r[b].i+lit; pc+=2; break; }
            case SDR_OP_RSUB_INT:      { uint8_t a=ins>>8,b=(ins>>12)&0xF; int32_t lit=SDRSignExtend16(insns[pc+1]); r[a].i=lit-r[b].i; pc+=2; break; }
            case SDR_OP_MUL_INT_LIT16: { uint8_t a=ins>>8,b=(ins>>12)&0xF; int32_t lit=SDRSignExtend16(insns[pc+1]); r[a].i=(int32_t)(r[b].i*lit); pc+=2; break; }
            case SDR_OP_DIV_INT_LIT16: { uint8_t a=ins>>8,b=(ins>>12)&0xF; int32_t lit=SDRSignExtend16(insns[pc+1]);
                if (lit==0) return [self throwException:@"Ljava/lang/ArithmeticException;"];
                r[a].i=r[b].i/lit; pc+=2; break; }
            case SDR_OP_REM_INT_LIT16: { uint8_t a=ins>>8,b=(ins>>12)&0xF; int32_t lit=SDRSignExtend16(insns[pc+1]);
                if (lit==0) return [self throwException:@"Ljava/lang/ArithmeticException;"];
                r[a].i=r[b].i%lit; pc+=2; break; }
            case SDR_OP_AND_INT_LIT16: { uint8_t a=ins>>8,b=(ins>>12)&0xF; int32_t lit=SDRSignExtend16(insns[pc+1]); r[a].i=r[b].i&lit; pc+=2; break; }
            case SDR_OP_OR_INT_LIT16:  { uint8_t a=ins>>8,b=(ins>>12)&0xF; int32_t lit=SDRSignExtend16(insns[pc+1]); r[a].i=r[b].i|lit; pc+=2; break; }
            case SDR_OP_XOR_INT_LIT16: { uint8_t a=ins>>8,b=(ins>>12)&0xF; int32_t lit=SDRSignExtend16(insns[pc+1]); r[a].i=r[b].i^lit; pc+=2; break; }

            /* ===== lit8 ===== */
            case SDR_OP_ADD_INT_LIT8: { uint8_t a=ins>>8; int32_t lit=SDRSignExtend8((uint8_t)insns[pc+1]); r[a].i=r[a].i+lit; pc+=2; break; }
            case SDR_OP_RSUB_INT_LIT8:{ uint8_t a=ins>>8; int32_t lit=SDRSignExtend8((uint8_t)insns[pc+1]); r[a].i=lit-r[a].i; pc+=2; break; }
            case SDR_OP_MUL_INT_LIT8: { uint8_t a=ins>>8; int32_t lit=SDRSignExtend8((uint8_t)insns[pc+1]); r[a].i=(int32_t)(r[a].i*lit); pc+=2; break; }
            case SDR_OP_DIV_INT_LIT8: { uint8_t a=ins>>8; int32_t lit=SDRSignExtend8((uint8_t)insns[pc+1]);
                if (lit==0) return [self throwException:@"Ljava/lang/ArithmeticException;"];
                r[a].i=r[a].i/lit; pc+=2; break; }
            case SDR_OP_REM_INT_LIT8: { uint8_t a=ins>>8; int32_t lit=SDRSignExtend8((uint8_t)insns[pc+1]);
                if (lit==0) return [self throwException:@"Ljava/lang/ArithmeticException;"];
                r[a].i=r[a].i%lit; pc+=2; break; }
            case SDR_OP_AND_INT_LIT8: { uint8_t a=ins>>8; int32_t lit=SDRSignExtend8((uint8_t)insns[pc+1]); r[a].i=r[a].i&lit; pc+=2; break; }
            case SDR_OP_OR_INT_LIT8:  { uint8_t a=ins>>8; int32_t lit=SDRSignExtend8((uint8_t)insns[pc+1]); r[a].i=r[a].i|lit; pc+=2; break; }
            case SDR_OP_XOR_INT_LIT8: { uint8_t a=ins>>8; int32_t lit=SDRSignExtend8((uint8_t)insns[pc+1]); r[a].i=r[a].i^lit; pc+=2; break; }
            case SDR_OP_SHL_INT_LIT8: { uint8_t a=ins>>8; int32_t lit=insns[pc+1]&0xFF; r[a].i=r[a].i<<(lit&0x1F); pc+=2; break; }
            case SDR_OP_SHR_INT_LIT8: { uint8_t a=ins>>8; int32_t lit=insns[pc+1]&0xFF; r[a].i=r[a].i>>(lit&0x1F); pc+=2; break; }
            case SDR_OP_USHR_INT_LIT8:{ uint8_t a=ins>>8; int32_t lit=insns[pc+1]&0xFF; r[a].i=(int32_t)((uint32_t)r[a].i>>(lit&0x1F)); pc+=2; break; }

            /* ===== 未实现 / 高级指令 ===== */
            default: {
                return [SDRExecOutcome outcomeWithError:
                        [NSString stringWithFormat:@"未实现指令 %s (0x%02X)", SDRDexOpcodeName(op), op]];
            }
        }
    }
}

#pragma mark - 字段 / 数组辅助

- (SDRDexObject *)instObjectForField:(uint8_t)op ins:(uint16_t)ins r:(SDRValue *)r {
    uint8_t b = (ins >> 12) & 0xF;
    return (__bridge SDRDexObject *)r[b].l;
}

- (SDRDexClass *)staticClassForField:(uint32_t)fieldIdx dex:(SDRDexFile *)dex {
    uint16_t classIdx = [dex fieldClassIdx:fieldIdx];
    return [_classLoader findClassByDescriptor:[dex typeDescriptor:classIdx]];
}

// 数组元素读取（aget 家族，23x 格式：AA|op, BB|CC；返回值按数组声明元素类型由 getAt 处理）。
- (void)agetElement:(uint16_t)ins insns:(const uint16_t *)insns pc:(uint32_t *)pc r:(SDRValue *)r {
    uint8_t aa = ins >> 8;
    uint16_t regs = insns[*pc + 1];
    uint8_t arrReg = regs & 0xFF;
    uint8_t idxReg = (regs >> 8) & 0xFF;
    SDRDexArray *arr = (__bridge SDRDexArray *)r[arrReg].l;
    int32_t idx = r[idxReg].i;
    r[aa] = [arr getAt:(uint32_t)idx];
    *pc += 2;
}

// 数组元素写入（aput 家族，23x 格式）。
- (void)aputElement:(uint16_t)ins insns:(const uint16_t *)insns pc:(uint32_t *)pc r:(SDRValue *)r {
    uint8_t aa = ins >> 8;   // 值寄存器
    uint16_t regs = insns[*pc + 1];
    uint8_t arrReg = regs & 0xFF;
    uint8_t idxReg = (regs >> 8) & 0xFF;
    SDRDexArray *arr = (__bridge SDRDexArray *)r[arrReg].l;
    int32_t idx = r[idxReg].i;
    [arr put:r[aa] at:(uint32_t)idx];
    *pc += 2;
}

// 实例字段读取（iget 家族，22c 格式：B|A|op, CCCC）。
- (void)igetField:(uint16_t)ins insns:(const uint16_t *)insns pc:(uint32_t *)pc r:(SDRValue *)r {
    uint8_t a = (ins >> 8) & 0xF;
    uint8_t b = (ins >> 12) & 0xF;
    uint16_t fieldIdx = insns[*pc + 1];
    SDRDexObject *obj = (__bridge SDRDexObject *)r[b].l;
    r[a] = SDRValueUnwrap(obj.instanceFields[@(fieldIdx)]);
    *pc += 2;
}

// 实例字段写入（iput 家族，22c 格式）。
- (void)iputField:(uint16_t)ins insns:(const uint16_t *)insns pc:(uint32_t *)pc r:(SDRValue *)r {
    uint8_t a = (ins >> 8) & 0xF;
    uint8_t b = (ins >> 12) & 0xF;
    uint16_t fieldIdx = insns[*pc + 1];
    SDRDexObject *obj = (__bridge SDRDexObject *)r[b].l;
    obj.instanceFields[@(fieldIdx)] = SDRValueWrap(r[a]);
    *pc += 2;
}

// 静态字段读取（sget 家族，21c 格式：AA|op, BBBB）。
- (void)sgetField:(uint16_t)ins insns:(const uint16_t *)insns pc:(uint32_t *)pc r:(SDRValue *)r dex:(SDRDexFile *)dex {
    uint8_t a = ins >> 8;
    uint16_t fieldIdx = insns[*pc + 1];
    SDRDexClass *c = [self staticClassForField:fieldIdx dex:dex];
    [self ensureClassInitialized:c];
    r[a] = SDRValueUnwrap(c.staticFields[@(fieldIdx)]);
    *pc += 2;
}

// 静态字段写入（sput 家族，21c 格式）。
- (void)sputField:(uint16_t)ins insns:(const uint16_t *)insns pc:(uint32_t *)pc r:(SDRValue *)r dex:(SDRDexFile *)dex {
    uint8_t a = ins >> 8;
    uint16_t fieldIdx = insns[*pc + 1];
    SDRDexClass *c = [self staticClassForField:fieldIdx dex:dex];
    [self ensureClassInitialized:c];
    c.staticFields[@(fieldIdx)] = SDRValueWrap(r[a]);
    *pc += 2;
}

// 填充 fill-array-data 常量数据（payload 结构：ident, element_width, size, data...）。
- (void)fillArrayData:(uint32_t)dataOff insns:(const uint16_t *)insns arrayReg:(uint8_t)reg r:(SDRValue *)r {
    SDRDexArray *arr = (__bridge SDRDexArray *)r[reg].l;
    if (!arr) return;
    uint16_t ident = insns[dataOff];
    uint16_t elemWidth = insns[dataOff + 1];
    uint32_t size = (uint32_t)insns[dataOff + 2] | ((uint32_t)insns[dataOff + 3] << 16);
    if (ident != 0x0300) return;
    NSUInteger toCopy = (NSUInteger)size * elemWidth;
    NSUInteger avail = (NSUInteger)arr.length * [arr elementWidth];
    if (toCopy > avail) toCopy = avail;
    if (toCopy == 0) return;
    const uint8_t *src = (const uint8_t *)&insns[dataOff + 4];
    memcpy(arr.primitiveData.mutableBytes, src, toCopy);
}

#pragma mark - invoke 处理

- (SDRExecOutcome *)performInvoke:(uint8_t)op frame:(SDRFrame *)frame atPc:(uint32_t)pc {
    SDRDexMethod *m = frame.method;
    const uint16_t *insns = m.insns;
    SDRValue *r = frame.registers;
    uint16_t ins = insns[pc];

    BOOL range = (op >= SDR_OP_INVOKE_VIRTUAL_RANGE && op <= SDR_OP_INVOKE_INTERFACE_RANGE);
    BOOL isStatic;
    switch (op) {
        case SDR_OP_INVOKE_STATIC: case SDR_OP_INVOKE_STATIC_RANGE: isStatic = YES; break;
        default: isStatic = NO; break;
    }
    BOOL isSuper = (op == SDR_OP_INVOKE_SUPER || op == SDR_OP_INVOKE_SUPER_RANGE);

    uint16_t methodIdx = insns[pc + 1];
    SDRDexFile *dex = m.owner.dexFile;
    NSString *methodName = [dex methodName:methodIdx];
    NSString *desc = [dex methodDescriptor:methodIdx];
    uint16_t ownerTypeIdx = [dex methodClassIdx:methodIdx];
    NSString *ownerDesc = [dex typeDescriptor:ownerTypeIdx];

    NSArray<NSString *> *params = SDRParseDescriptorParams(desc);

    // 收集源寄存器（含 this，若实例方法）。srcRegs 每项对应一个逻辑实参（不含幻影宽槽）。
    NSMutableArray<NSNumber *> *srcRegs = [NSMutableArray array];
    if (range) {
        // 3rc：BBBB 为起始寄存器，参数寄存器连续；宽类型在布局中占 2 槽但只取基址。
        uint32_t first = insns[pc + 2];
        uint32_t cur = first;
        if (!isStatic) { [srcRegs addObject:@(cur)]; cur += 1; }
        for (NSUInteger i = 0; i < params.count; i++) {
            [srcRegs addObject:@(cur)];
            cur += (SDRIsWideType(params[i]) ? 2 : 1);
        }
    } else {
        // 35c：A=参数字数（含 this），寄存器列表 C,D,E,F,G 依次为 this(若有)+参数。
        uint32_t g = (ins >> 8) & 0xF;
        uint16_t rw = insns[pc + 2];
        uint32_t regs[5] = { rw & 0xF, (rw >> 4) & 0xF, (rw >> 8) & 0xF, (rw >> 12) & 0xF, g };
        NSUInteger nArgs = params.count + (isStatic ? 0 : 1);
        for (NSUInteger i = 0; i < nArgs && i < 5; i++) {
            [srcRegs addObject:@(regs[i])];
        }
    }

    // 构建参数值数组（this 置于首位，与 invokeMethod 的展开约定一致）
    NSMutableArray<NSValue *> *argValues = [NSMutableArray array];
    for (NSUInteger i = 0; i < srcRegs.count; i++) {
        uint32_t reg = srcRegs[i].unsignedIntValue;
        [argValues addObject:SDRValueWrap(r[reg])];
    }

    // 确定声明类与接收者
    SDRDexClass *declClass = [_classLoader findClassByDescriptor:ownerDesc];
    SDRDexObject *receiver = nil;
    if (!isStatic) {
        uint32_t thisReg = srcRegs[0].unsignedIntValue;
        receiver = (__bridge SDRDexObject *)r[thisReg].l;
        if (!receiver || !receiver.clazz) {
            return [self throwException:@"Ljava/lang/NullPointerException;"];
        }
    }
    if (!declClass) {
        return [SDRExecOutcome outcomeWithError:
                [NSString stringWithFormat:@"找不到类 %@", ownerDesc]];
    }

    // 解析被调方法：static/direct 用声明类，super 从父类起，virtual/interface 沿接收者链查找。
    SDRDexMethod *callee = nil;
    if (isStatic || op == SDR_OP_INVOKE_DIRECT || op == SDR_OP_INVOKE_DIRECT_RANGE) {
        callee = [_classLoader resolveMethod:methodName descriptor:desc inClass:declClass];
    } else if (isSuper) {
        callee = [_classLoader resolveMethod:methodName descriptor:desc inClass:receiver.clazz.superClass];
    } else {
        callee = [_classLoader resolveMethod:methodName descriptor:desc inClass:receiver.clazz];
    }
    if (!callee) {
        return [SDRExecOutcome outcomeWithError:
                [NSString stringWithFormat:@"找不到方法 %@%@（调用点 %@）", methodName, desc, ownerDesc]];
    }

    // 静态方法调用前初始化类
    if (isStatic) [self ensureClassInitialized:callee.owner];

    return [self invokeMethod:callee args:argValues];
}

#pragma mark - 异常分发

// 在 frame 内为异常查找 try/catch；若找到则设置 pc 与 caughtException 返回 nil（正常继续），
// 否则返回异常结果交由上层（未捕获）。
- (SDRExecOutcome *)dispatchException:(SDRDexObject *)exception frame:(SDRFrame *)frame atPc:(uint32_t)pc {
    for (SDRTryRegion *region in frame.method.tryRegions) {
        if (![region containsPc:pc]) continue;
        for (SDRCatchHandler *h in region.handlers) {
            if (h.catchAll || [self object:exception isInstanceOfClass:[_classLoader findClassByDescriptor:h.typeDescriptor]]) {
                frame.caughtException = exception;
                frame.pc = h.handlerAddr;
                return nil;  // 已捕获
            }
        }
    }
    return [SDRExecOutcome outcomeWithException:exception];
}

#pragma mark - native 方法

- (SDRExecOutcome *)invokeNativeMethod:(SDRDexMethod *)method args:(NSArray<NSValue *> *)args {
    NSString *ownerDesc = method.owner.descriptor;
    NSString *key = [NSString stringWithFormat:@"%@.%@", ownerDesc, method.name];

    if ([key isEqualToString:@"Ljava/lang/Object;.<init>"]) {
        return [SDRExecOutcome outcomeWithValue:SDRMakeInt(0) kind:SDRReturnVoid];
    }
    if ([key isEqualToString:@"Ljava/lang/System;.currentTimeMillis"]) {
        return [SDRExecOutcome outcomeWithValue:SDRMakeLong((int64_t)([[NSDate date] timeIntervalSince1970] * 1000.0)) kind:SDRReturnLong];
    }
    if ([key isEqualToString:@"Ljava/lang/System;.arraycopy"]) {
        // 参数：src, srcPos, dst, dstPos, length
        SDRDexArray *src = (__bridge SDRDexArray *)SDRValueUnwrap(args[0]).l;
        int32_t srcPos = SDRValueUnwrap(args[1]).i;
        SDRDexArray *dst = (__bridge SDRDexArray *)SDRValueUnwrap(args[2]).l;
        int32_t dstPos = SDRValueUnwrap(args[3]).i;
        int32_t length = SDRValueUnwrap(args[4]).i;
        for (int32_t i = 0; i < length; i++) {
            [dst put:[src getAt:(uint32_t)(srcPos + i)] at:(uint32_t)(dstPos + i)];
        }
        return [SDRExecOutcome outcomeWithValue:SDRMakeInt(0) kind:SDRReturnVoid];
    }

    return [SDRExecOutcome outcomeWithError:
            [NSString stringWithFormat:@"native 方法未实现：%@%@", key, method.descriptor]];
}

@end