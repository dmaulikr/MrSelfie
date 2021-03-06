//
//  MSPreviewViewController.m
//  MrSelfie
//
//  Created by Weixi Yen on 5/15/14.
//  Copyright (c) 2014 MSStorm8. All rights reserved.
//

#import "MSPreviewViewController.h"
#import "Mixpanel.h"
#import <AssetsLibrary/AssetsLibrary.h>
#import <ImageIO/ImageIO.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>

static NSString *const GIF_FILE_NAME = @"animated.gif";
static NSString *const PHOTO_FILE_NAME = @"shots.jpg";

typedef enum {
    MediaTypeStateVideo,
    MediaTypeStatePhoto
} MediaTypeState;

typedef enum {
    PhotoOrientationPortrait,
    PhotoOrientationLandscape
} PhotoOrientation;

@interface MSPreviewViewController ()

@property (nonatomic, strong) IBOutlet UISegmentedControl *mediaTypeSegmentedControl;
@property (nonatomic, strong) IBOutlet UIView *segmentedControlBackgroundView;
@property (nonatomic, strong) IBOutlet UIImageView *imageView;
@property (nonatomic, strong) IBOutlet UIView *buttonContainerView;
@property (nonatomic, strong) IBOutlet UIView *segmentControlContainer;
@property (nonatomic, strong) IBOutlet UIButton *shareButton;
@property (nonatomic, strong) IBOutlet UIButton *retakeButton;
@property (nonatomic) int currentIndex;
@property (nonatomic, strong) NSURL *videoUrl;
@property (nonatomic, strong) NSURL *photoUrl;
@property (nonatomic, strong) UIImage *firstImage;
@property (nonatomic, strong) AVAssetWriter *videoWriter;
@property (nonatomic) MediaTypeState mediaType;

@property (nonatomic, strong) IBOutlet UIView *tutorialBackgroundView;
@property (nonatomic, strong) IBOutlet UIImageView *tutorialImageView;
@property (nonatomic) BOOL tutorialSwitchCompleted;

- (IBAction)share:(id)sender;
- (IBAction)retake:(id)sender;
- (IBAction)mediaTypeSwitched:(id)sender;

@end


@implementation MSPreviewViewController

#pragma mark - overwritten methods

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(orientationChanged)
                                                 name:UIDeviceOrientationDidChangeNotification
                                               object:nil];
    
    
    self.mediaType = MediaTypeStateVideo;
    self.videoUrl = nil;
    self.firstImage = [self.photos objectAtIndex:0];
    self.segmentedControlBackgroundView.layer.cornerRadius = 3.5f;

    NSMutableArray *arr = [NSMutableArray array];
    NSMutableArray *precisions = [NSMutableArray array];

    CGFloat alpha = 0.0f;

    for (int i=0; i<35; i++) {

        if (i > 30 && i < 35) {
            UIImage *test = [self addFlashOverlay:self.firstImage withAlpha:alpha];

            alpha += .2;

            [arr addObject:test];
            [precisions addObject:[self.positions objectAtIndex:0]];
        } else {
            [arr addObject:self.firstImage];
            [precisions addObject:[self.positions objectAtIndex:0]];
        }
    }
    
    PhotoOrientation photoOrientation = PhotoOrientationPortrait;
    if (self.firstImage.size.width > self.firstImage.size.height) {
        photoOrientation = PhotoOrientationLandscape;
    }
    
    int i = 0;
    for (UIImage *img in self.photos) {
        if (img.size.width < img.size.height && photoOrientation == PhotoOrientationPortrait) {
            [arr addObject:img];
            [arr addObject:img];
            [precisions addObject:[self.positions objectAtIndex:i]];
            [precisions addObject:[self.positions objectAtIndex:i]];
        }
        
        if (img.size.width > img.size.height && photoOrientation == PhotoOrientationLandscape) {
            [arr addObject:img];
            [arr addObject:img];
            [precisions addObject:[self.positions objectAtIndex:i]];
            [precisions addObject:[self.positions objectAtIndex:i]];
        }
        
        i += 1;
    }

    self.photos = arr;
    self.positions = precisions;

    self.currentIndex = self.photos.count - 1;
    [self showNextImage];

    [self createVideo];
    [self createPhoto];

    [self trackShotTaken];
    [self showTutorial];
}

- (UIImage *)addFlashOverlay:(UIImage *)backImage withAlpha:(CGFloat)alpha {

    UIImage *flashOverlay = [self imageWithColor:[UIColor colorWithRed:1.0f green:1.0f blue:1.0f alpha:alpha]
                                         andSize:backImage.size];

    UIImage *newImage;

    CGRect rect = CGRectMake(0, 0, backImage.size.width, backImage.size.height);

    // Begin context
    UIGraphicsBeginImageContext(rect.size);

    // draw images
    [backImage drawInRect:rect];
    [flashOverlay drawInRect:rect];

    // grab context
    newImage = UIGraphicsGetImageFromCurrentImageContext();

    // end context
    UIGraphicsEndImageContext();

    return newImage;
}

- (UIImage *)imageWithColor:(UIColor *)color andSize:(CGSize)size {
    CGRect rect = CGRectMake(0.0f, 0.0f, size.width, size.height);

    // Begin context
    UIGraphicsBeginImageContext(rect.size);

    CGContextRef context = UIGraphicsGetCurrentContext();

    CGContextSetFillColorWithColor(context, [color CGColor]);
    CGContextFillRect(context, rect);

    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();

    UIGraphicsEndImageContext();

    return image;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self orientationChanged];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [[UIDevice currentDevice] endGeneratingDeviceOrientationNotifications];
}

- (void)showNextImage {
    if (self.currentIndex < 0) {
        [self performSelector:@selector(showNextImage) withObject:nil afterDelay:0.3];
        return;
    }
    
    if (self.currentIndex <= 0 && self.mediaType == MediaTypeStatePhoto) {
        [self performSelector:@selector(showNextImage) withObject:nil afterDelay:0.3];
        return;
    }
    
    UIImage *image = [self.photos objectAtIndex:self.currentIndex];
    UIImage* flippedImage = [UIImage imageWithCGImage:image.CGImage
                                                scale:image.scale orientation:UIImageOrientationUpMirrored];
    
    if (self.currentIndex > 30 && self.currentIndex < 35) {        
        [self.imageView setImage:image];
    } else {
        if ([self isFlipped:self.currentIndex]) {
            [self.imageView setImage:flippedImage];
        } else {
            [self.imageView setImage:image];
        }
    }
    
    // reached the end of slideshow
    if (self.currentIndex == 0) {
        self.currentIndex = self.photos.count - 1;
        [self performSelector:@selector(showNextImage) withObject:nil afterDelay:0.3];
        return;
    }
    
    // default case, increment and show the next image
    self.currentIndex -= 1;
    [self performSelector:@selector(showNextImage) withObject:nil afterDelay:0.1];
}

- (IBAction)share:(id)sender {
    if (!self.videoUrl && self.mediaType == MediaTypeStateVideo) {
        return;
    }
    
    if (!self.photoUrl && self.mediaType == MediaTypeStatePhoto) {
        return;
    }

    NSString *string = @"Taken with http://shotsapp.co";
    
    NSMutableArray *activityItems = [NSMutableArray array];
    [activityItems addObject:string];
    
    if (self.mediaType == MediaTypeStateVideo) {
        [activityItems addObject:self.videoUrl];
    } else if (self.mediaType == MediaTypeStatePhoto) {
        [activityItems addObject:self.photoUrl];
    }

    // open up fb share
    UIActivityViewController *activityViewController =
    [[UIActivityViewController alloc] initWithActivityItems:activityItems
                                      applicationActivities:nil];
    
    [activityViewController setCompletionHandler:^(NSString *activityType, BOOL completed) {
        NSString *shareMediaType = @"NONE";
        
        if([activityType isEqualToString: UIActivityTypeMail]){
            shareMediaType = @"MAIL";
        }
        
        if([activityType isEqualToString: UIActivityTypePostToFacebook]){
            shareMediaType = @"FACEBOOK";
        }
        
        if([activityType isEqualToString: UIActivityTypePostToTwitter]){
            shareMediaType = @"TWITTER";
        }
        
        if([activityType isEqualToString: UIActivityTypeSaveToCameraRoll]){
            shareMediaType = @"SAVE_TO_CAMERA";
        }
        
        if([activityType isEqualToString: UIActivityTypeCopyToPasteboard]){
            shareMediaType = @"COPIED_TO_PASTEBOARD";
        }
        
        if([activityType isEqualToString: UIActivityTypeMessage]){
            shareMediaType = @"MESSAGE";
        }
        
        [[Mixpanel sharedInstance] track:@"SUCCESSFULLY_SHARED_VIDEO" properties:@{
                                                                                   @"TYPE": shareMediaType,
                                                                                   }];
        
        NSLog(@"SHARE DONE!");
    }];

    [self presentViewController:activityViewController
                                       animated:YES
                                     completion:nil];
    
    [[Mixpanel sharedInstance] track:@"CLICKED_SHARE_BUTTON"];
}

- (IBAction)retake:(id)sender {
    self.imageView.image = nil;
    __weak __typeof(self) weakSelf = self;
    [self dismissViewControllerAnimated:NO completion:^(void){
        weakSelf.photos = nil;
        weakSelf.positions = nil;
    }];
    
    [[Mixpanel sharedInstance] track:@"CLICKED_RETAKE_BUTTON"];
}

- (IBAction)mediaTypeSwitched:(id)sender {
    UISegmentedControl *segmentedControl = (UISegmentedControl *) sender;
    NSInteger selectedSegment = segmentedControl.selectedSegmentIndex;
    
    if (selectedSegment == 0) {
        self.mediaType = MediaTypeStateVideo;
        self.currentIndex = self.photos.count - 1;
    } else {
        self.mediaType = MediaTypeStatePhoto;
        self.currentIndex = 35;
        
        [self setTutorialSwitchComplete];
    }
}

#pragma mark - Animated Gif

- (void)createAnimatedGif {
    int frameCount = self.photos.count;
    
    NSDictionary *fileProperties = @{
                                 (__bridge id)kCGImagePropertyGIFDictionary: @{
                                         (__bridge id)kCGImagePropertyGIFLoopCount: @0, // 0 means loop forever
                                         }
                                 };
    
    NSDictionary *frameProperties = @{
                                      (__bridge id)kCGImagePropertyGIFDictionary: @{
                                              (__bridge id)kCGImagePropertyGIFDelayTime: @0.1f, // a float (not double!) in seconds, rounded to centiseconds in the GIF data
                                              }
                                      };
    
    NSDictionary *finalFrameProperties = @{
                                      (__bridge id)kCGImagePropertyGIFDictionary: @{
                                              (__bridge id)kCGImagePropertyGIFDelayTime: @3.0f, // a float (not double!) in seconds, rounded to centiseconds in the GIF data
                                              }
                                      };
    
    NSURL *documentsDirectoryURL = [[NSFileManager defaultManager] URLForDirectory:NSDocumentDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:nil];
    NSURL *fileURL = [documentsDirectoryURL URLByAppendingPathComponent:GIF_FILE_NAME];
    
    CGImageDestinationRef destination = CGImageDestinationCreateWithURL((__bridge CFURLRef)fileURL, kUTTypeGIF, frameCount, NULL);
    CGImageDestinationSetProperties(destination, (__bridge CFDictionaryRef)fileProperties);
    
    for (int i = self.photos.count - 1; i >= 0; i--) {
        @autoreleasepool {
            UIImage *image = [self.photos objectAtIndex:i];
            
            if (i == 0) {
                CGImageDestinationAddImage(destination, image.CGImage, (__bridge CFDictionaryRef)finalFrameProperties);
            } else {
                CGImageDestinationAddImage(destination, image.CGImage, (__bridge CFDictionaryRef)frameProperties);
            }
        }
    }
    
    if (!CGImageDestinationFinalize(destination)) {
        NSLog(@"failed to finalize image destination");
    }
    
    CFRelease(destination);
    NSLog(@"%@", fileURL);
    self.videoUrl = fileURL;
//    [[[ALAssetsLibrary alloc] init] writeImageDataToSavedPhotosAlbum:[NSData dataWithContentsOfURL:fileURL] metadata:nil completionBlock:nil];
}


#pragma mark - Photo 

- (void)createPhoto {
    dispatch_async(dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void){
        UIImage *photo = self.firstImage;
        NSData *photoData = UIImageJPEGRepresentation(photo, 0.0);
        NSURL *documentsDirectoryURL = [[NSFileManager defaultManager] URLForDirectory:NSDocumentDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:nil];
        NSURL *fileUrl = [documentsDirectoryURL URLByAppendingPathComponent:PHOTO_FILE_NAME];
        [photoData writeToURL:fileUrl atomically:YES];
        
        self.photoUrl = fileUrl;
    });
}


#pragma mark - Video

- (void)createVideo {
    
    dispatch_async(dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void){
        //Background Thread
        
        ///////////// setup OR function def if we move this to a separate function ////////////
        // this should be moved to its own function, that can take an imageArray, videoOutputPath, etc...
        //    - (void)exportImages:(NSMutableArray *)imageArray
        // asVideoToPath:(NSString *)videoOutputPath
        // withFrameSize:(CGSize)imageSize
        // framesPerSecond:(NSUInteger)fps {
        
        NSError *error = nil;
        
        
        // set up file manager, and file videoOutputPath, remove "test_output.mp4" if it exists...
        //NSString *videoOutputPath = @"/Users/someuser/Desktop/test_output.mp4";
        NSFileManager *fileMgr = [NSFileManager defaultManager];
        NSString *documentsDirectory = [NSHomeDirectory()
                                        stringByAppendingPathComponent:@"Documents"];
        NSString *videoOutputPath = [documentsDirectory stringByAppendingPathComponent:@"selfie.mp4"];
        //NSLog(@"-->videoOutputPath= %@", videoOutputPath);
        // get rid of existing mp4 if exists...
        if ([fileMgr removeItemAtPath:videoOutputPath error:&error] != YES)
            NSLog(@"Unable to delete file: %@", [error localizedDescription]);
        
        CGSize imageSize = CGSizeMake(self.firstImage.size.width, self.firstImage.size.height);
        NSUInteger fps = 15;
        
        
        
        //////////////     end setup    ///////////////////////////////////
        
        NSLog(@"Start building video from defined frames.");
        
        self.videoWriter = [[AVAssetWriter alloc] initWithURL:
                            [NSURL fileURLWithPath:videoOutputPath] fileType:AVFileTypeQuickTimeMovie
                                                        error:&error];
        NSParameterAssert(self.videoWriter);
        
        NSDictionary *videoSettings = [NSDictionary dictionaryWithObjectsAndKeys:
                                       AVVideoCodecH264, AVVideoCodecKey,
                                       [NSNumber numberWithInt:imageSize.width], AVVideoWidthKey,
                                       [NSNumber numberWithInt:imageSize.height], AVVideoHeightKey,
                                       nil];
        
        AVAssetWriterInput* videoWriterInput = [AVAssetWriterInput
                                                assetWriterInputWithMediaType:AVMediaTypeVideo
                                                outputSettings:videoSettings];
        
        
        AVAssetWriterInputPixelBufferAdaptor *adaptor = [AVAssetWriterInputPixelBufferAdaptor
                                                         assetWriterInputPixelBufferAdaptorWithAssetWriterInput:videoWriterInput
                                                         sourcePixelBufferAttributes:nil];
        
        NSParameterAssert(videoWriterInput);
        NSParameterAssert([self.videoWriter canAddInput:videoWriterInput]);
        videoWriterInput.expectsMediaDataInRealTime = YES;
        [self.videoWriter addInput:videoWriterInput];
        
        //Start a session:
        [self.videoWriter startWriting];
        [self.videoWriter startSessionAtSourceTime:kCMTimeZero];
        
        CVPixelBufferRef buffer = NULL;
        
        //convert uiimage to CGImage.
        int frameCount = 0;
        double numberOfSecondsPerFrame = 0.1;
        double frameDuration = fps * numberOfSecondsPerFrame;
        
        //for(VideoFrame * frm in imageArray)
        NSLog(@"**************************************************");
        
        for (int i=self.photos.count-1; i>=0; i--)
        {
            UIImage *img = self.photos[i];
            //UIImage * img = frm._imageFrame;
            if (buffer) {
                CVBufferRelease(buffer);
            }
            
            buffer = [self pixelBufferFromCGImage:[img CGImage] flip:[self isFlipped:i]];
            
            BOOL append_ok = NO;
            int j = 0;
            while (!append_ok && j < 30) {
                if (adaptor.assetWriterInput.readyForMoreMediaData)  {
                    //print out status:
                    NSLog(@"Processing video frame (%d,%d)",frameCount,(int)[self.photos count]);
                    
                    CMTime frameTime = CMTimeMake(frameCount*frameDuration,(int32_t) fps);
                    
                    append_ok = [adaptor appendPixelBuffer:buffer withPresentationTime:frameTime];
                    if(!append_ok){
                        NSError *error = self.videoWriter.error;
                        if(error!=nil) {
                            NSLog(@"Unresolved error %@,%@.", error, [error userInfo]);
                        }
                    }
                }
                else {
                    printf("adaptor not ready %d, %d\n", frameCount, j);
                    [NSThread sleepForTimeInterval:0.1];
                }
                j++;
            }
            if (!append_ok) {
                printf("error appending image %d times %d\n, with error.", frameCount, j);
            }
            frameCount++;
        }
        NSLog(@"**************************************************");
        
        //Finish the session:
        [videoWriterInput markAsFinished];
        [self.videoWriter finishWritingWithCompletionHandler:^(void) {
            CVBufferRelease(buffer);
            self.videoWriter = nil;
        }];
        NSLog(@"Write Ended");
        
        self.videoUrl = [NSURL fileURLWithPath:videoOutputPath];
        NSLog(@"%@", self.videoUrl);
    });
    
    
}

- (CVPixelBufferRef) pixelBufferFromCGImage: (CGImageRef)image flip:(BOOL)flip {
    CGSize size = CGSizeMake(self.firstImage.size.width, self.firstImage.size.height);
    
    NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:
                             [NSNumber numberWithBool:YES], kCVPixelBufferCGImageCompatibilityKey,
                             [NSNumber numberWithBool:YES], kCVPixelBufferCGBitmapContextCompatibilityKey,
                             nil];
    CVPixelBufferRef pxbuffer = NULL;
    
    CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault,
                                          size.width,
                                          size.height,
                                          kCVPixelFormatType_32ARGB,
                                          (__bridge CFDictionaryRef) options,
                                          &pxbuffer);
    
    if (status != kCVReturnSuccess){
        NSLog(@"Failed to create pixel buffer");
    }
    
    CVPixelBufferLockBaseAddress(pxbuffer, 0);
    void *pxdata = CVPixelBufferGetBaseAddress(pxbuffer);
    
    CGColorSpaceRef rgbColorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pxdata, size.width,
                                                 size.height, 8, 4*size.width, rgbColorSpace,
                                                 kCGImageAlphaPremultipliedFirst);
    
    
    if (flip) {
        CGAffineTransform transform = CGAffineTransformMakeTranslation(size.width, 0.0);
        transform = CGAffineTransformScale(transform, -1.0, 1.0);
        CGContextConcatCTM(context, transform);
    }
    
    //kCGImageAlphaNoneSkipFirst);
    CGContextConcatCTM(context, CGAffineTransformMakeRotation(0));
    CGContextDrawImage(context, CGRectMake(0, 0, CGImageGetWidth(image),
                                           CGImageGetHeight(image)), image);
    CGColorSpaceRelease(rgbColorSpace);
    CGContextRelease(context);
    
    CVPixelBufferUnlockBaseAddress(pxbuffer, 0);
    
    return pxbuffer;
}

#pragma mark - rotation

- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration {
    [UIView setAnimationsEnabled:NO];
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation {
    [UIView setAnimationsEnabled:YES];
}

- (void)orientationChanged {
    UIDevice *device = [UIDevice currentDevice];
    int maxLength = MAX(self.view.frame.size.width, self.view.frame.size.height);
    int minLength = MIN(self.view.frame.size.width, self.view.frame.size.height);
    switch (device.orientation) {
        case UIDeviceOrientationPortrait:
            self.buttonContainerView.transform = CGAffineTransformIdentity;
            self.buttonContainerView.frame = CGRectMake(0, maxLength - self.buttonContainerView.bounds.size.height, self.buttonContainerView.bounds.size.width, self.buttonContainerView.bounds.size.height);
            self.segmentControlContainer.transform = CGAffineTransformIdentity;
            self.segmentControlContainer.frame = CGRectMake(0, 0, self.segmentControlContainer.bounds.size.width, self.segmentControlContainer.bounds.size.height);
            break;
        case UIDeviceOrientationLandscapeLeft:
            self.buttonContainerView.transform = CGAffineTransformMakeRotation(-M_PI_2);
            self.buttonContainerView.center = CGPointMake(maxLength - self.buttonContainerView.frame.size.width / 2, minLength / 2);
            self.segmentControlContainer.transform = CGAffineTransformMakeRotation(-M_PI_2);
            self.segmentControlContainer.center = CGPointMake(self.segmentControlContainer.frame.size.width / 2, minLength / 2);
            break;
        case UIDeviceOrientationLandscapeRight:
            self.buttonContainerView.transform = CGAffineTransformMakeRotation(M_PI_2);
            self.buttonContainerView.center = CGPointMake(self.buttonContainerView.frame.size.width / 2, minLength / 2);
            self.segmentControlContainer.transform = CGAffineTransformMakeRotation(M_PI_2);
            self.segmentControlContainer.center = CGPointMake(maxLength - self.segmentControlContainer.frame.size.width / 2, minLength / 2);
            break;
        default:
            break;
    }
}


#pragma mark - tracking

- (void)trackShotTaken {
    UIDeviceOrientation orientation = [[UIDevice currentDevice] orientation];
    
    NSString *orientationString = @"LANDSCAPE";

    if (orientation == UIDeviceOrientationPortrait || orientation == UIDeviceOrientationPortraitUpsideDown) {
        orientationString = @"PORTRAIT";
    }
    
    NSNumber *length = [NSNumber numberWithLong:(self.photos.count - 15)];
    
    [[Mixpanel sharedInstance] track:@"SHOT_TAKEN" properties:@{
                                                                @"LENGTH": length,
                                                                @"ORIENTATION": orientationString,
                                                                }];
}

#pragma mark - Status Bar

- (BOOL)prefersStatusBarHidden {
    return YES;
}

#pragma mark - Flipped or not

- (BOOL)isFlipped:(int)index {
    if ([[self.positions objectAtIndex:index] intValue] == AVCaptureDevicePositionFront) {
        return YES;
    }
    return NO;
}

#pragma mark - tutorial

- (void)showTutorial {
    return; // disable tutorial
    
    self.tutorialSwitchCompleted = YES;
    
    dispatch_async(dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void){
        self.tutorialSwitchCompleted = [[NSUserDefaults standardUserDefaults] boolForKey:@"tutorial-switch"];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!self.tutorialSwitchCompleted) {
                self.tutorialBackgroundView.hidden = NO;
            } else {
                self.tutorialBackgroundView.hidden = YES;
            }
        });
    });
}

- (void)setTutorialSwitchComplete {
    if (self.tutorialSwitchCompleted == YES) {
        return;
    }
    
    self.tutorialSwitchCompleted = YES;
    
    dispatch_async(dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void){
        [[NSUserDefaults standardUserDefaults] setObject:[[NSNumber alloc] initWithBool:YES] forKey:@"tutorial-switch"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showTutorial];
        });
    });
}

@end