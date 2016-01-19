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

typedef NS_ENUM(NSInteger, SWPresenseAction) {
    SWPresenseActionSubscribe,
    SWPresenseActionUnsubscribe
};


typedef NS_ENUM(NSInteger, SWFileType) {
    SWFileTypeNo,
    SWFileTypeBin,
    SWFileTypePicture,
    SWFileTypeAudio,
    SWFileTypeVideo,
    SWFileTypeLocation
};

typedef NS_ENUM(NSInteger, SWGroupAction) {
    SWGroupActionAdd,
    SWGroupActionDelete
};

@interface SWAccount : NSObject <SWAccountProtocol>

@property (nonatomic, readonly) NSInteger accountId;
@property (nonatomic, readonly) SWAccountState accountState;
@property (nonatomic, readonly, strong) SWAccountConfiguration *accountConfiguration;
@property (nonatomic, readonly , assign, getter=isValid) BOOL valid;

-(void)configure:(SWAccountConfiguration *)configuration completionHandler:(void(^)(NSError *error))handler; //configure and add account
-(void)setCode: (NSString *)code completionHandler:(void(^)(NSError *error))handler;
-(void)setPhone: (NSString *)phone completionHandler:(void(^)(NSError *error))handler;
-(void)connect:(void(^)(NSError *error))handler;
-(void)disconnect:(void(^)(NSError *error))handler;

-(void)addCall:(SWCall *)call;
-(void)removeCall:(NSUInteger)callId;
-(SWCall *)lookupCall:(NSInteger)callId;
-(SWCall *)firstCall;

-(void)endAllCalls;

-(void)makeCallToGSM:(NSString *)URI completionHandler:(void(^)(NSError *error))handler;
-(void)makeCall:(NSString *)URI completionHandler:(void(^)(NSError *error))handler;
-(void)makeCall:(NSString *)URI toGSM:(BOOL) isGSM completionHandler:(void(^)(NSError *error))handler;



//-(void)answerCall:(NSUInteger)callId completionHandler:(void(^)(NSError *error))handler;
//-(void)endCall:(NSInteger)callId completionHandler:(void(^)(NSError *error))handler;

-(void)sendMessage:(NSString *)message to:(NSString *)URI completionHandler:(void(^)(NSError *error, NSString *SMID, NSString *fileServer, NSDate *date))handler;
-(void)sendGroupMessage:(NSString *)message to:(NSString *)URI completionHandler:(void(^)(NSError *error, NSString *SMID, NSString *fileServer, NSDate *date))handler;

-(void)sendMessage:(NSString *)message fileType:(SWFileType) fileType fileHash:(NSString *) fileHash to:(NSString *)URI isGroup:(BOOL) isGroup completionHandler:(void(^)(NSError *error, NSString *SMID, NSString *fileServer, NSDate *date))handler;
-(void)sendMessageReadNotifyTo:(NSString *)URI smid:(NSUInteger)smid completionHandler:(void(^)(NSError *error))handler;

//-(void)setPresenseStatusOnline:(SWPresenseState) state completionHandler:(void(^)(NSError *error))handler;
-(void)monitorPresenceStatusURI:(NSString *) URI action:(SWPresenseAction) action completionHandler:(void(^)(NSError *error))handler;

-(void)updateBalanceCompletionHandler:(void(^)(NSError *error, NSNumber *balance))handler;

-(void)createGroup:(NSArray *) abonents name:(NSString *) name completionHandler:(void(^)(NSError *error, NSString *groupID))handler;
-(void)groupInfo:(NSString *) groupID completionHandler:(void(^)(NSError *error, NSString *name, NSArray *abonents))handler;

-(void)groupAddAbonents:(NSArray *)abonents groupID: (NSString *) groupID completionHandler:(void(^)(NSError *error))handler;
-(void)groupRemoveAbonents:(NSArray *)abonents groupID: (NSString *) groupID completionHandler:(void(^)(NSError *error))handler;
-(void)modifyGroup:(NSString *) groupID action:(SWGroupAction) groupAction abonents:(NSArray *)abonents completionHandler:(void(^)(NSError *error))handler;

@end
