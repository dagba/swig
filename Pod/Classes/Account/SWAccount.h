//
//  SWAccount.h
//  swig
//
//  Created by Pierre-Marc Airoldi on 2014-08-21.
//  Copyright (c) 2014 PeteAppDesigns. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SWAccountProtocol.h"

//TODO: remove account from accounts when disconnected

@class SWAccountConfiguration, SWCall;

typedef NS_ENUM(NSInteger, SWAccountState) {
    SWAccountStateDisconnected,
    SWAccountStateConnecting,
    SWAccountStateConnected,
    SWAccountStateOffline
};

typedef NS_ENUM(NSInteger, SWPresenseState) {
    SWPresenseStateOffline,
    SWPresenseStateOnline
};

typedef NS_ENUM(NSInteger, SWFileType) {
    SWFileTypeNo,
    SWFileTypeBin,
    SWFileTypePicture,
    SWFileTypeAudio,
    SWFileTypeVideo
};

@interface SWAccount : NSObject <SWAccountProtocol>

@property (nonatomic, readonly) NSInteger accountId;
@property (nonatomic, readonly) SWAccountState accountState;
@property (nonatomic, readonly, strong) SWAccountConfiguration *accountConfiguration;
@property (nonatomic, readonly , assign, getter=isValid) BOOL valid;

-(void)configure:(SWAccountConfiguration *)configuration completionHandler:(void(^)(NSError *error))handler; //configure and add account
-(void)connect:(void(^)(NSError *error))handler;
-(void)disconnect:(void(^)(NSError *error))handler;

-(void)addCall:(SWCall *)call;
-(void)removeCall:(NSUInteger)callId;
-(SWCall *)lookupCall:(NSInteger)callId;
-(SWCall *)firstCall;

-(void)endAllCalls;

-(void)makeCall:(NSString *)URI completionHandler:(void(^)(NSError *error))handler;
//-(void)answerCall:(NSUInteger)callId completionHandler:(void(^)(NSError *error))handler;
//-(void)endCall:(NSInteger)callId completionHandler:(void(^)(NSError *error))handler;

-(void)sendMessage:(NSString *)message to:(NSString *)URI completionHandler:(void(^)(NSError *error, NSString *callID))handler;
-(void)sendMessage:(NSString *)message fileType:(SWFileType) fileType fileHash:(NSString *) fileHash to:(NSString *)URI completionHandler:(void(^)(NSError *error, NSString *callID))handler;
-(void)sendMessageReadNotifyTo:(NSString *)URI smid:(NSUInteger)smid completionHandler:(void(^)(NSError *error))handler;

-(void)setPresenseStatusOnline:(SWPresenseState) state completionHandler:(void(^)(NSError *error))handler;
-(void)subscribeBuddyURI:(NSString *) URI completionHandler:(void(^)(NSError *error))handler;

@end
