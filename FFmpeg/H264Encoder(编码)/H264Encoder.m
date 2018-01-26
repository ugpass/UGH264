
//
//  H264Encoder.m
//  FFmpeg
//
//  Created by wenxiang on 2018/1/26.
//  Copyright © 2018年 wenxiang. All rights reserved.
//

#import "H264Encoder.h"

@interface H264Encoder()

{
    VTCompressionSessionRef _encodeSesion;
    dispatch_queue_t _encodeQueue;
    long    _frameCount;
    FILE    *_h264File;
    int     _spsppsFound;
    
}
@property (nonatomic, strong)NSString *documentDictionary;
@end
@implementation H264Encoder
- (instancetype)init
{
    if (self = [super init]) {
        _encodeQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
        self.documentDictionary = [(NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask, YES)) objectAtIndex:0];
        _h264File = fopen([[NSString stringWithFormat:@"%@/vt_encode.h264", self.documentDictionary] UTF8String], "wb");
    }
    return self;
}

#pragma mark - videotoolbox methods
- (int)startEncodeSession:(int)width height:(int)height framerate:(int)fps bitrate:(int)bt
{
    OSStatus status;
    _frameCount = 0;
    
    VTCompressionOutputCallback cb = encodeOutputCallback;
    status = VTCompressionSessionCreate(kCFAllocatorDefault, width, height, kCMVideoCodecType_H264, NULL, NULL, NULL, cb, (__bridge void *)(self), &_encodeSesion);
    
    if (status != noErr) {
        NSLog(@"VTCompressionSessionCreate failed. ret=%d", (int)status);
        return -1;
    }
    
    // 设置实时编码输出，降低编码延迟
    status = VTSessionSetProperty(_encodeSesion, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue);
    NSLog(@"set realtime  return: %d", (int)status);
    
    // h264 profile, 直播一般使用baseline，可减少由于b帧带来的延时
    status = VTSessionSetProperty(_encodeSesion, kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_Baseline_AutoLevel);
    NSLog(@"set profile   return: %d", (int)status);
    
    // 设置编码码率(比特率)，如果不设置，默认将会以很低的码率编码，导致编码出来的视频很模糊
    status  = VTSessionSetProperty(_encodeSesion, kVTCompressionPropertyKey_AverageBitRate, (__bridge CFTypeRef)@(bt)); // bps
    
    int bitRateLimit = width * height * 3 * 4;
    CFNumberRef bitRateLimitRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &bitRateLimit);
    status = VTSessionSetProperty(_encodeSesion, kVTCompressionPropertyKey_DataRateLimits, bitRateLimitRef);
    //    status += VTSessionSetProperty(_encodeSesion, kVTCompressionPropertyKey_DataRateLimits, (__bridge CFArrayRef)@[@(bt*2/8), @1]); // Bps
    NSLog(@"set bitrate   return: %d", (int)status);
    
    // 设置关键帧间隔，即gop size
    status = VTSessionSetProperty(_encodeSesion, kVTCompressionPropertyKey_MaxKeyFrameInterval, (__bridge CFTypeRef)@(fps*2));
    // 设置帧率，只用于初始化session，不是实际FPS
    status = VTSessionSetProperty(_encodeSesion, kVTCompressionPropertyKey_ExpectedFrameRate, (__bridge CFTypeRef)@(fps));
    NSLog(@"set framerate return: %d", (int)status);
    
    // 开始编码
    status = VTCompressionSessionPrepareToEncodeFrames(_encodeSesion);
    NSLog(@"start encode  return: %d", (int)status);
    
    return 0;
}

// 编码一帧图像，使用queue，防止阻塞系统摄像头采集线程
- (void) encodeFrame:(CMSampleBufferRef )sampleBuffer
{
    dispatch_sync(_encodeQueue, ^{
        CVImageBufferRef imageBuffer = (CVImageBufferRef)CMSampleBufferGetImageBuffer(sampleBuffer);
        
        // pts,必须设置，否则会导致编码出来的数据非常大，原因未知
        CMTime pts = CMTimeMake(_frameCount, 1000);
        CMTime duration = kCMTimeInvalid;
        
        VTEncodeInfoFlags flags;
        
        // 送入编码器编码
        OSStatus statusCode = VTCompressionSessionEncodeFrame(_encodeSesion,
                                                              imageBuffer,
                                                              pts, duration,
                                                              NULL, NULL, &flags);
        
        if (statusCode != noErr) {
            NSLog(@"H264: VTCompressionSessionEncodeFrame failed with %d", (int)statusCode);
            
            [self stopEncodeSession];
            return;
        }
    });
}

- (void) stopEncodeSession
{
    VTCompressionSessionCompleteFrames(_encodeSesion, kCMTimeInvalid);
    
    VTCompressionSessionInvalidate(_encodeSesion);
    
    CFRelease(_encodeSesion);
    _encodeSesion = NULL;
}

// 编码回调，每当系统编码完一帧之后，会异步掉用该方法，此为c语言方法
void encodeOutputCallback(void *userData, void *sourceFrameRefCon, OSStatus status, VTEncodeInfoFlags infoFlags,
                          CMSampleBufferRef sampleBuffer )
{
    if (status != noErr) {
        NSLog(@"didCompressH264 error: with status %d, infoFlags %d", (int)status, (int)infoFlags);
        return;
    }
    if (!CMSampleBufferDataIsReady(sampleBuffer))
    {
        NSLog(@"didCompressH264 data is not ready ");
        return;
    }
    H264Encoder* encoder = (__bridge H264Encoder*)userData;
    
    // 判断当前帧是否为关键帧
    bool keyframe = !CFDictionaryContainsKey( (CFArrayGetValueAtIndex(CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, true), 0)), kCMSampleAttachmentKey_NotSync);
    
    // 获取sps & pps数据. sps pps只需获取一次，保存在h264文件开头即可
    if (keyframe && !encoder->_spsppsFound)
    {
        size_t spsSize, spsCount;
        size_t ppsSize, ppsCount;
        
        const uint8_t *spsData, *ppsData;
        
        CMFormatDescriptionRef formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer);
        OSStatus err0 = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatDesc, 0, &spsData, &spsSize, &spsCount, 0 );
        OSStatus err1 = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatDesc, 1, &ppsData, &ppsSize, &ppsCount, 0 );
        
        if (err0==noErr && err1==noErr)
        {
            encoder->_spsppsFound = 1;
            [encoder writeH264Data:(void *)spsData length:spsSize addStartCode:YES];
            [encoder writeH264Data:(void *)ppsData length:ppsSize addStartCode:YES];
            NSLog(@"got sps/pps data. Length: sps=%zu----sps=, pps=%zu", spsSize, ppsSize);
        }
    }
    
    size_t lengthAtOffset, totalLength;
    char *data;
    
    CMBlockBufferRef dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    OSStatus error = CMBlockBufferGetDataPointer(dataBuffer, 0, &lengthAtOffset, &totalLength, &data);
    
    if (error == noErr) {
        size_t offset = 0;
        const int lengthInfoSize = 4; // 返回的nalu数据前四个字节不是0001的startcode，而是大端模式的帧长度length
        
        // 循环获取nalu数据
        while (offset < totalLength - lengthInfoSize) {
            uint32_t naluLength = 0;
            memcpy(&naluLength, data + offset, lengthInfoSize); // 获取nalu的长度，
            
            // 大端模式转化为系统端模式
            naluLength = CFSwapInt32BigToHost(naluLength);
            NSLog(@"got nalu data, length=%d, totalLength=%zu", naluLength, totalLength);
            //发送！！！
            
            
            // 保存nalu数据到文件
            [encoder writeH264Data:data+offset+lengthInfoSize length:naluLength addStartCode:YES];
            
            
            // 读取下一个nalu，一次回调可能包含多个nalu
            offset += lengthInfoSize + naluLength;
        }
    }
}

// 保存h264数据到文件
- (void) writeH264Data:(void*)data length:(size_t)length addStartCode:(BOOL)b
{
    // 添加4字节的 h264 协议 start code
    const Byte bytes[] = "\x00\x00\x00\x01";
    if (_h264File) {
        if(b)
            fwrite(bytes, 1, 4, _h264File);
        
        fwrite(data, 1, length, _h264File);
    } else {
        NSLog(@"_h264File null error, check if it open successed");
    }
}

@end
