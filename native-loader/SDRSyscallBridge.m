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

- (BOOL)fullSyscallSupportAvailable { return YES; }

- (void)_memcpy:(void *)dst src:(const void *)src count:(size_t)count { if (dst && src && count) memcpy(dst, src, count); }
- (void)_memset:(void *)dst byte:(int)byte count:(size_t)count { if (dst && count) memset(dst, byte, count); }
- (void)_memmove:(void *)dst src:(const void *)src count:(size_t)count { if (dst && src && count) memmove(dst, src, count); }
- (int)_memcmp:(const void *)a b:(const void *)b count:(size_t)count {
    if (a == NULL || b == NULL) return a == b ? 0 : (a ? 1 : -1);
    return memcmp(a, b, count);
}

- (size_t)_strlen:(const char *)s { return s ? strlen(s) : 0; }
- (int)_strcmp:(const char *)a b:(const char *)b {
    if (a == NULL || b == NULL) return a == b ? 0 : (a ? 1 : -1);
    return strcmp(a, b);
}
- (int)_strncmp:(const char *)a b:(const char *)b count:(size_t)count {
    if (a == NULL || b == NULL) return a == b ? 0 : (a ? 1 : -1);
    return strncmp(a, b, count);
}
- (char *)_strcpy:(char *)dst src:(const char *)src {
    if (!dst || !src) return dst;
    return strcpy(dst, src);
}
- (char *)_strncpy:(char *)dst src:(const char *)src count:(size_t)count {
    if (!dst || !src) return dst;
    return strncpy(dst, src, count);
}
- (char *)_strcat:(char *)dst src:(const char *)src {
    if (!dst || !src) return dst;
    return strcat(dst, src);
}
- (char *)_strncat:(char *)dst src:(const char *)src count:(size_t)count {
    if (!dst || !src) return dst;
    return strncat(dst, src, count);
}
- (const char *)_strchr:(const char *)s c:(int)c { return s ? strchr(s, c) : NULL; }
- (const char *)_strstr:(const char *)haystack needle:(const char *)needle {
    if (!haystack || !needle) return NULL;
    return strstr(haystack, needle);
}

- (int)_open:(const char *)pathname flags:(int)flags { return pathname ? open(pathname, flags) : -1; }
- (int)_close:(int)fd { return close(fd); }
- (ssize_t)_read:(int)fd buf:(void *)buf count:(size_t)count { return (fd >= 0 && buf && count) ? read(fd, buf, count) : -1; }
- (ssize_t)_write:(int)fd buf:(const void *)buf count:(size_t)count { return (fd >= 0 && buf && count) ? write(fd, buf, count) : -1; }
- (off_t)_lseek:(int)fd offset:(off_t)offset whence:(int)whence { return (fd >= 0) ? lseek(fd, offset, whence) : (off_t)-1; }

@end