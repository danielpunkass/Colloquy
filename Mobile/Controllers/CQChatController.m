#import "CQChatController.h"

#import "CQChatRoomController.h"
#import "CQChatListViewController.h"
#import "CQConnectionsController.h"
#import "CQDirectChatController.h"

#import <ChatCore/MVChatConnection.h>
#import <ChatCore/MVChatRoom.h>
#import <ChatCore/MVChatUser.h>
#import <ChatCore/MVDirectChatConnection.h>

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

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_joinedRoom:) name:MVChatRoomJoinedNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_gotRoomMessage:) name:MVChatRoomGotMessageNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_gotPrivateMessage:) name:MVChatConnectionGotPrivateMessageNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_gotDirectChatMessage:) name:MVDirectChatConnectionGotMessageNotification object:nil];

	return self;
}

- (void) dealloc {
	[_chatListViewController release];
	[_chatControllers release];
	[super dealloc];
}

#pragma mark -

- (void) viewDidLoad {
	[super viewDidLoad];

	if (!_chatListViewController)
		_chatListViewController = [[CQChatListViewController alloc] init];
	[self pushViewController:_chatListViewController animated:NO];
}

#pragma mark -

static NSComparisonResult sortByConnectionAscending(CQDirectChatController *chatController1, CQDirectChatController *chatController2, void *context) {
	return [chatController1.connection.displayName caseInsensitiveCompare:chatController2.connection.displayName];
}

#pragma mark -

- (void) _sortChatControllers {
	[_chatControllers sortUsingFunction:sortByConnectionAscending context:NULL];
}

- (void) _joinedRoom:(NSNotification *) notification {
	MVChatRoom *room = notification.object;
	if (![[CQConnectionsController defaultController] managesConnection:room.connection])
		return;

	CQChatRoomController *roomController = [self chatViewControllerForRoom:room ifExists:NO];
	[roomController joined];
}

- (void) _gotRoomMessage:(NSNotification *) notification {
	// we do this here to make sure we catch early messages right when we join (this includes dircproxy's dump)
	MVChatRoom *room = notification.object;
	CQChatRoomController *controller = [self chatViewControllerForRoom:room ifExists:NO];

	MVChatUser *user = [notification.userInfo objectForKey:@"user"];
	NSData *message = [notification.userInfo objectForKey:@"message"];
	CQChatMessageType type = ([[notification.userInfo objectForKey:@"notice"] boolValue] ? CQChatMessageNoticeType : CQChatMessageNormalType);
	[controller addMessageToDisplay:message fromUser:user withAttributes:notification.userInfo withIdentifier:[notification.userInfo objectForKey:@"identifier"] andType:type];
}

- (void) _gotPrivateMessage:(NSNotification *) notification {
	MVChatUser *user = notification.object;
	if (![[CQConnectionsController defaultController] managesConnection:user.connection])
		return;

	BOOL hideFromUser = NO;

	if ([[notification.userInfo objectForKey:@"notice"] boolValue]) {
		if (![self chatViewControllerForUser:user ifExists:YES])
			hideFromUser = YES;

		if ([[NSUserDefaults standardUserDefaults] boolForKey:@"CQChatAlwaysShowNotices"])
			hideFromUser = NO;
	}

	if (!hideFromUser) {
		CQDirectChatController *controller = [self chatViewControllerForUser:user ifExists:NO userInitiated:NO];
		NSData *message = [notification.userInfo objectForKey:@"message"];
		CQChatMessageType type = ([[notification.userInfo objectForKey:@"notice"] boolValue] ? CQChatMessageNoticeType : CQChatMessageNormalType);
		[controller addMessageToDisplay:message fromUser:user withAttributes:notification.userInfo withIdentifier:[notification.userInfo objectForKey:@"identifier"] andType:type];
	}
}

- (void) _gotDirectChatMessage:(NSNotification *) notification {
	MVDirectChatConnection *connection = notification.object;
	MVChatUser *user = connection.user;
	if (![[CQConnectionsController defaultController] managesConnection:user.connection])
		return;

	NSData *message = [notification.userInfo objectForKey:@"message"];

	CQDirectChatController *controller = [self chatViewControllerForDirectChatConnection:connection ifExists:NO];
	[controller addMessageToDisplay:message fromUser:user withAttributes:notification.userInfo withIdentifier:[notification.userInfo objectForKey:@"identifier"] andType:CQChatMessageNormalType];
}

#pragma mark -

@synthesize chatViewControllers = _chatControllers;

- (NSArray *) chatViewControllersForConnection:(MVChatConnection *) connection {
	NSParameterAssert(connection != nil);

	NSMutableArray *result = [NSMutableArray array];

	for (id <CQChatViewController> controller in _chatControllers)
		if (controller.connection == connection)
			[result addObject:controller];

	return result;
}

- (NSArray *) chatViewControllersOfClass:(Class) class {
	NSParameterAssert(class != NULL);

	NSMutableArray *result = [NSMutableArray array];

	for (id <CQChatViewController> controller in _chatControllers)
		if ([controller isMemberOfClass:class])
			[result addObject:controller];

	return result;
}

- (NSArray *) chatViewControllersKindOfClass:(Class) class {
	NSParameterAssert(class != NULL);

	NSMutableArray *result = [NSMutableArray array];

	for (id <CQChatViewController> controller in _chatControllers)
		if ([controller isKindOfClass:class])
			[result addObject:controller];

	return result;
}

#pragma mark -

- (CQChatRoomController *) chatViewControllerForRoom:(MVChatRoom *) room ifExists:(BOOL) exists {
	NSParameterAssert(room != nil);

	for (id <CQChatViewController> controller in _chatControllers)
		if ([controller isMemberOfClass:[CQChatRoomController class]] && [controller.target isEqual:room])
			return (CQChatRoomController *)controller;

	CQChatRoomController *controller = nil;

	if (!exists) {
		if ((controller = [[CQChatRoomController alloc] initWithTarget:room])) {
			[_chatControllers addObject:controller];
			[controller release];

			[self _sortChatControllers];
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
		if ([controller isMemberOfClass:[CQDirectChatController class]] && [controller.target isEqual:user])
			return (CQDirectChatController *)controller;

	CQDirectChatController *controller = nil;

	if (!exists) {
		if ((controller = [[CQDirectChatController alloc] initWithTarget:user])) {
			[_chatControllers addObject:controller];
			[controller release];

			[self _sortChatControllers];
			return controller;
		}
	}

	return nil;
}

- (CQDirectChatController *) chatViewControllerForDirectChatConnection:(MVDirectChatConnection *) connection ifExists:(BOOL) exists {
	NSParameterAssert(connection != nil);

	for (id <CQChatViewController> controller in _chatControllers)
		if ([controller isMemberOfClass:[CQDirectChatController class]] && [controller.target isEqual:connection])
			break;

	CQDirectChatController *controller = nil;

	if (!exists) {
		if ((controller = [[CQDirectChatController alloc] initWithTarget:connection])) {
			[_chatControllers addObject:controller];
			[controller release];

			[self _sortChatControllers];
			return controller;
		}
	}

	return nil;
}

#pragma mark -

- (void) closeViewController:(id <CQChatViewController>) controller {
	if ([controller respondsToSelector:@selector(close)])
		[controller close];
	[_chatControllers removeObjectIdenticalTo:controller];
}
@end
