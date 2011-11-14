//
//  SUSStreamConnectionDelegate.m
//  iSub
//
//  Created by Benjamin Baron on 11/10/11.
//  Copyright (c) 2011 Ben Baron. All rights reserved.
//

#import "SUSStreamHandler.h"
#import "MusicSingleton.h"
#import "AudioStreamer.h"
#import "Song.h"
#import "iSubAppDelegate.h"
#import "NSMutableURLRequest+SUS.h"
#import "NSError-ISMSError.h"
#import "NSString-md5.h"

#define kThrottleTimeInterval 0.01

#define kMaxKilobitsPerSec3G 550
#define kMaxBytesPerSec3G ((kMaxKilobitsPerSec3G * 1024) / 8)
#define kMaxBytesPerInterval3G (kMaxBytesPerSec3G * kThrottleTimeInterval)

#define kMaxKilobitsPerSecWifi 8000
#define kMaxBytesPerSecWifi ((kMaxKilobitsPerSecWifi * 1024) / 8)
#define kMaxBytesPerIntervalWifi (kMaxBytesPerSecWifi * kThrottleTimeInterval)

#define kMinBytesToStartPlayback (1024 * 50)    // Number of bytes to wait before activating the player
#define kMinBytesToStartLimiting (1024 * 1024)   // Start throttling bandwidth after 1 MB downloaded for 192kbps files (adjusted accordingly by bitrate)

// Logging
#define isProgressLoggingEnabled NO
#define isThrottleLoggingEnabled NO

@implementation SUSStreamHandler
@synthesize totalBytesTransferred, bytesTransferred, throttlingDate, mySong, connection, byteOffset, delegate, fileHandle;

- (id)initWithSong:(Song *)song offset:(NSUInteger)offset delegate:(NSObject<SUSStreamHandlerDelegate> *)theDelegate
{
	if ((self = [super init]))
	{
		mySong = [song copy];
		delegate = theDelegate;
		byteOffset = offset;
	}
	
	return self;
}

- (id)initWithSong:(Song *)song delegate:(NSObject<SUSStreamHandlerDelegate> *)theDelegate
{
	return [[SUSStreamHandler alloc] initWithSong:song offset:0 delegate:theDelegate];
}

- (void)dealloc
{
	[fileHandle release]; fileHandle = nil;
	[mySong	release]; mySong = nil;
	[connection release]; connection = nil;
	[throttlingDate release]; throttlingDate = nil;
	[super dealloc];
}

- (void)start
{
	[self performSelectorInBackground:@selector(createConnection) withObject:nil]; 
}

- (void)createConnection
{
	@autoreleasepool 
	{
		MusicSingleton *musicControls = [MusicSingleton sharedInstance];
		
		// Create the file handle
		self.fileHandle = [NSFileHandle fileHandleForWritingAtPath:mySong.localPath];
		
		if (self.fileHandle)
		{
			// File exists so seek to end
			totalBytesTransferred = [self.fileHandle seekToEndOfFile];			
		}
		else
		{
			// File doesn't exist so create it
			totalBytesTransferred = 0;
			[[NSFileManager defaultManager] createFileAtPath:mySong.localPath contents:[NSData data] attributes:nil];
			self.fileHandle = [NSFileHandle fileHandleForWritingAtPath:mySong.localPath];
		}
		
		NSMutableDictionary *parameters = [NSMutableDictionary dictionaryWithObject:n2N(mySong.songId) forKey:@"id"];
		if ([musicControls maxBitrateSetting] != 0)
		{
			NSString *bitrate = [NSString stringWithFormat:@"%i", musicControls.maxBitrateSetting];
			[parameters setObject:n2N(bitrate) forKey:@"maxBitRate"];
		}
		
		NSMutableURLRequest *request = [NSMutableURLRequest requestWithSUSAction:@"stream" andParameters:parameters byteOffset:totalBytesTransferred];
		self.connection = [NSURLConnection connectionWithRequest:request delegate:self];
		if (connection)
		{
			CFRunLoopRun(); // Avoid thread exiting
		}
		else
		{
			NSError *error = [NSError errorWithISMSCode:ISMSErrorCode_CouldNotCreateConnection];
			[self.delegate SUSStreamHandlerConnectionFailed:self withError:error];
		}
	}
}

- (NSUInteger)bitrate
{	
	MusicSingleton *musicControls = [MusicSingleton sharedInstance];
	
	int bitRate = 128;
	
	if (mySong.bitRate == nil)
		bitRate = 128;
	else if ([mySong.bitRate intValue] < 1000)
		bitRate = [mySong.bitRate intValue];
	else
		bitRate = [mySong.bitRate intValue] / 1000;
	
	if (bitRate > musicControls.maxBitrateSetting && musicControls.maxBitrateSetting != 0)
		bitRate = musicControls.maxBitrateSetting;
	
	return bitRate;
}

- (void)cancel
{
	[connection cancel];
}

#pragma mark - Connection Delegate

- (BOOL)connection:(NSURLConnection *)connection canAuthenticateAgainstProtectionSpace:(NSURLProtectionSpace *)space 
{
	if([[space authenticationMethod] isEqualToString:NSURLAuthenticationMethodServerTrust]) 
		return YES; // Self-signed cert will be accepted
	
	return NO;
}

- (void)connection:(NSURLConnection *)connection didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{	
	if([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust])
	{
		[challenge.sender useCredential:[NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust] forAuthenticationChallenge:challenge]; 
	}
	[challenge.sender continueWithoutCredentialForAuthenticationChallenge:challenge];
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
	bytesTransferred = 0;
}

- (void)connection:(NSURLConnection *)theConnection didReceiveData:(NSData *)incrementalData 
{	
	totalBytesTransferred += [incrementalData length];
	bytesTransferred += [incrementalData length];
	
	// Save the data to the file
	[self.fileHandle writeData:incrementalData];
	
	// Notify delegate if enough bytes received to start playback
	if (totalBytesTransferred >= kMinBytesToStartPlayback)
		[self.delegate SUSStreamHandlerStartPlayback:self];
	
	// Log progress
	if (isProgressLoggingEnabled)
		DLog(@"downloadedLengthA:  %lu   bytesRead: %i", totalBytesTransferred, [incrementalData length]);
	
	// Handle throtling
	if (totalBytesTransferred < (kMinBytesToStartLimiting * ((float)self.bitrate / 160.0f)))
	{
		self.throttlingDate = [NSDate date];
		bytesTransferred = 0;
	}
	if ([[NSDate date] timeIntervalSinceDate:self.throttlingDate] > kThrottleTimeInterval &&
		totalBytesTransferred > (kMinBytesToStartLimiting * ((float)self.bitrate / 160.0f)))
	{
		bytesTransferred = 0;
		
		NSTimeInterval delay = 0.0;
		if ([iSubAppDelegate sharedInstance].isWifi == NO && bytesTransferred > kMaxBytesPerInterval3G)
		{
			delay = (kThrottleTimeInterval * ((double)bytesTransferred / (double)kMaxBytesPerInterval3G));
			
			if (isThrottleLoggingEnabled)
				DLog(@"Bandwidth used is more than kMaxBytesPerInterval3G, Pausing for %f", delay);
		}
		else if ([iSubAppDelegate sharedInstance].isWifi && bytesTransferred > kMaxBytesPerIntervalWifi)
		{
			delay = (kThrottleTimeInterval * ((double)bytesTransferred / (double)kMaxBytesPerIntervalWifi));
			
			if (isThrottleLoggingEnabled)
				DLog(@"Bandwidth used is more than kMaxBytesPerIntervalWifi, Pausing for %f", delay);
		}
				
		[NSThread sleepForTimeInterval:delay];
	}
}

- (void)connection:(NSURLConnection *)theConnection didFailWithError:(NSError *)error
{
	[theConnection release]; theConnection = nil;
		
	CFRunLoopStop(CFRunLoopGetCurrent()); // Stop the run loop so the thread can die
	
	[self.delegate SUSStreamHandlerConnectionFailed:self withError:error];
}	

- (void)connectionDidFinishLoading:(NSURLConnection *)theConnection 
{	
	[theConnection release]; theConnection = nil;
	
	CFRunLoopStop(CFRunLoopGetCurrent()); // Stop the run loop so the thread can die
	
	[self.delegate SUSStreamHandlerConnectionFinished:self];
}

#pragma mark - Overriding equality

- (NSUInteger)hash
{
	return [mySong.songId hash];
}

- (BOOL)isEqualToSUSStreamHandler:(SUSStreamHandler	*)otherHandler 
{
    if (self == otherHandler)
        return YES;
	
	return [mySong isEqualToSong:otherHandler.mySong];
}

- (BOOL)isEqual:(id)other 
{
    if (other == self)
        return YES;
	
    if (!other || ![other isKindOfClass:[self class]])
        return NO;
	
    return [self isEqualToSUSStreamHandler:other];
}

@end