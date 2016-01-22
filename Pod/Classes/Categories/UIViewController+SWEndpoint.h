//
//  UIViewController+SWEndpoint.h
//  Pods
//
//  Created by Maxim Keegan on 22.01.16.
//
//

#import <UIKit/UIKit.h>

@class SWAccount;
@interface UIViewController (SWEndpoint)

- (BOOL)sw_shouldObserveAccountStateChanges;
- (void)sw_accountStateChanged:(SWAccount*)account;

@end
