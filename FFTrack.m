//
//  Movist
//
//  Copyright 2006 ~ 2008 Yong-Hoe Kim, Cheol Ju. All rights reserved.
//      Yong-Hoe Kim  <cocoable@gmail.com>
//      Cheol Ju      <moosoy@gmail.com>
//
//  This file is part of Movist.
//
//  Movist is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation; either version 3 of the License, or
//  (at your option) any later version.
//
//  Movist is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

#import "FFTrack.h"
#import "MMovie_FFmpeg.h"
#include <sys/types.h>
#include <sys/sysctl.h>

@implementation FFContext

+ (id)contextWithAVStream:(AVStream*)stream index:(int)index
{
    return [[[FFContext alloc] initWithAVStream:stream index:index] autorelease];
}

- (id)initWithAVStream:(AVStream*)stream index:(int)index
{
    if ((self = [super init])) {
        _streamIndex = index;
        _stream = stream;
    }
    return self;
}

- (int)streamIndex { return _streamIndex; }
- (AVStream*)stream { return _stream; }

- (BOOL)initContext:(int*)errorCode
{
    AVCodecContext* context = _stream->codec;
    AVCodec* codec = avcodec_find_decoder(context->codec_id);
    if (!codec) {
        *errorCode = ERROR_FFMPEG_DECODER_NOT_FOUND;
        return FALSE;
    }

    context->debug_mv = 0;
    context->debug = 0;
    context->workaround_bugs = 1;
    context->lowres = 0;
    if (context->lowres) {
        context->flags |= CODEC_FLAG_EMU_EDGE;
    }
    context->idct_algo = FF_IDCT_AUTO;
    /* this is already set
       by initTrack:videoQueueCapacity:useFastDecoding: in FFVideoTrack.m.
    if (fast) {
        context->flags2 |= CODEC_FLAG2_FAST;
    }
     */
    context->skip_frame = AVDISCARD_DEFAULT;
    context->skip_idct = AVDISCARD_DEFAULT;
    context->skip_loop_filter = AVDISCARD_DEFAULT;
    context->err_recognition = AV_EF_CRCCHECK;
	context->error_concealment = 3;
	
    if (context->codec_type == AVMEDIA_TYPE_VIDEO) {
        int cpuCount;
        size_t oldlen = 4;
        if (sysctlbyname("hw.activecpu", &cpuCount, &oldlen, NULL, 0) == 0) {
            if (1 < cpuCount) {
                context->thread_count = 2;
            }
        }
    }
    
    if (avcodec_open2(context, codec, NULL) < 0) {
        *errorCode = ERROR_FFMPEG_CODEC_OPEN_FAILED;
        return FALSE;
    }
	
    return TRUE;
}

- (void)cleanupContext
{
    if (_stream->codec) {
        avcodec_close(_stream->codec);
    }
}

@end

////////////////////////////////////////////////////////////////////////////////
#pragma mark -

AVPacket s_flushPacket;

@implementation FFTrack

+ (void)initialize
{
    av_init_packet(&s_flushPacket);
    s_flushPacket.data = (uint8_t*)"FLUSH";
}

- (void)setMovie:(MMovie_FFmpeg*)movie { _movie = [movie retain]; }

- (void)dealloc
{
    //TRACE(@"%s", __PRETTY_FUNCTION__);
    [_movie release];
    [super dealloc];
}

- (BOOL)initTrack:(int*)errorCode
{
    if (![self initContext:errorCode]) {
        return FALSE;
    }
    _dataPoppingStarted = FALSE;

    return TRUE;
}

- (void)cleanupTrack
{
    // -[quit] should be sent before sending -[cleanupTrack].
    assert(!_running);
    [self cleanupContext];
}

- (void)quit
{
    while (_running) {
        [NSThread sleepUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    }
}

- (BOOL)isEnabled { return _enabled; }
- (void)setEnabled:(BOOL)enabled { _enabled = enabled; }

- (BOOL)isDataPoppingStarted { return _dataPoppingStarted; }

- (void)putPacket:(AVPacket*)packet {}

@end
