/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

#import "SDREntitlementChecker.h"
#import <mach/mach.h>
#import <os/proc.h>

// ============================================================================
// 权限键定义（侧载运行硬性要求的签名权限）
// ============================================================================

// 大地址空间：利用 64 位扩展虚拟寻址能力，支撑大段寄存器/堆映射。
static NSString *const kEntLargeAddressSpace = @"com.apple.developer.kernel.extended-virtual-addressing";
// 大内存：提高进程 Jetsam 内存上限，支撑 APK 运行时堆分配。
static NSString *const kEntLargeMemory = @"com.apple.developer.kernel.increased-memory-limit";

// ============================================================================
// 结果模型
// ============================================================================

@implementation SDREntitlementReport

- (NSArray<NSString *> *)missingTitles {
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    if (self.largeAddressSpace != SDREntitlementPresent) [out addObject:@"大地址空间"];
    if (self.largeMemory != SDREntitlementPresent) [out addObject:@"大内存"];
    return out;
}

- (BOOL)fullySatisfied {
    return self.largeAddressSpace == SDREntitlementPresent &&
           self.largeMemory == SDREntitlementPresent;
}

- (NSString *)summaryText {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    [parts addObject:[NSString stringWithFormat:@"大地址空间：%@", [self textForStatus:self.largeAddressSpace]]];
    [parts addObject:[NSString stringWithFormat:@"大内存：%@", [self textForStatus:self.largeMemory]]];
    return [parts componentsJoinedByString:@"\n"];
}

- (NSString *)degradedTipText {
    NSArray<NSString *> *missing = self.missingTitles;
    if (missing.count == 0) return nil;
    return [NSString stringWithFormat:@"缺少签名权限：%@。当前证书无法完整运行，请更换支持「大地址空间」「大内存」权限的侧载签名证书。",
            [missing componentsJoinedByString:@"、"]];
}

- (NSString *)textForStatus:(SDREntitlementStatus)status {
    switch (status) {
        case SDREntitlementPresent: return @"已开启";
        case SDREntitlementMissing: return @"缺失";
        case SDREntitlementUnknown: return @"无法检测";
    }
}

@end

// ============================================================================
// 检测器
// ============================================================================

@implementation SDREntitlementChecker

+ (SDREntitlementReport *)checkCurrentProcess {
    SDREntitlementReport *report = [SDREntitlementReport new];

    NSDictionary<NSString *, id> *entitlements = [self embeddedProvisionEntitlements];
    if (entitlements) {
        report.largeAddressSpace = [self statusForBoolValue:entitlements[kEntLargeAddressSpace]];
        report.largeMemory = [self statusForBoolValue:entitlements[kEntLargeMemory]];
        // 描述文件作为判定来源时可确认状态，无需额外探测。
        return report;
    }

    // 无嵌入描述文件（如 ad-hoc / 免费个人证书签名）：退化为运行时探测（尽力而为）。
    report.largeMemory = [self probeIncreasedMemoryLimit];
    report.largeAddressSpace = SDREntitlementUnknown; // 无可靠运行时探测手段，标记为无法检测
    return report;
}

+ (nullable NSDictionary<NSString *, id> *)embeddedProvisionEntitlements {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"embedded" ofType:@"mobileprovision"];
    if (!path) return nil;
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data || data.length == 0) return nil;

    // mobileprovision 是 CMS (PKCS7) 容器，内部包裹一段标准 XML 属性列表。
    // 直接定位 <plist ...> ... </plist> 片段即可解析。
    NSString *text = [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];
    if (!text) return nil;

    NSRange plistStart = [text rangeOfString:@"<plist"];
    NSRange plistEnd = [text rangeOfString:@"</plist>"];
    if (plistStart.location == NSNotFound || plistEnd.location == NSNotFound) return nil;

    NSUInteger plistLen = NSMaxRange(plistEnd) - plistStart.location;
    NSRange plistRange = NSMakeRange(plistStart.location, plistLen);
    NSData *plistData = [data subdataWithRange:plistRange];

    NSDictionary *provision = [NSPropertyListSerialization propertyListWithData:plistData
                                                                        options:0
                                                                         format:NULL
                                                                          error:nil];
    if (![provision isKindOfClass:[NSDictionary class]]) return nil;
    id ents = provision[@"Entitlements"];
    return [ents isKindOfClass:[NSDictionary class]] ? ents : nil;
}

// 内联解析 BOOL 权限。
+ (SDREntitlementStatus)statusForBoolValue:(id)value {
    if ([value isKindOfClass:[NSNumber class]]) {
        return [value boolValue] ? SDREntitlementPresent : SDREntitlementMissing;
    }
    return SDREntitlementUnknown;
}

// 运行时探测「大内存」：比较进程 phys_footprint 上限是否显著高于普通 App 的默认上限。
// 普通侧载 App 默认 Jetsam 上限一般在数百 MB 量级；开启 increased-memory-limit 后可达数 GB。
+ (SDREntitlementStatus)probeIncreasedMemoryLimit {
    // 优先用系统 API 获取当前进程的物理内存预算。
    int64_t limit = 0;
    if (@available(iOS 13.0, *)) {
        limit = os_proc_available_memory();
    }
    // os_proc_available_memory 返回“当前可用”，非“上限”，此处仅作参考；
    // 真正上限需通过 task_vm_info 的 phys_footprint 与 host 内存综合判断。
    if (limit > 5ull * 1024 * 1024 * 1024) {
        return SDREntitlementPresent;
    }
    if (limit > 2ull * 1024 * 1024 * 1024) {
        // 可用内存高于 2GB 视为已享受放宽的内存策略。
        return SDREntitlementPresent;
    }

    // 备选：读取 task 的 resident/phys footprint 与 system RAM 对照，仅作弱判定。
    mach_port_t task = mach_task_self();
    task_vm_info_data_t vmInfo;
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    if (task_info(task, TASK_VM_INFO, (task_info_t)&vmInfo, &count) == KERN_SUCCESS) {
        uint64_t physFootprint = vmInfo.phys_footprint;
        uint64_t totalRAM = [NSProcessInfo processInfo].physicalMemory;
        // 若进程物理占用已突破普通上限（约 1GB）且系统内存充裕，视为放宽。
        if (physFootprint > 1ull * 1024 * 1024 * 1024 && totalRAM > 4ull * 1024 * 1024 * 1024) {
            return SDREntitlementPresent;
        }
    }
    return SDREntitlementUnknown;
}

@end