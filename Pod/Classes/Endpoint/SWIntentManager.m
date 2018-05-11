//
//  SWIntentManager.m
//  Swig
//
//  Created by EastWind on 10.05.2018.
//

#import "SWIntentManager.h"
#import "SWIntentProtocol.h"

@interface SWIntentManager ()

@property (strong, readonly) NSMutableArray<id<SWIntentProtocol>> *intents;
@property (strong, readonly) dispatch_queue_t serialQueue;

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
    });

    if ([self needPerformNext]) {
        [self performNext];
    }
}

- (void) performNext {
    
    if (! [self needPerformNext]) {
        return;
    }
    
#ifndef DEBUG
#error TODO
    //TODO: убрать проверку выше, вместо этого возвращать что-то из блока ниже?
#endif
    
    __weak typeof(self) weakSelf = self;
    
    dispatch_async(self.serialQueue, ^{
        
        //double check
        if( ! [weakSelf needPerformNext]) {
            return;
        }
        id<SWIntentProtocol> intent = [weakSelf.intents objectAtIndex:0];
        
        [weakSelf.intents removeObjectAtIndex:0];
        
        [intent performIntent];
    });
    
    [self performNext];
}

- (BOOL) needPerformNext {
#ifndef DEBUG
#error TODO
    //TODO: check SIP status (on reg thread?)
#endif
    
    return self.intents.count > 0;
}

@end
