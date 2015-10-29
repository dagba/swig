//
//  SWAccountConfiguration.m
//  swig
//
//  Created by Pierre-Marc Airoldi on 2014-08-20.
//  Copyright (c) 2014 PeteAppDesigns. All rights reserved.
//

#import "SWAccountConfiguration.h"

@implementation SWAccountConfiguration

-(instancetype)init {
    
    self = [super init];
    
    if (!self) {
        return nil;
    }
    
    NSUserDefaults * standardUserDefaults = [NSUserDefaults standardUserDefaults];
    
    _displayName = nil;
    _address = nil;
    _domain = [standardUserDefaults stringForKey:@"domain"];
    _proxy = nil;
    _authScheme = @"digest";
    _authRealm = @"*";

    _username = [standardUserDefaults stringForKey:@"phone"];
    
    NSUUID *oNSUUID = [[UIDevice currentDevice] identifierForVendor];
    _password = [oNSUUID UUIDString];
    
    NSLog(@"%@:%@", _username, _password);
    
//    _username = @"79220000033";
//    _password = @"1234567890";
    
//    _code = @"";
    _registerOnAdd = NO;
    
    return self;
}

+(NSString *)addressFromUsername:(NSString *)username domain:(NSString *)domain {
    return [NSString stringWithFormat:@"%@@%@", username, domain];
}

@end
