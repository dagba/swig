//
//  SWMessageSenderProtocol.h
//  Swig
//
//  Created by EastWind on 10.05.2018.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, SWFileType) {
    SWFileTypeNo,
    SWFileTypeBin,
    SWFileTypePicture,
    SWFileTypeAudio,
    SWFileTypeVideo,
    SWFileTypeLocation,
    SWFileTypeContact,
    SWFileTypeSticker
};

@protocol SWMessageSenderProtocol <NSObject>

-(void)sendMessage:(NSString *)message fileType:(SWFileType) fileType fileHash:(NSString *) fileHash to:(NSString *)URI isGroup:(BOOL) isGroup forceOffline:(BOOL) forceOffline isGSM:(BOOL) isGSM completionHandler:(void(^)(NSError *error, NSString *SMID, NSString *fileServer, NSDate *date))handler;
-(void)sendMessage:(NSString *)message fileType:(SWFileType) fileType fileHash:(NSString *) fileHash to:(NSString *)URI isGroup:(BOOL) isGroup completionHandler:(void(^)(NSError *error, NSString *SMID, NSString *fileServer, NSDate *date))handler;

@end
