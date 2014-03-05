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

#import "Movist.h"

@class AppController;
@class MMovieView;

@interface ControlPanel : NSPanel
{
    IBOutlet AppController* _appController;
    IBOutlet MMovieView* _movieView;
    IBOutlet NSSegmentedControl* _segmentedControl;
    IBOutlet NSTabView* _tabView;
    NSPoint _initialDragPoint;

    // Video
    IBOutlet NSSlider* _videoBrightnessSlider;
    IBOutlet NSSlider* _videoSaturationSlider;
    IBOutlet NSSlider* _videoContrastSlider;
    IBOutlet NSSlider* _videoHueSlider;

    // Audio

    // Subtitle
    float _subtitleTrackLoadingTime;

    // Playback
    IBOutlet NSSlider* _playbackRateSlider;

    // Properties
    IBOutlet NSTextField* _movieFilenameTextField;
}

- (void)showPanel;
- (void)hidePanel;
- (IBAction)segmentedControlAction:(id)sender;

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark video

- (IBAction)videoColorControlsAction:(id)sender;
- (IBAction)videoColorControlsDefaultsAction:(id)sender;

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark audio

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark subtitle
- (float)subtitleTrackLoadingTime;
- (void)setSubtitleTrackLoadingTime:(float)time;

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark playback

- (void)updatePlaybackRateSlider:(float)rate;
- (IBAction)playbackRateAction:(id)sender;

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark properites
- (void)setMovieURL:(NSURL*)url;

@end
