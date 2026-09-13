/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

#import "SDRClassLoader.h"

@implementation SDRClassLoader {
    // 描述符 -> 引用数组（每项 @{ @"dex": SDRDexFile, @"idx": @(classDefIdx) }）
    NSMutableDictionary<NSString *, NSMutableArray<NSDictionary *> *> *_classRefs;
    // 描述符 -> 已构建的类
    NSMutableDictionary<NSString *, SDRDexClass *> *_loadedClasses;
}

- (instancetype)init {
    if (self = [super init]) {
        _dexFiles = [NSMutableArray array];
        _classRefs = [NSMutableDictionary dictionary];
        _loadedClasses = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)addDexFile:(SDRDexFile *)dexFile {
    [_dexFiles addObject:dexFile];
    for (uint16_t i = 0; i < dexFile.classDefsSize; i++) {
        uint32_t classIdx = [dexFile classDefClassIdx:i];
        NSString *desc = [dexFile typeDescriptor:(uint16_t)classIdx];
        NSMutableArray *refs = _classRefs[desc];
        if (!refs) {
            refs = [NSMutableArray array];
            _classRefs[desc] = refs;
        }
        [refs addObject:@{@"dex": dexFile, @"idx": @(i)}];
    }
}

- (SDRDexClass *)findClassByDescriptor:(NSString *)descriptor {
    if (descriptor.length == 0) return nil;
    SDRDexClass *cached = _loadedClasses[descriptor];
    if (cached) return cached;

    NSArray<NSDictionary *> *refs = _classRefs[descriptor];
    if (refs.count == 0) return nil;
    NSDictionary *ref = refs.firstObject;

    SDRDexFile *dex = ref[@"dex"];
    uint16_t defIdx = (uint16_t)[ref[@"idx"] unsignedIntegerValue];

    SDRDexClass *clazz = [SDRDexClass new];
    clazz.dexFile = dex;
    clazz.classIdx = (uint16_t)[dex classDefClassIdx:defIdx];
    clazz.accessFlags = [dex classDefAccessFlags:defIdx];
    clazz.superclassIdx = [dex classDefSuperclassIdx:defIdx];
    clazz.descriptor = [dex typeDescriptor:clazz.classIdx];

    // 字段
    NSMutableDictionary<NSString *, SDRDexField *> *fields = [NSMutableDictionary dictionary];
    uint32_t dataOff = [dex classDefClassDataOff:defIdx];
    [dex forEachFieldAtClassDataOff:dataOff block:^(uint32_t fieldIdx, uint32_t accessFlags) {
        SDRDexField *f = [SDRDexField new];
        f.fieldIdx = fieldIdx;
        f.name = [dex stringByIdx:[dex fieldNameIdx:fieldIdx]];
        uint16_t typeIdx = [dex fieldTypeIdx:fieldIdx];
        f.typeDescriptor = [dex typeDescriptor:typeIdx];
        f.primitiveType = SDRDexPrimitiveTypeFromDescriptor(f.typeDescriptor);
        f.accessFlags = accessFlags;
        fields[f.name] = f;
    }];
    clazz.fields = fields;

    // 方法
    NSMutableDictionary<NSString *, SDRDexMethod *> *methods = [NSMutableDictionary dictionary];
    [dex forEachMethodAtClassDataOff:dataOff block:^(uint32_t methodIdx, uint32_t accessFlags, uint32_t codeOff) {
        SDRDexMethod *m = [SDRDexMethod new];
        m.methodIdx = methodIdx;
        m.name = [dex methodName:methodIdx];
        m.descriptor = [dex methodDescriptor:methodIdx];
        m.accessFlags = accessFlags;
        if (codeOff != 0 && !(accessFlags & (SDR_ACC_NATIVE | SDR_ACC_ABSTRACT))) {
            [dex parseCodeItemAtOff:codeOff into:m error:NULL];
        }
        methods[m.name] = m;
    }];
    clazz.methods = methods;

    _loadedClasses[descriptor] = clazz;

    // 解析继承链（递归加载父类）
    if (clazz.superclassIdx != 0xFFFF) {
        NSString *superDesc = [dex typeDescriptor:clazz.superclassIdx];
        clazz.superClass = [self findClassByDescriptor:superDesc];
    }
    return clazz;
}

- (SDRDexMethod *)clinitMethodForClass:(SDRDexClass *)clazz {
    return clazz.methods[@"<clinit>"];
}

- (SDRDexMethod *)resolveMethod:(NSString *)name
                     descriptor:(NSString *)descriptor
                        inClass:(SDRDexClass *)clazz {
    SDRDexClass *cursor = clazz;
    while (cursor) {
        SDRDexMethod *m = cursor.methods[name];
        if (m) {
            if (descriptor == nil || [m.descriptor isEqualToString:descriptor]) {
                return m;
            }
        }
        cursor = cursor.superClass;
    }
    return nil;
}

@end