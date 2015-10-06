//
//  SWAppDelegate.m
//  Swig
//
//  Created by CocoaPods on 09/01/2014.
//  Copyright (c) 2014 Pierre-Marc Airoldi. All rights reserved.
//

#import "SWAppDelegate.h"
#import <Swig/Swig.h>

@implementation SWAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    // Override point for customization after application launch.
    
    NSUserDefaults * standardUserDefaults = [NSUserDefaults standardUserDefaults];
    if (![standardUserDefaults objectForKey:@"phone"] || ![standardUserDefaults objectForKey:@"domain"]) {
        [self registerDefaultsFromSettingsBundle];
    }

    
    NSLog(@"phone: %@", [standardUserDefaults objectForKey:@"phone"]);
    NSLog(@"domain: %@", [standardUserDefaults objectForKey:@"domain"]);
    
    [self configureEndpoint];
//    [self addSIPAccount];
    
    
    
    return YES;
}

#pragma NSUserDefaults
- (void)registerDefaultsFromSettingsBundle
{
    NSLog(@"Registering default values from Settings.bundle");
    NSUserDefaults * defs = [NSUserDefaults standardUserDefaults];
    [defs synchronize];
    
    NSString *settingsBundle = [[NSBundle mainBundle] pathForResource:@"Settings" ofType:@"bundle"];
    
    if(!settingsBundle)
    {
        NSLog(@"Could not find Settings.bundle");
        return;
    }
    
    NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:[settingsBundle stringByAppendingPathComponent:@"Root.plist"]];
    NSArray *preferences = [settings objectForKey:@"PreferenceSpecifiers"];
    NSMutableDictionary *defaultsToRegister = [[NSMutableDictionary alloc] initWithCapacity:[preferences count]];
    
    for (NSDictionary *prefSpecification in preferences)
    {
        NSString *key = [prefSpecification objectForKey:@"Key"];
        if (key)
        {
            // check if value readable in userDefaults
            id currentObject = [defs objectForKey:key];
            if (currentObject == nil)
            {
                // not readable: set value from Settings.bundle
                id objectToSet = [prefSpecification objectForKey:@"DefaultValue"];
                [defaultsToRegister setObject:objectToSet forKey:key];
                NSLog(@"Setting object %@ for key %@", objectToSet, key);
            }
            else
            {
                // already readable: don't touch
                NSLog(@"Key %@ is readable (value: %@), nothing written to defaults.", key, currentObject);
            }
        }
    }
    
    [defs registerDefaults:defaultsToRegister];
    [defs synchronize];
}

- (void)applicationWillResignActive:(UIApplication *)application
{
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}

-(void)configureEndpoint {
    
    SWTransportConfiguration *udp = [SWTransportConfiguration configurationWithTransportType:SWTransportTypeUDP];
//    udp.port = 5060;
    
//    SWTransportConfiguration *tcp = [SWTransportConfiguration configurationWithTransportType:SWTransportTypeTCP];
//    tcp.port = 5060;
    
    SWEndpointConfiguration *endpointConfiguration = [SWEndpointConfiguration configurationWithTransportConfigurations:@[udp]];
    
    SWEndpoint *endpoint = [SWEndpoint sharedEndpoint];
    
    [endpoint configure:endpointConfiguration completionHandler:^(NSError *error) {
        
        if (error) {
            
            NSLog(@"%@", [error description]);
            
            [endpoint reset:^(NSError *error) {
                if(error) NSLog(@"%@", [error description]);
            }];
        }
    }];
    
    [endpoint setIncomingCallBlock:^(SWAccount *account, SWCall *call) {
        
        NSLog(@"\n\nIncoming Call : %d\n\n", (int)call.callId);
        
    }];
    
    [endpoint setAccountStateChangeBlock:^(SWAccount *account) {
        
        NSLog(@"\n\nAccount State : %ld\n\n", (long)account.accountState);
    }];
    
    [endpoint setCallStateChangeBlock:^(SWAccount *account, SWCall *call) {
        
        NSLog(@"\n\nCall State : %ld\n\n", (long)call.callState);
    }];
    
    [endpoint setCallMediaStateChangeBlock:^(SWAccount *account, SWCall *call) {
        
        NSLog(@"\n\nMedia State Changed\n\n");
    }];
    

}

-(void)addSIPAccount {
    
    SWAccount *account = [SWAccount new];
    
    SWAccountConfiguration *configuration = [SWAccountConfiguration new];
    
//    configuration.username = kUsername;
//    configuration.password = kPassword;

//    configuration.domain = kDomain;

    configuration.address = [SWAccountConfiguration addressFromUsername:configuration.username domain:configuration.domain];
//    configuration.proxy = @"sbc.multifon.ru";
    configuration.registerOnAdd = YES;
    
    [account configure:configuration completionHandler:^(NSError *error) {
        
        if (error) {
            NSLog(@"%@", [error description]);
        }
        
    }];
}

@end
