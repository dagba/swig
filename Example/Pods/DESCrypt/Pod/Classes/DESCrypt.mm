//
//  DESCryptStub.m
//  CryptTest
//
//  Created by Maxim Keegan on 21.05.15.
//  Copyright (c) 2015 East Media. All rights reserved.
//

#import "DESCrypt.h"
#import "crypt.h"

@implementation DESCrypt

+ (NSString *) crypt:(NSString *) source withCode: (NSString *) code baseTable: (NSString *) baseTable {
//    const string base_table = "";
    const string base_table = [baseTable cStringUsingEncoding:NSASCIIStringEncoding];
    
    Crypt *crypt = new Crypt(base_table);
    
    const char *cCode = [code cStringUsingEncoding:NSASCIIStringEncoding];
    const char *cSource = [source cStringUsingEncoding:NSASCIIStringEncoding];
    
    string crypted = crypt->Encrypt(cSource, cCode);
    
    return [NSString stringWithCString:crypted.c_str() encoding:NSASCIIStringEncoding];
}

+ (NSString *) decrypt:(NSString *) crypted withCode: (NSString *) code baseTable: (NSString *) baseTable{
    const string base_table = [baseTable cStringUsingEncoding:NSASCIIStringEncoding];
    
    Crypt *crypt = new Crypt(base_table);
    
    const char *cCode = [code cStringUsingEncoding:NSASCIIStringEncoding];
    const char *cCrypted = [crypted cStringUsingEncoding:NSASCIIStringEncoding];
    
    string source = crypt->Decrypt(cCrypted, cCode);
    
    return [NSString stringWithCString:source.c_str() encoding:NSASCIIStringEncoding];
}


@end
