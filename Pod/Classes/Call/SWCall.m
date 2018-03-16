//
//  SWCall.m
//  swig
//
//  Created by Pierre-Marc Airoldi on 2014-08-21.
//  Copyright (c) 2014 PeteAppDesigns. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "SWCall.h"
#import "SWAccount.h"
#import "SWEndpoint.h"
#import "SWUriFormatter.h"
#import "NSString+PJString.h"
#import "pjsua.h"
#import <AVFoundation/AVFoundation.h>
#import "SWMutableCall.h"
#import "SWAccountConfiguration.h"
#import "SWThreadManager.h"
#import "EWFileLogger.h"
#import <pjsua-lib/pjsua_internal.h>

@interface SWCall ()

@property (nonatomic, strong) UILocalNotification *notification;
@property (nonatomic, strong) SWRingback *ringback;
@property (nonatomic, strong) NSString *hangupReason;

#define PJMEDIA_NO_VID_DEVICE -100

@property (nonatomic, assign) pjmedia_vid_dev_index currentVideoCaptureDevice;

@end

@implementation SWCall

-(instancetype)init {
    
    NSAssert(NO, @"never call init directly use init with call id");
    
    return nil;
}

-(instancetype)initWithCallId:(NSUInteger)callId accountId:(NSInteger)accountId inBound:(BOOL)inbound {
    
    self = [self initBeforeSipWithAccountId:accountId inBound:inbound withVideo:NO forUri:nil];
    
    if (!self) {
        return nil;
    }
    
    [self initSipDataForCallId:callId];
    
    return self;
}

-(instancetype)initBeforeSipWithAccountId:(NSInteger)accountId inBound:(BOOL)inbound withVideo: (BOOL) withVideo forUri: (NSString *) uri {
    
    self = [super init];
    
    _callId = -2;
    _accountId = accountId;
    _inbound = inbound;
    
    self.currentVideoCaptureDevice = PJMEDIA_NO_VID_DEVICE;
    
    if (!self) {
        return nil;
    }
    
    if (_inbound) {
        _missed = YES;
    }
    
    _withVideo = withVideo;
    
    _mute = NO;
    _speaker = _withVideo && [SWCall isOnlySpeakerOutput];
    
    _callState = SWCallStateReady;
    
    if (uri) {
        [self contactSetForUri:uri];
    }
    
    //TODO: move to account to fix multiple call problem
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(returnToBackground:) name:UIApplicationWillResignActiveNotification object:nil];
    
    return self;
}

-(void)initSipDataForCallId: (NSUInteger)callId {
    
    _callId = callId;
    
    pjsua_call_info info;
    
    pj_status_t status = pjsua_call_get_info(_callId, &info);
    
    //configure ringback
    
    _ringback = [SWRingback new];
    
    [self contactChanged];
    
    if ((status == PJ_SUCCESS) && (info.rem_vid_cnt > 0 || (!_inbound && (info.setting.vid_cnt > 0)))) {
        _withVideo = YES;
    }
    
    _mute = NO;
    _speaker = _withVideo && [SWCall isOnlySpeakerOutput];
}

-(instancetype)copyWithZone:(NSZone *)zone {
    
    SWCall *call = [[SWCall allocWithZone:zone] init];
    call.contact = [self.contact copyWithZone:zone];
    call.callId = self.callId;
    call.accountId = self.accountId;
    call.callState = self.callState;
    call.mediaState = self.mediaState;
    call.inbound = self.inbound;
    call.missed = self.missed;
    call.date = [self.date copyWithZone:zone];
    call.duration = self.duration;
    
    return call;
}

-(instancetype)mutableCopyWithZone:(NSZone *)zone {
    
    SWMutableCall *call = [[SWMutableCall  allocWithZone:zone] init];
    call.contact = [self.contact copyWithZone:zone];
    call.callId = self.callId;
    call.accountId = self.accountId;
    call.callState = self.callState;
    call.mediaState = self.mediaState;
    call.inbound = self.inbound;
    call.missed = self.missed;
    call.date = [self.date copyWithZone:zone];
    call.duration = self.duration;
    
    return call;
}

+(instancetype)callWithId:(NSInteger)callId accountId:(NSInteger)accountId inBound:(BOOL)inbound {
    
    SWCall *call = [[SWCall alloc] initWithCallId:callId accountId:accountId inBound:inbound];
    
    return call;
}

+(instancetype)callBeforeSipForAccountId:(NSInteger)accountId inBound:(BOOL)inbound withVideo: (BOOL) withVideo forUri: (NSString *) uri {
    
    SWCall *call = [[SWCall alloc] initBeforeSipWithAccountId:accountId inBound:inbound withVideo:withVideo forUri:uri];
    
    return call;
}

-(void)createLocalNotification {
    
    if ([[[UIDevice currentDevice] systemVersion] floatValue] < 10.0) {
        _notification = [[UILocalNotification alloc] init];
        _notification.repeatInterval = 0;
        _notification.soundName = [[[SWEndpoint sharedEndpoint].ringtone.fileURL path] lastPathComponent];
        
        pj_status_t status;
        
        pjsua_call_info info;
        
        status = pjsua_call_get_info((int)self.callId, &info);
        
        
        
        if (status == PJ_TRUE) {
            _notification.alertBody = [NSString stringWithFormat:@"Incoming call from %@", self.contact.name];
        }
        
        else {
            _notification.alertBody = @"Incoming call";
        }
        
        _notification.alertAction = @"Activate app";
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [[UIApplication sharedApplication] presentLocalNotificationNow:_notification];
        });
    }
}

-(void)dealloc {
    
    if (_notification) {
        [[UIApplication sharedApplication] cancelLocalNotification:_notification];
    }
    
    if (_callState != SWCallStateDisconnected && _callId != PJSUA_INVALID_ID) {
#warning main thread!
        dispatch_async(dispatch_get_main_queue(), ^{
            pjsua_call_hangup((int)_callId, 0, NULL, NULL);
        });

    }
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationWillResignActiveNotification object:nil];
}

-(void)setCallId:(NSInteger)callId {
    
    [self willChangeValueForKey:@"callId"];
    _callId = callId;
    [self didChangeValueForKey:@"callId"];
}

-(void)setAccountId:(NSInteger)accountId {
    
    [self willChangeValueForKey:@"callId"];
    _accountId = accountId;
    [self didChangeValueForKey:@"callId"];
}

-(void)setCallState:(SWCallState)callState {
    
    [self willChangeValueForKey:@"callState"];
    _callState = callState;
    [self didChangeValueForKey:@"callState"];
}

-(void)setMediaState:(SWMediaState)mediaState {
    
    [self willChangeValueForKey:@"mediaState"];
    _mediaState = mediaState;
    [self didChangeValueForKey:@"mediaState"];
}

-(void)setRingback:(SWRingback *)ringback {
    
    [self willChangeValueForKey:@"ringback"];
    _ringback = ringback;
    [self didChangeValueForKey:@"ringback"];
}

-(void)setContact:(SWContact *)contact {
    
    [self willChangeValueForKey:@"contact"];
    _contact = contact;
    [self didChangeValueForKey:@"contact"];
}

-(void)setMissed:(BOOL)missed {
    
    [self willChangeValueForKey:@"missed"];
    _missed = missed;
    [self didChangeValueForKey:@"missed"];
}

-(void)setInbound:(BOOL)inbound {
    
    [self willChangeValueForKey:@"inbound"];
    _inbound = inbound;
    [self didChangeValueForKey:@"inbound"];
}

-(void)setDate:(NSDate *)date {
    
    [self willChangeValueForKey:@"date"];
    _date = date;
    [self didChangeValueForKey:@"date"];
}

-(void)setDuration:(NSTimeInterval)duration {
    
    [self willChangeValueForKey:@"duration"];
    _duration = duration;
    [self didChangeValueForKey:@"duration"];
}

-(void)callStateChanged {
    pjsua_call_info callInfo;
    pjsua_call_get_info((int)self.callId, &callInfo);
    
    switch (callInfo.state) {
        case PJSIP_INV_STATE_NULL: {
            [SWCall closeSoundTrack:nil];
            self.callState = SWCallStateReady;
        } break;
            
        case PJSIP_INV_STATE_INCOMING: {
            [SWCall closeSoundTrack:nil];
            [[SWEndpoint sharedEndpoint] startStandartRingtone];
            [self sendRinging];
            self.callState = SWCallStateIncoming;
            [self updateOverrideSpeaker];
        } break;
            
        case PJSIP_INV_STATE_CALLING: {
            //[SWCall closeSoundTrack:nil];
//            [self.ringback start]; //TODO probably not needed
            self.callState = SWCallStateCalling;
            [self updateOverrideSpeaker];
        } break;
            
        case PJSIP_INV_STATE_EARLY: {
            self.callState = SWCallStateCalling;
#warning experiment лишний раз?
            //[self updateOverrideSpeaker];
            if (!self.inbound) {
                [SWCall openSoundTrack:^(NSError *error) {
                    if (callInfo.last_status == PJSIP_SC_RINGING) {
                        [self.ringback start];
                    } else if (callInfo.last_status == PJSIP_SC_PROGRESS) {
                        [self.ringback stop];
                    }
                }];
            }
            
        } break;
            
        case PJSIP_INV_STATE_CONNECTING: {
            [SWCall closeSoundTrack:nil];
            [self.ringback stop];
            [[SWEndpoint sharedEndpoint].ringtone stop];
            
            self.callState = SWCallStateConnecting;
            [self updateOverrideSpeaker];
        } break;
            
        case PJSIP_INV_STATE_CONFIRMED: {
            
            NSLog(@"<--starting--> SWCallStateConnected");
            //[self reRunVideo];
            
            [SWCall openSoundTrack:nil];
            
            self.callState = SWCallStateConnected;
            [self updateMuteStatus];
            [self updateOverrideSpeaker];
            
            __weak typeof(self) weakSelf = self;
            #warning костыль
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
                [weakSelf updateOverrideSpeaker];
            });
        } break;
            
        case PJSIP_INV_STATE_DISCONNECTED: {
            [SWCall closeSoundTrack:nil];
            [self.ringback stop];
            [[SWEndpoint sharedEndpoint].ringtone stop];
            
            self.callState = SWCallStateDisconnected;
            [self disableVideoCaptureDevice];
            [self updateOverrideSpeaker];
        } break;
    }
    
    [self contactChanged];
}

- (void) reRunVideo {
    if (!self.withVideo) {
        return;
    }
    
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0);
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), queue, ^{
        
        SWThreadManager *thrManager = [SWEndpoint sharedEndpoint].threadFactory;
        
        NSThread *callThread = [thrManager getCallManagementThread];
        
        [thrManager runBlock:^{
            pjsua_call *call;
            
            pjsua_call_media *call_med;
            
            call = &pjsua_var.calls[self.callId];
            
            int med_idx = pjsua_call_get_vid_stream_idx(self.callId);
            pj_status_t status;
            
            call_med = &call->media[med_idx];
            pjmedia_vid_stream *stream = call_med->strm.v.stream;
            char errmsg[PJ_ERR_MSG_SIZE];
            
            if (!stream) {
                pjmedia_endpt *endpt = pjsua_var.med_endpt;
                pjmedia_vid_stream_info *info;
                
                status = pjmedia_vid_stream_create(endpt, NULL, &info, call_med->tp, NULL, &stream);
                
                
                if (status != PJ_SUCCESS) {
                    pj_strerror(status, errmsg, sizeof(errmsg));
                }
            }
            
            BOOL isRunning = pjmedia_vid_stream_is_running(stream, PJMEDIA_DIR_ENCODING);
            
            if(!isRunning) {
                pjmedia_vid_stream_start(stream);
            }
        } onThread:callThread wait:NO];
        
    });
}

-(void)mediaStateChanged {
    
    pjsua_call_info callInfo;
    pjsua_call_get_info((int)self.callId, &callInfo);
    
    if (callInfo.media_status == PJSUA_CALL_MEDIA_ACTIVE || callInfo.media_status == PJSUA_CALL_MEDIA_REMOTE_HOLD) {
        pjsua_conf_connect(callInfo.conf_slot, 0);
        pjsua_conf_connect(0, callInfo.conf_slot);
        if(self.withVideo && (callInfo.media_status == PJSUA_CALL_MEDIA_ACTIVE)) {
#warning включать видео здесь
            //[self setVideoEnabled:true];
            [self sendVideoKeyframe];
        }
    }
    
    pjsua_call_media_status mediaStatus = callInfo.media_status;
    
    self.mediaState = (SWMediaState)mediaStatus;
}

- (void) changeVideoWindowWithSize: (CGSize) size {
    int vid_idx = pjsua_call_get_vid_stream_idx((int)self.callId);
    pjsua_vid_win_id wid;
    
    if (vid_idx >= 0) {
        pjsua_call_info ci;
        
        pjsua_call_get_info((int)self.callId, &ci);
        wid = ci.media[vid_idx].stream.vid.win_in;
        
        //Если окно не инициализировано, wid = -1
        if (wid == PJSUA_INVALID_ID) {
            return;
        }
        
        pjsua_vid_win_info windowInfo;
        pj_status_t status;
        
        status = pjsua_vid_win_get_info(wid, &windowInfo);
        
        if(status == PJ_SUCCESS) {
            self.videoView = (__bridge UIView *)windowInfo.hwnd.info.ios.window;
            self.videoSize = size;
        }
    }
    
    if (self.currentVideoCaptureDevice == PJMEDIA_NO_VID_DEVICE) {
        self.currentVideoCaptureDevice = PJMEDIA_VID_DEFAULT_CAPTURE_DEV;
    }
    
    [self setVideoCaptureDevice:self.currentVideoCaptureDevice];
}

-(SWAccount *)getAccount {
    
    pjsua_call_info info;
    pjsua_call_get_info((int)self.callId, &info);
    
    return [[SWEndpoint sharedEndpoint] lookupAccount:info.acc_id];
}

-(void)contactChanged {
    
    pjsua_call_info info;
    pjsua_call_get_info((int)self.callId, &info);
    
    NSString *remoteURI = [NSString stringWithPJString:info.remote_info];
    
    [self contactSetForUri:remoteURI];
}

-(void)contactSetForUri: (NSString *) remoteURI {
    
    SWContact *contect = [SWUriFormatter contactFromURI:remoteURI];
    
    self.contact = contect;
}

- (void) sendRinging {
    
#warning experiment гудки должен слать сервер
    //return;
    
    SWEndpoint *endpoint = [SWEndpoint sharedEndpoint];
    
    NSThread *callThread = [endpoint.threadFactory getCallManagementThread];
    
    if([NSThread currentThread] != callThread) {
        [self performSelector:@selector(sendRinging) onThread:callThread withObject:nil waitUntilDone:NO];
        return;
    }
        
    pj_status_t status;
    NSError *error;
    
    status = pjsua_call_answer((int)self.callId, PJSIP_SC_RINGING, NULL, NULL);
    
    if (status != PJ_SUCCESS) {
        
        error = [NSError errorWithDomain:@"Error send ringing" code:0 userInfo:nil];
    }
    
}


#pragma Call Management

-(void)answer:(void(^)(NSError *error))handler {
    
    SWEndpoint *endpoint = [SWEndpoint sharedEndpoint];
    
    NSThread *callThread = [endpoint.threadFactory getCallManagementThread];
    
    if([NSThread currentThread] != callThread) {
        [self performSelector:@selector(answer:) onThread:callThread withObject:handler waitUntilDone:NO];
        return;
    }
    
    pj_status_t status;
    NSError *error;
    
#warning отвечать без видео, если звонок с коллкита с заблокированного экрана?
    pjsua_call_setting call_setting;
    pjsua_call_setting_default(&call_setting);
    call_setting.vid_cnt=1;
    pjsua_call_answer2((int)self.callId, &call_setting, PJSIP_SC_OK, NULL, NULL);
    
    //status = pjsua_call_answer((int)self.callId, PJSIP_SC_OK, NULL, NULL);
    
    if (status != PJ_SUCCESS) {
        
        error = [NSError errorWithDomain:@"Error answering up call" code:0 userInfo:nil];
    }
    
    else {
        self.missed = NO;
    }
    
    //[self updateOverrideSpeaker];
    
    if (handler) {
        handler(error);
    }
    
}

-(void)terminateWithCompletion:(void(^)(NSError *error))handler {
    if (self.callState == SWCallStateReady) {
        _callState = SWCallStateDisconnected;
        [[SWEndpoint sharedEndpoint] runCallStateChangeBlockForCall:self setCode:PJSIP_SC_TSX_TRANSPORT_ERROR];
        if (handler) {
            handler(nil);
        }
    }
    else {
        [self hangup:handler];
    }
}

-(void)hangup:(void(^)(NSError *error))handler {
    
    SWThreadManager *thrManager = [SWEndpoint sharedEndpoint].threadFactory;
    NSThread *callThread = [thrManager getCallManagementThread];
    
    if ([NSThread currentThread] != callThread) {
        [self performSelector:@selector(hangup:) onThread:callThread withObject:handler waitUntilDone:NO];
        return;
    }
    
    typeof (self) slf = self;
    
    pj_status_t status;
    NSError *error;
    
    
    //Если попали сюда из hangupOnReason, сгенерируем структуру, добавим в хедер и очистим свойство
    
     pjsua_msg_data *msg_data = NULL;
     
     NSString *reason = slf.hangupReason;
     
    if (reason != nil) {
        msg_data = malloc(sizeof(pjsua_msg_data));
        slf.hangupReason = nil;
        pjsua_msg_data_init(msg_data);
        
        pj_str_t hname = pj_str((char *)[@"X-Reason" UTF8String]);
        char * headerValue=(char *)[reason UTF8String];
        pj_str_t hvalue = pj_str(headerValue);
        
        pj_pool_t *pool;
        pool = pjsua_pool_create("reasonheader", 512, 512);
        
        pjsip_generic_string_hdr* add_hdr = pjsip_generic_string_hdr_create(pool, &hname, &hvalue);
        pj_list_push_back(&(*msg_data).hdr_list, add_hdr);
    }
    else {
        msg_data = NULL;
    }
    
    SWCall *cll = slf;
    
    NSString *test = slf.hangupReason;
    NSInteger callid = slf.callId;
    SWCallState callState = slf.callState;
    
    
    if (slf.callId != PJSUA_INVALID_ID && slf.callState != SWCallStateDisconnected) {
        
        status = pjsua_call_hangup((int)slf.callId, 0, NULL, msg_data);
        //status = pjsua_call_hangup((int)self.callId, 0, NULL, NULL);
        
        if (status != PJ_SUCCESS) {
            
            error = [NSError errorWithDomain:@"Error hanging up call" code:0 userInfo:nil];
        }
        else {
            slf.missed = NO;
        }
    }
    
    if (handler) {
        handler(error);
    }
    
    slf.ringback = nil;
}

-(void)hangupOnReason: (NSString *)reason withCompletion:(void(^)(NSError *error))handler {
    self.hangupReason = reason;
    
    SWThreadManager *thrManager = [SWEndpoint sharedEndpoint].threadFactory;
    NSThread *callThread = [thrManager getCallManagementThread];
    
    [self performSelector:@selector(hangup:) onThread:callThread withObject:handler waitUntilDone:NO];
}

-(void)openSoundTrack:(void(^)(NSError *error))handler {
    
    [SWCall openSoundTrack:handler];
}

-(void)closeSoundTrack:(void(^)(NSError *error))handler {
    [SWCall closeSoundTrack:handler];
}

+(void)openSoundTrack:(void(^)(NSError *error))handler {
    
    SWThreadManager *thrManager = [SWEndpoint sharedEndpoint].threadFactory;
    NSThread *callThread = [thrManager getCallManagementThread];
    
    if ([NSThread currentThread] != callThread) {
        [self performSelector:@selector(openSoundTrack:) onThread:callThread withObject:handler waitUntilDone:NO];
        return;
    }
    
    NSLog(@"<--starting call--> openSoundTrack");
    
    pj_status_t status;
    NSError *error;
    
    status = pjsua_set_snd_dev(PJMEDIA_AUD_DEFAULT_CAPTURE_DEV, PJMEDIA_AUD_DEFAULT_PLAYBACK_DEV);
    
    if (status != PJ_SUCCESS) {
        error = [NSError errorWithDomain:@"Error open sound track" code:0 userInfo:nil];
    }
    
    
    if (handler) {
        handler(error);
    }
}

+(void)closeSoundTrack:(void(^)(NSError *error))handler {
    NSLog(@"<--starting call--> closeSoundTrack");
    
    SWThreadManager *thrManager = [SWEndpoint sharedEndpoint].threadFactory;
    NSThread *callThread = [thrManager getCallManagementThread];
    
    if ([NSThread currentThread] != callThread) {
        [self performSelector:@selector(closeSoundTrack:) onThread:callThread withObject:handler waitUntilDone:NO];
        return;
    }
    
    NSError *error;
    
    pjsua_set_no_snd_dev();
    
    //pjsua_set_no_snd_dev возвращает не статус!
    /*
     pj_status_t status;
     NSError *error;
     
    status = pjsua_set_no_snd_dev();
    
    if (status != PJ_SUCCESS) {
        error = [NSError errorWithDomain:@"Error close sound track" code:0 userInfo:nil];
    }
     */
    
    if (handler) {
        handler(error);
    }
}

-(void)setHold:(void(^)(NSError *error))handler {
    pj_status_t status;
    NSError *error;
    
    if (self.callId != PJSUA_INVALID_ID && self.callState != SWCallStateDisconnected) {

        pjsua_set_no_snd_dev();

        status = pjsua_call_set_hold((int)self.callId, NULL);
        
        if (status != PJ_SUCCESS) {
            
            error = [NSError errorWithDomain:@"Error holding call" code:0 userInfo:nil];
            
        }
        
    }
    
    if (handler) {
        handler(error);
    }

}

#pragma mark video

- (void) setVideoEnabled: (BOOL) enabled {
    if (enabled) {
        pjsua_call_set_vid_strm(self.callId, PJSUA_CALL_VID_STRM_ADD, NULL);
    }
    else {
        pjsua_call_set_vid_strm(self.callId, PJSUA_CALL_VID_STRM_REMOVE, NULL);
    }
}

- (void) changeVideoCaptureDevice {
    unsigned count = pjsua_vid_dev_count();
    
    if ((count == 0) || (self.callState != SWCallStateConnected)) {
        return;
    }
    
    pjmedia_vid_dev_info vdi;
    pj_status_t status;
    
    pjmedia_vid_dev_index currentDev = PJMEDIA_NO_VID_DEVICE;
    pjmedia_vid_dev_index nextDev = PJMEDIA_VID_DEFAULT_CAPTURE_DEV;
    
    for (pjmedia_vid_dev_index i=0; i<count; ++i) {
        status = pjsua_vid_dev_get_info(i, &vdi);
        
        if ((status == PJ_SUCCESS) && (vdi.dir == PJMEDIA_DIR_CAPTURE)) {
            //Если дошли до колорбаров, настоящие камеры кончились
            if([[[NSString stringWithCString:vdi.name encoding:NSASCIIStringEncoding] lowercaseString] containsString:@"colorbar"]) {
                break;
            }
            
            //pjsua_vid_dev_is_active (vdi.id) лучше не использовать
            //активными могут остаться несколько окон
            if(vdi.id == self.currentVideoCaptureDevice) {
                currentDev = vdi.id;
            }
            else {
                nextDev = vdi.id;
                
                //Если перед этим нашли текущее устройство видеозахвата, надо перейти на это.
                if(currentDev != PJMEDIA_NO_VID_DEVICE) {
                    
                    break;
                }
            }
        }
    }
    
    //Почему-то после этого pjsua_vid_dev_is_active всё равно тру, зато окно превью пропадает насовсем
    /*
    if(currentDev != PJMEDIA_NO_VID_DEVICE) {
        //Отключаем захват превью
        
        pjsua_vid_preview_stop(currentDev);
    }
     */
    
    [self setVideoCaptureDevice:nextDev];
}

- (void) disableVideoCaptureDevice {
    unsigned count = pjsua_vid_dev_count();
    
    if (count == 0) {
        return;
    }
    
    pjmedia_vid_dev_info vdi;
    pj_status_t status;
    
    pjmedia_vid_dev_index currentDev = PJMEDIA_NO_VID_DEVICE;
    
    //Найдём все активные видеоустройства
    for (pjmedia_vid_dev_index i=0; i<count; ++i) {
        status = pjsua_vid_dev_get_info(i, &vdi);
        
        if ((status == PJ_SUCCESS) && (vdi.dir == PJMEDIA_DIR_CAPTURE)) {
            //Если дошли до колорбаров, настоящие камеры кончились
            if([[[NSString stringWithCString:vdi.name encoding:NSASCIIStringEncoding] lowercaseString] containsString:@"colorbar"]) {
                break;
            }
            
            if(pjsua_vid_dev_is_active (vdi.id)) {
                currentDev = vdi.id;
                
                //Отключаем захват превью и его окно
                pjsua_vid_win_id wid;
                wid = pjsua_vid_preview_get_win(currentDev);
                if (wid != PJSUA_INVALID_ID) {
                    pjsua_vid_win_set_show(wid, PJ_FALSE);
                }
                
                pjsua_vid_preview_stop(currentDev);
            }
        }
    }
    
    self.currentVideoCaptureDevice = PJMEDIA_NO_VID_DEVICE;
    self.videoPreviewView = nil;
}

- (void) setVideoCaptureDevice: (int) devId {
    SWAccount *account = [self getAccount];
    
    [account configureVideoCodecForDevice: devId];
    
    pjsua_call_vid_strm_op_param param;
    
    pjsua_call_vid_strm_op_param_default(&param);
    
    param.cap_dev = devId;
    
    pjsua_call_set_vid_strm(self.callId,
                            PJSUA_CALL_VID_STRM_CHANGE_CAP_DEV,
                            &param);
    
    pjsua_vid_preview_param prvParam;
    
    pjsua_vid_preview_param_default(&prvParam);
    prvParam.wnd_flags = PJMEDIA_VID_DEV_WND_BORDER |
    PJMEDIA_VID_DEV_WND_RESIZABLE;
    
    pjsua_vid_preview_start(devId,&prvParam);
    
    pjsua_vid_win_id wnd = pjsua_vid_preview_get_win(devId);
    
    self.currentVideoCaptureDevice = devId;
    
    pjsua_vid_win_info windowInfo;
    
    pj_status_t status = pjsua_vid_win_get_info(wnd, &windowInfo);
    
    if(status != PJ_SUCCESS) return;
    
    if ((self.videoPreviewSize.width > 0) && (self.videoPreviewSize.height > 0)) {
        pjmedia_rect_size size;
        
        CGSize outputVideoSize = account.currentOutputVideoSize;
        
        CGFloat aspect = outputVideoSize.width / outputVideoSize.height;
        
        size.w = (int)self.videoPreviewSize.width;
#warning игнорируется переданная высота. Может быть, использовать как ограничения?
        size.h = (int)self.videoPreviewSize.width / aspect;
        
        pjsua_vid_win_set_size(wnd, &size);
    }
    else {
        pjsua_vid_win_set_show(wnd, PJ_FALSE);
    }
    
    self.videoPreviewView = (__bridge UIView *)windowInfo.hwnd.info.ios.window;
}

- (void) sendVideoKeyframe {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        __weak typeof(self) weakSelf = self;
        for(int i = 0; i < 5; i++) {
            if(!weakSelf) return;
            
            [NSThread sleepForTimeInterval:1];
#warning UI thread
            dispatch_async(dispatch_get_main_queue(), ^{
                pj_status_t status;
                status = pjsua_call_set_vid_strm(weakSelf.callId, PJSUA_CALL_VID_STRM_SEND_KEYFRAME, NULL);
            });
        }
    });
}

-(void)reinvite:(void(^)(NSError *error))handler {
    pj_status_t status;
    NSError *error;
    
    if (self.callId != PJSUA_INVALID_ID && self.callState != SWCallStateDisconnected) {

#warning experiment
        /*
         int capture_dev = 0;
         int playback_dev = 0;
         
         status = pjsua_get_snd_dev(&capture_dev, &playback_dev);
         status = pjsua_set_snd_dev(capture_dev, playback_dev);
         */
        
        status = pjsua_set_snd_dev(PJMEDIA_AUD_DEFAULT_CAPTURE_DEV, PJMEDIA_AUD_DEFAULT_PLAYBACK_DEV);
        
        status = pjsua_call_reinvite((int)self.callId, PJ_TRUE, NULL);
        
        if (status != PJ_SUCCESS) {
            error = [NSError errorWithDomain:@"Error reinvite call" code:0 userInfo:nil];
        }
    }
    
    if (handler) {
        handler(error);
    }
}

//-(void)transferCall:(NSString *)destination completionHandler:(void(^)(NSError *error))handler;
//-(void)replaceCall:(SWCall *)call completionHandler:(void (^)(NSError *))handler;

- (void)setMute:(BOOL)mute {
    if (mute == _mute) {
        return;
    }
    
    _mute = mute;
    
    if(self.callState == SWCallStateConnected) {
        [self updateMuteStatus];
    }
}

- (void) updateMuteStatus {
    
    NSLog(@"<--mute--> value:%@", _mute ? @"true" : @"false");
    pjsua_call_info callInfo;
    pjsua_call_get_info((int)self.callId, &callInfo);
    
    pj_status_t status;
    NSError *error = nil;
    if (_mute) {
        status = pjsua_conf_disconnect(0, callInfo.conf_slot);
        if (status != PJ_SUCCESS) {
            error = [NSError errorWithDomain:@"Error mute" code:0 userInfo:nil];
            _mute = NO;
        }
    }
    
    else {
        status = pjsua_conf_connect(0, callInfo.conf_slot);
        if (status != PJ_SUCCESS) {
            error = [NSError errorWithDomain:@"Error unmute" code:0 userInfo:nil];
            _mute = YES;
        }
        
    }
}

-(void)toggleMute:(void(^)(NSError *error))handler {
    
    pjsua_call_info callInfo;
    pjsua_call_get_info((int)self.callId, &callInfo);
    
    pj_status_t status;
    NSError *error = nil;
    if (!_mute) {
        status = pjsua_conf_disconnect(0, callInfo.conf_slot);
        _mute = YES;
        if (status != PJ_SUCCESS) {
            error = [NSError errorWithDomain:@"Error mute" code:0 userInfo:nil];
        }

    }
    
    else {
        status = pjsua_conf_connect(0, callInfo.conf_slot);
        _mute = NO;
        if (status != PJ_SUCCESS) {
            error = [NSError errorWithDomain:@"Error unmute" code:0 userInfo:nil];
        }

    }
    handler(error);
}

- (void)setSpeaker:(BOOL)speaker {
    if (_speaker == speaker) return;
    
    _speaker = speaker;
    
    [self updateOverrideSpeaker];
}

- (void) updateOverrideSpeaker {
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    NSString *sessionMode = AVAudioSessionModeDefault;
    
    BOOL speaker = NO;
    BOOL sessionActive = YES;
    
    switch (self.callState) {
        case SWCallStateReady:
            speaker = YES;
            break;
        case SWCallStateIncoming:
            speaker = YES;
            break;
        case SWCallStateCalling:
            speaker = _speaker || self.inbound;
            break;
        case SWCallStateConnecting:
            sessionActive = NO;
            speaker = _speaker;
            break;
        case SWCallStateConnected:
            sessionActive = YES;
            speaker = _speaker;
            //sessionMode = speaker ? AVAudioSessionModeVideoChat : AVAudioSessionModeDefault;
            break;
            
        case SWCallStateDisconnected:
            sessionActive = NO;
            speaker = NO;
            break;
        default:
            break;
    }
    
    NSError *error = nil;
    
    NSTimeInterval bufferDuration = .005;
    [audioSession setPreferredIOBufferDuration:bufferDuration error:&error];
    [audioSession setPreferredSampleRate:44100 error:&error];
    
    [audioSession setMode:sessionMode error:&error];
    
    //NSLog(@"<--speaker--> value:%@", speaker ? @"true" : @"false");
    if (speaker) {
        [audioSession setCategory:AVAudioSessionCategoryPlayAndRecord withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker|AVAudioSessionCategoryOptionDuckOthers error:&error];
    }
    
    else {
        
        [audioSession setCategory:AVAudioSessionCategoryPlayAndRecord withOptions:AVAudioSessionCategoryOptionDuckOthers error:&error];
        
        if (error) {
            NSLog(@"<--speaker--> setCategory error: %@", error);
        }
    }
    
    for (AVAudioSessionPortDescription* desc in [audioSession availableInputs]) {
        NSString *porttype = [desc portType];
        NSString *portname = [desc portName];
        NSArray<AVAudioSessionDataSourceDescription *> *dataSources = desc.dataSources;
        
        if (!([porttype isEqualToString:AVAudioSessionPortBuiltInSpeaker] || [porttype isEqualToString:AVAudioSessionPortBuiltInReceiver])) {
            return;
        }
        
        AVAudioSessionDataSourceDescription *frontMicrophone;
        AVAudioSessionDataSourceDescription *topMicrophone;
        AVAudioSessionDataSourceDescription *bottomMicrophone;
        
        //NSLog(@"<--speaker--> available input porttype: %@ : %@. DataSources: %d", porttype, portname, dataSources.count);
        //NSLog(@"<--speaker--> selectedDataSource:%@. location=%@; orientation=%@; selectedPolarPattern: %@", frontMicrophone.dataSourceName, frontMicrophone.location, frontMicrophone.orientation, frontMicrophone.selectedPolarPattern);
        
        
        for(AVAudioSessionDataSourceDescription* source in dataSources) {
            //NSLog(@"<--speaker--> --- dataSource: %@", source);
            if ([source.orientation isEqualToString:AVAudioSessionOrientationFront]) {
                frontMicrophone = source;
            }
            else if ([source.orientation isEqualToString:AVAudioSessionOrientationTop]) {
                topMicrophone = source;
            }
            else if ([source.orientation isEqualToString:AVAudioSessionOrientationBottom]) {
                bottomMicrophone = source;
            }
        }
        
        if (speaker) {
            //Если нашли передний микрофон, используем его (на 6 и выше?), иначе верхний (на 4s и на 5-х?)
            if (frontMicrophone) {
                [frontMicrophone setPreferredPolarPattern:AVAudioSessionPolarPatternOmnidirectional error:&error];
                
                [audioSession setInputDataSource:frontMicrophone error:&error];
            }
            else if (topMicrophone) {
                [topMicrophone setPreferredPolarPattern:AVAudioSessionPolarPatternOmnidirectional error:&error];
                
                [audioSession setInputDataSource:topMicrophone error:&error];
            }
        }
        else {
            //переключаемся на нижний микрофон
            if (bottomMicrophone) {
                [bottomMicrophone setPreferredPolarPattern:AVAudioSessionPolarPatternOmnidirectional error:&error];
                
                [audioSession setInputDataSource:bottomMicrophone error:&error];
            }
        }
    }
    
    /*
    NSLog(@"<--speaker--> audioSession.category:%@", audioSession.category);
    NSLog(@"<--speaker--> audioSession.mode:%@", audioSession.mode);
    NSLog(@"<--speaker--> audioSession.inputGain:%f", audioSession.inputGain);
    NSLog(@"<--speaker--> audioSession.categoryOptions:%d", audioSession.categoryOptions);
    */
}

#warning deprecated
-(void)toggleSpeaker:(void(^)(NSError *error))handler {
    NSError *error = nil;
    if (!_speaker) {
        [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayAndRecord error:&error];
        [[AVAudioSession sharedInstance] overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:&error];
        _speaker = YES;
    }
    
    else {
        [[AVAudioSession sharedInstance] overrideOutputAudioPort:AVAudioSessionPortOverrideNone error:&error];
        _speaker = NO;
    }
    handler(error);
}

-(void)sendDTMF:(NSString *)dtmf handler:(void(^)(NSError *error))handler {
    
    pj_status_t status;
    NSError *error;
    pj_str_t digits = [dtmf pjString];
    
    
    status = pjsua_call_dial_dtmf((int)self.callId, &digits);
    
    if (status != PJ_SUCCESS) {
        error = [NSError errorWithDomain:@"Error sending DTMF" code:0 userInfo:nil];
    }
    
    if (handler) {
        handler(error);
    }
}

#pragma Application Methods

-(void)returnToBackground:(NSNotificationCenter *)notification {
    
    if (self.callState == SWCallStateIncoming) {
        [self createLocalNotification];
    }
}

+ (BOOL)isOnlySpeakerOutput {
    AVAudioSessionRouteDescription* route = [[AVAudioSession sharedInstance] currentRoute];
    for (AVAudioSessionPortDescription* desc in [route outputs]) {
        NSString *porttype = [desc portType];
        if (!([porttype isEqualToString:AVAudioSessionPortBuiltInSpeaker] || [porttype isEqualToString:AVAudioSessionPortBuiltInReceiver]))
            return NO;
    }
    return YES;
}

@end
