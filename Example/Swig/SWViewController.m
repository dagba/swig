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
    
    [[SWEndpoint sharedEndpoint] setReadyToSendFileBlock:^(SWAccount *account, NSString *to, NSUInteger messageID, SWFileType fileType, NSString *fileHash) {
        NSLog(@"Ready To Send fileHash: %lu, to: %@, messageID: %lu", (unsigned long)fileType, to, (unsigned long)messageID);
        
        NSString *from = account.accountConfiguration.username;
        
        NSString *url = [NSString stringWithFormat:@"http://193.200.21.126:4950/api/image/%lu?a=%@&b=%@&hash=%@", (unsigned long)messageID, from, to, fileHash];
        
        NSLog(@"%@", url);
        
//        NSString *string = [NSString stringWithFormat:@"%@: %@ %@ %d %08lX\n", dateString, from, message, messageID, (unsigned long)fileHash];
        
//        _textView.text = [_textView.text stringByAppendingString:string];
    }];
    
    [[SWEndpoint sharedEndpoint] setMessageReceivedBlock:^(SWAccount *account, NSString *from, NSString *message, NSUInteger messageID, SWFileType fileType, NSString *fileHash) {
        NSLog(@"messageID: %lu, from: %@, message: %@", (unsigned long)messageID, from, message);
        
        NSString *dateString = [NSDateFormatter localizedStringFromDate:[NSDate date]
                                                              dateStyle:NSDateFormatterShortStyle
                                                              timeStyle:NSDateFormatterMediumStyle];
        
        NSString *string = [NSString stringWithFormat:@"%@: %@ %@ %d %@\n", dateString, from, message, messageID, fileHash];
        
        _textView.text = [_textView.text stringByAppendingString:string];
        
        [account sendMessageReadNotifyTo:from smid:messageID completionHandler:^(NSError *error) {
            NSLog(@"error %@", error);
        }];
    }];
    
    [[SWEndpoint sharedEndpoint] setMessageStatusBlock:^(SWAccount *account, NSUInteger messageID, NSUInteger status) {
        NSString *string = [NSString stringWithFormat:@"Message %lu: status %d\n", (unsigned long)messageID, status];
        
        _textView.text = [_textView.text stringByAppendingString:string];
    }];
    
    //
    [[SWEndpoint sharedEndpoint] setNeedConfirmBlock:^(SWAccount *account, NSUInteger status) {
        [self performSegueWithIdentifier:@"SWViewControllerPushSWConfirmViewController" sender:self];
    }];

    [[SWEndpoint sharedEndpoint] setAbonentStatusBlock:^(SWAccount *account, NSString *abonent, SWPresenseState loginStatus) {
        NSString *string = [NSString stringWithFormat:@"Abonent %@ goes %@\n", abonent, (loginStatus==SWAccountStateDisconnected?@"Offline":@"Online")];
        
        _textView.text = [_textView.text stringByAppendingString:string];

        UIColor *color;
        
        if (loginStatus == SWAccountStateDisconnected) {
            color = [UIColor redColor];
        } else {
            color = [UIColor greenColor];
        }
        
        [_phoneNumberTextField setBackgroundColor:color];
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
    
    NSString *callTo = [NSString stringWithFormat:@"sips:%@@ewsip.ru", _phoneNumberTextField.text];

    
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

- (IBAction)presenseChange:(UISwitch *)sender {
    SWAccount *account = [[SWEndpoint sharedEndpoint] firstAccount];
    
    SWPresenseState state = (BOOL)sender.isOn?SWPresenseStateOnline:SWPresenseStateOffline;
    
    [account setPresenseStatusOnline:state completionHandler:^(NSError *error) {
        NSLog(@"%@", error);
    }];
}

- (IBAction)subscribe:(UIButton *)sender {
    SWAccount *account = [[SWEndpoint sharedEndpoint] firstAccount];
    [account subscribeBuddyURI:_phoneNumberTextField.text completionHandler:^(NSError *error) {
        NSLog(@"%@", error);
    }];
}

- (IBAction)file:(UIButton *)sender {
    SWAccount *account = [[SWEndpoint sharedEndpoint] firstAccount];
    
    [account sendMessage:_messageTextField.text fileType:SWFileTypePicture fileHash:[[[NSProcessInfo processInfo] globallyUniqueString] substringToIndex:8] to:_phoneNumberTextField.text completionHandler:^(NSError *error, NSString *callID) {
        if (!error) {
            NSString *string = [NSString stringWithFormat:@"File: %@ sent\n", callID];
            _textView.text = [_textView.text stringByAppendingString:string];
        } else {
            NSString *string = [NSString stringWithFormat:@"File not sent: %@\n", error.domain];
            _textView.text = [_textView.text stringByAppendingString:string];
        }
    }];
}

@end
