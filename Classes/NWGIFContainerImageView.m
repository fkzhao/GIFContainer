//
//  NWGIFContainerImageView.m
//  GIFContainer
//
//  Created by Anselz on 14-6-10.
//  Copyright (c) 2014年 NeoWork. All rights reserved.
//

#import "NWGIFContainerImageView.h"

@interface NWGIFContainerImageView ()

@property (nonatomic, strong, readwrite) UIImage *currentFrame;
@property (nonatomic, assign, readwrite) NSUInteger currentFrameIndex;
@property (nonatomic, assign) NSUInteger loopCountdown;
@property (nonatomic, assign) NSTimeInterval accumulator;
@property (nonatomic, strong, readonly) CADisplayLink *displayLink;
@property (nonatomic, assign) BOOL shouldAnimate;
@property (nonatomic, assign) BOOL needsDisplayWhenImageBecomesAvailable;

@end

@implementation NWGIFContainerImageView

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        // Initialization code
    }
    return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    if (self) {
        
    }
    return self;
}

- (void)awakeFromNib {

}

#pragma mark Public

- (void)setAnimatedImage:(NWGIFContainerImage *)animatedImage
{
    if (![_animatedImage isEqual:animatedImage]) {
        if (animatedImage) {
            // Clear out the image.
            super.image = nil;
        } else {
            // Stop animating before the animated image gets cleared out.
            [self stopAnimating];
        }
        
        _animatedImage = animatedImage;
        
        self.currentFrame = animatedImage.posterImage;
        self.currentFrameIndex = 0;
        if (animatedImage.loopCount > 0) {
            self.loopCountdown = animatedImage.loopCount;
        } else {
            self.loopCountdown = NSUIntegerMax;
        }
        self.accumulator = 0.0;
        
        // Start animating after the new animated image has been set.
        [self updateShouldAnimate];
        if (self.shouldAnimate) {
            [self startAnimating];
        }
        
        [self.layer setNeedsDisplay];
    }
}


#pragma mark Private

// Explicit synthesizing for `readonly` property with overridden getter.
@synthesize displayLink = _displayLink;

- (CADisplayLink *)displayLink
{
    if (!_displayLink) {
        NWGIFContainerProxy *weakProxy = [NWGIFContainerProxy weakProxyForObject:self];
        _displayLink = [CADisplayLink displayLinkWithTarget:weakProxy selector:@selector(displayDidRefresh:)];
        //如果RunLoop的mode设置为NSDefaultRunLoopMode scrollView滑动时将会阻塞动画
        [_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        _displayLink.paused = YES;
    }
    
    return _displayLink;
}
#pragma mark - UIView Method Overrides
#pragma mark Observing View-Related Changes

- (void)didMoveToSuperview
{
    [super didMoveToSuperview];
    
    [self updateShouldAnimate];
    if (self.shouldAnimate) {
        [self startAnimating];
    } else {
        [self stopAnimating];
    }
}


- (void)didMoveToWindow
{
    [super didMoveToWindow];
    
    [self updateShouldAnimate];
    if (self.shouldAnimate) {
        [self startAnimating];
    } else {
        [self stopAnimating];
    }
}


#pragma mark - UIImageView Method Overrides
#pragma mark Image Data

- (UIImage *)image
{
    UIImage *image = nil;
    if (self.animatedImage) {
        // Initially set to the poster image.
        image = self.currentFrame;
    } else {
        image = super.image;
    }
    return image;
}


- (void)setImage:(UIImage *)image
{
    if (image) {
        // Clear out the animated image and implicitly pause animation playback.
        self.animatedImage = nil;
    }
    
    super.image = image;
}


#pragma mark Animating Images

- (void)startAnimating
{
    if (self.animatedImage) {
        self.displayLink.paused = NO;
    } else {
        [super startAnimating];
    }
}


- (void)stopAnimating
{
    if (self.animatedImage) {
        self.displayLink.paused = YES;
    } else {
        [super stopAnimating];
    }
}


- (BOOL)isAnimating
{
    BOOL isAnimating = NO;
    if (self.animatedImage) {
        isAnimating = !self.displayLink.isPaused;
    } else {
        isAnimating = [super isAnimating];
    }
    return isAnimating;
}


#pragma mark - Private Methods
#pragma mark Animation

// Don't repeatedly check our window & superview in `-displayDidRefresh:` for performance reasons.
// Just update our cached value whenever the animated image, window or superview is changed.
- (void)updateShouldAnimate
{
    self.shouldAnimate = self.animatedImage && self.window && self.superview;
}


- (void)displayDidRefresh:(CADisplayLink *)displayLink
{

    if (!self.shouldAnimate) {
        NSLog(@"Warn: Trying to animate image when we shouldn't: %@", self);
        return;
    }
    UIImage *image = [self.animatedImage imageLazilyCachedAtIndex:self.currentFrameIndex];
    if (image) {
        self.currentFrame = image;
        if (self.needsDisplayWhenImageBecomesAvailable) {
            [self.layer setNeedsDisplay];
            self.needsDisplayWhenImageBecomesAvailable = NO;
        }
        
        self.accumulator += displayLink.duration;
        
        while (self.accumulator >= [self.animatedImage.delayTimes[self.currentFrameIndex] floatValue]) {
            self.accumulator -= [self.animatedImage.delayTimes[self.currentFrameIndex] floatValue];
            self.currentFrameIndex++;
            if (self.currentFrameIndex >= self.animatedImage.frameCount) {
                // If we've looped the number of times that this animated image describes, stop looping.
                self.loopCountdown--;
                if (self.loopCountdown == 0) {
                    [self stopAnimating];
                    return;
                }
                self.currentFrameIndex = 0;
            }
            // Calling `-setNeedsDisplay` will just paint the current frame, not the new frame that we may have moved to.
            // Instead, set `needsDisplayWhenImageBecomesAvailable` to `YES` -- this will paint the new image once loaded.
            self.needsDisplayWhenImageBecomesAvailable = YES;
        }
    } else {
        
    }
}


#pragma mark - CALayerDelegate (Informal)
#pragma mark Providing the Layer's Content

- (void)displayLayer:(CALayer *)layer
{
    layer.contents = (__bridge id)self.currentFrame.CGImage;
}

@end
