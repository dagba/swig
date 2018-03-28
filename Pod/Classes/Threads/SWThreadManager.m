//
//  SWThreadFactory.m
//  Swig
//
//  Created by EastWind on 25.02.2018.
//

#import "SWThreadManager.h"

#import "SWEndpoint.h"

#import "EWFileLogger.h"

@interface SWThreadManager () {
    NSThread *_messageThread;
    NSThread *_callManagementThread;
    NSThread *_registrationThread;
}

@end

@implementation SWThreadManager

+ (instancetype) sharedInstance {
    static SWThreadManager *_sharedInstance;
    static dispatch_once_t initOnceToken;
    dispatch_once(&initOnceToken, ^{
        _sharedInstance = [[self alloc] init];
    });
    return _sharedInstance;
}

- (NSThread *) getMessageThread {
    
    NSLog(@"<--threads--> requesting: <MessageThread> from: <%@>", [NSThread currentThread]);
    
    if (_messageThread == nil) {
        _messageThread = [[NSThread alloc]  initWithTarget:self selector:@selector(threadKeepAlive:) object:nil];
        _messageThread.name = @"messageThread";
        [_messageThread start];
    }
    
    [[SWEndpoint sharedEndpoint] registerSipThread:_messageThread];
    
    return _messageThread;
}

- (NSThread *) getCallManagementThread {
    
#warning experiment работа со звонками и с аккаунтами лочат друг друга
    return [self getRegistrationThread];
    
    NSLog(@"<--threads--> requesting: <CallManagementThread> from: <%@>", [NSThread currentThread]);
    
    if (_callManagementThread == nil) {
        _callManagementThread = [[NSThread alloc]  initWithTarget:self selector:@selector(threadKeepAlive:) object:nil];
        _callManagementThread.name = @"callManagementThread";
        [_callManagementThread start];
    }
    
    [[SWEndpoint sharedEndpoint] registerSipThread:_callManagementThread];
    
    return _callManagementThread;
}

- (NSThread *) getRegistrationThread {
    
    NSLog(@"<--threads--> requesting: <RegistrationThread> from: <%@>", [NSThread currentThread]);
    
    @synchronized (self) {
        if (_registrationThread == nil) {
            _registrationThread = [[NSThread alloc]  initWithTarget:self selector:@selector(threadKeepAlive:) object:nil];
            _registrationThread.name = @"registrationThread";
            [_registrationThread start];
        }
    }
    
    [[SWEndpoint sharedEndpoint] registerSipThread:_registrationThread];
    
    return _registrationThread;
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
    NSLog(@"<--threads--> requesting: <%@> from: <%@>", thread, [NSThread currentThread]);
    [self performSelector: @selector(runBlock:) onThread: thread withObject: [block copy] waitUntilDone: wait];
}

- (void) runBlock: (void (^)(void)) block {
    block();
}

@end
