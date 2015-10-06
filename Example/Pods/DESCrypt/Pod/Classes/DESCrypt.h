//
//  DESCryptStub.h
//  CryptTest
//
//  Created by Maxim Keegan on 21.05.15.
//  Copyright (c) 2015 East Media. All rights reserved.
//

#define kBaseTable "EWSIPfghijklmnopqrstuvwxyz012345"

#import <Foundation/Foundation.h>

@interface DESCrypt : NSObject

+ (NSString *) crypt:(NSString *) source withCode: (NSString *) code baseTable: (NSString *) baseTable;
+ (NSString *) decrypt:(NSString *) crypted withCode: (NSString *) code baseTable: (NSString *) baseTable;

@end
