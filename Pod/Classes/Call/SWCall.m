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

@interface SWCall ()

@property (nonatomic, strong) UILocalNotification *notification;
@property (nonatomic, strong) SWRingback *ringback;

@end

@implementation SWCall

-(instancetype)init {
    
    NSAssert(NO, @"never call init directly use init with call id");
    
    return nil;
}

-(instancetype)initWithCallId:(NSUInteger)callId accountId:(NSInteger)accountId inBound:(BOOL)inbound {
    
    self = [super init];
    
    if (!self) {
        return nil;
    }
    
    _inbound = inbound;
    
    if (_inbound) {
        _missed = YES;
    }
    
    pjsua_call_info info;
    
    pj_status_t status = pjsua_call_get_info(callId, &info);
    
    if ((status == PJ_SUCCESS) && (info.rem_vid_cnt > 0 || (!_inbound && (info.setting.vid_cnt > 0)))) {
        _withVideo = YES;
    }
    
#ifdef DEBUG
#warning test
    NSLog(@"<--SWCall init-->call created with video? %@", _withVideo ? @"true" : @"false");
#else
#error test
#endif
    
    _callState = SWCallStateReady;
    _callId = callId;
    _accountId = accountId;
    
    //configure ringback
    
    _ringback = [SWRingback new];
    
    [self contactChanged];
    
    //TODO: move to account to fix multiple call problem
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(returnToBackground:) name:UIApplicationWillResignActiveNotification object:nil];
    
    return self;
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
            self.callState = SWCallStateReady;
        } break;
            
        case PJSIP_INV_STATE_INCOMING: {
            [[SWEndpoint sharedEndpoint].ringtone start];
            [self sendRinging];
            self.callState = SWCallStateIncoming;
        } break;
            
        case PJSIP_INV_STATE_CALLING: {
//            [self.ringback start]; //TODO probably not needed
            self.callState = SWCallStateCalling;
        } break;
            
        case PJSIP_INV_STATE_EARLY: {
            if (!self.inbound) {
                if (callInfo.last_status == PJSIP_SC_RINGING) {
                    [self.ringback start];
                } else if (callInfo.last_status == PJSIP_SC_PROGRESS) {
                    [self.ringback stop];
                }
            }
            
            self.callState = SWCallStateCalling;
        } break;
            
        case PJSIP_INV_STATE_CONNECTING: {
            self.callState = SWCallStateConnecting;
        } break;
            
        case PJSIP_INV_STATE_CONFIRMED: {
            [self.ringback stop];
            [[SWEndpoint sharedEndpoint].ringtone stop];
            
            self.callState = SWCallStateConnected;
        } break;
            
        case PJSIP_INV_STATE_DISCONNECTED: {
            [self.ringback stop];
            [[SWEndpoint sharedEndpoint].ringtone stop];
            
            self.callState = SWCallStateDisconnected;
        } break;
    }
    
    [self contactChanged];
}

-(void)mediaStateChanged {
    
    pjsua_call_info callInfo;
    pjsua_call_get_info((int)self.callId, &callInfo);
    
    if (callInfo.media_status == PJSUA_CALL_MEDIA_ACTIVE || callInfo.media_status == PJSUA_CALL_MEDIA_REMOTE_HOLD) {
        pjsua_conf_connect(callInfo.conf_slot, 0);
        pjsua_conf_connect(0, callInfo.conf_slot);
        if(self.withVideo && (callInfo.media_status == PJSUA_CALL_MEDIA_ACTIVE)) {
#warning нужно ли?
            //[self changeVideoWindow];
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
        
        pjsua_vid_win_info windowInfo;
        pj_status_t status;
        
        status = pjsua_vid_win_get_info(wid, &windowInfo);
        
        if(status == PJ_SUCCESS) {
            self.videoView = CFBridgingRelease(windowInfo.hwnd.info.ios.window);
            self.videoSize = size;
        }
    }
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
    
    SWContact *contect = [SWUriFormatter contactFromURI:remoteURI];
    
    self.contact = contect;
}

- (void) sendRinging {
    pj_status_t status;
    NSError *error;
    
    status = pjsua_call_answer((int)self.callId, PJSIP_SC_RINGING, NULL, NULL);
    
    if (status != PJ_SUCCESS) {
        
        error = [NSError errorWithDomain:@"Error send ringing" code:0 userInfo:nil];
    }
    
}


#pragma Call Management

-(void)answer:(void(^)(NSError *error))handler {
    
    pj_status_t status;
    NSError *error;
    
    status = pjsua_call_answer((int)self.callId, PJSIP_SC_OK, NULL, NULL);
    
    if (status != PJ_SUCCESS) {
        
        error = [NSError errorWithDomain:@"Error answering up call" code:0 userInfo:nil];
    }
    
    else {
        self.missed = NO;
    }
    
     AVAudioSession *audioSession = [AVAudioSession sharedInstance];
     
     NSError *overrideError;
     
     if ([audioSession overrideOutputAudioPort:AVAudioSessionPortOverrideNone error:&overrideError]) {
     }
     if ([audioSession setCategory:AVAudioSessionModeVoiceChat error:&overrideError]) {
     }
    
    if (handler) {
        handler(error);
    }
    
}

-(void)hangup:(void(^)(NSError *error))handler {
    
    pj_status_t status;
    NSError *error;
    
    if (self.callId != PJSUA_INVALID_ID && self.callState != SWCallStateDisconnected) {
        
        status = pjsua_call_hangup((int)self.callId, 0, NULL, NULL);
        
        if (status != PJ_SUCCESS) {
            
            error = [NSError errorWithDomain:@"Error hanging up call" code:0 userInfo:nil];
        }
        else {
            self.missed = NO;
        }
    }
    
    if (handler) {
        handler(error);
    }
    
    self.ringback = nil;
}

-(void)openSoundTrack:(void(^)(NSError *error))handler {
    
    pj_status_t status;
    NSError *error;
    
#warning experiment
    /*
    int capture_dev = 0;
    int playback_dev = 0;
    
    status = pjsua_get_snd_dev(&capture_dev, &playback_dev);
    status = pjsua_set_snd_dev(capture_dev, playback_dev);
    */
    
    status = pjsua_set_snd_dev(PJMEDIA_AUD_DEFAULT_CAPTURE_DEV, PJMEDIA_AUD_DEFAULT_PLAYBACK_DEV);
    
    if (status != PJ_SUCCESS) {
        error = [NSError errorWithDomain:@"Error open sound track" code:0 userInfo:nil];
    }
    
    
    if (handler) {
        handler(error);
    }
}

-(void)closeSoundTrack:(void(^)(NSError *error))handler {
    
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
    
    if (count == 0) {
        return;
    }
    
    pjmedia_vid_dev_info vdi;
    pj_status_t status;
    
    int currentDev = -1;
    int nextDev = PJMEDIA_VID_DEFAULT_CAPTURE_DEV;
    
    for (int i=0; i<count; ++i) {
        status = pjsua_vid_dev_get_info(i, &vdi);
        
        if ((status == PJ_SUCCESS) && (vdi.dir == PJMEDIA_DIR_CAPTURE)) {
            //Если дошли до колорбаров, настоящие камеры кончились
            if([[[NSString stringWithCString:vdi.name encoding:NSASCIIStringEncoding] lowercaseString] containsString:@"colorbar"]) {
                break;
            }
            
            if(pjsua_vid_dev_is_active (vdi.id)) {
                currentDev = vdi.id;
            }
            else {
                nextDev = vdi.id;
                
                //Если перед этим нашли текущее устройство видеозахвата, надо перейти на это.
                if(currentDev != -1) {
                    break;
                }
            }
        }
    }
    
    pjsua_call_vid_strm_op_param param;
    
    pjsua_call_vid_strm_op_param_default(&param);
    
    param.cap_dev = nextDev;
    
    pjsua_call_set_vid_strm(self.callId,
                            PJSUA_CALL_VID_STRM_CHANGE_CAP_DEV,
                            &param);
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

-(void)toggleSpeaker:(void(^)(NSError *error))handler {
    NSError *error = nil;
    if (!_speaker) {
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

@end
