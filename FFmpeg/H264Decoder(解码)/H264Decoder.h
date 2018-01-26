//
//  H264Decoder.h
//  FFmpeg
//
//  Created by wenxiang on 2018/1/26.
//  Copyright © 2018年 wenxiang. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>


@interface H264Decoder : NSObject

- (void) decodeData:(NSData *)data;

@end
