//
//  SWThreadFactory.h
//  Swig
//
//  Created by EastWind on 25.02.2018.
//

#import <Foundation/Foundation.h>

@interface SWThreadManager : NSObject

- (NSThread *) getMessageThread;
- (NSThread *) getCallManagementThread;

- (void) runBlock: (void (^)(void)) block onThread: (NSThread *) thread wait: (BOOL) wait;

@end
