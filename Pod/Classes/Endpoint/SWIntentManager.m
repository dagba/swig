//
//  SWIntentManager.m
//  Swig
//
//  Created by EastWind on 10.05.2018.
//

#import "SWIntentManager.h"
#import "SWIntentProtocol.h"
#import "SWEndpoint.h"

@interface SWIntentManager () {
    NSThread *_intentsThread;
}

@property (strong, readonly) NSMutableArray<id<SWIntentProtocol>> *intents;
@property (strong, readonly) dispatch_queue_t serialQueue;
@property (assign, atomic) BOOL working;

@end

@implementation SWIntentManager

- (instancetype)init
{
    self = [super init];
    if (self) {
        self->_intents = [NSMutableArray new];
        self->_serialQueue = dispatch_queue_create("ru.eastwind.SIPIntentsQueue", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void) addIntent: (id<SWIntentProtocol>) intent {
    dispatch_async(self.serialQueue, ^{
        [self.intents addObject:intent];
        self.working = YES;
    });

    //по добавлению интента
    [self start];
}

- (void) start {
    self.working = YES;
    [self startIntentsThread];
}

- (void) startIntentsThread {
    
    NSLog(@"<--threads--> requesting: <sipIntentsThread>");
    
    @synchronized (self) {
        if ((_intentsThread == nil) || (!_intentsThread.isExecuting)) {
            _intentsThread = [[NSThread alloc]  initWithTarget:self selector:@selector(threadKeepAlive:) object:nil];
            _intentsThread.name = @"sipIntentsThread";
            [_intentsThread start];
        }
    }
}

- (void)threadKeepAlive:(id)data {
    while (self.working) {
        [self performNext];
    }
}

- (void) performNext {
    
    __weak typeof(self) weakSelf = self;
    
    dispatch_async(self.serialQueue, ^{
        
        if( ! [weakSelf needPerformNext]) {
            return;
        }
        
        id<SWIntentProtocol> intent = [weakSelf.intents objectAtIndex:0];
        
        [weakSelf.intents removeObjectAtIndex:0];
        
        [intent performIntent];
    });
}

- (BOOL) needPerformNext {
    BOOL result = NO;
    
    //Вернем нет, если нет интентов
    result = (self.intents.count > 0);
    
    //Проверим, готов ли СИП обработать интент
    result = result && [[SWEndpoint sharedEndpoint] hasActiveAccount];
    
    //Если проверка не прошла, останавливаем работу, чтобы не обрабатывать следующие интенты
    self.working = result;
    
    return result;
}

@end
