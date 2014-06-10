//
//  NWGIFContainerProxy.h
//  GIFContainer
//
//  Created by Anselz (@Janselz) on 14-6-10.
//  Copyright (c) 2014年 NeoWork. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NWGIFContainerProxy : NSProxy
+ (instancetype)weakProxyForObject:(id)targetObject;
@end
