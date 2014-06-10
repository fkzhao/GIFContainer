//
//  NWGIFContainerImage.h
//  GIFContainer
//
//  Created by Anselz (@Janselz) on 14-6-10.
//  Copyright (c) 2014年 NeoWork. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "NWGIFContainerProxy.h"
@interface NWGIFContainerImage : NSObject
@property (nonatomic, strong, readonly) UIImage *posterImage;
@property (nonatomic, assign, readonly) CGSize size;
@property (nonatomic, assign, readonly) NSUInteger loopCount;
@property (nonatomic, strong, readonly) NSArray *delayTimes;
@property (nonatomic, assign, readonly) NSUInteger frameCount;
@property (nonatomic, assign, readonly) NSUInteger frameCacheSizeCurrent;
@property (nonatomic, assign) NSUInteger frameCacheSizeMax;
- (UIImage *)imageLazilyCachedAtIndex:(NSUInteger)index;
+ (CGSize)sizeForImage:(id)image;
- (instancetype)initWithAnimatedGIFData:(NSData *)data;
@property (nonatomic, strong, readonly) NSData *data;
@end
