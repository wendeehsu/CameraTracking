//
//  IrisTracker.m
//  CameraProcessing
//
//  Created by dentall01 on 2019/4/14.
//  Copyright © 2019 dentallio. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CameraProcessing/visageSDK-iOS/include/visageVision.h"
#import "Tracker.h"
#import <iostream>
#include "IrisTracker.hpp"

namespace VisageSDK {
    void initializeLicenseManager(const char *licenseKeyFileName);
}

@implementation Tracker

+(void) SetUpLicense {
    VisageSDK::initializeLicenseManager("452-200-213-720-601-632-039-228-064-839-022.vlc");
}

//- (void)hello_cpp_wrapped {
//    IrisTracker iris;
//    iris.hello_cpp();
//}

@end
