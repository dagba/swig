//
//  SWSipMessage.h
//  Swig
//
//  Created by EastWind on 25.02.2018.
//

#import <Foundation/Foundation.h>
#import "SWAccount.h"

@interface SWSipMessage : NSObject

@property (strong, nonatomic, nullable) NSString *message;
@property (assign, nonatomic) SWFileType fileType;
@property (strong, nonatomic, nullable) NSString *fileHash;
@property (strong, nonatomic, nullable) NSString *URI;
@property (assign, nonatomic, nullable) BOOL *isGroup;
@property (assign, nonatomic, nullable) BOOL *forceOffline;
@property (assign, nonatomic, nullable) BOOL *isGSM;
@property (nonatomic, copy, nullable) void (^completionHandler)(NSError *error, NSString *SMID, NSString *fileServer, NSDate *date);

@end
