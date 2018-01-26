//
//  NextViewController.m
//  FFmpeg
//
//  Created by wenxiang on 2018/1/26.
//  Copyright © 2018年 wenxiang. All rights reserved.
//

#import "NextViewController.h"
#import <AVFoundation/AVFoundation.h>
#import "H264Encoder.h"
@interface NextViewController ()<AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate>
@property (nonatomic, strong) AVCaptureSession *session;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *preLayer;


@property (nonatomic, strong) AVCaptureDevice *videoDev;
@property (nonatomic, strong) AVCaptureDevice *audioDev;

@property (nonatomic, strong) AVCaptureDeviceInput *videoInput;
@property (nonatomic, strong) AVCaptureDeviceInput *audioDevInput;

@property (nonatomic, strong) AVCaptureVideoDataOutput *videoOutput;
@property (nonatomic, strong) AVCaptureAudioDataOutput *audioOutput;

@property (nonatomic) dispatch_queue_t videoQueue;
@property (nonatomic) dispatch_queue_t audioQueue;

@property (nonatomic, strong) H264Encoder *h264encoder;

@end

@implementation NextViewController

- (H264Encoder *)h264encoder
{
    if (!_h264encoder) {
        _h264encoder = [[H264Encoder alloc] init];
    }
    return _h264encoder;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.session = [[AVCaptureSession alloc] init];
    
    //分辨率
    if (![self.session canSetSessionPreset:AVCaptureSessionPreset1280x720]) {
        if (![self.session canSetSessionPreset:AVCaptureSessionPreset640x480]) {
            
        }
    }
    [self.session beginConfiguration];
    
    [self setupVideo];
    [self setupAudio];
    
    [self.session commitConfiguration];
    self.preLayer = [AVCaptureVideoPreviewLayer layerWithSession:self.session];
    UIView *view = [[UIView alloc] initWithFrame:CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width, [UIScreen mainScreen].bounds.size.height)];
    CALayer *viewlayer = [view  layer];
    viewlayer.masksToBounds = YES;
    
    [self.preLayer setFrame:view.bounds];
    [self.preLayer setVideoGravity:AVLayerVideoGravityResizeAspectFill];
    
    [viewlayer insertSublayer:self.preLayer below:[[viewlayer sublayers] objectAtIndex:0]];
    [self.view addSubview:view];
    dispatch_sync(dispatch_queue_create("encode", DISPATCH_QUEUE_SERIAL), ^{
        NSLog(@"recordVideo....");
        [self.h264encoder startEncodeSession:480 height:640 framerate:25 bitrate:1500*1000];
        [self.session startRunning];
    });
    
}
- (void) setupVideo
{
    self.videoDev = [self deviceWithMediaType:AVMediaTypeVideo preferringPosition:AVCaptureDevicePositionBack];
    NSError *error = nil;
    self.videoInput = [AVCaptureDeviceInput deviceInputWithDevice:self.videoDev error:&error];
    if (error) {
        NSLog(@"videoerror:%@", error);
        return;
    }
    if ([self.session canAddInput:self.videoInput]) {
        [self.session addInput:self.videoInput];
    }
    
    self.videoOutput = [[AVCaptureVideoDataOutput alloc] init];
    NSString* key = (NSString*)kCVPixelBufferPixelFormatTypeKey;
    
    NSNumber* val = [NSNumber numberWithUnsignedInt:kCVPixelFormatType_420YpCbCr8BiPlanarFullRange];
    NSDictionary* videoSettings = [NSDictionary dictionaryWithObject:val forKey:key];
    
    self.videoOutput.videoSettings = videoSettings;
    
    self.videoQueue = dispatch_queue_create("videoqueue", DISPATCH_QUEUE_SERIAL);
    [self.videoOutput setSampleBufferDelegate:self queue:self.videoQueue];
    
    if ([self.session canAddOutput:self.videoOutput]) {
        [self.session addOutput:self.videoOutput];
        AVCaptureConnection *captureConnection = [self.videoOutput connectionWithMediaType:AVMediaTypeVideo];
        // 视频稳定设置
        if ([captureConnection isVideoStabilizationSupported]) {
            captureConnection.preferredVideoStabilizationMode = AVCaptureVideoStabilizationModeAuto;
        }
        captureConnection.videoScaleAndCropFactor = captureConnection.videoMaxScaleAndCropFactor;
    }
}

- (void) setupAudio
{
    self.audioDev = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
    NSError *error = nil;
    self.audioDevInput = [AVCaptureDeviceInput deviceInputWithDevice:self.audioDev error:&error];
    if (error) {
        NSLog(@"audioerror=%@", error);
        return;
    }
    if ([self.session canAddInput:self.audioDevInput]) {
        [self.session addInput:self.audioDevInput];
    }
    self.audioQueue = dispatch_queue_create("Audio Capture Queue", DISPATCH_QUEUE_SERIAL);
    self.audioOutput = [[AVCaptureAudioDataOutput alloc] init];
    [self.audioOutput setSampleBufferDelegate:self queue:self.audioQueue];
    if ([self.session canAddOutput:self.audioOutput]) {
        [self.session addOutput:self.audioOutput];
    }
}

- (AVCaptureDevice *) deviceWithMediaType:(AVMediaType)mediaType preferringPosition:(AVCaptureDevicePosition)position
{
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    
    
    for (AVCaptureDevice *device in devices) {
        if (device.position == position) {
            return device;
        }
    }
    return nil;
}

#pragma mark - delegate
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    CMTime pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
    double dPTS = (double)(pts.value) / pts.timescale;
    if (output == self.videoOutput) {// 视频编码
        [self.h264encoder encodeFrame:sampleBuffer];
    } else if (output == self.audioOutput) {//音频编码
        
        
    }
}
- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end
