//
//  H264Encoder.h
//  FFmpeg
//
//  Created by wenxiang on 2018/1/26.
//  Copyright © 2018年 wenxiang. All rights reserved.
//

#import <Foundation/Foundation.h>
 

@interface H264Encoder : NSObject

- (int)startEncodeSession:(int)width height:(int)height framerate:(int)fps bitrate:(int)bt;
- (void) encodeFrame:(CMSampleBufferRef )sampleBuffer;
@end
