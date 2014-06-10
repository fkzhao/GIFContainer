//
//  NWGIFContainerImageView.h
//  GIFContainer
//
//  Created by Anselz on 14-6-10.
//  Copyright (c) 2014年 NeoWork. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "NWGIFContainerImage.h"
#import "NWGIFContainerProxy.h"

@interface NWGIFContainerImageView : UIImageView

@property (nonatomic, strong) NWGIFContainerImage *animatedImage;
@property (nonatomic, strong, readonly) UIImage *currentFrame;
@property (nonatomic, assign, readonly) NSUInteger currentFrameIndex;


@end
