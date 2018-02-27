//
//  SWRingback.m
//  swig
//
//  Created by Pierre-Marc Airoldi on 2014-08-27.
//  Copyright (c) 2014 PeteAppDesigns. All rights reserved.
//

#import "SWRingback.h"
#import "SWEndpoint.h"
#import "SWEndpointConfiguration.h"
#import "SWThreadManager.h"
#import "Logger.h"

#define kSWRingbackFrequency1 440
#define kSWRingbackFrequency2 480
#define kSWRingbackOnDuration 2000
#define kSWRingbackOffDuration 4000
#define kSWRingbackCount 1
#define kSWRingbackInterval 4000

#define kSWAudioFramePtime PJSUA_DEFAULT_AUDIO_FRAME_PTIME
#define kSWChannelCount 1

@implementation SWRingback

-(instancetype)init {
    
    self = [super init];
    
    if (!self) {
        return nil;
    }
    
    SWEndpoint *endpoint = [SWEndpoint sharedEndpoint];
    
    pj_status_t status;
    
    pjmedia_tone_desc tone[kSWRingbackCount];
    pj_str_t name = pj_str("tone");
    
    //TODO make ptime and channel count not constant?

    NSUInteger samplesPerFrame = (kSWAudioFramePtime * endpoint.endpointConfiguration.clockRate * kSWChannelCount) / 1000;
    
    pj_pool_t *pool = [endpoint pjPool];
    
    status = pjmedia_tonegen_create2(pool, &name, (unsigned int)endpoint.endpointConfiguration.clockRate, kSWChannelCount, (unsigned int)samplesPerFrame, 16, PJMEDIA_TONEGEN_LOOP, &_ringbackPort);
    
    if (status != PJ_SUCCESS) {
        DDLogDebug(@"Error creating ringback tones");
        return nil;
    }
    
    pj_bzero(&tone, sizeof(tone));
    
    for (int i = 0; i < kSWRingbackCount; ++i) {
        tone[i].freq1 = kSWRingbackFrequency1;
        tone[i].freq2 = kSWRingbackFrequency2;
        tone[i].on_msec = kSWRingbackOnDuration;
        tone[i].off_msec = kSWRingbackOffDuration;
    }
    
    tone[kSWRingbackCount - 1].off_msec = kSWRingbackInterval;
    
    pjmedia_tonegen_play(self.ringbackPort, kSWRingbackCount, tone, PJMEDIA_TONEGEN_LOOP);
    
    status = pjsua_conf_add_port([endpoint pjPool], [self ringbackPort], (int *)&_ringbackSlot);
    
    if (status != PJ_SUCCESS) {
        DDLogDebug(@"Error adding media port for ringback tones");
        return nil;
    }
    
    return self;
}

-(void)dealloc {
    int ringbackSlot = (int)_ringbackSlot;
    pjmedia_port *ringbackPort = _ringbackPort;
    
    SWEndpoint *endpoint = [SWEndpoint sharedEndpoint];
    
    NSThread *callThread = [endpoint.threadFactory getCallManagementThread];
    [endpoint registerSipThread:callThread];
    
    [endpoint.threadFactory runBlock:^{
        pjsua_conf_remove_port(ringbackSlot);
        pjmedia_port_destroy(ringbackPort);
    } onThread:callThread wait:NO];
    
    /*
#warning main thread!
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        pjsua_conf_remove_port(ringbackSlot);
        pjmedia_port_destroy(ringbackPort);
    });
     */
}

-(void)start {
   pjsua_conf_connect((int)self.ringbackSlot, 0);
}

-(void)stop {
    pjsua_conf_disconnect((int)self.ringbackSlot, 0);
    pjmedia_tonegen_rewind(self.ringbackPort);
}

@end
