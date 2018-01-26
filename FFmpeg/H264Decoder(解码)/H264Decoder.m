
//
//  H264Decoder.m
//  FFmpeg
//
//  Created by wenxiang on 2018/1/26.
//  Copyright © 2018年 wenxiang. All rights reserved.
//

#import "H264Decoder.h"

static AVPacket *packet;
static AVFrame *frame;
static AVCodec *codec;
static AVCodecContext *codecContext;
static AVCodecParserContext *parserContext;
struct SwsContext *swsContext;

static uint8_t *pictureData[4];
static int pictureLineSize[4];

@implementation H264Decoder

- (instancetype)init
{
    if (self = [super init]) {
        avcodec_register_all();
        packet = av_packet_alloc();
        
        if (!packet) {
            NSLog(@"初始化解码器失败");
        }
        
        codec = avcodec_find_decoder(AV_CODEC_ID_H264);
        if (!codec) {
            NSLog(@"初始化解码器失败");
        }
        NSLog(@"%s", codec->name);
        
        parserContext = av_parser_init(codec->id);
        if (!parserContext) {
            NSLog(@"初始化解码器失败");
        }
        
        codecContext = avcodec_alloc_context3(codec);
        if (!codecContext) {
            NSLog(@"初始化解码器失败");
        }
        
        if (avcodec_open2(codecContext, codec, NULL) < 0) {
            NSLog(@"初始化解码器失败");
        }
        
        frame = av_frame_alloc();
        if (!frame) {
            NSLog(@"初始化解码器失败");
        }
        
    }
    return self;
}

-(void)decodeData:(NSData *)data
{
    NSMutableData *tmpData = [NSMutableData dataWithData:data];
    
    while (tmpData.length>0) {
        int len = av_parser_parse2(parserContext, codecContext, &packet->data, &packet->size, tmpData.bytes, tmpData.length, AV_NOPTS_VALUE, AV_NOPTS_VALUE, 0);
        if (len<0) {
            NSLog(@"解码失败");
            return;
        }
        
        NSMutableData *subData = [NSMutableData dataWithData:[tmpData subdataWithRange:NSMakeRange(len, tmpData.length - len)]];
        tmpData = subData;
        if(packet->size) {
            [self decodeCodecContext:codecContext frame:frame packet:packet];
        }
    }
}

- (void) decodeCodecContext:(AVCodecContext *)codeContext frame:(AVFrame*)frame packet:(AVPacket*)packet{
    int ret = avcodec_send_packet(codeContext, packet);
    if (ret < 0) {
        NSLog(@"解码失败");
        return;
    }
    while (ret>=0) {
        ret = avcodec_receive_frame(codeContext, frame);
        if (ret == AVERROR_EOF || ret == AVERROR(EAGAIN)) {
            return;
        }else if (ret < 0) {
            NSLog(@"解码失败");
            return;
        }
        
        UIImage *img = [self convertFrameToImage:frame];
        NSData *imgData = UIImagePNGRepresentation(img);
        
        NSString *fileName = [NSString stringWithFormat:@"%d.jpg", codeContext->frame_number];
        NSString *documentPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        NSString *fileOutputPath = [documentPath stringByAppendingPathComponent:fileName];
        NSLog(@"filepath=%@", documentPath);
       
        [imgData writeToFile:fileOutputPath atomically:YES];
        
    }
}

- (UIImage *) convertFrameToImage:(AVFrame*)frame
{
    if (frame->data[0]) {
        int width = frame->width;
        int height = frame->height;
        
        swsContext = sws_getContext(width, height, frame->format, width, height, AV_PIX_FMT_RGBA, SWS_POINT, 0, 0, 0);
        if (swsContext == NULL) {
            return nil;
        }
        int det_bpp = av_get_bits_per_pixel(av_pix_fmt_desc_get(AV_PIX_FMT_RGBA));
        if (frame->key_frame) {
            av_image_alloc(pictureData, pictureLineSize, width, height, AV_PIX_FMT_RGBA, 1);
        }
        
        sws_scale(swsContext, frame->data, frame->linesize, 0, height, pictureData, pictureLineSize);
        
        CFDataRef dataRef = CFDataCreateWithBytesNoCopy(kCFAllocatorDefault, pictureData[0], pictureLineSize[0] * height, kCFAllocatorNull);
        CGColorSpaceRef colorspace = CGColorSpaceCreateDeviceRGB();
        CGDataProviderRef provider = CGDataProviderCreateWithCFData(dataRef);
        CGImageRef cgimage = CGImageCreate(width, height, 8, det_bpp, pictureLineSize[0], colorspace, kCGBitmapByteOrderDefault, provider, NULL, NO, kCGRenderingIntentDefault);
        UIImage *img = [UIImage imageWithCGImage:cgimage];
        CGImageRelease(cgimage);
        CGDataProviderRelease(provider);
        CGColorSpaceRelease(colorspace);
        CFRelease(dataRef);
        return img;
    }
    return nil;
}

- (void)dealloc
{
    if (codecContext) {
        avcodec_close(codecContext);
        avcodec_free_context(&codecContext);
        codecContext = NULL;
    }
}

@end
