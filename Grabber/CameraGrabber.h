#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreMedia/CoreMedia.h>
#import <visageVision.h>

// declare C++ implementation for .m (Obj-C) files
#ifdef __OBJC__
#ifndef __cplusplus
typedef void VsImage;
#endif
#endif

@interface CameraGrabber : UIViewController <AVCaptureVideoDataOutputSampleBufferDelegate> {
    AVCaptureSession *_captureSession;
    AVCaptureConnection *_videoConnection;
    const NSString *_preset;
    UIImageView *_imageView;
    AVCaptureVideoPreviewLayer *_prevLayer;
    
    uint8_t *_buffers[3];
    uint8_t *_bufferR90;
    
    int _wb;
    int _rb;
    int _ub;
    pthread_mutex_t mutex;
    pthread_cond_t cond;
    BOOL areBuffersInited;
    BOOL _newFrame;
    int _fps;
    int _device;
}

/*!
 @brief    The capture session takes the input from the camera and capture it
 */
@property (nonatomic, retain) AVCaptureSession *captureSession;

@property (nonatomic, retain) AVCaptureConnection *videoConnection;

@property (nonatomic, retain) const NSString *preset;
/*!
 @brief    The UIImageView we use to display the image generated from the imageBuffer
 */
@property (nonatomic, retain) UIImageView *imageView;
/*!
 @brief    The CALAyer customized by apple to display the video corresponding to a capture session
 */
@property (nonatomic, retain) AVCaptureVideoPreviewLayer *prevLayer;

@property (nonatomic) int wb;
@property (nonatomic) int rb;
@property (nonatomic) int ub;
@property (nonatomic) BOOL newFrame;

- (id)initWithSessionPreset:(const NSString*)preset UseFPS:(int)fps withDevice:(int)device;
/*!
 @brief    This method initializes the capture session
 */
- (void)initCapture;
- (void)startCapture:(UIView *) camView withCamera:(int)camera;
- (void)stopCapture;
- (int)getPixelFormat;
//- (void)getFrame:(unsigned char*) imageData;
- (unsigned char*)getBuffer:(int)rotated isMirrored:(int)mirrored;

@end
