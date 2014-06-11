//
//  NWGIFContainerImage.m
//  GIFContainer
//
//  Created by Anselz (@Janselz) on 14-6-10.
//  Copyright (c) 2014年 NeoWork. All rights reserved.
//

#import "NWGIFContainerImage.h"
#import <ImageIO/ImageIO.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <CoreGraphics/CoreGraphics.h>


#define MEGABYTE (1024 * 1024)

typedef NS_ENUM(NSUInteger, NWAnimatedImageDataSizeCategory) {
    NWAnimatedImageDataSizeCategoryAll = 10,       // All frames permanently in memory (be nice to the CPU)
    NWAnimatedImageDataSizeCategoryDefault = 75,   // A frame cache of default size in memory (usually real-time performance and keeping low memory profile)
    NWAnimatedImageDataSizeCategoryOnDemand = 250, // Only keep one frame at the time in memory (easier on memory, slowest performance)
    NWAnimatedImageDataSizeCategoryUnsupported     // Even for one frame too large, computer says no.
};

typedef NS_ENUM(NSUInteger, NWAnimatedImageFrameCacheSize) {
    NWAnimatedImageFrameCacheSizeNoLimit = 0,                // 0 means no specific limit
    NWAnimatedImageFrameCacheSizeLowMemory = 1,              // The minimum frame cache size; this will produce frames on-demand.
    NWAnimatedImageFrameCacheSizeGrowAfterMemoryWarning = 2, // If we can produce the frames faster than we consume, one frame ahead will already result in a stutter-free playback.
    NWAnimatedImageFrameCacheSizeDefault = 5                 // Build up a comfy buffer window to cope with CPU hiccups etc.
};

@interface NWGIFContainerImage () {
    CGImageSourceRef _imageSource;
    dispatch_queue_t _serialQueue;

}
@property (nonatomic, assign, readonly) NSUInteger frameCacheSizeOptimal;
@property (nonatomic, assign) NSUInteger frameCacheSizeMaxInternal;
@property (nonatomic, assign) NSUInteger requestedFrameIndex;
@property (nonatomic, assign, readonly) NSUInteger posterImageFrameIndex;
@property (nonatomic, strong, readonly) NSMutableArray *cachedFrames;
@property (nonatomic, strong, readonly) NSMutableIndexSet *cachedFrameIndexes;
@property (nonatomic, strong, readonly) NSMutableIndexSet *requestedFrameIndexes;
@property (nonatomic, strong, readonly) NSIndexSet *allFramesIndexSet;
@property (nonatomic, assign) NSUInteger memoryWarningCount;
@property (nonatomic, strong, readonly) NWGIFContainerImage *weakProxy;
@end

@implementation NWGIFContainerImage
#pragma mark - Accessors
#pragma mark Public

// This is the definite value the frame cache needs to size itself to.
- (NSUInteger)frameCacheSizeCurrent
{
    NSUInteger frameCacheSizeCurrent = self.frameCacheSizeOptimal;
    
    // If set, respect the caps.
    if (self.frameCacheSizeMax > NWAnimatedImageFrameCacheSizeNoLimit) {
        frameCacheSizeCurrent = MIN(frameCacheSizeCurrent, self.frameCacheSizeMax);
    }
    
    if (self.frameCacheSizeMaxInternal > NWAnimatedImageFrameCacheSizeNoLimit) {
        frameCacheSizeCurrent = MIN(frameCacheSizeCurrent, self.frameCacheSizeMaxInternal);
    }
    
    return frameCacheSizeCurrent;
}


- (void)setFrameCacheSizeMax:(NSUInteger)frameCacheSizeMax
{
    if (_frameCacheSizeMax != frameCacheSizeMax) {
        
        // Remember whether the new cap will cause the current cache size to shrink; then we'll make sure to purge from the cache if needed.
        BOOL willFrameCacheSizeShrink = (frameCacheSizeMax < self.frameCacheSizeCurrent);
        
        // Update the value
        _frameCacheSizeMax = frameCacheSizeMax;
        
        if (willFrameCacheSizeShrink) {
            [self purgeFrameCacheIfNeeded];
        }
    }
}


#pragma mark Private

- (void)setFrameCacheSizeMaxInternal:(NSUInteger)frameCacheSizeMaxInternal
{
    if (_frameCacheSizeMaxInternal != frameCacheSizeMaxInternal) {
        
        // Remember whether the new cap will cause the current cache size to shrink; then we'll make sure to purge from the cache if needed.
        BOOL willFrameCacheSizeShrink = (frameCacheSizeMaxInternal < self.frameCacheSizeCurrent);
        
        // Update the value
        _frameCacheSizeMaxInternal = frameCacheSizeMaxInternal;
        
        if (willFrameCacheSizeShrink) {
            [self purgeFrameCacheIfNeeded];
        }
    }
}


// Explicit synthesizing for `readonly` property with overridden getter.
@synthesize weakProxy = _weakProxy;

- (NWGIFContainerImage *)weakProxy
{
    if (!_weakProxy) {
        _weakProxy = (id)[NWGIFContainerProxy weakProxyForObject:self];
    }
    
    return _weakProxy;
}


#pragma mark - Life Cycle

- (id)init
{
    NSLog(@"Error: Use `-initWithAnimatedGIFData:` and supply the animated GIF data as an argument to initialize an object of type `FLAnimatedImage`.");
    return nil;
}

- (instancetype)initWithAnimatedGIFData:(NSData *)data
{
    // Early return if no data supplied!
    BOOL hasData = ([data length] > 0);
    if (!hasData) {
        NSLog(@"Error: No animated GIF data supplied.");
        return nil;
    }
    
    self = [super init];
    if (self) {
        _data = data;
        
        // Initialize internal data structures
        _cachedFrames = [[NSMutableArray alloc] init];
        _cachedFrameIndexes = [[NSMutableIndexSet alloc] init];
        _requestedFrameIndexes = [[NSMutableIndexSet alloc] init];
        
        // Note: We could leverage `CGImageSourceCreateWithURL` too to add a second initializer `-initWithAnimatedGIFContentsOfURL:`.
        _imageSource = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
        if (!_imageSource) {
            NSLog(@"Error: Failed to `CGImageSourceCreateWithData` for animated GIF data %@", data);
            return nil;
        }
        
        //获取图片类型
        CFStringRef imageSourceContainerType = CGImageSourceGetType(_imageSource);
        //判断图片类型是否是GIF格式
        BOOL isGIFData = UTTypeConformsTo(imageSourceContainerType, kUTTypeGIF);
        if (!isGIFData) {
            NSLog(@"Error: Supplied data is of type %@ and doesn't seem to be GIF data %@", imageSourceContainerType, data);
            return nil;
        }
        
        //获取LoopCount 0标示一直重复播放
        // Image properties 示例:
        // {
        //     FileSize = 314446;
        //     "{GIF}" = {
        //         HasGlobalColorMap = 1;
        //         LoopCount = 0;
        //     };
        // }
       
        NSDictionary *imageProperties = (__bridge_transfer NSDictionary *)CGImageSourceCopyProperties(_imageSource, NULL);
        _loopCount = [[[imageProperties objectForKey:(id)kCGImagePropertyGIFDictionary] objectForKey:(id)kCGImagePropertyGIFLoopCount] unsignedIntegerValue];
        
        // Iterate through frame images
        size_t imageCount = CGImageSourceGetCount(_imageSource);
        NSMutableArray *delayTimesMutable = [NSMutableArray arrayWithCapacity:imageCount];
        for (size_t i = 0; i < imageCount; i++) {
            CGImageRef frameImageRef = CGImageSourceCreateImageAtIndex(_imageSource, i, NULL);
            if (frameImageRef) {
                UIImage *frameImage = [UIImage imageWithCGImage:frameImageRef];
                //检查图片是否合法
                if (frameImage) {
                    // Set poster image
                    if (!self.posterImage) {
                        _posterImage = frameImage;
                        // Set its size to proxy our size.
                        _size = _posterImage.size;
                        // Remember index of poster image so we never purge it; also add it to the cache.
                        _posterImageFrameIndex = i;
                        self.cachedFrames[self.posterImageFrameIndex] = self.posterImage;
                        [self.cachedFrameIndexes addIndex:self.posterImageFrameIndex];
                    } else {
                        // Placeholder indicates that we don't have a cached frame.
                        // We use an array instead of a dictionary for slightly faster access.
                        self.cachedFrames[i] = [NSNull null];
                    }
                    
                    //获取这一幁图片显示时间 就是所谓的延迟时间
                    // Get `DelayTime`
                    // Note: It's not in (1/100) of a second like still falsly described in the documentation as per iOS 7 but in seconds stored as `kCFNumberFloat32Type`.
                    // Frame properties example:
                    // {
                    //     ColorModel = RGB;
                    //     Depth = 8;
                    //     PixelHeight = 960;
                    //     PixelWidth = 640;
                    //     "{GIF}" = {
                    //         DelayTime = "0.4";
                    //         UnclampedDelayTime = "0.4";
                    //     };
                    // }
                    
                    
                    //获取指定桢图片的属性
                    NSDictionary *frameProperties = (__bridge_transfer NSDictionary *)CGImageSourceCopyPropertiesAtIndex(_imageSource, i, NULL);
                    NSDictionary *framePropertiesGIF = [frameProperties objectForKey:(id)kCGImagePropertyGIFDictionary];
                    
                    // Try to use the unclamped delay time; fall back to the normal delay time.
                    NSNumber *delayTime = [framePropertiesGIF objectForKey:(id)kCGImagePropertyGIFUnclampedDelayTime];
                    if (!delayTime) {
                        delayTime = [framePropertiesGIF objectForKey:(id)kCGImagePropertyGIFDelayTime];
                    }
                    //如果没有得到一个延迟时间的属性，回落到`kDelayTimeIntervalDefault`或结转的前一帧的值。
                    const NSTimeInterval kDelayTimeIntervalDefault = 0.1;
                    if (!delayTime) {
                        if (i == 0) {
                            NSLog(@"Verbose: Falling back to default delay time for first frame %@ because none found in GIF properties %@", frameImage, frameProperties);
                            delayTime = @(kDelayTimeIntervalDefault);
                        } else {
                            NSLog(@"Verbose: Falling back to preceding delay time for frame %zu %@ because none found in GIF properties %@", i, frameImage, frameProperties);
                            delayTime = delayTimesMutable[i - 1];
                        }
                    }
                    const NSTimeInterval kDelayTimeIntervalMinimum = 0.02;
        
                    
                    //如果延迟时间小于 最小时间 0.02 (这个地方目的是为了做播放流畅 0.02应该是根据大量测试总结出来的 可以参考http://nullsleep.tumblr.com/post/16524517190/animated-gif-minimum-frame-delay-browser-compatibility) PS：NSOrderedAscending 左边小于右边
                    if ([delayTime compare:@(kDelayTimeIntervalMinimum)] == NSOrderedAscending) {
                        NSLog(@"Verbose: Rounding frame %zu's `delayTime` from %f up to default %f (minimum supported: %f).", i, [delayTime floatValue], kDelayTimeIntervalDefault, kDelayTimeIntervalMinimum);
                        delayTime = @(kDelayTimeIntervalDefault);
                    }
                    delayTimesMutable[i] = delayTime;
                } else {
                    NSLog(@"Verbose: Dropping frame %zu because valid `CGImageRef` %@ did result in `nil`-`UIImage`.", i, frameImageRef);
                }
                CFRelease(frameImageRef);
            } else {
                NSLog(@"Verbose: Dropping frame %zu because failed to `CGImageSourceCreateImageAtIndex` with image source %@", i, _imageSource);
            }
        }
        _delayTimes = [delayTimesMutable copy];
        _frameCount = [_delayTimes count];
        
        if (self.frameCount == 0) {
            NSLog(@"Error: Failed to create any valid frames for GIF with properties %@", imageProperties);
            return nil;
        } else if (self.frameCount == 1) {
            // Warn when we only have a single frame but return a valid GIF.
            NSLog(@"Verbose: Created valid GIF but with only a single frame. Image properties: %@", imageProperties);
        } else {
            // We have multiple frames, rock on!
        }
        
        // Calculate the optimal frame cache size: try choosing a larger buffer window depending on the predicted image size.
        // It's only dependent on the image size & number of frames and never changes.
        
        //真正性能优化在这里，更具图片的大小来判断图片的执行帧数
        CGFloat animatedImageDataSize = CGImageGetBytesPerRow(self.posterImage.CGImage) * self.size.height * self.frameCount / MEGABYTE;
        if (animatedImageDataSize <= NWAnimatedImageDataSizeCategoryAll) {
            _frameCacheSizeOptimal = self.frameCount;
        } else if (animatedImageDataSize <= NWAnimatedImageDataSizeCategoryDefault) {
            // This value doesn't depend on device memory much because if we're not keeping all frames in memory we will always be decoding 1 frame up ahead per 1 frame that gets played and at this point we might as well just keep a small buffer just large enough to keep from running out of frames.
            _frameCacheSizeOptimal = NWAnimatedImageFrameCacheSizeDefault;
        } else {
            // The predicted size exceeds the limits to build up a cache and we go into low memory mode from the beginning.
            _frameCacheSizeOptimal = NWAnimatedImageFrameCacheSizeLowMemory;
        }
        _frameCacheSizeOptimal = MIN(_frameCacheSizeOptimal, self.frameCount);
        
        _allFramesIndexSet = [[NSIndexSet alloc] initWithIndexesInRange:NSMakeRange(0, self.frameCount)];
        
        //注册收到系统内存警告监听
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didReceiveMemoryWarning:) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    }
    return self;
}


- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    if (_weakProxy) {
        [NSObject cancelPreviousPerformRequestsWithTarget:_weakProxy];
    }
    
    if (_imageSource) {
        CFRelease(_imageSource);
    }
    
    // Needed for deployment target iOS 5.0
#if ((__IPHONE_OS_VERSION_MIN_REQUIRED < __IPHONE_6_0) || (!defined(__IPHONE_6_0)))
    if (_serialQueue) {
        dispatch_release(_serialQueue);
    }
#endif
}


#pragma mark - Public Methods

// See header for more details.
// Note: both consumer and producer are throttled: consumer by frame timings and producer by the available memory (max buffer window size).
- (UIImage *)imageLazilyCachedAtIndex:(NSUInteger)index
{
    // Early return if the requested index is beyond bounds.
    // Note: We're comparing an index with a count and need to bail on greater than or equal to.
    if (index >= self.frameCount) {
        NSLog(@"Error: Skipping requested frame %lu beyond bounds (total frame count: %lu) for animated image: %@", (unsigned long)index,  (unsigned long)self.frameCount, self);
        return nil;
    }
    
    // Remember requested frame index, this influences what we should cache next.
    self.requestedFrameIndex = index;
    
    // Quick check to avoid doing any work if we already have all possible frames cached, a common case.
    if ([self.cachedFrameIndexes count] < self.frameCount) {
        // If we have frames that should be cached but aren't and aren't requested yet, request them.
        // Exclude existing cached frames, frames already requested, and specially cached poster image.
        NSMutableIndexSet *frameIndexesToAddToCacheMutable = [[self frameIndexesToCache] mutableCopy];
        [frameIndexesToAddToCacheMutable removeIndexes:self.cachedFrameIndexes];
        [frameIndexesToAddToCacheMutable removeIndexes:self.requestedFrameIndexes];
        [frameIndexesToAddToCacheMutable removeIndex:self.posterImageFrameIndex];
        NSIndexSet *frameIndexesToAddToCache = [frameIndexesToAddToCacheMutable copy];
        
        // Asynchronously add frames to our cache.
        if ([frameIndexesToAddToCache count] > 0) {
            [self addFrameIndexesToCache:frameIndexesToAddToCache];
        }
    }
    
    // Get the specified image. Watch out for `NSNull` placeholders.
    UIImage *image = nil;
    id tryImage = self.cachedFrames[index];
    if ([tryImage isKindOfClass:[UIImage class]]) {
        image = tryImage;
    }
    
    // Purge if needed based on the current playhead position.
    [self purgeFrameCacheIfNeeded];
    
    return image;
}


// Only called once from `-imageLazilyCachedAtIndex` but factored into its own method for logical grouping.
- (void)addFrameIndexesToCache:(NSIndexSet *)frameIndexesToAddToCache
{
    // Order matters. First, iterate over the indexes starting from the requested frame index.
    // Then, if there are any indexes before the requested frame index, do those.
    NSRange firstRange = NSMakeRange(self.requestedFrameIndex, self.frameCount - self.requestedFrameIndex);
    NSRange secondRange = NSMakeRange(0, self.requestedFrameIndex);
    if (firstRange.length + secondRange.length != self.frameCount) {
        NSLog(@"Error: Two-part frame cache range doesn't equal full range.");
    }
    
    // Add to the requested list before we actually kick them off, so they don't get into the queue twice.
    [self.requestedFrameIndexes addIndexes:frameIndexesToAddToCache];
    
    // Lazily create dedicated isolation queue.
    if (!_serialQueue) {
        _serialQueue = dispatch_queue_create("com.flipboard.framecachingqueue", DISPATCH_QUEUE_SERIAL);
    }
    
    // Start streaming requested frames in the background into the cache.
    dispatch_async(_serialQueue, ^{
        // Produce and cache next needed frame.
        void (^frameRangeBlock)(NSRange, BOOL *) = ^(NSRange range, BOOL *stop) {
            // Iterate through contiguous indexes; can be faster than `enumerateIndexesInRange:options:usingBlock:`.
            for (NSUInteger i = range.location; i < NSMaxRange(range); i++) {
                UIImage *image = [self predrawnImageAtIndex:i];
                // The results get returned one by one as soon as they're ready (and not in batch).
                // The benefits of having the first frames as quick as possible outweigh building up a buffer to cope with potential hiccups when the CPU suddenly gets busy.
                if (image) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        self.cachedFrames[i] = image;
                        [self.cachedFrameIndexes addIndex:i];
                        [self.requestedFrameIndexes removeIndex:i];
                    });
                }
            }
        };
        
        // Guard against crashing on 0-length ranges with an 'NSRangeException' "last range index (-1) beyond bounds" (Apple's error message is bogus here).
        // This is only needed on iOS 5, iPad only, running on device and only for the range {0,0} but regardless of whether the index set is mutable or immutable or what the indexes in the set are (can even be empty).
        if (firstRange.length > 0) {
            [frameIndexesToAddToCache enumerateRangesInRange:firstRange options:0 usingBlock:frameRangeBlock];
        }
        if (secondRange.length > 0) {
            [frameIndexesToAddToCache enumerateRangesInRange:secondRange options:0 usingBlock:frameRangeBlock];
        }
    });
}


+ (CGSize)sizeForImage:(id)image
{
    CGSize imageSize = CGSizeZero;
    
    // Early return for nil
    if (!image) {
        return imageSize;
    }
    
    if ([image isKindOfClass:[UIImage class]]) {
        UIImage *uiImage = (UIImage *)image;
        imageSize = uiImage.size;
    } else if ([image isKindOfClass:[NWGIFContainerImage class]]) {
        NWGIFContainerImage *animatedImage = (NWGIFContainerImage *)image;
        imageSize = animatedImage.size;
    } else {
        // Bear trap to capture bad images; we have seen crashers cropping up on iOS 7.
        NSLog(@"Error: `image` isn't of expected types `UIImage` or `FLAnimatedImage`: %@", image);
    }
    
    return imageSize;
}


#pragma mark - Private Methods
#pragma mark Frame Loading

- (UIImage *)predrawnImageAtIndex:(NSUInteger)index
{
    // It's very important to use the cached `_imageSource` since the random access to a frame with `CGImageSourceCreateImageAtIndex` turns from an O(1) into an O(n) operation when re-initializing the image source every time.
    CGImageRef imageRef = CGImageSourceCreateImageAtIndex(_imageSource, index, NULL);
    UIImage *image = [UIImage imageWithCGImage:imageRef];
    CFRelease(imageRef);
    
    // Loading in the image object is only half the work, the displaying image view would still have to synchronosly wait and decode the image, so we go ahead and do that here on the background thread.
    image = [[self class] predrawnImageFromImage:image];
    
    return image;
}


#pragma mark Frame Caching

- (NSIndexSet *)frameIndexesToCache
{
    NSIndexSet *indexesToCache = nil;
    // Quick check to avoid building the index set if the number of frames to cache equals the total frame count.
    if (self.frameCacheSizeCurrent == self.frameCount) {
        indexesToCache = self.allFramesIndexSet;
    } else {
        NSMutableIndexSet *indexesToCacheMutable = [[NSMutableIndexSet alloc] init];
        
        // Add indexes to the set in two separate blocks- the first starting from the requested frame index, up to the limit or the end.
        // The second, if needed, the remaining number of frames beginning at index zero.
        NSUInteger firstLength = MIN(self.frameCacheSizeCurrent, self.frameCount - self.requestedFrameIndex);
        NSRange firstRange = NSMakeRange(self.requestedFrameIndex, firstLength);
        [indexesToCacheMutable addIndexesInRange:firstRange];
        NSUInteger secondLength = self.frameCacheSizeCurrent - firstLength;
        if (secondLength > 0) {
            NSRange secondRange = NSMakeRange(0, secondLength);
            [indexesToCacheMutable addIndexesInRange:secondRange];
        }
        // Double check our math, before we add the poster image index which may increase it by one.
        if ([indexesToCacheMutable count] != self.frameCacheSizeCurrent) {
            NSLog(@"Error: Number of frames to cache doesn't equal expected cache size.");
        }
        
        [indexesToCacheMutable addIndex:self.posterImageFrameIndex];
        
        indexesToCache = [indexesToCacheMutable copy];
    }
    
    return indexesToCache;
}


- (void)purgeFrameCacheIfNeeded
{
    // Purge frames that are currently cached but don't need to be.
    // But not if we're still under the number of frames to cache.
    // This way, if all frames are allowed to be cached (the common case), we can skip all the `NSIndexSet` math below.
    if ([self.cachedFrameIndexes count] > self.frameCacheSizeCurrent) {
        NSMutableIndexSet *indexesToPurge = [self.cachedFrameIndexes mutableCopy];
        [indexesToPurge removeIndexes:[self frameIndexesToCache]];
        [indexesToPurge enumerateRangesUsingBlock:^(NSRange range, BOOL *stop) {
            // Iterate through contiguous indexes; can be faster than `enumerateIndexesInRange:options:usingBlock:`.
            for (NSUInteger i = range.location; i < NSMaxRange(range); i++) {
                [self.cachedFrameIndexes removeIndex:i];
                self.cachedFrames[i] = [NSNull null];
                // Note: Don't `CGImageSourceRemoveCacheAtIndex` on the image source for frames that we don't want cached any longer to maintain O(1) time access.
            }
        }];
    }
}


- (void)growFrameCacheSizeAfterMemoryWarning:(NSNumber *)frameCacheSize
{
    self.frameCacheSizeMaxInternal = [frameCacheSize unsignedIntegerValue];
    NSLog(@"Verbose: Grew frame cache size max to %lu after memory warning for animated image: %@", (unsigned long)self.frameCacheSizeMaxInternal, self);
    
    // Schedule resetting the frame cache size max completely after a while.
    const NSTimeInterval kResetDelay = 3.0;
    [self.weakProxy performSelector:@selector(resetFrameCacheSizeMaxInternal) withObject:nil afterDelay:kResetDelay];
}


- (void)resetFrameCacheSizeMaxInternal
{
    self.frameCacheSizeMaxInternal = NWAnimatedImageFrameCacheSizeNoLimit;
    NSLog(@"Verbose: Reset frame cache size max (current frame cache size: %lu) for animated image: %@", (unsigned long)self.frameCacheSizeCurrent, self);
}


#pragma mark System Memory Warnings Notification Handler

- (void)didReceiveMemoryWarning:(NSNotification *)notification
{
    // Hold (and use!) a strong reference to self, since `NSNotificationCenter` no longer strongly references the observer.
    // This is another example of the lame fallout from the LLVM change in Xcode 5.1.
    NWGIFContainerImage *strongSelf = self;
    
    strongSelf.memoryWarningCount++;
    
    // If we were about to grow larger, but got rapped on our knuckles by the system again, cancel.
    [NSObject cancelPreviousPerformRequestsWithTarget:strongSelf.weakProxy selector:@selector(growFrameCacheSizeAfterMemoryWarning:) object:@(NWAnimatedImageFrameCacheSizeGrowAfterMemoryWarning)];
    [NSObject cancelPreviousPerformRequestsWithTarget:strongSelf.weakProxy selector:@selector(resetFrameCacheSizeMaxInternal) object:nil];
    
    // Go down to the minimum and by that implicitly immediately purge from the cache if needed to not get jettisoned by the system and start producing frames on-demand.
    NSLog(@"Verbose: Attempt setting frame cache size max to %lu (previous was %lu) after memory warning #%lu for animated image: %@", (unsigned long)NWAnimatedImageFrameCacheSizeLowMemory, (unsigned long)strongSelf.frameCacheSizeMaxInternal, (unsigned long)strongSelf.memoryWarningCount, strongSelf);
    strongSelf.frameCacheSizeMaxInternal = NWAnimatedImageFrameCacheSizeLowMemory;
    
    // Schedule growing larger again after a while, but cap our attempts to prevent a periodic sawtooth wave (ramps upward and then sharply drops) of memory usage.
    //
    // [mem]^     (2)   (5)  (6)        1) Loading frames for the first time
    //   (*)|      ,     ,    ,         2) Mem warning #1; purge cache
    //      |     /| (4)/|   /|         3) Grow cache size a bit after a while, if no mem warning occurs
    //      |    / |  _/ | _/ |         4) Try to grow cache size back to optimum after a while, if no mem warning occurs
    //      |(1)/  |_/   |/   |__(7)    5) Mem warning #2; purge cache
    //      |__/   (3)                  6) After repetition of (3) and (4), mem warning #3; purge cache
    //      +---------------------->    7) After 3 mem warnings, stay at minimum cache size
    //                            [t]
    //                                  *) The mem high water mark before we get warned might change for every cycle.
    //
    const NSUInteger kGrowAttemptsMax = 2;
    const NSTimeInterval kGrowDelay = 2.0;
    if ((strongSelf.memoryWarningCount - 1) <= kGrowAttemptsMax) {
        [strongSelf.weakProxy performSelector:@selector(growFrameCacheSizeAfterMemoryWarning:) withObject:@(NWAnimatedImageFrameCacheSizeGrowAfterMemoryWarning) afterDelay:kGrowDelay];
    }
    
    // Note: It's not possible to get the level of a memory warning with a public API: http://stackoverflow.com/questions/2915247/iphone-os-memory-warnings-what-do-the-different-levels-mean/2915477#2915477
}


#pragma mark Image Decoding

// Decodes the image's data and draws it off-screen fully in memory; it's thread-safe and hence can be called on a background thread.
// On success, the returned object is a new `UIImage` instance with the same content as the one passed in.
// On failure, the returned object is the unchanged passed in one; the data will not be predrawn in memory though and an error will be logged.
// First inspired by & good Karma to: https://gist.github.com/steipete/1144242
+ (UIImage *)predrawnImageFromImage:(UIImage *)imageToPredraw
{
    // Always use a device RGB color space for simplicity and predictability what will be going on.
    CGColorSpaceRef colorSpaceDeviceRGBRef = CGColorSpaceCreateDeviceRGB();
    // Early return on failure!
    if (!colorSpaceDeviceRGBRef) {
        NSLog(@"Error: Failed to `CGColorSpaceCreateDeviceRGB` for image %@", imageToPredraw);
        return imageToPredraw;
    }
    
    // Even when the image doesn't have transparency, we have to add the extra channel because Quartz doesn't support other pixel formats than 32 bpp/8 bpc for RGB:
    // kCGImageAlphaNoneSkipFirst, kCGImageAlphaNoneSkipLast, kCGImageAlphaPremultipliedFirst, kCGImageAlphaPremultipliedLast
    // (source: docs "Quartz 2D Programming Guide > Graphics Contexts > Table 2-1 Pixel formats supported for bitmap graphics contexts")
    size_t numberOfComponents = CGColorSpaceGetNumberOfComponents(colorSpaceDeviceRGBRef) + 1; // 4: RGB + A
    
    // "In iOS 4.0 and later, and OS X v10.6 and later, you can pass NULL if you want Quartz to allocate memory for the bitmap." (source: docs)
    void *data = NULL;
    size_t width = imageToPredraw.size.width;
    size_t height = imageToPredraw.size.height;
    size_t bitsPerComponent = CHAR_BIT;
    
    size_t bitsPerPixel = (bitsPerComponent * numberOfComponents);
    size_t bytesPerPixel = (bitsPerPixel / BYTE_SIZE);
    size_t bytesPerRow = (bytesPerPixel * width);
    
    CGBitmapInfo bitmapInfo = kCGBitmapByteOrderDefault;
    
    CGImageAlphaInfo alphaInfo = CGImageGetAlphaInfo(imageToPredraw.CGImage);
    // If the alpha info doesn't match to one of the supported formats (see above), pick a reasonable supported one.
    // "For bitmaps created in iOS 3.2 and later, the drawing environment uses the premultiplied ARGB format to store the bitmap data." (source: docs)
    if (alphaInfo == kCGImageAlphaNone || alphaInfo == kCGImageAlphaOnly) {
        alphaInfo = kCGImageAlphaNoneSkipFirst;
    } else if (alphaInfo == kCGImageAlphaFirst) {
        alphaInfo = kCGImageAlphaPremultipliedFirst;
    } else if (alphaInfo == kCGImageAlphaLast) {
        alphaInfo = kCGImageAlphaPremultipliedLast;
    }
    // "The constants for specifying the alpha channel information are declared with the `CGImageAlphaInfo` type but can be passed to this parameter safely." (source: docs)
    bitmapInfo |= alphaInfo;
    
    // Create our own graphics context to draw to; `UIGraphicsGetCurrentContext`/`UIGraphicsBeginImageContextWithOptions` doesn't create a new context but returns the current one which isn't thread-safe (e.g. main thread could use it at the same time).
    // Note: It's not worth caching the bitmap context for multiple frames ("unique key" would be `width`, `height` and `hasAlpha`), it's ~50% slower. Time spent in libRIP's `CGSBlendBGRA8888toARGB8888` suddenly shoots up -- not sure why.
    CGContextRef bitmapContextRef = CGBitmapContextCreate(data, width, height, bitsPerComponent, bytesPerRow, colorSpaceDeviceRGBRef, bitmapInfo);
    CGColorSpaceRelease(colorSpaceDeviceRGBRef);
    // Early return on failure!
    if (!bitmapContextRef) {
        NSLog(@"Error: Failed to `CGBitmapContextCreate` with color space %@ and parameters (width: %zu height: %zu bitsPerComponent: %zu bytesPerRow: %zu) for image %@", colorSpaceDeviceRGBRef, width, height, bitsPerComponent, bytesPerRow, imageToPredraw);
        return imageToPredraw;
    }
    
    // Draw image in bitmap context and create image by preserving receiver's properties.
    CGContextDrawImage(bitmapContextRef, CGRectMake(0.0, 0.0, imageToPredraw.size.width, imageToPredraw.size.height), imageToPredraw.CGImage);
    CGImageRef predrawnImageRef = CGBitmapContextCreateImage(bitmapContextRef);
    UIImage *predrawnImage = [UIImage imageWithCGImage:predrawnImageRef scale:imageToPredraw.scale orientation:imageToPredraw.imageOrientation];
    CGImageRelease(predrawnImageRef);
    CGContextRelease(bitmapContextRef);
    
    // Early return on failure!
    if (!predrawnImage) {
        NSLog(@"Error: Failed to `imageWithCGImage:scale:orientation:` with image ref %@ created with color space %@ and bitmap context %@ and properties and properties (scale: %f orientation: %ld) for image %@", predrawnImageRef, colorSpaceDeviceRGBRef, bitmapContextRef, imageToPredraw.scale, (long)imageToPredraw.imageOrientation, imageToPredraw);
        return imageToPredraw;
    }
    
    return predrawnImage;
}


#pragma mark - Description

- (NSString *)description
{
    NSString *description = [super description];
    
    description = [description stringByAppendingFormat:@" size=%@", NSStringFromCGSize(self.size)];
    description = [description stringByAppendingFormat:@" frameCount=%lu", (unsigned long)self.frameCount];
    
    return description;
}


@end
