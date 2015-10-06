//
//  SWEndpoint.m
//  swig
//
//  Created by Pierre-Marc Airoldi on 2014-08-20.
//  Copyright (c) 2014 PeteAppDesigns. All rights reserved.
//

#import <UIKit/UIKit.h>

#import "SWEndpoint.h"
#import "SWTransportConfiguration.h"
#import "SWEndpointConfiguration.h"
#import "SWAccount.h"
#import "SWCall.h"
#import "pjsua.h"
#import "NSString+PJString.h"
#import <AFNetworkReachabilityManager.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <libextobjc/extobjc.h>
#import "Logger.h"
#import "SWAccountConfiguration.h"
#import "SWUriFormatter.h"

#define KEEP_ALIVE_INTERVAL 600

typedef void (^SWAccountStateChangeBlock)(SWAccount *account);
typedef void (^SWIncomingCallBlock)(SWAccount *account, SWCall *call);
typedef void (^SWCallStateChangeBlock)(SWAccount *account, SWCall *call);
typedef void (^SWCallMediaStateChangeBlock)(SWAccount *account, SWCall *call);


//thread statics
static pj_thread_t *thread;

//callback functions

static void SWOnIncomingCall(pjsua_acc_id acc_id, pjsua_call_id call_id, pjsip_rx_data *rdata);

static void SWOnCallMediaState(pjsua_call_id call_id);

static void SWOnCallState(pjsua_call_id call_id, pjsip_event *e);

static void SWOnCallTransferStatus(pjsua_call_id call_id, int st_code, const pj_str_t *st_text, pj_bool_t final, pj_bool_t *p_cont);

static void SWOnCallReplaced(pjsua_call_id old_call_id, pjsua_call_id new_call_id);

static void SWOnRegState(pjsua_acc_id acc_id);

static void SWOnNatDetect(const pj_stun_nat_detect_result *res);

static void SWOnTransportState (pjsip_transport *tp, pjsip_transport_state state, const pjsip_transport_state_info *info);

static pjsip_redirect_op SWOnCallRedirected(pjsua_call_id call_id, const pjsip_uri *target, const pjsip_event *e);

//static void SWOnPager (pjsua_call_id call_id, const pj_str_t *from, const pj_str_t *to, const pj_str_t *contact, const pj_str_t *mime_type, const pj_str_t *body, pjsip_rx_data *rdata, pjsua_acc_id acc_id);
//
//static void SWOnPagerStatus  (pjsua_call_id call_id, const pj_str_t *to, const pj_str_t *body, void *user_data, pjsip_status_code status, const pj_str_t *reason, pjsip_tx_data *tdata, pjsip_rx_data *rdata, pjsua_acc_id acc_id);
//
//static void SWOnTyping (pjsua_call_id call_id, const pj_str_t *from, const pj_str_t *to, const pj_str_t *contact, pj_bool_t is_typing, pjsip_rx_data *rdata, pjsua_acc_id acc_id);
//
//static void SWOnMWIInfo (pjsua_acc_id acc_id, pjsua_mwi_info *mwi_info);
//

static pj_bool_t on_rx_request(pjsip_rx_data *rdata)
{
    return [[SWEndpoint sharedEndpoint] requestPackageProcessing:rdata];
}


static pj_bool_t on_rx_response(pjsip_rx_data *rdata)
{
    
    
    return [[SWEndpoint sharedEndpoint] responsePackageProcessing:rdata];
}

static pjsip_module sipgate_module =
{
    NULL, NULL,	             /* prev and next */
    { (char *)"sipmessenger-core", 17},   /* Name */
    //    { "mod-default-handler", 19 },
    -1,                      /* Id */
    //    PJSIP_MOD_PRIORITY_APPLICATION,/* Priority	 */
    PJSIP_MOD_PRIORITY_TRANSPORT_LAYER, /* Priority */
    NULL,                    /* load() */
    NULL,                    /* start() */
    NULL,                    /* stop() */
    NULL,                    /* unload() */
    &on_rx_request,          /* on_rx_request() */
    &on_rx_response,         /* on_rx_response() */
    NULL,        /* on_tx_request() */
    NULL,       /* on_tx_response() */
    NULL,                    /* on_tsx_state() */
};



@interface SWEndpoint ()

@property (nonatomic, copy) SWIncomingCallBlock incomingCallBlock;
@property (nonatomic, copy) SWAccountStateChangeBlock accountStateChangeBlock;
@property (nonatomic, copy) SWCallStateChangeBlock callStateChangeBlock;
@property (nonatomic, copy) SWCallMediaStateChangeBlock callMediaStateChangeBlock;

@property (nonatomic, copy) SWMessageSentBlock messageSentBlock;
@property (nonatomic, copy) SWMessageReceivedBlock messageReceivedBlock;
@property (nonatomic, copy) SWMessageStatusBlock messageStatusBlock;
@property (nonatomic, copy) SWNeedConfirmBlock needConfirmBlock;
@property (nonatomic, copy) SWConfirmationBlock confirmationBlock;

@property (nonatomic) pj_thread_t *thread;



@end

@implementation SWEndpoint

static SWEndpoint *_sharedEndpoint = nil;



+(id)sharedEndpoint {
    
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        _sharedEndpoint = [self new];
    });
    
    return _sharedEndpoint;
}

-(instancetype)init {
    
    if (_sharedEndpoint) {
        return _sharedEndpoint;
    }
    
    self = [super init];
    
    if (!self) {
        return nil;
    }
    
    [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
    
    [DDLog addLogger:[DDASLLogger sharedInstance]];
    [DDLog addLogger:[DDTTYLogger sharedInstance]];
    
    DDFileLogger *fileLogger = [[DDFileLogger alloc] init];
    fileLogger.rollingFrequency = 0;
    fileLogger.maximumFileSize = 0;
    
    [DDLog addLogger:fileLogger];
    
    _accounts = [[NSMutableArray alloc] init];
    
    [self registerThread];
    
    NSURL *fileURL = [[NSBundle mainBundle] URLForResource:@"Ringtone" withExtension:@"aif"];
    
    _ringtone = [[SWRingtone alloc] initWithFileAtPath:fileURL];
    
    //TODO check if the reachability happens in background
    //FIX make sure connect doesnt get called too often
    //IP Change logic
    
    [[AFNetworkReachabilityManager sharedManager] setReachabilityStatusChangeBlock:^(AFNetworkReachabilityStatus status) {
        
        if ([AFNetworkReachabilityManager sharedManager].reachableViaWiFi) {
            
            [self performSelectorOnMainThread:@selector(keepAlive) withObject:nil waitUntilDone:YES];
        }
        
        else if ([AFNetworkReachabilityManager sharedManager].reachableViaWWAN) {
            [self performSelectorOnMainThread:@selector(keepAlive) withObject:nil waitUntilDone:YES];
        }
        
        else {
            //offline
        }
    }];
    
    
    [[AFNetworkReachabilityManager sharedManager] startMonitoring];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector: @selector(handleEnteredBackground:) name: UIApplicationDidEnterBackgroundNotification object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector: @selector(handleApplicationWillTeminate:) name:UIApplicationWillTerminateNotification object:nil];
    
    return self;
}

-(void)dealloc {
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidEnterBackgroundNotification object:nil];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationWillTerminateNotification object:nil];
    
    [self reset:^(NSError *error) {
        if (error) DDLogDebug(@"%@", [error description]);
    }];
}

#pragma Notification Methods

-(void)handleEnteredBackground:(NSNotification *)notification {
    
    UIApplication *application = (UIApplication *)notification.object;
    
    [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:NULL];
    [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
    
    self.ringtone.volume = 0.0;
    
    [self performSelectorOnMainThread:@selector(keepAlive) withObject:nil waitUntilDone:YES];
    
    [application setKeepAliveTimeout:KEEP_ALIVE_INTERVAL handler: ^{
        [self performSelectorOnMainThread:@selector(keepAlive) withObject:nil waitUntilDone:YES];
    }];
}

-(void)handleApplicationWillTeminate:(NSNotification *)notification {
    
    UIApplication *application = (UIApplication *)notification.object;
    
    //TODO hangup all calls
    //TODO remove all accounts
    //TODO close all transports
    //TODO reset endpoint
    
    for (int i = 0; i < [self.accounts count]; ++i) {
        
        SWAccount *account = [self.accounts objectAtIndex:i];
        
        dispatch_semaphore_t semaphone = dispatch_semaphore_create(0);
        
        @weakify(account);
        [account disconnect:^(NSError *error) {
            
            @strongify(account);
            account = nil;
            
            dispatch_semaphore_signal(semaphone);
        }];
        
        dispatch_semaphore_wait(semaphone, DISPATCH_TIME_FOREVER);
    }
    
    NSMutableArray *mutableAccounts = [self.accounts mutableCopy];
    
    [mutableAccounts removeAllObjects];
    
    self.accounts = mutableAccounts;
    
    [self reset:^(NSError *error) {
        
        if (error) {
            DDLogDebug(@"%@", [error description]);
        }
    }];
    
    [application setApplicationIconBadgeNumber:0];
}

-(void)keepAlive {
    
    if (pjsua_get_state() != PJSUA_STATE_RUNNING) {
        return;
    }
    
    [self registerThread];
    
    for (SWAccount *account in self.accounts) {
        
        if (account.isValid) {
            
            dispatch_semaphore_t semaphone = dispatch_semaphore_create(0);
            
            [account connect:^(NSError *error) {
                
                dispatch_semaphore_signal(semaphone);
            }];
            
            dispatch_semaphore_wait(semaphone, DISPATCH_TIME_FOREVER);
        }
        
        else {
            
            dispatch_semaphore_t semaphone = dispatch_semaphore_create(0);
            
            [account disconnect:^(NSError *error) {
                
                dispatch_semaphore_signal(semaphone);
            }];
            
            dispatch_semaphore_wait(semaphone, DISPATCH_TIME_FOREVER);
        }
    }
}

#pragma Endpoint Methods

-(void)setEndpointConfiguration:(SWEndpointConfiguration *)endpointConfiguration {
    
    [self willChangeValueForKey:@"endpointConfiguration"];
    _endpointConfiguration = endpointConfiguration;
    [self didChangeValueForKey:@"endpointConfiguration"];
}

-(void)setRingtone:(SWRingtone *)ringtone {
    
    [self willChangeValueForKey:@"ringtone"];
    
    if (_ringtone.isPlaying) {
        [_ringtone stop];
        _ringtone = ringtone;
        [_ringtone start];
    }
    
    else {
        _ringtone = ringtone;
    }
    
    [self didChangeValueForKey:@"ringtone"];
}

-(void)configure:(SWEndpointConfiguration *)configuration completionHandler:(void(^)(NSError *error))handler {
    
    //TODO add lock to this method
    
    self.endpointConfiguration = configuration;
    
    pj_status_t status;
    
    status = pjsua_create();
    
    if (status != PJ_SUCCESS) {
        
        NSError *error = [NSError errorWithDomain:@"Error creating pjsua" code:status userInfo:nil];
        
        if (handler) {
            handler(error);
        }
        
        return;
    }
    
    pjsua_config ua_cfg;
    pjsua_logging_config log_cfg;
    pjsua_media_config media_cfg;
    
    pjsua_config_default(&ua_cfg);
    pjsua_logging_config_default(&log_cfg);
    pjsua_media_config_default(&media_cfg);
    
    ua_cfg.cb.on_incoming_call = &SWOnIncomingCall;
    ua_cfg.cb.on_call_media_state = &SWOnCallMediaState;
    ua_cfg.cb.on_call_state = &SWOnCallState;
    ua_cfg.cb.on_call_transfer_status = &SWOnCallTransferStatus;
    ua_cfg.cb.on_call_replaced = &SWOnCallReplaced;
    ua_cfg.cb.on_reg_state = &SWOnRegState;
    ua_cfg.cb.on_nat_detect = &SWOnNatDetect;
    ua_cfg.cb.on_call_redirected = &SWOnCallRedirected;
    ua_cfg.cb.on_transport_state = &SWOnTransportState;
    ua_cfg.stun_host = [@"stun.sipgate.net" pjString];
    
    
    
    //
    ua_cfg.max_calls = (unsigned int)self.endpointConfiguration.maxCalls;
    
    log_cfg.level = (unsigned int)self.endpointConfiguration.logLevel;
    log_cfg.console_level = (unsigned int)self.endpointConfiguration.logConsoleLevel;
    log_cfg.log_filename = [self.endpointConfiguration.logFilename pjString];
    log_cfg.log_file_flags = (unsigned int)self.endpointConfiguration.logFileFlags;
    
    media_cfg.clock_rate = (unsigned int)self.endpointConfiguration.clockRate;
    media_cfg.snd_clock_rate = (unsigned int)self.endpointConfiguration.sndClockRate;
    
    
    status = pjsua_init(&ua_cfg, &log_cfg, &media_cfg);
    
    if (status != PJ_SUCCESS) {
        
        NSError *error = [NSError errorWithDomain:@"Error initializing pjsua" code:status userInfo:nil];
        
        if (handler) {
            handler(error);
        }
        
        return;
    }
    
    status = pjsip_endpt_register_module(pjsua_get_pjsip_endpt(), &sipgate_module);
    if (status != PJ_SUCCESS) {
        return;
    }
    
    status = pjnath_init();
    if (status != PJ_SUCCESS) {
        return;
    }
    
    
    //TODO autodetect port by checking transportId!!!!
    
    for (SWTransportConfiguration *transport in self.endpointConfiguration.transportConfigurations) {
        
        pjsua_transport_config transportConfig;
        pjsua_transport_id transportId;
        
        pjsua_transport_config_default(&transportConfig);
        
        pjsip_transport_type_e transportType = (pjsip_transport_type_e)transport.transportType;
        
        status = pjsua_transport_create(transportType, &transportConfig, &transportId);
        
        if (status != PJ_SUCCESS) {
            
            NSError *error = [NSError errorWithDomain:@"Error creating pjsua transport" code:status userInfo:nil];
            
            if (handler) {
                handler(error);
            }
            
            return;
        }
    }
    
    [self start:handler];
}

-(BOOL)hasTCPConfiguration {
    
    NSUInteger index = [self.endpointConfiguration.transportConfigurations indexOfObjectPassingTest:^BOOL(SWTransportConfiguration *obj, NSUInteger idx, BOOL *stop) {
        
        if (obj.transportType == SWTransportTypeTCP || obj.transportType == SWTransportTypeTCP6) {
            return YES;
            *stop = YES;
        }
        
        else {
            return NO;
        }
    }];
    
    if (index == NSNotFound) {
        return NO;
    }
    
    else {
        return YES;
    }
}

-(void)registerThread {
    
    if (pjsua_get_state() != PJSUA_STATE_RUNNING) {
        return;
    }
    
    if (!pj_thread_is_registered()) {
        pj_thread_register("swig", NULL, &thread);
    }
    
    else {
        thread = pj_thread_this();
    }
    
    if (!_pjPool) {
        dispatch_async(dispatch_get_main_queue(), ^{
            _pjPool = pjsua_pool_create("swig-pjsua", 512, 512);
        });
    }
}

-(void)start:(void(^)(NSError *error))handler {
    
    pj_status_t status = pjsua_start();
    
    if (status != PJ_SUCCESS) {
        
        NSError *error = [NSError errorWithDomain:@"Error starting pjsua" code:status userInfo:nil];
        
        if (handler) {
            handler(error);
        }
        
        return;
    }
    
    if (handler) {
        handler(nil);
    }
}

-(void)reset:(void(^)(NSError *error))handler {
    
    //TODO shutdown agent correctly. stop all calls, destroy all accounts
    
    for (SWAccount *account in self.accounts) {
        
        [account endAllCalls];
        
        dispatch_semaphore_t sema = dispatch_semaphore_create(0);
        
        [account disconnect:^(NSError *error) {
            dispatch_semaphore_signal(sema);
        }];
        
        dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
    }
    
    //    NSMutableArray *mutableArray = [self.accounts mutableCopy];
    //
    //    [mutableArray removeAllObjects];
    //
    //    self.accounts = mutableArray;
    
    //    pj_status_t status = pjsua_destroy();
    //
    //    if (status != PJ_SUCCESS) {
    //
    //        NSError *error = [NSError errorWithDomain:@"Error destroying pjsua" code:status userInfo:nil];
    //
    //        if (handler) {
    //            handler(error);
    //        }
    //
    //        return;
    //    }
    //
    //    if (handler) {
    //        handler(nil);
    //    }
}

#pragma Account Management

-(void)addAccount:(SWAccount *)account {
    
    if (![self lookupAccount:account.accountId]) {
        
        NSMutableArray *mutableArray = [self.accounts mutableCopy];
        [mutableArray addObject:account];
        
        self.accounts = mutableArray;
    }
}

-(void)removeAccount:(SWAccount *)account {
    
    if ([self lookupAccount:account.accountId]) {
        
        NSMutableArray *mutableArray = [self.accounts mutableCopy];
        [mutableArray removeObject:account];
        
        self.accounts = mutableArray;
    }
}

-(SWAccount *)lookupAccount:(NSInteger)accountId {
    
    NSUInteger accountIndex = [self.accounts indexOfObjectPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
        
        SWAccount *account = (SWAccount *)obj;
        
        if (account.accountId == accountId && account.accountId != PJSUA_INVALID_ID) {
            return YES;
        }
        
        return NO;
    }];
    
    if (accountIndex != NSNotFound) {
        return [self.accounts objectAtIndex:accountIndex]; //TODO add more management
    }
    
    else {
        return nil;
    }
}
-(SWAccount *)firstAccount {
    
    if (self.accounts.count > 0) {
        return self.accounts[0];
    }
    
    else {
        return nil;
    }
}


#pragma Block Parameters

-(void)setAccountStateChangeBlock:(void(^)(SWAccount *account))accountStateChangeBlock {
    
    _accountStateChangeBlock = accountStateChangeBlock;
}

-(void)setIncomingCallBlock:(void(^)(SWAccount *account, SWCall *call))incomingCallBlock {
    
    _incomingCallBlock = incomingCallBlock;
}

-(void)setCallStateChangeBlock:(void(^)(SWAccount *account, SWCall *call))callStateChangeBlock {
    
    _callStateChangeBlock = callStateChangeBlock;
}

-(void)setCallMediaStateChangeBlock:(void(^)(SWAccount *account, SWCall *call))callMediaStateChangeBlock {
    
    _callMediaStateChangeBlock = callMediaStateChangeBlock;
}

- (void) setMessageSentBlock: (SWMessageSentBlock) messageSentBlock {
    _messageSentBlock = messageSentBlock;
}

- (void) setNeedConfirmBlock: (SWNeedConfirmBlock) needConfirmBlock {
    _needConfirmBlock = needConfirmBlock;
}

- (void) setConfirmationBlock: (SWConfirmationBlock) confirmationBlock {
    _confirmationBlock = confirmationBlock;
}

- (void) setMessageStatusBlock: (SWMessageStatusBlock) messageStatusBlock {
    _messageStatusBlock = messageStatusBlock;
}

#pragma PJSUA Callbacks

static void SWOnRegState(pjsua_acc_id acc_id) {
    
    SWAccount *account = [[SWEndpoint sharedEndpoint] lookupAccount:acc_id];
    
    if (account) {
        
        [account accountStateChanged];
        
        if ([SWEndpoint sharedEndpoint].accountStateChangeBlock) {
            [SWEndpoint sharedEndpoint].accountStateChangeBlock(account);
        }
        
        if (account.accountState == SWAccountStateDisconnected) {
            [[SWEndpoint sharedEndpoint] removeAccount:account];
        }
    }
}

static void SWOnIncomingCall(pjsua_acc_id acc_id, pjsua_call_id call_id, pjsip_rx_data *rdata) {
    
    SWAccount *account = [[SWEndpoint sharedEndpoint] lookupAccount:acc_id];
    
    if (account) {
        
        SWCall *call = [SWCall callWithId:call_id accountId:acc_id inBound:YES];
        
        if (call) {
            
            [account addCall:call];
            
            [call callStateChanged];
            
            if ([SWEndpoint sharedEndpoint].incomingCallBlock) {
                [SWEndpoint sharedEndpoint].incomingCallBlock(account, call);
            }
        }
    }
}

static void SWOnCallState(pjsua_call_id call_id, pjsip_event *e) {
    
    pjsua_call_info callInfo;
    pjsua_call_get_info(call_id, &callInfo);
    
    SWAccount *account = [[SWEndpoint sharedEndpoint] lookupAccount:callInfo.acc_id];
    
    if (account) {
        
        SWCall *call = [account lookupCall:call_id];
        
        if (call) {
            
            [call callStateChanged];
            
            if ([SWEndpoint sharedEndpoint].callStateChangeBlock) {
                [SWEndpoint sharedEndpoint].callStateChangeBlock(account, call);
            }
            
            if (call.callState == SWCallStateDisconnected) {
                [account removeCall:call.callId];
            }
        }
    }
}

static void SWOnCallMediaState(pjsua_call_id call_id) {
    
    pjsua_call_info callInfo;
    pjsua_call_get_info(call_id, &callInfo);
    
    
    SWAccount *account = [[SWEndpoint sharedEndpoint] lookupAccount:callInfo.acc_id];
    
    if (account) {
        
        SWCall *call = [account lookupCall:call_id];
        
        if (call) {
            
            [call mediaStateChanged];
            
            if ([SWEndpoint sharedEndpoint].callMediaStateChangeBlock) {
                [SWEndpoint sharedEndpoint].callMediaStateChangeBlock(account, call);
            }
        }
    }
}

//TODO: implement these
static void SWOnCallTransferStatus(pjsua_call_id call_id, int st_code, const pj_str_t *st_text, pj_bool_t final, pj_bool_t *p_cont) {
    NSLog(@"%d", call_id);
}

static void SWOnCallReplaced(pjsua_call_id old_call_id, pjsua_call_id new_call_id) {
    
}

static void SWOnNatDetect(const pj_stun_nat_detect_result *res){
    
    NSLog(@"Nat detect: %s", res->nat_type_name);
}

static void SWOnTransportState (pjsip_transport *tp, pjsip_transport_state state, const pjsip_transport_state_info *info) {
    
    NSLog(@"%@ %@", tp, info);
}

static pjsip_redirect_op SWOnCallRedirected(pjsua_call_id call_id, const pjsip_uri *target, const pjsip_event *e){
    
    pjsip_redirect_op redirect = PJSIP_REDIRECT_ACCEPT;
    
    return redirect;
}

#pragma Setters/Getters

-(void)setPjPool:(pj_pool_t *)pjPool {
    
    _pjPool = pjPool;
}

-(void)setAccounts:(NSArray *)accounts {
    
    [self willChangeValueForKey:@"accounts"];
    _accounts = accounts;
    [self didChangeValueForKey:@"accounts"];
}

- (pj_bool_t) requestPackageProcessing: (pjsip_rx_data *)data {
    
    if (data == nil) {
        return PJ_FALSE;
    }
    
    if (pjsip_method_cmp(&data->msg_info.msg->line.req.method, &pjsip_register_method) == 0) {
        //        NSLog(@"data %@", data);
    } else if (pjsip_method_cmp(&data->msg_info.msg->line.req.method, &pjsip_message_method) == 0) {
        [self incomingMessage:data];
        return PJ_TRUE;
    } else if(pjsip_method_cmp(&data->msg_info.msg->line.req.method, &pjsip_subscribe_method) == 0) {
        //puts("subs");
    } else if (pjsip_method_cmp(&data->msg_info.msg->line.req.method, &pjsip_notify_method) == 0) {
        [self incomingNotify:data];
        return PJ_TRUE;
    } else if (pjsip_method_cmp(&data->msg_info.msg->line.req.method, &pjsip_invite_method) == 0) {
        //        [self incomingInvite:data];
    }
    return PJ_FALSE;
}

- (pj_bool_t) responsePackageProcessing:(pjsip_rx_data *)data {
    /* Разбираем - на какой запрос пришел ответ */
    NSString *call_id = [NSString stringWithPJString:data->msg_info.cid->id];
    int status = data->msg_info.msg->line.status.code;
    
    NSUInteger cseq = data->msg_info.cseq->cseq;
    
    NSUInteger sm_id = 0;
    
    pjsua_acc_id acc_id = pjsua_acc_find_for_incoming(data);
    SWAccount *account = [[SWEndpoint sharedEndpoint] lookupAccount:(int)acc_id];
    
    if (pjsip_method_cmp(&data->msg_info.cseq->method, &pjsip_register_method) == 0) {
        
        if (status == PJSIP_SC_NOT_FOUND && [account.accountConfiguration.code length] != 4){
            if (_needConfirmBlock) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    _needConfirmBlock(account, PJSIP_SC_NOT_FOUND);
                });
            }
            return PJ_FALSE;
        }
        
        if (status == PJSIP_SC_NOT_FOUND && [account.accountConfiguration.code length] == 4){
            return PJ_FALSE;
        }
        
        if (status == PJSIP_SC_UNAUTHORIZED && [account.accountConfiguration.code length] == 4) {
            [self processingFirstRegistration:account cseq:cseq];
            return PJ_FALSE;
        }
        
        if (status == PJSIP_SC_OK) {
            if (_confirmationBlock) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    _confirmationBlock(nil);
                });
            }
            return PJ_FALSE;
        }
    }
    
    
    if (pjsip_method_cmp(&data->msg_info.cseq->method, &pjsip_message_method) == 0) {
        /* Смотрим есть ли в сообщении заголовок SmID */
        pj_str_t  smid_hdr_str = pj_str((char *)"SMID");
        pjsip_generic_string_hdr* smid_hdr = (pjsip_generic_string_hdr*)pjsip_msg_find_hdr_by_name(data->msg_info.msg, &smid_hdr_str, nil);
        if (smid_hdr != nil) {
            sm_id = atoi(smid_hdr->hvalue.ptr);
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            _messageSentBlock(account, call_id, sm_id, status);
        });
        return PJ_TRUE;
    }
    
    return PJ_FALSE;
}

#pragma mark Входящее уведомление
- (void) incomingNotify:(pjsip_rx_data *)data {
    /* Смотрим о каком абоненте речь в сообщении */
    
    pjsua_acc_id acc_id = pjsua_acc_find_for_incoming(data);
    SWAccount *account = [[SWEndpoint sharedEndpoint] lookupAccount:(int)acc_id];

    
    pjsip_sip_uri *uri = (pjsip_sip_uri*)pjsip_uri_get_uri(data->msg_info.from->uri);
    NSString *abonent = [NSString stringWithPJString:uri->user];
    
    pj_str_t status_str    = pj_str((char *)"Status");
    pj_str_t delivered_str = pj_str((char *)"Event");
    
    /* Нужно разобраться что за уведомление пришло */
    /* заголовок Status: status_type      - статус абонента */
    /* заголовок Event: status            - статус сообщения SmID */
    
    /* Status? */
    pjsip_generic_string_hdr *event_hdr = (pjsip_generic_string_hdr*)pjsip_msg_find_hdr_by_name(data->msg_info.msg, &status_str, nil);
    if (event_hdr != nil) {
        //        if (!InDestrxoy) {
        int  status;
        char   buf[32] = {0};
        memcpy(buf, event_hdr->hvalue.ptr, event_hdr->hvalue.slen);
        status = atoi(buf);
#warning
        
        //        dispatch_async(dispatch_get_main_queue(), ^{
        //            if (_receiveAbonentStatusBlock) {
        //                _receiveAbonentStatusBlock(abonent, (NSInteger)status);
        //            }
        //        });
        [self sendSubmit:data withCode:PJSIP_SC_OK];
        //        delete abonent;
        return;
    }
    
    /* Event? */
    event_hdr = (pjsip_generic_string_hdr*)pjsip_msg_find_hdr_by_name(data->msg_info.msg, &delivered_str, nil);
    if (event_hdr != nil) {
        
        /* Получаем SmID */
        NSUInteger sm_id = 0;
        pj_str_t  smid_hdr_str = pj_str((char *)"SMID");
        pjsip_generic_string_hdr* smid_hdr = (pjsip_generic_string_hdr*)pjsip_msg_find_hdr_by_name(data->msg_info.msg, &smid_hdr_str, nil);
        if (smid_hdr != nil) {
            sm_id = atoi(smid_hdr->hvalue.ptr);
            NSUInteger event_value = atoi(event_hdr->hvalue.ptr);

            /* Передаем идентификатор и статус сообщения в GUI */
            dispatch_async(dispatch_get_main_queue(), ^{
                if (_messageStatusBlock) {
                    _messageStatusBlock(account, sm_id, event_value);
                }
            });
            
            [self sendSubmit:data withCode:PJSIP_SC_OK];
        }
        return;
    }
}

- (void) incomingMessage:(pjsip_rx_data *)data {
    if (data == nil) {
        return;
    }
    
    pjsip_sip_uri *uri = (pjsip_sip_uri*)pjsip_uri_get_uri(data->msg_info.to->uri);
    if (uri == nil) {
        [self sendSubmit:data withCode:PJSIP_SC_BAD_REQUEST];
        return;
    }
    
    /* Проверяем - нам ли сообщение */
    
    pjsua_acc_id acc_id = pjsua_acc_find_for_incoming(data);
    SWAccount *account = [[SWEndpoint sharedEndpoint] lookupAccount:(int)acc_id];
    
    
    NSString *to = [NSString stringWithPJString:uri->user];
    if (![account.accountConfiguration.username isEqualToString:to]) {
        [self sendSubmit:data withCode:PJSIP_SC_NOT_FOUND];
        return;
    }
    
    uri = (pjsip_sip_uri*)pjsip_uri_get_uri(data->msg_info.from->uri);
    
    NSString *abonent = [NSString stringWithPJString:uri->user];
    
    NSString *message_txt = [[NSString alloc] initWithBytes:data->msg_info.msg->body->data length:(NSUInteger)data->msg_info.msg->body->len encoding:NSUTF16LittleEndianStringEncoding];
    
    /* Выдираем Sm_ID */
    NSUInteger sm_id = 0;
    
    /* Смотрим есть ли в сообщении заголовок SmID */
    pj_str_t  smid_hdr_str = pj_str((char *)"SMID");
    pjsip_generic_string_hdr* smid_hdr = (pjsip_generic_string_hdr*)pjsip_msg_find_hdr_by_name(data->msg_info.msg, &smid_hdr_str, nil);
    if (smid_hdr != nil) {
        sm_id = atoi(smid_hdr->hvalue.ptr);
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if (_messageReceivedBlock) {
            _messageReceivedBlock(account, abonent, message_txt, (NSUInteger) sm_id);
        }
    });
    
    
    [self sendSubmit:data withCode:PJSIP_SC_OK];
    
    //    delete abonent;
    //    delete message_txt;
    //    delete to;
}


#pragma mark - Отправляем абоненту результат обработки его сообщения
- (BOOL) sendSubmit:(pjsip_rx_data *) message withCode:(int32_t) answer_code {
    pjsip_tx_data       *answer_msg;
    pj_status_t          status;
    bool                 ret_value = false;
    
    /* Готовим ответ абоненту о результате регистрации */
    status = pjsip_endpt_create_response(pjsua_get_pjsip_endpt(), message, answer_code, nil, &answer_msg);
    if (status == PJ_SUCCESS) {
        
        pj_str_t   smid_hdr_str = pj_str((char *)"SMID");
        pjsip_hdr *smid_hdr = (pjsip_hdr*)pjsip_msg_find_hdr_by_name(message->msg_info.msg, &smid_hdr_str, nil);
        if (smid_hdr != nil) {
            pjsip_msg_add_hdr(answer_msg->msg, smid_hdr);
        }
        
        /* Получаем адрес, куда мы должны отправить ответ */
        pjsip_response_addr  response_addr;
        status = pjsip_get_response_addr(answer_msg->pool, message, &response_addr);
        if (status == PJ_SUCCESS) {
            /* Отправляем ответ на регистрацию */
            status = pjsip_endpt_send_response(pjsua_get_pjsip_endpt(), &response_addr, answer_msg, nil, nil);
            if (status == PJ_SUCCESS) {
                ret_value = true;
            }
        }
    }
    if (status != PJ_SUCCESS) {
        NSLog(@"Error");
        //        [self parseError:status];
    }
    return ret_value;
}

- (BOOL) prepareRegisterData:(pjsip_authorization_hdr *) auth_hdr account:(SWAccount *) account {
    if (auth_hdr == nil) {
        return false;
    }
    
    auth_hdr->scheme = pj_str((char *)"digest");
    auth_hdr->credential.digest.algorithm = pj_str((char *)"md5");
    
    auth_hdr->credential.digest.username = [account.accountConfiguration.cryptedUsername pjString];
    
    auth_hdr->credential.digest.response = [account.accountConfiguration.cryptedPassword pjString];
    
    return true;
}


- (void) processingFirstRegistration:(SWAccount *) account cseq:(NSUInteger) cseq {
    /* Готовим ответную строку для сервера */
    pjsip_authorization_hdr* auth_hdr = pjsip_authorization_hdr_create(_pjPool);
    
    if (![self prepareRegisterData:auth_hdr account:account]) return;
    
    /* Создаем запрос на регистрацию с необходимыми данными */
    pj_status_t    status;
    pjsip_tx_data *tx_msg;
    pj_str_t       contact;
    
    pjsua_transport_info transport_info;
    pjsua_transport_get_info(0, &transport_info);
    
    contact = [[NSString stringWithFormat:@"<sip:%@@%@>;q=0.5;expires=%d", account.accountConfiguration.username, [NSString stringWithPJString:transport_info.local_name.host], 3600] pjString];
    
    pjsua_acc_info info;
    
    pjsua_acc_get_info(0, &info);
    
    NSLog(@"info %@", [NSString stringWithPJString:info.acc_uri]);
    
    //    pj_str_t local = [_LocalURI pjString];
    //    pj_str_t proxy = [_ProxyURI pjString];
    
    
    /* Создаем непосредственно запрос */
    status = pjsip_endpt_create_request(pjsua_get_pjsip_endpt(),
                                        &pjsip_register_method,
                                        &info.acc_uri, //proxy
                                        &info.acc_uri, //local
                                        &info.acc_uri, //local
                                        &contact, //contact
                                        nil,
                                        cseq,
                                        nil,
                                        &tx_msg);
    
    
    
    pjsip_msg_add_hdr(tx_msg->msg, (pjsip_hdr*)auth_hdr);
    
    if (status == PJ_SUCCESS) {
        status = pjsip_endpt_send_request(pjsua_get_pjsip_endpt(), tx_msg, 100, nil, nil);
    }
}



@end
