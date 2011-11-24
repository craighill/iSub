//
//  Song+DAO.m
//  iSub
//
//  Created by Ben Baron on 11/14/11.
//  Copyright (c) 2011 Ben Baron. All rights reserved.
//

#import "Song+DAO.h"
#import "FMDatabase.h"
#import "FMDatabaseAdditions.h"
#import "DatabaseSingleton.h"
#import "NSString+md5.h"
#import "ViewObjectsSingleton.h"
#import "SavedSettings.h"
#import "MusicSingleton.h"
#import "SUSCurrentPlaylistDAO.h"
#import "BassWrapperSingleton.h"

@implementation Song (DAO)

- (FMDatabase *)db
{
	return [DatabaseSingleton sharedInstance].songCacheDb;
}

- (BOOL)fileExists
{
	// Filesystem check
	//return [[NSFileManager defaultManager] fileExistsAtPath:self.localPath] 

	// Database check
	return [self.db boolForQuery:@"SELECT COUNT(*) FROM cachedSongs WHERE md5 = ?", [self.path md5]];
}

- (BOOL)isPartiallyCached
{
	return [self.db intForQuery:@"SELECT count(*) FROM cachedSongs WHERE md5 = ? AND finished = 'NO'", [self.path md5]];
}

- (void)setIsPartiallyCached:(BOOL)isPartiallyCached
{
	[self insertIntoCachedSongsTable];
}

- (BOOL)isFullyCached
{
	return [[self.db stringForQuery:@"SELECT finished FROM cachedSongs WHERE md5 = ?", [self.path md5]] boolValue];
}

- (void)setIsFullyCached:(BOOL)isFullyCached
{
	[self.db executeUpdate:@"UPDATE cachedSongs SET finished = 'YES' WHERE md5 = ?", [self.path md5]];
	
	[self insertIntoCachedSongsLayout];
	
	// Setup the genre table entries
	if (self.genre)
	{		
		// Check if the genre has a table in the database yet, if not create it and add the new genre to the genres table
		if ([self.db intForQuery:@"SELECT COUNT(*) FROM genres WHERE genre = ?", self.genre] == 0)
		{							
			[self.db executeUpdate:@"INSERT INTO genres (genre) VALUES (?)", self.genre];
			if ([self.db hadError])
			{
				DLog(@"Err adding the genre %d: %@", [self.db lastErrorCode], [self.db lastErrorMessage]); 
			}
		}
		
		// Insert the song object into the genresSongs
		[self insertIntoGenreTable:@"genresSongs"];
	}
}

+ (Song *)songFromDbResult:(FMResultSet *)result
{
	Song *aSong = nil;
	if ([result next])
	{
		aSong = [[Song alloc] init];
		if ([result stringForColumn:@"title"] != nil)
			aSong.title = [[result stringForColumn:@"title"] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
		if ([result stringForColumn:@"songId"] != nil)
			aSong.songId = [[result stringForColumn:@"songId"] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
		if ([result stringForColumn:@"artist"] != nil)
			aSong.artist = [[result stringForColumn:@"artist"] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
		if ([result stringForColumn:@"album"] != nil)
			aSong.album = [[result stringForColumn:@"album"] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
		if ([result stringForColumn:@"genre"] != nil)
			aSong.genre = [[result stringForColumn:@"genre"] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
		if ([result stringForColumn:@"coverArtId"] != nil)
			aSong.coverArtId = [[result stringForColumn:@"coverArtId"] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
		if ([result stringForColumn:@"path"] != nil)
			aSong.path = [[result stringForColumn:@"path"] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
		if ([result stringForColumn:@"suffix"] != nil)
			aSong.suffix = [[result stringForColumn:@"suffix"] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
		if ([result stringForColumn:@"transcodedSuffix"] != nil)
			aSong.transcodedSuffix = [[result stringForColumn:@"transcodedSuffix"] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
		aSong.duration = [NSNumber numberWithInt:[result intForColumn:@"duration"]];
		aSong.bitRate = [NSNumber numberWithInt:[result intForColumn:@"bitRate"]];
		aSong.track = [NSNumber numberWithInt:[result intForColumn:@"track"]];
		aSong.year = [NSNumber numberWithInt:[result intForColumn:@"year"]];
		aSong.size = [NSNumber numberWithInt:[result intForColumn:@"size"]];
	}
	
	if ([aSong path] == nil)
	{
		[aSong release]; aSong = nil;
	}
	
	return aSong;
}

+ (Song *)songFromDbRow:(NSUInteger)row inTable:(NSString *)table inDatabase:(FMDatabase *)db
{
	row++;
	Song *aSong = nil;
	FMResultSet *result = [db executeQuery:[NSString stringWithFormat:@"SELECT * FROM %@ WHERE ROWID = %i", table, row]];
	if ([db hadError]) 
	{
		DLog(@"Err %d: %@", [db lastErrorCode], [db lastErrorMessage]);
	}
	else
	{
		aSong = [Song songFromDbResult:result];
	}
	[result close];
	
	return [aSong autorelease];
}

+ (Song *)songFromAllSongsDb:(NSUInteger)row inTable:(NSString *)table
{
	return [self songFromDbRow:row inTable:table inDatabase:[DatabaseSingleton sharedInstance].allSongsDb];
}

+ (Song *)songFromServerPlaylistId:(NSString *)md5 row:(NSUInteger)row
{
	NSString *table = [NSString stringWithFormat:@"splaylist%@", md5];
	return [self songFromDbRow:row inTable:table inDatabase:[DatabaseSingleton sharedInstance].localPlaylistsDb];
}

+ (Song *)songFromDbForMD5:(NSString *)md5 inTable:(NSString *)table inDatabase:(FMDatabase *)db
{
	Song *aSong = nil;
	FMResultSet *result = [db executeQuery:[NSString stringWithFormat:@"SELECT * FROM %@ WHERE md5 = %@", table, md5]];
	if ([db hadError]) 
	{
		DLog(@"Err %d: %@", [db lastErrorCode], [db lastErrorMessage]);
	}
	else
	{
		aSong = [Song songFromDbResult:result];
	}
	[result close];
	
	return [aSong autorelease];
}

+ (Song *)songFromGenreDb:(NSString *)md5
{
	if ([ViewObjectsSingleton sharedInstance].isOfflineMode)
	{
		return [self songFromDbForMD5:md5 inTable:@"genresSongs" inDatabase:[DatabaseSingleton sharedInstance].songCacheDb];
	}
	else
	{
		return [self songFromDbForMD5:md5 inTable:@"genresSongs" inDatabase:[DatabaseSingleton sharedInstance].songCacheDb];
	}
}

+ (Song *)songFromCacheDb:(NSString *)md5
{
	return [self songFromDbForMD5:md5 inTable:@"cachedSongs" inDatabase:[DatabaseSingleton sharedInstance].songCacheDb];
}

- (BOOL)insertIntoTable:(NSString *)table inDatabase:(FMDatabase *)db
{
	[db executeUpdate:[NSString stringWithFormat:@"INSERT INTO %@ (title, songId, artist, album, genre, coverArtId, path, suffix, transcodedSuffix, duration, bitRate, track, year, size) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", table], self.title, self.songId, self.artist, self.album, self.genre, self.coverArtId, self.path, self.suffix, self.transcodedSuffix, self.duration, self.bitRate, self.track, self.year, self.size];
	
	if ([db hadError]) 
	{
		DLog(@"Err inserting song %d: %@", [db lastErrorCode], [db lastErrorMessage]);
	}
	
	return ![db hadError];
}

- (BOOL)insertIntoServerPlaylistWithPlaylistId:(NSString *)md5
{
	NSString *table = [NSString stringWithFormat:@"splaylist%@", md5];
	return [self insertIntoTable:table inDatabase:[DatabaseSingleton sharedInstance].localPlaylistsDb];
}

- (BOOL)insertIntoFolderCacheForFolderId:(NSString *)folderId
{
	[[DatabaseSingleton sharedInstance].albumListCacheDb executeUpdate:@"INSERT INTO songsCache (folderId, title, songId, artist, album, genre, coverArtId, path, suffix, transcodedSuffix, duration, bitRate, track, year, size) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", [NSString md5:folderId], self.title, self.songId, self.artist, self.album, self.genre, self.coverArtId, self.path, self.suffix, self.transcodedSuffix, self.duration, self.bitRate, self.track, self.year, self.size];
	
	if ([[DatabaseSingleton sharedInstance].albumListCacheDb hadError])
	{
		DLog(@"Err inserting song %d: %@", [[DatabaseSingleton sharedInstance].albumListCacheDb lastErrorCode], [[DatabaseSingleton sharedInstance].albumListCacheDb lastErrorMessage]);
	}
	
	return ![[DatabaseSingleton sharedInstance].albumListCacheDb hadError];
}

- (BOOL)insertIntoGenreTable:(NSString *)table
{	
	[self.db executeUpdate:[NSString stringWithFormat:@"INSERT INTO %@ (md5, title, songId, artist, album, genre, coverArtId, path, suffix, transcodedSuffix, duration, bitRate, track, year, size) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", table], [self.path md5], self.title, self.songId, self.artist, self.album, self.genre, self.coverArtId, self.path, self.suffix, self.transcodedSuffix, self.duration, self.bitRate, self.track, self.year, self.size];
	
	if ([self.db hadError]) 
	{
		DLog(@"Err inserting song into genre table %d: %@", [self.db lastErrorCode], [self.db lastErrorMessage]);
	}
	
	return ![self.db hadError];
}

- (BOOL)insertIntoCachedSongsTable
{
	[self.db executeUpdate:[NSString stringWithFormat:@"REPLACE INTO cachedSongs (md5, finished, cachedDate, playedDate, title, songId, artist, album, genre, coverArtId, path, suffix, transcodedSuffix, duration, bitRate, track, year, size) VALUES (?, 'NO', %i, 0, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", (NSUInteger)[[NSDate date] timeIntervalSince1970]], [self.path md5], self.title, self.songId, self.artist, self.album, self.genre, self.coverArtId, self.path, self.suffix, self.transcodedSuffix, self.duration, self.bitRate, self.track, self.year, self.size];
	
	if ([self.db hadError]) 
	{
		DLog(@"Err inserting song into genre table %d: %@", [self.db lastErrorCode], [self.db lastErrorMessage]);
	}
	
	return ![self.db hadError];
}

- (BOOL)addToCacheQueue
{	
	if ([self.db intForQuery:@"SELECT COUNT(*) FROM cachedSongs WHERE md5 = ? AND finished = 'YES'", [self.path md5]] == 0) 
	{
		[self.db executeUpdate:@"INSERT INTO cacheQueue (md5, finished, cachedDate, playedDate, title, songId, artist, album, genre, coverArtId, path, suffix, transcodedSuffix, duration, bitRate, track, year, size) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", [self.path md5], @"NO", [NSNumber numberWithInt:(NSUInteger)[[NSDate date] timeIntervalSince1970]], [NSNumber numberWithInt:0], self.title, self.songId, self.artist, self.album, self.genre, self.coverArtId, self.path, self.suffix, self.transcodedSuffix, self.duration, self.bitRate, self.track, self.year, self.size];
	}
	
	if ([self.db hadError]) 
	{
		DLog(@"Err adding song to cache queue %d: %@", [self.db lastErrorCode], [self.db lastErrorMessage]);
	}
	
	return ![self.db hadError];
}

- (BOOL)addToPlaylistQueue
{
	DatabaseSingleton *dbControls = [DatabaseSingleton sharedInstance];
	MusicSingleton *musicControls = [MusicSingleton sharedInstance];

	BOOL hadError = NO;
	
	if ([SavedSettings sharedInstance].isJukeboxEnabled)
	{
		//DLog(@"inserting %@", aSong.title);
		[self insertIntoTable:@"jukeboxCurrentPlaylist" inDatabase:dbControls.currentPlaylistDb];
		if ([dbControls.currentPlaylistDb hadError])
			hadError = YES;
		
		if (musicControls.isShuffle)
		{
			[self insertIntoTable:@"jukeboxShufflePlaylist" inDatabase:dbControls.currentPlaylistDb];
			if ([dbControls.currentPlaylistDb hadError])
				hadError = YES;
		}
	}
	else
	{
		[self insertIntoTable:@"currentPlaylist" inDatabase:dbControls.currentPlaylistDb];
		if ([dbControls.currentPlaylistDb hadError])
			hadError = YES;
		
		if (musicControls.isShuffle)
		{
			[self insertIntoTable:@"shufflePlaylist" inDatabase:dbControls.currentPlaylistDb];
			if ([dbControls.currentPlaylistDb hadError])
				hadError = YES;
		}
	}
	
	return !hadError;
}

- (BOOL)addToShuffleQueue
{
	DatabaseSingleton *dbControls = [DatabaseSingleton sharedInstance];

	BOOL hadError = NO;
	
	if ([SavedSettings sharedInstance].isJukeboxEnabled)
	{
		[self insertIntoTable:@"jukeboxShufflePlaylist" inDatabase:dbControls.currentPlaylistDb];
		if ([dbControls.currentPlaylistDb hadError])
			hadError = YES;
	}
	else
	{
		[self insertIntoTable:@"shufflePlaylist" inDatabase:dbControls.currentPlaylistDb];
		if ([dbControls.currentPlaylistDb hadError])
			hadError = YES;
	}
	
	return !hadError;
}

- (BOOL)insertIntoCachedSongsLayout
{
	// Save the offline view layout info
	NSArray *splitPath = [self.path componentsSeparatedByString:@"/"];
	
	BOOL hadError = YES;	

	if ([splitPath count] <= 9)
	{
		NSMutableArray *segments = [[NSMutableArray alloc] initWithArray:splitPath];
		while ([segments count] < 9)
		{
			[segments addObject:@""];
		}
		
		NSString *query = [NSString stringWithFormat:@"INSERT INTO cachedSongsLayout (md5, genre, segs, seg1, seg2, seg3, seg4, seg5, seg6, seg7, seg8, seg9) VALUES ('%@', '%@', %i, ?, ?, ?, ?, ?, ?, ?, ?, ?)", [self.songId md5], self.genre, [splitPath count]];
		[self.db executeUpdate:query, [segments objectAtIndex:0], [segments objectAtIndex:1], [segments objectAtIndex:2], [segments objectAtIndex:3], [segments objectAtIndex:4], [segments objectAtIndex:5], [segments objectAtIndex:6], [segments objectAtIndex:7], [segments objectAtIndex:8]];
		
		hadError = [self.db hadError];
		
		[segments release];
	}
	
	return !hadError;
}

+ (BOOL)removeSongFromCacheDbByMD5:(NSString *)md5
{
	DatabaseSingleton *dbControls = [DatabaseSingleton sharedInstance];
	MusicSingleton *musicControls = [MusicSingleton sharedInstance];

	BOOL hadError = NO;	
	
	// Get the song info
	FMResultSet *result = [dbControls.songCacheDb executeQuery:@"SELECT genre, transcodedSuffix, suffix FROM cachedSongs WHERE md5 = ?", md5];
	[result next];
	NSString *genre = nil;
	NSString *transcodedSuffix = nil;
	NSString *suffix = nil;
	if ([result stringForColumnIndex:0] != nil)
		genre = [NSString stringWithString:[result stringForColumnIndex:0]];
	if ([result stringForColumnIndex:1] != nil)
		transcodedSuffix = [NSString stringWithString:[result stringForColumnIndex:1]];
	if ([result stringForColumnIndex:2] != nil)
		suffix = [NSString stringWithString:[result stringForColumnIndex:2]];
	[result close];
	if ([dbControls.songCacheDb hadError])
		hadError = YES;
	
	// Delete the row from the cachedSongs and genresSongs
	[dbControls.songCacheDb executeUpdate:@"DELETE FROM cachedSongs WHERE md5 = ?", md5];
	if ([dbControls.songCacheDb hadError])
		hadError = YES;
	[dbControls.songCacheDb executeUpdate:@"DELETE FROM cachedSongsLayout WHERE md5 = ?", md5];
	if ([dbControls.songCacheDb hadError])
		hadError = YES;
	[dbControls.songCacheDb executeUpdate:@"DELETE FROM genresSongs WHERE md5 = ?", md5];
	if ([dbControls.songCacheDb hadError])
		hadError = YES;
	
	// Delete the song from disk
	NSString *fileName;
	if (transcodedSuffix)
		fileName = [musicControls.audioFolderPath stringByAppendingString:[NSString stringWithFormat:@"/%@.%@", md5, transcodedSuffix]];
	else
		fileName = [musicControls.audioFolderPath stringByAppendingString:[NSString stringWithFormat:@"/%@.%@", md5, suffix]];
	///////// REWRITE TO CATCH THIS NSFILEMANAGER ERROR ///////////
	[[NSFileManager defaultManager] removeItemAtPath:fileName error:NULL];
	
	SUSCurrentPlaylistDAO *dataModel = [SUSCurrentPlaylistDAO dataModel];
	
	// Check if we're deleting the song that's currently playing. If so, stop the player.
	if (dataModel.currentSong && ![SavedSettings sharedInstance].isJukeboxEnabled &&
		[[dataModel.currentSong.path md5] isEqualToString:md5])
	{
        [[BassWrapperSingleton sharedInstance] stop];
	}
	
	// Clean up genres table
	if ([dbControls.songCacheDb intForQuery:@"SELECT COUNT(*) FROM genresSongs WHERE genre = ?", genre] == 0)
	{
		[dbControls.songCacheDb executeUpdate:@"DELETE FROM genres WHERE genre = ?", genre];
		if ([dbControls.songCacheDb hadError])
			hadError = YES;
	}
	
	return !hadError;
}

@end
