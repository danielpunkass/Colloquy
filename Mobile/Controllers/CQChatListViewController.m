#import "CQChatListViewController.h"

#import "CQChatRoomController.h"
#import "CQChatTableCell.h"
#import "CQConnectionsController.h"
#import "CQDirectChatController.h"
#import "NSStringAdditions.h"

#import <ChatCore/MVChatConnection.h>
#import <ChatCore/MVChatRoom.h>
#import <ChatCore/MVChatUser.h>

@implementation CQChatListViewController
- (id) init {
	if (!(self = [super initWithStyle:UITableViewStylePlain]))
		return nil;

	self.title = NSLocalizedString(@"Colloquies", @"Colloquies view title");

	UIBarButtonItem *addItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:[CQChatController defaultController] action:@selector(showNewChatActionSheet)];
	self.navigationItem.leftBarButtonItem = addItem;
	[addItem release];

	self.navigationItem.rightBarButtonItem = self.editButtonItem;

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_refreshConnectionChatCells:) name:MVChatConnectionDidConnectNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_refreshConnectionChatCells:) name:MVChatConnectionDidDisconnectNotification object:nil];

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_refreshChatCell:) name:MVChatRoomJoinedNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_refreshChatCell:) name:MVChatRoomPartedNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_refreshChatCell:) name:MVChatRoomKickedNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_refreshChatCell:) name:MVChatUserNicknameChangedNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_refreshChatCell:) name:MVChatUserStatusChangedNotification object:nil];

	return self;
}

- (void) dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];

	[super dealloc];
}

#pragma mark -

static MVChatConnection *connectionForSection(NSInteger section) {
	NSMutableSet *connections = [NSMutableSet set];

	for (CQDirectChatController *controller in [CQChatController defaultController].chatViewControllers) {
		if (controller.connection) {
			[connections addObject:controller.connection];
			if ((section + 1) == connections.count)
				return controller.connection;
		}
	}

	return nil;
}

static NSUInteger sectionIndexForConnection(MVChatConnection *connection) {
	NSArray *controllers = [CQChatController defaultController].chatViewControllers;
	if (!controllers.count)
		return NSNotFound;

	MVChatConnection *currentConnection = nil;
	NSUInteger sectionIndex = 0;

	for (CQDirectChatController *currentController in controllers) {
		if (currentController.connection != currentConnection) {
			if (currentConnection) ++sectionIndex;
			currentConnection = currentController.connection;
		}

		if (currentController.connection == connection)
			return sectionIndex;
	}

	return NSNotFound;
}

static NSIndexPath *indexPathForChatController(id <CQChatViewController> controller) {
	NSArray *controllers = [CQChatController defaultController].chatViewControllers;
	if (!controllers.count)
		return nil;

	MVChatConnection *connection = controller.connection;
	MVChatConnection *currentConnection = nil;
	NSUInteger sectionIndex = 0;
	NSUInteger rowIndex = 0;

	for (CQDirectChatController *currentController in controllers) {
		if (currentController.connection != currentConnection) {
			if (currentConnection) ++sectionIndex;
			currentConnection = currentController.connection;
		}

		if (currentController == controller)
			return [NSIndexPath indexPathForRow:rowIndex inSection:sectionIndex];

		if (currentController.connection == connection && currentController != controller)
			++rowIndex;
	}

	return nil;
}

#pragma mark -

- (void) viewDidLoad {
	[super viewDidLoad];

	self.tableView.rowHeight = 72.;
}

- (void) viewWillAppear:(BOOL) animated {
	NSIndexPath *selectedIndexPath = [self.tableView indexPathForSelectedRow];
	if (selectedIndexPath) {
		MVChatConnection *connection = connectionForSection(selectedIndexPath.section);
		NSArray *controllers = [[CQChatController defaultController] chatViewControllersForConnection:connection];
		id <CQChatViewController> chatViewController = [controllers objectAtIndex:selectedIndexPath.row];
		CQChatTableCell *cell = (CQChatTableCell *)[self.tableView cellForRowAtIndexPath:selectedIndexPath];
		[cell takeValuesFromChatViewController:chatViewController];
	}

	[super viewWillAppear:animated];

	self.navigationItem.leftBarButtonItem.enabled = ([CQConnectionsController defaultController].connections.count ? YES : NO);
}

#pragma mark -

- (CQChatTableCell *) _chatTableCellForController:(id <CQChatViewController>) controller {
	NSIndexPath *indexPath = indexPathForChatController(controller);
	return (CQChatTableCell *)[self.tableView cellForRowAtIndexPath:indexPath];
}

- (void) _addMessagePreview:(NSDictionary *) info withEncoding:(NSStringEncoding) encoding toChatTableCell:(CQChatTableCell *) cell animated:(BOOL) animated {
	MVChatUser *user = [info objectForKey:@"user"];
	NSData *message = [info objectForKey:@"message"];
	NSString *messageString = [[NSString alloc] initWithChatData:message encoding:encoding];

	NSString *transformedMessageString = [messageString stringByStrippingXMLTags];
	transformedMessageString = [transformedMessageString stringByDecodingXMLSpecialCharacterEntities];
	transformedMessageString = [transformedMessageString stringBySubstitutingEmoticonsForEmoji];

	BOOL action = [[info objectForKey:@"action"] boolValue];

	[cell addMessagePreview:transformedMessageString fromUser:user asAction:action animated:animated];

	[messageString release];
}

- (void) _refreshConnectionChatCells:(NSNotification *) notification {
	MVChatConnection *connection = notification.object;
	NSUInteger sectionIndex = sectionIndexForConnection(connection);
	if (sectionIndex == NSNotFound)
		return;

	NSUInteger i = 0;
	for (id <CQChatViewController> controller in [[CQChatController defaultController] chatViewControllersForConnection:connection]) {
		NSIndexPath *indexPath = [NSIndexPath indexPathForRow:i++ inSection:sectionIndex];
		CQChatTableCell *cell = (CQChatTableCell *)[self.tableView cellForRowAtIndexPath:indexPath];
		[cell takeValuesFromChatViewController:controller];
	}
}

- (void) _refreshChatCell:(NSNotification *) notification {
	id target = notification.object;
	id <CQChatViewController> controller = nil;
	if ([target isKindOfClass:[MVChatRoom class]])
		controller = [[CQChatController defaultController] chatViewControllerForRoom:target ifExists:YES];
	else if ([target isKindOfClass:[MVChatUser class]])
		controller = [[CQChatController defaultController] chatViewControllerForUser:target ifExists:YES];

	if (!controller)
		return;

	CQChatTableCell *cell = [self _chatTableCellForController:controller];
	[cell takeValuesFromChatViewController:controller];
}

#pragma mark -

- (void) addChatViewController:(id <CQChatViewController>) controller {
	if ([[CQChatController defaultController] chatViewControllersForConnection:controller.connection].count == 1) {
		NSUInteger sectionIndex = sectionIndexForConnection(controller.connection);
		[self.tableView beginUpdates];
		if ([CQChatController defaultController].chatViewControllers.count == 1)
			[self.tableView deleteSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationFade];
		[self.tableView insertSections:[NSIndexSet indexSetWithIndex:sectionIndex] withRowAnimation:UITableViewRowAnimationTop];
		[self.tableView endUpdates];
	} else {
		NSIndexPath *changedIndexPath = indexPathForChatController(controller);
		[self.tableView insertRowsAtIndexPaths:[NSArray arrayWithObject:changedIndexPath] withRowAnimation:UITableViewRowAnimationTop];
	}
}

- (void) selectChatViewController:(id <CQChatViewController>) controller animatedSelection:(BOOL) animatedSelection animatedScroll:(BOOL) animatedScroll {
	NSIndexPath *indexPath = indexPathForChatController(controller);
	[self.tableView scrollToRowAtIndexPath:indexPath atScrollPosition:UITableViewScrollPositionNone animated:animatedScroll];
	[self.tableView selectRowAtIndexPath:indexPath animated:animatedSelection scrollPosition:UITableViewScrollPositionNone];
}

- (void) addMessagePreview:(NSDictionary *) info forChatController:(id <CQChatViewController>) controller {
	CQChatTableCell *cell = [self _chatTableCellForController:controller];

	if ([controller respondsToSelector:@selector(unreadCount)])
		cell.unreadCount = controller.unreadCount;

	if ([controller respondsToSelector:@selector(importantUnreadCount)])
		cell.importantUnreadCount = controller.importantUnreadCount;

	if (cell.importantUnreadCount == cell.unreadCount)
		cell.unreadCount = 0;

	[self _addMessagePreview:info withEncoding:controller.encoding toChatTableCell:cell animated:YES];
}

#pragma mark -

- (NSInteger) numberOfSectionsInTableView:(UITableView *)tableView {
	NSMutableSet *connections = [NSMutableSet set];

	for (CQDirectChatController *controller in [CQChatController defaultController].chatViewControllers)
		if (controller.connection)
			[connections addObject:controller.connection];

	return connections.count ? connections.count : 1;
}

- (NSInteger) tableView:(UITableView *) tableView numberOfRowsInSection:(NSInteger) section {
	MVChatConnection *connection = connectionForSection(section);
	if (connection)
		return [[CQChatController defaultController] chatViewControllersForConnection:connection].count;
	return 0;
}

- (NSString *) tableView:(UITableView *) tableView titleForHeaderInSection:(NSInteger) section {
	return connectionForSection(section).displayName;
}

- (UITableViewCell *) tableView:(UITableView *) tableView cellForRowAtIndexPath:(NSIndexPath *) indexPath {
	MVChatConnection *connection = connectionForSection(indexPath.section);
	NSArray *controllers = [[CQChatController defaultController] chatViewControllersForConnection:connection];
	id <CQChatViewController> chatViewController = [controllers objectAtIndex:indexPath.row];

	CQChatTableCell *cell = [CQChatTableCell reusableTableViewCellInTableView:tableView];

	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

	if ([chatViewController isMemberOfClass:[CQChatRoomController class]]) {
		cell.removeConfirmationText = NSLocalizedString(@"Leave", @"Leave remove confirmation button title");
	} else if ([chatViewController isMemberOfClass:[CQDirectChatController class]]) {
		cell.removeConfirmationText = NSLocalizedString(@"Close", @"Close remove confirmation button title");
		cell.showsUserInMessagePreviews = NO;
	}

	if ([chatViewController isKindOfClass:[CQDirectChatController class]]) {
		CQDirectChatController *directChatViewController = (CQDirectChatController *)chatViewController;
		NSArray *recentMessages = directChatViewController.recentMessages;
		NSUInteger maximum = MIN(cell.maximumMessagePreviews, recentMessages.count);
		for (NSUInteger i = (recentMessages.count - maximum); i < recentMessages.count; ++i) {
			NSDictionary *info = [recentMessages objectAtIndex:i];
			[self _addMessagePreview:info withEncoding:directChatViewController.encoding toChatTableCell:cell animated:NO];
		}
	}

	[cell takeValuesFromChatViewController:chatViewController];

	return cell;
}

- (UITableViewCellEditingStyle) tableView:(UITableView *) tableView editingStyleForRowAtIndexPath:(NSIndexPath *) indexPath {
	return UITableViewCellEditingStyleDelete;
}

- (void) tableView:(UITableView *) tableView commitEditingStyle:(UITableViewCellEditingStyle) editingStyle forRowAtIndexPath:(NSIndexPath *) indexPath {
	if (editingStyle != UITableViewCellEditingStyleDelete)
		return;

	MVChatConnection *connection = connectionForSection(indexPath.section);
	NSArray *controllers = [[CQChatController defaultController] chatViewControllersForConnection:connection];
	id <CQChatViewController> chatViewController = [controllers objectAtIndex:indexPath.row];

	[[CQChatController defaultController] closeViewController:chatViewController];

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

- (void) tableView:(UITableView *) tableView didSelectRowAtIndexPath:(NSIndexPath *) indexPath {
	MVChatConnection *connection = connectionForSection(indexPath.section);
	NSArray *controllers = [[CQChatController defaultController] chatViewControllersForConnection:connection];
	id <CQChatViewController> chatViewController = [controllers objectAtIndex:indexPath.row];

	[[CQChatController defaultController] showChatController:chatViewController animated:YES];
}
@end
