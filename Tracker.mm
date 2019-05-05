#import <opencv2/opencv.hpp>
#import <opencv2/core/types_c.h>
#import <opencv2/imgcodecs/ios.h>
#import "Tracker.h"
#import <Foundation/Foundation.h>
#import "CameraProcessing/visageSDK-iOS/include/visageVision.h"
#import <iostream>

namespace VisageSDK {
    void initializeLicenseManager(const char *licenseKeyFileName);
}

@implementation Tracker {
    // Define private properties.
    int resizeFactors[3];
    int resizef;
    bool isVertical;
    int trackerDelay;
    int blurCount;
    int blurKernelSize;
    int cannyp1;
    int cannyp2 ;
    int maskLine;
    int radt1Plus;
    int radt1Minus;
    int radChangeNoLessThan;
//    int borderFactorx;
//    int borderFactory;
    const cv::String* lensPath;
    float lensTransparentWeight;
    int wait;
    int _frameRate;
    VisageSDK::VisageTracker* tracker;
//    VisageSDK::VisageFaceAnalyser *analyser;
    VisageSDK::FaceData trackingData[3];
    const char* lefteye[8];
    const char* righteye[8];
    const char* leftPupil;
    const char* rightPupil;
    std::vector<cv::Point> lefteyeCV, righteyeCV;
    cv::Point leftPupilCV, rightPupilCV;
    int radius;
    cv::Mat _lens;
    bool isChanged;
};

int borderFactorx;
int borderFactory;

- (void) InitProperty {
    isVertical = true;
    trackerDelay = 15;
    blurCount = 4;
    blurKernelSize = 3;
    cannyp1 = 60;
    cannyp2 = 100;
    maskLine = 2;
    radt1Plus = 4;
    radt1Minus = 0;
    radChangeNoLessThan = 3;
    borderFactorx = 5;
    borderFactory = 4;
    lensTransparentWeight = 0.4;
    wait = 33 - trackerDelay;
    leftPupil = "3.5";
    rightPupil = "3.6";
    isChanged = false;

    int _resizeFactors[3] = {3,2,1};
    for(int i = 0; i < 3; i++){
        resizeFactors[i] = _resizeFactors[i];
    }

    const char* _lefteye[8] = { "3.1", "3.3", "3.7", "3.11", "12.5", "12.7", "12.9", "12.11" };
    const char* _righteye[8] = { "3.2", "3.4", "3.8", "3.12", "12.6", "12.8", "12.10", "12.12" };
    for(int i = 0; i < 8; i++){
        lefteye[i] = _lefteye[i];
        righteye[i] = _righteye[i];
    }

    VisageSDK::initializeLicenseManager("452-200-213-720-601-632-039-228-064-839-022.vlc");
}

- (void) InitTracker : (int) frameRate {
    // cv::waitKey(1000);
    
    // initialize Points for comparation
    for (int i = 0; i < 8; i++) {
        lefteyeCV.push_back(cv::Point(0, 0));
        righteyeCV.push_back(cv::Point(0, 0));
    }
    leftPupilCV = cv::Point(0, 0);
    rightPupilCV = cv::Point(0, 0);
    
    tracker = new VisageSDK::VisageTracker("Facial Features Tracker - High.cfg");
    //    analyser = new VisageSDK::VisageFaceAnalyser();
//    analyser->init("Resources/bdtsdata/LBF/vfadata");
    
    // initialize lensPath
    const cv::String t("lens.jpg");
    lensPath = &t;
    _lens = cv::imread(t);
    
    // framerate
    wait = frameRate - trackerDelay;
    if (wait <= 0) {
        wait = 1;
    }
}

+ (int*) vis2cv_AxisTransfer:(const float*) pos
                              width:(int)width
                              height:(int)height {
    //cout << pos[0] << " " << pos[1]<<endl;
    int x = pos[0] * width;
    int y = pos[1] * height;
    y = height - y;
    int ans[2] = { x, y };
    return ans;
}

// collect contour points inside the eyeMask (input *contours and output *insidePoints)
+ (void) pointsInside:(cv::Mat) eyeMask
                      contours:(std::vector<std::vector<cv::Point>>*) contours
                      insidePoints:(std::vector<cv::Point2d>*) insidePoints
                      defx:(int) defx
                      defy:(int) defy {
    for (int i = 0; i<contours->size(); i++)
    {
        for (int j = 0; j < contours->at(i).size(); j++) {
            cv::Point t = contours->at(i).at(j);
            if (eyeMask.at<uchar>(t.y, t.x) == 255) {
                insidePoints->push_back(t);
            }
        }
    }
}

+ (bool) isNearBorder:(cv::Point) point rect:(cv::Rect) rect {
    int xborder = rect.width / borderFactorx;  //12
    int yborder = rect.height / borderFactory;  //5

    return point.x - rect.x < xborder ||
            rect.x + rect.width - point.x < xborder ||
            point.y - rect.y < yborder ||
            rect.y + rect.height - point.y < yborder;
}

+ (float) pointsDistanceCV:(cv::Point2d) p1 p2:(cv::Point) p2 {
    return sqrt(pow((p1.x - p2.x), 2) + pow((p1.y - p2.y), 2));
}

+ (float) pointsDistance:(int*) cvCoor point:(cv::Point) point {
    return sqrt(pow((cvCoor[0] - point.x), 2) + pow((cvCoor[1] - point.y), 2));
}


- (int) Track:(cv::Mat) frame_
                mask:(cv::Mat*)mask
                pupil:(cv::Point*)pupil
                returnRadius:(int*) returnRadius
{
    cv::Mat frame = frame_.clone();
    if (isVertical)
        transpose(frame, frame);

    IplImage temp = (IplImage)frame;
    IplImage *ipl = &temp;

    int* stat;
    stat = tracker->track(ipl->width, ipl->height, ipl->imageData, trackingData, VISAGE_FRAMEGRABBER_FMT_BGR);
    
    usleep(20);
    cout << stat[0];
    //cv::waitKey(trackerDelay);        // tracker may be too slow to be real time
    if (stat[0] != TRACK_STAT_OK) {
        cout << "tracker err" << " " << stat[0] << endl;
        return 2;
    }
    cout<<"out!!";
    // get eye feature points and convert to openCV coordinate (upper-left is(0,0) )
    const float *pos;
    int* cvCoor;
    for (int i = 0; i < 8; i++) {
        // left eye
        pos = trackingData[0].featurePoints2D->getFPPos(lefteye[i]);
        cvCoor = [Tracker vis2cv_AxisTransfer:pos width:ipl->width height:ipl->height];
        if (lefteyeCV[i].x == 0 ||
            [Tracker pointsDistance:cvCoor point:lefteyeCV[i]] > 3) {
            lefteyeCV[i].x = cvCoor[0];
            lefteyeCV[i].y = cvCoor[1];
        }

        //right eye
        pos = trackingData[0].featurePoints2D->getFPPos(righteye[i]);
        cvCoor = [Tracker vis2cv_AxisTransfer:pos width:ipl->width height:ipl->height];
        if (righteyeCV[i].x == 0 ||
            [Tracker pointsDistance:cvCoor point:righteyeCV[i]] > 3) {
            righteyeCV[i].x = cvCoor[0];
            righteyeCV[i].y = cvCoor[1];
        }
    }
    //pupil
    pos = trackingData[0].featurePoints2D->getFPPos(leftPupil);
    cvCoor = [Tracker vis2cv_AxisTransfer:pos width:ipl->width height:ipl->height];
    if (leftPupilCV.x == 0 ||
        [Tracker pointsDistance:cvCoor point:leftPupilCV] > 0) {
        leftPupilCV = cv::Point(cvCoor[0], cvCoor[1]);
    }
    //cout << leftPupilCV.x << endl;

    pos = trackingData[0].featurePoints2D->getFPPos(rightPupil);
    cvCoor = [Tracker vis2cv_AxisTransfer:pos width:ipl->width height:ipl->height];
    if (rightPupilCV.x == 0 ||
        [Tracker pointsDistance:cvCoor point:rightPupilCV] > 0) {
        rightPupilCV = cv::Point(cvCoor[0], cvCoor[1]);
    }

    // get eyesquare roi
    cv::Rect leftRect = cv::boundingRect(lefteyeCV);
    cv::Rect rightRect = cv::boundingRect(righteyeCV);
    if (leftRect.width == 1 || rightRect.width == 1) {
        cout << "bounding box err";
        return 3;
    }
    cv::Mat leftRoi(frame, leftRect);
    cv::Mat rightRoi(frame, rightRect);

    // Blur and get canny
    for (int i = 0; i < blurCount; i++) {
        cv::GaussianBlur(leftRoi, leftRoi, cv::Size(blurKernelSize, blurKernelSize), 1);
        cv::GaussianBlur(rightRoi, rightRoi, cv::Size(blurKernelSize, blurKernelSize), 1);
    }

    cv::Mat leftCanny, rightCanny;
    cv::Canny(leftRoi, leftCanny, cannyp1, cannyp2);
    cv::Canny(rightRoi, rightCanny, cannyp1, cannyp2);

    // draw two eye contour mask(from boundoing box roi) seperately
    cv::Mat lefteyeMask(leftRect.height, leftRect.width, CV_8UC1, cv::Scalar(0)),
    righteyeMask(rightRect.height, rightRect.width, CV_8UC1, cv::Scalar(0));
    cv::Point cl_[8], cr_[8];
    int order[8] = { 3, 6, 0, 4, 2, 5, 1, 7 };  // counter Clockwise

    for (int i = 0; i < lefteyeCV.size(); i++) {
        cl_[i] = cv::Point(lefteyeCV[order[i]].x - leftRect.x, lefteyeCV[order[i]].y - leftRect.y);
        cr_[i] = cv::Point(righteyeCV[order[i]].x - rightRect.x, righteyeCV[order[i]].y - rightRect.y);
    }
    cv::fillConvexPoly(lefteyeMask, cl_, 8, cv::Scalar(255, 255, 255));
    cv::fillConvexPoly(righteyeMask, cr_, 8, cv::Scalar(255, 255, 255));
    cv::Mat lefteyeMaskForInside = lefteyeMask.clone(), righteyeMaskForInside = righteyeMask.clone();

    // shrink the mask for function "pointsInside()"
    for (int i = 0; i < 8; i++) {
        if (i == 7) {
            cv::line(lefteyeMaskForInside, cl_[i], cl_[0], cv::Scalar(0), maskLine);
            cv::line(righteyeMaskForInside, cr_[i], cr_[0], cv::Scalar(0), maskLine);
        }
        else {
            cv::line(lefteyeMaskForInside, cl_[i], cl_[i + 1], cv::Scalar(0), maskLine);
            cv::line(righteyeMaskForInside, cr_[i], cr_[i + 1], cv::Scalar(0), maskLine);
        }
    }


    // get contours inside eye
    std::vector< std::vector<cv::Point>> leftContours, rightContours;

    cv::findContours(leftCanny, leftContours, cv::RETR_LIST, cv::CHAIN_APPROX_NONE);
    cv::findContours(rightCanny, rightContours, cv::RETR_LIST, cv::CHAIN_APPROX_NONE);
    std::vector<cv::Point2d> leftInside, rightInside;

    [Tracker pointsInside:lefteyeMaskForInside contours:&leftContours insidePoints:&leftInside defx:leftRect.x defy:leftRect.y];
    [Tracker pointsInside:righteyeMaskForInside contours:&rightContours insidePoints:&rightInside defx:rightRect.x defy:rightRect.y];

    // calculate Iris radius
    if (trackingData[0].eyeClosure[0] && trackingData[0].eyeClosure[1]) {
        // if eye-closure detected, then continue for next frame
        bool isBorder = false;
        // isNearBorder(rightPupilCV, rightRect)
        if (![Tracker isNearBorder:leftPupilCV rect:leftRect] &&
            ![Tracker isNearBorder:rightPupilCV rect:rightRect]) {

            int radius_t1 = 0, radius_t2 = 0;
            // first calculate
            for (int i = 0; i < leftInside.size(); i++) {
                radius_t1 += sqrt(pow((leftInside.at(i).x + leftRect.x - leftPupilCV.x), 2) +
                                  pow((leftInside.at(i).y + leftRect.y - leftPupilCV.y), 2));
            }
            for (int i = 0; i < rightInside.size(); i++) {
                radius_t1 += sqrt(pow((rightInside.at(i).x + rightRect.x - rightPupilCV.x), 2) +
                                  pow((rightInside.at(i).y + rightRect.y - rightPupilCV.y), 2));
            }
            if (rightInside.size() + leftInside.size() != 0)
                radius_t1 /= rightInside.size() + leftInside.size();

            // delete unqulified points
            int count = 0;
            for (int i = 0; i < leftInside.size(); i++) {
                float dis = sqrt(pow((leftInside.at(i).x + leftRect.x - leftPupilCV.x), 2) +
                                 pow((leftInside.at(i).y + leftRect.y - leftPupilCV.y), 2));
                if (dis < radius_t1 + radt1Plus && dis > radius_t1 - radt1Minus) {
                    count++;
                    radius_t2 += dis;
                }
            }
            for (int i = 0; i < rightInside.size(); i++) {
                float dis = sqrt(pow((rightInside.at(i).x + rightRect.x - rightPupilCV.x), 2) +
                                 pow((rightInside.at(i).y + rightRect.y - rightPupilCV.y), 2));
                if (dis < radius_t1 + radt1Plus && dis > radius_t1 - radt1Minus) {
                    count++;
                    radius_t2 += dis;
                }
            }

            if (count != 0)
                radius_t2 /= count;
            if (abs((radius_t2 - radius)) > radChangeNoLessThan) {
                radius = radius_t2;
            }
        }
        else {
            isBorder = true;
            radius *= 0.8;
        }
        if (radius < 1)
            radius = 1;

        // load lens pic and resize, set seperate lens roi(square) on face
        cv::Mat lens;
        if (isChanged) {
            _lens = cv::imread(*lensPath);
        }
        try {
            cv::resize(_lens, lens, cv::Size((int)radius * 2, (int)radius * 2));
        }
        catch (exception err) {
            cout << "lens resize err" << endl;
            return 4;
        }
        cv::Rect leftIrisRect(leftPupilCV.x - radius, leftPupilCV.y - radius, 2 * radius, 2 * radius),
        rightIrisRect(rightPupilCV.x - radius, rightPupilCV.y - radius, 2 * radius, 2 * radius);
        cv::Mat leftIrisRoi(frame, leftIrisRect), rightIrisRoi(frame, rightIrisRect);

        // make border on mask for the later roi cutting. The Rect x y need to add the border
        int margin = radius + 10;
        cv::copyMakeBorder(lefteyeMask, lefteyeMask, margin, margin, margin, margin, cv::BORDER_CONSTANT, cv::Scalar(0, 0, 0));
        cv::copyMakeBorder(righteyeMask, righteyeMask, margin, margin, margin, margin, cv::BORDER_CONSTANT, cv::Scalar(0, 0, 0));
        
        cv::Rect leftIrisMaskRect(leftIrisRect.x - leftRect.x + margin, leftIrisRect.y - leftRect.y + margin, leftIrisRect.width, leftIrisRect.height),
        rightIrisMaskRect(rightIrisRect.x - rightRect.x + margin, rightIrisRect.y - rightRect.y + margin, rightIrisRect.width, rightIrisRect.height);
        try {
            // set lens roi(square) on mask
            cv::Mat leftmaskRoi(lefteyeMask, leftIrisMaskRect), rightmaskRoi(righteyeMask, rightIrisMaskRect);

            // turn mask to black on mask roi if lens[i,j] is white(average > 250)
            cv::Mat lensGray;
            cv::cvtColor(lens, lensGray, cv::COLOR_BGR2GRAY);
            for (int i = 0; i < lens.rows; i++) {
                for (int j = 0; j < lens.cols; j++) {
                    if (lensGray.at<uchar>(i, j) >= 235)
                    {
                        leftmaskRoi.at<uchar>(i, j) = 0;
                        rightmaskRoi.at<uchar>(i, j) = 0;
                    }
                }
            }

            cv::Mat leftMask = leftmaskRoi.clone(), rightMask = rightmaskRoi.clone();

            // add lens pic on face lensRoi with mask and transparency
            cv::Mat buffer = leftIrisRoi.clone();
            cv::add(lens, leftIrisRoi, buffer, leftMask);
            cv::addWeighted(leftIrisRoi, 1 - lensTransparentWeight, buffer, lensTransparentWeight, 0, leftIrisRoi);

            buffer = rightIrisRoi.clone();
            cv::add(lens, rightIrisRoi, buffer, rightMask);
            cv::addWeighted(rightIrisRoi, 1 - lensTransparentWeight, buffer, lensTransparentWeight, 0, rightIrisRoi);

            cv::Mat lShow(frame, leftRect), rShow(frame, rightRect);
//            cv::imshow("ll", lShow);
//            cv::imshow("rr", rShow);

            if (isBorder) {
                radius /= 0.8;
            }

            if ( !leftMask.empty()  && !rightMask.empty() ) {
                cout << leftMask.cols << " " << rightMask.cols << endl;
                *returnRadius = radius;
                mask[0] = leftMask.clone();
                mask[1] = rightMask.clone();
                pupil[0] = leftPupilCV;
                pupil[1] = rightPupilCV;
            }
            else {
                throw;
            }
        }
        catch (exception err) {
            cout << "lensGrayMask or add err" << endl;
            return 5;
        }
    }
    else {
        return 1;
    }
    return 0;
}

- (UIImage *) GetPupil: (Tracker*) irisTracker
                        frame:(UIImage*)frame{
    cv::Mat frameMat;
    UIImageToMat(frame, frameMat);
    // cv::resize(frameMat, frameMat, cv::Size(480,640));
    while (true) {
        cv::Mat mask[2];
        cv::Point pupil[2];
        int radius = 0;
        int stat = [irisTracker Track:frameMat mask:mask pupil:pupil returnRadius:&radius];
        if (stat == 0) {
            cout << "get image from tracker!!!!" << endl;
            return MatToUIImage(frameMat);
        }
    }
    return nil;
}

@end
