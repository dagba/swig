//
//  SWThreadFactory.h
//  Swig
//
//  Created by EastWind on 25.02.2018.
//

#import <Foundation/Foundation.h>

@interface SWThreadManager : NSObject

+ (instancetype) sharedInstance;

- (NSThread *) getMessageThread;
- (NSThread *) getCallManagementThread;
- (NSThread *) getRegistrationThread;

- (void) runBlock: (void (^)(void)) block onThread: (NSThread *) thread wait: (BOOL) wait;

@end
