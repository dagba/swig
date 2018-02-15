//
//  EWFileLogger.h
//  Swig
//
//  Created by EastWind on 13.02.2018.
//

#import <Foundation/Foundation.h>

//#warning test logging to file
//#define EW_OVERRIDE_NSLOG

#ifdef EW_OVERRIDE_NSLOG
#define NSLog(args...) _Log(@"DEBUG ", __FILE__,__LINE__,__PRETTY_FUNCTION__,args);
#endif

@interface EWFileLogger : NSObject
void _Log(NSString *prefix, const char *file, int lineNumber, const char *funcName, NSString *format,...);

@end

