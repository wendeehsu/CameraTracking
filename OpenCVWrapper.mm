//  OpenCVWrapper.mm
//  CameraProcessing

#import <opencv2/opencv.hpp>
#import <opencv2/imgcodecs/ios.h>
#import "OpenCVWrapper.h"

@implementation OpenCVWrapper

+(UIImage *) MakeGrayof: (UIImage *) image
{
    // Transform UIImage to cv::Mat.
    cv::Mat imageMat;
    UIImageToMat(image, imageMat);
    
    // If image is already grayscale.
    if(imageMat.channels() == 1)
    {
        return image;
    }
    
    // Transform the color to gray.
    cv::Mat grayMat;
    cvtColor(imageMat, grayMat, cv::COLOR_BGR2GRAY);
    
    return MatToUIImage(grayMat);
}

@end
