//
//  SWThreadFactory.m
//  Swig
//
//  Created by EastWind on 25.02.2018.
//

#import "SWThreadManager.h"

#import "SWEndpoint.h"

@interface SWThreadManager () {
    NSThread *_messageThread;
    NSThread *_callManagementThread;
}

@end

@implementation SWThreadManager

- (NSThread *) getMessageThread {
    if (_messageThread == nil) {
        _messageThread = [[NSThread alloc]  initWithTarget:self selector:@selector(threadKeepAlive:) object:nil];
        [_messageThread start];
    }
    _messageThread.name = @"messageThread";
    
    return _messageThread;
}

- (NSThread *) getCallManagementThread {
    if (_callManagementThread == nil) {
        _callManagementThread = [[NSThread alloc]  initWithTarget:self selector:@selector(threadKeepAlive:) object:nil];
        [_callManagementThread start];
    }
    _callManagementThread.name = @"callManagementThread";
    
    return _callManagementThread;
}

- (void)threadKeepAlive:(id)data {
    NSRunLoop *runloop = [NSRunLoop currentRunLoop];
    [runloop addPort:[NSMachPort port] forMode:NSDefaultRunLoopMode];
    
#warning вынести в свойство?
    BOOL isAlive = YES;
    
    while (isAlive) { // 'isAlive' is a variable that is used to control the thread existence...
        [runloop runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
    }
}

- (void) runBlock: (void (^)(void)) block onThread: (NSThread *) thread wait: (BOOL) wait {
    [self performSelector: @selector(runBlock:) onThread: thread withObject: [block copy] waitUntilDone: wait];
}

- (void) runBlock: (void (^)(void)) block {
    block();
}

@end
