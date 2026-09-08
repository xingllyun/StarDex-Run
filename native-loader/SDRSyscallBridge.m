/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

#import "SDRSyscallBridge.h"
#import <stdlib.h>
#import <string.h>
#import <fcntl.h>
#import <unistd.h>

@implementation SDRSyscallBridge

+ (instancetype)sharedInstance { static id s; static dispatch_once_t t; dispatch_once(&t, ^{ s = [self new]; }); return s; }

- (BOOL)fullSyscallSupportAvailable { return NO; }

- (void)_malloc { /* 由解释器内存管理统一持有 */ }
- (void)_free { /* 空实现占位 */ }

- (void)_memcpy:(void *)dst src:(const void *)src count:(size_t)count { memcpy(dst, src, count); }
- (void)_memset:(void *)dst byte:(int)byte count:(size_t)count { memset(dst, byte, count); }
- (size_t)_strlen:(const char *)s { return strlen(s); }
- (int)_strcmp:(const char *)a b:(const char *)b { return strcmp(a, b); }

- (int)_open:(const char *)pathname flags:(int)flags { return open(pathname, flags); }
- (int)_close:(int)fd { return close(fd); }
- (ssize_t)_read:(int)fd buf:(void *)buf count:(size_t)count { return read(fd, buf, count); }
- (ssize_t)_write:(int)fd buf:(const void *)buf count:(size_t)count { return write(fd, buf, count); }
- (off_t)_lseek:(int)fd offset:(off_t)offset whence:(int)whence { return lseek(fd, offset, whence); }

@end