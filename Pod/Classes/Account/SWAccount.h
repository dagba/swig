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
    SWFileTypeLocation,
    SWFileTypeContact
};

typedef NS_ENUM(NSInteger, SWGroupAction) {
    SWGroupActionAdd,
    SWGroupActionDelete
};

typedef NS_ENUM(NSInteger, SWCallRoute) {
    SWCallRouteGSM = 0,
    SWCallRouteSIP = 1
};

typedef NS_ENUM(NSInteger, SWMessageDirection) {
    SWMessageDirectionOutgoing = 0,
    SWMessageDirectionIncoming = 1
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

- (void) accountStateConnecting;

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
-(void)sendMessage:(NSString *)message fileType:(SWFileType) fileType fileHash:(NSString *) fileHash to:(NSString *)URI isGroup:(BOOL) isGroup forceOffline:(BOOL) forceOffline isGSM:(BOOL) isGSM completionHandler:(void(^)(NSError *error, NSString *SMID, NSString *fileServer, NSDate *date))handler;
-(void)sendMessageReadNotifyTo:(NSString *)URI smid:(NSUInteger)smid groupID:(NSInteger) groupID completionHandler:(void(^)(NSError *error))handler;

-(void)deleteMessage:(NSInteger) smid direction:(SWMessageDirection) direction fileFlag:(BOOL) fileFlag chatID: (NSInteger) chatID completionHandler:(void(^)(NSError *error))handler;

-(void)deleteChat:(NSString *) partner withSMID:(NSInteger) smid groupId:(NSInteger) groupId completionHandler:(void(^)(NSError *error))handler;

//-(void)setPresenseStatusOnline:(SWPresenseState) state completionHandler:(void(^)(NSError *error))handler;
-(void)monitorPresenceStatusURI:(NSString *) URI action:(SWPresenseAction) action completionHandler:(void(^)(NSError *error))handler;

-(void)updateBalanceCompletionHandler:(void(^)(NSError *error, NSNumber *balance))handler;

-(void)createGroup:(NSArray *) abonents name:(NSString *) name completionHandler:(void(^)(NSError *error, NSInteger groupID))handler;
-(void)groupInfo:(NSInteger) groupID completionHandler:(void(^)(NSError *error, NSString *name, NSArray *abonents, NSString *avatarPath))handler;

-(void)groupAddAbonents:(NSArray *)abonents groupID: (NSInteger) groupID completionHandler:(void(^)(NSError *error))handler;
-(void)groupRemoveAbonents:(NSArray *)abonents groupID: (NSInteger) groupID completionHandler:(void(^)(NSError *error))handler;
-(void)modifyGroup:(NSInteger) groupID action:(SWGroupAction) groupAction abonents:(NSArray *)abonents completionHandler:(void(^)(NSError *error))handler;
-(void)modifyGroup:(NSInteger) groupID avatarPath:(NSString *) avatarPath completionHandler:(void(^)(NSError *error))handler;

- (void) logoutCompletitionHandler:(void(^)(NSError *error))handler;
- (void) deleteAccountCompletitionHandler:(void(^)(NSError *error))handler;
- (void) logoutAll:(BOOL) all completionHandler:(void(^)(NSError *error))handler;

- (void) setCallRoute:(SWCallRoute) callRoute completionHandler:(void(^)(NSError *error))handler;
- (void) getCallRouteCompletionHandler:(void(^)(SWCallRoute callRoute, NSError *error))handler;
@end
