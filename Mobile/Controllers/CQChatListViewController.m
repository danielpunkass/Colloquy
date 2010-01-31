#import "CQChatListViewController.h"

#import "CQActionSheet.h"
#import "CQChatRoomController.h"
#import "CQColloquyApplication.h"
#import "CQConnectionsController.h"
#import "CQDirectChatController.h"
#import "CQFileTransferController.h"
#import "CQFileTransferTableCell.h"
#import "CQTableViewSectionHeader.h"

#import <ChatCore/MVChatConnection.h>
#import <ChatCore/MVChatRoom.h>
#import <ChatCore/MVChatUser.h>

static BOOL showsChatIcons;

@implementation CQChatListViewController
+ (void) userDefaultsChanged {
	showsChatIcons = [[NSUserDefaults standardUserDefaults] boolForKey:@"CQShowsChatIcons"];
}

+ (void) initialize {
	static BOOL userDefaultsInitialized;

	if (userDefaultsInitialized)
		return;

	userDefaultsInitialized = YES;

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(userDefaultsChanged) name:NSUserDefaultsDidChangeNotification object:nil];

	[self userDefaultsChanged];
}

- (id) init {
	if (!(self = [super initWithStyle:UITableViewStylePlain]))
		return nil;

	self.title = NSLocalizedString(@"Colloquies", @"Colloquies view title");

	UIBarButtonItem *addItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:[CQChatController defaultController] action:@selector(showNewChatActionSheet:)];
	self.navigationItem.leftBarButtonItem = addItem;
	[addItem release];
	
	self.navigationItem.leftBarButtonItem.accessibilityLabel = NSLocalizedString(@"New chat.", @"Voiceover new chat label");
	self.navigationItem.rightBarButtonItem.accessibilityLabel = NSLocalizedString(@"Manage chats.", @"Voiceover manage chats label");

	self.editButtonItem.possibleTitles = [NSSet setWithObjects:NSLocalizedString(@"Manage", @"Manage button title"), NSLocalizedString(@"Done", @"Done button title"), nil];
	self.editButtonItem.title = NSLocalizedString(@"Manage", @"Manage button title");
	self.navigationItem.rightBarButtonItem = self.editButtonItem;

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_addedChatViewController:) name:CQChatControllerAddedChatViewControllerNotification object:nil];

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_refreshConnectionChatCells:) name:MVChatConnectionDidConnectNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_refreshConnectionChatCells:) name:MVChatConnectionDidDisconnectNotification object:nil];

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_refreshChatCell:) name:MVChatRoomJoinedNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_refreshChatCell:) name:MVChatRoomPartedNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_refreshChatCell:) name:MVChatRoomKickedNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_refreshChatCell:) name:MVChatUserNicknameChangedNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_refreshChatCell:) name:MVChatUserStatusChangedNotification object:nil];

#if ENABLE(FILE_TRANSFERS)
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_refreshFileTransferCell:) name:MVFileTransferFinishedNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_refreshFileTransferCell:) name:MVFileTransferErrorOccurredNotification object:nil];
#endif

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_updateMessagePreview:) name:CQChatViewControllerRecentMessagesUpdatedNotification object:nil];

	return self;
}

- (void) dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];

	[super dealloc];
}

#pragma mark -

static MVChatConnection *connectionForSection(NSUInteger section) {
	NSArray *controllers = [CQChatController defaultController].chatViewControllers;
	if (!controllers.count)
		return nil;

	MVChatConnection *currentConnection = nil;
	NSUInteger sectionIndex = 0;

	for (id controller in controllers) {
		if (![controller conformsToProtocol:@protocol(CQChatViewController)])
			continue;

		id <CQChatViewController> chatViewController = controller;
		if (chatViewController.connection != currentConnection) {
			if (currentConnection) ++sectionIndex;
			currentConnection = chatViewController.connection;
		}

		if (sectionIndex == section)
			return chatViewController.connection;
	}

	return nil;
}

static NSUInteger sectionIndexForConnection(MVChatConnection *connection) {
	NSArray *controllers = [CQChatController defaultController].chatViewControllers;
	if (!controllers.count)
		return NSNotFound;

	MVChatConnection *currentConnection = nil;
	NSUInteger sectionIndex = 0;

	for (id controller in controllers) {
		if (![controller conformsToProtocol:@protocol(CQChatViewController)])
			continue;

		id <CQChatViewController> chatViewController = controller;
		if (chatViewController.connection != currentConnection) {
			if (currentConnection) ++sectionIndex;
			currentConnection = chatViewController.connection;
		}

		if (chatViewController.connection == connection)
			return sectionIndex;
	}

	return NSNotFound;
}

static NSIndexPath *indexPathForChatController(id controller) {
	NSArray *controllers = [CQChatController defaultController].chatViewControllers;
	if (!controllers.count)
		return nil;

	MVChatConnection *connection = nil;
	if ([controller conformsToProtocol:@protocol(CQChatViewController)])
		connection = ((id <CQChatViewController>) controller).connection;

	MVChatConnection *currentConnection = nil;
	NSUInteger sectionIndex = 0;
	NSUInteger rowIndex = 0;

	for (id currentController in controllers) {
		if ([currentController conformsToProtocol:@protocol(CQChatViewController)]) {
			id <CQChatViewController> chatViewController = currentController;
			if (chatViewController.connection != currentConnection) {
				if (currentConnection) ++sectionIndex;
				currentConnection = chatViewController.connection;
			}

			if (chatViewController == controller)
				return [NSIndexPath indexPathForRow:rowIndex inSection:sectionIndex];

			if (chatViewController.connection == connection && chatViewController != controller)
				++rowIndex;
		} else {
			if (currentController == controller)
				return [NSIndexPath indexPathForRow:rowIndex inSection:sectionIndex + 1];
			++rowIndex;
		}
	}

	return nil;
}

#pragma mark -

- (CQChatTableCell *) _chatTableCellForController:(id <CQChatViewController>) controller {
	NSIndexPath *indexPath = indexPathForChatController(controller);
	return (CQChatTableCell *)[self.tableView cellForRowAtIndexPath:indexPath];
}

#if ENABLE(FILE_TRANSFERS)
- (CQFileTransferTableCell *) _fileTransferCellForController:(CQFileTransferController *) controller {
	NSIndexPath *indexPath = indexPathForChatController(controller);
	return (CQFileTransferTableCell *)[self.tableView cellForRowAtIndexPath:indexPath];
}
#endif

- (void) _addMessagePreview:(NSDictionary *) info withEncoding:(NSStringEncoding) encoding toChatTableCell:(CQChatTableCell *) cell animated:(BOOL) animated {
	MVChatUser *user = [info objectForKey:@"user"];
	NSString *message = [info objectForKey:@"messagePlain"];
	BOOL action = [[info objectForKey:@"action"] boolValue];

	if (!message) {
		message = [info objectForKey:@"message"];
		message = [message stringByStrippingXMLTags];
		message = [message stringByDecodingXMLSpecialCharacterEntities];
	}

	if (!message || !user)
		return;

	[cell addMessagePreview:message fromUser:user asAction:action animated:animated];
}

- (void) _addedChatViewController:(NSNotification *) notification {
	id <CQChatViewController> controller = [notification.userInfo objectForKey:@"controller"];
	[self addChatViewController:controller];
}

- (void) _updateMessagePreview:(NSNotification *) notification {
	if (!_active) {
		_needsUpdate = YES;
		return;
	}

	CQDirectChatController *chatController = notification.object;
	CQChatTableCell *cell = [self _chatTableCellForController:chatController];

	cell.unreadCount = chatController.unreadCount;
	cell.importantUnreadCount = chatController.importantUnreadCount;

	[self _addMessagePreview:chatController.recentMessages.lastObject withEncoding:chatController.encoding toChatTableCell:cell animated:YES];
}

- (void) _refreshChatCell:(CQChatTableCell *) cell withController:(id <CQChatViewController>) chatViewController animated:(BOOL) animated {
	if (animated)
		[UIView beginAnimations:nil context:NULL];

	[cell takeValuesFromChatViewController:chatViewController];

	if ([chatViewController isMemberOfClass:[CQDirectChatController class]])
		cell.showsUserInMessagePreviews = NO;

	if (animated)
		[UIView commitAnimations];
}

#if ENABLE(FILE_TRANSFERS)
- (void) _refreshFileTransferCell:(CQFileTransferTableCell *) cell withController:(CQFileTransferController *) controller animated:(BOOL) animated {
	if (animated)
		[UIView beginAnimations:nil context:NULL];

	[cell takeValuesFromController:controller];

	if (animated)
		[UIView commitAnimations];
}
#endif

- (void) _refreshConnectionChatCells:(NSNotification *) notification {
	if (!_active) {
		_needsUpdate = YES;
		return;
	}

	MVChatConnection *connection = notification.object;
	NSUInteger sectionIndex = sectionIndexForConnection(connection);
	if (sectionIndex == NSNotFound)
		return;

	NSUInteger i = 0;
	for (id <CQChatViewController> controller in [[CQChatController defaultController] chatViewControllersForConnection:connection]) {
		NSIndexPath *indexPath = [NSIndexPath indexPathForRow:i++ inSection:sectionIndex];
		CQChatTableCell *cell = (CQChatTableCell *)[self.tableView cellForRowAtIndexPath:indexPath];
		[self _refreshChatCell:cell withController:controller animated:YES];
	}
}

- (void) _refreshChatCell:(NSNotification *) notification {
	if (!_active) {
		_needsUpdate = YES;
		return;
	}

	id target = notification.object;
	id <CQChatViewController> controller = nil;
	if ([target isKindOfClass:[MVChatRoom class]])
		controller = [[CQChatController defaultController] chatViewControllerForRoom:target ifExists:YES];
	else if ([target isKindOfClass:[MVChatUser class]])
		controller = [[CQChatController defaultController] chatViewControllerForUser:target ifExists:YES];

	if (!controller)
		return;

	CQChatTableCell *cell = [self _chatTableCellForController:controller];
	[self _refreshChatCell:cell withController:controller animated:YES];
}

#if ENABLE(FILE_TRANSFERS)
- (void) _refreshFileTransferCell:(NSNotification *) notification {
	if (!_active) {
		_needsUpdate = YES;
		return;
	}

	MVFileTransfer *transfer = notification.object;
	if (!transfer)
		return;

	CQFileTransferController *controller = [[CQChatController defaultController] chatViewControllerForFileTransfer:transfer ifExists:NO];
	CQFileTransferTableCell *cell = [self _fileTransferCellForController:controller];
	[self _refreshFileTransferCell:cell withController:controller animated:YES];
}
#endif

#pragma mark -

- (void) viewDidLoad {
	[super viewDidLoad];

	self.tableView.rowHeight = 62.;
}

- (void) viewWillAppear:(BOOL) animated {
	if (_needsUpdate) {
		[self.tableView reloadData];
		_needsUpdate = NO;
	}

	_active = YES;

	NSIndexPath *selectedIndexPath = [self.tableView indexPathForSelectedRow];
	if (selectedIndexPath) {
		MVChatConnection *connection = connectionForSection(selectedIndexPath.section);
		if (connection) {
			NSArray *controllers = [[CQChatController defaultController] chatViewControllersForConnection:connection];
			id <CQChatViewController> chatViewController = [controllers objectAtIndex:selectedIndexPath.row];
			CQChatTableCell *cell = (CQChatTableCell *)[self.tableView cellForRowAtIndexPath:selectedIndexPath];
			[self _refreshChatCell:cell withController:chatViewController animated:NO];
		}
	}

	[super viewWillAppear:animated];
}

- (void) viewDidDisappear:(BOOL) animated {
	[super viewDidDisappear:animated];

	_active = NO;
}

#pragma mark -

- (void) addChatViewController:(id) controller {
	if (!_active) {
		_needsUpdate = YES;
		return;
	}

	NSArray *controllers = nil;
	if ([controller conformsToProtocol:@protocol(CQChatViewController)])
		controllers = [[CQChatController defaultController] chatViewControllersForConnection:((id <CQChatViewController>)controller).connection];
#if ENABLE(FILE_TRANSFERS)
	else if ([controller isKindOfClass:[CQFileTransferController class]])
		controllers = [[CQChatController defaultController] chatViewControllersOfClass:[CQFileTransferController class]];
#endif
	else {
		NSAssert(NO, @"Should not reach this point.");
		return;
	}

	NSIndexPath *changedIndexPath = indexPathForChatController(controller);
	if (controllers.count == 1) {
		[self.tableView beginUpdates];
		if ([CQChatController defaultController].chatViewControllers.count == 1)
			[self.tableView deleteSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationFade];
		[self.tableView insertSections:[NSIndexSet indexSetWithIndex:changedIndexPath.section] withRowAnimation:UITableViewRowAnimationTop];
		[self.tableView endUpdates];
	} else {
		[self.tableView insertRowsAtIndexPaths:[NSArray arrayWithObject:changedIndexPath] withRowAnimation:UITableViewRowAnimationTop];
	}
}

- (void) selectChatViewController:(id) controller animatedSelection:(BOOL) animatedSelection animatedScroll:(BOOL) animatedScroll {
	if (!self.tableView.numberOfSections || _needsUpdate) {
		[self.tableView reloadData];
		_needsUpdate = NO;
	}

	NSIndexPath *indexPath = indexPathForChatController(controller);
	[self.tableView scrollToRowAtIndexPath:indexPath atScrollPosition:UITableViewScrollPositionNone animated:animatedScroll];
	[self.tableView selectRowAtIndexPath:indexPath animated:animatedSelection scrollPosition:UITableViewScrollPositionNone];
}

#pragma mark -

- (void) setEditing:(BOOL) editing animated:(BOOL) animated {
	[super setEditing:editing animated:animated];

	if (!editing)
		self.editButtonItem.title = NSLocalizedString(@"Manage", @"Manage button title");
}

#pragma mark -

- (void) actionSheet:(UIActionSheet *) actionSheet clickedButtonAtIndex:(NSInteger) buttonIndex {
	if (buttonIndex == actionSheet.cancelButtonIndex)
		return;

	NSInteger section = [[(CQActionSheet *) actionSheet userInfo] intValue];
	MVChatConnection *connection = connectionForSection(section);

	if (buttonIndex == 0) {
		if (connection.status == MVChatConnectionConnectingStatus || connection.status == MVChatConnectionConnectedStatus) {
			[connection disconnectWithReason:[MVChatConnection defaultQuitMessage]];
		} else {
			[connection cancelPendingReconnectAttempts];
			[connection connect];
		}
		return;
	}

	NSMutableArray *rowsToDelete = [[NSMutableArray alloc] init];
	NSMutableArray *viewsToClose = [[NSMutableArray alloc] init];
	Class classToClose = Nil;

	if (buttonIndex == 1 && [[CQChatController defaultController] connectionHasAChatRoom:connection])
		classToClose = [MVChatRoom class];
	else classToClose = [MVChatUser class];

	NSArray *viewControllers = [[CQChatController defaultController] chatViewControllersForConnection:connection];

	for (id <CQChatViewController> chatViewController in viewControllers) {
		if (![chatViewController.target isKindOfClass:classToClose])
			continue;

		NSIndexPath *indexPath = indexPathForChatController(chatViewController);
		if (!indexPath)
			continue;

		[rowsToDelete addObject:indexPath];
		[viewsToClose addObject:chatViewController];
	}

	for (id <CQChatViewController> chatViewController in viewsToClose)
		[[CQChatController defaultController] closeViewController:chatViewController];

	if (viewControllers.count == viewsToClose.count) {
		[self.tableView beginUpdates];
		[self.tableView deleteSections:[NSIndexSet indexSetWithIndex:section] withRowAnimation:UITableViewRowAnimationTop];
		if (![CQChatController defaultController].chatViewControllers.count)
			[self.tableView insertSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationFade];
		[self.tableView endUpdates];
	} else [self.tableView deleteRowsAtIndexPaths:rowsToDelete withRowAnimation:UITableViewRowAnimationTop];

	[rowsToDelete release];
	[viewsToClose release];
}

#pragma mark -

- (void) tableSectionHeaderSelected:(CQTableViewSectionHeader *) header {
	NSInteger section = header.section;

	MVChatConnection *connection = connectionForSection(section);
	if (!connection)
		return;

	CQActionSheet *sheet = [[CQActionSheet alloc] init];
	sheet.delegate = self;
	sheet.userInfo = [NSNumber numberWithInt:header.section];

	if (connection.status == MVChatConnectionConnectingStatus || connection.status == MVChatConnectionConnectedStatus)
		sheet.destructiveButtonIndex = [sheet addButtonWithTitle:NSLocalizedString(@"Disconnect", @"Disconnect button title")];
	else
		[sheet addButtonWithTitle:NSLocalizedString(@"Connect", @"Connect button title")];

	if ([[CQChatController defaultController] connectionHasAChatRoom:connectionForSection(section)])
		[sheet addButtonWithTitle:NSLocalizedString(@"Close All Chat Rooms", @"Close all rooms button title")];

	if ([[CQChatController defaultController] connectionHasAPrivateChat:connectionForSection(section)])	
		[sheet addButtonWithTitle:NSLocalizedString(@"Close All Private Chats", @"Close all private chats button title")];

	sheet.cancelButtonIndex = [sheet addButtonWithTitle:NSLocalizedString(@"Cancel", @"Cancel button title")];

	[[CQColloquyApplication sharedApplication] showActionSheet:sheet forSender:header animated:YES];

	[sheet release];
}

#pragma mark -

- (NSInteger) numberOfSectionsInTableView:(UITableView *) tableView {
	NSArray *controllers = [CQChatController defaultController].chatViewControllers;
	if (!controllers.count)
		return 1;

	MVChatConnection *currentConnection = nil;
	NSUInteger sectionCount = 0;

	for (id controller in controllers) {
		if (![controller conformsToProtocol:@protocol(CQChatViewController)])
			break;

		id <CQChatViewController> chatViewController = controller;
		if (chatViewController.connection != currentConnection) {
			++sectionCount;
			currentConnection = chatViewController.connection;
		}
	}

	return (sectionCount ? sectionCount : 1);
}

- (NSInteger) tableView:(UITableView *) tableView numberOfRowsInSection:(NSInteger) section {
	MVChatConnection *connection = connectionForSection(section);
	if (connection)
		return [[CQChatController defaultController] chatViewControllersForConnection:connection].count;
#if ENABLE(FILE_TRANSFERS)
	return [[CQChatController defaultController] chatViewControllersOfClass:[CQFileTransferController class]].count;
#else
	return 0;
#endif
}

- (NSString *) tableView:(UITableView *) tableView titleForHeaderInSection:(NSInteger) section {
	MVChatConnection *connection = connectionForSection(section);
	if (connection)
		return connection.displayName;

#if ENABLE(FILE_TRANSFERS)
	if ([[CQChatController defaultController] chatViewControllersKindOfClass:[CQFileTransferController class]].count)
		return NSLocalizedString(@"File Transfers", @"File Transfers section title");
#endif

	return nil;
}

- (UITableViewCell *) tableView:(UITableView *) tableView cellForRowAtIndexPath:(NSIndexPath *) indexPath {
	MVChatConnection *connection = connectionForSection(indexPath.section);
	if (connection) {
		NSArray *controllers = [[CQChatController defaultController] chatViewControllersForConnection:connection];
		id <CQChatViewController> chatViewController = [controllers objectAtIndex:indexPath.row];

		CQChatTableCell *cell = [CQChatTableCell reusableTableViewCellInTableView:tableView];

		cell.showsIcon = showsChatIcons;

		[self _refreshChatCell:cell withController:chatViewController animated:NO];

		if ([chatViewController isKindOfClass:[CQDirectChatController class]]) {
			CQDirectChatController *directChatViewController = (CQDirectChatController *)chatViewController;
			NSArray *recentMessages = directChatViewController.recentMessages;
			NSMutableArray *previewMessages = [[NSMutableArray alloc] initWithCapacity:2];

			for (NSInteger i = (recentMessages.count - 1); i >= 0 && previewMessages.count < 2; --i) {
				NSDictionary *message = [recentMessages objectAtIndex:i];
				MVChatUser *user = [message objectForKey:@"user"];
				if (!user.localUser) [previewMessages insertObject:message atIndex:0];
			}

			for (NSDictionary *message in previewMessages)
				[self _addMessagePreview:message withEncoding:directChatViewController.encoding toChatTableCell:cell animated:NO];

			[previewMessages release];
		}

		return cell;
	}

#if ENABLE(FILE_TRANSFERS)
	NSArray *controllers = [[CQChatController defaultController] chatViewControllersKindOfClass:[CQFileTransferController class]];
	CQFileTransferController *controller = [controllers objectAtIndex:indexPath.row];

	CQFileTransferTableCell *cell = (CQFileTransferTableCell *)[tableView dequeueReusableCellWithIdentifier:@"FileTransferTableCell"];
	if (!cell) {
		NSArray *array = [[NSBundle mainBundle] loadNibNamed:@"FileTransferTableCell" owner:self options:nil];
		for (id object in array) {
			if ([object isKindOfClass:[CQFileTransferTableCell class]]) {
				cell = object;
				break;
			}
		}
	}

	cell.showsIcon = showsChatIcons;

	[self _refreshFileTransferCell:cell withController:controller animated:NO];

	return cell;
#else
	return nil;
#endif
}

- (UITableViewCellEditingStyle) tableView:(UITableView *) tableView editingStyleForRowAtIndexPath:(NSIndexPath *) indexPath {
	return UITableViewCellEditingStyleDelete;
}

- (NSString *) tableView:(UITableView *) tableView titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *) indexPath {
	MVChatConnection *connection = connectionForSection(indexPath.section);
	if (connection) {
		NSArray *controllers = [[CQChatController defaultController] chatViewControllersForConnection:connection];
		id <CQChatViewController> chatViewController = [controllers objectAtIndex:indexPath.row];

		if ([chatViewController isMemberOfClass:[CQChatRoomController class]] && chatViewController.available)
			return NSLocalizedString(@"Leave", @"Leave remove confirmation button title");
		return NSLocalizedString(@"Close", @"Close remove confirmation button title");
	}

#if ENABLE(FILE_TRANSFERS)
	NSArray *controllers = [[CQChatController defaultController] chatViewControllersKindOfClass:[CQFileTransferController class]];
	CQFileTransferController *controller = [controllers objectAtIndex:indexPath.row];

	MVFileTransferStatus status = controller.transfer.status;
	if (status == MVFileTransferDoneStatus || status == MVFileTransferStoppedStatus)
		return NSLocalizedString(@"Close", @"Close remove confirmation button title");
	return NSLocalizedString(@"Stop", @"Stop remove confirmation button title");
#else
	return nil;
#endif
}

- (void) tableView:(UITableView *) tableView commitEditingStyle:(UITableViewCellEditingStyle) editingStyle forRowAtIndexPath:(NSIndexPath *) indexPath {
	if (editingStyle != UITableViewCellEditingStyleDelete)
		return;

	MVChatConnection *connection = connectionForSection(indexPath.section);
	NSArray *controllers = nil;
	id controller = nil;

	if (connection) {
		controllers = [[CQChatController defaultController] chatViewControllersForConnection:connection];
		id <CQChatViewController> chatViewController = [controllers objectAtIndex:indexPath.row];
		controller = chatViewController;

		if ([chatViewController isMemberOfClass:[CQChatRoomController class]]) {
			CQChatRoomController *chatRoomController = (CQChatRoomController *)chatViewController;
			if (chatRoomController.available) {
				[chatRoomController part];
				[self.tableView updateCellAtIndexPath:indexPath withAnimation:UITableViewRowAnimationFade];
				return;
			}
		}
#if ENABLE(FILE_TRANSFERS)
	} else {
		controllers = [[CQChatController defaultController] chatViewControllersKindOfClass:[CQFileTransferController class]];
		CQFileTransferController *fileTransferController = [controllers objectAtIndex:indexPath.row];
		controller = fileTransferController;

		if (fileTransferController.transfer.status != MVFileTransferDoneStatus && fileTransferController.transfer.status != MVFileTransferStoppedStatus) {
			[fileTransferController.transfer cancel];
			[self.tableView updateCellAtIndexPath:indexPath withAnimation:UITableViewRowAnimationFade];
			return;
		}
#endif
	}

	[[CQChatController defaultController] closeViewController:controller];

	if (controllers.count == 1) {
		[self.tableView beginUpdates];
		[self.tableView deleteSections:[NSIndexSet indexSetWithIndex:indexPath.section] withRowAnimation:UITableViewRowAnimationRight];
		if (![CQChatController defaultController].chatViewControllers.count)
			[self.tableView insertSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationFade];
		[self.tableView endUpdates];
	} else {
		[self.tableView deleteRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationRight];
	}
}

- (CGFloat) tableView:(UITableView *) tableView heightForHeaderInSection:(NSInteger) section {
	return 22.;
}

- (UIView *) tableView:(UITableView *) tableView viewForHeaderInSection:(NSInteger) section {
	if (![CQChatController defaultController].chatViewControllers.count)
		return nil;

	CQTableViewSectionHeader *view = [[CQTableViewSectionHeader alloc] initWithFrame:CGRectZero];
	view.textLabel.text = [self tableView:tableView titleForHeaderInSection:section];
	view.section = section;
	view.disclosureImageView.hidden = YES;

	[view addTarget:self action:@selector(tableSectionHeaderSelected:) forControlEvents:UIControlEventTouchUpInside];

	return [view autorelease];
}

- (void) tableView:(UITableView *) tableView didSelectRowAtIndexPath:(NSIndexPath *) indexPath {
	MVChatConnection *connection = connectionForSection(indexPath.section);
	if (!connection)
		return;

	NSArray *controllers = [[CQChatController defaultController] chatViewControllersForConnection:connection];
	id <CQChatViewController> chatViewController = [controllers objectAtIndex:indexPath.row];

	[[CQChatController defaultController] showChatController:chatViewController animated:YES];
}

- (BOOL) tableView:(UITableView *) tableView shouldShowMenuForRowAtIndexPath:(NSIndexPath *) indexPath {
	return YES;
}

- (BOOL) tableView:(UITableView *) tableView canPerformAction:(SEL) action forRowAtIndexPath:(NSIndexPath *) indexPath withSender:(id) sender {
	if (action == @selector(copy:))
		return YES;

	if (action == @selector(join:) || action == @selector(leave:)) {
		MVChatConnection *connection = connectionForSection(indexPath.section);
		if (!connection)
			return NO;

		NSArray *controllers = [[CQChatController defaultController] chatViewControllersForConnection:connection];
		id <CQChatViewController> chatViewController = [controllers objectAtIndex:indexPath.row];
		if (![chatViewController isMemberOfClass:[CQChatRoomController class]])
			return NO;

		CQChatRoomController *chatRoomViewController = (CQChatRoomController *)chatViewController;

		if (action == @selector(join:) && chatRoomViewController.room.joined)
			return NO;

		if (action == @selector(leave:) && !chatRoomViewController.room.joined)
			return NO;

		return YES;
	}

	return NO;
}

- (void) tableView:(UITableView *) tableView performAction:(SEL) action forRowAtIndexPath:(NSIndexPath *) indexPath withSender:(id) sender {
	MVChatConnection *connection = connectionForSection(indexPath.section);
	if (!connection)
		return;

	NSArray *controllers = [[CQChatController defaultController] chatViewControllersForConnection:connection];
	id <CQChatViewController> chatViewController = [controllers objectAtIndex:indexPath.row];

	if ([chatViewController isMemberOfClass:[CQDirectChatController class]]) {
		CQDirectChatController *directChatViewController = (CQDirectChatController *)chatViewController;
		if (action == @selector(copy:))
			[UIPasteboard generalPasteboard].string = directChatViewController.user.nickname;
	} else if ([chatViewController isMemberOfClass:[CQChatRoomController class]]) {
		CQChatRoomController *chatRoomViewController = (CQChatRoomController *)chatViewController;
		if (action == @selector(copy:))
			[UIPasteboard generalPasteboard].string = chatRoomViewController.room.name;
		else if (action == @selector(join:))
			[chatRoomViewController join];
		else if (action == @selector(leave:))
			[chatRoomViewController part];
	}
}
@end
