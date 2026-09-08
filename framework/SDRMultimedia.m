/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

#import "SDRMultimedia.h"

#pragma mark - Bitmap

@implementation SDRBitmap
- (nullable instancetype)initWithData:(NSData *)data {
    if (self = [super init]) {
        _image = [UIImage imageWithData:data];
        if (!_image) return nil;
        _width = (NSUInteger)(_image.size.width * _image.scale);
        _height = (NSUInteger)(_image.size.height * _image.scale);
    }
    return self;
}
- (nullable instancetype)initWithImage:(UIImage *)image {
    if (self = [super init]) {
        _image = image;
        _width = (NSUInteger)(image.size.width * image.scale);
        _height = (NSUInteger)(image.size.height * image.scale);
    }
    return self;
}
@end

#pragma mark - MediaPlayer

@implementation SDRMediaPlayer {
    AVAudioPlayer *_player;
}

- (instancetype)initWithContentsOfFile:(NSString *)path {
    if (self = [super init]) {
        _player = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path] error:NULL];
    }
    return self;
}

- (BOOL)prepareToPlay:(NSError **)error { return [_player prepareToPlay]; }
- (void)play { [_player play]; }
- (void)pause { [_player pause]; }
- (void)stop { [_player stop]; }
- (BOOL)isPlaying { return _player.isPlaying; }

@end

#pragma mark - Camera

@implementation SDRCamera
+ (void)requestAccessWithCompletion:(void (^)(BOOL))completion {
    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:completion];
}
+ (BOOL)hasCameraAccess {
    return [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo] == AVAuthorizationStatusAuthorized;
}
@end