//
//  ViewController.m
//  Demo
//
//  Created by Anselz on 14-6-10.
//  Copyright (c) 2014年 NeoWork. All rights reserved.
//

#import "ViewController.h"
#import "NWGIFContainerImageView.h"

@interface ViewController ()<UITableViewDataSource,UITableViewDelegate>
@property (weak, nonatomic) IBOutlet UITableView *mainTableView;

@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    
	// Do any additional setup after loading the view, typically from a nib.
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

-(NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 20;
}
-(CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 120.0f;
}

-(UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell"];
    if (cell == nil) {
        cell = [[UITableViewCell alloc]initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"cell"];
        NWGIFContainerImageView *imageView = [[NWGIFContainerImageView alloc]initWithFrame:CGRectMake(10, 5, 300, 110)];
        imageView.tag = 1001;
        [cell.contentView addSubview:imageView];
        UIActivityIndicatorView *acView = [[UIActivityIndicatorView alloc]initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
        acView.hidden = YES;
        acView.tag = 1002;
        [cell.contentView addSubview:acView];
    }
    NWGIFContainerImageView *imageView = (NWGIFContainerImageView *)[cell.contentView viewWithTag:1001];
    UIActivityIndicatorView *acView = (UIActivityIndicatorView *)[cell.contentView viewWithTag:1002];
    acView.center = cell.contentView.center;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        acView.hidden = NO;
        [acView startAnimating];
        NSURL *url = [NSURL URLWithString:@"http://raphaelschaad.com/static/nyan.gif"];
        NSData *data = [NSData dataWithContentsOfURL:url];
        NWGIFContainerImage *animatedImage = [[NWGIFContainerImage alloc] initWithAnimatedGIFData:data];
        dispatch_async(dispatch_get_main_queue(), ^{
            [acView stopAnimating];
            acView.hidden = YES;
            imageView.animatedImage = animatedImage;
        });
        
    });
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}
@end
