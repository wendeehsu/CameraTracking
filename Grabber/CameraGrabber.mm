#import "CameraGrabber.h"

#import <mach/mach_time.h>
#import <sys/time.h>

#define FRAME_BGRA 0
#define PREVLAYER 0

@implementation CameraGrabber

@synthesize captureSession = _captureSession;
@synthesize videoConnection = _videoConnection;
@synthesize preset = _preset;
@synthesize imageView = _imageView;
@synthesize prevLayer = _prevLayer;
@synthesize wb = _wb;
@synthesize rb = _rb;
@synthesize ub = _ub;
@synthesize newFrame = _newFrame;

int width;
int height;

#pragma mark -
#pragma mark Initialization
- (id)init
{
    self = [super init];
    if (self) {
        /*We initialize some variables (they might be not initialized depending on what is commented or not)*/
        self.imageView = nil;
        self.prevLayer = nil;
        pthread_mutex_init(&mutex, NULL);
        pthread_cond_init(&cond, NULL);
        areBuffersInited = NO;
        self.wb = 0;
        self.rb = 1;
        self.ub = 2;
        self.newFrame = NO;
        self.preset = AVCaptureSessionPreset640x480;
        _buffers[0] = nil;
        _buffers[1] = nil;
        _buffers[2] = nil;
        _bufferR90 = nil;
        _fps = 30;
        _device = 0;
    }
    //[self initCapture];
    return self;
}

- (id)initWithSessionPreset:(const NSString*)preset UseFPS:(int)fps withDevice:(int)device
{
    self = [super init];
    if (self) {
        /*We initialize some variables (they might be not initialized depending on what is commented or not)*/
        self.imageView = nil;
        self.prevLayer = nil;
        pthread_mutex_init(&mutex, NULL);
        pthread_cond_init(&cond, NULL);
        areBuffersInited = NO;
        self.wb = 0;
        self.rb = 1;
        self.ub = 2;
        self.newFrame = NO;
        self.preset = preset;
        _buffers[0] = nil;
        _buffers[1] = nil;
        _buffers[2] = nil;
        _bufferR90 = nil;
        _fps = fps;
        _device = device;
    }
    //[self initCapture];
    
    return self;
}

- (void)viewDidLoad
{
    /*We intialize the capture*/
    //[self initCapture];
}

- (void)initCapture
{
    /*We setup the input*/
    AVCaptureDeviceInput *captureInput = nil;
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for (AVCaptureDevice *device in devices) {
        if (_device == 0) {
            if ([device position] == AVCaptureDevicePositionFront) {
                captureInput = [AVCaptureDeviceInput deviceInputWithDevice:device error:nil];
                break;
            }
        } else {
            if ([device position] == AVCaptureDevicePositionBack) {
                captureInput = [AVCaptureDeviceInput deviceInputWithDevice:device error:nil];
                break;
            }
        }
    }
    
    if (captureInput == nil) {
        NSLog(@"No camera! Exiting...");
        return;
    }
    
    /*We setupt the output*/
    AVCaptureVideoDataOutput *captureOutput = [[AVCaptureVideoDataOutput alloc] init];
    /*While a frame is processes in -captureOutput:didOutputSampleBuffer:fromConnection: delegate methods no other frames are added in the queue.
     If you don't want this behaviour set the property to NO */
    captureOutput.alwaysDiscardsLateVideoFrames = YES;
    /*We specify a minimum duration for each frame (play with this settings to avoid having too many frames waiting
     in the queue because it can cause memory issues). It is similar to the inverse of the maximum framerate.
     In this example we set a min frame duration of 1/10 seconds so a maximum framerate of 10fps. We say that
     we are not able to process more than 10 frames per second.*/
    //captureOutput.minFrameDuration = CMTimeMake(1, _fps);
    
    /*We create a serial queue to handle the processing of our frames*/
    dispatch_queue_t captureQueue;
    captureQueue = dispatch_queue_create("cameraQueue", DISPATCH_QUEUE_CONCURRENT);
    dispatch_set_target_queue(captureQueue, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0));
    [captureOutput setSampleBufferDelegate:self queue:captureQueue];
    
    //dispatch_queue_t queue = dispatch_queue_create("myQueue", NULL);
    //[output setSampleBufferDelegate:self queue:queue];
    //dispatch_release(queue);
    
    // Set the video output to store frame in BGRA (It is supposed to be faster)
    NSString* key = (NSString*)kCVPixelBufferPixelFormatTypeKey;
#if FRAME_BGRA
    NSNumber* value = [NSNumber numberWithUnsignedInt:kCVPixelFormatType_32BGRA];
#else
    NSNumber* value = [NSNumber numberWithUnsignedInt:kCVPixelFormatType_420YpCbCr8BiPlanarFullRange];
#endif
    NSDictionary* videoSettings = [NSDictionary dictionaryWithObject:value forKey:key];
    [captureOutput setVideoSettings:videoSettings];
    
    /*And we create a capture session*/
    _captureSession = [[AVCaptureSession alloc] init];
    [self.captureSession setSessionPreset:[self.preset copy]];
    /*We add input and output*/
    [self.captureSession addInput:captureInput];
    [self.captureSession addOutput:captureOutput];
    
    
    // Find a suitable AVCaptureDevice
    AVCaptureDevice *device = captureInput.device;//[captureInput device];
    
    NSError *error2;
    [device lockForConfiguration:&error2];
    if (error2 == nil) {
        if (device.activeFormat.videoSupportedFrameRateRanges){
            [device setActiveVideoMinFrameDuration:CMTimeMake(1, _fps)];
            [device setActiveVideoMaxFrameDuration:CMTimeMake(1, _fps)];
        }else{
            //handle condition
        }
    }else{
        // handle error2
    }
    [device unlockForConfiguration];
    
    
    //We add the preview layer
#if PREVLAYER
    self.prevLayer = [AVCaptureVideoPreviewLayer layerWithSession: self.captureSession];
    self.prevLayer.frame = self.view.bounds;
    if ([self.prevLayer isOrientationSupported]) {
        [self.prevLayer setOrientation:AVCaptureVideoOrientationPortrait];
    }
    
    self.prevLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    [self.view.layer addSublayer: self.prevLayer];
#endif
    
}

#pragma mark -
#pragma mark AVCaptureSession delegate
- (void)captureOutput:(AVCaptureOutput *)captureOutput
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection
{
    
    //uint64_t startTime = 0;
    //uint64_t endTime = 0;
    //uint64_t elapsedTime = 0;
    //uint64_t elapsedTimeMilli = 0;
    
    //mach_timebase_info_data_t timeBaseInfo;
    //mach_timebase_info(&timeBaseInfo);
    
    //startTime = mach_absolute_time();
    //time = time * 0.9 + last_frame * 0.1;
    
    //We create an autorelease pool because as we are not in the main_queue our code is
    //not executed in the main thread. So we have to create an autorelease pool for the thread we are in
    
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    //Lock the image buffer
    CVPixelBufferLockBaseAddress(imageBuffer,0);
    //Get information about the image
    uint8_t *baseAddress = (uint8_t *)CVPixelBufferGetBaseAddress(imageBuffer);
    uint8_t *yBaseAddress = (uint8_t *)CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 0);
    //size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
    width = (int) CVPixelBufferGetWidth(imageBuffer);
    height = (int) CVPixelBufferGetHeight(imageBuffer);
    
    unsigned char *src = 0;
#if FRAME_BGRA
    int size = (width*height)*4;
    if (!areBuffersInited) {
        _bufferR90 = new uint8_t[size];
        for (int i = 0; i < 3; i++) {
            _buffers[i] = new uint8_t[size];
        }
        areBuffersInited = YES;
    }
    
    src = (unsigned char*) baseAddress;
    // using memcpy
    memcpy(_buffers[self.wb], (char *)src, sizeof(uint8_t)*size);
    
#else
    int size = (width*height)*3/2;
    if (!areBuffersInited) {
        _bufferR90 = new uint8_t[size];
        for (int i = 0; i < 3; i++) {
            _buffers[i] = new uint8_t[size];
        }
        areBuffersInited = YES;
    }
    
    src = (unsigned char*) yBaseAddress;
    // using memcpy
    memcpy(_buffers[self.wb], (char *)src, sizeof(uint8_t)*size);
#endif
    
    int tmp;
    pthread_mutex_lock(&mutex);
    //NSLog(@"Writing to %d Read %d", self.wb, self.rb);
    tmp = self.wb;
    self.wb = self.rb;
    self.rb = tmp;
    self.newFrame = YES;
    pthread_cond_signal(&cond);
    pthread_mutex_unlock(&mutex);
    
    //We unlock the  image buffer
    CVPixelBufferUnlockBaseAddress(imageBuffer,0);
    
    
    //endTime = mach_absolute_time();
    
    //elapsedTime = endTime - startTime;
    //elapsedTimeMilli = elapsedTime * timeBaseInfo.numer / (timeBaseInfo.denom * 1e6);
    //NSLog(@"Time needed: %f for frame: %dx%d", elapsedTimeMilli, width, height);
}

-(void) startCapture:(UIView *)camView withCamera:(int)camera
{
    self.view = camView;
    _device = camera;
    [self initCapture];
    [self.captureSession startRunning];
}

- (void)stopCapture
{
    [self.captureSession stopRunning];
    pthread_mutex_lock(&mutex);
    NSLog(@"Stopping camera capture...");
    self.newFrame = YES;
    pthread_cond_signal(&cond);
    pthread_mutex_unlock(&mutex);
}

- (int)getPixelFormat
{
#if FRAME_BGRA
    return 4;
#else
    return 1;
#endif
}

- (unsigned char*)getBuffer:(int)rotated isMirrored:(int)mirrored
{
    struct timespec   ts;
    struct timeval    tp;
    
    int rc = gettimeofday(&tp, NULL);
    
    if(rc!=0)
        return 0;
    
    /* Convert from timeval to timespec */
    ts.tv_sec  = tp.tv_sec + 5;
    ts.tv_nsec = 0;
    
    pthread_mutex_lock(&mutex);
    
    while (!_newFrame) {
        int ret = pthread_cond_timedwait(&cond, &mutex, &ts);
        if (ret == ETIMEDOUT)
        {
            NSLog(@"cond timed out\n");
            pthread_mutex_unlock(&mutex);
            return 0;
        }
    }
    
    int tmp = self.ub;
    self.ub = self.rb;
    self.rb = tmp;
    //NSLog(@"Using %d Read %d", self.ub, self.rb);
    self.newFrame = NO;
    pthread_mutex_unlock(&mutex);
    
    
    if (_buffers[self.ub] != nil) {
#if FRAME_BGRA
        [self rotateBGRA: _buffers[self.ub] _saveTo:_bufferR90 _width:width _height:height _rotation:rotated _cameraDevice:_device _mirrored:mirrored];
#else
        [self rotateYUV: _buffers[self.ub] _saveTo:_bufferR90 _width:width _height:height _rotation:rotated _cameraDevice:_device _mirrored:mirrored];
#endif
    }
    
    return (unsigned char*)_bufferR90;
    
}

- (void)rotateYUV:(uint8_t*)yuv _saveTo:(uint8_t*)output _width:(int)width _height:(int)height _rotation:(int)rotation _cameraDevice:(int)device _mirrored:(int)mirrored
{
    int frameSize = width * height;
    Boolean swap = false;
    Boolean xflip = false;
    Boolean yflip = false;
    
    if (rotation == 0)
    {
        swap = true;
        
        if (mirrored == 1)
        {
            if (device == 1)
                xflip = true;
        }
        
        else if (mirrored == 0)
        {
            if (device == 0)
                xflip = true;
        }
    }
    
    else if (rotation == 1)
    {
        if (mirrored == 1)
            xflip = true;
        
        if (device == 1)
            yflip = true;
    }
    
    else if (rotation == 2)
    {
        swap = true;
        yflip = true;
        
        if (mirrored == 1)
        {
            if (device == 0)
                xflip = true;
        }
        
        else if (mirrored == 0)
        {
            if (device == 1)
                xflip = true;
        }
    }
    
    else
    {
        yflip = true;
        
        if (mirrored == 0)
            xflip = true;
        
        if (device == 1)
            yflip = false;
    }
    
    
    for (int j = 0; j < height; j++) {
        for (int i = 0; i < width; i++) {
            int yIn = j * width + i;
            int uIn = frameSize + (j >> 1) * width + (i & ~1);
            int vIn = uIn       + 1;
            
            int wOut     = swap  ? height              : width;
            int hOut     = swap  ? width               : height;
            int iSwapped = swap  ? j                   : i;
            int jSwapped = swap  ? i                   : j;
            int iOut     = xflip ? wOut - iSwapped - 1 : iSwapped;
            int jOut     = yflip ? hOut - jSwapped - 1 : jSwapped;
            
            int yOut = jOut * wOut + iOut;
            int uOut = frameSize + (jOut >> 1) * wOut + (iOut & ~1);
            int vOut = uOut + 1;
            
            output[yOut] = (0xff & yuv[yIn]);
            output[uOut] = (0xff & yuv[uIn]);
            output[vOut] = (0xff & yuv[vIn]);
        }
    }
}


- (void)rotateBGRA:(uint8_t*)rgba _saveTo:(uint8_t*)output _width:(int)width _height:(int)height _rotation:(int)rotation _cameraDevice:(int)device _mirrored:(int)mirrored
{
    Boolean swap = false;
    Boolean xflip = false;
    Boolean yflip = false;
    
    if (rotation == 0)
    {
        swap = true;
        
        if (mirrored == 1)
        {
            if (device == 1)
                xflip = true;
        }
        
        else if (mirrored == 0)
        {
            if (device == 0)
                xflip = true;
        }
    }
    
    else if (rotation == 1)
    {
        if (mirrored == 1)
            xflip = true;
        
        if (device == 1)
            yflip = true;
    }
    
    else if (rotation == 2)
    {
        swap = true;
        yflip = true;
        
        if (mirrored == 1)
        {
            if (device == 0)
                xflip = true;
        }
        
        else if (mirrored == 0)
        {
            if (device == 1)
                xflip = true;
        }
    }
    
    else
    {
        yflip = true;
        
        if (mirrored == 0)
            xflip = true;
        
        if (device == 1)
            yflip = false;
    }
    
    
    for (int j = 0; j < height; j++) {
        for (int i = 0; i < width; i++) {
            int rIn = j * width * 4 + 4*i + 0;
            int gIn = j * width * 4 + 4*i + 1;
            int bIn = j * width * 4 + 4*i + 2;
            int aIn = j * width * 4 + 4*i + 3;
            
            int wOut     = swap  ? height              : width;
            int hOut     = swap  ? width               : height;
            int iSwapped = swap  ? j                   : i;
            int jSwapped = swap  ? i                   : j;
            int iOut     = xflip ? wOut - iSwapped - 1 : iSwapped;
            int jOut     = yflip ? hOut - jSwapped - 1 : jSwapped;
            
            int rOut = jOut * wOut * 4 + 4*iOut + 0;
            int gOut = jOut * wOut * 4 + 4*iOut + 1;
            int bOut = jOut * wOut * 4 + 4*iOut + 2;
            int aOut = jOut * wOut * 4 + 4*iOut + 3;
            
            output[rOut] = (0xff & rgba[rIn]);
            output[gOut] = (0xff & rgba[gIn]);
            output[bOut] = (0xff & rgba[bIn]);
            output[aOut] = (0xff & rgba[aIn]);
        }
    }
}


#pragma mark -
#pragma mark Memory management

- (void)viewDidUnload
{
    self.imageView = nil;
    self.prevLayer = nil;
}

- (void)dealloc
{
    [self stopCapture];
    
    if (areBuffersInited) {
        for (int i = 0; i < 3; i++) {
            delete[] _buffers[i];
        }
        
        delete[] _bufferR90;
    }
    
    pthread_mutex_destroy(&mutex);
    pthread_cond_destroy(&cond);
}


@end
