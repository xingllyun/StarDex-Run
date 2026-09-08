/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - HttpURLConnection

// HttpURLConnection 基础实现：映射 iOS NSURLSession。
@interface SDRHttpURLConnection : NSObject
@property (nonatomic, copy) NSString *method;            // GET / POST / PUT / DELETE
@property (nonatomic, copy, nullable) NSDictionary<NSString *, NSString *> *headers;
@property (nonatomic, strong, nullable) NSData *bodyData;
- (instancetype)initWithURL:(NSURL *)url;
// 同步发送，返回响应体；网络错误时 error 非空。
- (nullable NSData *)sendAndReceiveResponseWithError:(NSError **)error;
// 异步发送，完成回调（主线程）。
- (void)sendAsyncWithCompletion:(void (^)(nullable NSData *data, NSInteger statusCode, NSError * _Nullable error))completion;
@end

#pragma mark - Socket

// Socket 基础 TCP / UDP 通信支持。
@interface SDRSocket : NSObject
@property (nonatomic, readonly) BOOL connected;
- (instancetype)initTCPWithHost:(NSString *)host port:(uint16_t)port;
- (instancetype)initUDPWithHost:(NSString *)host port:(uint16_t)port;
- (BOOL)connectTCP:(NSError **)error;
- (NSInteger)sendData:(NSData *)data error:(NSError **)error;
- (nullable NSData *)receiveDataWithMaxLength:(NSUInteger)maxLength error:(NSError **)error;
- (void)close;
@end

#pragma mark - 网络状态监听

// 网络状态监听：映射 iOS 系统网络状态接口。
@interface SDRNetworkMonitor : NSObject
+ (instancetype)sharedInstance;
@property (nonatomic, copy, nullable) void (^onStatusChange)(NSInteger status);
- (void)startMonitoring;
- (void)stopMonitoring;
- (BOOL)isNetworkReachable;
@end

NS_ASSUME_NONNULL_END