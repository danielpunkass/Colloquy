#import "CQChatController.h"

#import "CQAlertView.h"
#import "CQChatCreationViewController.h"
#import "CQChatListViewController.h"
#import "CQChatRoomController.h"
#import "CQColloquyApplication.h"
#import "CQConnectionsController.h"
#import "CQDirectChatController.h"
#import "CQFileTransferController.h"
#import "CQSoundController.h"
#import "UIImageAdditions.h"

#import <ChatCore/MVChatConnection.h>
#import <ChatCore/MVChatUser.h>
#import <ChatCore/MVDirectChatConnection.h>
#import <ChatCore/MVFileTransfer.h>

#define ChatRoomInviteAlertTag 1
#define FileDownloadAlertTag 2

#define NewChatActionSheetTag 1
#define NewConnectionActionSheetTag 2
#define SendFileActionSheetTag 3
#define FileTypeActionSheetTag 4

@interface CQChatController (CQChatControllerPrivate)
- (void) _showNextChatControllerAnimated:(BOOL) animated;
#if ENABLE(FILE_TRANSFERS)
- (void) _sendImage;
#endif
@end

#pragma mark -

@implementation CQChatController
+ (CQChatController *) defaultController {
	static BOOL creatingSharedInstance = NO;
	static CQChatController *sharedInstance = nil;

	if (!sharedInstance && !creatingSharedInstance) {
		creatingSharedInstance = YES;
		sharedInstance = [[self alloc] init];
	}

	return sharedInstance;
}

- (id) init {
	if (!(self = [super init]))
		return nil;

	_chatControllers = [[NSMutableArray alloc] init];

	self.title = NSLocalizedString(@"Colloquies", @"Colloquies tab title");
	self.tabBarItem.image = [UIImage imageNamed:@"colloquies.png"];
	self.delegate = self;

	self.navigationBar.tintColor = [CQColloquyApplication sharedApplication].tintColor;

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_joinedRoom:) name:MVChatRoomJoinedNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_gotRoomMessage:) name:MVChatRoomGotMessageNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_gotPrivateMessage:) name:MVChatConnectionGotPrivateMessageNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_gotDirectChatMessage:) name:MVDirectChatConnectionGotMessageNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_invitedToRoom:) name:MVChatRoomInvitedNotification object:nil];

#if ENABLE(FILE_TRANSFERS)
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_gotFileDownloadOffer:) name:MVDownloadFileTransferOfferNotification object:nil];
#endif

	return self;
}

- (void) dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];

	[_chatListViewController release];
	[_chatControllers release];
	[_nextController release];
	[_nextRoomConnection release];

#if ENABLE(FILE_TRANSFERS)
	[_transferImage release];
	[_fileUser release];
#endif

	[super dealloc];
}

#pragma mark -

- (void) viewDidLoad {
	[super viewDidLoad];

	if (!_chatListViewController) {
		_chatListViewController = [[CQChatListViewController alloc] init];
		[self pushViewController:_chatListViewController animated:NO];
	}

	if (_nextController)
		[self _showNextChatControllerAnimated:NO];
}

- (void) viewWillAppear:(BOOL) animated {
	[super viewWillAppear:animated];

	self.totalImportantUnreadCount = 0;

	_active = YES;
}

- (void) viewWillDisappear:(BOOL) animated {
	[super viewWillDisappear:animated];

	_active = NO;
}

- (BOOL) shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation) interfaceOrientation {
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"CQDisableLandscape"])
		return (interfaceOrientation == UIInterfaceOrientationPortrait);
	return (UIInterfaceOrientationIsLandscape(interfaceOrientation) || interfaceOrientation == UIInterfaceOrientationPortrait);
}

#pragma mark -

static NSComparisonResult sortControllersAscending(id controller1, id controller2, void *context) {
	if ([controller1 isKindOfClass:[CQDirectChatController class]] && [controller2 isKindOfClass:[CQDirectChatController class]]) {
		CQDirectChatController *chatController1 = controller1;
		CQDirectChatController *chatController2 = controller2;
		NSComparisonResult result = [chatController1.connection.displayName caseInsensitiveCompare:chatController2.connection.displayName];
		if (result != NSOrderedSame)
			return result;

		result = [chatController1.connection.nickname caseInsensitiveCompare:chatController2.connection.nickname];
		if (result != NSOrderedSame)
			return result;

		if (chatController1.connection < chatController2.connection)
			return NSOrderedAscending;
		if (chatController1.connection > chatController2.connection)
			return NSOrderedDescending;

		if ([chatController1 isMemberOfClass:[CQChatRoomController class]] && [chatController2 isMemberOfClass:[CQDirectChatController class]])
			return NSOrderedAscending;
		if ([chatController1 isMemberOfClass:[CQDirectChatController class]] && [chatController2 isMemberOfClass:[CQChatRoomController class]])
			return NSOrderedDescending;

		return [chatController1.title caseInsensitiveCompare:chatController2.title];
	}
	else if ([controller1 isKindOfClass:[CQDirectChatController class]]) {
		return NSOrderedAscending;
	}
	else if ([controller2 isKindOfClass:[CQDirectChatController class]]) {
		return NSOrderedDescending;
	}
	else {
		return NSOrderedSame;
	}
}

#pragma mark -

- (void) _sortChatControllers {
	[_chatControllers sortUsingFunction:sortControllersAscending context:NULL];
}

- (void) _joinedRoom:(NSNotification *) notification {
	MVChatRoom *room = notification.object;
	CQChatRoomController *roomController = [self chatViewControllerForRoom:room ifExists:NO];
	[roomController didJoin];
}

- (void) _gotRoomMessage:(NSNotification *) notification {
	// We do this here to make sure we catch early messages right when we join (this includes dircproxy's dump).
	MVChatRoom *room = notification.object;

	CQChatRoomController *controller = [self chatViewControllerForRoom:room ifExists:NO];
	[controller addMessage:notification.userInfo];
}

- (void) _gotPrivateMessage:(NSNotification *) notification {
	MVChatUser *user = notification.object;

	if (user.localUser && [notification.userInfo objectForKey:@"target"])
		user = [notification.userInfo objectForKey:@"target"];

	BOOL hideFromUser = NO;
	if ([[notification.userInfo objectForKey:@"notice"] boolValue]) {
		if (![self chatViewControllerForUser:user ifExists:YES])
			hideFromUser = YES;

		if ( [[NSUserDefaults standardUserDefaults] integerForKey:@"JVChatAlwaysShowNotices"] == 1 || ( [[NSUserDefaults standardUserDefaults] integerForKey:@"JVChatAlwaysShowNotices"] == 0 && ![[notification userInfo] objectForKey:@"handled"] ) )
			hideFromUser = NO;
	}

	if (!hideFromUser) {
		CQDirectChatController *controller = [self chatViewControllerForUser:user ifExists:NO userInitiated:NO];
		[controller addMessage:notification.userInfo];
	}
}

- (void) _gotDirectChatMessage:(NSNotification *) notification {
	MVDirectChatConnection *connection = notification.object;

	CQDirectChatController *controller = [self chatViewControllerForDirectChatConnection:connection ifExists:NO];
	[controller addMessage:notification.userInfo];
}

#if ENABLE(FILE_TRANSFERS)
- (void) _gotFileDownloadOffer:(NSNotification *) notification {
	MVDownloadFileTransfer *transfer = notification.object;

	NSString *action = [[NSUserDefaults standardUserDefaults] stringForKey:@"CQFileDownloadAction"];
	if ([action isEqualToString:@"Auto-Accept"]) {
		NSString *filePath = [NSTemporaryDirectory() stringByAppendingPathComponent:transfer.originalFileName];
		[transfer setDestination:filePath renameIfFileExists:YES];
		[transfer acceptByResumingIfPossible:YES];
		return;
	} else if ([action isEqualToString:@"Auto-Deny"]) {
		[transfer reject];
		return;
	}

	NSString *file = transfer.originalFileName;
	if (![UIImage isValidImageFormat:file]) {
		[transfer.user.connection sendRawMessageWithFormat:@"NOTICE %@ :%@", transfer.user.nickname, @"Mobile Colloquy does not support files of that type."];
		[transfer reject];
		return;
	}

	NSString *user = transfer.user.displayName;

	CQAlertView *alert = [[CQAlertView alloc] init];
	alert.tag = FileDownloadAlertTag;
	alert.userInfo = transfer;
	alert.delegate = self;
	alert.title = NSLocalizedString(@"File Download", "File Download alert title");
	alert.message = [NSString stringWithFormat:NSLocalizedString(@"%@ wants to send you \"%@\".", "File download alert message"), user, file];

	[alert addButtonWithTitle:NSLocalizedString(@"Accept", @"Accept alert button title")];

	alert.cancelButtonIndex = [alert addButtonWithTitle:NSLocalizedString(@"Deny", @"Deny alert button title")];

	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"CQVibrateOnFileTransfer"])
		[CQSoundController vibrate];

	if (![[[NSUserDefaults standardUserDefaults] stringForKey:@"CQSoundOnFileTransfer"] isEqualToString:@"None"]) {
		static CQSoundController *fileTransferSound;

		if (!fileTransferSound) {
			NSString *alert = [[NSUserDefaults standardUserDefaults] stringForKey:@"CQSoundOnFileTransfer"];
			fileTransferSound = [[CQSoundController alloc] initWithSoundNamed:alert];
		}

		[fileTransferSound playSound];
	}

	[alert show];

	[alert release];
}
#endif

- (void) _invitedToRoom:(NSNotification *) notification {
	NSString *roomName = [[notification userInfo] objectForKey:@"room"];
	MVChatConnection *connection = [notification object];

	NSString *action = [[NSUserDefaults standardUserDefaults] stringForKey:@"CQChatRoomInviteAction"];
	if ([action isEqualToString:@"Auto-Join"]) {
		[connection joinChatRoomNamed:roomName];
		return;
	} else if ([action isEqualToString:@"Auto-Deny"]) {
		return;
	}

	MVChatUser *user = [[notification userInfo] objectForKey:@"user"];
	MVChatRoom *room = [connection chatRoomWithName:roomName];

	CQAlertView *alert = [[CQAlertView alloc] init];
	alert.tag = ChatRoomInviteAlertTag;
	alert.userInfo = room;
	alert.delegate = self;
	alert.title = NSLocalizedString(@"Invited to Room", "Invited to room alert title");
	alert.message = [NSString stringWithFormat:NSLocalizedString(@"You were invited to \"%@\" by \"%@\" on \"%@\".", "Invited to join room alert message"), room.displayName, user.displayName, connection.displayName];

	alert.cancelButtonIndex = [alert addButtonWithTitle:NSLocalizedString(@"Dismiss", @"Dismiss alert button title")];

	[alert addButtonWithTitle:NSLocalizedString(@"Join", @"Join button title")];

	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"CQVibrateOnHighlight"])
		[CQSoundController vibrate];

	if (![[[NSUserDefaults standardUserDefaults] stringForKey:@"CQSoundOnHighlight"] isEqualToString:@"None"]) {
		static CQSoundController *highlightSound;

		if (!highlightSound) {
			NSString *alert = [[NSUserDefaults standardUserDefaults] stringForKey:@"CQSoundOnHighlight"];
			highlightSound = [[CQSoundController alloc] initWithSoundNamed:alert];
		}		

		[highlightSound playSound];
	}

	[alert show];

	[alert release];
}

- (void) _showNextChatControllerAnimated:(BOOL) animated {
	if (self.topViewController != _chatListViewController)
		return;

	[_chatListViewController selectChatViewController:_nextController animatedSelection:NO animatedScroll:animated];
	[self pushViewController:(UIViewController *)_nextController animated:animated];

	[_nextController release];
	_nextController = nil;
}

- (void) _showNextChatController {
	[self _showNextChatControllerAnimated:YES];
}

#pragma mark -

- (void) alertView:(UIAlertView *) alertView clickedButtonAtIndex:(NSInteger) buttonIndex {
	id userInfo = ((CQAlertView *)alertView).userInfo;

	if (buttonIndex == alertView.cancelButtonIndex) {
#if ENABLE(FILE_TRANSFERS)
		if (alertView.tag == FileDownloadAlertTag)
			[(MVDownloadFileTransfer *)userInfo reject];
#endif
		return;
	}

	if (alertView.tag == ChatRoomInviteAlertTag) {
		[(MVChatRoom *)userInfo join];
#if ENABLE(FILE_TRANSFERS)
	} else if (alertView.tag == FileDownloadAlertTag) {
		MVDownloadFileTransfer *transfer = userInfo;
		NSString *filePath = [NSTemporaryDirectory() stringByAppendingPathComponent:transfer.originalFileName];
		[self chatViewControllerForFileTransfer:transfer ifExists:NO];
		[transfer setDestination:filePath renameIfFileExists:YES];
		[transfer acceptByResumingIfPossible:YES];
#endif
	}
}

#pragma mark -

- (void) actionSheet:(UIActionSheet *) actionSheet clickedButtonAtIndex:(NSInteger) buttonIndex {
	if (buttonIndex == actionSheet.cancelButtonIndex) {
#if ENABLE(FILE_TRANSFERS)
		[_fileUser release];
		_fileUser = nil;
#endif
		return;
	}

	if (actionSheet.tag == NewChatActionSheetTag) {
		CQChatCreationViewController *creationViewController = [[CQChatCreationViewController alloc] init];

		if (buttonIndex == 0)
			creationViewController.roomTarget = YES;

		[self presentModalViewController:creationViewController animated:YES];
		[creationViewController release];
	} else if (actionSheet.tag == NewConnectionActionSheetTag) {
		if (buttonIndex == 0) {
			[[CQConnectionsController defaultController] showCreationActionSheet];
		} else if (buttonIndex == 1) {
			[self joinSupportRoom];
		}
#if ENABLE(FILE_TRANSFERS)
	} else if (actionSheet.tag == SendFileActionSheetTag) {
		BOOL sendExistingPhoto = NO;
		BOOL takeNewPhoto = NO;
		BOOL sendContact = NO;

		if (buttonIndex == 0) {
            if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
				takeNewPhoto = YES;
            } else if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) {
				sendExistingPhoto = YES;
            } else {
                sendContact = YES;
            }
        } else if (buttonIndex == 1) {
            if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) {
				sendExistingPhoto = YES;
            } else {
                sendContact = YES;
            }
        } else {
			sendContact = YES;
        }

		if (takeNewPhoto) {
			UIImagePickerController *picker = [[UIImagePickerController alloc] init];
			picker.delegate = self;
			picker.allowsImageEditing = YES;
			picker.sourceType = UIImagePickerControllerSourceTypeCamera;
			[self presentModalViewController:picker animated:YES];
			[picker release];
		} else if (sendExistingPhoto) {
			UIImagePickerController *picker = [[UIImagePickerController alloc] init];
			picker.delegate = self;
			picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
			[self presentModalViewController:picker animated:YES];
			[picker release];
		} else if (sendContact) {
			NSAssert(NO, @"Contact sending not implemented.");
		}
    } else if (actionSheet.tag == FileTypeActionSheetTag) {
		_png = (buttonIndex == 0);

		[self _sendImage];
#endif
	}
}

#pragma mark -

#if ENABLE(FILE_TRANSFERS)
- (void) imagePickerController:(UIImagePickerController *) picker didFinishPickingImage:(UIImage *) image editingInfo:(NSDictionary *) editingInfo {
	_transferImage = [image retain];
	
	NSString *behavior = [[NSUserDefaults standardUserDefaults] stringForKey:@"CQFileTransferBehavior"];
	if ([behavior isEqualToString:@"Ask"]) {
		UIActionSheet *sheet = [[UIActionSheet alloc] init];
		sheet.delegate = self;
		sheet.tag = FileTypeActionSheetTag;
		[sheet addButtonWithTitle:NSLocalizedString(@"PNG", @"PNG button title")];
		[sheet addButtonWithTitle:NSLocalizedString(@"JPG", @"JPG button title")];
		[[CQColloquyApplication sharedApplication] showActionSheet:sheet];
		[sheet release];
	} else {
		_png = [behavior isEqualToString:@"PNG"];

		[self _sendImage];
	}

    [self dismissModalViewControllerAnimated:YES];
}

- (void) imagePickerControllerDidCancel:(UIImagePickerController *) picker {
    [self dismissModalViewControllerAnimated:YES];
    [_fileUser release];
}

#pragma mark -

- (void) _sendImage {
	NSData *data = nil;
	if (_png) data = UIImagePNGRepresentation(_transferImage);
	else data = UIImageJPEGRepresentation(_transferImage, 0.83333333f);

	[_transferImage release];

	NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
	[formatter setDateFormat:@"yyyy-MM-dd-A"];

	NSString *name = [[formatter stringFromDate:[NSDate date]] stringByAppendingString:@".png"];
	[formatter release];

	name = [name stringByReplacingOccurrencesOfString:@" " withString:@"_"];

	NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
	[data writeToFile:path atomically:NO];

	MVUploadFileTransfer *transfer = [_fileUser sendFile:path passively:YES];
	[self chatViewControllerForFileTransfer:transfer ifExists:NO];
	[_fileUser release];
}
#endif

#pragma mark -

- (NSDictionary *) persistentStateForConnection:(MVChatConnection *) connection {
	NSArray *controllers = [self chatViewControllersForConnection:connection];
	if (!controllers.count)
		return nil;

	NSMutableDictionary *state = [[NSMutableDictionary alloc] init];
	NSMutableArray *controllerStates = [[NSMutableArray alloc] init];

	for (id <CQChatViewController> controller in controllers) {
		if (![controller respondsToSelector:@selector(persistentState)])
			continue;

		NSDictionary *controllerState = controller.persistentState;
		if (!controllerState.count || ![controllerState objectForKey:@"class"])
			continue;

		[controllerStates addObject:controllerState];
	}

	if (controllerStates.count)
		[state setObject:controllerStates forKey:@"chatControllers"];

	[controllerStates release];

	return [state autorelease];
}

- (void) restorePersistentState:(NSDictionary *) state forConnection:(MVChatConnection *) connection {
	for (NSDictionary *controllerState in [state objectForKey:@"chatControllers"]) {
		NSString *className = [controllerState objectForKey:@"class"];
		Class class = NSClassFromString(className);
		if (!class)
			continue;

		id <CQChatViewController> controller = [[class alloc] initWithPersistentState:controllerState usingConnection:connection];
		if (!controller)
			continue;

		[_chatControllers addObject:controller];
		[controller release];

		if ([[controllerState objectForKey:@"active"] boolValue]) {
			id old = _nextController;
			_nextController = [controller retain];
			[old release];
		}
	}

	[self _sortChatControllers];
}

#pragma mark -

- (NSInteger) totalImportantUnreadCount {
	return _totalImportantUnreadCount;
}

- (void) setTotalImportantUnreadCount:(NSInteger) count {
	if (count < 0)
		count = 0;

	_totalImportantUnreadCount = count;

	if ((!_active || self.topViewController != _chatListViewController) && _totalImportantUnreadCount) {
		_chatListViewController.navigationItem.title = [NSString stringWithFormat:NSLocalizedString(@"%@ (%u)", @"Unread count view title, uses the view's normal title with a number"), self.title, _totalImportantUnreadCount];
		self.tabBarItem.badgeValue = [NSString stringWithFormat:@"%u", _totalImportantUnreadCount];
	} else {
		_chatListViewController.navigationItem.title = self.title;
		self.tabBarItem.badgeValue = nil;
	}
}

#pragma mark -

- (void) showNewChatActionSheet {
	UIActionSheet *sheet = [[UIActionSheet alloc] init];
	sheet.delegate = self;

	if ([CQConnectionsController defaultController].connections.count) {
		sheet.tag = NewChatActionSheetTag;

		[sheet addButtonWithTitle:NSLocalizedString(@"Join a Chat Room", @"Join a Chat Room button title")];
		[sheet addButtonWithTitle:NSLocalizedString(@"Message a User", @"Message a User button title")];
	} else {
		sheet.tag = NewConnectionActionSheetTag;

		[sheet addButtonWithTitle:NSLocalizedString(@"Add New Connection", @"Add New Connection button title")];
		[sheet addButtonWithTitle:NSLocalizedString(@"Join Support Room", @"Join Support Room button title")];
	}

	sheet.cancelButtonIndex = [sheet addButtonWithTitle:NSLocalizedString(@"Cancel", @"Cancel button title")];

	[[CQColloquyApplication sharedApplication] showActionSheet:sheet];

	[sheet release];
}

- (void) showFilePickerWithUser:(MVChatUser *) user {
#if ENABLE(FILE_TRANSFERS)
	UIActionSheet *sheet = [[UIActionSheet alloc] init];
	sheet.delegate = self;
	sheet.tag = SendFileActionSheetTag;

	if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera])
		[sheet addButtonWithTitle:NSLocalizedString(@"Take Photo", @"Take Photo button title")];
	if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary])
		[sheet addButtonWithTitle:NSLocalizedString(@"Choose Existing Photo", @"Choose Existing Photo button title")];
//	[sheet addButtonWithTitle:NSLocalizedString(@"Choose Contact", @"Choose Contact button title")];

	sheet.cancelButtonIndex = [sheet addButtonWithTitle:NSLocalizedString(@"Cancel", @"Cancel button title")];

	_fileUser = [user retain];

	[[CQColloquyApplication sharedApplication] showActionSheet:sheet];

	[sheet release];
#endif
}

- (void) showChatControllerWhenAvailableForRoomNamed:(NSString *) roomName andConnection:(MVChatConnection *) connection {
	NSParameterAssert(connection != nil);

	[_nextRoomConnection release];
	_nextRoomConnection = nil;

	MVChatRoom *room = (roomName.length ? [connection chatRoomWithName:roomName] : nil);
	if (room) {
		CQChatRoomController *controller = [self chatViewControllerForRoom:room ifExists:YES];
		if (controller) {
			[self showChatController:controller animated:YES];
			return;
		}
	}

	_nextRoomConnection = [connection retain];
}

- (void) showChatControllerForUserNicknamed:(NSString *) nickname andConnection:(MVChatConnection *) connection {
	[_nextRoomConnection release];
	_nextRoomConnection = nil;

	MVChatUser *user = (nickname.length ? [[connection chatUsersWithNickname:nickname] anyObject] : nil);
	if (!user)
		return;

	CQDirectChatController *controller = [self chatViewControllerForUser:user ifExists:NO];
	if (!controller)
		return;

	[self showChatController:controller animated:YES];
}

- (void) joinSupportRoom {
	MVChatConnection *connection = [[CQConnectionsController defaultController] connectionForServerAddress:@"freenode.net"];
	if (!connection) connection = [[CQConnectionsController defaultController] connectionForServerAddress:@"freenode.com"];

	if (!connection) {
		connection = [[MVChatConnection alloc] initWithType:MVChatConnectionIRCType];
		connection.displayName = @"Freenode";
		connection.server = @"irc.freenode.net";
		connection.preferredNickname = [MVChatConnection defaultNickname];
		connection.realName = [MVChatConnection defaultRealName];
		connection.username = [connection.preferredNickname lowercaseString];
		connection.encoding = [MVChatConnection defaultEncoding];
		connection.automaticallyConnect = NO;
		connection.secure = NO;
		connection.serverPort = 6667;

		[[CQConnectionsController defaultController] addConnection:connection];

		[connection release];
	}

	[connection connectAppropriately];

	[self showChatControllerWhenAvailableForRoomNamed:@"#colloquy-mobile" andConnection:connection];

	[connection joinChatRoomNamed:@"#colloquy-mobile"];

	[CQColloquyApplication sharedApplication].tabBarController.selectedViewController = self;
}

- (void) showChatController:(id <CQChatViewController>) controller animated:(BOOL) animated {
	[_nextRoomConnection release];
	_nextRoomConnection = nil;

	BOOL delayed = (animated && self.topViewController != _chatListViewController);
	if (delayed) {
		id old = _nextController;
		_nextController = [controller retain];
		[old release];
	}

	[self popToRootViewControllerAnimated:animated];

	if (!delayed) {
		[_chatListViewController selectChatViewController:controller animatedSelection:NO animatedScroll:animated];
		[self pushViewController:(UIViewController *)controller animated:animated];
	}
}

- (void) navigationController:(UINavigationController *) navigationController willShowViewController:(UIViewController *) viewController animated:(BOOL) animated {
	if (viewController == _chatListViewController)
		self.totalImportantUnreadCount = 0;
}

- (void) navigationController:(UINavigationController *) navigationController didShowViewController:(UIViewController *) viewController animated:(BOOL) animated {
	if (viewController == _chatListViewController && _nextController)
		[self performSelector:@selector(_showNextChatController) withObject:nil afterDelay:0.33];
}

#pragma mark -

@synthesize chatViewControllers = _chatControllers;

- (NSArray *) chatViewControllersForConnection:(MVChatConnection *) connection {
	NSParameterAssert(connection != nil);

	NSMutableArray *result = [NSMutableArray array];

	for (id controller in _chatControllers)
		if ([controller conformsToProtocol:@protocol(CQChatViewController)] && ((id <CQChatViewController>) controller).connection == connection)
			[result addObject:controller];

	return result;
}

- (NSArray *) chatViewControllersOfClass:(Class) class {
	NSParameterAssert(class != NULL);

	NSMutableArray *result = [NSMutableArray array];

	for (id controller in _chatControllers)
		if ([controller isMemberOfClass:class])
			[result addObject:controller];

	return result;
}

- (NSArray *) chatViewControllersKindOfClass:(Class) class {
	NSParameterAssert(class != NULL);

	NSMutableArray *result = [NSMutableArray array];

	for (id controller in _chatControllers)
		if ([controller isKindOfClass:class])
			[result addObject:controller];

	return result;
}

#pragma mark -

- (CQChatRoomController *) chatViewControllerForRoom:(MVChatRoom *) room ifExists:(BOOL) exists {
	NSParameterAssert(room != nil);

	for (id <CQChatViewController> controller in _chatControllers)
		if ([controller isMemberOfClass:[CQChatRoomController class]] && controller.target == room)
			return (CQChatRoomController *)controller;

	CQChatRoomController *controller = nil;

	if (!exists) {
		if ((controller = [[CQChatRoomController alloc] initWithTarget:room])) {
			[_chatControllers addObject:controller];
			[controller release];

			[self _sortChatControllers];

			[_chatListViewController addChatViewController:controller];

			if (room.connection == _nextRoomConnection)
				[self showChatController:controller animated:YES];

			return controller;
		}
	}

	return nil;
}

- (CQDirectChatController *) chatViewControllerForUser:(MVChatUser *) user ifExists:(BOOL) exists {
	return [self chatViewControllerForUser:user ifExists:exists userInitiated:YES];
}

- (CQDirectChatController *) chatViewControllerForUser:(MVChatUser *) user ifExists:(BOOL) exists userInitiated:(BOOL) initiated {
	NSParameterAssert(user != nil);

	for (id <CQChatViewController> controller in _chatControllers)
		if ([controller isMemberOfClass:[CQDirectChatController class]] && controller.target == user)
			return (CQDirectChatController *)controller;

	CQDirectChatController *controller = nil;

	if (!exists) {
		if ((controller = [[CQDirectChatController alloc] initWithTarget:user])) {
			[_chatControllers addObject:controller];
			[controller release];

			[self _sortChatControllers];

			[_chatListViewController addChatViewController:controller];

			return controller;
		}
	}

	return nil;
}

- (CQDirectChatController *) chatViewControllerForDirectChatConnection:(MVDirectChatConnection *) connection ifExists:(BOOL) exists {
	NSParameterAssert(connection != nil);

	for (id <CQChatViewController> controller in _chatControllers)
		if ([controller isMemberOfClass:[CQDirectChatController class]] && controller.target == connection)
			return (CQDirectChatController *)controller;

	CQDirectChatController *controller = nil;

	if (!exists) {
		if ((controller = [[CQDirectChatController alloc] initWithTarget:connection])) {
			[_chatControllers addObject:controller];
			[controller release];

			[self _sortChatControllers];

			[_chatListViewController addChatViewController:controller];

			return controller;
		}
	}

	return nil;
}

#if ENABLE(FILE_TRANSFERS)
- (CQFileTransferController *) chatViewControllerForFileTransfer:(MVFileTransfer *) transfer ifExists:(BOOL) exists {
	NSParameterAssert(transfer != nil);

	for (id controller in _chatControllers)
		if ([controller isMemberOfClass:[CQFileTransferController class]] && ((CQFileTransferController *)controller).transfer == transfer)
			return controller;

	if (!exists) {
		CQFileTransferController *controller = [[CQFileTransferController alloc] initWithTransfer:transfer];
		if (controller) {
			[_chatControllers addObject:controller];
			[controller release];

			[self _sortChatControllers];

			[_chatListViewController addChatViewController:controller];

			return controller;
		}
	}

	return nil;
}
#endif

#pragma mark -

- (BOOL) connectionHasAChatRoom:(MVChatConnection *) connection {
	for (id <CQChatViewController> chatViewController in [self chatViewControllersForConnection:connection])
		if ([chatViewController.target isKindOfClass:[MVChatRoom class]])
			return YES;
	return NO;
}

- (BOOL) connectionHasAPrivateChat:(MVChatConnection *) connection {
	for (id <CQChatViewController> chatViewController in [self chatViewControllersForConnection:connection])
		if ([chatViewController.target isKindOfClass:[MVChatUser class]])
			return YES;
	return NO;
}

#pragma mark -

- (void) closeViewController:(id) controller {
	if ([controller respondsToSelector:@selector(close)])
		[controller close];
	[_chatControllers removeObjectIdenticalTo:controller];
}
@end

#pragma mark -

@implementation MVIRCChatRoom (CQChatControllerAdditions)
- (NSString *) displayName {
	if (![[NSUserDefaults standardUserDefaults] boolForKey:@"JVShowFullRoomNames"])
		return [self.connection displayNameForChatRoomNamed:self.name];
	return self.name;
}
@end
