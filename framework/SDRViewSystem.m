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
- (void)replaceNativeView:(UIView *)view {
    if (view) _nativeView = view;
}
- (void)setFrame:(CGRect)frame { _frame = frame; _nativeView.frame = frame; }
- (void)setHidden:(BOOL)hidden { _hidden = hidden; _nativeView.hidden = hidden; }
- (void)setTag:(NSInteger)tag { _tag = tag; _nativeView.tag = tag; }
@end

@implementation SDRTextView {
    UILabel *_label;
}
- (instancetype)init {
    if (self = [super init]) {
        _label = [[UILabel alloc] init];
        _label.numberOfLines = 0;
        [self replaceNativeView:_label];
        _fontSize = 17.0;
        _textColor = [UIColor labelColor];
        _textAlignment = NSTextAlignmentLeft;
    }
    return self;
}
- (void)setText:(NSString *)text {
    _text = [text copy];
    _label.text = text;
}
- (void)setTextColor:(UIColor *)textColor {
    _textColor = textColor;
    _label.textColor = textColor;
}
- (void)setFontSize:(CGFloat)fontSize {
    _fontSize = fontSize;
    _label.font = [UIFont systemFontOfSize:fontSize];
}
- (void)setTextAlignment:(NSTextAlignment)textAlignment {
    _textAlignment = textAlignment;
    _label.textAlignment = textAlignment;
}
@end

@implementation SDRButton {
    UIButton *_button;
}
- (instancetype)init {
    if (self = [super init]) {
        _button = [UIButton buttonWithType:UIButtonTypeSystem];
        [self replaceNativeView:_button];
        _textColor = [UIColor systemBlueColor];
        [_button addTarget:self action:@selector(_handleTap) forControlEvents:UIControlEventTouchUpInside];
    }
    return self;
}
- (void)setText:(NSString *)text {
    _text = [text copy];
    [_button setTitle:text forState:UIControlStateNormal];
}
- (void)setTextColor:(UIColor *)textColor {
    _textColor = textColor;
    [_button setTitleColor:textColor forState:UIControlStateNormal];
}
- (void)_handleTap {
    if (self.onClick) self.onClick();
}
@end

@implementation SDRImageView {
    UIImageView *_imageView;
}
- (instancetype)init {
    if (self = [super init]) {
        _imageView = [[UIImageView alloc] init];
        _imageView.contentMode = UIViewContentModeScaleAspectFit;
        [self replaceNativeView:_imageView];
    }
    return self;
}
- (void)setImage:(UIImage *)image {
    _image = image;
    _imageView.image = image;
}
- (void)loadImageFromData:(NSData *)data {
    if (data.length == 0) return;
    UIImage *img = [UIImage imageWithData:data];
    if (img) self.image = img;
}
@end

@implementation SDREditText {
    UITextField *_field;
}
- (instancetype)init {
    if (self = [super init]) {
        _field = [[UITextField alloc] init];
        _field.borderStyle = UITextBorderStyleRoundedRect;
        [self replaceNativeView:_field];
    }
    return self;
}
- (void)setText:(NSString *)text {
    _text = [text copy];
    _field.text = text;
}
- (void)setPlaceholder:(NSString *)placeholder {
    _placeholder = [placeholder copy];
    _field.placeholder = placeholder;
}
@end

@implementation SDRListView {
    UIStackView *_stack;
}
- (instancetype)init {
    if (self = [super init]) {
        _stack = [[UIStackView alloc] init];
        _stack.axis = UILayoutConstraintAxisVertical;
        _stack.spacing = 4.0;
        [self replaceNativeView:_stack];
    }
    return self;
}
- (void)setItems:(NSArray<NSString *> *)items {
    _items = [items copy];
    for (UIView *v in _stack.arrangedSubviews) {
        [_stack removeArrangedSubview:v];
        [v removeFromSuperview];
    }
    for (NSString *item in items) {
        UILabel *l = [[UILabel alloc] init];
        l.text = item;
        l.font = [UIFont systemFontOfSize:15.0];
        [_stack addArrangedSubview:l];
    }
}
@end

@implementation SDRLayoutInflater
- (SDRView *)inflateLayoutData:(NSData *)xmlData error:(NSError **)error {
    // 骨架阶段：布局解析待实现。
    return nil;
}
@end

@implementation SDRTouchEvent
@end