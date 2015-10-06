//
//  SWAccountConfiguration.m
//  swig
//
//  Created by Pierre-Marc Airoldi on 2014-08-20.
//  Copyright (c) 2014 PeteAppDesigns. All rights reserved.
//

#import "SWAccountConfiguration.h"
#import "DESCrypt.h"

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
    
    
//    _username = @"79220000002";
//    _password = @"1148111e-435f-403a-bd0d-a56e7e70c2bf_5.7";
    
    _code = @"";
    _registerOnAdd = NO;
    
    return self;
}

+(NSString *)addressFromUsername:(NSString *)username domain:(NSString *)domain {
    return [NSString stringWithFormat:@"%@@%@", username, domain];
}

- (NSString *) cryptedUsername {
    return [DESCrypt crypt:self.username withCode:self.code baseTable:@"EWSIPfghijklmnopqrstuvwxyz012345"];

}
- (NSString *) cryptedPassword {
    return [DESCrypt crypt:self.password withCode:self.code baseTable:@"EWSIPfghijklmnopqrstuvwxyz012345"];
}

@end
