//
//  SWCall.h
//  swig
//
//  Created by Pierre-Marc Airoldi on 2014-08-21.
//  Copyright (c) 2014 PeteAppDesigns. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SWCallProtocol.h"
#import "pjsua.h"
#import "SWRingback.h"
#import "SWRingtone.h"
#import "SWContact.h"

#import <UIKit/UIKit.h>

//TODO: move to 2 sublclasses (incoming/outgoing)

@class SWAccount;

typedef NS_ENUM(NSInteger, SWCallState) {
    SWCallStateReady,
    SWCallStateIncoming,
    SWCallStateCalling,
    SWCallStateConnecting,
    SWCallStateConnected,
    SWCallStateDisconnected,
    SWCallStateDisconnectRingtone
};

typedef NS_ENUM(NSInteger, SWMediaState) {
    SWMediaStateNone = PJSUA_CALL_MEDIA_NONE,
    SWMediaStateError = PJSUA_CALL_MEDIA_ERROR,
    SWMediaStateActive = PJSUA_CALL_MEDIA_ACTIVE,
    SWMediaStateLocalHold = PJSUA_CALL_MEDIA_LOCAL_HOLD,
    SWMediaStateRemoteHold = PJSUA_CALL_MEDIA_REMOTE_HOLD
};

typedef NS_ENUM(NSInteger, SWCallReason) {
    SWCallReasonSilence = -1,
    SWCallReasonUnknown = 0,
    SWCallReasonTerminatedRemote = 799
};

@interface SWCall : NSObject <SWCallProtocol, NSCopying, NSMutableCopying, AVAudioPlayerDelegate>

@property (nonatomic, readonly, strong) SWContact *contact;
@property (nonatomic, readonly) NSInteger callId;
@property (nonatomic, readonly) NSInteger accountId;
@property (nonatomic, readonly) SWCallState callState;
@property (nonatomic, readonly) SWMediaState mediaState;
@property (nonatomic, readonly) BOOL inbound;
@property (nonatomic, readonly) BOOL withVideo;
@property (nonatomic, readonly) BOOL missed;
@property (nonatomic, assign) BOOL speaker;
@property (nonatomic, assign) BOOL mute;

@property (nonatomic, strong) NSString *ctcallId;

@property (nonatomic, weak) UIView *videoView;
@property (nonatomic, weak) UIView *videoPreviewView;
@property (nonatomic, assign) CGSize videoSize;
@property (nonatomic, assign) CGSize videoPreviewSize;

@property (nonatomic, readonly) NSDate *date;
@property (nonatomic, readonly) NSTimeInterval duration; //TODO: update with timer
@property (nonatomic, assign) NSInteger hangupReason;

-(instancetype)initWithCallId:(NSUInteger)callId accountId:(NSInteger)accountId inBound:(BOOL)inbound;
+(instancetype)callWithId:(NSInteger)callId accountId:(NSInteger)accountId inBound:(BOOL)inbound;
+(instancetype)callBeforeSipForAccountId:(NSInteger)accountId inBound:(BOOL)inbound withVideo: (BOOL) withVideo forUri: (NSString *) uri;
-(void)initSipDataForCallId: (NSUInteger)callId;

-(SWAccount *)getAccount;

-(void)answer:(void(^)(NSError *error))handler;
-(void)hangup:(void(^)(NSError *error))handler;
-(void)hangupOnReason: (NSInteger) reason withCompletion:(void(^)(NSError *error))handler;
-(void)terminateWithCompletion:(void(^)(NSError *error))handler;

-(void)setHold:(void(^)(NSError *error))handler;
-(void)reinvite:(void(^)(NSError *error))handler;

- (void) setVideoEnabled: (BOOL) enabled;
- (void) changeVideoCaptureDevice;

//-(void)transferCall:(NSString *)destination completionHandler:(void(^)(NSError *error))handler;
//-(void)replaceCall:(SWCall *)call completionHandler:(void (^)(NSError *))handler;

-(void)toggleMute:(void(^)(NSError *error))handler;
-(void)toggleSpeaker:(void(^)(NSError *error))handler;
-(void)sendDTMF:(NSString *)dtmf handler:(void(^)(NSError *error))handler;

- (void) changeVideoWindowWithSize: (CGSize) size;

-(void)openSoundTrack:(void(^)(NSError *error))handler;
-(void)closeSoundTrack:(void(^)(NSError *error))handler;

+(void)openSoundTrack:(void(^)(NSError *error))handler;
+(void)closeSoundTrack:(void(^)(NSError *error))handler;

-(void)updateOverrideSpeaker;

@end
