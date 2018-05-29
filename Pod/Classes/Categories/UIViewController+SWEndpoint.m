//
//  UIViewController+SWEndpoint.m
//  Pods
//
//  Created by Maxim Keegan on 22.01.16.
//
//

#import "UIViewController+SWEndpoint.h"

#import <objc/runtime.h>

#import "SWEndpoint.h"

static void swEndPointViewController_swizzleInstanceMethod(Class c, SEL original, SEL replacement)
{
    Method a = class_getInstanceMethod(c, original);
    Method b = class_getInstanceMethod(c, replacement);
    if (class_addMethod(c, original, method_getImplementation(b), method_getTypeEncoding(b)))
    {
        class_replaceMethod(c, replacement, method_getImplementation(a), method_getTypeEncoding(a));
    }
    else
    {
        method_exchangeImplementations(a, b);
    }
}

@implementation UIViewController (SWEndpoint)

#pragma mark - Swizzle

+ (void)load
{
    swEndPointViewController_swizzleInstanceMethod(self, @selector(viewWillAppear:), @selector(swEndPointViewController_viewWillAppear:));
    swEndPointViewController_swizzleInstanceMethod(self, @selector(viewDidDisappear:), @selector(swEndPointViewController_viewDidDisappear:));
}

- (void)swEndPointViewController_viewWillAppear:(BOOL)animated {
    [self swEndPointViewController_viewWillAppear:animated];
    
    // check observe or not
    BOOL shouldObserve = [self sw_shouldObserveAccountStateChanges];
    
    // if observe no require
    if (shouldObserve == NO) return;
    
    // subscribe self
    [[SWEndpoint sharedEndpoint] setAccountStateChangeBlock:^(SWAccount *account) {
        
        [self sw_accountStateChanged:account];
        
    } forObserver:self];
}

- (void)swEndPointViewController_viewDidDisappear:(BOOL)animated {
    [self swEndPointViewController_viewDidDisappear:animated];
    
    [[SWEndpoint sharedEndpoint] removeAccountStateChangeBlockForObserver:self];
}

#pragma mark - Methods

- (BOOL)sw_shouldObserveAccountStateChanges {
    return NO;
}

- (void)sw_accountStateChanged:(SWAccount*)account {
    
}


@end
