//
//  EWFileLogger.m
//  Swig
//
//  Created by EastWind on 13.02.2018.
//

#import "EWFileLogger.h"

#import "SWAccount.h"

@implementation EWFileLogger

void _Log(NSString *prefix, const char *file, int lineNumber, const char *funcName, NSString *format,...) {
    va_list ap;
    va_start (ap, format);
    format = [format stringByAppendingString:@"\n"];
    NSString *msg = [[NSString alloc] initWithFormat:[NSString stringWithFormat:@"%@",format] arguments:ap];
    va_end (ap);
    fprintf(stderr,"%s%50s:%3d - %s",[prefix UTF8String], funcName, lineNumber, [msg UTF8String]);
    
    if(EW_LOGGING_TO_FILE) {
        [EWFileLogger append: msg];
    }
}

+(void) append: (NSString *) msg{
    
    if (!EW_LOG_FILE_NAME) {
        EW_LOG_FILE_NAME = [EWFileLogger generateFilename];
    }
    
    // get path to Documents/somefile.txt
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSString *path = [documentsDirectory stringByAppendingPathComponent:EW_LOG_FILE_NAME];
    // create if needed
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]){
        [self createFileAt:path];
    }
    else {
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL];
        unsigned long long fileSize = [attributes fileSize];
        
        //Если новый файл разросся больше предельного размера, удаляем старый файл, а новый делаем старым
        if (fileSize > EW_LOG_FILE_SIZE) {
            [self deleteFileAt:[documentsDirectory stringByAppendingPathComponent:EW_LOG_FILE_NAME_OLD]];
            
            EW_LOG_FILE_NAME_OLD = EW_LOG_FILE_NAME;
            EW_LOG_FILE_NAME = [EWFileLogger generateFilename];
            path = [documentsDirectory stringByAppendingPathComponent:EW_LOG_FILE_NAME];
            [self createFileAt:path];
        }
    }
    
    // append
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    [handle truncateFileAtOffset:[handle seekToEndOfFile]];
    [handle writeData:[msg dataUsingEncoding:NSUTF8StringEncoding]];
    [handle closeFile];
}

+ (void) createFileAt: (NSString *) path {
    fprintf(stderr,"Creating file at %s",[path UTF8String]);
    [[NSData data] writeToFile:path atomically:YES];
}

+ (void) deleteFileAt: (NSString *) path {
    fprintf(stderr,"Deleting file at %s",[path UTF8String]);
    NSError *error;
    if ([[NSFileManager defaultManager] isDeletableFileAtPath:path]) {
        BOOL success = [[NSFileManager defaultManager] removeItemAtPath:path error:&error];
        if (!success) {
            NSLog(@"Error removing file at path: %@", error.localizedDescription);
        }
    }
}

+ (NSString *) generateFilename {
    return [NSString stringWithFormat:@"logfile%s.txt", [[NSProcessInfo processInfo] globallyUniqueString]];
}

@end
