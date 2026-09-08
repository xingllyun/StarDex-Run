/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

#import "SDRDexTypes.h"
#import <objc/message.h>
#import <string.h>

NSValue *SDRValueWrap(SDRValue v) {
    SDRValueBox box;
    box.v = v;
    return [NSValue valueWithBytes:&box objCType:@encode(SDRValueBox)];
}

SDRValue SDRValueUnwrap(NSValue *box) {
    SDRValueBox b;
    b.v.bits = 0;
    if (box) { [box getValue:&b]; }
    return b.v;
}

SDRValue SDRMakeInt(int32_t v)          { SDRValue r; r.bits = 0; r.i = v; return r; }
SDRValue SDRMakeLong(int64_t v)         { SDRValue r; r.j = v; return r; }
SDRValue SDRMakeFloat(float v)          { SDRValue r; r.bits = 0; r.f = v; return r; }
SDRValue SDRMakeDouble(double v)        { SDRValue r; r.d = v; return r; }
SDRValue SDRMakeObject(void *ref)       { SDRValue r; r.bits = 0; r.l = ref; return r; }

#pragma mark - SDRDexObject

@implementation SDRDexObject

- (instancetype)initWithClass:(SDRDexClass *)clazz {
    if (self = [super init]) {
        _clazz = clazz;
        _instanceFields = [NSMutableDictionary dictionary];
    }
    return self;
}

@end

#pragma mark - SDRDexArray

@implementation SDRDexArray

- (instancetype)initWithType:(SDRDexPrimitiveType)type length:(uint32_t)length {
    if (self = [super init]) {
        _elementType = type;
        _length = length;
        if (type == SDRDexTypeObject) {
            _objectElements = [NSMutableArray arrayWithCapacity:length];
            for (uint32_t i = 0; i < length; i++) { [_objectElements addObject:[NSNull null]]; }
        } else {
            _primitiveData = [NSMutableData dataWithLength:(NSUInteger)length * [self elementWidth]];
        }
    }
    return self;
}

- (uint32_t)elementWidth {
    switch (_elementType) {
        case SDRDexTypeBoolean:
        case SDRDexTypeByte: return 1;
        case SDRDexTypeShort:
        case SDRDexTypeChar: return 2;
        case SDRDexTypeInt:
        case SDRDexTypeFloat: return 4;
        case SDRDexTypeLong:
        case SDRDexTypeDouble: return 8;
        default: return 4;
    }
}

- (SDRValue)getAt:(uint32_t)index {
    if (index >= _length) { SDRValue z; z.bits = 0; return z; }
    if (_elementType == SDRDexTypeObject) {
        id obj = _objectElements[index];
        return SDRMakeObject((__bridge void *)(obj == [NSNull null] ? nil : obj));
    }
    uint8_t *base = (uint8_t *)_primitiveData.bytes + ((NSUInteger)index * [self elementWidth]);
    switch (_elementType) {
        case SDRDexTypeBoolean: return SDRMakeInt(*(uint8_t *)base ? 1 : 0);
        case SDRDexTypeByte:    return SDRMakeInt(*(int8_t *)base);
        case SDRDexTypeShort:   return SDRMakeInt(*(int16_t *)base);
        case SDRDexTypeChar:    return SDRMakeInt(*(uint16_t *)base);
        case SDRDexTypeInt:     return SDRMakeInt(*(int32_t *)base);
        case SDRDexTypeFloat: {
            SDRValue v; v.bits = 0; memcpy(&v.f, base, 4); return v;
        }
        case SDRDexTypeLong: {
            SDRValue v; memcpy(&v.j, base, 8); return v;
        }
        case SDRDexTypeDouble: {
            SDRValue v; memcpy(&v.d, base, 8); return v;
        }
        default: { SDRValue z; z.bits = 0; return z; }
    }
}

- (void)put:(SDRValue)value at:(uint32_t)index {
    if (index >= _length) return;
    if (_elementType == SDRDexTypeObject) {
        id obj = (__bridge id)value.l;
        _objectElements[index] = obj ? obj : [NSNull null];
        return;
    }
    uint8_t *base = (uint8_t *)_primitiveData.bytes + ((NSUInteger)index * [self elementWidth]);
    switch (_elementType) {
        case SDRDexTypeBoolean: *(uint8_t *)base = value.i ? 1 : 0; break;
        case SDRDexTypeByte:    *(int8_t *)base = (int8_t)value.i; break;
        case SDRDexTypeShort:   *(int16_t *)base = (int16_t)value.i; break;
        case SDRDexTypeChar:    *(uint16_t *)base = (uint16_t)value.i; break;
        case SDRDexTypeInt:     *(int32_t *)base = value.i; break;
        case SDRDexTypeFloat:   memcpy(base, &value.f, 4); break;
        case SDRDexTypeLong:    memcpy(base, &value.j, 8); break;
        case SDRDexTypeDouble:  memcpy(base, &value.d, 8); break;
        default: break;
    }
}

@end

#pragma mark - SDRDexClass

@implementation SDRDexClass

- (instancetype)init {
    if (self = [super init]) {
        _staticFields = [NSMutableDictionary dictionary];
        _superclassIdx = 0xFFFF;
    }
    return self;
}

- (SDRDexMethod *)methodByName:(NSString *)name {
    return _methods[name];
}

- (SDRDexField *)fieldByName:(NSString *)name {
    return _fields[name];
}

@end

#pragma mark - SDRDexField

@implementation SDRDexField
@end

#pragma mark - SDRDexMethod

@implementation SDRDexMethod

- (BOOL)isNative { return (_accessFlags & SDR_ACC_NATIVE) != 0; }
- (BOOL)isAbstract { return (_accessFlags & SDR_ACC_ABSTRACT) != 0; }

@end

#pragma mark - SDRCatchHandler

@implementation SDRCatchHandler
@end

#pragma mark - SDRTryRegion

@implementation SDRTryRegion

- (BOOL)containsPc:(uint32_t)pc {
    return pc >= _startAddr && pc < _endAddr;
}

@end

#pragma mark - SDRFrame

@implementation SDRFrame

- (instancetype)initWithMethod:(SDRDexMethod *)method {
    if (self = [super init]) {
        _method = method;
        _registersSize = method.registersSize;
        _pc = 0;
        if (_registersSize > 0) {
            _registers = (SDRValue *)calloc(_registersSize, sizeof(SDRValue));
        }
    }
    return self;
}

- (void)dealloc {
    if (_registers) { free(_registers); _registers = NULL; }
}

@end