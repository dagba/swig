//
//  EWFileLogger.h
//  Swig
//
//  Created by EastWind on 13.02.2018.
//

#warning велосипед

#import <Foundation/Foundation.h>

#define NSLog(args...) _Log(@"DEBUG ", __FILE__,__LINE__,__PRETTY_FUNCTION__,args);

static BOOL EW_LOGGING_TO_FILE = NO;

static unsigned long long EW_LOG_FILE_SIZE = 1024*1024*100;

static NSString *EW_LOG_FILE_NAME;
static NSString *EW_LOG_FILE_NAME_OLD;

@interface EWFileLogger : NSObject
void _Log(NSString *prefix, const char *file, int lineNumber, const char *funcName, NSString *format,...);

@end

