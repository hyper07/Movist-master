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

#import "AppController.h"
#import "UserDefaults.h"

#import "MMovie.h"
#import "Playlist.h"
#import "PlaylistController.h"

#import "MainWindow.h"
#import "MMovieView.h"
#import "FullScreener.h"
#import "PlayPanel.h"

@implementation AppController (Playlist)

- (Playlist*)playlist { return _playlist; }

- (void)addFiles:(NSArray*)filenames
{
    //TRACE(@"%s", __PRETTY_FUNCTION__);
    [_playlist addFiles:filenames];
    [_playlistController updateUI];
    [_propertiesView reloadData];
}

- (void)addSubtitleFiles:(NSArray*)filenames
{
    [self addSubtitles:URLsFromFilenames(filenames)];
}

- (void)updatePrevNextMovieButtons
{
    BOOL enabled = (1 < [_playlist count]);
    [_prevMovieButton setEnabled:enabled];
    [_nextMovieButton setEnabled:enabled];
}

- (BOOL)openCurrentPlaylistItem
{
    //TRACE(@"%s", __PRETTY_FUNCTION__);
    PlaylistItem* item = [_playlist currentItem];
    return [self openMovie:[item movieURL] movieClass:nil
                 subtitles:[item subtitleURLs] subtitleEncoding:kCFStringEncodingInvalidId];
}

- (void)openPrevPlaylistItem
{
    //TRACE(@"%s", __PRETTY_FUNCTION__);
    [_playlist setPrevItem];
    if (![self openCurrentPlaylistItem]) {
        [self playlistEnded];
    }
}

- (void)openNextPlaylistItem
{
    //TRACE(@"%s", __PRETTY_FUNCTION__);
    [_playlist setNextItem];
    if (![self openCurrentPlaylistItem]) {
        [self playlistEnded];
    }
}

- (void)playlistEnded
{
    if ([self isFullNavigation]) {
        if ([_fullScreener isNavigating]) {
            // preview is over => do nothing
        }
        else {
            [_fullScreener closeCurrent];
        }
    }
    else {
        if ([self isFullScreen]) {
            [self endFullScreen];
        }
        else if ([self isDesktopBackground]) {
            [self endDesktopBackground];
        }
        [_movieView setMessage:@""];
        [_movieView showLogo];
    }
}

////////////////////////////////////////////////////////////////////////////////
#pragma mark -

- (void)setRepeatMode:(unsigned int)mode
{
    //TRACE(@"%s %d", __PRETTY_FUNCTION__, mode);
	NSMenuItem* item = nil;
	for (item in [_controlMenu itemArray]) {
        if ([item action] == @selector(repeatAction:) && [item tag] == mode) {
			break;
        }
    }
	[_movieView setMessage:(item) ? [item title] : @""];
         
    [_playlist setRepeatMode:mode];
    [self updateRepeatUI];
}

////////////////////////////////////////////////////////////////////////////////
#pragma mark -

- (void)loadLastPlayedMovieInfo
{
    _lastPlayedMovieURL = nil;
    _lastPlayedMovieTime = 0.0;

    if ([_defaults boolForKey:MRememberLastPlayKey]) {
        NSData* data = [_defaults objectForKey:MPlaylistKey];
        if (data) {
            [_playlist release];
            _playlist = [[NSKeyedUnarchiver unarchiveObjectWithData:data] retain];
        }
        if (0 < [_playlist count]) {
            _lastPlayedMovieURL = [[[_playlist currentItem] movieURL] retain];
            _lastPlayedMovieTime = [_defaults floatForKey:MLastPlayedMovieTimeKey];
            _lastPlayedMovieRepeatRange = NSRangeFromString(
                [_defaults objectForKey:MLastPlayedMovieRepeatRangeKey]);
        }
    }
}

- (void)saveLastPlayedMovieInfo
{
    if ([_defaults boolForKey:MRememberLastPlayKey]) {
        // save last playlist, file, time & repeat-range.
        [_defaults setObject:[NSKeyedArchiver archivedDataWithRootObject:_playlist]
                      forKey:MPlaylistKey];
        [_defaults setObject:[NSNumber numberWithFloat:_lastPlayedMovieTime]
                      forKey:MLastPlayedMovieTimeKey];
        [_defaults setObject:NSStringFromRange(_lastPlayedMovieRepeatRange)
                      forKey:MLastPlayedMovieRepeatRangeKey];
    }
    else {
        [_defaults removeObjectForKey:MPlaylistKey];
        [_defaults removeObjectForKey:MLastPlayedMovieTimeKey];
        [_defaults removeObjectForKey:MLastPlayedMovieRepeatRangeKey];
    }
}

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark UI

- (void)updateRepeatUI
{
    //TRACE(@"%s", __PRETTY_FUNCTION__);
    unsigned int mode = [_playlist repeatMode];

	for (NSMenuItem* item in [_controlMenu itemArray]) {
        if ([item action] == @selector(repeatAction:)) {
            [item setState:[item tag] == mode];
        }
    }
    [_playlistController updateRepeatUI];
}

- (BOOL)playlistWindowVisible
{
    return (_playlistController && [[_playlistController window] isVisible]);
}

- (void)showPlaylistWindow
{
    //TRACE(@"%s", __PRETTY_FUNCTION__);
    if (!_playlistController) {
        _playlistController = [[PlaylistController alloc]
                                initWithAppController:self playlist:_playlist];
    }
    if (![self playlistWindowVisible]) {
        BOOL floating = [_defaults boolForKey:MFloatingPlaylistKey];
        if (([[NSApp currentEvent] modifierFlags] & NSShiftKeyMask)) {
            floating = !floating;
        }
        if ([self isFullScreen] || [self isDesktopBackground] || floating) {
            [_playlistController showWindow:self];
            [[_playlistController window] setDelegate:self];
            [[_playlistController window] makeKeyWindow];
            if (![self isFullScreen] && ![self isDesktopBackground] && floating) {
                [[_playlistController window] setAlwaysOnTop:[_mainWindow alwaysOnTop]];
            }
            [_playPanel orderOutWithFadeOut:self];
        }
        else {
            [_playlistController runSheetForWindow:_mainWindow];
        }
    }
}

- (void)hidePlaylistWindow
{
    //TRACE(@"%s", __PRETTY_FUNCTION__);
    if ([self playlistWindowVisible]) {
        [_playlistController closeAction:self];
    }
}

- (void)playlistUpdated:(NSNotification*)notification
{
    [_playlistController updateUI];
    [self updatePrevNextMovieButtons];
}

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark IB actions

- (IBAction)playlistAction:(id)sender
{
    //TRACE(@"%s", __PRETTY_FUNCTION__);
    if ([self playlistWindowVisible]) {
        [self hidePlaylistWindow];
    }
    else {
        [self showPlaylistWindow];
    }
}

- (IBAction)prevNextMovieAction:(id)sender
{
    //TRACE(@"%s %d", __PRETTY_FUNCTION__, [sender tag]);
    if ([sender tag] < 0) {
        [self openPrevPlaylistItem];
    }
    else {
        [self openNextPlaylistItem];
    }
}

- (IBAction)repeatAction:(id)sender
{
    //TRACE(@"%s %d", __PRETTY_FUNCTION__, [sender tag]);
    [self setRepeatMode:[sender tag]];
}

@end
