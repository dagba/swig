//
//  SWEndpoint.h
//  swig
//
//  Created by Pierre-Marc Airoldi on 2014-08-20.
//  Copyright (c) 2014 PeteAppDesigns. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SWAccount.h"
#import <pjsua.h>
#import "SWRingtone.h"
#import <pjnath.h>

typedef NS_ENUM(NSUInteger, SWMessageStatus) {
    SWMessageStatusUnknown = 0,
    SWMessageStatusSended = 1,
    SWMessageStatusDelivered = 2,
    SWMessageStatusNotDelivered = 3,
    SWMessageStatusRead = 4
};

typedef void (^SWMessageSentBlock)(SWAccount *account, NSString *callID, NSUInteger messageID, SWMessageStatus status);
typedef void (^SWMessageReceivedBlock)(SWAccount *account, NSString *from, NSString *message, NSUInteger messageID, SWFileType fileType, NSString *fileHash);
typedef void (^SWNeedConfirmBlock)(SWAccount *account, NSUInteger status);
typedef void (^SWConfirmationBlock)(NSError *error);
typedef void (^SWMessageStatusBlock) (SWAccount *account, NSUInteger messageID, SWMessageStatus status);
typedef void (^SWAbonentStatusBlock) (SWAccount *account, NSString *abonent, SWPresenseState loginStatus);
typedef void (^SWReadyToSendFileBlock) (SWAccount *account, NSString *to, NSUInteger messageID, SWFileType fileType, NSString *fileHash);



@class SWEndpointConfiguration, SWAccount, SWCall;

@interface SWEndpoint : NSObject

@property (nonatomic, strong, readonly) SWEndpointConfiguration *endpointConfiguration;
@property (nonatomic, readonly) pj_pool_t *pjPool;
@property (nonatomic, strong, readonly) NSArray *accounts;
@property (nonatomic, strong) SWRingtone *ringtone;
@property (atomic) pjsip_sip_uri *fix_contact_uri;


+(instancetype)sharedEndpoint;

-(void)configure:(SWEndpointConfiguration *)configuration completionHandler:(void(^)(NSError *error))handler; //configure and start endpoint
-(BOOL)hasTCPConfiguration;
-(void)start:(void(^)(NSError *error))handler;
-(void)reset:(void(^)(NSError *error))handler; //reset endpoint

-(void)addAccount:(SWAccount *)account;
-(void)removeAccount:(SWAccount *)account;
-(SWAccount *)lookupAccount:(NSInteger)accountId;
-(SWAccount *)firstAccount;

-(void)setAccountStateChangeBlock:(void(^)(SWAccount *account))accountStateChangeBlock;
-(void)setIncomingCallBlock:(void(^)(SWAccount *account, SWCall *call))incomingCallBlock;
-(void)setCallStateChangeBlock:(void(^)(SWAccount *account, SWCall *call))callStateChangeBlock;
-(void)setCallMediaStateChangeBlock:(void(^)(SWAccount *account, SWCall *call))callMediaStateChangeBlock;

- (void) setMessageSentBlock: (SWMessageSentBlock) messageSentBlock;
- (void) setMessageReceivedBlock: (SWMessageReceivedBlock) messageReceivedBlock;
- (void) setMessageStatusBlock: (SWMessageStatusBlock) messageStatusBlock;
- (void) setAbonentStatusBlock: (SWAbonentStatusBlock) abonentStatusBlock;

//- (void) setReceiveAbonentStatusBlock: (void(^)() receiveAbonentStatusBlock);
//- (void) setReceiveNotifyBlock: (void(^)() receiveNotifyBlock);
- (void) setNeedConfirmBlock: (SWNeedConfirmBlock) needConfirmBlock;
- (void) setConfirmationBlock: (SWConfirmationBlock) confirmationBlock;

- (void) setReadyToSendFileBlock: (SWReadyToSendFileBlock) readyToSendFileBlock;



-(void)keepAlive;

- (pj_bool_t) incomingRequestPackageProcessing: (pjsip_rx_data *)data;
- (pj_bool_t) incomingResponsePackageProcessing: (pjsip_rx_data *)data;
- (pj_bool_t) outgoingResponsePackageProcessing: (pjsip_tx_data *)tdata;

@end
