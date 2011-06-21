//
//  DribbbleLikeDownloader.m
//  LockerRoom
//
//  Created by Joni Salonen on 5/30/11.
//  Copyright 2011 bilambee. All rights reserved.
//

#import "DribbbleLikeDownloader.h"
#import "DribbbleShot.h"
#import "Finder.h"

@implementation DribbbleLikeDownloader

@synthesize checkAllPages;

+(DribbbleLikeDownloader*)downloaderForPlayer:(NSString *)playerId directory:(NSString *)target
{
	DribbbleLikeDownloader *obj = [DribbbleLikeDownloader alloc];
	obj->playerId = [playerId retain];
	obj->currentPage = 1;
	obj->numberOfPages = -1;
	obj->currentDownloads = 0;
	
	obj->currentData = nil;
	obj->targetDirectory = [target retain];
	
	return obj;
}

-(void)dealloc
{
	[playerId release];
	[targetDirectory release];
	[currentData release];
	[fileNameMap release];
	[super dealloc];
}

-(BOOL)downloadNextPage
{
	if (numberOfPages != -1 && currentPage >= numberOfPages) {
		// download finished
		if (downloadInProgress != NO) {
			NSLog(@"Finished downloading!");
			[currentDelegate performSelector:@selector(dribbbleLikeDownloaderFinished:) withObject:self];
			downloadInProgress = NO;
		}
		return NO;
	} else if (currentDownloads > 0) {
		// Still downloading a page, hold your horses...
		downloadInProgress = YES;
		return YES;
	} else {
		// Go get that new page!
		currentPage++;
		NSString *urlStr = [NSString stringWithFormat:
							@"http://api.dribbble.com/players/%@/shots/likes?page=%d&per_page=30", 
							playerId, currentPage];
		NSURL *url = [NSURL URLWithString:urlStr];
		NSURLRequest *req = [NSURLRequest requestWithURL:url];
		NSURLConnection *conn = [NSURLConnection connectionWithRequest:req delegate:self];
		if (conn) {
			NSLog(@"Downloading page %d", currentPage);
			if (currentData == nil) {
				currentData = [[NSMutableData dataWithLength:0] retain];
			} else {
				[currentData setLength:0];
			}
			downloadInProgress = YES; // download started
			[currentDelegate performSelector:@selector(dribbbleLikeDownloaderStarted:) withObject:self];
			return YES;
		} else {
			NSLog(@"Download failed on page %d", currentPage);
			[currentDelegate performSelector:@selector(dribbbleLikeDownloaderFinished:) withObject:self];
			downloadInProgress = NO; // download failed
			return NO;
		}
	}
}

-(void)downloadLikes:(id)delegate
{
	if (downloadInProgress == NO) {
		currentPage = 0;
		currentDelegate = delegate;
		fileNameMap = [[NSMutableDictionary alloc] init];
		[self downloadNextPage];
	}
}


#pragma mark Downloading metadata

-(NSString*)getFileName:(NSDictionary*)shot
{
	NSString *username = [[shot objectForKey:@"player"] objectForKey:@"username"];
	NSURL *imageUrl = [NSURL URLWithString:[shot objectForKey:@"image_url"]];
	
	NSString *filename  = [NSString stringWithFormat:@"%@-%@",
						   username, [imageUrl lastPathComponent]];
	
	return [targetDirectory stringByAppendingPathComponent:filename];
}


-(void)handleMetadataPage:(NSMutableDictionary*)page
{
	NSNumber *npages = [page objectForKey:@"pages"]; 
	numberOfPages = [npages intValue];
	
	// go get them likes!
	NSArray *likes = [page objectForKey:@"shots"];
	NSInteger downloadsStarted = 0;
	NSUInteger i, count = [likes count];
	for (i = 0; i < count; i++) {
		NSDictionary *obj = [likes objectAtIndex:i];
		NSString *fileName = [self getFileName:obj];
		NSFileManager *fm = [NSFileManager defaultManager];
		if (![fm fileExistsAtPath:fileName]) {
			NSURL *url = [NSURL URLWithString:[obj objectForKey:@"image_url"]];
			NSURLRequest *req = [NSURLRequest requestWithURL:url];
			NSURLDownload *download = [[NSURLDownload alloc] initWithRequest:req delegate:self];
			if (download) {
				NSLog(@"Downloading %@", fileName);
				DribbbleShot *shot = [[DribbbleShot alloc] init];
				shot.localPath = fileName;
				shot.imageURL = [url description];
				shot.playerUsername = [[obj objectForKey:@"player"] objectForKey:@"username"];
				shot.url = [obj objectForKey:@"url"];
				shot.title = [obj objectForKey:@"title"];
				[fileNameMap setObject:shot forKey:url];
				[shot release];
				[download setDestination:fileName allowOverwrite:NO];
				downloadsStarted = downloadsStarted + 1;
			} else {
				NSLog(@"Failed to download shot %@", [obj objectForKey:@"title"]);
			}
		} else {
			//NSLog(@"Already downloaded: %@", fileName);
		}
	}
	
	if (downloadsStarted == 0) {
		if (checkAllPages) {
			// if no downloads are started, go to next page
			[self downloadNextPage];
		} else {
			downloadInProgress = NO;
			NSLog(@"Already downloaded everything!");
			[currentDelegate performSelector:@selector(dribbbleLikeDownloaderFinished:) withObject:self];
		}
	}
}

-(void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
	[currentData setLength:0];
}

-(void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
	[currentData appendData:data];
}

-(void)connectionDidFinishLoading:(NSURLConnection *)connection
{
	[currentData appendBytes:"\0" length:1];
	NSString *dataString = [NSString stringWithUTF8String:[currentData bytes]];
	if (dataString == nil) {
		NSLog(@"Failed to convert to UTF8: %s", [currentData bytes]);
	} else {
		NSMutableDictionary *jsonObj = [dataString JSONValue];
		[self handleMetadataPage:jsonObj];
	}
}

-(void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
	NSLog(@"Download failed: %@", [error localizedDescription]);
}

#pragma mark Downloading shots

-(void)downloadDidBegin:(NSURLDownload *)download
{
//	NSLog(@"Download did begin");
	currentDownloads++;
	[currentDelegate performSelector:@selector(dribbbleLikeDownloader:downloadDidBegin:) 
						  withObject:self 
						  withObject:download];
}

-(void)setFinderComment:(NSString*)comment forFile:(NSString*)path
{
	@try {
		FinderApplication *finderApp = [SBApplication applicationWithBundleIdentifier:@"com.apple.finder"];
		NSURL *location = [NSURL fileURLWithPath:path];
		FinderItem *item = [[finderApp items] objectAtLocation:location];
		item.comment = comment;
	}
	@catch (NSException *ex) {
		NSLog(@"Unable to set finder comment for %@: %@", path, ex);
	}
}

-(void)downloadDidFinish:(NSURLDownload *)download
{
	NSURL *requestURL = [[download request] URL];
	DribbbleShot *shot = [fileNameMap objectForKey:requestURL]; 
	[self setFinderComment:[shot finderComment] forFile:shot.localPath];
	[fileNameMap removeObjectForKey:requestURL];

	currentDownloads--;
	[self downloadNextPage];
}

-(void)download:(NSURLDownload *)download didFailWithError:(NSError *)error
{
	// Release memory allocated for dribbble shot data
	NSURL *requestURL = [[download request] URL];
	[fileNameMap removeObjectForKey:requestURL];

	NSLog(@"Error downloading %@: %@", [[download request] URL], [error localizedDescription]);
	currentDownloads--;
	[self downloadNextPage];
}

@end
