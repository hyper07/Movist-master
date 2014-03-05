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

#import "Playlist.h"
#import "UserDefaults.h"

#import "MMovie_FFmpeg.h"
#import "MMovie_QuickTime.h"
#import "MSubtitleParser_SMI.h"
#import "MSubtitleParser_TXT.h"
#import "MSubtitleParser_SSA.h"
#import "MSubtitleParser_MKV.h"
#import "MSubtitleParser_SUB.h"

#import "MainWindow.h"
#import "MMovieView.h"
#import "FullScreener.h"
#import "CustomControls.h"  // for SeekSlider
#import "ControlPanel.h"

@implementation AppController (Open)

- (MMovie*)movieFromURL:(NSURL*)movieURL withMovieClass:(Class)movieClass
                   error:(NSError**)error
{
    //TRACE(@"%s \"%@\" with \"%@\"", __PRETTY_FUNCTION__,
    //      [movieURL absoluteString], movieClass);
    MMovieInfo movieInfo;
    if (![MMovie getMovieInfo:&movieInfo forMovieURL:movieURL error:error]) {
        if (movieClass && movieClass == [MMovie_FFmpeg class]) {
            return nil;
        }
        // continue by using QuickTime
        movieClass = [MMovie_QuickTime class];
    }

    NSArray* classes;
    if (movieClass) {
        // if movieClass is specified, then try it only
        classes = [NSArray arrayWithObject:movieClass];
    }
    else {
        // try all movie-classes with starting default-movie-class
        int codecId = [[movieInfo.videoTracks objectAtIndex:0] codecId];
        int decoder = [_defaults defaultDecoderForCodecId:codecId];
        if (decoder == DECODER_QUICKTIME) {
            classes = [NSArray arrayWithObjects:
                [MMovie_QuickTime class], [MMovie_FFmpeg class], nil];
        }
        else {
            classes = [NSArray arrayWithObjects:
                [MMovie_FFmpeg class], [MMovie_QuickTime class], nil];
        }
    }

    MMovie* movie;
    NSString* info;
    BOOL digitalAudioOut = _audioDeviceSupportsDigital &&
                           [_defaults boolForKey:MAutodetectDigitalAudioOutKey];
	for(movieClass in classes) {
        info = [NSString stringWithFormat:
                NSLocalizedString(@"Opening with %@...", nil), [movieClass name]];
        [_movieView setMessageWithURL:movieURL info:info];
        [_movieView display];   // force display

        movie = [[movieClass alloc] initWithURL:movieURL movieInfo:&movieInfo
                                digitalAudioOut:digitalAudioOut error:error];
        if (movie) {
            return [movie autorelease];
        }
    }
    return nil;
}

- (NSArray*)subtitleFromURL:(NSURL*)subtitleURL
               withEncoding:(CFStringEncoding)cfEncoding
                      error:(NSError**)error
{
    //TRACE(@"%s \"%@\"", __PRETTY_FUNCTION__, [subtitleURL absoluteString]);
    if (!subtitleURL) {
        return nil;
    }
    if (![subtitleURL isFileURL]) {
        //TRACE(@"remote subtitle is not supported yet");
        NSError* err = [NSError errorWithDomain:[NSApp localizedAppName] code:0 userInfo:0];
		if(error != NULL)
			*error = err;
        return nil;
    }

    NSString* path = [subtitleURL path];
    NSString* ext = [[path pathExtension] lowercaseString];
    if (cfEncoding == kCFStringEncodingInvalidId) {
        cfEncoding = [_defaults integerForKey:MSubtitleEncodingKey];
    }

    // find parser for subtitle's path extension
    Class parserClass;
    NSDictionary* options = nil;
    if ([ext isEqualToString:@"smi"] || [ext isEqualToString:@"sami"]) {
        parserClass = [MSubtitleParser_SMI class];
        NSNumber* stringEncoding = [NSNumber numberWithInt:cfEncoding];
        NSNumber* replaceNLWithBR = [_defaults objectForKey:MSubtitleReplaceNLWithBRKey];
        options = [NSDictionary dictionaryWithObjectsAndKeys:
                   stringEncoding, MSubtitleParserOptionKey_stringEncoding,
                   replaceNLWithBR, MSubtitleParserOptionKey_SMI_replaceNewLineWithBR,
                   nil];
    }
    else if ([ext isEqualToString:@"srt"] || [ext isEqualToString:@"txt"]) {
        parserClass = [MSubtitleParser_TXT class];
		NSNumber* stringEncoding = [NSNumber numberWithInt:cfEncoding];
		NSNumber* movieFps = [NSNumber numberWithFloat:[_movie fps]];
		options = [NSDictionary dictionaryWithObjectsAndKeys:
                   stringEncoding, MSubtitleParserOptionKey_stringEncoding,
				   movieFps, MSubtitleParserOptionKey_movieFps,
				   nil];
    }
    else if ([ext isEqualToString:@"ssa"] || [ext isEqualToString:@"ass"]) {
        parserClass = [MSubtitleParser_SSA class];
        NSNumber* stringEncoding = [NSNumber numberWithInt:cfEncoding];
        options = [NSDictionary dictionaryWithObjectsAndKeys:
                   stringEncoding, MSubtitleParserOptionKey_stringEncoding,
                   nil];
    }
    else if ([ext isEqualToString:@"mkv"] || [ext isEqualToString:@"mks"]) {
        parserClass = [MSubtitleParser_MKV class];
    }
    else if ([ext isEqualToString:@"sub"] || [ext isEqualToString:@"rar"]) {
        parserClass = [MSubtitleParser_SUB class];
    }
    else {
        NSError* err = [NSError errorWithDomain:[NSApp localizedAppName] code:1 userInfo:0];
		if(error != NULL)
			*error = err;
        return nil;
    }

    MSubtitleParser* parser = [[[parserClass alloc] initWithURL:subtitleURL] autorelease];
    NSArray* subtitles = [parser parseWithOptions:options error:error];
    if (!subtitles) {
        NSError* err = [NSError errorWithDomain:[NSApp localizedAppName] code:2 userInfo:0];
		if(error != NULL)
			*error = err;
        return nil;
    }
    return subtitles;
}

- (NSArray*)subtitleFromURLs:(NSArray*)subtitleURLs
                withEncoding:(CFStringEncoding)cfEncoding
                       error:(NSError**)error
{
    NSMutableArray* subtitles = [NSMutableArray arrayWithCapacity:1];

    BOOL someError = FALSE;
	for(NSURL* url in subtitleURLs) {
		NSArray* subs = [self subtitleFromURL:url withEncoding:cfEncoding error:error];
        if (!subs) {
            someError = TRUE;
        }
        else if (cfEncoding == kCFStringEncodingInvalidId && 0 == [subs count]) {
            subs = [self subtitleFromURL:url withEncoding:kCFStringEncodingUTF8 error:error];
            if (!subs || 0 == [subs count]) {
                subs = [self subtitleFromURL:url withEncoding:kCFStringEncodingUTF16 error:error];
            }
        }

        if (subs && 0 < [subs count]) {
            [subtitles addObjectsFromArray:subs];
        }
    }
    return (0 < [subtitles count]) ? subtitles : (someError) ? nil : subtitles;
}

- (NSString*)subtitleInfoMessageString
{
    NSString* s = nil;
    if (_subtitles) {
		for (MSubtitle* subtitle in _subtitles) {
            if ([subtitle isEnabled]) {
                s = (!s) ? [NSString stringWithString:[subtitle name]] :
                           [s stringByAppendingFormat:@", %@", [subtitle name]];
            }
        }
        if (!s) {
            s = NSLocalizedString(@"Cannot Read Subtitle", nil);
        }
    }
    return s;
}

- (void)updateUIForOpenedMovieAndSubtitle:(NSString*)subtitleInfo
{
    NSSize ss = [[_mainWindow screen] frame].size;
    NSSize ms = [_movie adjustedSizeByAspectRatio];
    [_movieView setFullScreenFill:(ss.width / ss.height < ms.width / ms.height) ?
                        [_defaults integerForKey:MFullScreenFillForWideMovieKey] :
                        [_defaults integerForKey:MFullScreenFillForStdMovieKey]];
    [_movieView hideLogo];
    [_movieView setMovie:_movie];
    [_movieView updateLetterBoxHeight];
    [_movieView updateMovieRect:TRUE];

    if (_subtitles) {
        NSString* info = [NSString stringWithFormat:@"%@, %@",
                          [[_movie class] name], [self subtitleInfoMessageString]];
        [_movieView setMessageWithURL:[self movieURL] info:info];
    }
    else {
        if ([subtitleInfo isEqualToString:@""]) {
            [_movieView setMessageWithURL:[self movieURL] info:[[_movie class] name]];
        }
        else {
            NSString* info = [NSString stringWithFormat:@"%@, %@",
                              [[_movie class] name], subtitleInfo];
            [_movieView setMessageWithURL:[self movieURL] info:info];
        }
    }

    if (_mainWindow == [_movieView window]) {
        switch ([_defaults integerForKey:MOpeningViewKey]) {
            case OPENING_VIEW_HALF_SIZE         : [self resizeWithMagnification:0.5];   break;
            case OPENING_VIEW_NORMAL_SIZE       : [self resizeWithMagnification:1.0];   break;
            case OPENING_VIEW_DOUBLE_SIZE       : [self resizeWithMagnification:2.0];   break;
            case OPENING_VIEW_FIT_TO_SCREEN     : [self resizeToScreen];                break;
            case OPENING_VIEW_DESKTOP_BACKGROUND: [self beginDesktopBackground];        break;
            case OPENING_VIEW_FULL_SCREEN       : [self beginFullScreen];               break;
        }
    }
    // subtitles should be set after resizing window.
    [self updateMovieViewSubtitles];

    // update etc. UI
    [_seekSlider setDuration:[_movie duration]];
    [_seekSlider setIndexedDuration:0];
    [_fsSeekSlider setDuration:[_movie duration]];
    [_fsSeekSlider setIndexedDuration:0];
    [_prevSeekButton updateHoverImage];
    [_nextSeekButton updateHoverImage];
    [_controlPanelButton updateHoverImage];
    [_prevMovieButton updateHoverImage];
    [_nextMovieButton updateHoverImage];
    [_playlistButton updateHoverImage];
    [self updateDataSizeBpsUI];
    [self setRangeRepeatRange:_lastPlayedMovieRepeatRange];

    Class otherClass = ([_movie isMemberOfClass:[MMovie_QuickTime class]]) ?
                                [MMovie_FFmpeg class] : [MMovie_QuickTime class];
    [_reopenWithMenuItem setTitle:[NSString stringWithFormat:
            NSLocalizedString(@"Reopen With %@", nil), [otherClass name]]];
    _prevMovieTime = 0.0;
    [self updateUI];

    // update system activity periodically not to activate screen saver
    _updateSystemActivityTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
        target:self selector:@selector(updateSystemActivity:) userInfo:nil repeats:TRUE];

    // add to recent-menu
    [[NSDocumentController sharedDocumentController] noteNewRecentDocumentURL:[self movieURL]];
}

- (BOOL)openMovie:(NSURL*)movieURL movieClass:(Class)movieClass
        subtitles:(NSArray*)subtitleURLs subtitleEncoding:(CFStringEncoding)subtitleEncoding
{
    //TRACE(@"%s", __PRETTY_FUNCTION__);
    // -[closeMovie] should be called after opening new-movie not to display black screen.
    if (!movieURL) {
        [self closeMovie];
        if ([self isDesktopBackground]) {
            [self endDesktopBackground];
        }
        return FALSE;
    }

    // open movie
    NSError* error;
    MMovie* movie = [self movieFromURL:movieURL withMovieClass:movieClass error:&error];
    if (!movie) {
        [self closeMovie];
        if ([self isFullScreen]) {
            NSString* s = [movieURL isFileURL] ? [movieURL path] : [movieURL absoluteString];
            [_movieView setError:error info:[s lastPathComponent]];
        }
        else {
            if ([self isDesktopBackground]) {
                [self endDesktopBackground];
            }
            [self showOpenAlert:error forURL:movieURL];
        }
        return FALSE;
    }
    [self closeMovie];
    assert(_movie == nil);
    _movie = [movie retain];

    // observe movie's notifications
    NSNotificationCenter* nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(movieIndexDurationChanged:)
               name:MMovieIndexedDurationNotification object:_movie];
    [nc addObserver:self selector:@selector(movieRateChanged:)
               name:MMovieRateChangeNotification object:_movie];
    [nc addObserver:self selector:@selector(movieCurrentTimeChanged:)
               name:MMovieCurrentTimeNotification object:_movie];
    [nc addObserver:self selector:@selector(movieEnded:)
               name:MMovieEndNotification object:_movie];
    [nc addObserver:self selector:@selector(playlistUpdated:)
               name:MPlaylistUpdatedNotification object:_playlist];

    // don't check for alt-volume-change while opening movie
    _checkForAltVolumeChange = FALSE;

    BOOL isSeries = (_lastPlayedMovieURL &&
                     checkMovieSeries([[_lastPlayedMovieURL path] lastPathComponent],
                                      [[movieURL path] lastPathComponent]));
    if (isSeries) {
        // if same movie series, then maintain some previous settings.
        [_movie setAspectRatio:_lastPlayedMovieAspectRatio];
    }
    else {
        // if not same movie series, then clear previous audio track info.
        [_audioTrackIndexSet removeAllIndexes];
    }

    // update movie
    [self updateDigitalAudioOut:self];
    // -[autoenableAudioTracks] should be sent after -[updateDigitalAudioOut:]
    // for selecting only one audio track in digital-out.
    [self autoenableAudioTracks];
    // movie volume should be set again for changed audio tracks.
    [_movie setVolume:[self isCurrentlyDigitalAudioOut] ?
                        DIGITAL_VOLUME : [_defaults floatForKey:MVolumeKey]];
    [_movie setMuted:([_muteButton state] == NSOnState)];
    if (!_lastPlayedMovieURL || ![_lastPlayedMovieURL isEqualTo:movieURL]) {
        [_lastPlayedMovieURL release];
        _lastPlayedMovieURL = [movieURL retain];
        _lastPlayedMovieTime = 0;
        _lastPlayedMovieRepeatRange.length = 0;
    }
    else if (0 < _lastPlayedMovieTime) {
        [_movie gotoTime:_lastPlayedMovieTime];
    }
    
    // open subtitles
    NSString* subtitleInfo = @"";
    if ([_defaults boolForKey:MSubtitleEnableKey]) {
        NSMutableArray* subtitles = [NSMutableArray arrayWithCapacity:1];
        // load mkv-embedded subtitles
        if ([_defaults boolForKey:MAutoLoadMKVEmbeddedSubtitlesKey]) {
            NSString* ext = [[[movieURL path] pathExtension] lowercaseString];
            if ([ext isEqualToString:@"mkv"]) {
                NSArray* subs = [self subtitleFromURL:movieURL
                                         withEncoding:subtitleEncoding error:&error];
                if (!subs) {
                    // cannot open file...
                    // continue... subtitle is not necessary for movie.
                }
                else {
                    [subtitles addObjectsFromArray:subs];
                }
            }
        }
        // load external subtitle files
        if (0 < [subtitleURLs count]) {
            NSArray* subs = [self subtitleFromURLs:subtitleURLs
                                      withEncoding:subtitleEncoding error:&error];
            if (!subs) {
                subtitleInfo = [subtitleInfo stringByAppendingString:
                                NSLocalizedString(@"No Subtitle", nil)];
                // continue... subtitle is not necessary for movie.
            }
            else if ([subs count] == 0) {
                subtitleInfo = [subtitleInfo stringByAppendingFormat:@"%@ %@",
                                NSLocalizedString(@"Cannot Read Subtitle", nil),
                                NSLocalizedString(@"Reopen with other encodings", nil)];
            }
            else {
                [subtitles addObjectsFromArray:subs];
            }
        }
        if (0 < [subtitles count]) {
            _subtitles = [subtitles retain];
            [self updateExternalSubtitleTrackNames];
            if (!isSeries) {
                // if not same movie series, then clear previous subtitle info.
                [_subtitleNameSet removeAllObjects];
            }
            [self autoenableSubtitles];
        }
    }
    [self updateUIForOpenedMovieAndSubtitle:subtitleInfo];
    _checkForAltVolumeChange = TRUE;

    [_movie setRate:_playRate];  // auto play

    return TRUE;
}

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark public interface

- (BOOL)openFile:(NSString*)filename
{
    //TRACE(@"%s", __PRETTY_FUNCTION__);
    return [self openFiles:[NSArray arrayWithObject:filename]];
}

- (BOOL)openFiles:(NSArray*)filenames
{
    //TRACE(@"%s", __PRETTY_FUNCTION__);
    int option = [_defaults boolForKey:MAutodetectMovieSeriesKey] ?
                                                    OPTION_SERIES : OPTION_ONLY;
    return [self openFiles:filenames option:option];
}

- (BOOL)openURL:(NSURL*)url
{
    //TRACE(@"%s", __PRETTY_FUNCTION__);
    runAlertPanel(_mainWindow,
                  @"\"Open URL...\" is not implemented yet.", @"",
                  NSLocalizedString(@"OK", nil), nil, nil);
    return FALSE;
}

- (BOOL)openFile:(NSString*)filename option:(int)option
{
    //TRACE(@"%s", __PRETTY_FUNCTION__);
    return [self openFiles:[NSArray arrayWithObject:filename] option:option];
}

- (BOOL)openFiles:(NSArray*)filenames option:(int)option
{
    //TRACE(@"%s", __PRETTY_FUNCTION__);
    if (![_mainWindow isVisible]) {
        [_mainWindow makeKeyAndOrderFront:self];
    }

    [_playlist removeAllItems];
    if ([filenames count] == 1) {
        [_playlist addFile:[filenames objectAtIndex:0] option:option];
    }
    else {
        [_playlist addFiles:filenames];
    }
    return (0 < [_playlist count]) ? [self openCurrentPlaylistItem] : FALSE;
}

- (BOOL)openSubtitleFiles:(NSArray*)filenames
{
    if (!_movie) {
        return FALSE;
    }

    if (![_mainWindow isVisible]) {
        [_mainWindow makeKeyAndOrderFront:self];
    }

    NSArray* subtitleExts = [MSubtitle fileExtensions];
	NSString* filename = nil;
	for (filename in filenames) {
        if (![filename hasAnyExtension:subtitleExts]) {
            break;
        }
    }
    if (!filename) {    // all subtitle files => open them
        [[_playlist currentItem] setSubtitleURLs:URLsFromFilenames(filenames)];
        [_playlistController updateUI];
        [self reopenSubtitles];
        return TRUE;
    }
    return FALSE;
}

- (BOOL)openSubtitles:(NSArray*)subtitleURLs encoding:(CFStringEncoding)encoding
{
    NSError* error;
    NSArray* subtitles = [self subtitleFromURLs:subtitleURLs withEncoding:encoding error:&error];
    if (!subtitles) {
        NSString* s = @"";
		for (NSURL* subtitleURL in subtitleURLs) {
            s = [s stringByAppendingFormat:@"%@\n", [[subtitleURL path] lastPathComponent]];
        }
        runAlertPanel(_mainWindow, NSLocalizedString(@"Cannot open file", nil), s,
                      NSLocalizedString(@"OK", nil), nil, nil);
        [self setLetterBoxHeight:[_defaults integerForKey:MLetterBoxHeightKey]];
        return FALSE;
    }

    if (encoding != kCFStringEncodingInvalidId && [subtitles count] == 0) {
        // if this is reopening with other encoding and no subtitle in subtitleURLs,
        // then, don't reset current subtitles for trials with other encodings.
        // FIXME: show all subtitleURLs...
        NSString* s = [NSString stringWithFormat:@"%@: %@",
                       NSLocalizedString(@"Cannot Read Subtitle", nil),
                       NSLocalizedString(@"Reopen with other encodings", nil)];
        [_movieView setMessageWithURL:[subtitleURLs objectAtIndex:0] info:s];
        return FALSE;
    }

    [_subtitles release];
    _subtitles = [subtitles mutableCopy];
    [[_playlist currentItem] setSubtitleURLs:subtitleURLs];
    [self autoenableSubtitles];
    [self updateExternalSubtitleTrackNames];
    [self updateSubtitleLanguageMenuItems];
    [_propertiesView reloadData];

    [self updateMovieViewSubtitles];
    [self setLetterBoxHeight:[_defaults integerForKey:MLetterBoxHeightKey]];

    if ([_defaults boolForKey:MGotoBegginingWhenOpenSubtitleKey]) {
        [_movie gotoBeginning];
    }

    // FIXME: show all subtitleURLs...
    [_movieView setMessageWithURL:[subtitleURLs objectAtIndex:0]
                             info:[self subtitleInfoMessageString]];

    return TRUE;
}

- (void)addSubtitles:(NSArray*)subtitleURLs
{
    PlaylistItem* item = [_playlist currentItem];
    if (!item) {
        return;
    }

    NSError* error;
    NSArray* subtitles = [self subtitleFromURLs:subtitleURLs
                                   withEncoding:kCFStringEncodingInvalidId error:&error];
    if (!subtitles) {
		for (NSURL* subtitleURL in subtitleURLs) {
            runAlertPanelForOpenError(_mainWindow, error, subtitleURL);
        }
        return;
    }

	for (MSubtitle* subtitle in subtitles) {
        [subtitle setEnabled:FALSE];
    }
    
    BOOL initSubtitle = (_subtitles == nil);
    if (!_subtitles) {
        _subtitles = [[NSMutableArray alloc] initWithArray:subtitles];
    }
    else {
        [_subtitles addObjectsFromArray:subtitles];
    }
    [[_playlist currentItem] addSubtitleURLs:subtitleURLs];
    [self updateExternalSubtitleTrackNames];
    [self updateSubtitleLanguageMenuItems];
    [_playlistController updateUI];
    [_propertiesView reloadData];

    // FIXME: show all subtitleURLs...
    //[_movieView setMessageWithURL:[subtitleURLs objectAtIndex:0]
    //                         info:[self subtitleInfoMessageString]];

    if (initSubtitle && 0 < [_subtitles count]) {
        [self autoenableSubtitles];
        [self updateSubtitleLanguageMenuItems];
        [_propertiesView reloadData];

        [self setLetterBoxHeight:[_defaults integerForKey:MLetterBoxHeightKey]];

        if ([_defaults boolForKey:MGotoBegginingWhenOpenSubtitleKey]) {
            [_movie gotoBeginning];
        }
    }
}

- (BOOL)reopenMovieWithMovieClass:(Class)movieClass
{
    //TRACE(@"%s:%@", __PRETTY_FUNCTION__, movieClass);
    [self closeMovie];

    if ([_defaults boolForKey:MGotoBegginingWhenReopenMovieKey]) {
        // to play at the beginning
        [_lastPlayedMovieURL release];
        _lastPlayedMovieURL = nil;
    }

    PlaylistItem* item = [_playlist currentItem];
    return [self openMovie:[item movieURL] movieClass:movieClass
                 subtitles:[item subtitleURLs] subtitleEncoding:kCFStringEncodingInvalidId];
}

- (void)reopenSubtitles
{
    //TRACE(@"%s", __PRETTY_FUNCTION__);
    if (_movie) {
        [self openSubtitles:[[_playlist currentItem] subtitleURLs]
                   encoding:kCFStringEncodingInvalidId];
    }
}

- (void)closeMovie
{
    //TRACE(@"%s", __PRETTY_FUNCTION__);
    if (_movie) {
        NSURL* movieURL = [_movie url];
        NSString* ext = [[[movieURL path] pathExtension] lowercaseString];
        if ([ext isEqualToString:@"mkv"]) {
            [MSubtitleParser_MKV quitThreadForSubtitleURL:movieURL];
        }

        [_movie setRate:0.0];   // at first, pause.
        [_updateSystemActivityTimer invalidate];

        _lastPlayedMovieTime = ([_movie currentTime] < [_movie duration]) ?
                                [_movie currentTime] : 0.0;
        _lastPlayedMovieRepeatRange = [_seekSlider repeatRange];
        _lastPlayedMovieAspectRatio = [_movie aspectRatio];

        // init _audioTrackIndexSet for next open.
        [_audioTrackIndexSet removeAllIndexes];
        NSArray* audioTracks = [_movie audioTracks];
        int i, count = [audioTracks count];
        for (i = 0; i < count; i++) {
            if ([[audioTracks objectAtIndex:i] isEnabled]) {
                [_audioTrackIndexSet addIndex:i];
            }
        }

		// TODO: bemore careful about how we are identifying subtitle tracks
		//       as "name" can be "Unnamed" which is not specific. Might be
		//       best to combine name and language.
        // init _subtitleNameSet for next open.
        [_subtitleNameSet removeAllObjects];
		for (MSubtitle* subtitle in _subtitles) {
            if ([subtitle isEnabled]) {
                [_subtitleNameSet addObject:[subtitle UIName]];
            }
        }

        [_playlistController updateUI];

        NSNotificationCenter* nc = [NSNotificationCenter defaultCenter];
        [nc removeObserver:self name:nil object:_movie];
        [nc removeObserver:self name:nil object:_playlist];

        [_movieView setMovie:nil];
        [_movieView setMessage:@""];
        [_movie cleanup], _movie = nil;

        [_subtitles release], _subtitles = nil;
        [_reopenWithMenuItem setTitle:[NSString stringWithFormat:
            NSLocalizedString(@"Reopen With %@", nil), @"..."]];
        [self updateUI];
    }
}

- (void)updateDecoderUI
{
    NSImage* image = nil;
    NSImage* fsImage = nil, *fsImagePressed = nil;
    if ([_movieView movie]) {
        NSString* decoder = [[[_movieView movie] class] name];
        if ([decoder isEqualToString:[MMovie_QuickTime name]]) {
            image          = [NSImage imageNamed:@"MainQuickTime"];
            fsImage        = [NSImage imageNamed:@"FSQuickTime"];
            fsImagePressed = [NSImage imageNamed:@"FSQuickTimePressed"];
        }
        else {  // [decoder isEqualToString:[MMovie_FFmpeg name]]
            image          = [NSImage imageNamed:@"MainFFMPEG"];
            fsImage        = [NSImage imageNamed:@"FSFFMPEG"];
            fsImagePressed = [NSImage imageNamed:@"FSFFmpegPressed"];
        }
    }

    [_decoderButton setImage:image];
    [_fsDecoderButton setImage:fsImage];
    [_fsDecoderButton setAlternateImage:fsImagePressed];
    [_cpDecoderButton setImage:fsImage];
    [_cpDecoderButton setAlternateImage:fsImagePressed];

    [_decoderButton setEnabled:(image != nil)];
    [_fsDecoderButton setEnabled:(fsImage != nil)];
    [_cpDecoderButton setEnabled:(fsImage != nil)];
}

- (void)updateDataSizeBpsUI
{
    NSString* s = @"";
    if (_movie) {
        float megaBytes = [_movie fileSize] / 1024. / 1024.;
        if (megaBytes < 1024) {
            s = [NSString stringWithFormat:@"%.2f MB", megaBytes];
        }
        else {
            s = [NSString stringWithFormat:@"%.2f GB", megaBytes / 1024.];
        }
        if (0 < [_movie bitRate]) {
            s = [s stringByAppendingFormat:@",  %d kbps", [_movie bitRate] / 1000];
        }
    }
    [_dataSizeBpsTextField setStringValue:s];
}

- (void)updateSystemActivity:(NSTimer*)timer
{
    //TRACE(@"%s", __PRETTY_FUNCTION__);
    if ([self isFullScreen] ||  // always deactivate screen-saver in full-screen
        ([_movie rate] != 0 && [_defaults boolForKey:MDeactivateScreenSaverKey])) {
        UpdateSystemActivity(UsrActivity);
    }
    if ([self isFullScreen]) {
        [_fullScreener autoHidePlayPanel];
    }
}

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark IB actions

- (IBAction)openFileAction:(id)sender
{
    //TRACE(@"%s", __PRETTY_FUNCTION__);
    BOOL alwaysOnTop = [_mainWindow alwaysOnTop];
    if (alwaysOnTop) {
        [_mainWindow setAlwaysOnTop:FALSE];
    }

    NSOpenPanel* panel = [NSOpenPanel openPanel];
    //[panel setTitle:NSLocalizedString(@"Open Movie File", nil)];
    [panel setCanChooseFiles:TRUE];
    [panel setCanChooseDirectories:TRUE];
    [panel setAllowsMultipleSelection:FALSE];
	[panel setAllowedFileTypes:[MMovie fileExtensions]];
    if (NSOKButton == [panel runModal]) {
        [self openFile:[[panel URL] path]];
    }

    if (alwaysOnTop) {
        [_mainWindow setAlwaysOnTop:TRUE];
    }
}

- (IBAction)openSubtitleFileAction:(id)sender
{
    //TRACE(@"%s", __PRETTY_FUNCTION__);
    BOOL alwaysOnTop = [_mainWindow alwaysOnTop];
    if (alwaysOnTop) {
        [_mainWindow setAlwaysOnTop:FALSE];
    }

    NSOpenPanel* panel = [NSOpenPanel openPanel];
    //[panel setTitle:NSLocalizedString(@"Open Subtitle Files", nil)];
    [panel setCanChooseFiles:TRUE];
    [panel setCanChooseDirectories:FALSE];
    [panel setAllowsMultipleSelection:TRUE];
	[panel setAllowedFileTypes:[MSubtitle fileExtensions]];
    if (NSOKButton == [panel runModal]) {
        [self openSubtitles:[panel URLs]
                   encoding:kCFStringEncodingInvalidId];
    }

    if (alwaysOnTop) {
        [_mainWindow setAlwaysOnTop:TRUE];
    }
}

- (IBAction)addSubtitleFileAction:(id)sender
{
    BOOL alwaysOnTop = [_mainWindow alwaysOnTop];
    if (alwaysOnTop) {
        [_mainWindow setAlwaysOnTop:FALSE];
    }

    NSOpenPanel* panel = [NSOpenPanel openPanel];
    //[panel setTitle:NSLocalizedString(@"Add Subtitle Files", nil)];
    [panel setCanChooseFiles:TRUE];
    [panel setCanChooseDirectories:FALSE];
    [panel setAllowsMultipleSelection:TRUE];
	[panel setAllowedFileTypes:[MSubtitle fileExtensions]];
    if (NSOKButton == [panel runModal]) {
        [self addSubtitles:[panel URLs]];
    }

    if (alwaysOnTop) {
        [_mainWindow setAlwaysOnTop:TRUE];
    }
}

- (IBAction)reopenMovieAction:(id)sender
{
    //TRACE(@"%s", __PRETTY_FUNCTION__);
    if (_movie) {
        Class newClass = ([_movie isMemberOfClass:[MMovie_QuickTime class]]) ?
                                [MMovie_FFmpeg class] : [MMovie_QuickTime class];
        [self reopenMovieWithMovieClass:newClass];
    }
}

- (IBAction)reopenSubtitleAction:(id)sender
{
    //TRACE(@"%s", __PRETTY_FUNCTION__);
    [self openSubtitles:[[_playlist currentItem] subtitleURLs]
               encoding:[sender tag]];
}

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark properties view

- (int)numberOfRowsInTableView:(NSTableView*)tableView
{
    //TRACE(@"%s", __PRETTY_FUNCTION__);
    int count = 0;
    if (_movie) {
        count += [[_movie videoTracks] count];
        count += [[_movie audioTracks] count];
        if (_subtitles) {
            count += [_subtitles count];
        }
    }
    return count;
}

- (id)tableView:(NSTableView*)tableView
    objectValueForTableColumn:(NSTableColumn*)tableColumn row:(int)rowIndex
{
    //TRACE(@"%s %@:%d", __PRETTY_FUNCTION__, [tableColumn identifier], rowIndex);
    int vCount = [[_movie videoTracks] count];
    int aCount = [[_movie audioTracks] count];
    //int sCount = [_subtitles count];
    int vIndex = rowIndex;
    int aIndex = vIndex - vCount;
    int sIndex = aIndex - aCount;

    NSString* identifier = [tableColumn identifier];
    if ([identifier isEqualToString:@"enable"]) {
        if (vIndex < vCount) {
            // at least, one video track should be enabled.
            int i, count = 0;
            NSArray* tracks = [_movie videoTracks];
            for (i = 0; i < vCount; i++) {
                if (i != vIndex && [[tracks objectAtIndex:i] isEnabled]) {
                    count++;
                }
            }
            [[tableColumn dataCellForRow:rowIndex] setEnabled:0 < count];
            BOOL state = [[tracks objectAtIndex:vIndex] isEnabled];
            return [NSNumber numberWithBool:state];
        }
        else {
            if (aIndex < aCount) {
                [[tableColumn dataCellForRow:rowIndex] setEnabled:TRUE];
                BOOL state = [[[_movie audioTracks] objectAtIndex:aIndex] isEnabled];
                return [NSNumber numberWithBool:state];
            }
            else {
                BOOL state = [[_subtitles objectAtIndex:sIndex] isEnabled];
                if (state) {
                    [[tableColumn dataCellForRow:rowIndex] setEnabled:TRUE];
                }
                else {
                    // max 3 subtitles can be enabled
                    int count = [self enabledSubtitleCount];
                    [[tableColumn dataCellForRow:rowIndex] setEnabled:count < 3];
                }
                return [NSNumber numberWithBool:state];
            }
        }
    }
    else if ([identifier isEqualToString:@"name"]) {
        if (vIndex < vCount) {
            return [[[_movie videoTracks] objectAtIndex:vIndex] name];
        }
        else if (aIndex < aCount) {
            return [[[_movie audioTracks] objectAtIndex:aIndex] name];
        }
        else {
            return [[_subtitles objectAtIndex:sIndex] trackName];
        }
    }
    else if ([identifier isEqualToString:@"codec"]) {
        if (vIndex < vCount) {
            return codecName([[[_movie videoTracks] objectAtIndex:vIndex] codecId]);
        }
        else if (aIndex < aCount) {
            return codecName([[[_movie audioTracks] objectAtIndex:aIndex] codecId]);
        }
        else {
            return [(MSubtitle*)[_subtitles objectAtIndex:sIndex] type];
        }
    }
    else if ([identifier isEqualToString:@"format"]) {
        if (vIndex < vCount) {
            return [[[_movie videoTracks] objectAtIndex:vIndex] summary];
        }
        else if (aIndex < aCount) {
            return [[[_movie audioTracks] objectAtIndex:aIndex] summary];
        }
        else {
            MSubtitle* subtitle = [_subtitles objectAtIndex:sIndex];
            NSString* summary = [subtitle summary];
            NSString* type = [subtitle type];
            if ([subtitle isEmbedded]) {
                if ([type hasPrefix:@"UTF8"] || [type hasPrefix:@"USF"] ||
                    [type hasPrefix:@"SSA"]  || [type hasPrefix:@"ASS"]) {
                    float loadingTime = [_controlPanel subtitleTrackLoadingTime];
                    if (0 < loadingTime) {
                        summary = [summary stringByAppendingFormat:@" (%@ %.1f %%)",
                                   NSLocalizedString(@"Loading", nil),
                                   100 * loadingTime / [_movie duration]];
                    }
                }
                else {
                    summary = [summary stringByAppendingFormat:@" (%@)",
                               NSLocalizedString(@"Not Supported Yet", nil)];
                }
            }
            /*
            else if ([type isEqualToString:@"VOBSUB"]) {
                float loadingTime = [_controlPanel vobsubFileLoadingTime];
                if (0 < loadingTime) {
                    summary = [summary stringByAppendingFormat:@" (%@ %.1f %%)",
                               NSLocalizedString(@"Loading", nil),
                               100 * loadingTime / [_movie duration]];
                }
            }
             */
            return summary;
        }
    }
    return nil;
}
/*
- (void)tableView:(NSTableView*)tableView willDisplayCell:(id)cell
   forTableColumn:(NSTableColumn*)tableColumn row:(int)rowIndex
{
    TRACE(@"%s %@:%d", __PRETTY_FUNCTION__, [tableColumn identifier], rowIndex);
    // the first video track is always enable. (cannot disable)
    if ([[tableColumn identifier] isEqualToString:@"enable"]) {
        [[tableColumn dataCellForRow:rowIndex] setEnabled:(rowIndex != 0)];
    }
}
*/
- (void)tableView:(NSTableView*)tableView setObjectValue:(id)object
   forTableColumn:(NSTableColumn*)tableColumn row:(int)rowIndex
{
    //TRACE(@"%s %@ %@ %d", __PRETTY_FUNCTION__, object, [tableColumn identifier], rowIndex);
    NSString* identifier = [tableColumn identifier];
    if ([identifier isEqualToString:@"enable"]) {
        int vCount = [[_movie videoTracks] count];
        int aCount = [[_movie audioTracks] count];
        int vIndex = rowIndex;
        int aIndex = vIndex - vCount;
        int sIndex = aIndex - aCount;

        if (vIndex < vCount) {
            BOOL enabled = [(NSNumber*)object boolValue];
            [self setVideoTrackAtIndex:vIndex enabled:enabled];
            [tableView reloadData];  // to update other video tracks availablity
        }
        else if (aIndex < aCount) {
            BOOL enabled = [(NSNumber*)object boolValue];
            if (![self isCurrentlyDigitalAudioOut] || !enabled) {
                [self setAudioTrackAtIndex:aIndex enabled:enabled];
            }
            else {
                [self enableAudioTracksInIndexSet:[NSIndexSet indexSetWithIndex:aIndex]];
                [self setAudioTrackAtIndex:aIndex enabled:enabled]; // to show message and update menu-items
                [tableView reloadData];  // to update other audio tracks availablity
            }
        }
        else {
            MSubtitle* subtitle = [_subtitles objectAtIndex:sIndex];
            BOOL enabled = [(NSNumber*)object boolValue];
            [self setSubtitle:subtitle enabled:enabled];
            [tableView reloadData];  // to update other subtitle tracks availablity
        }
    }
}

- (IBAction)moviePropertyAction:(id)sender
{
    //TRACE(@"%s %@", __PRETTY_FUNCTION__, sender);
}

@end
