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

#import <Carbon/Carbon.h>   // for SystemUIMode, Options

@class MMovieView;
@class MainWindow;
@class FullWindow;
@class PlayPanel;

@interface FullScreener : NSObject
{
    int _effect;
    MMovieView* _movieView;
    MainWindow* _mainWindow;
    FullWindow* _fullWindow;
    PlayPanel* _playPanel;

    NSURL* _movieURL;
    NSRect _movieViewRect;  // in _mainWindow
    BOOL _fullScreenFromDesktopBackground;

    // hide main-menu & dock
    BOOL _autoShowDock;
    BOOL _mainMenuAndDockIsHidden;
    SystemUIMode _normalSystemUIMode;
    SystemUIOptions _normalSystemUIOptions;

    // for animation effect
    NSWindow* _blackWindow;
    NSRect _restoreRect;
    NSRect _maxMainRect;
    NSRect _fullMovieRect;

    // for black-screens effect
    ScreenFader* _blackScreenFader;
}

- (id)initWithMainWindow:(MainWindow*)mainWindow
               playPanel:(PlayPanel*)playPanel;

- (FullWindow*)fullWindow;
- (void)setMovieURL:(NSURL*)movieURL;
- (void)setAutoShowDock:(BOOL)autoShow;

- (BOOL)isFullScreen;
- (void)beginFullScreen;
- (void)endFullScreen;
- (void)autoHidePlayPanel;

- (BOOL)isDesktopBackground;
- (void)beginDesktopBackground;
- (void)endDesktopBackground;

- (BOOL)isNavigation;
- (BOOL)isNavigating;
- (BOOL)isPreviewing;
- (void)beginNavigation;
- (void)endNavigation;

- (void)selectUpper;
- (void)selectLower;
- (void)selectCurrent;

- (void)openCurrent;
- (BOOL)closeCurrent;
- (BOOL)canCloseCurrent;

@end

////////////////////////////////////////////////////////////////////////////////
#pragma mark -

@interface FullScreener (Transition)

- (void)showMainMenuAndDock;
- (void)hideMainMenuAndDock;

- (void)attachMovieViewToFullWindow;
- (void)detachMovieViewFromFullWindow;

- (void)beginFullScreenFromDesktopBackground;
- (void)endFullScreenToDesktopBackground;

@end
