//
//  SWContact.h
//  
//
//  Created by Pierre-Marc Airoldi on 2014-09-08.
//
//

#import <Foundation/Foundation.h>

@interface SWContact : NSObject <NSCopying, NSMutableCopying>

@property (nonatomic, readonly, strong) NSString *name;
@property (nonatomic, readonly, strong) NSString *host;
@property (nonatomic, readonly, strong) NSString *user;


-(instancetype)initWithName:(NSString *)name host:(NSString *)host user:(NSString *) user;

@end
