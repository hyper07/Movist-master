//
//  Movist
//
//  Copyright 2006 ~ 2008 Yong-Hoe Kim. All rights reserved.
//      Yong-Hoe Kim  <cocoable@gmail.com>
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

#import "ControlPanel.h"

#import "MMovieView.h"
#import "AppController.h"
#import "UserDefaults.h"
#import "MMovie_QuickTime.h"
#import "MMovie_FFmpeg.h"

@implementation ControlPanel

- (id)initWithContentRect:(NSRect)contentRect
                styleMask:(NSUInteger)styleMask
                  backing:(NSBackingStoreType)bufferingType
                    defer:(BOOL)deferCreation
{
    //TRACE(@"%s", __PRETTY_FUNCTION__);
    if (self = [super initWithContentRect:contentRect
                                styleMask:NSBorderlessWindowMask
                                  backing:bufferingType
                                    defer:deferCreation]) {
        [self initHUDWindow];
        [self setFloatingPanel:TRUE];
    }
    return self;
}

- (void)awakeFromNib
{
    //TRACE(@"%s", __PRETTY_FUNCTION__);
    [self updateHUDBackground];
    [self initHUDSubviews];

    _initialDragPoint.x = -1;
    _initialDragPoint.y = -1;

    [_videoBrightnessSlider setMinValue:MIN_BRIGHTNESS];
    [_videoBrightnessSlider setMaxValue:MAX_BRIGHTNESS];
    [_videoBrightnessSlider setFloatValue:DEFAULT_BRIGHTNESS];

    [_videoSaturationSlider setMinValue:MIN_SATURATION];
    [_videoSaturationSlider setMaxValue:MAX_SATURATION];
    [_videoSaturationSlider setFloatValue:DEFAULT_SATURATION];

    [_videoContrastSlider setMinValue:MIN_CONTRAST];
    [_videoContrastSlider setMaxValue:MAX_CONTRAST];
    [_videoContrastSlider setFloatValue:DEFAULT_CONTRAST];

    [_videoHueSlider setMinValue:MIN_HUE];
    [_videoHueSlider setMaxValue:MAX_HUE];
    [_videoHueSlider setFloatValue:DEFAULT_HUE];

    [_playbackRateSlider setMinValue:MIN_PLAY_RATE];
    [_playbackRateSlider setMaxValue:MAX_PLAY_RATE];
    [self updatePlaybackRateSlider:DEFAULT_PLAY_RATE];

    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    NSString* identifier = (NSString*)[defaults objectForKey:MControlTabKey];
    if (NSNotFound == [_tabView indexOfTabViewItemWithIdentifier:identifier]) {
        [_segmentedControl setSelectedSegment:0];
        [_tabView selectFirstTabViewItem:self];
    }
    else {
        int index = [_tabView indexOfTabViewItemWithIdentifier:identifier];
        [_segmentedControl setSelectedSegment:index];
        [_tabView selectTabViewItemWithIdentifier:identifier];
    }
}

- (void)dealloc
{
    [self cleanupHUDWindow];
    [super dealloc];
}

- (void)orderOut:(id)sender
{
    //TRACE(@"%s", __PRETTY_FUNCTION__);
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    NSString* identifier = (NSString*)[[_tabView selectedTabViewItem] identifier];
    [defaults setObject:identifier forKey:MControlTabKey];
    [super orderOut:sender];
}

- (BOOL)canBecomeKeyWindow { return FALSE; }

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark window-moving by dragging

- (void)mouseDown:(NSEvent*)event
{
    NSRect frame = [self frame];
    _initialDragPoint = [self convertBaseToScreen:[event locationInWindow]];
    _initialDragPoint.x -= frame.origin.x;
    _initialDragPoint.y -= frame.origin.y;
}

- (void)mouseUp:(NSEvent*)event
{
    _initialDragPoint.x = -1;
    _initialDragPoint.y = -1;
}

- (void)mouseDragged:(NSEvent*)event
{
    if (0 <= _initialDragPoint.x && 0 <= _initialDragPoint.y) {
        NSPoint p = [self convertBaseToScreen:[event locationInWindow]];
        NSRect sr = [[self screen] frame];
        NSRect wr = [self frame];
        
        NSPoint origin;
        origin.x = p.x - _initialDragPoint.x;
        origin.y = p.y - _initialDragPoint.y;
        if (NSMaxY(sr) < origin.y + wr.size.height) {
            origin.y = sr.origin.y + (sr.size.height - wr.size.height);
        }
        [self setFrameOrigin:origin];
    }
}

///////////////////////////////////////////////////////////////////////////////
#pragma mark -

- (void)showPanel { [self orderFront:self]; }
- (void)hidePanel { [self orderOut:self]; }

- (IBAction)segmentedControlAction:(id)sender
{
    [_tabView selectTabViewItemAtIndex:[_segmentedControl selectedSegment]];
}

- (void)setMovieURL:(NSURL*)url
{
    if (!url) {
        [_movieFilenameTextField setStringValue:@""];
    }
    else if ([url isFileURL]) {
        [_movieFilenameTextField setStringValue:[[url path] lastPathComponent]];
    }
    else {
        [_movieFilenameTextField setStringValue:[[url absoluteString] lastPathComponent]];
    }
}

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark video

- (IBAction)videoColorControlsAction:(id)sender
{
    //TRACE(@"%s %@", __PRETTY_FUNCTION__, sender);
    if (sender == _videoBrightnessSlider) {
        [_movieView setBrightness:normalizedFloat25([sender floatValue])];
        [_movieView setMessage:[NSString localizedStringWithFormat:@"%@ %.2f",
            NSLocalizedString(@"Brightness", nil), [_movieView brightness]]];
    }
    else if (sender == _videoSaturationSlider) {
        [_movieView setSaturation:normalizedFloat25([sender floatValue])];
        [_movieView setMessage:[NSString localizedStringWithFormat:@"%@ %.2f",
            NSLocalizedString(@"Saturation", nil), [_movieView saturation]]];
    }
    else if (sender == _videoContrastSlider) {
        [_movieView setContrast:normalizedFloat25([sender floatValue])];
        [_movieView setMessage:[NSString localizedStringWithFormat:@"%@ %.2f",
            NSLocalizedString(@"Contrast", nil), [_movieView contrast]]];
    }
    else if (sender == _videoHueSlider) {
        [_movieView setHue:normalizedFloat25([sender floatValue])];
        [_movieView setMessage:[NSString localizedStringWithFormat:@"%@ %.2f",
            NSLocalizedString(@"Hue", nil), [_movieView hue]]];
    }
}

- (IBAction)videoColorControlsDefaultsAction:(id)sender
{
    //TRACE(@"%s %d", __PRETTY_FUNCTION__, [sender tag]);
    switch ([sender tag]) {
        case 0 :
            [_videoBrightnessSlider setFloatValue:DEFAULT_BRIGHTNESS];
            [self videoColorControlsAction:_videoBrightnessSlider];
            break;
        case 1 :
            [_videoSaturationSlider setFloatValue:DEFAULT_SATURATION];
            [self videoColorControlsAction:_videoSaturationSlider];
            break;
        case 2 :
            [_videoContrastSlider setFloatValue:DEFAULT_CONTRAST];
            [self videoColorControlsAction:_videoContrastSlider];
            break;
        case 3 :
            [_videoHueSlider setFloatValue:DEFAULT_HUE];
            [self videoColorControlsAction:_videoHueSlider];
            break;
    }
}

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark audio

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark subtitle

- (float)subtitleTrackLoadingTime { return _subtitleTrackLoadingTime; }
- (void)setSubtitleTrackLoadingTime:(float)t { _subtitleTrackLoadingTime = t; }

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark playback

- (void)updatePlaybackRateSlider:(float)rate
{
    float value;
    const float dv = (3.0 - 0.5) / 6;
    if (rate <= 1.0) {
        value = (0.5 + dv * 0) + (2 * dv * (rate - 0.5)) / (1.0 - 0.5);
    }
    else if (rate <= 2.0) {
        value = (0.5 + dv * 2) + (2 * dv * (rate - 1.0)) / (2.0 - 1.0);
    }
    else {  // rate <= 3.0
        value = (0.5 + dv * 4) + (2 * dv * (rate - 2.0)) / (3.0 - 2.0);
    }
    [_playbackRateSlider setFloatValue:value];
}

- (IBAction)playbackRateAction:(id)sender
{
    const float dv = (3.0 - 0.5) / 6;
    if (sender == _playbackRateSlider) {
        float rate;
        float value = [_playbackRateSlider floatValue];
        if (value <= 0.5 + dv * 2) {        // 0.5 ~ 1.0 (2: 0.5, 0.75, 1.0)
            rate = 0.5 + (value - (0.5 + dv * 0)) * ((1.0 - 0.5) / 2) / dv;
        }
        else if (value <= 0.5 + dv * 5) {   // 1.0 ~ 2.0 (3: 1.0, 1.3, 1.6, 2.0)
            rate = 1.0 + (value - (0.5 + dv * 2)) * ((2.0 - 1.0) / 2) / dv;
        }
        else {                              // 2.0 ~ 3.0 (1: 2.0, 3.0)
            rate = 2.0 + (value - (0.5 + dv * 4)) * ((3.0 - 2.0) / 2) / dv;
        }
        [_appController setPlayRate:rate];
    }
    else {
        [_playbackRateSlider setFloatValue:0.5 + dv * 2];
        [_appController setPlayRate:DEFAULT_PLAY_RATE];
    }
}

@end
