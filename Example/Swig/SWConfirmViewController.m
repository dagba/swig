//
//  SWConfirmViewController.m
//  Swig
//
//  Created by Maxim Keegan on 28.09.15.
//  Copyright © 2015 Pierre-Marc Airoldi. All rights reserved.
//

#import "SWConfirmViewController.h"
#import <Swig/Swig.h>
//#import "DESCrypt.h"

@interface SWConfirmViewController ()

@property (weak, nonatomic) IBOutlet UITextField *codeTextField;

@end

@implementation SWConfirmViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [[SWEndpoint sharedEndpoint] setConfirmationBlock:^(NSError *error) {
        [self.navigationController popViewControllerAnimated:YES];
    }];
    // Do any additional setup after loading the view.
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/
- (IBAction)confirmAction:(UIButton *)sender {
    
    SWAccount *account = [[SWEndpoint sharedEndpoint] firstAccount];
    
    [account setCode:_codeTextField.text completionHandler:^(NSError *error) {
        NSLog(@"error: %@", error);
    }];
    
}

@end
