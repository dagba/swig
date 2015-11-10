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

#define kRegTimeout 800

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
    
    self.accountConfiguration = configuration;
    
    if (!self.accountConfiguration.address) {
        self.accountConfiguration.address = [SWAccountConfiguration addressFromUsername:self.accountConfiguration.username domain:self.accountConfiguration.domain];
    }
    
    NSString *suffix = @"";
    
    pjsua_transport_info transport_info;
    pjsua_transport_get_info(0, &transport_info);
    
    suffix = [NSString stringWithFormat:@";transport=%@", [NSString stringWithPJString:transport_info.type_name]];
    
    pjsua_acc_config acc_cfg;
    pjsua_acc_config_default(&acc_cfg);
    
    acc_cfg.id = [[SWUriFormatter sipUri:[self.accountConfiguration.address stringByAppendingString:suffix] withDisplayName:self.accountConfiguration.displayName] pjString];
    acc_cfg.reg_uri = [[SWUriFormatter sipUri:[self.accountConfiguration.domain stringByAppendingString:suffix]] pjString];
    acc_cfg.register_on_acc_add = self.accountConfiguration.registerOnAdd ? PJ_TRUE : PJ_FALSE;
    acc_cfg.publish_enabled = self.accountConfiguration.publishEnabled ? PJ_TRUE : PJ_FALSE;
    acc_cfg.reg_timeout = kRegTimeout;
    
    acc_cfg.cred_count = 1;
    acc_cfg.cred_info[0].scheme = [self.accountConfiguration.authScheme pjString];
    acc_cfg.cred_info[0].realm = [self.accountConfiguration.authRealm pjString];
    acc_cfg.cred_info[0].username = [self.accountConfiguration.username pjString];
    acc_cfg.cred_info[0].data_type = PJSIP_CRED_DATA_PLAIN_PASSWD;
    acc_cfg.cred_info[0].data = [self.accountConfiguration.password pjString];

    acc_cfg.sip_stun_use = PJSUA_STUN_USE_DEFAULT;
    acc_cfg.media_stun_use = PJSUA_STUN_USE_DEFAULT;
    
    if (!self.accountConfiguration.proxy) {
        acc_cfg.proxy_cnt = 0;
    } else {
        acc_cfg.proxy_cnt = 1;
        acc_cfg.proxy[0] = [[SWUriFormatter sipUri:[self.accountConfiguration.proxy stringByAppendingString:suffix]] pjString];
    }
    
    
    pj_status_t status;
    
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
//        if (handler) {
//            handler(nil);
//            return;
//        }
        
        [self connect:^(NSError *error) {
            handler(error);
        }];

        return;
        
//        pjsua_acc_config acc_cfg;
//        pj_status_t status = pjsua_acc_get_config((int)self.accountId, [[SWEndpoint sharedEndpoint] pjPool], &acc_cfg);
//        
//        if (status != PJ_SUCCESS) {
//            NSError *error = [NSError errorWithDomain:@"Cannot get config" code:status userInfo:nil];
//            
//            if (handler) {
//                handler(error);
//            }
//            return;
//        }
//
//        
//        pj_str_t hname = pj_str((char *)"Auth");
//        pj_str_t hvalue = [[NSString stringWithFormat:@"code=%@, UID=%@", code, self.accountConfiguration.password] pjString];
//        
//        struct pjsip_generic_string_hdr event_hdr;
//        pjsip_generic_string_hdr_init2(&event_hdr, &hname, &hvalue);
//
//
//        pj_list_erase(&acc_cfg.reg_hdr_list);
//        pj_list_push_back(&acc_cfg.reg_hdr_list, &event_hdr);
//        
//        
//        status = pjsua_acc_modify((int)self.accountId, &acc_cfg);
//        
//        if (status != PJ_SUCCESS) {
//            NSError *error = [NSError errorWithDomain:@"Cannot modify account" code:status userInfo:nil];
//            
//            if (handler) {
//                handler(error);
//            }
//            return;
//        }
//
//        
//        if (handler) {
//            handler(nil);
//        }
//        return;
    }
    NSError *error = [NSError errorWithDomain:@"Code invalid" code:0 userInfo:nil];
    if (handler) {
        handler(error);
    }
}

- (void) setPhone: (NSString *) phone completionHandler:(void(^)(NSError *error))handler {
    self.accountConfiguration.username = phone;
    pjsua_acc_config acc_cfg;
    pj_status_t status = pjsua_acc_get_config((int)self.accountId, [[SWEndpoint sharedEndpoint] pjPool], &acc_cfg);
    
    if (status != PJ_SUCCESS) {
        NSError *error = [NSError errorWithDomain:@"Cannot get config" code:status userInfo:nil];
        
        if (handler) {
            handler(error);
        }
        return;
    }
    
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
    
    if (handler) {
        handler(nil);
    }
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
    
    else if (PJSIP_IS_STATUS_IN_CLASS(code, 100) || PJSIP_IS_STATUS_IN_CLASS(code, 300)) {
        self.accountState = SWAccountStateConnecting;
    }
    
    else if (PJSIP_IS_STATUS_IN_CLASS(code, 200)) {
        self.accountState = SWAccountStateConnected;
    }
    
    else {
        self.accountState = SWAccountStateDisconnected;
    }
}

-(BOOL)isValid {
    
    return pjsua_acc_is_valid((int)self.accountId);
}

#pragma Call Management

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

-(void)makeCall:(NSString *)URI completionHandler:(void(^)(NSError *error))handler {
    
    pj_status_t status;
    NSError *error;
    
    pjsua_call_id callIdentifier;
    pj_str_t uri = [[SWUriFormatter sipUri:URI fromAccount:self] pjString];
    
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

-(void)sendMessage:(NSString *)message to:(NSString *)URI completionHandler:(void(^)(NSError *error, NSString *callID))handler {
    [self sendMessage:message fileType:SWFileTypeNo fileHash:nil to:URI completionHandler:handler];
}

-(void)sendMessage:(NSString *)message fileType:(SWFileType) fileType fileHash:(NSString *) fileHash to:(NSString *)URI completionHandler:(void(^)(NSError *error, NSString *callID))handler {
    pj_status_t    status;
    pjsip_tx_data *tx_msg;
    pj_str_t       contact;

    pjsua_transport_info transport_info;
    pjsua_transport_get_info(0, &transport_info);
    
    contact = [[NSString stringWithFormat:@"<sips:%@@%@>;q=0.5;expires=%d", self.accountConfiguration.username, [NSString stringWithPJString:transport_info.local_name.host], 3600] pjString];
    
    pj_str_t to = [[SWUriFormatter sipUri:URI fromAccount:self] pjString];

    
    pjsua_acc_info info;
    
    pjsua_acc_get_info((int)self.accountId, &info);
    
//    NSData *message_data = [message dataUsingEncoding:NSUTF16LittleEndianStringEncoding];
    NSData *message_data = [message dataUsingEncoding:NSUTF8StringEncoding];

    char * a = (char *)[message_data bytes];

    pj_str_t pjMessage;

    pj_strset(&pjMessage, a, (int)[message_data length]);

    /* Создаем непосредственно запрос */
    status = pjsip_endpt_create_request(pjsua_get_pjsip_endpt(),
                                        &pjsip_message_method,
                                        &info.acc_uri, //proxy
                                        &info.acc_uri, //local
                                        &to, //source to
                                        &contact, //contact
                                        nil,
                                        -1,
                                        &pjMessage,
                                        &tx_msg);
    
    if (status != PJ_SUCCESS) {
        NSError *error = [NSError errorWithDomain:@"Error creating message" code:0 userInfo:nil];
        handler(error, nil);
        return;
    }
    
    if (fileType != SWFileTypeNo) {
        pj_str_t hname = pj_str((char *)"FileType");
        char to_string[256];
        pj_str_t hvalue;
        hvalue.ptr = to_string;
        hvalue.slen = sprintf(to_string, "%lu",(unsigned long)fileType);
        pjsip_generic_string_hdr* filetype_hdr = pjsip_generic_string_hdr_create([SWEndpoint sharedEndpoint].pjPool, &hname, &hvalue);
        
        hname = pj_str((char *)"FileHash");
        
        hvalue = [fileHash pjString];

        pjsip_generic_string_hdr* file_hash_hdr = pjsip_generic_string_hdr_create([SWEndpoint sharedEndpoint].pjPool, &hname, &hvalue);
        
        pjsip_msg_add_hdr(tx_msg->msg, (pjsip_hdr*)filetype_hdr);
        pjsip_msg_add_hdr(tx_msg->msg, (pjsip_hdr*)file_hash_hdr);
    }
    
    pjsip_cid_hdr *cid_hdr = PJSIP_MSG_CID_HDR(tx_msg->msg);
    
    status = pjsip_endpt_send_request_stateless(pjsua_get_pjsip_endpt(), tx_msg, nil, nil);
    if (status != PJ_SUCCESS) {
        NSError *error = [NSError errorWithDomain:@"Error sending message" code:0 userInfo:nil];
        handler(error, nil);
        return;
    }
    
    handler(nil, [NSString stringWithPJString:cid_hdr->id]);
}


-(void)sendMessageReadNotifyTo:(NSString *)URI smid:(NSUInteger)smid completionHandler:(void(^)(NSError *error))handler {
    pj_status_t    status;
    pjsip_tx_data *tx_msg;
    
    pj_str_t hname = pj_str((char *)"Event");
    char to_string[256];
    pj_str_t hvalue;
    hvalue.ptr = to_string;
    hvalue.slen = sprintf(to_string, "%lu",(unsigned long)SWMessageStatusRead);
    pjsip_generic_string_hdr* event_hdr = pjsip_generic_string_hdr_create([SWEndpoint sharedEndpoint].pjPool, &hname, &hvalue);
    
    hname = pj_str((char *)"SMID");
    hvalue.ptr = to_string;
    hvalue.slen = sprintf(to_string, "%lu",(unsigned long)smid);
    pjsip_generic_string_hdr* smid_hdr = pjsip_generic_string_hdr_create([SWEndpoint sharedEndpoint].pjPool, &hname, &hvalue);

    
    pjsua_transport_info transport_info;
    pjsua_transport_get_info(0, &transport_info);
    
    
    pjsua_acc_info info;
    
    pjsua_acc_get_info((int)self.accountId, &info);
    
//    pjsip_sip_uri *to = (pjsip_sip_uri *)pjsip_uri_get_uri(data->msg_info.to->uri);
//    pjsip_sip_uri *from = (pjsip_sip_uri *)pjsip_uri_get_uri(data->msg_info.from->uri);
    
//    char to_string[256];
//    char from_string[256];
//    
//    pj_str_t source;
//    source.ptr = to_string;
//    source.slen = snprintf(to_string, 256, "sip:%.*s@%.*s", (int)to->user.slen, to->user.ptr, (int)to->host.slen,to->host.ptr);
//    
//    pj_str_t target;
//    target.ptr = from_string;
//    target.slen = snprintf(from_string, 256, "sip:%.*s@%.*s", (int)from->user.slen, from->user.ptr, (int)from->host.slen,from->host.ptr);

    pj_str_t target = [[SWUriFormatter sipUri:URI fromAccount:self] pjString];


    
    /* Создаем непосредственно запрос */
    status = pjsip_endpt_create_request(pjsua_get_pjsip_endpt(),
                                        &pjsip_notify_method,
                                        &info.acc_uri, //proxy
                                        &info.acc_uri, //from
                                        &target, //to
                                        &info.acc_uri, //contact
                                        NULL,
                                        -1,
                                        NULL,
                                        &tx_msg);
    
    
    if (status != PJ_SUCCESS) {
        NSError *error = [NSError errorWithDomain:@"Failed to create reading recepient" code:0 userInfo:nil];
        handler(error);
    
        return;
    }
    
    
    pjsip_msg_add_hdr(tx_msg->msg, (pjsip_hdr*)event_hdr);
    pjsip_msg_add_hdr(tx_msg->msg, (pjsip_hdr*)smid_hdr);
    
    if (status == PJ_SUCCESS) {
        pjsip_endpt_send_request(pjsua_get_pjsip_endpt(), tx_msg, 1000, NULL, NULL);
    }
}

-(void)setPresenseStatusOnline:(SWPresenseState) state completionHandler:(void(^)(NSError *error))handler {
    pj_status_t    status;
    pjsip_tx_data *tx_msg;
    
    pj_str_t hname = pj_str((char *)"Event");
    
    char to_string[256];
    pj_str_t hvalue;
    hvalue.ptr = to_string;
    hvalue.slen = sprintf(to_string, "%lu",(unsigned long)state);
    
    pjsip_generic_string_hdr* event_hdr = pjsip_generic_string_hdr_create([SWEndpoint sharedEndpoint].pjPool, &hname, &hvalue);
    
    pjsua_transport_info transport_info;
    pjsua_transport_get_info(0, &transport_info);
    
    
    pjsua_acc_info info;
    
    pjsua_acc_get_info((int)self.accountId, &info);
    
    /* Создаем непосредственно запрос */
    status = pjsip_endpt_create_request(pjsua_get_pjsip_endpt(),
                                        &pjsip_publish_method,
                                        &info.acc_uri, //proxy
                                        &info.acc_uri, //from
                                        &info.acc_uri, //to
                                        &info.acc_uri, //contact
                                        NULL,
                                        -1,
                                        NULL,
                                        &tx_msg);
    
    
    if (status != PJ_SUCCESS) {
        NSError *error = [NSError errorWithDomain:@"Failed to create publish status" code:0 userInfo:nil];
        handler(error);
        
        return;
    }
    
    
    pjsip_msg_add_hdr(tx_msg->msg, (pjsip_hdr*)event_hdr);
    
    if (status == PJ_SUCCESS) {
        pjsip_endpt_send_request(pjsua_get_pjsip_endpt(), tx_msg, 1000, NULL, NULL);
    }

    if (status != PJ_SUCCESS) {
        NSError *error = [NSError errorWithDomain:@"Failed to publish status" code:0 userInfo:nil];
        handler(error);
        
        return;
    }
}

-(void)subscribeBuddyURI:(NSString *) URI completionHandler:(void(^)(NSError *error))handler {
    pj_status_t    status;
    pjsip_tx_data *tx_msg;
    
    pj_str_t hname = pj_str((char *)"Event");
    
    pj_str_t hvalue = pj_str((char *)"presence");
    
    pjsip_generic_string_hdr* event_hdr = pjsip_generic_string_hdr_create([SWEndpoint sharedEndpoint].pjPool, &hname, &hvalue);
    
    pjsua_transport_info transport_info;
    pjsua_transport_get_info(0, &transport_info);
    
    pjsua_acc_info info;
    
    pjsua_acc_get_info((int)self.accountId, &info);
    
    pj_str_t target = [[SWUriFormatter sipUri:URI fromAccount:self] pjString];
    
    /* Создаем непосредственно запрос */
    status = pjsip_endpt_create_request(pjsua_get_pjsip_endpt(),
                                        &pjsip_subscribe_method,
                                        &info.acc_uri, //proxy
                                        &info.acc_uri, //from
                                        &target, //to
                                        &info.acc_uri, //contact
                                        NULL,
                                        -1,
                                        NULL,
                                        &tx_msg);
    
    
    if (status != PJ_SUCCESS) {
        NSError *error = [NSError errorWithDomain:@"Failed to create subscribe request" code:0 userInfo:nil];
        handler(error);
        
        return;
    }
    
    pjsip_msg_add_hdr(tx_msg->msg, (pjsip_hdr*)event_hdr);
    
    if (status == PJ_SUCCESS) {
        pjsip_endpt_send_request(pjsua_get_pjsip_endpt(), tx_msg, 1000, NULL, NULL);
    }
    
    if (status != PJ_SUCCESS) {
        NSError *error = [NSError errorWithDomain:@"Failed to send subscribe requesrt" code:0 userInfo:nil];
        handler(error);
        
        return;
    }
}

@end