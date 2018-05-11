//
//  SWIntentManager.h
//  Swig
//
//  Created by EastWind on 10.05.2018.
//

#import <Foundation/Foundation.h>

@protocol SWIntentProtocol;

@interface SWIntentManager : NSObject

- (void) addIntent: (id<SWIntentProtocol>) intent;

@end
