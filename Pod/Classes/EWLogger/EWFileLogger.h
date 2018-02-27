//
//  EWFileLogger.h
//  Swig
//
//  Created by EastWind on 13.02.2018.
//

#warning велосипед
#warning вынести в отдельный под

#import <Foundation/Foundation.h>

#define NSLog(args...) _Log(@"DEBUG ", __FILE__,__LINE__,__PRETTY_FUNCTION__,args);

@interface EWFileLogger : NSObject

@property (class, nonatomic, assign) BOOL loggingToFile;

@property (class, nonatomic, assign) unsigned long long logFileSize;

@property (class, nonatomic, strong) NSString *logFileName;
@property (class, nonatomic, strong) NSString *logFileNameOld;

void _Log(NSString *prefix, const char *file, int lineNumber, const char *funcName, NSString *format,...);

@end

