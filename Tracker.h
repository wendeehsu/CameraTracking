//#import <opencv2/opencv.hpp>
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface Tracker : NSObject

- (void) InitProperty;
- (void) InitTracker : (int) frameRate;
- (UIImage *) GetPupil: (Tracker*) irisTracker frame:(UIImage*)frame;
@end
NS_ASSUME_NONNULL_END
