//
//  SWViewController.m
//  Swig
//
//  Created by Pierre-Marc Airoldi on 09/01/2014.
//  Copyright (c) 2014 Pierre-Marc Airoldi. All rights reserved.
//

#import "SWViewController.h"
#import <Swig/Swig.h>
#import "SWAppDelegate.h"

@interface SWViewController ()

@property (weak, nonatomic) IBOutlet UITextField *phoneNumberTextField;
@property (weak, nonatomic) IBOutlet UILabel *phoneNumberLabel;
@property (weak, nonatomic) IBOutlet UITextField *messageTextField;
@property (weak, nonatomic) IBOutlet UITextView *textView;

@end

@implementation SWViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    SWAppDelegate *appDelegate = [[UIApplication sharedApplication] delegate];
    [appDelegate addSIPAccount];

    [[SWEndpoint sharedEndpoint] setMessageSentBlock:^(SWAccount *account, NSString *callID, NSUInteger messageID, NSUInteger status) {
        NSString *string = [NSString stringWithFormat:@"callID: %@, messageID: %lu, status: %lu\n", callID, (unsigned long)messageID, (unsigned long)status];
        _textView.text = [_textView.text stringByAppendingString:string];

    }];
    
    [[SWEndpoint sharedEndpoint] setMessageReceivedBlock:^(SWAccount *account, NSString *from, NSString *message, NSUInteger messageID) {
        NSLog(@"messageID: %lu, from: %@, message: %@", (unsigned long)messageID, from, message);

        NSString *dateString = [NSDateFormatter localizedStringFromDate:[NSDate date]
                                                              dateStyle:NSDateFormatterShortStyle
                                                              timeStyle:NSDateFormatterMediumStyle];

        NSString *string = [NSString stringWithFormat:@"%@: %@ %@ %d\n", dateString, from, message, messageID];
        
        _textView.text = [_textView.text stringByAppendingString:string];

    }];
    
    [[SWEndpoint sharedEndpoint] setMessageStatusBlock:^(SWAccount *account, NSUInteger messageID, NSUInteger status) {
        NSString *string = [NSString stringWithFormat:@"Message %lu: status %d\n", (unsigned long)messageID, status];
        
        _textView.text = [_textView.text stringByAppendingString:string];
    }];
    
    //
    [[SWEndpoint sharedEndpoint] setNeedConfirmBlock:^(SWAccount *account, NSUInteger status) {
        [self performSegueWithIdentifier:@"SWViewControllerPushSWConfirmViewController" sender:self];
    }];
    
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapGesture)];
    [self.view addGestureRecognizer:tap];
    
	// Do any additional setup after loading the view, typically from a nib.
}

- (void) tapGesture {
    [self.view endEditing:YES];
}

- (void) viewDidAppear:(BOOL)animated {
    
    SWAccount *account = [[SWEndpoint sharedEndpoint] firstAccount];
    [_phoneNumberLabel setText:account.accountConfiguration.address];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

-(IBAction)makeCall:(id)sender {
 
    SWAccount *account = [[SWEndpoint sharedEndpoint] firstAccount];
    
    NSString *callTo = [NSString stringWithFormat:@"%@@ewsip.ru", _phoneNumberTextField.text];

    
    [account makeCall:callTo completionHandler:^(NSError *error) {
       
        if (error) {
            NSLog(@"%@",[error description]);
        }
    }];
}

-(IBAction)answer:(id)sender {
    
    SWAccount *account = [[SWEndpoint sharedEndpoint] firstAccount];

    SWCall *call = [account firstCall];
    
    if (call) {
        [call answer:^(NSError *error) {
            
        }];
    }
}

-(IBAction)mute:(id)sender {
    
    SWAccount *account = [[SWEndpoint sharedEndpoint] firstAccount];
    
    SWCall *call = [account firstCall];

    if (call) {
        
        [call toggleMute:^(NSError *error) {

        }];
    }
}

-(IBAction)speaker:(id)sender {
    
    SWAccount *account = [[SWEndpoint sharedEndpoint] firstAccount];
    
    SWCall *call = [account firstCall];
    
    if (call) {
        
        [call toggleSpeaker:^(NSError *error) {

        }];
    }
}

- (IBAction)hang:(UIButton *)sender {
    SWAccount *account = [[SWEndpoint sharedEndpoint] firstAccount];
    
    SWCall *call = [account firstCall];
    
    if (call) {
        
        [call hangup:^(NSError *error) {
            NSLog(@"hangup error%@", error);
        }];
    }

}

- (IBAction)sendMesage:(UIButton *)sender {
    [self.view endEditing:YES];
    SWAccount *account = [[SWEndpoint sharedEndpoint] firstAccount];

    [account sendMessage:_messageTextField.text to:_phoneNumberTextField.text completionHandler:^(NSError *error, NSString *callID) {
        if (!error) {
            NSString *string = [NSString stringWithFormat:@"Message: %@ sent\n", callID];
            _textView.text = [_textView.text stringByAppendingString:string];
        } else {
            NSString *string = [NSString stringWithFormat:@"Message not sent: %@\n", error.domain];
            _textView.text = [_textView.text stringByAppendingString:string];
        }
    }];
    
}

@end
