//
//  SWAudioSessionObserver.m
//  Swig
//
//  Created by EastWind on 03.03.2018.
//

#import "SWAudioSessionObserver.h"

#import "EWFileLogger.h"

#import <AVFoundation/AVFoundation.h>

@implementation SWAudioSessionObserver

- (instancetype)init {
    self = [super init];
    if (self) {
        NSNotificationCenter *notCenter = [NSNotificationCenter defaultCenter];
        [notCenter addObserver:self selector:@selector(videoWasInterruptedNotification:) name:AVCaptureSessionWasInterruptedNotification object:nil];
         /*
          [notCenter addObserver:self selector:@selector(audioSessionInterruptionWithNotification:) name:AVAudioSessionInterruptionNotification object:nil];
        [notCenter addObserver:self selector:@selector(audioSessionRouteDidChangeWithNotification:) name:AVAudioSessionRouteChangeNotification object:nil];
        
        [notCenter addObserver:self selector:@selector(videoErrorNotification:) name:AVCaptureSessionRuntimeErrorNotification object:nil];
        [notCenter addObserver:self selector:@selector(videoStartNotification:) name:AVCaptureSessionDidStartRunningNotification object:nil];
        [notCenter addObserver:self selector:@selector(videoDidStopNotification:) name:AVCaptureSessionDidStopRunningNotification object:nil];
        [notCenter addObserver:self selector:@selector(videoWasInterruptedNotification:) name:AVCaptureSessionWasInterruptedNotification object:nil];
        */
        
        
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void) audioSessionRouteDidChangeWithNotification: (NSNotification *) notification {
    //NSLog(@"<--AudioSession notification--> RouteDidChangeNotification:%@",notification);
    
    NSDictionary *interuptionDict = notification.userInfo;
    
    NSInteger routeChangeReason = [[interuptionDict valueForKey:AVAudioSessionRouteChangeReasonKey] integerValue];
    
    switch (routeChangeReason) {
        case AVAudioSessionRouteChangeReasonUnknown:
            NSLog(@"<--AudioSession notification--> routeChangeReason : AVAudioSessionRouteChangeReasonUnknown");
            break;
            
        case AVAudioSessionRouteChangeReasonNewDeviceAvailable:
            // a headset was added or removed
            NSLog(@"<--AudioSession notification--> routeChangeReason : AVAudioSessionRouteChangeReasonNewDeviceAvailable");
            break;
            
        case AVAudioSessionRouteChangeReasonOldDeviceUnavailable:
            // a headset was added or removed
            NSLog(@"<--AudioSession notification--> routeChangeReason : AVAudioSessionRouteChangeReasonOldDeviceUnavailable");
            break;
            
        case AVAudioSessionRouteChangeReasonCategoryChange:
            // called at start - also when other audio wants to play
            NSLog(@"<--AudioSession notification--> routeChangeReason : AVAudioSessionRouteChangeReasonCategoryChange");//AVAudioSessionRouteChangeReasonCategoryChange
            break;
            
        case AVAudioSessionRouteChangeReasonOverride:
            NSLog(@"<--AudioSession notification--> routeChangeReason : AVAudioSessionRouteChangeReasonOverride");
            break;
            
        case AVAudioSessionRouteChangeReasonWakeFromSleep:
            NSLog(@"<--AudioSession notification--> routeChangeReason : AVAudioSessionRouteChangeReasonWakeFromSleep");
            break;
            
        case AVAudioSessionRouteChangeReasonNoSuitableRouteForCategory:
            NSLog(@"<--AudioSession notification--> routeChangeReason : AVAudioSessionRouteChangeReasonNoSuitableRouteForCategory");
            break;
            
        default:
            break;
    }
}

- (void) audioSessionInterruptionWithNotification: (NSNotification *) notification {
    NSLog(@"<--AudioSession notification--> InterruptionNotification:%@",notification);
}

- (void) videoErrorNotification: (NSNotification *) notification {
    NSLog(@"<--videoErrorNotification--> Notification:%@",notification);
}

- (void) videoStartNotification: (NSNotification *) notification {
    NSLog(@"<--videoStartNotification--> Notification:%@",notification);
}

- (void) videoDidStopNotification: (NSNotification *) notification {
    NSLog(@"<--videoDidStopNotification--> Notification:%@",notification);
}

- (void) videoWasInterruptedNotification: (NSNotification *) notification {
    if (@available(iOS 9.0, *)) {
        NSLog(@"<--starting--> videoWasInterruptedNotification");
        
        NSLog(@"<--videoWasInterruptedNotification--> key: %d Notification:%@",notification.userInfo[AVCaptureSessionInterruptionReasonKey] == AVCaptureSessionInterruptionReasonVideoDeviceNotAvailableInBackground, notification);
    } else {
        // Fallback on earlier versions
    }
}

@end
