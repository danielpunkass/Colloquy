#import "CQActivityWindowController.h"

#import "MVConnectionsController.h"
 
#import "CQGroupCell.h"

#define CQFileTransferInactiveWaitLimit 300 // in seconds
#define CQExpandCollapseRowInterval .5

NSString *CQActivityTypeFileTransfer = @"CQActivityTypeFileTransfer";
NSString *CQActivityTypeChatInvite = @"CQActivityTypeChatInvite";
NSString *CQActivityTypeDirectChatInvite = @"CQActivityTypeDirectChatInvite";

NSString *CQActivityStatusInvalid = @"CQActivityStatusInvalid";
NSString *CQActivityStatusPending = @"CQActivityStatusPending";
NSString *CQActivityStatusComplete = @"CQActivityStatusComplete";
NSString *CQActivityStatusAccepted = @"CQActivityStatusAccepted";
NSString *CQActivityStatusRejected = @"CQActivityStatusRejected";


NSString *CQDirectChatConnectionKey = @"CQDirectChatConnectionKey";

@interface CQActivityWindowController (Private)
- (NSUInteger) _fileTransferCountForConnection:(MVChatConnection *) connection;
- (NSUInteger) _directChatConnectionCount;
- (NSUInteger) _invitationCountForConnection:(MVChatConnection *) connection;

- (BOOL) _isHeaderItem:(id) item;
- (BOOL) _shouldExpandOrCollapse;

- (void) _appendActivity:(id) activity forConnection:(id) connection;
@end

#pragma mark -

@implementation CQActivityWindowController
+ (CQActivityWindowController *) sharedController {
	static CQActivityWindowController *sharedActivityWindowController = nil;
	static BOOL creatingSharedInstance = NO;
	if (sharedActivityWindowController)
		return sharedActivityWindowController;

	creatingSharedInstance = YES;
	sharedActivityWindowController = [[CQActivityWindowController alloc] init];

	return sharedActivityWindowController;
}

- (id) init {
	if (!(self = [super initWithWindowNibName:@"CQActivityWindow"]))
		return nil;

	_activity = [[NSMapTable alloc] initWithKeyOptions:NSMapTableZeroingWeakMemory valueOptions:NSMapTableStrongMemory capacity:[[MVConnectionsController defaultController] connections].count];
	[_activity setObject:[NSMutableArray array] forKey:CQDirectChatConnectionKey];

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(chatRoomInvitationAccepted:) name:MVChatRoomJoinedNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(chatRoomInvitationReceived:) name:MVChatRoomInvitedNotification object:nil];

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(directChatDidConnect:) name:MVDirectChatConnectionErrorDomain object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(directChatErrorOccurred:) name:MVDirectChatConnectionDidConnectNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(directChatOfferReceived:) name:MVDirectChatConnectionOfferNotification object:nil];

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(fileTransferWasOffered:) name:MVDownloadFileTransferOfferNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(fileTransferDidStart:) name:MVFileTransferStartedNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(fileTransferDidFinish:) name:MVFileTransferFinishedNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(fileTransferErrorReceived:) name:MVFileTransferErrorOccurredNotification object:nil];

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(connectionDidConnect:) name:MVChatConnectionDidConnectNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(connectionDidDisconnect:) name:MVChatConnectionDidDisconnectNotification object:nil];

	return self;
}

- (void) dealloc {
	[_activity release];

	[super dealloc];
}

#pragma mark -

- (IBAction) showActivityWindow:(id) sender {
	[self.window makeKeyAndOrderFront:nil];
}

- (IBAction) hideActivityWindow:(id) sender {
	[self.window orderOut:nil];
}

- (void) orderFrontIfNecessary {
	if (![self.window isVisible])
		[self.window makeKeyAndOrderFront:nil];
}

#pragma mark -

- (void) connectionDidConnect:(NSNotification *) notification {
	MVChatConnection *connection = notification.object;

	[_activity setObject:[NSMutableArray array] forKey:connection];
}

- (void) connectionDidDisconnect:(NSNotification *) notification {
	MVChatConnection *connection = notification.object;

	for (NSMutableDictionary *dictionary in [_activity objectForKey:connection]) {
		if (![dictionary objectForKey:@"status"])
			[dictionary setObject:CQActivityStatusInvalid forKey:@"status"];
	}

	[_outlineView reloadData];
}

#pragma mark -

- (void) chatRoomInvitationAccepted:(NSNotification *) notification {
	MVChatRoom *room = notification.object;

	for (NSMutableDictionary *dictionary in [_activity objectForKey:room.connection]) {
		if ([dictionary objectForKey:@"type"] != CQActivityTypeChatInvite)
			continue;

		MVChatRoom *activityRoom = [dictionary objectForKey:@"room"];
		if (![room isEqualToChatRoom:activityRoom]) // can we just use == here?
			continue;

		[dictionary setObject:CQActivityStatusAccepted forKey:@"status"];

		[_outlineView reloadData];

		break;
	}
}

- (void) chatRoomInvitationReceived:(NSNotification *) notification {
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"JVAutoJoinChatRoomOnInvite"])
		return;

	NSString *name = [notification.userInfo objectForKey:@"room"];
	MVChatConnection *connection = notification.object;
	for (NSDictionary *dictionary in [_activity objectForKey:connection]) { // if we already have an invite and its pending, ignore it
		if ([[dictionary objectForKey:@"room"] isCaseInsensitiveEqualToString:name]) {
			if ([dictionary objectForKey:@"status"] == CQActivityStatusPending)
				return;
		}
	}

	NSMutableDictionary *chatRoomInfo = [notification.userInfo mutableCopy];
	[chatRoomInfo setObject:CQActivityTypeChatInvite forKey:@"type"];
	[chatRoomInfo setObject:CQActivityStatusPending forKey:@"status"];
	[self _appendActivity:chatRoomInfo forConnection:connection];
	[chatRoomInfo release];

	[_outlineView reloadData];

	[self orderFrontIfNecessary];
}

#pragma mark -

- (void) directChatDidConnect:(NSNotification *) notification {
	MVDirectChatConnection *connection = notification.object;

	for (NSMutableDictionary *dictionary in [_activity objectForKey:CQDirectChatConnectionKey]) {
		// find the connection
		[dictionary setObject:CQActivityStatusAccepted forKey:@"status"];
	}
}

- (void) directChatErrorOccurred:(NSNotification *) notification {
	MVDirectChatConnection *connection = notification.object;
	for (NSMutableDictionary *dictionary in [_activity objectForKey:CQDirectChatConnectionKey]) {
		// find the connection
		[dictionary setObject:CQActivityStatusInvalid forKey:@"status"];
	}
}

- (void) directChatOfferReceived:(NSNotification *) notification {
	MVDirectChatConnection *connection = notification.object;

	NSMutableDictionary *chatRoomInfo = [notification.userInfo mutableCopy];
	[chatRoomInfo setObject:CQActivityTypeDirectChatInvite forKey:@"type"];
	[chatRoomInfo setObject:CQActivityStatusPending forKey:@"status"];
	[self _appendActivity:chatRoomInfo forConnection:connection];
	[chatRoomInfo release];

	[_outlineView reloadData];

	[self orderFrontIfNecessary];
}

#pragma mark -

- (void) fileTransferWasOffered:(NSNotification *) notification {
	MVFileTransfer *transfer = notification.object;

	NSMutableDictionary *fileTransferInfo = [[NSMutableDictionary dictionaryWithObjectsAndKeys:CQActivityTypeFileTransfer, @"type", transfer, @"transfer", nil] mutableCopy];
	[fileTransferInfo setObject:CQActivityTypeFileTransfer forKey:@"type"];
	[fileTransferInfo setObject:CQActivityStatusPending forKey:@"status"];
	[self _appendActivity:fileTransferInfo forConnection:transfer.user.connection];
	[fileTransferInfo release];

	[self performSelector:@selector(_invalidateItemForFileTransfer:) withObject:transfer afterDelay:CQFileTransferInactiveWaitLimit];

	[_outlineView reloadData];

	[self orderFrontIfNecessary];
}

- (void) fileTransferDidStart:(NSNotification *) notification {
	MVFileTransfer *transfer = notification.object;

	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(invalidateFileTransfer:) object:transfer];

	for (NSMutableDictionary *dictionary in [_activity objectForKey:transfer.user.connection]) {
		if ([dictionary objectForKey:@"transfer"] != transfer)
			continue;

		[dictionary setObject:CQActivityStatusAccepted forKey:@"status"];

		// start tracking progress
	}

	[self orderFrontIfNecessary];
}

- (void) fileTransferDidFinish:(NSNotification *) notification {
	MVFileTransfer *transfer = notification.object;
	for (NSMutableDictionary *dictionary in [_activity objectForKey:transfer.user.connection]) {
		if ([dictionary objectForKey:@"transfer"] != transfer)
			continue;

		[dictionary setObject:CQActivityStatusComplete forKey:@"status"];
	}
	
	[self orderFrontIfNecessary];
}

- (void) fileTransferErrorReceived:(NSNotification *) notification {
	MVFileTransfer *transfer = notification.object;
	for (NSMutableDictionary *dictionary in [_activity objectForKey:transfer.user.connection]) {
		if ([dictionary objectForKey:@"transfer"] != transfer)
			continue;

		[dictionary setObject:CQActivityStatusInvalid forKey:@"status"];
	}

	[self orderFrontIfNecessary];
}

#pragma mark -

- (id) outlineView:(NSOutlineView *) outlineView child:(NSInteger) childAtIndex ofItem:(id) item {
	if (!item) {
		NSInteger count = 0;
		for (id key in _activity) {
			NSArray *activity = [_activity objectForKey:key];
			if (!activity.count)
				continue;
			if (childAtIndex == count) {
				return key;
			}
			count++;
		}
	}

	return [[_activity objectForKey:item] objectAtIndex:childAtIndex];
}

- (BOOL) outlineView:(NSOutlineView *) outlineView isItemExpandable:(id) item {
	return [self _isHeaderItem:item]; // top level, shows the connection name
}

- (NSInteger) outlineView:(NSOutlineView *) outlineView numberOfChildrenOfItem:(id) item {
	if (!item) {
		NSUInteger count = 0;
		for (id key in _activity) {
			NSArray *activity = [_activity objectForKey:key];
			if (activity.count)
				count++;
		}
		return count;
	}

	return ((NSArray *)[_activity objectForKey:item]).count;
}

- (id) outlineView:(NSOutlineView *) outlineView objectValueForTableColumn:(NSTableColumn *) tableColumn byItem:(id) item {
	if ([item isKindOfClass:[MVChatConnection class]])
		return ((MVChatConnection *)item).server;
	if (item == CQDirectChatConnectionKey)
		return NSLocalizedString(@"Direct Chat Invites", @"Direct Chat Invites header title");

	return [item description];
}

- (BOOL) outlineView:(NSOutlineView *) outlineView isGroupItem:(id) item {
	return [self _isHeaderItem:item]; // top level, shows the connection name
}

#pragma mark -

- (NSCell *) outlineView:(NSOutlineView *) outlineView dataCellForTableColumn:(NSTableColumn *) tableColumn item:(id) item {
	if ([item isKindOfClass:[MVChatConnection class]]) {
		CQGroupCell *cell = [[CQGroupCell alloc] initTextCell:((MVChatConnection *)item).server];
		cell.unansweredActivityCount = [outlineView isItemExpanded:item] ? 0 : ((NSArray *)[_activity objectForKey:item]).count;
		return [cell autorelease];
	}

	if (item == CQDirectChatConnectionKey) {
		CQGroupCell *cell = [[CQGroupCell alloc] initTextCell:NSLocalizedString(@"Direct Chat Invites", @"Direct Chat Invites header title")];
		cell.unansweredActivityCount = [outlineView isItemExpanded:item] ? 0 : ((NSArray *)[_activity objectForKey:item]).count;
		return [cell autorelease];
	}

	return [[[NSCell alloc] initTextCell:[item description]] autorelease];
}

- (CGFloat) outlineView:(NSOutlineView *) outlineView heightOfRowByItem:(id) item {
	return (item && [self _isHeaderItem:item]) ? 19. : 50.;
}

- (BOOL) outlineView:(NSOutlineView *) outlineView shouldCollapseItem:(id) item {
	return [self _shouldExpandOrCollapse];
}

- (BOOL) outlineView:(NSOutlineView *) outlineView shouldEditTableColumn:(NSTableColumn *) tableColumn item:(id) item {
	return NO;
}

- (BOOL) outlineView:(NSOutlineView *) outlineView shouldExpandItem:(id) item {
	return [self _shouldExpandOrCollapse];
}

- (BOOL) outlineView:(NSOutlineView *) outlineView shouldSelectItem:(id) item {
	return ![self _isHeaderItem:item];
}

- (NSString *) outlineView:(NSOutlineView *) outlineView toolTipForCell:(NSCell *) cell rect:(NSRectPointer) rect tableColumn:(NSTableColumn *) tableColumn item:(id) item mouseLocation:(NSPoint) mouseLocation {
	if ([item isKindOfClass:[MVChatConnection class]]) {
		NSUInteger invites = [self _invitationCountForConnection:item];
		NSUInteger fileTransfers = [self _fileTransferCountForConnection:item];
		if (invites) {
			if (invites > 1) {
				if (fileTransfers) {
					if (fileTransfers > 1) {
						return [NSString stringWithFormat:@"%ld file transfers and %ld chat room invites on %@", fileTransfers, invites, ((MVChatConnection *)item).server];
					}
					return [NSString stringWithFormat:@"1 file transfer and %ld chat room invites on %@", invites, ((MVChatConnection *)item).server];
				}
				return [NSString stringWithFormat:@"%ld chat room invites on %@", fileTransfers, ((MVChatConnection *)item).server];
			}
			if (fileTransfers) {
				if (fileTransfers > 1) {
					return [NSString stringWithFormat:@"%ld file transfers and 1 chat room invite on %@", fileTransfers, ((MVChatConnection *)item).server];
				}
				return [NSString stringWithFormat:@"1 file transfer and 1 chat room invite on %@", fileTransfers, ((MVChatConnection *)item).server];
			}
			return [NSString stringWithFormat:@"1 chat room invite on %@", fileTransfers, ((MVChatConnection *)item).server];
		}
		if (fileTransfers) {
			if (fileTransfers > 1)
				return [NSString stringWithFormat:@"%ld file transfers on %@", fileTransfers, ((MVChatConnection *)item).server];
			return [NSString stringWithFormat:@"1 file transfer on %@", fileTransfers, ((MVChatConnection *)item).server];
		}
	}

	if (item == CQDirectChatConnectionKey) {
		NSUInteger count = [self _directChatConnectionCount];
		if (count > 1)
			return [NSString stringWithFormat:@"%ld direct chat invitations", count];
		return [NSString stringWithFormat:@"1 direct chat invitation", count];
	}

	return nil;
}

#pragma mark -

- (NSUInteger) _countForType:(NSString *) type inConnection:(id) connection {
	NSUInteger count = 0;
	for (NSDictionary *dictionary in [_activity objectForKey:connection])
		if ([dictionary objectForKey:@"type"] == type)
			count++;
	return count;
}

- (NSUInteger) _directChatConnectionCount {
	return [self _countForType:CQActivityTypeDirectChatInvite inConnection:CQDirectChatConnectionKey];
}

- (NSUInteger) _fileTransferCountForConnection:(MVChatConnection *) connection {
	return [self _countForType:CQActivityTypeFileTransfer inConnection:connection];
}

- (NSUInteger) _invitationCountForConnection:(MVChatConnection *) connection {
	return [self _countForType:CQActivityTypeChatInvite inConnection:connection];
}

#pragma mark -

- (BOOL) _isHeaderItem:(id) item {
	return ([item isKindOfClass:[MVChatConnection class]] || item == CQDirectChatConnectionKey);
}

- (BOOL) _shouldExpandOrCollapse {
	if (!_rowLastClickedTime) {
		_rowLastClickedTime = [NSDate timeIntervalSinceReferenceDate];

		return YES;
	}

	NSTimeInterval currentTime = [NSDate timeIntervalSinceReferenceDate];
	BOOL shouldExpandOrCollapse = ((currentTime - _rowLastClickedTime) > CQExpandCollapseRowInterval);

	_rowLastClickedTime = currentTime;

	return shouldExpandOrCollapse;
}

#pragma mark -

- (void) _appendActivity:(NSDictionary *) activity forConnection:(id) connection {
	NSMutableArray *activities = [_activity objectForKey:connection];
	NSString *type = [activity objectForKey:@"type"];
	if (type == CQActivityTypeFileTransfer) // file transfers are sorted by time added, so just add to the end
		[activities addObject:activity];

	if (type == CQActivityTypeChatInvite) {
		NSUInteger insertionPoint = 0;
		for (NSDictionary *existingActivity in activities) {
			type = [existingActivity objectForKey:@"type"];
			if (type == CQActivityTypeFileTransfer) // File transfers are at the end and we want to insert above it
				break;

			if (type == CQActivityTypeChatInvite)
				continue;

			if ([[activity objectForKey:@"room"] compare:[existingActivity objectForKey:@"room"]] == NSOrderedDescending)
				insertionPoint++;
			else break;
		}

		[activities insertObject:activity atIndex:insertionPoint];
	}

	if (type == CQActivityTypeDirectChatInvite) {
		NSUInteger insertionPoint = 0;
		id newUser = [activity objectForKey:@"user"];
		for (NSDictionary *existingActivity in activities) {
			id existingUser = [existingActivity objectForKey:@"user"];
			NSComparisonResult comparisonResult = [newUser compare:existingUser];
			if (comparisonResult != NSOrderedDescending) // multiple dcc chat sessions for the same username are valid, added to the end, after the current ones.
				insertionPoint++;
			else break;
		}

		[activities insertObject:activity atIndex:insertionPoint];
	}
}
@end
