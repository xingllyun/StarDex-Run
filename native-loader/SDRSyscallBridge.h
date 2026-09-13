/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// 系统调用映射：实现 libc 常用基础函数 → iOS 系统 libc 对应接口的映射。
// 当前阶段提供最小系统调用映射；预留完整系统调用全量映射扩展位。
@interface SDRSyscallBridge : NSObject

+ (instancetype)sharedInstance;

// 基础 libc 映射：内存操作。
- (void)_memcpy:(void *)dst src:(const void *)src count:(size_t)count;
- (void)_memset:(void *)dst byte:(int)byte count:(size_t)count;
- (void)_memmove:(void *)dst src:(const void *)src count:(size_t)count;
- (int)_memcmp:(const void *)a b:(const void *)b count:(size_t)count;

// 基础 libc 映射：字符串操作。
- (size_t)_strlen:(const char *)s;
- (int)_strcmp:(const char *)a b:(const char *)b;
- (int)_strncmp:(const char *)a b:(const char *)b count:(size_t)count;
- (char *)_strcpy:(char *)dst src:(const char *)src;
- (char *)_strncpy:(char *)dst src:(const char *)src count:(size_t)count;
- (char *)_strcat:(char *)dst src:(const char *)src;
- (char *)_strncat:(char *)dst src:(const char *)src count:(size_t)count;
- (const char *)_strchr:(const char *)s c:(int)c;
- (const char *)_strstr:(const char *)haystack needle:(const char *)needle;

// 基础 libc 映射：文件描述符操作（映射到 iOS fd 语义）。
- (int)_open:(const char *)pathname flags:(int)flags;
- (int)_close:(int)fd;
- (ssize_t)_read:(int)fd buf:(void *)buf count:(size_t)count;
- (ssize_t)_write:(int)fd buf:(const void *)buf count:(size_t)count;
- (off_t)_lseek:(int)fd offset:(off_t)offset whence:(int)whence;

// 预留：完整系统调用全量映射扩展位（进程、线程、网络、信号等后续补充）。
@property (nonatomic, readonly) BOOL fullSyscallSupportAvailable;

@end

NS_ASSUME_NONNULL_END