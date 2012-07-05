//
//  PlaylistsViewController.h
//  iSub
//
//  Created by Ben Baron on 4/2/10.
//  Copyright 2010 Ben Baron. All rights reserved.
//

#import "BBSimpleConnectionQueue.h"
#import "ISMSLoaderDelegate.h"

@class BBSimpleConnectionQueue, SUSServerPlaylistsDAO;

@interface PlaylistsViewController : UITableViewController <BBSimpleConnectionQueueDelegate, ISMSLoaderDelegate>

@property (nonatomic, strong) UIView *headerView;
@property (nonatomic, strong) UISegmentedControl *segmentedControl;
@property (nonatomic, strong) UIImageView *noPlaylistsScreen;
@property (nonatomic) BOOL isNoPlaylistsScreenShowing;
@property (nonatomic, strong) UILabel *savePlaylistLabel;
@property (nonatomic, strong) UILabel *playlistCountLabel;
@property (nonatomic, strong) UIButton *savePlaylistButton;
@property (nonatomic, strong) UILabel *deleteSongsLabel;
@property (nonatomic, strong) UILabel *spacerLabel;
@property (nonatomic, strong) UILabel *editPlaylistLabel;
@property (nonatomic, strong) UIButton *editPlaylistButton;
@property (nonatomic) BOOL isPlaylistSaveEditShowing;
@property (nonatomic, strong) BBSimpleConnectionQueue *connectionQueue;
@property (nonatomic) BOOL savePlaylistLocal;
@property (nonatomic, strong) NSMutableData *receivedData;
@property (nonatomic, strong) NSURLConnection *connection;
@property (nonatomic, strong) NSMutableURLRequest *request;
@property (nonatomic, strong) SUSServerPlaylistsDAO *serverPlaylistsDataModel;
@property (nonatomic) NSUInteger currentPlaylistCount;
@property (nonatomic, strong) UITextField *playlistNameTextField;

- (void)showDeleteButton;
- (void)hideDeleteButton;

- (void)segmentAction:(id)sender;
- (void)updateCurrentPlaylistCount;

- (void)parseData;
- (void)cancelLoad;

@end
