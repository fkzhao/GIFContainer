//
//  NWGIFContainerProxy.m
//  GIFContainer
//
//  Created by Anselz (@Janselz) on 14-6-10.
//  Copyright (c) 2014年 NeoWork. All rights reserved.
//

#import "NWGIFContainerProxy.h"

@interface NWGIFContainerProxy ()
@property (nonatomic, weak) id target;
@end

@implementation NWGIFContainerProxy
#pragma mark Life Cycle

+ (instancetype)weakProxyForObject:(id)targetObject
{
    NWGIFContainerProxy *weakProxy = [NWGIFContainerProxy alloc];
    weakProxy.target = targetObject;
    return weakProxy;
}


#pragma mark Forwarding Messages

- (id)forwardingTargetForSelector:(SEL)selector
{
    // Keep it lightweight: access the ivar directly
    return _target;
}


#pragma mark - NSWeakProxy Method Overrides
#pragma mark Handling Unimplemented Methods

- (void)forwardInvocation:(NSInvocation *)invocation
{
    void *nullPointer = NULL;
    [invocation setReturnValue:&nullPointer];
}


- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector
{
   
    return [NSObject instanceMethodSignatureForSelector:@selector(init)];
}

@end
