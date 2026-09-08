/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

#import "SDRViewSystem.h"

@implementation SDRLayoutParams
@end

@implementation SDRView
- (instancetype)init {
    if (self = [super init]) {
        _nativeView = [[UIView alloc] init];
    }
    return self;
}
- (UIView *)nativeViewForDisplay { return _nativeView; }
- (void)setFrame:(CGRect)frame { _frame = frame; _nativeView.frame = frame; }
- (void)setHidden:(BOOL)hidden { _hidden = hidden; _nativeView.hidden = hidden; }
- (void)setTag:(NSInteger)tag { _tag = tag; _nativeView.tag = tag; }
@end

@implementation SDRTextView
- (void)setText:(NSString *)text {
    _text = [text copy];
    UIView *nv = self.nativeView;
    if ([nv isKindOfClass:[UILabel class]]) { ((UILabel *)nv).text = text; }
}
@end

@implementation SDRButton
@end

@implementation SDRImageView
- (void)setImage:(UIImage *)image {
    _image = image;
    UIView *nv = self.nativeView;
    if ([nv isKindOfClass:[UIImageView class]]) { ((UIImageView *)nv).image = image; }
}
@end

@implementation SDREditText
@end

@implementation SDRListView
@end

@implementation SDRLayoutInflater
- (SDRView *)inflateLayoutData:(NSData *)xmlData error:(NSError **)error {
    // 骨架阶段：布局解析待实现。
    return nil;
}
@end

@implementation SDRTouchEvent
@end