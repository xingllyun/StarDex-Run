/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - SharedPreferences

// 轻量键值存储：映射 iOS 沙盒 plist（Android SharedPreferences 等价实现）。
@interface SDRSharedPreferences : NSObject
@property (nonatomic, copy, readonly) NSString *name;
- (instancetype)initWithName:(NSString *)name packageName:(NSString *)packageName;
- (nullable id)objectForKey:(NSString *)key;
- (void)setObject:(id)object forKey:(NSString *)key;
- (void)removeObjectForKey:(NSString *)key;
- (BOOL)containsKey:(NSString *)key;
- (void)flush;
@end

#pragma mark - SQLite

// SQLite 数据库封装：映射 iOS 原生 SQLite 接口。
@interface SDRSQLiteDatabase : NSObject
- (nullable instancetype)initWithPath:(NSString *)path error:(NSError **)error;
- (BOOL)executeStatement:(NSString *)sql error:(NSError **)error;
- (nullable NSArray<NSDictionary<NSString *, id> *> *)queryStatement:(NSString *)sql error:(NSError **)error;
- (void)close;
@end

#pragma mark - 文件存储

// 文件存储：模拟安卓 /data/data/[包名]/ 目录结构，对应 iOS 沙盒路径。
@interface SDRFileStorage : NSObject
@property (nonatomic, copy, readonly) NSString *packageName;
// 沙盒根（对应安卓 data 目录）：<App沙盒>/Documents/apps/<包名>/
@property (nonatomic, copy, readonly) NSString *dataRoot;
@property (nonatomic, copy, readonly) NSString *filesDir;
@property (nonatomic, copy, readonly) NSString *cacheDir;
@property (nonatomic, copy, readonly) NSString *databasesDir;
- (instancetype)initWithPackageName:(NSString *)packageName;
- (BOOL)writeData:(NSData *)data toRelativePath:(NSString *)relativePath error:(NSError **)error;
- (nullable NSData *)readDataAtRelativePath:(NSString *)relativePath error:(NSError **)error;
// Android 绝对路径（如 /data/data/x/files/a.txt）→ 沙盒相对路径。
+ (nullable NSString *)relativePathForAndroidPath:(NSString *)androidPath;
@end

NS_ASSUME_NONNULL_END