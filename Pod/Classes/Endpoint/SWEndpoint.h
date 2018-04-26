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

struct Sync {
    NSUInteger lastSmidRX;
    NSUInteger lastSmidTX;
    NSUInteger lastReport;
    NSUInteger lastViev;
};

struct Settings {
    __unsafe_unretained NSString *contactServer;
    __unsafe_unretained NSString *pushServer;
    __unsafe_unretained NSString *fileServer;
    BOOL homeAbonent;
};


typedef NS_ENUM(NSUInteger, SWMessageStatus) {
    SWMessageStatusSending = 0,
    SWMessageStatusSended = 1,
    SWMessageStatusDelivered = 2,
    SWMessageStatusNotDelivered = 3,
    SWMessageStatusRead = 4
};

//typedef void (^SWMessageSentBlock)(SWAccount *account, NSString *callID, NSUInteger messageID, SWMessageStatus status, NSString *fileServer);
typedef void (^SWMessageReceivedBlock)(SWAccount *account, NSString *from, NSString *to, NSString *message, NSUInteger messageID, NSInteger groupID, NSDate *date, SWFileType fileType, NSString *fileHash, NSString *fileServer, BOOL sync, BOOL lastMessageInPack, int status);
typedef void (^SWMessageDeletedBlock)(SWAccount *account, NSUInteger messageID);
typedef void (^SWChatDeletedBlock)(SWAccount *account, NSString* partner, NSUInteger groupID);
typedef void (^SWNeedConfirmBlock)(SWAccount *account, NSUInteger status, NSDictionary *headers);
typedef void (^SWConfirmationBlock)(SWAccount *account, NSError *error);
typedef void (^SWMessageStatusBlock) (SWAccount *account, NSUInteger messageID, SWMessageStatus status, NSDate *date, BOOL sync, BOOL lastMessageInPack);
typedef void (^SWMessageStatusBlockForAbonent) (SWAccount *account, NSUInteger messageID, SWMessageStatus status, NSDate *date, BOOL sync, BOOL lastMessageInPack, NSString *abonent);
typedef void (^SWAbonentStatusBlock) (SWAccount *account, NSString *abonent, SWPresenseState loginStatus, NSDate *lastOnline);
typedef void (^SWGroupMembersUpdatedBlock) (SWAccount *account, NSString *abonent, NSString *admin, NSInteger groupID, BOOL abonentAdded);
//typedef void (^SWReadyToSendFileBlock) (SWAccount *account, NSString *to, NSUInteger messageID, SWFileType fileType, NSString *fileHash);
typedef struct Sync (^SWGetCounterBlock) (SWAccount *account);
typedef void (^SWSettingsUpdatedBlock) (struct Settings settings);
typedef void (^SWSyncDoneBlock) (SWAccount *account);
typedef void (^SWGroupCreatedBlock) (SWAccount *account, NSInteger groupID, NSString *groupName);
typedef void (^SWTypingBlock) (SWAccount *account, NSString *abonent, NSInteger groupID, BOOL typing);
typedef BOOL (^SWShouldResumeBlock) (SWAccount *account);
typedef void (^SWUnauthorizedBlock) (SWAccount *account);

typedef void (^SWErrorBlock) (NSUInteger status);

//typedef void (^SWBalanceUpdatedBlock) (NSNumber *balance);


@class SWEndpointConfiguration, SWAccount, SWCall, SWThreadManager;

@interface SWEndpoint : NSObject

@property (nonatomic, strong, readonly) SWEndpointConfiguration *endpointConfiguration;
//@property (nonatomic, readonly) pj_pool_t *pjPool;
@property (nonatomic, strong, readonly) NSArray *accounts;
@property (nonatomic, strong) SWRingtone *ringtone;
@property (nonatomic, readonly) BOOL areOtherCalls;

@property (nonatomic, strong) SWThreadManager *threadFactory;

@property (nonatomic, copy) SWNeedConfirmBlock needConfirmBlock;

+(instancetype)sharedEndpoint;

- (pj_pool_t *) pjPool;

-(void)configure:(SWEndpointConfiguration *)configuration completionHandler:(void(^)(NSError *error))handler; //configure and start endpoint
-(BOOL)hasTCPConfiguration;
-(void)start:(void(^)(NSError *error))handler;
-(void)reset:(void(^)(NSError *error))handler; //reset endpoint
-(void)restart:(void(^)(NSError *error))handler;
-(void)setShouldResumeBlock:(SWShouldResumeBlock)handler;


-(void)addAccount:(SWAccount *)account;
-(void)removeAccount:(SWAccount *)account;
-(SWAccount *)lookupAccount:(NSInteger)accountId;
-(SWAccount *)firstAccount;

-(void)setAccountStateChangeBlock:(void(^)(SWAccount *account))accountStateChangeBlock forObserver: (id) observer;
-(void)removeAccountStateChangeBlockForObserver: (id) observer;
-(void)setIncomingCallBlock:(void(^)(SWAccount *account, SWCall *call))incomingCallBlock;
-(void)setCallStateChangeBlock:(void(^)(SWAccount *account, SWCall *call, pjsip_status_code statusCode))callStateChangeBlock;
- (void) runCallStateChangeBlockForCall: (SWCall *)call setCode: (pjsip_status_code) statusCode;
-(void)setCallMediaStateChangeBlock:(void(^)(SWAccount *account, SWCall *call))callMediaStateChangeBlock;
-(void)setCallVideoFormatChangeBlock:(void(^)(SWAccount *account, SWCall *call))callVideoFormatChangeBlock;
-(void)setSyncDoneBlock:(void(^)(SWAccount *account))syncDoneBlock;
-(void)setGroupCreatedBlock:(void(^)(SWAccount *account, NSInteger groupID, NSString *groupName))groupCreatedBlock;


//- (void) setMessageSentBlock: (SWMessageSentBlock) messageSentBlock;
- (void) setMessageReceivedBlock: (SWMessageReceivedBlock) messageReceivedBlock;
- (void) setMessageDeletedBlock: (SWMessageDeletedBlock) messageDeletedBlock;
- (void) setMessageStatusBlock: (SWMessageStatusBlock) messageStatusBlock;
- (void) setMessageStatusBlockForAbonent: (SWMessageStatusBlockForAbonent) messageStatusBlockForAbonent;
- (void) setAbonentStatusBlock: (SWAbonentStatusBlock) abonentStatusBlock;
- (void) setGroupMembersUpdatedBlock: (SWGroupMembersUpdatedBlock) groupMembersUpdatedBlock;
- (void) setTypingBlock: (SWTypingBlock) typingBlock;
- (void) setChatDeletedBlock: (SWChatDeletedBlock) chatDeletedBlock;

- (void) registerSipThread: (NSThread *) thread;

//- (void) setReceiveAbonentStatusBlock: (void(^)() receiveAbonentStatusBlock);
//- (void) setReceiveNotifyBlock: (void(^)() receiveNotifyBlock);
- (void) setConfirmationBlock: (SWConfirmationBlock) confirmationBlock;

- (void) setUnauthorizedBlock: (SWUnauthorizedBlock) unauthorizedBlock;

- (void) setOtherErrorBlock: (SWErrorBlock) otherErrorBlock;

//- (void) setReadyToSendFileBlock: (SWReadyToSendFileBlock) readyToSendFileBlock;

- (void) setGetCountersBlock: (SWGetCounterBlock) getCountersBlock;
- (void) setSettingsUpdatedBlock: (SWSettingsUpdatedBlock) settingsUpdatedBlock;
//- (void) setContactServerUpdatedBlock: (SWContactServerUpdatedBlock) contactsServerUpdatedBlock;
//- (void) setPushServerUpdatedBlock: (SWPushServerUpdatedBlock) pushServerUpdatedBlock;
//- (void) setBalanceUpdatedBlock: (SWBalanceUpdatedBlock) balanceUpdatedBlock;

//-(void)keepAlive;

- (pj_bool_t) rxRequestPackageProcessing: (pjsip_rx_data *)data;
- (pj_bool_t) rxResponsePackageProcessing: (pjsip_rx_data *)data;
- (pj_bool_t) txResponsePackageProcessing: (pjsip_tx_data *)tdata;
- (pj_bool_t) txRequestPackageProcessing: (pjsip_tx_data *)tdata;

- (void) startStandartRingtone;
- (SWRingtone *) getRingtoneForReason: (NSInteger) reason;

+ (NSString *) getHeaderByName: (NSString *) hname forMessage: (pjsip_msg *) msg;


@end
