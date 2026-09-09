/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

#import "SDRNetworking.h"
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <SystemConfiguration/SystemConfiguration.h>

#pragma mark - HttpURLConnection

@implementation SDRHttpURLConnection {
    NSURL *_url;
}

- (instancetype)initWithURL:(NSURL *)url {
    if (self = [super init]) {
        _url = url;
        _method = @"GET";
    }
    return self;
}

- (NSData *)sendAndReceiveResponseWithError:(NSError **)error {
    __block NSData *result = nil;
    __block NSInteger code = 0;
    __block NSError *err = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:_url];
    req.HTTPMethod = _method;
    [_headers enumerateKeysAndObjectsUsingBlock:^(NSString *k, NSString *v, BOOL *stop) {
        [req setValue:v forHTTPHeaderField:k];
    }];
    if (_bodyData) req.HTTPBody = _bodyData;

    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:
      ^(NSData *data, NSURLResponse *resp, NSError *e) {
        result = data;
        if ([resp isKindOfClass:[NSHTTPURLResponse class]]) code = ((NSHTTPURLResponse *)resp).statusCode;
        err = e;
        dispatch_semaphore_signal(sem);
    }] resume];
    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    if (err && error) *error = err;
    return result;
}

- (void)sendAsyncWithCompletion:(void (^)(NSData *, NSInteger, NSError *))completion {
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:_url];
    req.HTTPMethod = _method;
    if (_bodyData) req.HTTPBody = _bodyData;
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:
      ^(NSData *data, NSURLResponse *resp, NSError *e) {
        NSInteger code = [resp isKindOfClass:[NSHTTPURLResponse class]] ? ((NSHTTPURLResponse *)resp).statusCode : 0;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(data, code, e);
        });
    }] resume];
}

@end

#pragma mark - Socket

@implementation SDRSocket {
    NSString *_host;
    uint16_t _port;
    BOOL _udp;
    int _socketFD;
    struct sockaddr_in _addr;
}

- (instancetype)initTCPWithHost:(NSString *)host port:(uint16_t)port {
    self = [super init];
    _host = host; _port = port; _udp = NO; _socketFD = -1; return self;
}

- (instancetype)initUDPWithHost:(NSString *)host port:(uint16_t)port {
    self = [super init];
    _host = host; _port = port; _udp = YES; _socketFD = -1; return self;
}

- (BOOL)connectTCP:(NSError **)error {
    _socketFD = socket(AF_INET, _udp ? SOCK_DGRAM : SOCK_STREAM, 0);
    if (_socketFD < 0) return NO;
    _addr.sin_family = AF_INET;
    _addr.sin_port = htons(_port);
    inet_pton(AF_INET, _host.UTF8String, &_addr.sin_addr);
    if (!_udp && connect(_socketFD, (struct sockaddr *)&_addr, sizeof(_addr)) < 0) return NO;
    return YES;
}

- (NSInteger)sendData:(NSData *)data error:(NSError **)error {
    ssize_t n = _udp
        ? sendto(_socketFD, data.bytes, data.length, 0, (struct sockaddr *)&_addr, sizeof(_addr))
        : send(_socketFD, data.bytes, data.length, 0);
    return (NSInteger)n;
}

- (NSData *)receiveDataWithMaxLength:(NSUInteger)maxLength error:(NSError **)error {
    NSMutableData *buf = [NSMutableData dataWithLength:maxLength];
    ssize_t n = recv(_socketFD, buf.mutableBytes, maxLength, 0);
    if (n <= 0) return nil;
    return [buf subdataWithRange:NSMakeRange(0, (NSUInteger)n)];
}

- (BOOL)connected { return _socketFD >= 0; }

- (void)close { if (_socketFD >= 0) { close(_socketFD); _socketFD = -1; } }

@end

#pragma mark - NetworkMonitor

@implementation SDRNetworkMonitor
+ (instancetype)sharedInstance { static id s; static dispatch_once_t t; dispatch_once(&t, ^{ s = [self new]; }); return s; }
- (void)startMonitoring {}
- (void)stopMonitoring {}
- (BOOL)isNetworkReachable {
    SCNetworkReachabilityRef ref = SCNetworkReachabilityCreateWithName(NULL, "captive.apple.com");
    SCNetworkReachabilityFlags flags = 0;
    BOOL ok = ref && SCNetworkReachabilityGetFlags(ref, &flags);
    if (ref) CFRelease(ref);
    return ok && (flags & kSCNetworkReachabilityFlagsReachable);
}
@end