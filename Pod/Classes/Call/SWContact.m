
//
//  SWContact.m
//  
//
//  Created by Pierre-Marc Airoldi on 2014-09-08.
//
//

#import "SWContact.h"
#import "SWMutableContact.h"

@implementation SWContact

-(instancetype)init {
    
    return [self initWithName:nil host:nil user:nil];
}

-(instancetype)initWithName:(NSString *)name host:(NSString *)host user: (NSString *) user {
    
    self = [super init];
    
    if (!self) {
        return nil;
    }
    
    if (!name) {
        _name = @"";
    } else {
        _name = name;
    }
    
    if (!host) {
        _host = @"";
    } else {
        _host = host;
    }

    if (!user) {
        _user = @"";
    } else {
        _user = user;
    }

    return self;
}

-(instancetype)copyWithZone:(NSZone *)zone {
    
    SWContact *contact = [[SWContact allocWithZone:zone] init];
    contact.name = [self.name copyWithZone:zone];
    contact.host = [self.host copyWithZone:zone];
    contact.user = [self.user copyWithZone:zone];
    
    return contact;
}

-(instancetype)mutableCopyWithZone:(NSZone *)zone {
 
    SWMutableContact *contact = [[SWMutableContact allocWithZone:zone] init];
    contact.name = [self.name copyWithZone:zone];
    contact.host = [self.host copyWithZone:zone];
    contact.user = [self.user copyWithZone:zone];

    return contact;
}

-(void)setName:(NSString *)name {
    
    [self willChangeValueForKey:@"name"];
    _name = name;
    [self didChangeValueForKey:@"name"];
}

-(void)setHost:(NSString *)host {
    
    [self willChangeValueForKey:@"host"];
    _host = host;
    [self didChangeValueForKey:@"host"];
}

-(void)setUser:(NSString *)user {
    
    [self willChangeValueForKey:@"user"];
    _user = user;
    [self didChangeValueForKey:@"user"];
}


@end
