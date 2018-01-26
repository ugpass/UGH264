//
//  ViewController.m
//  FFmpeg
//
//  Created by wenxiang on 2018/1/26.
//  Copyright © 2018年 wenxiang. All rights reserved.
//

#import "ViewController.h"
#import "NextViewController.h"
#import "H264Decoder.h"
@interface ViewController ()


//解码
@property (nonatomic, strong) H264Decoder *h264decoder;
@end

@implementation ViewController
- (IBAction)startClick:(id)sender {
    
    NextViewController *vc = [[NextViewController alloc] init];
    [self presentViewController:vc animated:YES completion:nil];
}
/**
 *解码h264 生成图片
 */
- (IBAction)playClick:(id)sender {
    self.h264decoder = [[H264Decoder alloc] init];
    
    NSString *filePathIn = [[NSBundle mainBundle] pathForResource:@"vtencode" ofType:@"h264"];
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingAtPath:filePathIn];
    unsigned long long filesize = [fileHandle seekToEndOfFile];
    [fileHandle seekToFileOffset:0];
    
    while (fileHandle.offsetInFile != filesize) {
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            NSData *data = [fileHandle readDataOfLength:1];
            [self.h264decoder decodeData:data];
        });
        
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    
    
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end
