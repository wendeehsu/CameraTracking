//
//  IrisTracker.hpp
//  CameraProcessing
//
//  Created by dentall01 on 2019/4/16.
//  Copyright © 2019 dentallio. All rights reserved.
//

#ifndef IrisTracker_hpp
#define IrisTracker_hpp

#include <opencv2/opencv.hpp>
#include <stdio.h>
#include "CameraProcessing/visageSDK-iOS/include/visageVision.h"

class IrisTracker
{
private:
    int resizeFactors[3] = { 3,2,1 };
    int resizef;
    bool isVertical = true; // if get track err 3 all the time, try to change this value
    int trackerDelay = 15;
    // Gaussian blur
    int blurCount = 4;
    int blurKernelSize = 3;
    //Canny
    int cannyp1 = 60;
    int cannyp2 = 100;
    //MaskForInside_preprocess line type
    int maskLine = 2;
    //Iris radius_second calculation bounding, all positive number
    int radt1Plus = 4;
    int radt1Minus = 0;
    int radChangeNoLessThan = 3;
    int borderFactorx = 5;
    int borderFactory = 4;
    //lens
    const cv::String* lensPath;
    float lensTransparentWeight = 0.4;
    // frame rate
    int wait = 33 - trackerDelay;
    
    int frameRate;  // must > 20;
    VisageSDK::VisageTracker* tracker;
    VisageSDK::VisageFaceAnalyser *analyser;
    VisageSDK::FaceData trackingData[3];
    const char* lefteye[8] = { "3.1", "3.3", "3.7", "3.11", "12.5", "12.7", "12.9", "12.11" };  //8 points
    const char* righteye[8] = { "3.2", "3.4", "3.8", "3.12", "12.6", "12.8", "12.10", "12.12" };
    const char* leftPupil = "3.5";
    const char* rightPupil = "3.6";
    std::vector<cv::Point> lefteyeCV, righteyeCV;
    cv::Point leftPupilCV, rightPupilCV;
    int radius;
    cv::Mat _lens;
    bool isChanged = false;
    
public:
    // set path:
    //"Facial Features Tracker - High.cfg",  "lens-1.jpg" , and  "Samples\data\bdtsdata\LBF\vfadata" folder
    // framerate must > 20
    void initialize(const char* highCfg, const char* lensPath, const char* vfadata, int framerate);
    
    // frame_ : the current frame, mask and pupil is the output Iris mask and pupil, [0] is left and [1] is right,
    // radius : the Iris radius. The origin of pupil is set to the upper-left corner of the frame
    // return :
    // 0 : tracking success
    // 1 : eye closure is detect(having no pupil and mask)
    // 2 3 4 5 : if error
    int irisTrack(cv::Mat frame_, cv::Mat mask[2], cv::Point pupil[2], int* radius);
    
    // get the properties of the face detected
    int getAge(cv::Mat frame);
    float* getEmotion(cv::Mat frame);  // float[7] : anger, disgust, fear, happiness, sadness, surprise and neutral
    int getGender(cv::Mat frame);
    
private:
    int* vis2cv_AxisTransfer(const float* pos, int width, int height);
    void pointsInside(cv::Mat eyeMask, std::vector< std::vector<cv::Point>>* contours, std::vector<cv::Point2d>* insidePoints, int defx, int defy);
    bool isNearBorder(cv::Point point, cv::Rect rect);
    float pointsDistance(int* cvCoor, cv::Point point);
    float pointsDistance(cv::Point2d p1, cv::Point p2);
    
public:
    IrisTracker();
    ~IrisTracker();
};

#endif /* IrisTracker_hpp */
