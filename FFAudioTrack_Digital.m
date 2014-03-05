//
//  Movist
//
//  Copyright 2006, 2007, 2008 Cheol Ju. All rights reserved.
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

// The S/PDIF part of the code is based on the auhal audio output
// module from VideoLAN:
// Copyright (C) 2005 the VideoLAN team
// Authors: Derk-Jan Hartman <hartman at videolan dot org>

#import "FFTrack.h"
#import "MMovie_FFmpeg.h"

OSStatus digitalAudioProc(AudioDeviceID           device,
                          const AudioTimeStamp*   now,
                          const AudioBufferList*  inputData,
                          const AudioTimeStamp*   inputTime,
                          AudioBufferList*        outputData,
                          const AudioTimeStamp*   outputTime,
                          void*                   clientData);
static int AudioStreamChangeFormat(AudioStreamID i_stream_id, AudioStreamBasicDescription change_format );

@interface AudioRawDataQueue : NSObject
{
    UInt8* _data;
    double* _time;
    NSRecursiveLock* _mutex;
    unsigned int _capacity;
    unsigned int _bufferCount;
    unsigned int _front;
    unsigned int _rear;
    unsigned int _remnant;
}
@end

@implementation AudioRawDataQueue

- (id)initWithCapacity:(unsigned int)capacity
{
    self = [super init];
    if (self) {
        _capacity = capacity;
        _bufferCount = capacity / 6144;
        _data = malloc(sizeof(UInt8) * _bufferCount * 6144);
        _time = malloc(sizeof(double) * _bufferCount);
        _mutex = [[NSRecursiveLock alloc] init];
        _front = 0;
        _rear = 0;
        _remnant = 0;
    }
    return self;
}

- (void)dealloc
{
    free(_data);
    free(_time);
    [_mutex release];
    [super dealloc];
}

- (void)clear { 
    //[_mutex lock];
    _rear = _front;
    //[_mutex unlock];
}

- (BOOL)isEmpty { return (_front == _rear); }
- (BOOL)isFull { return (_front == (_rear + 1) % _bufferCount); }

- (int)dataSize
{
    //[_mutex lock];
    int size = (_bufferCount + _rear - _front) % _bufferCount * 6144;
    //[_mutex unlock];
    return size;
}

- (double)current
{
    //[_mutex lock];
    if ([self isEmpty]) {
        //[_mutex unlock];
        return -1.;
    }
    double time = _time[_front];
    //[_mutex unlock];
    return time;
}

- (double)lastTime
{
    //[_mutex lock];
    if ([self isEmpty]) {
        //[_mutex unlock];
        return -1;
    }
    int index = (_rear + _bufferCount - 1) % _bufferCount;
    double time = _time[index];
    //[_mutex unlock];
    return time;
}

- (BOOL)putData:(UInt8*)data size:(int)size time:(double)time
{
    //[_mutex lock];
    if ([self isFull]) {
        //[_mutex unlock];
        return FALSE;
    }
    assert(_remnant + size <= 6144);
    memcpy(&_data[6144 * _rear + _remnant], data, size);
    if (_remnant == 0) {
        _time[_rear] = time;
    }
    if (_remnant + size == 6144) {
        _rear = (_rear + 1) % _bufferCount;
        _remnant = 0;
    } 
    else {
        _remnant += size;
    }
    //[_mutex unlock];
    return TRUE;
}

- (BOOL)getData:(UInt8*)data
{
    //[_mutex lock];
    if ([self isEmpty]) {
        //[_mutex unlock];
        return FALSE;
    }
    memcpy(data, &_data[6144 * _front], 6144);
    _front = (_front + 1) % _bufferCount;
    //[_mutex unlock];
    return TRUE;
}

- (BOOL)removeData
{
    //[_mutex lock];
    if ([self isEmpty]) {
        //[_mutex unlock];
        return FALSE;
    }
    _front = (_front + 1) % _bufferCount;
    //[_mutex unlock];
    return TRUE;
}

- (void)removeDataUntilTime:(double)time 
{
    //[_mutex lock];
    while (![self isEmpty]) {
        if (time <= _time[_front]) {
            break;
        }
        _front = (_front + 1) % _bufferCount;
    }
    //[_mutex unlock];
}

@end


@implementation FFAudioTrack (Digital)

// TODO: make these member vars
static AudioDeviceID s_audioDeviceId = 0;
static BOOL s_first = TRUE;
static AudioDeviceIOProcID s_theIOProcID = NULL;

- (AudioDeviceID)getDeviceId
{
    AudioDeviceID audioDev = 0;
    UInt32 paramSize = sizeof(AudioDeviceID);
	AudioObjectPropertyAddress propertyAddress = {
		kAudioHardwarePropertyDefaultOutputDevice,
		kAudioObjectPropertyScopeGlobal,
		kAudioObjectPropertyElementMaster
	};
	OSStatus err = AudioObjectGetPropertyData(kAudioObjectSystemObject, &propertyAddress, 0, NULL, &paramSize, &audioDev);
    if (err != noErr) {
        TRACE(@"failed to get device id : [%4.4s]\n", (char *)&err);
        assert(FALSE);
        return 0;
    }
    return audioDev;
}

- (BOOL)setDeviceHogMode:(BOOL)hog
{
    pid_t pid = hog ? getpid() : -1;
	AudioObjectPropertyAddress propertyAddress = {
		kAudioDevicePropertyHogMode,
		kAudioDevicePropertyScopeOutput,
		kAudioObjectPropertyElementMaster
	};
	OSStatus err = AudioObjectSetPropertyData(_audioDev, &propertyAddress, 0, NULL, sizeof(pid_t), &pid);
    if (err != noErr ) {
        TRACE(@"failed to set hogmode %d : [%4.4s]", hog, (char *)&err );
        return FALSE;
    }
    return TRUE;
}

- (BOOL)setDeviceMixable:(BOOL)mixable
{
	OSStatus err;
    UInt32 paramSize = 0;
    Boolean writable, mix;
	AudioObjectPropertyAddress propertyAddress = {
		kAudioDevicePropertySupportsMixing,
		kAudioObjectPropertyScopeGlobal, // seems like it should be "kAudioDevicePropertyScopeOutput", but I guess not?
		kAudioObjectPropertyElementMaster
	};
	err = AudioObjectIsPropertySettable(_audioDev, &propertyAddress, &writable);
	paramSize = sizeof(Boolean);
	err = AudioObjectGetPropertyData(_audioDev, &propertyAddress, 0, NULL, &paramSize, &mix);
	if (err != noErr && writable)
	{
		mix = mixable;
		err = AudioObjectSetPropertyData(_audioDev, &propertyAddress, 0, NULL, paramSize, &mix);
    }
    if (err != noErr) {
        TRACE(@"failed to set mixmode %d : [%4.4s]\n", mixable, (char *)&err);
        return FALSE;
    }
    return TRUE;
}

- (BOOL)initDigitalAudio:(int*)error
{
    OSStatus err = noErr;
    UInt32 paramSize = sizeof(AudioDeviceID);
    if (s_audioDeviceId) {
        _audioDev = s_audioDeviceId;
    }
    else {
        _audioDev = [self getDeviceId];
        if (!_audioDev) {
            return FALSE;
        }
        s_audioDeviceId = _audioDev;
    }

    if (![self setDeviceHogMode:TRUE]) {
        return FALSE;
    }
    [self setDeviceMixable:FALSE];

	AudioObjectPropertyAddress propertyAddress = {
		kAudioDevicePropertyStreams,
		kAudioDevicePropertyScopeOutput,
		kAudioObjectPropertyElementMaster
	};
    /* Retrieve all the output streams. */
	err = AudioObjectGetPropertyDataSize(_audioDev, &propertyAddress, 0, NULL, &paramSize);
    if (err != noErr) {
        TRACE(@"could not get number of streams: [%4.4s]\n", (char *)&err);
        return FALSE;
    }
    int streamCount = paramSize / sizeof(AudioStreamID);
	AudioStreamID* stream = (AudioStreamID*)malloc(paramSize);
	err = AudioObjectGetPropertyData(_audioDev, &propertyAddress, 0, NULL, &paramSize, stream);
    if (err != noErr) {
        TRACE(@"could not get number of streams: [%4.4s]\n", (char *)&err);
        free(stream);
        return FALSE;
    }

    int i, j;
    AudioStreamBasicDescription desc;
    for (i = 0; i < streamCount; i++) {
        /* Find a stream with a cac3 stream */
        AudioStreamBasicDescription* format = 0;
		propertyAddress.mSelector = kAudioStreamPropertyPhysicalFormats;
		propertyAddress.mScope    = kAudioObjectPropertyScopeGlobal;
        /* Retrieve all the stream formats supported by each output stream */
		err = AudioObjectGetPropertyDataSize(stream[i], &propertyAddress, 0, NULL, &paramSize);
        if (err != noErr ) {
            TRACE(@"could not get number of streamformats: [%4.4s]", (char *)&err );
            continue;
        }
        int formatCount = paramSize / sizeof(AudioStreamBasicDescription);
        format = (AudioStreamBasicDescription*)malloc(paramSize);
		err = AudioObjectGetPropertyData(stream[i], &propertyAddress, 0, NULL, &paramSize, format);
        if (err != noErr) {
            TRACE(@"could not get the list of streamformats: [%4.4s]", (char *)&err );
            free(format);
            continue;
        }
        /* Check if one of the supported formats is a digital format */
        for (j = 0; j < formatCount; j++) {
            if (format[j].mFormatID == 'IAC3' ||
                format[j].mFormatID == kAudioFormat60958AC3) {
                if ((int)(format[j].mSampleRate) == _stream->codec->sample_rate) {
                    desc = format[j];
                    break;
                }
            }
        }
        free(format);
        if (j < formatCount) {
            _digitalStream = stream[i];
            break;
        }
    }
    free(stream);
    if (i == streamCount) {
        TRACE(@"could not find a properstreamformat");
        return FALSE;
    }
    
    if (s_first) {
        /* Retrieve the original format of this stream first if not done so already */
        paramSize = sizeof(_originalDesc);
		propertyAddress.mSelector = kAudioStreamPropertyPhysicalFormat;
		err = AudioObjectGetPropertyData(_digitalStream, &propertyAddress, 0, NULL, &paramSize, &_originalDesc);
        if (err != noErr) {
            TRACE(@"could not retrieve the original streamformat: [%4.4s]", (char *)&err );
            assert(FALSE);
        }
        s_first = FALSE;
    }
    
    if (!AudioStreamChangeFormat(_digitalStream, desc)) {
        return FALSE;
    }
    _currentDesc = desc;
    _bigEndian = _currentDesc.mFormatFlags & kAudioFormatFlagIsBigEndian;

	err = AudioDeviceCreateIOProcID(_audioDev, digitalAudioProc, (void *)self, &s_theIOProcID);
    if (err != noErr) {
        TRACE(@"AudioDeviceAddIOProc failed: [%4.4s]", (char *)&err );
        return FALSE;
    }
    _rawDataQueue = [[AudioRawDataQueue alloc] initWithCapacity:6144 * 256];
    return TRUE;
}

- (void)cleanupDigitalAudio
{
    /* Remove IOProc callback */
	OSStatus err = AudioDeviceDestroyIOProcID(_audioDev, s_theIOProcID);
    if (err != noErr) {
        TRACE(@"AudioDeviceRemoveIOProc failed: [%4.4s]", (char *)&err );
    }
    AudioStreamChangeFormat(_digitalStream, _originalDesc);
    _currentDesc = _originalDesc;
    _bigEndian = _currentDesc.mFormatFlags & kAudioFormatFlagIsBigEndian;
    [self setDeviceMixable:TRUE];
    
/*
    err = AudioHardwareRemovePropertyListener(kAudioHardwarePropertyDevices,
                                              HardwareListener );
    
    if (err != noErr) {
        TRACE(@"AudioHardwareRemovePropertyListener failed: [%4.4s]", (char *)&err );
    }    
*/
    [self setDeviceHogMode:FALSE];
    _audioDev = 0;
    [_rawDataQueue clear];
    [_rawDataQueue release];
    _rawDataQueue = 0;
    _running = FALSE;
}

- (void)startDigitalAudio
{
    if (noErr !=  AudioDeviceStart(_audioDev, s_theIOProcID)) {
        TRACE(@"AudioDeviceStart failed");
        assert(FALSE);
    }
    return;
}

- (void)stopDigitalAudio
{
    if (noErr != AudioDeviceStop(_audioDev, s_theIOProcID)) {
        //_started = FALSE;
        TRACE(@"AudioDeviceStop failed");
        return;
    }
}

- (void)enqueueAc3Data:(AVPacket*)packet
{
    static const UInt8 HEADER_LE[] = {0x72, 0xf8, 0x1f, 0x4e, 0x01, 0x00};        
    static const UInt8 HEADER_BE[] = {0xF8, 0x72, 0x4E, 0x1F, 0x00, 0x01};

    UInt8 buffer[6144];
    UInt8* packetPtr = packet->data;
    int packetSize = packet->size;
    int i;
    /* Copy the S/PDIF headers. */
    if (_bigEndian) {
        memcpy(buffer, HEADER_BE, sizeof(HEADER_BE));
        buffer[4] = packetPtr[5] & 0x7; /* bsmod */
        buffer[6] = ((packetSize / 2) >> 4) & 0xff;
        buffer[7] = ((packetSize / 2) << 4) & 0xff;
        memcpy(buffer + 8, packetPtr, packetSize);
    }
    else {
        memcpy(buffer, HEADER_LE, sizeof(HEADER_LE));
        buffer[5] = packetPtr[5] & 0x07; /* bsmod */
        buffer[6] = ((packetSize / 2)<< 4) & 0xff;
        buffer[7] = ((packetSize / 2)>> 4) & 0xff;
        swab(packetPtr, buffer + 8, packetSize);
    }
    for (i = packetSize + 8; i < 6144; i++) {
        buffer[i] = 0;
    }
    double decodedAudioTime = (double)1. * packet->dts * PTS_TO_SEC;
    [_rawDataQueue putData:buffer size:6144 time:decodedAudioTime];    
}

- (void)enqueueDtsData:(AVPacket*)packet
{
    //TRACE(@"audio time %lld * %lf = %lf", packet->dts, PTS_TO_SEC, 1. * packet->dts * PTS_TO_SEC);
    static const uint8_t HEADER_LE[6] = { 0x72, 0xF8, 0x1F, 0x4E, 0x00, 0x00 };
    static const uint8_t HEADER_BE[6] = { 0xF8, 0x72, 0x4E, 0x1F, 0x00, 0x00 };
    uint32_t i_ac5_spdif_type = 0x0B; // FIXME what is it?
    UInt8 buffer[6144];
    const UInt8* packetPtr = packet->data;
    int packetSize = packet->size;
    
    if (_bigEndian) {
        memcpy(buffer, HEADER_BE, sizeof(HEADER_BE));
        buffer[5] = i_ac5_spdif_type;
    }
    else {
        memcpy(buffer, HEADER_LE, sizeof(HEADER_LE));
        buffer[4] = i_ac5_spdif_type;
    }
    buffer[6] = (packetSize<< 3) & 0xFF;
    buffer[7] = (packetSize>> 5) & 0xFF;
    
    UInt8 p0 = packetPtr[0];
    if (((p0 == 0xFF || p0 == 0xFE) && _bigEndian) ||
        ((p0 == 0x1F || p0 == 0x7F) && !_bigEndian)) {
        swab(packetPtr, buffer + 8, packetSize);
    }
    else {
        memcpy(buffer + 8, packetPtr, packetSize);        
    }
    double decodedAudioTime = (double)1. * packet->dts * PTS_TO_SEC;
    assert(packetSize + 8 <= 6144/3);
    //TRACE(@"audio time %lld * %lf = %lf", packet->dts, PTS_TO_SEC, decodedAudioTime);
    [_rawDataQueue putData:buffer size:6144/3 time:decodedAudioTime];        
}

- (void)putDigitalAudioPacket:(AVPacket*)packet
{
    AVCodecContext* context = _stream->codec;
    if (packet->data == s_flushPacket.data) {
        avcodec_flush_buffers(context);
        return;
    }        
    
    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];    
    
    if (_stream->codec->codec_id == CODEC_ID_DTS) {
        [self enqueueDtsData:packet];
    }
    else {
        [self enqueueAc3Data:packet];
    }
    // ?????? mkv ????????? ?????? ????????? decoding ??? ????????? ?????? packet ??? dts ?????? ????????? ??????.
    UInt8* packetPtr = packet->data;
    int packetSize = packet->size;
    int decodedSize;
	int got_frame;
    while (0 < packetSize) {
		decodedSize = avcodec_decode_audio4(context, _decodedFrame, &got_frame, packet);
        if (decodedSize < 0) { 
            TRACE(@"decodedSize < 0");
            break;
        }
        packetPtr  += decodedSize;
        packetSize -= decodedSize;
    }
    if (packet->data) {
        av_free_packet(packet);
    }
    [pool release];
}

- (void)nextDigitalAudio:(AudioBuffer)audioBuf
               timeStamp:(const AudioTimeStamp*)timeStamp
{
    int requestSize = audioBuf.mDataByteSize;
    if (requestSize != 6144) {
        //TRACE(@"request audio data size %d", requestSize);
    }
    _dataPoppingStarted = TRUE;
    if (![self isEnabled] || 
        [_movie quitRequested] ||
        [_movie reservedCommand] != COMMAND_NONE ||
        [_movie isPlayLocked] ||
        [_movie command] != COMMAND_PLAY ||
		[_movie hostTime0point] == 0.0 ||
        [_rawDataQueue isEmpty]) {
        memset((uint8_t*)(audioBuf.mData), 0, audioBuf.mDataByteSize);
        //TRACE(@"no audio data, queue(%f)", [_rawDataQueue current]);
        [_movie audioTrack:self avFineTuningTime:(double)0];
        _dataPoppingStarted = FALSE;
        return;
    }
    
    double hostTime = 1. * timeStamp->mHostTime / [_movie hostTimeFreq];
    double currentTime = hostTime - [_movie hostTime0point];
    double audioTime = [_rawDataQueue current];
    
    double dt = audioTime - currentTime;
    if (dt < -0.2 || 0.2 < dt) {
        if (dt < 0 && currentTime < [_rawDataQueue lastTime]) {
            [_rawDataQueue removeDataUntilTime:currentTime];
            if ([_rawDataQueue isEmpty]) {
                memset((uint8_t*)(audioBuf.mData), 0, audioBuf.mDataByteSize);
                [_movie audioTrack:self avFineTuningTime:0];
                //TRACE(@"currentTime(%f) audioTime %f dt:%f", currentTime, audioTime, dt);
                _dataPoppingStarted = FALSE;
                return;
            }
            dt = 0;
        }
        else {
            memset((uint8_t*)(audioBuf.mData), 0, audioBuf.mDataByteSize);
            [_movie audioTrack:self avFineTuningTime:0];
            //TRACE(@"currentTime(%f) audioTime %f dt:%f", currentTime, audioTime, dt);
            _dataPoppingStarted = FALSE;
            return;
        }
    }
    else if (-0.01 < dt && dt < 0.01) {
        dt = 0;
    }
    [_movie audioTrack:self avFineTuningTime:dt];    

    if ([_movie muted]) {
        [_rawDataQueue removeData];
        memset((uint8_t*)(audioBuf.mData), 0, audioBuf.mDataByteSize);
    }
    else {
        [_rawDataQueue getData:(UInt8*)(audioBuf.mData)];
    }
    _dataPoppingStarted = FALSE;
}

- (void)clearDigitalDataQueue
{
    [_rawDataQueue clear];
}

@end

OSStatus digitalAudioProc(AudioDeviceID           device,
                          const AudioTimeStamp*   now,
                          const AudioBufferList*  inputData,
                          const AudioTimeStamp*   inputTime,
                          AudioBufferList*        outputData,
                          const AudioTimeStamp*   outputTime,
                          void*                   clientData) {
//    TRACE(@"%llu %llu", inputTime->mHostTime, outputTime->mHostTime);
    FFAudioTrack* track = (FFAudioTrack*)clientData;
    [track nextDigitalAudio:outputData->mBuffers[0]
                  timeStamp:(const AudioTimeStamp*)outputTime];
    return noErr;
}

/*****************************************************************************
 * StreamListener
 *****************************************************************************/
static OSStatus StreamListener(AudioStreamID inStream,
                               UInt32 inChannel,
                               AudioDevicePropertyID inPropertyID,
                               void * inClientData )
{
    OSStatus err = noErr;
    return err;
}

/*****************************************************************************
 * AudioStreamChangeFormat: Change i_stream_id to change_format
 *****************************************************************************/
static int AudioStreamChangeFormat(AudioStreamID i_stream_id, AudioStreamBasicDescription change_format )
{
    OSStatus            err = noErr;
    UInt32              paramSize = 0;
    int i;

#if 0
    /* Install the callback */
    err = AudioStreamAddPropertyListener( i_stream_id, 0,
                                         kAudioStreamPropertyPhysicalFormat,
                                         StreamListener, 0 );
    if( err != noErr )
    {
        TRACE(@"AudioStreamAddPropertyListener failed: [%4.4s]", (char *)&err );
        return FALSE;
    }
#endif

	AudioObjectPropertyAddress propertyAddress = {
		kAudioStreamPropertyPhysicalFormat,
		kAudioObjectPropertyScopeGlobal,
		kAudioObjectPropertyElementMaster
	};

    /* change the format */
	err = AudioObjectSetPropertyData(i_stream_id, &propertyAddress, 0, NULL, sizeof(AudioStreamBasicDescription), &change_format);
    if( err != noErr )
    {
        TRACE(@"could not set the stream format: [%4.4s]", (char *)&err );
        return FALSE;
    }
    /* The AudioStreamSetProperty is not only asynchronious (requiring the locks)
     * it is also not atomic in its behaviour.
     * Therefore we check 5 times before we really give up.
     * FIXME: failing isn't actually implemented yet. */
    for( i = 0; i < 5; i++ )
    {
        AudioStreamBasicDescription actual_format;
        paramSize = sizeof( AudioStreamBasicDescription );
		err = AudioObjectGetPropertyData(i_stream_id, &propertyAddress, 0, NULL, &paramSize, &actual_format);
        
        //msg_Dbg( p_aout, STREAM_FORMAT_MSG( "actual format in use: ", actual_format ) );
        if (actual_format.mSampleRate == change_format.mSampleRate &&
            actual_format.mFormatID == change_format.mFormatID &&
            actual_format.mFramesPerPacket == change_format.mFramesPerPacket) {
            /* The right format is now active */
            break;
        }
        else {
            TRACE(@"[%s] we wait", __PRETTY_FUNCTION__);
        }
        /* We need to check again */
        [NSThread sleepUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
#if 0        
    /* Removing the property listener */
    err = AudioStreamRemovePropertyListener( i_stream_id, 0,
                                            kAudioStreamPropertyPhysicalFormat,
                                            StreamListener );
    if( err != noErr )
    {
        TRACE(@"AudioStreamRemovePropertyListener failed: [%4.4s]", (char *)&err );
        return FALSE;
    }
#endif
    return TRUE;
}

