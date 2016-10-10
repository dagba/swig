//
//  SWAccount.m
//  swig
//
//  Created by Pierre-Marc Airoldi on 2014-08-21.
//  Copyright (c) 2014 PeteAppDesigns. All rights reserved.
//

#import "SWAccount.h"
#import "SWAccountConfiguration.h"
#import "SWEndpoint.h"
#import "SWCall.h"
#import "SWUriFormatter.h"
#import "NSString+PJString.h"

#import "pjsua.h"

#include <stdio.h>
#include <stdlib.h>

#define kRegTimeout 800

void * refToSelf;

@interface SWAccount ()

@property (nonatomic, strong) SWAccountConfiguration *configuration;
@property (nonatomic, strong) NSMutableArray *calls;

@end

@implementation SWAccount

-(instancetype)init {
    
    self = [super init];
    
    if (!self) {
        return nil;
    }
    
    _calls = [NSMutableArray new];
    
    refToSelf = (__bridge void *)(self);
    
    return self;
}

-(void)dealloc {
    
}

-(void)setAccountId:(NSInteger)accountId {
    
    _accountId = accountId;
}

-(void)setAccountState:(SWAccountState)accountState {
    
    [self willChangeValueForKey:@"accountState"];
    _accountState = accountState;
    [self didChangeValueForKey:@"accountState"];
}

-(void)setAccountConfiguration:(SWAccountConfiguration *)accountConfiguration {
    
    [self willChangeValueForKey:@"accountConfiguration"];
    _accountConfiguration = accountConfiguration;
    [self didChangeValueForKey:@"accountConfiguration"];
}

-(void)configure:(SWAccountConfiguration *)configuration completionHandler:(void(^)(NSError *error))handler {
    pj_status_t status;

    self.accountConfiguration = configuration;
    
    if (!self.accountConfiguration.address) {
        self.accountConfiguration.address = [SWAccountConfiguration addressFromUsername:self.accountConfiguration.username domain:self.accountConfiguration.domain];
    }
    
    pjsua_acc_config acc_cfg;
    pjsua_acc_config_default(&acc_cfg);
    
    acc_cfg.id = [[SWUriFormatter sipUri:self.accountConfiguration.address withDisplayName:self.accountConfiguration.displayName] pjString];
    acc_cfg.reg_uri = [[SWUriFormatter sipUri:self.accountConfiguration.domain] pjString];
    acc_cfg.register_on_acc_add = self.accountConfiguration.registerOnAdd ? PJ_TRUE : PJ_FALSE;
    acc_cfg.publish_enabled = self.accountConfiguration.publishEnabled ? PJ_TRUE : PJ_FALSE;
    acc_cfg.reg_timeout = kRegTimeout;
    acc_cfg.allow_contact_rewrite = 0;
    acc_cfg.contact_rewrite_method = PJSUA_CONTACT_REWRITE_ALWAYS_UPDATE;
    acc_cfg.allow_via_rewrite = 0;
//    acc_cfg.ipv6_media_use = PJSUA_IPV6_ENABLED;

    //    acc_cfg.reg_delay_before_refresh
    //    acc_cfg.reg_first_retry_interval
    acc_cfg.reg_retry_interval = 5;
    
    acc_cfg.cred_count = 1;
    acc_cfg.cred_info[0].scheme = [self.accountConfiguration.authScheme pjString];
    acc_cfg.cred_info[0].realm = [self.accountConfiguration.authRealm pjString];
    acc_cfg.cred_info[0].username = [self.accountConfiguration.username pjString];
    acc_cfg.cred_info[0].data_type = PJSIP_CRED_DATA_PLAIN_PASSWD;
    acc_cfg.cred_info[0].data = [self.accountConfiguration.password pjString];
    acc_cfg.ka_interval = 25;
    
    acc_cfg.sip_stun_use = PJSUA_STUN_USE_DEFAULT;
    acc_cfg.media_stun_use = PJSUA_STUN_USE_DEFAULT;

    
    if (!self.accountConfiguration.proxy) {
        acc_cfg.proxy_cnt = 0;
    } else {
        acc_cfg.proxy_cnt = 1;
        acc_cfg.proxy[0] = [[SWUriFormatter sipUri:self.accountConfiguration.proxy] pjString];
    }
    
    
    int accountId = (int)self.accountId;
    
    status = pjsua_acc_add(&acc_cfg, PJ_TRUE, &accountId);
    
    if (status != PJ_SUCCESS) {
        
        NSError *error = [NSError errorWithDomain:@"Error adding account" code:status userInfo:nil];
        
        if (handler) {
            handler(error);
        }
        
        return;
    } else {
        [[SWEndpoint sharedEndpoint] addAccount:self];
    }
    
    if (!self.accountConfiguration.registerOnAdd) {
        [self connect:handler];
    } else {
        if (handler) {
            handler(nil);
        }
    }
}

- (void) setCode: (NSString *) code completionHandler:(void(^)(NSError *error))handler {
    if ([code length] == 4) {
        [self.accountConfiguration setCode:code];
        [self connect:^(NSError *error) {
            handler(error);
        }];
        
        return;
    }
    NSError *error = [NSError errorWithDomain:@"Code invalid" code:0 userInfo:nil];
    if (handler) {
        handler(error);
    }
}

- (void) setPhone: (NSString *) phone completionHandler:(void(^)(NSError *error))handler {
    self.accountConfiguration.username = phone;
    self.accountConfiguration.address = [SWAccountConfiguration addressFromUsername:self.accountConfiguration.username domain:self.accountConfiguration.domain];

    pjsua_acc_config acc_cfg;
    pj_status_t status = pjsua_acc_get_config((int)self.accountId, [[SWEndpoint sharedEndpoint] pjPool], &acc_cfg);
    
    if (status != PJ_SUCCESS) {
        NSError *error = [NSError errorWithDomain:@"Cannot get config" code:status userInfo:nil];
        
        if (handler) {
            handler(error);
        }
        return;
    }
    
    acc_cfg.id = [[SWUriFormatter sipUri:self.accountConfiguration.address withDisplayName:self.accountConfiguration.displayName] pjString];

    acc_cfg.cred_info[0].username = [phone pjString];
    
    status = pjsua_acc_modify((int)self.accountId, &acc_cfg);
    
    if (status != PJ_SUCCESS) {
        NSError *error = [NSError errorWithDomain:@"Cannot modify account" code:status userInfo:nil];
        
        if (handler) {
            handler(error);
        }
        return;
    }
    
    
    if (handler) {
        handler(nil);
    }
    return;
}

-(void)connect:(void(^)(NSError *error))handler {
    
    //FIX: registering too often will cause the server to possibly return error
    
    pj_status_t status;
    
    status = pjsua_acc_set_registration((int)self.accountId, PJ_TRUE);
    
    if (status != PJ_SUCCESS) {
        
        NSError *error = [NSError errorWithDomain:@"Error setting registration" code:status userInfo:nil];
        
        if (handler) {
            handler(error);
        }
        
        return;
    }
    
    status = pjsua_acc_set_online_status((int)self.accountId, PJ_TRUE);
    
    if (status != PJ_SUCCESS) {
        
        NSError *error = [NSError errorWithDomain:@"Error setting online status" code:status userInfo:nil];
        
        if (handler) {
            handler(error);
        }
        
        return;
    }
    
    if (handler) {
        handler(nil);
    }
}

-(void)disconnect:(void(^)(NSError *error))handler {
    
    pj_status_t status;
    
    if (pjsua_acc_get_count() == 0) return;
    
    status = pjsua_acc_set_online_status((int)self.accountId, PJ_FALSE);
    
    if (status != PJ_SUCCESS) {
        
        NSError *error = [NSError errorWithDomain:@"Error setting online status" code:status userInfo:nil];
        
        if (handler) {
            handler(error);
        }
        
        return;
    }
    
    status = pjsua_acc_set_registration((int)self.accountId, PJ_FALSE);
    
    if (status != PJ_SUCCESS) {
        
        NSError *error = [NSError errorWithDomain:@"Error setting registration" code:status userInfo:nil];
        
        if (handler) {
            handler(error);
        }
        
        return;
    }
    
    pjsua_acc_del((int)self.accountId);
    
    if (handler) {
        handler(nil);
    }
}

- (void) accountStateConnecting {
    [self setAccountState:SWAccountStateConnecting];
}

-(void)accountStateChanged {
    
    pjsua_acc_info accountInfo;
    pjsua_acc_get_info((int)self.accountId, &accountInfo);
    
    pjsip_status_code code = accountInfo.status;
    
    //TODO make status offline/online instead of offline/connect
    //status would be disconnected, online, and offline, isConnected could return true if online/offline
    
    if (code == 0 || accountInfo.expires == -1) {
        self.accountState = SWAccountStateDisconnected;
    }
    
    else if (PJSIP_IS_STATUS_IN_CLASS(code, PJSIP_SC_TRYING) || PJSIP_IS_STATUS_IN_CLASS(code, PJSIP_SC_MULTIPLE_CHOICES)) {
        self.accountState = SWAccountStateConnecting;
    }
    
    else if (PJSIP_IS_STATUS_IN_CLASS(code, PJSIP_SC_OK)) {
        self.accountState = SWAccountStateConnected;
    }
    
    else {
        self.accountState = SWAccountStateDisconnected;
    }
}

-(BOOL)isValid {
    
    return pjsua_acc_is_valid((int)self.accountId);
}

#pragma mark - Call Management

-(void)addCall:(SWCall *)call {
    
    [self.calls addObject:call];
    
    //TODO:: setup blocks
}

-(void)removeCall:(NSUInteger)callId {
    
    SWCall *call = [self lookupCall:callId];
    
    if (call) {
        [self.calls removeObject:call];
    }
    
    call = nil;
}

-(SWCall *)lookupCall:(NSInteger)callId {
    
    NSUInteger callIndex = [self.calls indexOfObjectPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
        
        SWCall *call = (SWCall *)obj;
        
        if (call.callId == callId && call.callId != PJSUA_INVALID_ID) {
            return YES;
        }
        
        return NO;
    }];
    
    if (callIndex != NSNotFound) {
        return [self.calls objectAtIndex:callIndex]; //TODO add more management
    }
    
    else {
        return nil;
    }
}

-(SWCall *)firstCall {
    
    if (self.calls.count > 0) {
        return self.calls[0];
    }
    
    else {
        return nil;
    }
}

-(void)endAllCalls {
    
    for (SWCall *call in self.calls) {
        [call hangup:nil];
    }
}

-(void)makeCallToGSM:(NSString *)URI completionHandler:(void(^)(NSError *error))handler {
    [self makeCall:URI toGSM:YES completionHandler:handler];
}

-(void)makeCall:(NSString *)URI completionHandler:(void(^)(NSError *error))handler {
    [self makeCall:URI toGSM:NO completionHandler:handler];
}

-(void)makeCall:(NSString *)URI toGSM:(BOOL) isGSM completionHandler:(void(^)(NSError *error))handler {
    pj_status_t status;
    NSError *error;
    
    pjsua_call_id callIdentifier;
    
    pj_str_t uri = [[SWUriFormatter sipUriWithPhone:URI fromAccount:self toGSM:isGSM] pjString];
    
    status = pjsua_call_make_call((int)self.accountId, &uri, 0, NULL, NULL, &callIdentifier);
    
    if (status != PJ_SUCCESS) {
        
        error = [NSError errorWithDomain:@"Error hanging up call" code:0 userInfo:nil];
    }
    
    else {
        
        SWCall *call = [SWCall callWithId:callIdentifier accountId:self.accountId inBound:NO];
        
        
        [self addCall:call];
    }
    
    if (handler) {
        handler(error);
    }
}

#pragma mark - Send Message

-(void)sendMessage:(NSString *)message to:(NSString *)URI completionHandler:(void(^)(NSError *error, NSString *SMID, NSString *fileServer, NSDate *date))handler {
    [self sendMessage:message fileType:SWFileTypeNo fileHash:nil to:URI isGroup:NO completionHandler:handler];
}

-(void)sendGroupMessage:(NSString *)message to:(NSString *)URI completionHandler:(void(^)(NSError *error, NSString *SMID, NSString *fileServer, NSDate *date))handler {
    [self sendMessage:message fileType:SWFileTypeNo fileHash:nil to:URI isGroup:YES completionHandler:handler];
}

-(void)sendMessage:(NSString *)message fileType:(SWFileType) fileType fileHash:(NSString *) fileHash to:(NSString *)URI isGroup:(BOOL) isGroup completionHandler:(void(^)(NSError *error, NSString *SMID, NSString *fileServer, NSDate *date))handler {
    [self sendMessage:message fileType:fileType fileHash:fileHash to:URI isGroup:isGroup forceOffline:NO isGSM:NO completionHandler:handler];
}

-(void)sendMessage:(NSString *)message fileType:(SWFileType) fileType fileHash:(NSString *) fileHash to:(NSString *)URI isGroup:(BOOL) isGroup forceOffline:(BOOL) forceOffline isGSM:(BOOL) isGSM completionHandler:(void(^)(NSError *error, NSString *SMID, NSString *fileServer, NSDate *date))handler {
    
    if (!forceOffline) {
        if (self.accountState != SWAccountStateConnected) {
            NSError *error = [NSError errorWithDomain:@"Not Connected" code:0 userInfo:nil];
            handler(error, nil, nil, nil);
            return;
        }
    }

    
    pj_status_t    status;
    pjsip_tx_data *tx_msg;
    
    pj_str_t to = [[SWUriFormatter sipUriWithPhone:URI fromAccount:self toGSM:isGSM] pjString];

    status = pjsua_acc_create_request((int)self.accountId, &pjsip_message_method, &to, &tx_msg);
    if (status != PJ_SUCCESS) {
        NSError *error = [NSError errorWithDomain:@"Error creating message" code:0 userInfo:nil];
        handler(error, nil, nil, nil);
        return;
    }
    
    pj_str_t pjMessage = [message pjString];
    
    pj_str_t type = pj_str((char *)"text");
    pj_str_t subtype = pj_str((char *)"plain");
    
    pjsip_msg_body *body = pjsip_msg_body_create(tx_msg->pool, &type, &subtype, &pjMessage);
    
    tx_msg->msg->body = body;
    
    if (isGroup) {
        pj_str_t hname = pj_str((char *)"GroupID");
        pj_str_t hvalue = [URI pjString];
        pjsip_generic_string_hdr *group_id_hdr = pjsip_generic_string_hdr_create(tx_msg->pool, &hname, &hvalue);
        
        pjsip_msg_add_hdr(tx_msg->msg, (pjsip_hdr*)group_id_hdr);
    }
    
    if (fileType != SWFileTypeNo) {
        pj_str_t hname = pj_str((char *)"FileType");
        char to_string[256];
        pj_str_t hvalue;
        hvalue.ptr = to_string;
        hvalue.slen = sprintf(to_string, "%lu",(unsigned long)fileType);
        pjsip_generic_string_hdr* filetype_hdr = pjsip_generic_string_hdr_create(tx_msg->pool, &hname, &hvalue);
        
        hname = pj_str((char *)"FileHash");
        
        hvalue = [fileHash pjString];
        
        pjsip_generic_string_hdr* file_hash_hdr = pjsip_generic_string_hdr_create(tx_msg->pool, &hname, &hvalue);
        
        pjsip_msg_add_hdr(tx_msg->msg, (pjsip_hdr*)filetype_hdr);
        pjsip_msg_add_hdr(tx_msg->msg, (pjsip_hdr*)file_hash_hdr);
    }
    
    pjsip_endpt_send_request(pjsua_get_pjsip_endpt(), tx_msg, 1000, (__bridge_retained void *) [handler copy], &sendMessageCallback);
}

static void sendMessageCallback(void *token, pjsip_event *e) {
    void (^handler)(NSError *, NSString *, NSString *, NSDate *) = (__bridge_transfer typeof(handler))(token);
    
    if (e->body.tsx_state.type != PJSIP_EVENT_RX_MSG) {
        NSError *error = [NSError errorWithDomain:@"Transport Error" code:0 userInfo:nil];
//        dispatch_async(dispatch_get_main_queue(), ^{
            handler(error, nil, nil, nil);
//        });
        int accountID = ((__bridge SWAccount *)refToSelf).accountId;
        pjsua_acc_set_registration(accountID, PJ_TRUE);

        return;
    }
    
    pjsip_msg *msg = e->body.rx_msg.rdata->msg_info.msg;
    NSError *error = [NSError errorWithDomain:@"Failed to SendMessage" code:0 userInfo:nil];
    if (msg == nil) {
//        dispatch_async(dispatch_get_main_queue(), ^{
            handler(error, nil, nil, nil);
//        });
        
        return;
    }

    
    if (msg->line.status.code != PJSIP_SC_OK) {
        NSError *error = [NSError errorWithDomain:[NSString stringWithPJString:msg->line.status.reason] code:msg->line.status.code userInfo:nil];
//        dispatch_async(dispatch_get_main_queue(), ^{
            handler(error, nil, nil, nil);
//        });
        return;
    }
    
    pj_str_t smid_hdr_str = pj_str((char *)"SMID");
    pjsip_generic_string_hdr *smid_hdr = (pjsip_generic_string_hdr*)pjsip_msg_find_hdr_by_name(msg, &smid_hdr_str, nil);
    
    NSString *fileServer = nil;
    pj_str_t  file_server_hdr_str = pj_str((char *)"File-Server");
    pjsip_generic_string_hdr* file_server_hdr = (pjsip_generic_string_hdr*)pjsip_msg_find_hdr_by_name(msg, &file_server_hdr_str, nil);

    pj_str_t submit_time_hdr_str = pj_str((char *)"SubmitTime");
    pjsip_generic_string_hdr* submit_time_hdr = (pjsip_generic_string_hdr*)pjsip_msg_find_hdr_by_name(msg, &submit_time_hdr_str, nil);
    
    NSDate *date = [NSDate date];
    if (submit_time_hdr != nil) {
        NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
        [dateFormatter setDateFormat:@"YYYY-MM-dd HH:mm:ss Z"];
        date = [dateFormatter dateFromString:[NSString stringWithPJString:submit_time_hdr->hvalue]];
    }
    
    if (file_server_hdr != nil) {
        fileServer = [[NSString stringWithPJString:file_server_hdr->hvalue] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"<>"]];
    }

//    dispatch_async(dispatch_get_main_queue(), ^{
//    if (smid_hdr) {

    handler(nil, smid_hdr?[NSString stringWithPJString:smid_hdr->hvalue]:nil, fileServer, date);
//    } else {
//        NSError *error = [NSError errorWithDomain:@"Failed to SendMessage" code:0 userInfo:nil];
//        handler(error, nil, nil, nil);
//    }
//    });
}

#pragma mark - Message Notify

-(void)sendMessageReadNotifyTo:(NSString *)URI smid:(NSUInteger)smid groupID:(NSInteger) groupID completionHandler:(void(^)(NSError *error))handler {
    if (self.accountState != SWAccountStateConnected) {
        NSError *error = [NSError errorWithDomain:@"Not Connected" code:0 userInfo:nil];
        handler(error);
        return;
    }

    
    pj_status_t    status;
    pjsip_tx_data *tx_msg;
    
    pj_str_t target = [[SWUriFormatter sipUri:URI fromAccount:self] pjString];
    
    status = pjsua_acc_create_request((int)self.accountId, &pjsip_notify_method, &target, &tx_msg);
    
    if (status != PJ_SUCCESS) {
        NSError *error = [NSError errorWithDomain:@"Failed to create reading recepient" code:0 userInfo:nil];
        handler(error);
        return;
    }
    pj_str_t hname = pj_str((char *)"Event");
    char to_string[256];
    pj_str_t hvalue;
    hvalue.ptr = to_string;
    hvalue.slen = sprintf(to_string, "%lu",(unsigned long)SWMessageStatusRead);
    
    pjsip_generic_string_hdr* event_hdr = pjsip_generic_string_hdr_create(tx_msg->pool, &hname, &hvalue);
    
    hname = pj_str((char *)"SMID");
    hvalue.ptr = to_string;
    hvalue.slen = sprintf(to_string, "%lu",(unsigned long)smid);
    pjsip_generic_string_hdr* smid_hdr = pjsip_generic_string_hdr_create(tx_msg->pool, &hname, &hvalue);

    if (groupID > 0) {
        hname = pj_str((char *)"GroupID");
        char buffer[50];
        hvalue.ptr = buffer;
        hvalue.slen = snprintf(buffer, 50, "%d", (int)groupID);
        pjsip_generic_string_hdr* group_id_hdr = pjsip_generic_string_hdr_create(tx_msg->pool, &hname, &hvalue);
        pjsip_msg_add_hdr(tx_msg->msg, (pjsip_hdr*)group_id_hdr);
    }
    
    pjsip_msg_add_hdr(tx_msg->msg, (pjsip_hdr*)event_hdr);
    pjsip_msg_add_hdr(tx_msg->msg, (pjsip_hdr*)smid_hdr);

    pjsip_endpt_send_request(pjsua_get_pjsip_endpt(), tx_msg, 1000, (__bridge_retained void *) [handler copy], &sendMessageReadNotifyCallback);
}

static void sendMessageReadNotifyCallback(void *token, pjsip_event *e) {
    void (^handler)(NSError *) = (__bridge_transfer typeof(handler))(token);
    
    if (e->body.tsx_state.type != PJSIP_EVENT_RX_MSG) {
        NSError *error = [NSError errorWithDomain:@"Transport Error" code:0 userInfo:nil];
//        dispatch_async(dispatch_get_main_queue(), ^{
            handler(error);
//        });
        int accountID = ((__bridge SWAccount *)refToSelf).accountId;
        pjsua_acc_set_registration(accountID, PJ_TRUE);

        return;
    }
    
    pjsip_msg *msg = e->body.rx_msg.rdata->msg_info.msg;
    NSError *error = [NSError errorWithDomain:@"Failed to Message Read Notify" code:0 userInfo:nil];
    if (msg == nil) {
//        dispatch_async(dispatch_get_main_queue(), ^{
            handler(error);
//        });
        
        return;
    }
    
    if (msg->line.status.code != PJSIP_SC_OK) {
        NSError *error = [NSError errorWithDomain:[NSString stringWithPJString:msg->line.status.reason] code:msg->line.status.code userInfo:nil];
//        dispatch_async(dispatch_get_main_queue(), ^{
            handler(error);
//        });
        return;
    }
//    dispatch_async(dispatch_get_main_queue(), ^{
        handler(nil);
//    });
}

#pragma mark - Delete Message

- (void) deleteMessage:(NSInteger) smid direction:(SWMessageDirection) direction fileFlag:(BOOL) fileFlag chatID: (NSInteger) chatID completionHandler:(void(^)(NSError *error))handler {
    pj_status_t    status;
    pjsip_tx_data *tx_msg;
    
    pjsua_acc_info info;
    
    pjsua_acc_get_info((int)self.accountId, &info);
    
    pjsip_method method;
    pj_str_t method_string = pj_str("COMMAND");
    
    pjsip_method_init_np(&method, &method_string);
    
    /* Создаем непосредственно запрос */
    status = pjsua_acc_create_request((int)self.accountId, &method, &info.acc_uri, &tx_msg);
    if (status != PJ_SUCCESS) {
        NSError *error = [NSError errorWithDomain:@"Failed to delete message" code:0 userInfo:nil];
        handler(error);
        return;
    }

    pj_str_t hname_name = pj_str((char *)"Command-Name");
    pj_str_t hvalue_name = pj_str((char *)"DeleteMessage");
    
    pjsip_generic_string_hdr* hdr_name = pjsip_generic_string_hdr_create(tx_msg->pool, &hname_name, &hvalue_name);
    
    pj_str_t hname_value = pj_str((char *)"Command-Value");
    
    char buffer[255];
    pj_str_t hvalue_value;
    hvalue_value.ptr = buffer;
    hvalue_value.slen = snprintf(buffer, 255, "SMID=%d Type=%d FileFlag=%d", (int)smid, (int)direction, (int)fileFlag);
    
    pjsip_generic_string_hdr* hdr_value = pjsip_generic_string_hdr_create(tx_msg->pool, &hname_value, &hvalue_value);
    
    pjsip_msg_add_hdr(tx_msg->msg, (pjsip_hdr*)hdr_name);
    pjsip_msg_add_hdr(tx_msg->msg, (pjsip_hdr*)hdr_value);
    
    pjsip_endpt_send_request(pjsua_get_pjsip_endpt(), tx_msg, 1000, (__bridge_retained void *) [handler copy], &deleteMessageCallback);
}

static void deleteMessageCallback(void *token, pjsip_event *e) {
    
    void (^handler)(NSError *) = (__bridge_transfer typeof(handler))(token);
    
    if (e->body.tsx_state.type != PJSIP_EVENT_RX_MSG) {
        NSError *error = [NSError errorWithDomain:@"Transport Error" code:0 userInfo:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            handler(error);
        });
        int accountID = ((__bridge SWAccount *)refToSelf).accountId;
        pjsua_acc_set_registration(accountID, PJ_TRUE);
        return;
    }
    
    pjsip_msg *msg = e->body.rx_msg.rdata->msg_info.msg;
    NSError *error = [NSError errorWithDomain:@"Failed to Delete Message" code:0 userInfo:nil];
    if (msg == nil) {
        dispatch_async(dispatch_get_main_queue(), ^{
            handler(error);
        });
        return;
    }
    
    if (msg->line.status.code != PJSIP_SC_OK) {
        NSError *error = [NSError errorWithDomain:[NSString stringWithPJString:msg->line.status.reason] code:msg->line.status.code userInfo:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            handler(error);
        });
        return;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        handler(nil);
    });
}


-(void)deleteChat:(NSString *) partner withSMID:(NSInteger) smid groupId:(NSInteger) groupId completionHandler:(void(^)(NSError *error))handler {
    pj_status_t    status;
    pjsip_tx_data *tx_msg;

    pjsip_method method;
    pj_str_t method_string = pj_str("COMMAND");

    pjsip_method_init_np(&method, &method_string);

    pj_str_t target = [[SWUriFormatter sipUri:partner fromAccount:self] pjString];
    
    /* Создаем непосредственно запрос */
    status = pjsua_acc_create_request((int)self.accountId, &method, &target, &tx_msg);
    if (status != PJ_SUCCESS) {
        NSError *error = [NSError errorWithDomain:@"Failed to delete chat" code:0 userInfo:nil];
        handler(error);
        return;
    }

    pj_str_t hname_name = pj_str((char *)"Command-Name");
    pj_str_t hvalue_name = pj_str((char *)"DeleteChat");
    
    pjsip_generic_string_hdr* hdr_name = pjsip_generic_string_hdr_create(tx_msg->pool, &hname_name, &hvalue_name);
    
    pj_str_t hname_value = pj_str((char *)"Command-Value");
    
    
    NSString *hvalue = [NSString stringWithFormat:@"SMID=%d", (int)smid];
    
    if (groupId > 0) {
        hvalue = [hvalue stringByAppendingString:[NSString stringWithFormat:@" ChatID=%d", (int)groupId]];
    }
    
    pj_str_t hvalue_value = [hvalue pjString];
    pjsip_generic_string_hdr* hdr_value = pjsip_generic_string_hdr_create(tx_msg->pool, &hname_value, &hvalue_value);

    pjsip_msg_add_hdr(tx_msg->msg, (pjsip_hdr*)hdr_name);
    pjsip_msg_add_hdr(tx_msg->msg, (pjsip_hdr*)hdr_value);

    pjsip_endpt_send_request(pjsua_get_pjsip_endpt(), tx_msg, 1000, (__bridge_retained void *) [handler copy], &deleteChatCallback);
}

static void deleteChatCallback(void *token, pjsip_event *e) {
    
    void (^handler)(NSError *) = (__bridge_transfer typeof(handler))(token);
    
    if (e->body.tsx_state.type != PJSIP_EVENT_RX_MSG) {
        NSError *error = [NSError errorWithDomain:@"Transport Error" code:0 userInfo:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            handler(error);
        });
        int accountID = ((__bridge SWAccount *)refToSelf).accountId;
        pjsua_acc_set_registration(accountID, PJ_TRUE);
        return;
    }
    
    pjsip_msg *msg = e->body.rx_msg.rdata->msg_info.msg;
    NSError *error = [NSError errorWithDomain:@"Failed to Delete Chat" code:0 userInfo:nil];
    if (msg == nil) {
        dispatch_async(dispatch_get_main_queue(), ^{
            handler(error);
        });
        return;
    }
    
    if (msg->line.status.code != PJSIP_SC_OK) {
        NSError *error = [NSError errorWithDomain:[NSString stringWithPJString:msg->line.status.reason] code:msg->line.status.code userInfo:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            handler(error);
        });
        return;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        handler(nil);
    });
}



//-(void)setPresenseStatusOnline:(SWPresenseState) state completionHandler:(void(^)(NSError *error))handler {
//    pj_status_t    status;
//    pjsip_tx_data *tx_msg;
//    
//    pj_str_t hname = pj_str((char *)"Event");
//    
//    char to_string[256];
//    pj_str_t hvalue;
//    hvalue.ptr = to_string;
//    hvalue.slen = sprintf(to_string, "%lu",(unsigned long)state);
//    
//    pjsip_generic_string_hdr* event_hdr = pjsip_generic_string_hdr_create([SWEndpoint sharedEndpoint].pjPool, &hname, &hvalue);
//    
//    pjsua_acc_info info;
//    
//    pjsua_acc_get_info((int)self.accountId, &info);
//    
//    /* Создаем непосредственно запрос */
//    
//    status = pjsua_acc_create_request((int)self.accountId, &pjsip_publish_method, &info.acc_uri, &tx_msg);
//    
//    if (status != PJ_SUCCESS) {
//        NSError *error = [NSError errorWithDomain:@"Failed to create publish status" code:0 userInfo:nil];
////        dispatch_async(dispatch_get_main_queue(), ^{
//            handler(error);
////        });
//        
//        return;
//    }
//    
//    
//    pjsip_msg_add_hdr(tx_msg->msg, (pjsip_hdr*)event_hdr);
//    
//    pjsip_endpt_send_request(pjsua_get_pjsip_endpt(), tx_msg, 1000, (__bridge_retained void *) [handler copy], &publishCallback);
//}
//
//static void publishCallback(void *token, pjsip_event *e) {
//    
//    void (^handler)(NSError *) = (__bridge_transfer typeof(handler))(token);
//    
//    if (e->body.tsx_state.type != PJSIP_EVENT_RX_MSG) {
//        NSError *error = [NSError errorWithDomain:@"Transport Error" code:0 userInfo:nil];
////        dispatch_async(dispatch_get_main_queue(), ^{
//            handler(error);
////        });
//        int accountID = ((__bridge SWAccount *)refToSelf).accountId;
//        pjsua_acc_set_registration(accountID, PJ_TRUE);
//
//        return;
//    }
//    
//    pjsip_msg *msg = e->body.rx_msg.rdata->msg_info.msg;
//    if (msg == nil) {
//        NSError *error = [NSError errorWithDomain:@"Failed to publish status" code:0 userInfo:nil];
////        dispatch_async(dispatch_get_main_queue(), ^{
//        
//            handler(error);
////        });
//        return;
//    }
//    
//    if (msg->line.status.code != PJSIP_SC_OK) {
//        NSError *error = [NSError errorWithDomain:[NSString stringWithPJString:msg->line.status.reason] code:msg->line.status.code userInfo:nil];
////        dispatch_async(dispatch_get_main_queue(), ^{
//            handler(error);
////        });
//        return;
//    }
////    dispatch_async(dispatch_get_main_queue(), ^{
//        handler(nil);
////    });
//}

#pragma mark - Subscribe for abonent status

-(void) monitorPresenceStatusURI:(NSString *) URI action:(SWPresenseAction) action completionHandler:(void(^)(NSError *error))handler {
    if (self.accountState != SWAccountStateConnected) {
        NSError *error = [NSError errorWithDomain:@"Not Connected" code:0 userInfo:nil];
        handler(error);
        return;
    }

    pj_status_t    status;
    pjsip_tx_data *tx_msg;
    
    pjsua_acc_info info;
    
    pjsua_acc_get_info((int)self.accountId, &info);
    
    pj_str_t target = [[SWUriFormatter sipUri:URI fromAccount:self] pjString];
    
    status = pjsua_acc_create_request((int)self.accountId, &pjsip_subscribe_method, &target, &tx_msg);
    
    if (status != PJ_SUCCESS) {
        NSError *error = [NSError errorWithDomain:@"Failed to create subscribe request" code:0 userInfo:nil];
        handler(error);
        return;
    }
    
    if (action == SWPresenseActionSubscribe) {
        pj_str_t hname = pj_str((char *)"Event");
        pj_str_t hvalue = pj_str((char *)"presence");
        pjsip_generic_string_hdr* event_hdr = pjsip_generic_string_hdr_create(tx_msg->pool, &hname, &hvalue);
        
        pjsip_msg_add_hdr(tx_msg->msg, (pjsip_hdr*)event_hdr);
    }
    
    pjsip_endpt_send_request(pjsua_get_pjsip_endpt(), tx_msg, 1000, (__bridge_retained void *) [handler copy], &subscribeCallback);
}

static void subscribeCallback(void *token, pjsip_event *e) {
    void (^handler)(NSError *) = (__bridge_transfer typeof(handler))(token);
    
    if (e->body.tsx_state.type != PJSIP_EVENT_RX_MSG) {
        NSError *error = [NSError errorWithDomain:@"Transport Error" code:0 userInfo:nil];
//        dispatch_async(dispatch_get_main_queue(), ^{
            handler(error);
//        });
        int accountID = ((__bridge SWAccount *)refToSelf).accountId;
        pjsua_acc_set_registration(accountID, PJ_TRUE);
        

        return;
    }
    
    pjsip_msg *msg = e->body.rx_msg.rdata->msg_info.msg;
    if (msg == nil) {
        NSError *error = [NSError errorWithDomain:@"Failed to subscribe" code:0 userInfo:nil];
//        dispatch_async(dispatch_get_main_queue(), ^{
            handler(error);
//        });
        return;
    }
    
    
    if (msg->line.status.code != PJSIP_SC_OK) {
        NSError *error = [NSError errorWithDomain:[NSString stringWithPJString:msg->line.status.reason] code:msg->line.status.code userInfo:nil];
//        dispatch_async(dispatch_get_main_queue(), ^{
            handler(error);
//        });
        return;
    }
    
//    dispatch_async(dispatch_get_main_queue(), ^{
        handler(nil);
//    });
}

#pragma mark - Get Balance

-(void)updateBalanceCompletionHandler:(void(^)(NSError *error, NSNumber *balance))handler {
    if (self.accountState != SWAccountStateConnected) {
        NSError *error = [NSError errorWithDomain:@"Not Connected" code:0 userInfo:nil];
        handler(error, nil);
        return;
    }

    pj_status_t    status;
    pjsip_tx_data *tx_msg;
    
    pjsua_acc_info info;
    
    pjsua_acc_get_info((int)self.accountId, &info);
    
    pjsip_method method;
    pj_str_t method_string = pj_str("COMMAND");
    
    pjsip_method_init_np(&method, &method_string);
    
    /* Создаем непосредственно запрос */
    status = pjsua_acc_create_request((int)self.accountId, &method, &info.acc_uri, &tx_msg);
    if (status != PJ_SUCCESS) {
        NSError *error = [NSError errorWithDomain:@"Failed to create balance request" code:0 userInfo:nil];
        handler(error, nil);
        return;
    }

    pj_str_t hname = pj_str((char *)"Command-Name");
    
    pj_str_t hvalue = pj_str((char *)"GetBalance");
    
    pjsip_generic_string_hdr* event_hdr = pjsip_generic_string_hdr_create(tx_msg->pool, &hname, &hvalue);

    pjsip_msg_add_hdr(tx_msg->msg, (pjsip_hdr*)event_hdr);
    
    pjsip_endpt_send_request(pjsua_get_pjsip_endpt(), tx_msg, 1000, (__bridge_retained void *) [handler copy], &updateBalanceCallback);
}

static void updateBalanceCallback(void *token, pjsip_event *e) {
    
    void (^handler)(NSError *, NSString *) = (__bridge_transfer typeof(handler))(token);
    
    if (e->body.tsx_state.type != PJSIP_EVENT_RX_MSG) {
        NSError *error = [NSError errorWithDomain:@"Transport Error" code:0 userInfo:nil];
//        dispatch_async(dispatch_get_main_queue(), ^{
            handler(error, nil);
//        });
        int accountID = ((__bridge SWAccount *)refToSelf).accountId;
        pjsua_acc_set_registration(accountID, PJ_TRUE);

        return;
    }
    
    pjsip_msg *msg = e->body.rx_msg.rdata->msg_info.msg;
    if (msg == nil) {
        NSError *error = [NSError errorWithDomain:@"Failed to get Group info" code:0 userInfo:nil];
//        dispatch_async(dispatch_get_main_queue(), ^{
            handler(error, nil);
//        });
        return;
    }
    pj_str_t balance_hdr_str = pj_str((char *)"Balance");
    pjsip_generic_string_hdr* balance_hdr = (pjsip_generic_string_hdr*)pjsip_msg_find_hdr_by_name(msg, &balance_hdr_str, nil);
    if (balance_hdr != nil) {
        double balanceDouble = [[NSString stringWithPJString:balance_hdr->hvalue] doubleValue];
        NSNumber *balanceNumber = [NSNumber numberWithDouble:balanceDouble];
//        dispatch_async(dispatch_get_main_queue(), ^{
            handler(nil, balanceNumber);
//        });
    } else {
        NSError *error = [NSError errorWithDomain:@"Failed to update balance" code:0 userInfo:nil];
//        dispatch_async(dispatch_get_main_queue(), ^{
            handler(error, nil);
//        });
    }
}

#pragma mark - Groups

-(void) createGroup:(NSArray *) abonents name:(NSString *) name completionHandler:(void(^)(NSError *error, NSInteger groupID))handler {
    if (self.accountState != SWAccountStateConnected) {
        NSError *error = [NSError errorWithDomain:@"Not Connected" code:0 userInfo:nil];
        handler(error, nil);
        return;
    }

    pj_status_t    status;
    pjsip_tx_data *tx_msg;
    
    pjsua_acc_info info;
    
    pjsua_acc_get_info((int)self.accountId, &info);
    
    pjsip_method method;
    pj_str_t method_string = pj_str("COMMAND");
    
    pjsip_method_init_np(&method, &method_string);
    
    /* Создаем непосредственно запрос */
    status = pjsua_acc_create_request((int)self.accountId, &method, &info.acc_uri, &tx_msg);
    
    if (status != PJ_SUCCESS) {
        NSError *error = [NSError errorWithDomain:@"Failed to create balance request" code:0 userInfo:nil];
        handler(error, nil);
        return;
    }

    pj_str_t hname_name = pj_str((char *)"Command-Name");
    pj_str_t hvalue_name = pj_str((char *)"CreateChat");
    pjsip_generic_string_hdr* hdr_name = pjsip_generic_string_hdr_create(tx_msg->pool, &hname_name, &hvalue_name);
    
    pj_str_t hname_value = pj_str((char *)"Command-Value");
    pj_str_t hvalue_value = [name pjString];
    pjsip_generic_string_hdr* hdr_value = pjsip_generic_string_hdr_create(tx_msg->pool, &hname_value, &hvalue_value);
    

    
    NSString *abonentsString = [abonents componentsJoinedByString:@", "];
    
    pj_str_t abonentsPjStr = [abonentsString pjString];
    
    pj_str_t type = pj_str((char *)"text");
    pj_str_t subtype = pj_str((char *)"plain");
    
    
    pjsip_msg_body *body = pjsip_msg_body_create(tx_msg->pool, &type, &subtype, &abonentsPjStr);
    
    pjsip_msg_add_hdr(tx_msg->msg, (pjsip_hdr*)hdr_name);
    pjsip_msg_add_hdr(tx_msg->msg, (pjsip_hdr*)hdr_value);
    tx_msg->msg->body = body;
    
    pjsip_endpt_send_request(pjsua_get_pjsip_endpt(), tx_msg, 1000, (__bridge_retained void *) [handler copy], &createChatCallback);
    
}

static void createChatCallback(void *token, pjsip_event *e) {
    
    void (^handler)(NSError *, NSInteger) = (__bridge_transfer typeof(handler))(token);
    
    if (e->body.tsx_state.type != PJSIP_EVENT_RX_MSG) {
        NSError *error = [NSError errorWithDomain:@"Transport Error" code:0 userInfo:nil];
//        dispatch_async(dispatch_get_main_queue(), ^{
            handler(error, nil);
//        });
        int accountID = ((__bridge SWAccount *)refToSelf).accountId;
        pjsua_acc_set_registration(accountID, PJ_TRUE);
        return;
    }
    
    pjsip_msg *msg = e->body.rx_msg.rdata->msg_info.msg;
    
    pj_str_t group_id_hdr_str = pj_str((char *)"GroupID");
    pjsip_generic_string_hdr *group_id_hdr = (pjsip_generic_string_hdr*)pjsip_msg_find_hdr_by_name(msg, &group_id_hdr_str, nil);
//    dispatch_async(dispatch_get_main_queue(), ^{
        if (group_id_hdr) {
            NSInteger group_id = atoi(group_id_hdr->hvalue.ptr);
            handler(nil, group_id);
        } else {
            NSError *error = [NSError errorWithDomain:@"Failed to create group" code:0 userInfo:nil];
            handler(error, nil);
        }
//    });
    
}

-(void)groupInfo:(NSInteger) groupID completionHandler:(void(^)(NSError *error, NSString *name, NSArray *abonents, NSString *avatarPath))handler {
    if (self.accountState != SWAccountStateConnected) {
        NSError *error = [NSError errorWithDomain:@"Not Connected" code:0 userInfo:nil];
        handler(error, nil, nil, nil);
        return;
    }

    pj_status_t    status;
    pjsip_tx_data *tx_msg;
    
    pjsua_acc_info info;
    
    pjsua_acc_get_info((int)self.accountId, &info);
    
    pjsip_method method;
    pj_str_t method_string = pj_str("COMMAND");
    
    pjsip_method_init_np(&method, &method_string);
    
    /* Создаем непосредственно запрос */
    status = pjsua_acc_create_request((int)self.accountId, &method, &info.acc_uri, &tx_msg);
    
    if (status != PJ_SUCCESS) {
        NSError *error = [NSError errorWithDomain:@"Failed to create group info request" code:0 userInfo:nil];
        handler(error, nil, nil, nil);
        return;
    }

    pj_str_t hname_name = pj_str((char *)"Command-Name");
    pj_str_t hvalue_name = pj_str((char *)"GetChatInfo");
    pjsip_generic_string_hdr* hdr_name = pjsip_generic_string_hdr_create(tx_msg->pool, &hname_name, &hvalue_name);
    
    pj_str_t hname_value = pj_str((char *)"Command-Value");
    
    char buffer[50];
    pj_str_t hvalue_value;
    hvalue_value.ptr = buffer;
    hvalue_value.slen = snprintf(buffer, 50, "%d", (int)groupID);
    
    
    pjsip_generic_string_hdr* hdr_value = pjsip_generic_string_hdr_create(tx_msg->pool, &hname_value, &hvalue_value);
    
    pjsip_msg_add_hdr(tx_msg->msg, (pjsip_hdr*)hdr_name);
    pjsip_msg_add_hdr(tx_msg->msg, (pjsip_hdr*)hdr_value);
    
    pjsip_endpt_send_request(pjsua_get_pjsip_endpt(), tx_msg, 1000, (__bridge_retained void *) [handler copy], &groupInfoCallback);
}

static void groupInfoCallback(void *token, pjsip_event *e) {
    
    void (^handler)(NSError *, NSString *, NSArray *, NSString *) = (__bridge_transfer typeof(handler))(token);
    
    if (e->body.tsx_state.type != PJSIP_EVENT_RX_MSG) {
        NSError *error = [NSError errorWithDomain:@"Transport Error" code:0 userInfo:nil];
//        dispatch_async(dispatch_get_main_queue(), ^{
            handler(error, nil, nil, nil);
//        });
        int accountID = ((__bridge SWAccount *)refToSelf).accountId;
        pjsua_acc_set_registration(accountID, PJ_TRUE);
        return;
    }
    
    pjsip_msg *msg = e->body.rx_msg.rdata->msg_info.msg;
    if (msg == nil) {
        NSError *error = [NSError errorWithDomain:@"Failed to get Group info" code:0 userInfo:nil];
//        dispatch_async(dispatch_get_main_queue(), ^{
            handler(error, nil, nil, nil);
//        });
        return;
    }
    
    if (msg->line.status.code != PJSIP_SC_OK) {
        NSError *error = [NSError errorWithDomain:[NSString stringWithPJString:msg->line.status.reason] code:msg->line.status.code userInfo:nil];
//        dispatch_async(dispatch_get_main_queue(), ^{
            handler(error, nil, nil, nil);
//        });
        return;
    }

    NSString *message_txt = @"";
    
    if (msg->body != nil) {
        //    NSString *message_txt = [[NSString alloc] initWithBytes:data->msg_info.msg->body->data length:(NSUInteger)data->msg_info.msg->body->len encoding:NSUTF16LittleEndianStringEncoding];
        message_txt = [[NSString alloc] initWithBytes:msg->body->data length:(NSUInteger)msg->body->len encoding:NSUTF8StringEncoding];
    }

    NSArray *rawResponse = [message_txt componentsSeparatedByString:@"\n"];
    
    NSString *chatName = [rawResponse objectAtIndex:0];

    NSString *stringContacts = [rawResponse objectAtIndex:1];

    NSArray *rawContacts = [stringContacts componentsSeparatedByString:@","];
    
    NSMutableArray *array = [[NSMutableArray alloc] initWithCapacity:rawContacts.count];
    
    for (NSString *object in rawContacts) {
        NSString *trimmedObject = [object stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        [array addObject:trimmedObject];
    }
    
    NSString *avatarPath = nil;
    if (rawResponse.count == 3) {
        avatarPath = [rawResponse objectAtIndex:2];
    }
    
    handler(nil, chatName, array, avatarPath);
}

-(void)groupAddAbonents:(NSArray *)abonents groupID: (NSInteger) groupID completionHandler:(void(^)(NSError *error))handler {
    [self modifyGroup:groupID action:SWGroupActionAdd abonents:abonents completionHandler:handler];
}

-(void)groupRemoveAbonents:(NSArray *)abonents groupID: (NSInteger) groupID completionHandler:(void(^)(NSError *error))handler {
    [self modifyGroup:groupID action:SWGroupActionDelete abonents:abonents completionHandler:handler];
}

-(void)modifyGroup:(NSInteger) groupID action:(SWGroupAction) groupAction abonents:(NSArray *)abonents completionHandler:(void(^)(NSError *error))handler {
    if (self.accountState != SWAccountStateConnected) {
        NSError *error = [NSError errorWithDomain:@"Not Connected" code:0 userInfo:nil];
        handler(error);
        return;
    }
    
    pj_status_t    status;
    pjsip_tx_data *tx_msg;
    
    pjsua_acc_info info;
    
    pjsua_acc_get_info((int)self.accountId, &info);
    
    pjsip_method method;
    pj_str_t method_string = pj_str("COMMAND");
    
    pjsip_method_init_np(&method, &method_string);
    
    /* Создаем непосредственно запрос */
    status = pjsua_acc_create_request((int)self.accountId, &method, &info.acc_uri, &tx_msg);
    
    if (status != PJ_SUCCESS) {
        NSError *error = [NSError errorWithDomain:@"Failed to create group modify request" code:0 userInfo:nil];
        handler(error);
        return;
    }

    pj_str_t hname_name = pj_str((char *)"Command-Name");
    pj_str_t hvalue_name;
    
    switch (groupAction) {
        case SWGroupActionAdd:
            hvalue_name = pj_str((char *)"AddAbonent");
            break;
        case SWGroupActionDelete:
            hvalue_name = pj_str((char *)"DeleteAbonent");
            break;
            
        default:
            break;
    }
    pjsip_generic_string_hdr* hdr_name = pjsip_generic_string_hdr_create(tx_msg->pool, &hname_name, &hvalue_name);
    
    pj_str_t hname_value = pj_str((char *)"Command-Value");
    
    char buffer[50];
    pj_str_t hvalue_value;
    hvalue_value.ptr = buffer;
    hvalue_value.slen = snprintf(buffer, 50, "%d", groupID);
    
    pjsip_generic_string_hdr* hdr_value = pjsip_generic_string_hdr_create(tx_msg->pool, &hname_value, &hvalue_value);
    
    pjsip_msg_add_hdr(tx_msg->msg, (pjsip_hdr*)hdr_name);
    pjsip_msg_add_hdr(tx_msg->msg, (pjsip_hdr*)hdr_value);
    
    NSString *message = [abonents componentsJoinedByString:@","];
    
    pj_str_t pjMessage = [message pjString];
    
    pj_str_t type = pj_str((char *)"text");
    pj_str_t subtype = pj_str((char *)"plain");
    
    pjsip_msg_body *body = pjsip_msg_body_create(tx_msg->pool, &type, &subtype, &pjMessage);
    
    tx_msg->msg->body = body;
    
    pjsip_endpt_send_request(pjsua_get_pjsip_endpt(), tx_msg, 1000, (__bridge_retained void *) [handler copy], &groupModifyCallback);
}

static void groupModifyCallback(void *token, pjsip_event *e) {
    
    void (^handler)(NSError *) = (__bridge_transfer typeof(handler))(token);
    
    if (e->body.tsx_state.type != PJSIP_EVENT_RX_MSG) {
        NSError *error = [NSError errorWithDomain:@"Transport Error" code:0 userInfo:nil];
//        dispatch_async(dispatch_get_main_queue(), ^{
            handler(error);
//        });
        int accountID = ((__bridge SWAccount *)refToSelf).accountId;
        pjsua_acc_set_registration(accountID, PJ_TRUE);
        return;
    }
    
    pjsip_msg *msg = e->body.rx_msg.rdata->msg_info.msg;
    NSError *error = [NSError errorWithDomain:@"Failed to modify Group" code:0 userInfo:nil];
    if (msg == nil) {
//        dispatch_async(dispatch_get_main_queue(), ^{
            handler(error);
//        });
        return;
    }
    
    if (msg->line.status.code != PJSIP_SC_OK) {
        NSError *error = [NSError errorWithDomain:[NSString stringWithPJString:msg->line.status.reason] code:msg->line.status.code userInfo:nil];
//        dispatch_async(dispatch_get_main_queue(), ^{
            handler(error);
//        });
        return;
    }

//    dispatch_async(dispatch_get_main_queue(), ^{
        handler(nil);
//    });
}

-(void)modifyGroup:(NSInteger) groupID avatarPath:(NSString *) avatarPath completionHandler:(void(^)(NSError *error))handler {
    if (self.accountState != SWAccountStateConnected) {
        NSError *error = [NSError errorWithDomain:@"Not Connected" code:0 userInfo:nil];
        handler(error);
        return;
    }
    
    pj_status_t    status;
    pjsip_tx_data *tx_msg;
    
    pjsua_acc_info info;
    
    pjsua_acc_get_info((int)self.accountId, &info);
    
    pjsip_method method;
    pj_str_t method_string = pj_str("COMMAND");
    
    pjsip_method_init_np(&method, &method_string);
    
    /* Создаем непосредственно запрос */
    status = pjsua_acc_create_request((int)self.accountId, &method, &info.acc_uri, &tx_msg);
    
    if (status != PJ_SUCCESS) {
        NSError *error = [NSError errorWithDomain:@"Failed to create group modify request" code:0 userInfo:nil];
        handler(error);
        return;
    }
    pj_str_t hname_name = pj_str((char *)"Command-Name");
    pj_str_t hvalue_name = pj_str((char *)"SetGroupAvatar");
    
    pjsip_generic_string_hdr* hdr_name = pjsip_generic_string_hdr_create(tx_msg->pool, &hname_name, &hvalue_name);
    
    pj_str_t hname_value = pj_str((char *)"Command-Value");
    
    char buffer[50];
    pj_str_t hvalue_value;
    hvalue_value.ptr = buffer;
    hvalue_value.slen = snprintf(buffer, 50, "%d", groupID);
    
    pjsip_generic_string_hdr* hdr_value = pjsip_generic_string_hdr_create(tx_msg->pool, &hname_value, &hvalue_value);
    
    pjsip_msg_add_hdr(tx_msg->msg, (pjsip_hdr*)hdr_name);
    pjsip_msg_add_hdr(tx_msg->msg, (pjsip_hdr*)hdr_value);
    
    pj_str_t pjMessage = [avatarPath pjString];
    
    pj_str_t type = pj_str((char *)"text");
    pj_str_t subtype = pj_str((char *)"plain");
    
    pjsip_msg_body *body = pjsip_msg_body_create(tx_msg->pool, &type, &subtype, &pjMessage);
    
    tx_msg->msg->body = body;
    
    pjsip_endpt_send_request(pjsua_get_pjsip_endpt(), tx_msg, 1000, (__bridge_retained void *) [handler copy], &groupModifyCallback);
}

#pragma mark - Logout

- (void) logoutCompletitionHandler:(void(^)(NSError *error))handler {
    [self logoutAll:NO completionHandler:handler];
}

- (void) deleteAccountCompletitionHandler:(void(^)(NSError *error))handler {
    [self logoutAll:YES completionHandler:handler];
}

-(void) logoutAll:(BOOL) all completionHandler:(void(^)(NSError *error))handler {
    if (self.accountState != SWAccountStateConnected) {
        NSError *error = [NSError errorWithDomain:@"Not Connected" code:0 userInfo:nil];
        handler(error);
        return;
    }
    
    pj_status_t    status;
    pjsip_tx_data *tx_msg;
    
    pjsua_acc_info info;
    
    pjsua_acc_get_info((int)self.accountId, &info);
    
    pjsip_method method;
    pj_str_t method_string = pj_str("COMMAND");
    
    pjsip_method_init_np(&method, &method_string);
    
    /* Создаем непосредственно запрос */
    status = pjsua_acc_create_request((int)self.accountId, &method, &info.acc_uri, &tx_msg);
    
    if (status != PJ_SUCCESS) {
        NSError *error = [NSError errorWithDomain:@"Failed to create group modify request" code:0 userInfo:nil];
        handler(error);
        return;
    }
    
    pj_str_t hname_name = pj_str((char *)"Command-Name");
    pj_str_t hvalue_name = pj_str((char *)"Logout");
    
    pjsip_generic_string_hdr* hdr_name = pjsip_generic_string_hdr_create(tx_msg->pool, &hname_name, &hvalue_name);
    
    pj_str_t hname_value = pj_str((char *)"Command-Value");
    pj_str_t hvalue_value = pj_str((char *)(all?"All":"Current"));
    
    pjsip_generic_string_hdr* hdr_value = pjsip_generic_string_hdr_create(tx_msg->pool, &hname_value, &hvalue_value);

    pjsip_msg_add_hdr(tx_msg->msg, (pjsip_hdr*)hdr_name);
    pjsip_msg_add_hdr(tx_msg->msg, (pjsip_hdr*)hdr_value);
    
    pjsip_endpt_send_request(pjsua_get_pjsip_endpt(), tx_msg, 1000, (__bridge_retained void *) [handler copy], &logoutCallback);
}

static void logoutCallback(void *token, pjsip_event *e) {
    
    void (^handler)(NSError *) = (__bridge_transfer typeof(handler))(token);
    
    if (e->body.tsx_state.type != PJSIP_EVENT_RX_MSG) {
        NSError *error = [NSError errorWithDomain:@"Transport Error" code:0 userInfo:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            handler(error);
        });
        int accountID = ((__bridge SWAccount *)refToSelf).accountId;
        pjsua_acc_set_registration(accountID, PJ_TRUE);
        return;
    }
    
    pjsip_msg *msg = e->body.rx_msg.rdata->msg_info.msg;
    NSError *error = [NSError errorWithDomain:@"Failed to modify Group" code:0 userInfo:nil];
    if (msg == nil) {
        dispatch_async(dispatch_get_main_queue(), ^{
            handler(error);
        });
        return;
    }
    
    if (msg->line.status.code != PJSIP_SC_OK) {
        NSError *error = [NSError errorWithDomain:[NSString stringWithPJString:msg->line.status.reason] code:msg->line.status.code userInfo:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            handler(error);
        });
        return;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        handler(nil);
    });
}

#pragma mark - Call Route

- (void) setCallRoute:(SWCallRoute) callRoute completionHandler:(void(^)(NSError *error))handler {
    pj_status_t    status;
    pjsip_tx_data *tx_msg;
    
    pjsua_acc_info info;
    
    pjsua_acc_get_info((int)self.accountId, &info);
    
    pjsip_method method;
    pj_str_t method_string = pj_str("COMMAND");
    
    pjsip_method_init_np(&method, &method_string);
    
    /* Создаем непосредственно запрос */
    status = pjsua_acc_create_request((int)self.accountId, &method, &info.acc_uri, &tx_msg);
    
    if (status != PJ_SUCCESS) {
        NSError *error = [NSError errorWithDomain:@"Failed to set route" code:0 userInfo:nil];
        handler(error);
        return;
    }
    
    pj_str_t hname_name = pj_str((char *)"Command-Name");
    pj_str_t hvalue_name = pj_str((char *)"SetRoute");
    
    pjsip_generic_string_hdr* hdr_name = pjsip_generic_string_hdr_create(tx_msg->pool, &hname_name, &hvalue_name);
    
    pj_str_t hname_value = pj_str((char *)"Command-Value");
    char to_string[256];
    pj_str_t hvalue_value;
    hvalue_value.ptr = to_string;
    hvalue_value.slen = sprintf(to_string, "%lu",(unsigned long)callRoute);
    
    pjsip_generic_string_hdr* hdr_value = pjsip_generic_string_hdr_create(tx_msg->pool, &hname_value, &hvalue_value);

    pjsip_msg_add_hdr(tx_msg->msg, (pjsip_hdr*)hdr_name);
    pjsip_msg_add_hdr(tx_msg->msg, (pjsip_hdr*)hdr_value);
    
    pjsip_endpt_send_request(pjsua_get_pjsip_endpt(), tx_msg, 1000, (__bridge_retained void *) [handler copy], &setRouteCallback);

}

static void setRouteCallback(void *token, pjsip_event *e) {
    
    void (^handler)(NSError *) = (__bridge_transfer typeof(handler))(token);
    
    if (e->body.tsx_state.type != PJSIP_EVENT_RX_MSG) {
        NSError *error = [NSError errorWithDomain:@"Transport Error" code:0 userInfo:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            handler(error);
        });
        int accountID = ((__bridge SWAccount *)refToSelf).accountId;
        pjsua_acc_set_registration(accountID, PJ_TRUE);
        return;
    }
    
    pjsip_msg *msg = e->body.rx_msg.rdata->msg_info.msg;
    NSError *error = [NSError errorWithDomain:@"Failed to Set route" code:0 userInfo:nil];
    if (msg == nil) {
        dispatch_async(dispatch_get_main_queue(), ^{
            handler(error);
        });
        return;
    }
    
    if (msg->line.status.code != PJSIP_SC_OK) {
        NSError *error = [NSError errorWithDomain:[NSString stringWithPJString:msg->line.status.reason] code:msg->line.status.code userInfo:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            handler(error);
        });
        return;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        handler(nil);
    });
}


- (void) getCallRouteCompletionHandler:(void(^)(SWCallRoute callRoute, NSError *error))handler {
    pj_status_t    status;
    pjsip_tx_data *tx_msg;
    
    pjsua_acc_info info;
    
    pjsua_acc_get_info((int)self.accountId, &info);
    
    pjsip_method method;
    pj_str_t method_string = pj_str("COMMAND");
    
    pjsip_method_init_np(&method, &method_string);
    
    /* Создаем непосредственно запрос */
    status = pjsua_acc_create_request((int)self.accountId, &method, &info.acc_uri, &tx_msg);
    if (status != PJ_SUCCESS) {
        NSError *error = [NSError errorWithDomain:@"Failed to set route" code:0 userInfo:nil];
        handler(-1, error);
        return;
    }

    pj_str_t hname_name = pj_str((char *)"Command-Name");
    pj_str_t hvalue_name = pj_str((char *)"GetRoute");
    
    pjsip_generic_string_hdr* hdr_name = pjsip_generic_string_hdr_create(tx_msg->pool, &hname_name, &hvalue_name);
    

    pjsip_msg_add_hdr(tx_msg->msg, (pjsip_hdr*)hdr_name);
    
    pjsip_endpt_send_request(pjsua_get_pjsip_endpt(), tx_msg, 1000, (__bridge_retained void *) [handler copy], &getRouteCallback);
}

static void getRouteCallback(void *token, pjsip_event *e) {
    
    void (^handler)(SWCallRoute, NSError *) = (__bridge_transfer typeof(handler))(token);
    
    if (e->body.tsx_state.type != PJSIP_EVENT_RX_MSG) {
        NSError *error = [NSError errorWithDomain:@"Transport Error" code:0 userInfo:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            handler(-1, error);
        });
        int accountID = ((__bridge SWAccount *)refToSelf).accountId;
        pjsua_acc_set_registration(accountID, PJ_TRUE);
        return;
    }
    
    pjsip_msg *msg = e->body.rx_msg.rdata->msg_info.msg;
    NSError *error = [NSError errorWithDomain:@"Failed to Get route" code:0 userInfo:nil];
    if (msg == nil) {
        dispatch_async(dispatch_get_main_queue(), ^{
            handler(-1, error);
        });
        return;
    }
    
    if (msg->line.status.code != PJSIP_SC_OK) {
        NSError *error = [NSError errorWithDomain:[NSString stringWithPJString:msg->line.status.reason] code:msg->line.status.code userInfo:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            handler(0, error);
        });
        return;
    }
    
    pj_str_t value_hdr_str = pj_str((char *)"Command-Value");
    pjsip_hdr *value_hdr = (pjsip_hdr*)pjsip_msg_find_hdr_by_name(msg, &value_hdr_str, nil);
    
    SWCallRoute callRoute = -1;
    if (value_hdr != nil) {
        callRoute = atoi(((pjsip_generic_string_hdr *)value_hdr)->hvalue.ptr);
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        handler(callRoute, nil);
    });
}

- (void) blockUser:(NSString *)abonent completionHandler:(void(^)(NSError *error))handler {
    pj_status_t    status;
    pjsip_tx_data *tx_msg;
    
    pjsua_acc_info info;
    
    pjsua_acc_get_info((int)self.accountId, &info);
    
    pjsip_method method;
    pj_str_t method_string = pj_str("COMMAND");
    
    pjsip_method_init_np(&method, &method_string);
    
    /* Создаем непосредственно запрос */
    status = pjsua_acc_create_request((int)self.accountId, &method, &info.acc_uri, &tx_msg);
    if (status != PJ_SUCCESS) {
        NSError *error = [NSError errorWithDomain:@"Failed to set route" code:0 userInfo:nil];
        handler(error);
        return;
    }

    pj_str_t hname_name = pj_str((char *)"Command-Name");
    pj_str_t hvalue_name = pj_str((char *)"BlockUser");
    
    pjsip_generic_string_hdr* hdr_name = pjsip_generic_string_hdr_create(tx_msg->pool, &hname_name, &hvalue_name);
    
    pj_str_t hname_value = pj_str((char *)"Command-Value");
    pj_str_t hvalue_value = [abonent pjString];
    
    pjsip_generic_string_hdr* hdr_value = pjsip_generic_string_hdr_create(tx_msg->pool, &hname_value, &hvalue_value);

    pjsip_msg_add_hdr(tx_msg->msg, (pjsip_hdr*)hdr_name);
    pjsip_msg_add_hdr(tx_msg->msg, (pjsip_hdr*)hdr_value);
    
    pjsip_endpt_send_request(pjsua_get_pjsip_endpt(), tx_msg, 1000, (__bridge_retained void *) [handler copy], &blockUserCallback);
    
}

static void blockUserCallback(void *token, pjsip_event *e) {
    
    void (^handler)(NSError *) = (__bridge_transfer typeof(handler))(token);
    
    if (e->body.tsx_state.type != PJSIP_EVENT_RX_MSG) {
        NSError *error = [NSError errorWithDomain:@"Transport Error" code:0 userInfo:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            handler(error);
        });
        int accountID = ((__bridge SWAccount *)refToSelf).accountId;
        pjsua_acc_set_registration(accountID, PJ_TRUE);
        return;
    }
    
    pjsip_msg *msg = e->body.rx_msg.rdata->msg_info.msg;
    NSError *error = [NSError errorWithDomain:@"Failed to block user" code:0 userInfo:nil];
    if (msg == nil) {
        dispatch_async(dispatch_get_main_queue(), ^{
            handler(error);
        });
        return;
    }
    
    if (msg->line.status.code != PJSIP_SC_OK) {
        NSError *error = [NSError errorWithDomain:[NSString stringWithPJString:msg->line.status.reason] code:msg->line.status.code userInfo:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            handler(error);
        });
        return;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        handler(nil);
    });
}

- (void) releaseUser:(NSString *)abonent completionHandler:(void(^)(NSError *error))handler {
    pj_status_t    status;
    pjsip_tx_data *tx_msg;
    
    pjsua_acc_info info;
    
    pjsua_acc_get_info((int)self.accountId, &info);
    
    pjsip_method method;
    pj_str_t method_string = pj_str("COMMAND");
    
    pjsip_method_init_np(&method, &method_string);
    
    /* Создаем непосредственно запрос */
    status = pjsua_acc_create_request((int)self.accountId, &method, &info.acc_uri, &tx_msg);
    if (status != PJ_SUCCESS) {
        NSError *error = [NSError errorWithDomain:@"Failed to set route" code:0 userInfo:nil];
        handler(error);
        return;
    }

    pj_str_t hname_name = pj_str((char *)"Command-Name");
    pj_str_t hvalue_name = pj_str((char *)"ReleaseUser");
    
    pjsip_generic_string_hdr* hdr_name = pjsip_generic_string_hdr_create(tx_msg->pool, &hname_name, &hvalue_name);
    
    pj_str_t hname_value = pj_str((char *)"Command-Value");
    pj_str_t hvalue_value = [abonent pjString];
    
    pjsip_generic_string_hdr* hdr_value = pjsip_generic_string_hdr_create(tx_msg->pool, &hname_value, &hvalue_value);
    

    pjsip_msg_add_hdr(tx_msg->msg, (pjsip_hdr*)hdr_name);
    pjsip_msg_add_hdr(tx_msg->msg, (pjsip_hdr*)hdr_value);
    
    pjsip_endpt_send_request(pjsua_get_pjsip_endpt(), tx_msg, 1000, (__bridge_retained void *) [handler copy], &releaseUserCallback);
    
}

static void releaseUserCallback(void *token, pjsip_event *e) {
    
    void (^handler)(NSError *) = (__bridge_transfer typeof(handler))(token);
    
    if (e->body.tsx_state.type != PJSIP_EVENT_RX_MSG) {
        NSError *error = [NSError errorWithDomain:@"Transport Error" code:0 userInfo:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            handler(error);
        });
        int accountID = ((__bridge SWAccount *)refToSelf).accountId;
        pjsua_acc_set_registration(accountID, PJ_TRUE);
        return;
    }
    
    pjsip_msg *msg = e->body.rx_msg.rdata->msg_info.msg;
    NSError *error = [NSError errorWithDomain:@"Failed to release user" code:0 userInfo:nil];
    if (msg == nil) {
        dispatch_async(dispatch_get_main_queue(), ^{
            handler(error);
        });
        return;
    }
    
    if (msg->line.status.code != PJSIP_SC_OK) {
        NSError *error = [NSError errorWithDomain:[NSString stringWithPJString:msg->line.status.reason] code:msg->line.status.code userInfo:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            handler(error);
        });
        return;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        handler(nil);
    });
}

- (void) getBlackListCompletionHandler:(void(^)(NSError *error, NSArray *blackListed))handler {
    pj_status_t    status;
    pjsip_tx_data *tx_msg;
    
    pjsua_acc_info info;
    
    pjsua_acc_get_info((int)self.accountId, &info);
    
    pjsip_method method;
    pj_str_t method_string = pj_str("COMMAND");
    
    pjsip_method_init_np(&method, &method_string);
    
    /* Создаем непосредственно запрос */
    status = pjsua_acc_create_request((int)self.accountId, &method, &info.acc_uri, &tx_msg);
    
    if (status != PJ_SUCCESS) {
        NSError *error = [NSError errorWithDomain:@"Failed to set route" code:0 userInfo:nil];
        handler(error, nil);
        return;
    }
    
    pj_str_t hname_name = pj_str((char *)"Command-Name");
    pj_str_t hvalue_name = pj_str((char *)"GetBlackList");
    
    pjsip_generic_string_hdr* hdr_name = pjsip_generic_string_hdr_create(tx_msg->pool, &hname_name, &hvalue_name);
    
    //    pj_str_t hname_value = pj_str((char *)"Command-Value");
    //    pj_str_t hvalue_value = [abonent pjString];
    //
    //    pjsip_generic_string_hdr* hdr_value = pjsip_generic_string_hdr_create([SWEndpoint sharedEndpoint].pjPool, &hname_value, &hvalue_value);
    
    pjsip_msg_add_hdr(tx_msg->msg, (pjsip_hdr*)hdr_name);
    
    pjsip_endpt_send_request(pjsua_get_pjsip_endpt(), tx_msg, 1000, (__bridge_retained void *) [handler copy], &getBlacklistCallback);
}

static void getBlacklistCallback(void *token, pjsip_event *e) {
    
    void (^handler)(NSError *,NSArray *) = (__bridge_transfer typeof(handler))(token);
    
    if (e->body.tsx_state.type != PJSIP_EVENT_RX_MSG) {
        NSError *error = [NSError errorWithDomain:@"Transport Error" code:0 userInfo:nil];
                dispatch_async(dispatch_get_main_queue(), ^{
        handler(error, nil);
                });
        int accountID = ((__bridge SWAccount *)refToSelf).accountId;
        pjsua_acc_set_registration(accountID, PJ_TRUE);
        return;
    }
    
    pjsip_msg *msg = e->body.rx_msg.rdata->msg_info.msg;
    if (msg == nil) {
        NSError *error = [NSError errorWithDomain:@"Failed to get Group info" code:0 userInfo:nil];
                dispatch_async(dispatch_get_main_queue(), ^{
        handler(error, nil);
                });
        return;
    }
    
    if (msg->line.status.code != PJSIP_SC_OK) {
        NSError *error = [NSError errorWithDomain:[NSString stringWithPJString:msg->line.status.reason] code:msg->line.status.code userInfo:nil];
                dispatch_async(dispatch_get_main_queue(), ^{
        handler(error, nil);
                });
        return;
    }
    
    NSString *message_txt;
    
    if (msg->body != nil) {
        message_txt = [[NSString alloc] initWithBytes:msg->body->data length:(NSUInteger)msg->body->len encoding:NSUTF8StringEncoding];
    }
    
    NSArray *rawContacts = [message_txt componentsSeparatedByString:@","];
    
    NSMutableArray *array = [[NSMutableArray alloc] initWithCapacity:rawContacts.count];
    
    for (NSString *object in rawContacts) {
        NSString *trimmedObject = [object stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        [array addObject:trimmedObject];
    }
    
    handler(nil, array);
}

- (void) reportUser:(NSString *)abonent SMID:(NSUInteger) SMID completionHandler:(void(^)(NSError *error))handler {
    pj_status_t    status;
    pjsip_tx_data *tx_msg;
    
    pj_str_t to = [[SWUriFormatter sipUriWithPhone:abonent fromAccount:self toGSM:NO] pjString];

    pjsip_method method;
    pj_str_t method_string = pj_str("COMMAND");
    
    pjsip_method_init_np(&method, &method_string);
    

    status = pjsua_acc_create_request((int)self.accountId, &method, &to, &tx_msg);
    if (status != PJ_SUCCESS) {
        NSError *error = [NSError errorWithDomain:@"Error creating message" code:0 userInfo:nil];
        handler(error);
        return;
    }

    pj_str_t hname_name = pj_str((char *)"Command-Name");
    pj_str_t hvalue_name = pj_str((char *)"IsSpam");
    
    pjsip_generic_string_hdr* hdr_name = pjsip_generic_string_hdr_create(tx_msg->pool, &hname_name, &hvalue_name);
    
    pj_str_t hname_value = pj_str((char *)"Command-Value");
    char to_string[256];
    pj_str_t hvalue_value;
    hvalue_value.ptr = to_string;
    hvalue_value.slen = sprintf(to_string, "%lu",(unsigned long)SMID);
    pjsip_generic_string_hdr* hdr_value = pjsip_generic_string_hdr_create(tx_msg->pool, &hname_value, &hvalue_value);
    
    pjsip_msg_add_hdr(tx_msg->msg, (pjsip_hdr*)hdr_name);
    pjsip_msg_add_hdr(tx_msg->msg, (pjsip_hdr*)hdr_value);
    
    pjsip_endpt_send_request(pjsua_get_pjsip_endpt(), tx_msg, 1000, (__bridge_retained void *) [handler copy], &getBlacklistCallback);
}

static void reportUserCallback(void *token, pjsip_event *e) {
    
    void (^handler)(NSError *) = (__bridge_transfer typeof(handler))(token);
    
    if (e->body.tsx_state.type != PJSIP_EVENT_RX_MSG) {
        NSError *error = [NSError errorWithDomain:@"Transport Error" code:0 userInfo:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            handler(error);
        });
        int accountID = ((__bridge SWAccount *)refToSelf).accountId;
        pjsua_acc_set_registration(accountID, PJ_TRUE);
        return;
    }
    
    pjsip_msg *msg = e->body.rx_msg.rdata->msg_info.msg;
    NSError *error = [NSError errorWithDomain:@"Failed to report user" code:0 userInfo:nil];
    if (msg == nil) {
        dispatch_async(dispatch_get_main_queue(), ^{
            handler(error);
        });
        return;
    }
    
    if (msg->line.status.code != PJSIP_SC_OK) {
        NSError *error = [NSError errorWithDomain:[NSString stringWithPJString:msg->line.status.reason] code:msg->line.status.code userInfo:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            handler(error);
        });
        return;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        handler(nil);
    });
}

- (void) isTyping:(BOOL) typing abonent:(NSString *)abonent groupID:(NSInteger) groupID  completionHandler:(void(^)(NSError *error))handler {
//    status = pjsua_acc_create_request((int)self.accountId, &method, &to, &tx_msg);
    pj_str_t to = [[SWUriFormatter sipUriWithPhone:abonent fromAccount:self toGSM:NO] pjString];

    pjsua_msg_data msg_data;
    pjsua_msg_data_init(&msg_data);

    if (groupID) {
        pj_str_t hname = pj_str((char *)"GroupID");
        pj_str_t hvalue;

        char buffer[50];
        hvalue.ptr = buffer;
        hvalue.slen = snprintf(buffer, 50, "%d", (int)groupID);
        pjsip_generic_string_hdr* group_id_hdr = pjsip_generic_string_hdr_create([SWEndpoint sharedEndpoint].pjPool, &hname, &hvalue);
        pj_list_push_back(&msg_data.hdr_list, (pjsip_hdr*)group_id_hdr);
    }
    pj_status_t status = pjsua_im_typing((int)self.accountId, &to, typing, &msg_data);
    if (status == PJ_SUCCESS && handler) {
        dispatch_async(dispatch_get_main_queue(), ^{
            handler(nil);
        });
    }
    else if (handler) {
        char errbuf[256];
        pjsip_strerror(status, errbuf, sizeof(errbuf));
        NSError *error = [NSError errorWithDomain:[NSString stringWithFormat:@"%c", errbuf] code:status userInfo:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            handler(error);
        });

    }
}

- (void) clearCallsCompletionHandler:(void(^)(NSError *error))handler {
    pj_status_t    status;
    pjsip_tx_data *tx_msg;
    
    pjsip_method method;
    pj_str_t method_string = pj_str("COMMAND");
    
    pjsip_method_init_np(&method, &method_string);
    
    pjsua_acc_info info;
    
    pjsua_acc_get_info((int)self.accountId, &info);
    
    /* Создаем непосредственно запрос */
    status = pjsua_acc_create_request((int)self.accountId, &method, &info.acc_uri, &tx_msg);
    
    if (status != PJ_SUCCESS) {
        NSError *error = [NSError errorWithDomain:@"Failed to set route" code:0 userInfo:nil];
        handler(error);
        return;
    }

    pj_str_t hname_name = pj_str((char *)"Command-Name");
    pj_str_t hvalue_name = pj_str((char *)"ClearCalls");
    
    pjsip_generic_string_hdr* hdr_name = pjsip_generic_string_hdr_create(tx_msg->pool, &hname_name, &hvalue_name);
    

    pjsip_msg_add_hdr(tx_msg->msg, (pjsip_hdr*)hdr_name);
    
    pjsip_endpt_send_request(pjsua_get_pjsip_endpt(), tx_msg, 1000, (__bridge_retained void *) [handler copy], &clearCallsCallback);
}

static void clearCallsCallback(void *token, pjsip_event *e) {
    
    void (^handler)(NSError *) = (__bridge_transfer typeof(handler))(token);
    
    if (e->body.tsx_state.type != PJSIP_EVENT_RX_MSG) {
        NSError *error = [NSError errorWithDomain:@"Transport Error" code:0 userInfo:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            handler(error);
        });
        int accountID = ((__bridge SWAccount *)refToSelf).accountId;
        pjsua_acc_set_registration(accountID, PJ_TRUE);
        return;
    }
    
    pjsip_msg *msg = e->body.rx_msg.rdata->msg_info.msg;
    NSError *error = [NSError errorWithDomain:@"Failed to Clear Calls" code:0 userInfo:nil];
    if (msg == nil) {
        dispatch_async(dispatch_get_main_queue(), ^{
            handler(error);
        });
        return;
    }
    
    if (msg->line.status.code != PJSIP_SC_OK) {
        NSError *error = [NSError errorWithDomain:[NSString stringWithPJString:msg->line.status.reason] code:msg->line.status.code userInfo:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            handler(error);
        });
        return;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        handler(nil);
    });
}



@end
