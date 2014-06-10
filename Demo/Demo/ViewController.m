//
//  ViewController.m
//  Demo
//
//  Created by Anselz on 14-6-10.
//  Copyright (c) 2014年 NeoWork. All rights reserved.
//

#import "ViewController.h"
#import "NWGIFContainerImageView.h"

@interface ViewController ()
@property (weak, nonatomic) IBOutlet NWGIFContainerImageView *mainImageView;

@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    NSURL *url = [NSURL URLWithString:@"http://raphaelschaad.com/static/nyan.gif"];
    NSData *data = [NSData dataWithContentsOfURL:url];
    NWGIFContainerImage *animatedImage = [[NWGIFContainerImage alloc] initWithAnimatedGIFData:data];
    self.mainImageView.animatedImage = animatedImage;
	// Do any additional setup after loading the view, typically from a nib.
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
