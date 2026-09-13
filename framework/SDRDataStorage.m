/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

#import "SDRDataStorage.h"
#import <sqlite3.h>

#pragma mark - SharedPreferences

@implementation SDRSharedPreferences {
    NSMutableDictionary<NSString *, id> *_store;
    NSString *_filePath;
}

- (instancetype)initWithName:(NSString *)name packageName:(NSString *)packageName {
    if (self = [super init]) {
        _name = [name copy];
        NSString *dir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        NSString *appRoot = [dir stringByAppendingPathComponent:@"apps"];
        NSString *pkgRoot = [appRoot stringByAppendingPathComponent:packageName];
        _filePath = [[pkgRoot stringByAppendingPathComponent:@"shared_prefs"]
                     stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"plist"]];
        _store = [NSMutableDictionary dictionaryWithContentsOfFile:_filePath] ?: [NSMutableDictionary dictionary];
    }
    return self;
}

- (id)objectForKey:(NSString *)key { return _store[key]; }
- (void)setObject:(id)object forKey:(NSString *)key { if (object) _store[key] = object; }
- (void)removeObjectForKey:(NSString *)key { [_store removeObjectForKey:key]; }
- (BOOL)containsKey:(NSString *)key { return _store[key] != nil; }

- (void)flush {
    [[NSFileManager defaultManager] createDirectoryAtPath:[_filePath stringByDeletingLastPathComponent]
                              withIntermediateDirectories:YES attributes:nil error:nil];
    [_store writeToFile:_filePath atomically:YES];
}

@end

#pragma mark - SQLiteDatabase

@implementation SDRSQLiteDatabase {
    sqlite3 *_db;
}

- (instancetype)initWithPath:(NSString *)path error:(NSError **)error {
    if (self = [super init]) {
        if (sqlite3_open(path.UTF8String, &_db) != SQLITE_OK) {
            if (error) *error = [NSError errorWithDomain:@"SDRSQLiteDatabase" code:1
                userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:sqlite3_errmsg(_db)]}];
            sqlite3_close(_db); _db = NULL;
            return nil;
        }
    }
    return self;
}

- (BOOL)executeStatement:(NSString *)sql error:(NSError **)error {
    if (!_db) return NO;
    char *errMsg = NULL;
    if (sqlite3_exec(_db, sql.UTF8String, NULL, NULL, &errMsg) != SQLITE_OK) {
        if (error) *error = [NSError errorWithDomain:@"SDRSQLiteDatabase" code:2
            userInfo:@{NSLocalizedDescriptionKey: errMsg ? [NSString stringWithUTF8String:errMsg] : @"执行失败"}];
        sqlite3_free(errMsg);
        return NO;
    }
    return YES;
}

- (NSArray<NSDictionary<NSString *, id> *> *)queryStatement:(NSString *)sql error:(NSError **)error {
    NSMutableArray *rows = [NSMutableArray array];
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL) != SQLITE_OK) return rows;
    int colCount = sqlite3_column_count(stmt);
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        NSMutableDictionary *row = [NSMutableDictionary dictionary];
        for (int i = 0; i < colCount; i++) {
            const char *name = sqlite3_column_name(stmt, i);
            const unsigned char *text = sqlite3_column_text(stmt, i);
            row[[NSString stringWithUTF8String:name]] = text ? [NSString stringWithUTF8String:(const char *)text] : [NSNull null];
        }
        [rows addObject:row];
    }
    sqlite3_finalize(stmt);
    return rows;
}

- (void)close { if (_db) { sqlite3_close(_db); _db = NULL; } }

@end

#pragma mark - FileStorage

@implementation SDRFileStorage

- (instancetype)initWithPackageName:(NSString *)packageName {
    if (self = [super init]) {
        _packageName = [packageName copy];
        NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        _dataRoot = [[docs stringByAppendingPathComponent:@"apps"] stringByAppendingPathComponent:packageName];
        _filesDir = [_dataRoot stringByAppendingPathComponent:@"files"];
        _cacheDir = [_dataRoot stringByAppendingPathComponent:@"cache"];
        _databasesDir = [_dataRoot stringByAppendingPathComponent:@"databases"];
    }
    return self;
}

- (NSString *)absolutePathForRelativePath:(NSString *)relativePath {
    return [_dataRoot stringByAppendingPathComponent:relativePath];
}

- (BOOL)writeData:(NSData *)data toRelativePath:(NSString *)relativePath error:(NSError **)error {
    NSString *full = [self absolutePathForRelativePath:relativePath];
    NSError *e = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:[full stringByDeletingLastPathComponent]
                              withIntermediateDirectories:YES attributes:nil error:&e];
    if (e) { if (error) *error = e; return NO; }
    return [data writeToFile:full options:NSDataWritingAtomic error:error];
}

- (NSData *)readDataAtRelativePath:(NSString *)relativePath error:(NSError **)error {
    return [NSData dataWithContentsOfFile:[self absolutePathForRelativePath:relativePath] options:0 error:error];
}

+ (NSString *)relativePathForAndroidPath:(NSString *)androidPath {
    // 形如 /data/data/[包名]/files/... → 取 files/ 之后部分。
    NSArray *comps = [androidPath pathComponents];
    NSUInteger idx = [comps indexOfObject:@"files"];
    if (idx == NSNotFound) idx = [comps indexOfObject:@"cache"];
    if (idx == NSNotFound) idx = [comps indexOfObject:@"databases"];
    if (idx == NSNotFound) return nil;
    NSArray *sub = [comps subarrayWithRange:NSMakeRange(idx, comps.count - idx)];
    return [NSString pathWithComponents:sub];
}

@end