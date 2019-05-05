#import "TrackerWrapper.h"
#import "visageVision.h"
#import "DemoFrameGrabber.h"
#import "UIDeviceHardware.h"
#include <sys/timeb.h>

using namespace VisageSDK;

@implementation TrackerWrapper
@synthesize glView;

static CameraGrabber *cameraGrabber = 0;
static VideoGrabber *videoGrabber = 0;
long fg_pts = -1;
static int *trackerStatus = TRACK_STAT_OFF;
const int max_faces = 4;
bool isTracking=false;
static bool threadRunning = false;
static NSCondition *waitHandle;
long currentTime;
long startTime;
int frameCount; // frame count from beginning of tracking
double frameTime; // duration of one frame in milliseconds
const NSString *preset;
int _device = 0;
NSString *path = nil;
int _width;
int _height;
int cam_width;
int cam_height;
BOOL fileExists = false;
int _framerate;
int _rotated = 0;
int _isMirrored = 1;

//pure track time variables
long startTrackTime = 0;
long endTrackTime = 0;
long elapsedTrackTime = 0;

//logo image
VsImage* logo = NULL;
int logoViewportWidth;
int logoViewportHeight;

void YUV_TO_RGBA(unsigned char* yuv, unsigned char* buff, int width, int height);

int clamp(int x)
{
	unsigned y;
	return !(y=x>>8) ? x : (0xff ^ (y>>24));
}

//helper method for converting UIImage to VsImage
VsImage *CreateVsImageFromUIImage(UIImage *image, int nChannels);

// comment this to use head tracking configuration
#define FACE_TRACKER

- (void)initTracker:(CustomGLView *)view withInformer:(Informer *)informer
{
	waitHandle = [NSCondition new];
	threadRunning = false;
	
	//initialize licensing
	//example how to initialize license key
	initializeLicenseManager("452-200-213-720-601-632-039-228-064-839-022.vlc");
	
	if (self->m_informer == NULL)
		self->m_informer = informer;
	
	glView = view;

	// choose configuration based on device at run-time
	NSString* deviceType = [UIDeviceHardware platform];
	
	//NSLog(deviceType);
#ifdef FACE_TRACKER
	if ([deviceType hasPrefix:@"iPhone3"] ||           // iPhone4
		[deviceType hasPrefix:@"iPhone4"] ||           // iPhone4S
		[deviceType hasPrefix:@"iPad2"]                // iPad2
		)
		tracker = new VisageTracker("Facial Features Tracker - Low.cfg");
	else
		tracker = new VisageTracker("Facial Features Tracker - High.cfg");      // all other devices
#else
	tracker = new VisageTracker("Head Tracker.cfg");
#endif

	//get OpenGL context size
	glWidth = glView.bounds.size.width;
	glHeight = glView.bounds.size.height;
	
	inGetTrackingResults = false;
    
    //load logo image by the given path
    NSString *logoPath = [[NSBundle mainBundle] pathForResource:@"logo" ofType:@"png"];
    UIImage *logoImage = [UIImage imageWithContentsOfFile:logoPath];
    logo = CreateVsImageFromUIImage(logoImage, 4);
}

- (void) trackingCamThread:(id)object
{
	int cam_fps = 30;
	
	getOrientation();
	setDimensions(_rotated);
	
	// if camera already works, release
	if(cameraGrabber)
	{
		cameraGrabber = 0;
	}
	
	// initialize new camera
	cameraGrabber = [[CameraGrabber alloc] initWithSessionPreset:preset UseFPS:cam_fps withDevice:_device];
    [cameraGrabber startCapture:nil withCamera:_device];

	m_frame = vsCreateImage(vsSize(cam_width, cam_height), VS_DEPTH_8U, 4);
	
	int pixelFormat = [cameraGrabber getPixelFormat];
	int format = VISAGE_FRAMEGRABBER_FMT_LUMINANCE;
	
	if (pixelFormat == 1)
		format = VISAGE_FRAMEGRABBER_FMT_LUMINANCE;
	else
		format = VISAGE_FRAMEGRABBER_FMT_BGRA;
	
    
	while(isTracking)
	{
		getOrientation();
		setDimensions(_rotated);
		
		unsigned char* pixels = [cameraGrabber getBuffer:_rotated isMirrored:_isMirrored];
		
        startTrackTime = [self getCurrentTimeMs];
		trackerStatus = tracker->track(cam_width, cam_height, (const char *)pixels, trackingData,format, VISAGE_FRAMEGRABBER_ORIGIN_TL, 0, -1, max_faces);
        endTrackTime = [self getCurrentTimeMs];
        elapsedTrackTime = endTrackTime - startTrackTime;
		
		if (pixelFormat == 1) {
			//Convert to RGBA for image to be drawn
			YUV_TO_RGBA(pixels, (unsigned char*)m_frame->imageData, cam_width, cam_height);
		}
		else {
			memcpy(m_frame->imageData, pixels, m_frame->imageSize);
		}
 
		m_frame->width = cam_width;
		m_frame->height = cam_height;
		
		[self displayTrackingResults:trackerStatus Frame:m_frame];

        int trackerCount = 0;
        
        for (int i = 0; i < max_faces;  i++)
        {
            if (trackerStatus[i] == TRACK_STAT_OFF)
                trackerCount++;
        }
        
        if (trackerCount == max_faces)
            break;
	}
	
    vsReleaseImage(&m_frame);

	[waitHandle lock];
	threadRunning = false;
	[waitHandle broadcast];
	[waitHandle unlock];
   
}

- (void)startTrackingFromCam
{
   
#if TARGET_IPHONE_SIMULATOR
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Error"
													message:@"No camera available on simulator."
												   delegate:nil
										  cancelButtonTitle:@"OK"
										  otherButtonTitles:nil];
	[alert show];
#else
	
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		
		[self stopTracker];
		while(inGetTrackingResults)
			;
		[waitHandle lock];
		isTracking = true;
		
		if (!threadRunning)
		{
			threadRunning = true;
			[NSThread detachNewThreadSelector:@selector(trackingCamThread:) toTarget:self withObject: self];
		}
		
		[waitHandle unlock];
   });
	
#endif
}

- (void) trackingVideoThread: (NSString *)filename
{
	double fps;
	bool video_file_sync = true;
	
	frameCount = 0;
	
	if (filename)
		 [self captureFromFile:filename];

	else
	{
		NSString *bundlefile = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"jam1.mp4"];
		
		 [self captureFromFile:bundlefile];
		
	}
	
	if (fileExists) {
		
		fps = _framerate;
		frameTime = 1000.0/fps;
		startTime = [self getCurrentTimeMs];
		
		m_frame = vsCreateImage(vsSize(_width, _height), VS_DEPTH_8U, 4);
		
		while(isTracking)
		{
			if (video_file_sync)
			{
				currentTime = [self getCurrentTimeMs];
				
				while((currentTime - startTime) > frameTime*(1+frameCount) )
				{
					bool ret = [videoGrabber isGrabbing] ? true : false;
					
					if (videoGrabber == NULL || !ret)
						break;
			
					  [videoGrabber getNextMovieFrame:YES];
						
					 frameCount++;
					 currentTime = [self getCurrentTimeMs];
				}
				
				while((currentTime - startTime) < frameTime*(frameCount-5))
				{
					usleep(1000);
					currentTime = [self getCurrentTimeMs];
					
				}
				
			}
			
			frameCount++;
						
			VsImage *tmp = [videoGrabber getNextMovieFrame:NO];
			unsigned char *pixels = nil;
			if (tmp) {
				pixels = (unsigned char *) tmp->imageData;
			} else {
				pixels = nil;
			}

            startTrackTime = [self getCurrentTimeMs];
			trackerStatus = tracker->track(_width, _height, (const char *)pixels, trackingData,VISAGE_FRAMEGRABBER_FMT_RGBA, VISAGE_FRAMEGRABBER_ORIGIN_TL, 0, -1, max_faces);
            endTrackTime = [self getCurrentTimeMs];
            elapsedTrackTime = endTrackTime - startTrackTime;
			
			if(pixels)
			memcpy(m_frame->imageData, (char*) pixels, m_frame->imageSize);
			
			m_frame->width = _width;
			m_frame->height = _height;
			
			[self displayTrackingResults:trackerStatus Frame:m_frame];
			
            int trackerCount = 0;
            
            for (int i = 0; i < max_faces;  i++)
            {
                if (trackerStatus[i] == TRACK_STAT_OFF)
                    trackerCount++;
            }
            
            if (trackerCount == max_faces)
                break;
		}
	}
	
    videoGrabber = 0;
    vsReleaseImage(&m_frame);
	
	[waitHandle lock];
	threadRunning = false;
	[waitHandle broadcast];
	[waitHandle unlock];
	
}

- (void)startTrackingFromVideo:(NSString *)filename
{
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		
		[self stopTracker];
		
		while(inGetTrackingResults)
			;
		
		[waitHandle lock];
		isTracking = true;
		
		if (!threadRunning)
		{
			threadRunning = true;
			[NSThread detachNewThreadSelector:@selector(trackingVideoThread:) toTarget:self withObject: filename];
		}
		
		[waitHandle unlock];
	});
}

-(void) captureFromFile:(NSString *)filename
{
	int _rotated = 0;
	
	fileExists = [[NSFileManager defaultManager] fileExistsAtPath:[NSString stringWithUTF8String:[filename UTF8String]]];
	if (!fileExists) {
		NSLog(@"File %s does not exist!", [filename UTF8String]);
		return;
	}
	
	path = [NSString stringWithUTF8String:[filename UTF8String]];
	
	// capture from video file
	videoGrabber = [[VideoGrabber alloc] init];
	
	// set output image size
	videoGrabber.outputWidth = 0;//_width;
	videoGrabber.outputHeight = 0;//_height;
	
	_framerate = 30;
	_rotated = [videoGrabber startGrabbing:path];
	
	_framerate = videoGrabber.framerate;
	if (_rotated == 0 || _rotated == 1) {
		_width = videoGrabber.width;
		_height = videoGrabber.height;
	} else {
		_width = videoGrabber.height;
		_height = videoGrabber.width;
	}
	
}

- (long) getCurrentTimeMs
{
	struct timeb timebuffer;
	ftime (&timebuffer);
	
	long clockTime = 1000 * (long)timebuffer.time + timebuffer.millitm;
	
	return clockTime;
	
}

- (void) trackingImageThread:(id)object
{
	demoFrameGrabber = new DemoFrameGrabber();
	unsigned char* pixels = demoFrameGrabber->GrabFrame(fg_pts);
	m_frame = vsCreateImage(vsSize(demoFrameGrabber->width, demoFrameGrabber->height), VS_DEPTH_8U, 4);

	while(isTracking)
	{
        startTrackTime = [self getCurrentTimeMs];
		trackerStatus = tracker->track(demoFrameGrabber->width, demoFrameGrabber->height, (const char*)pixels, trackingData, VISAGE_FRAMEGRABBER_FMT_RGBA, VISAGE_FRAMEGRABBER_ORIGIN_TL, 0, -1, max_faces);
        endTrackTime = [self getCurrentTimeMs];
        elapsedTrackTime = endTrackTime - startTrackTime;
		
		memcpy(m_frame->imageData, (char*) pixels, m_frame->imageSize);
		
		[self displayTrackingResults:trackerStatus Frame:m_frame];
		
		int trackerCount = 0;

		for (int i = 0; i < max_faces;  i++)
		{
			if (trackerStatus[i] == TRACK_STAT_OFF)
            trackerCount++;
		}

		if (trackerCount == max_faces)
			break;
	}
	
	delete demoFrameGrabber;
	demoFrameGrabber = 0;
    vsReleaseImage(&m_frame);
	
	[waitHandle lock];
	threadRunning = false;
	[waitHandle broadcast];
	[waitHandle unlock];
}

- (void)startTrackingFromImage
{
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		
		[self stopTracker];
		
		while(inGetTrackingResults)
			;
		
		[waitHandle lock];
		isTracking = true;
		
		if (!threadRunning)
		{
			threadRunning = true;
			[NSThread detachNewThreadSelector:@selector(trackingImageThread:) toTarget:self withObject: self];
		}
		
		[waitHandle unlock];
	});
}

- (void)stopTracker
{
	[waitHandle lock];
	
	isTracking = false;
	
	// Keep waiting until either the predicate is true or we timed out
	while (threadRunning && [waitHandle waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:60]]) {
	}
	
	[waitHandle unlock];
}

- (void)dummyThread:(id)object
{
	int n = 0;
	n++;
}

- (BOOL)startMultithread
{
	[NSThread detachNewThreadSelector:@selector(dummyThread:) toTarget:self withObject: nil];
	return [NSThread isMultiThreaded];
}

#include <mach/mach_time.h>

#define MEASURE_FRAMES 10
uint64_t last_times[MEASURE_FRAMES];
int framecount = -1;
int last_pts = 0;


- (void)displayTrackingResults:(int*)trackerStatus Frame:(VsImage*)frame
{
	inGetTrackingResults = true;
	
	int pts = (int)trackingData[0].timeStamp;
	
	if (last_pts == pts) {
		inGetTrackingResults = false;
		return;
	}

	last_pts = pts;
	
	mach_timebase_info_data_t timeBaseInfo;
	mach_timebase_info(&timeBaseInfo);

	//measure the frame rate
	uint64_t currentTime = mach_absolute_time() * timeBaseInfo.numer / (timeBaseInfo.denom * 1e6);
	if(framecount == -1)
	{
		framecount = 0;
		for(int i=0;i<10;i++)
			last_times[i]=0;
	}
	framecount++;
	if(framecount == MEASURE_FRAMES) framecount = 0;
	last_times[framecount] = currentTime;

    //drawing results
    [glView setOpenGLContext];
		
    float videoAspect = frame->width / (float)frame->height;
	
    //
    int winWidth = glWidth;
    int winHeight = glWidth / videoAspect;
    
    //draw frame and tracking results
    VisageRendering::DisplayResults(&trackingData[0], trackerStatus[0], winWidth, winHeight, frame);
        
    for (int i = 1; i < max_faces; i++)
        VisageRendering::DisplayResults(&trackingData[i], trackerStatus[i], winWidth, winHeight, frame, DISPLAY_DEFAULT - DISPLAY_FRAME);
	
    //set logo viewport dimensions
    logoViewportWidth = winWidth;
    logoViewportHeight = winHeight;
    
    //draw logo
    if(logo != NULL)
        VisageRendering::DisplayLogo(logo, logoViewportWidth, logoViewportHeight);
   
    [glView swapOpenGLBuffers];
	
	const char *trackingStatusString;
	switch (trackerStatus [0]) {
		case TRACK_STAT_OFF:
			trackingStatusString = "OFF";
			break;
		case TRACK_STAT_OK:
			trackingStatusString = "OK";
			break;
		case TRACK_STAT_RECOVERING:
			trackingStatusString = "RECOVERING";
			break;
		case TRACK_STAT_INIT:
			trackingStatusString = "INITIALIZING";
			break;
		default:
			trackingStatusString = "N/A";
			break;
	}
	
	// display the frame rate, position and other info
	
	float r[3] = {0};
	float t[3] = {0};
	if (trackerStatus[0] == TRACK_STAT_OK)
	{
		for(int i=0;i<3;i++) {
			r[i] = trackingData[0].faceRotation[i] * 180.0f / 3.14159f; //rads to degs
			t[i] = trackingData[0].faceTranslation[i] * 100.0f; //translation is expressed in meters so this gives approximate values in centimeters if camera focus distance parameter is set correctly in configuration file
		}
	}
	
	NSString* fps = [NSString stringWithFormat:@"%4.1f FPS (track %ld ms) \n", trackingData[0].frameRate, elapsedTrackTime];
	NSString* info = [NSString stringWithFormat:@"Head position %+5.1f %+5.1f %+5.1f | Rotation (deg) %+5.1f %+5.1f %+5.1f",t[0],t[1],t[2],r[0],r[1],r[2]];
	NSString* status = [NSString stringWithFormat:@"Status: %s", trackingStatusString];
 
	[self->m_informer showTrackingFps:fps Info:info andStatus:status];
	
	
	inGetTrackingResults = false;
}


void YUV_TO_RGBA(unsigned char* yuv, unsigned char* buff, int width, int height)
{
	const int frameSize = width * height;
	
	const int ii = 0;
	const int ij = 0;
	const int di = +1;
	const int dj = +1;
	
	unsigned char* rgba = buff;
	
	for (int i = 0, ci = ii; i < height; ++i, ci += di)
	{
		for (int j = 0, cj = ij; j < width; ++j, cj += dj)
		{
			int y = (0xff & ((int) yuv[ci * width + cj]));
			int v = (0xff & ((int) yuv[frameSize + (ci >> 1) * width + (cj & ~1) + 0]));
			int u = (0xff & ((int) yuv[frameSize + (ci >> 1) * width + (cj & ~1) + 1]));
			y = y < 16 ? 16 : y;
			
			int a0 = 1192 * (y -  16);
			int a1 = 1634 * (v - 128);
			int a2 =  832 * (v - 128);
			int a3 =  400 * (u - 128);
			int a4 = 2066 * (u - 128);
			
			int r = (a0 + a1) >> 10;
			int g = (a0 - a2 - a3) >> 10;
			int b = (a0 + a4) >> 10;
			
			*rgba++ = clamp(r);
			*rgba++ = clamp(g);
			*rgba++ = clamp(b);
			*rgba++ = 255;
		}
	}
}


void getOrientation()
{
	UIInterfaceOrientation orientation = [UIApplication sharedApplication].statusBarOrientation;

	if (orientation == UIInterfaceOrientationPortrait)
	_rotated = 0;
	else if (orientation == UIInterfaceOrientationLandscapeLeft)
	_rotated = 1;
	else if (orientation == UIInterfaceOrientationLandscapeRight)
	_rotated = 3;
	else
	_rotated = 0;

}


void setDimensions(int orientation)
{
	NSString* deviceType = [UIDeviceHardware platform];
	
	if (orientation == 0 || orientation == 2)
	{
		// portrait mode
		cam_width = 480;
		cam_height = 640;
		preset = AVCaptureSessionPreset640x480;
	}
	
	else
	{
		// landscape mode
		cam_width = 640;
		cam_height = 480;
		preset = AVCaptureSessionPreset640x480;
	}
	
	// override for iPhone 4
	if ([deviceType hasPrefix:@"iPhone3"]) {	// iPhone4
		if (orientation == 0 || orientation == 2)
		{
			// portrait mode
			cam_width = 144;
			cam_height = 192;
			preset = AVCaptureSessionPresetLow;
		}
		
		else
		{
			// landscape mode
			cam_width = 192;
			cam_height = 144;
			preset = AVCaptureSessionPresetLow;
		}
		
	}
	
}


@end
