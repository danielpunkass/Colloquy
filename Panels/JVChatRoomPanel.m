#import "JVChatController.h"
#import "JVTabbedChatWindowController.h"
#import "MVConnectionsController.h"
#import "JVChatRoomPanel.h"
#import "JVChatRoomMember.h"
#import "JVNotificationController.h"
#import "MVBuddyListController.h"
#import "JVBuddy.h"
#import "JVChatMessage.h"
#import "MVTextView.h"
#import "JVStyleView.h"
#import "NSURLAdditions.h"
#import "NSAttributedStringMoreAdditions.h"
#import "MVChatUserAdditions.h"
#import "MVApplicationController.h"

@interface JVChatRoomPanel (JVChatRoomPrivate)
- (void) _topicChanged:(id) sender;
@end

#pragma mark -

@interface JVDirectChatPanel (JVDirectChatPrivate)
- (NSString *) _selfCompositeName;
- (NSString *) _selfStoredNickname;
- (NSMutableAttributedString *) _convertRawMessage:(NSData *) message;
- (NSMutableAttributedString *) _convertRawMessage:(NSData *) message withBaseFont:(NSFont *) baseFont;
- (void) _didConnect:(NSNotification *) notification;
- (void) _didDisconnect:(NSNotification *) notification;
- (void) _didSwitchStyles:(NSNotification *) notification;
@end

#pragma mark -

@interface JVChatRoomMember (JVChatMemberPrivate)
- (NSString *) _selfStoredNickname;
- (NSString *) _selfCompositeName;
- (void) _detach;
@end

#pragma mark -

@implementation JVChatRoomPanel
- (id) initWithTarget:(id) target {
	if( ( self = [super initWithTarget:target] ) ) {
		_sortedMembers = [[NSMutableArray allocWithZone:nil] initWithCapacity:100];
		_preferredTabCompleteNicknames = [[NSMutableArray allocWithZone:nil] initWithCapacity:10];
		_nextMessageAlertMembers = [[NSMutableSet allocWithZone:nil] initWithCapacity:5];
		_cantSendMessages = YES;
		_kickedFromRoom = NO;
		_banListSynced = NO;
		_joinCount = 0;

		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector( _partedRoom: ) name:MVChatRoomPartedNotification object:target];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector( _kicked: ) name:MVChatRoomKickedNotification object:target];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector( _memberJoined: ) name:MVChatRoomUserJoinedNotification object:target];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector( _memberParted: ) name:MVChatRoomUserPartedNotification object:target];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector( _memberKicked: ) name:MVChatRoomUserKickedNotification object:target];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector( _roomModeChanged: ) name:MVChatRoomModesChangedNotification object:target];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector( _memberModeChanged: ) name:MVChatRoomUserModeChangedNotification object:target];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector( _memberBanned: ) name:MVChatRoomUserBannedNotification object:target];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector( _memberBanRemoved: ) name:MVChatRoomUserBanRemovedNotification object:target];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector( _membersSynced: ) name:MVChatRoomMemberUsersSyncedNotification object:target];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector( _bannedMembersSynced: ) name:MVChatRoomBannedUsersSyncedNotification object:target];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector( _memberNicknameChanged: ) name:MVChatUserNicknameChangedNotification object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector( _userBricked: ) name:MVChatRoomUserBrickedNotification object:target];
	}

	return self;
}

- (void) awakeFromNib {
	[super awakeFromNib];

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector( _didClearDisplay: ) name:JVStyleViewDidClearNotification object:display];

	[display setBodyTemplate:@"chatRoom"];
	[display addBanner:@"roomTopicBanner"];

/*	NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@://%@/%@", [[self connection] urlScheme], [[self connection] server], [[_target description] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]]];
	NSString *path = [[NSString stringWithFormat:@"~/Library/Application Support/Colloquy/Recent Chat Rooms/%@ (%@).inetloc", _target, [[self connection] server]] stringByExpandingTildeInPath];

	[url writeToInternetLocationFile:path];
	[[NSFileManager defaultManager] changeFileAttributes:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:YES], NSFileExtensionHidden, nil] atPath:path]; */
}

- (void) dealloc {
	[self partChat:nil];

	[[NSNotificationCenter defaultCenter] removeObserver:self];

	[_sortedMembers makeObjectsPerformSelector:@selector( _detach )];
	[_nextMessageAlertMembers makeObjectsPerformSelector:@selector( _detach )];

	[_sortedMembers release];
	[_preferredTabCompleteNicknames release];
	[_nextMessageAlertMembers release];

	_sortedMembers = nil;
	_preferredTabCompleteNicknames = nil;
	_nextMessageAlertMembers = nil;

	[super dealloc];
}

#pragma mark -
#pragma mark Chat View Protocol Support

- (void) setWindowController:(JVChatWindowController *) controller {
	[super setWindowController:controller];
	if( [[self preferenceForKey:@"expanded"] boolValue] )
		[controller performSelector:@selector( expandListItem: ) withObject:self afterDelay:0.];
}

- (void) willDispose {
	[super willDispose];
	[self partChat:nil];
}

#pragma mark -

- (NSString *) title {
	if( [[NSUserDefaults standardUserDefaults] boolForKey:@"JVShowFullRoomNames"] )
		return [(MVChatRoom *)[self target] name];
	return [[self target] displayName];
}

- (NSString *) windowTitle {
	return [NSString stringWithFormat:@"%@ (%@)", [self title], [[self connection] server]];
}

- (NSString *) information {
	if( _kickedFromRoom )
		return NSLocalizedString( @"kicked out", "chat room kicked status line in drawer" );
	if( ! [_sortedMembers count] )
		return NSLocalizedString( @"joining...", "joining status info line in drawer" );
	if( [[self connection] isConnected] ) {
		if( [[[MVConnectionsController defaultController] connectedConnections] count] == 1 ) {
			if( [_sortedMembers count] > 1 )
				return [NSString stringWithFormat:NSLocalizedString( @"%d members", "number of room members information line" ), [_sortedMembers count]];
			else if( [_sortedMembers count] == 1 )
				return NSLocalizedString( @"1 member", "one room member information line" );
		} else return [[self connection] server];
	}
	return NSLocalizedString( @"disconnected", "disconnected status info line in drawer" );
}

- (NSString *) toolTip {
	NSString *messageCount = @"";
	NSString *memberCount = @"";

	if( [self newMessagesWaiting] == 0 ) messageCount = NSLocalizedString( @"no messages waiting", "no messages waiting room tooltip" );
	else if( [self newMessagesWaiting] == 1 ) messageCount = NSLocalizedString( @"1 message waiting", "one message waiting room tooltip" );
	else messageCount = [NSString stringWithFormat:NSLocalizedString( @"%d messages waiting", "messages waiting room tooltip" ), [self newMessagesWaiting]];

	if( [_sortedMembers count] == 1 ) memberCount = NSLocalizedString( @"1 member", "one member room status info tooltip" );
	else memberCount = [NSString stringWithFormat:NSLocalizedString( @"%d members", "number of members room status info tooltip" ), [_sortedMembers count]];

	return [NSString stringWithFormat:@"%@ (%@)\n%@\n%@", _target, [[self connection] server], memberCount, messageCount];
}

- (NSString *) identifier {
	return [NSString stringWithFormat:@"Chat Room %@ (%@)", [self target], [[self connection] server]];
}

#pragma mark -

- (NSImage *) icon {
	BOOL smallIcons = [[[self windowController] preferenceForKey:@"small drawer icons"] boolValue];
	if( smallIcons || [_windowController isMemberOfClass:[JVTabbedChatWindowController class]] )
		return [NSImage imageNamed:@"roomTab"];
	return [NSImage imageNamed:@"room"];
}

- (NSImage *) statusImage {
	if( [_windowController isMemberOfClass:[JVTabbedChatWindowController class]] ) {
		if( _isActive && [[[self view] window] isKeyWindow] ) {
			_newMessageCount = 0;
			_newHighlightMessageCount = 0;
			[[NSApp delegate] updateDockTile];
			return nil;
		}

		return ( [_waitingAlerts count] ? [NSImage imageNamed:@"AlertCautionIcon"] : ( _newMessageCount ? ( _newHighlightMessageCount ? [NSImage imageNamed:@"roomTabNewHighlightMessage"] : [NSImage imageNamed:@"roomTabNewMessage"] ) : nil ) );
	}

	return [super statusImage];
}

- (BOOL) isEnabled {
	return [[self target] isJoined];
}

#pragma mark -

- (NSUInteger) numberOfChildren {
	return [_sortedMembers count];
}

- (id) childAtIndex:(NSUInteger) index {
	return [_sortedMembers objectAtIndex:index];
}

- (NSArray *) children {
	return _sortedMembers;
}

#pragma mark -

- (NSMenu *) menu {
	NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];
	NSMenuItem *item = nil;

	item = [[NSMenuItem alloc] initWithTitle:NSLocalizedString( @"Get Info", "get info contextual menu item title" ) action:@selector( getInfo: ) keyEquivalent:@""];
	[item setTarget:_windowController];
	[menu addItem:item];
	[item release];

	item = [[NSMenuItem alloc] initWithTitle:NSLocalizedString( @"Add to Favorites", "add to favorites contextual menu") action:@selector( addToFavorites: ) keyEquivalent:@""];
	[item setTarget:self];
	[menu addItem:item];
	[item release];

	[menu addItem:[NSMenuItem separatorItem]];

	if( [[[self windowController] allChatViewControllers] count] > 1 ) {
		item = [[NSMenuItem alloc] initWithTitle:NSLocalizedString( @"Detach From Window", "detach from window contextual menu item title" ) action:@selector( detachView: ) keyEquivalent:@""];
		[item setRepresentedObject:self];
		[item setTarget:[JVChatController defaultController]];
		[menu addItem:item];
		[item release];
	}

	item = [[NSMenuItem alloc] initWithTitle:NSLocalizedString( @"Close", "close contextual menu item title" ) action:@selector( close: ) keyEquivalent:@""];
	[item setTarget:self];
	[menu addItem:item];
	[item release];

	[menu addItem:[NSMenuItem separatorItem]];

	item = [[NSMenuItem alloc] initWithTitle:NSLocalizedString( @"Auto Join", "auto join contextual menu") action:@selector( toggleAutoJoin: ) keyEquivalent:@""];
	[item setTarget:self];
	[menu addItem:item];
	[item release];

	if( [[self target] isJoined] ) {
		item = [[NSMenuItem alloc] initWithTitle:NSLocalizedString( @"Leave Room", "leave room contextual menu item title" ) action:@selector( partChat: ) keyEquivalent:@""];
		[item setTarget:self];
		[menu addItem:item];
		[item release];
	} else {
		item = [[NSMenuItem alloc] initWithTitle:NSLocalizedString( @"Rejoin Room", "rejoin room contextual menu item title" ) action:@selector( joinChat: ) keyEquivalent:@""];
		[item setTarget:self];
		[menu addItem:item];
		[item release];
	}

	[menu addItem:[NSMenuItem separatorItem]];

	item = [[NSMenuItem alloc] initWithTitle:NSLocalizedString( @"Ignore Notifications", "lists whether or not notifications are enabled") action:@selector( toggleNotifications: ) keyEquivalent:@""];
	[item setEnabled:YES];
	[item setTarget:self];
	[menu addItem:item];
	[item release];

	return [menu autorelease];
}

#pragma mark -

- (BOOL) acceptsDraggedFileOfType:(NSString *) type {
	return NO;
}

- (void) handleDraggedFile:(NSString *) path {
	[self doesNotRecognizeSelector:_cmd];
}

#pragma mark -

- (BOOL) validateMenuItem:(NSMenuItem *) menuItem {
	if( [menuItem action] == @selector( addToFavorites: ) && [menuItem tag] == 10 )
		[menuItem setTitle:[NSString stringWithFormat:NSLocalizedString( @"Add \"%@ (%@)\"", "add to favorites contextual menu"), _target, [[self connection] server]]];
	else if( [menuItem action] == @selector( toggleAutoJoin: ) ) {
		[menuItem setState:NSOffState];
		for( id object in [[MVConnectionsController defaultController] joinRoomsForConnection:[self connection]] )
			if( [_target isEqual:[[self connection] chatRoomWithName:(NSString *)object]] )
				[menuItem setState:NSOnState];
	}

	return [super validateMenuItem: menuItem];
}

#pragma mark -
#pragma mark Miscellaneous

- (IBAction) clearDisplay:(id) sender {
	[display clear];
}

- (IBAction) addToFavorites:(id) sender {
	NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@://%@/%@", [[self connection] urlScheme], [[self connection] server], [[_target description] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]]];
	NSString *path = [[NSString stringWithFormat:@"~/Library/Application Support/Colloquy/Favorites/%@ (%@).inetloc", _target, [[self connection] server]] stringByExpandingTildeInPath];

	[url writeToInternetLocationFile:path];
	[[NSFileManager defaultManager] setAttributes:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:YES], NSFileExtensionHidden, nil] ofItemAtPath:path error:nil];
	[[NSWorkspace sharedWorkspace] noteFileSystemChanged:path];

	[MVConnectionsController refreshFavoritesMenu];
}

- (IBAction) toggleAutoJoin:(id) sender {
	NSMutableArray *rooms = [[[MVConnectionsController defaultController] joinRoomsForConnection:[self connection]] mutableCopy];
	if( [(NSMenuItem *)sender state] == NSOnState ) {
		for( id object in rooms )
			if( [_target isEqual:[[self connection] chatRoomWithName:(NSString *)object]] ) {
				[rooms removeObject:object];
				break;
			}
	} else [rooms addObject:[_target name]];

	[[MVConnectionsController defaultController] setJoinRooms:rooms forConnection:[self connection]];

	[rooms release];
}

- (IBAction) changeEncoding:(id) sender {
	[super changeEncoding:sender];
	[[self target] setEncoding:[self encoding]];
	if( sender ) [self _topicChanged:nil];
}

#pragma mark -
#pragma mark Message Handling

- (void) handleRoomMessageNotification:(NSNotification *) notification {
	JVChatMessageType type = ( [[[notification userInfo] objectForKey:@"notice"] boolValue] ? JVChatMessageNoticeType : JVChatMessageNormalType );
	[self addMessageToDisplay:[[notification userInfo] objectForKey:@"message"] fromUser:[[notification userInfo] objectForKey:@"user"] withAttributes:[notification userInfo] withIdentifier:[[notification userInfo] objectForKey:@"identifier"] andType:type];
}

- (void) processIncomingMessage:(JVMutableChatMessage *) message {
	JVChatRoomMember *member = [self chatRoomMemberForUser:[message sender]];
	if( member ) [message setSender:member];

	if( [message isHighlighted] && [message ignoreStatus] == JVNotIgnored ) {
		[_preferredTabCompleteNicknames removeObject:[[message sender] nickname]];
		[_preferredTabCompleteNicknames insertObject:[[message sender] nickname] atIndex:0];
	}

	if( [message ignoreStatus] == JVNotIgnored && [[message sender] respondsToSelector:@selector( isLocalUser )] && ! [[message sender] isLocalUser] ) {
		NSMutableDictionary *context = [NSMutableDictionary dictionary];
		[context setObject:[NSString stringWithFormat:NSLocalizedString( @"%@ Room Activity", "room activity bubble title" ), [self title]] forKey:@"title"];
		if( [self newMessagesWaiting] == 1 ) [context setObject:[NSString stringWithFormat:NSLocalizedString( @"%@ has a message waiting\nfrom %@.", "new single room message bubble text" ), [self title], [member displayName]] forKey:@"title"];
		else [context setObject:[NSString stringWithFormat:NSLocalizedString( @"%@ has %d messages waiting.\nLast from %@", "new room messages bubble text" ), [self title], [self newMessagesWaiting], [member displayName]] forKey:@"title"];
		[context setObject:[NSString stringWithFormat:NSLocalizedString( @"%@", "room activity bubble message" ), [message bodyAsPlainText]] forKey:@"description"];
		[context setObject:[NSImage imageNamed:@"room"] forKey:@"image"];
		[context setObject:[[self windowTitle] stringByAppendingString:@"JVChatRoomActivity"] forKey:@"coalesceKey"];
		[context setObject:self forKey:@"target"];
		[context setObject:NSStringFromSelector( @selector( activate: ) ) forKey:@"action"];
		[self performNotification:@"JVChatRoomActivity" withContextInfo:context];
	}

	if( [message ignoreStatus] == JVNotIgnored && [_nextMessageAlertMembers containsObject:[message sender]] ) {
		NSMutableDictionary *context = [NSMutableDictionary dictionary];
		[context setObject:[NSString stringWithFormat:NSLocalizedString( @"%@ Replied", "member replied bubble title" ), [[message sender] title]] forKey:@"title"];
		[context setObject:[NSString stringWithFormat:NSLocalizedString( @"%@ has possibly replied to your message.", "new room messages bubble text" ), [[message sender] title]] forKey:@"description"];
		[context setObject:[NSImage imageNamed:@"activityNewImportant"] forKey:@"image"];
		[context setObject:self forKey:@"target"];
		[context setObject:NSStringFromSelector( @selector( activate: ) ) forKey:@"action"];
		[self performNotification:@"JVChatReplyAfterAddressing" withContextInfo:context];

		[_nextMessageAlertMembers removeObject:[message sender]];
	}

	NSCharacterSet *escapeSet = [NSCharacterSet characterSetWithCharactersInString:@"^[]{}()\\.$*+?|"];

	for( member in _sortedMembers ) {
		NSMutableString *escapedName = [[member nickname] mutableCopy];
		[escapedName escapeCharactersInSet:escapeSet];

		NSString *pattern = [[NSString alloc] initWithFormat:@"(?<=^|\\s|[^\\w])%@(?=$|\\s|[^\\w])", escapedName];
		AGRegex *regex = [AGRegex regexWithPattern:pattern options:AGRegexCaseInsensitive];

		[escapedName release];
		[pattern release];

		NSArray *matches = [regex findAllInString:[message bodyAsPlainText]];

		for( AGRegexMatch *match in matches ) {
			NSRange foundRange = [match range];
			// don't highlight nicks in the middle of a link
			if( ! [[message body] attribute:NSLinkAttributeName atIndex:foundRange.location effectiveRange:NULL] ) {
				NSMutableSet *classes = [NSMutableSet setWithSet:[[message body] attribute:@"CSSClasses" atIndex:foundRange.location effectiveRange:NULL]];
				[classes addObject:@"member"];
				[[message body] addAttribute:@"CSSClasses" value:[NSSet setWithSet:classes] range:foundRange];
			}
		}
	}

	NSMethodSignature *signature = [NSMethodSignature methodSignatureWithReturnAndArgumentTypes:@encode( void ), @encode( JVMutableChatMessage * ), @encode( id ), nil];
	NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];

	[invocation setSelector:@selector( processIncomingMessage:inView: )];
	[invocation setArgument:&message atIndex:2];
	[invocation setArgument:&self atIndex:3];

	[[MVChatPluginManager defaultManager] makePluginsPerformInvocation:invocation stoppingOnFirstSuccessfulReturn:NO];
}

- (void) sendMessage:(JVMutableChatMessage *) message {
	[super sendMessage:message];

	AGRegex *regex = [AGRegex regexWithPattern:@"^(.*?)[:;,-]" options:AGRegexCaseInsensitive];
	AGRegexMatch *match = [regex findInString:[message bodyAsPlainText]];
	if( [match count] ) {
		JVChatRoomMember *mbr = [self firstChatRoomMemberWithName:[match groupAtIndex:1]];
		if( mbr ) [_nextMessageAlertMembers addObject:mbr];
	}
}

#pragma mark -
#pragma mark Join & Part Handling

- (void) joined {
	_banListSynced = NO;

	[_sortedMembers makeObjectsPerformSelector:@selector( _detach )];
	[_sortedMembers removeAllObjects];

	[_preferredTabCompleteNicknames removeAllObjects];

	[_nextMessageAlertMembers makeObjectsPerformSelector:@selector( _detach )];
	[_nextMessageAlertMembers removeAllObjects];

	for( MVChatUser *member in [[self target] memberUsers] ) {
		JVChatRoomMember *listItem = [[JVChatRoomMember alloc] initWithRoom:self andUser:member];
		[_sortedMembers addObject:listItem];
		[listItem release];
	}

	[self resortMembers];

	_cantSendMessages = NO;
	_kickedFromRoom = NO;

	[_windowController reloadListItem:self andChildren:YES];

	NSMethodSignature *signature = [NSMethodSignature methodSignatureWithReturnAndArgumentTypes:@encode( void ), @encode( JVChatRoomPanel * ), nil];
	NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];

	[invocation setSelector:@selector( joinedRoom: )];
	[invocation setArgument:&self atIndex:2];

	[[MVChatPluginManager defaultManager] makePluginsPerformInvocation:invocation];

	[[NSNotificationCenter defaultCenter] removeObserver:self name:MVChatConnectionNicknameAcceptedNotification object:nil];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:MVChatRoomTopicChangedNotification object:nil];

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector( _selfNicknameChanged: ) name:MVChatConnectionNicknameAcceptedNotification object:[self connection]];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector( _topicChanged: ) name:MVChatRoomTopicChangedNotification object:[self target]];

	[self _topicChanged:nil];

	if( _joinCount ) [self addEventMessageToDisplay:NSLocalizedString( @"You rejoined the room.", "rejoined the room status message" ) withName:@"rejoined" andAttributes:nil];
	_joinCount++;
}

- (void) parting {
	if( [[self target] isJoined] ) {
		_cantSendMessages = YES;

		NSMethodSignature *signature = [NSMethodSignature methodSignatureWithReturnAndArgumentTypes:@encode( void ), @encode( JVChatRoomPanel * ), nil];
		NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];

		[invocation setSelector:@selector( partingFromRoom: )];
		[invocation setArgument:&self atIndex:2];

		[[MVChatPluginManager defaultManager] makePluginsPerformInvocation:invocation];

		[[NSNotificationCenter defaultCenter] removeObserver:self name:MVChatConnectionNicknameAcceptedNotification object:nil];
		[[NSNotificationCenter defaultCenter] removeObserver:self name:MVChatRoomTopicChangedNotification object:nil];
	}
}

#pragma mark -

- (void) joinChat:(id) sender {
	if( ! [[self connection] isConnected] )
		[[self connection] connect];
	[[self target] join];
}

- (void) partChat:(id) sender {
	if( [[self target] isJoined] ) {
		[self parting];
		[[self target] part];
	}
}

#pragma mark -
#pragma mark User List Access

- (NSSet *) chatRoomMembersWithName:(NSString *) name {
	if( ! [name length] ) return nil;

	NSMutableSet *ret = [NSMutableSet set];
	JVChatRoomMember *member = nil;

	for( member in _sortedMembers ) {
		if( [[member nickname] caseInsensitiveCompare:name] == NSOrderedSame ) {
			[ret addObject:member];
		} else if( [[member realName] caseInsensitiveCompare:name] == NSOrderedSame ) {
			[ret addObject:member];
		} else if( [[member title] caseInsensitiveCompare:name] == NSOrderedSame ) {
			[ret addObject:member];
		}
	}

	return [NSSet setWithSet:ret];
}

- (JVChatRoomMember *) firstChatRoomMemberWithName:(NSString *) name {
	if( ! [name length] ) return nil;

	JVChatRoomMember *member = nil;

	for( member in _sortedMembers ) {
		if( [[member nickname] caseInsensitiveCompare:name] == NSOrderedSame ) {
			return member;
		} else if( [[member title] caseInsensitiveCompare:name] == NSOrderedSame ) {
			return member;
		}
	}

	return nil;
}

- (JVChatRoomMember *) chatRoomMemberForUser:(MVChatUser *) user {
	if( ! user ) return nil;

	JVChatRoomMember *member = nil;

	for( member in _sortedMembers )
		if( [[member user] isEqualToChatUser:user] )
			return member;

	return nil;
}

- (JVChatRoomMember *) localChatRoomMember {
	JVChatRoomMember *member = nil;

	for( member in _sortedMembers )
		if( [[member user] isLocalUser] )
			return member;

	return nil;
}

- (void) resortMembers {
	if( [[NSUserDefaults standardUserDefaults] boolForKey:@"JVSortRoomMembersByStatus"] ) {
		[_sortedMembers sortUsingSelector:@selector( compareUsingStatus: )];
	} else [_sortedMembers sortUsingSelector:@selector( compare: )];

	[_windowController reloadListItem:self andChildren:YES];
}

#pragma mark -
#pragma mark WebKit Support

- (NSArray *) webView:(WebView *) sender contextMenuItemsForElement:(NSDictionary *) element defaultMenuItems:(NSArray *) defaultMenuItems {
	// valid member links: "member:xenon" or "member:identifier:qI+rEcbsuX1T0tNbi6mM+A=="
	if( [[[element objectForKey:WebElementLinkURLKey] scheme] isEqualToString:@"member"] ) {
		NSString *resource = [[[element objectForKey:WebElementLinkURLKey] resourceSpecifier] stringByDecodingIllegalURLCharacters];
		BOOL specific = [resource hasPrefix:@"identifier:"];
		NSString *nick = [resource substringFromIndex:( specific ? 11 : 0 )];
		JVChatRoomMember *mbr = nil;
		MVChatUser *user = nil;

		if( specific ) user = [[self connection] chatUserWithUniqueIdentifier:nick];
		else user = [[self firstChatRoomMemberWithName:nick] user];

		if( ! user ) user = [[[self connection] chatUsersWithNickname:nick] anyObject];

		if( user ) mbr = [self chatRoomMemberForUser:user];
		else mbr = [self firstChatRoomMemberWithName:nick];

		NSMutableArray *ret = [NSMutableArray array];
		NSMenuItem *item = nil;

		if( mbr ) {
			for( item in [[mbr menu] itemArray] ) {
				item = [item copy];
				[ret addObject:item];
				[item release];
			}
		} else if( user ) {
			for( item in [user standardMenuItems] )
				[ret addObject:item];
		}

		NSMethodSignature *signature = [NSMethodSignature methodSignatureWithReturnAndArgumentTypes:@encode( NSArray * ), @encode( id ), @encode( id ), nil];
		NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];

		[invocation setSelector:@selector( contextualMenuItemsForObject:inView: )];
		if( mbr ) [invocation setArgument:&mbr atIndex:2];
		else [invocation setArgument:&user atIndex:2];
		[invocation setArgument:&self atIndex:3];

		NSArray *results = [[MVChatPluginManager defaultManager] makePluginsPerformInvocation:invocation];
		if( [results count] ) {
			[ret addObject:[NSMenuItem separatorItem]];

			NSArray *items = nil;
			for( items in results ) {
				if( ![items conformsToProtocol:@protocol(NSFastEnumeration)] ) continue;

				for( item in items )
					if( [item isKindOfClass:[NSMenuItem class]] ) [ret addObject:item];
			}

			if( [[ret lastObject] isSeparatorItem] )
				[ret removeObjectIdenticalTo:[ret lastObject]];
		}

		return ret;
	}

	return [super webView:sender contextMenuItemsForElement:element defaultMenuItems:defaultMenuItems];
}

- (void) webView:(WebView *) sender decidePolicyForNavigationAction:(NSDictionary *) actionInformation request:(NSURLRequest *) request frame:(WebFrame *) frame decisionListener:(id <WebPolicyDecisionListener>) listener {
	// valid member links: "member:xenon" or "member:identifier:qI+rEcbsuX1T0tNbi6mM+A=="
	if( [[[actionInformation objectForKey:WebActionOriginalURLKey] scheme] isEqualToString:@"member"] ) {
		NSString *resource = [[[actionInformation objectForKey:WebActionOriginalURLKey] resourceSpecifier] stringByDecodingIllegalURLCharacters];
		BOOL specific = [resource hasPrefix:@"identifier:"];
		NSString *nick = [resource substringFromIndex:( specific ? 11 : 0 )];
		MVChatUser *user = nil;

		if( specific ) user = [[self connection] chatUserWithUniqueIdentifier:nick];
		else user = [[self firstChatRoomMemberWithName:nick] user];

		if( ! user ) user = [[[self connection] chatUsersWithNickname:nick] anyObject];

		if( user && ! [user isLocalUser] )
			[[JVChatController defaultController] chatViewControllerForUser:user ifExists:NO];

		[listener ignore];
	} else {
		[super webView:sender decidePolicyForNavigationAction:actionInformation request:request frame:frame decisionListener:listener];
	}
}

#pragma mark -
#pragma mark TextView/Input Support

- (NSArray *) textView:(NSTextView *) textView stringCompletionsForPrefix:(NSString *) prefix {
	NSMutableArray *possibleCompletion = [NSMutableArray array];

	if( [prefix isEqualToString:@""] ) {
		if( [_preferredTabCompleteNicknames count] )
			[possibleCompletion addObject:[_preferredTabCompleteNicknames objectAtIndex:0]];
		return possibleCompletion;
	}

	for( NSString *name in _preferredTabCompleteNicknames )
		if( [name rangeOfString:prefix options:( NSCaseInsensitiveSearch | NSAnchoredSearch )].location == NSOrderedSame )
			[possibleCompletion addObject:name];

	for( MVChatUser *user in _sortedMembers ) {
		NSString *name = [user nickname];
		if( ! [possibleCompletion containsObject:name] && [name rangeOfString:prefix options:( NSCaseInsensitiveSearch | NSAnchoredSearch )].location == NSOrderedSame )
			[possibleCompletion addObject:name];
	}

	static NSArray *commands;
	if (!commands) commands = [[NSArray alloc] initWithObjects:@"/topic ", @"/kick ", @"/ban ", @"/kickban ", @"/op ", @"/voice ", @"/halfop ", @"/quiet ", @"/deop ", @"/devoice ", @"/dehalfop ", @"/dequiet ", @"/unban ", @"/bankick ", @"/cycle ", @"/hop ", @"/me ", @"/msg ", @"/nick ", @"/away ", @"/say ", @"/raw ", @"/quote ", @"/join ", @"/quit ", @"/disconnect ", @"/query ", @"/umode ", @"/globops ", @"/google ", @"/part ", nil];

	for( NSString *name in commands )
		if ([name hasCaseInsensitivePrefix:prefix])
			[possibleCompletion addObject:name];

	return possibleCompletion;
}

- (void) textView:(NSTextView *) textView selectedCompletion:(NSString *) completion fromPrefix:(NSString *) prefix {
	if( [completion isEqualToString:[[[self connection] localUser] nickname]] ) return;
	[_preferredTabCompleteNicknames removeObject:completion];
	[_preferredTabCompleteNicknames insertObject:completion atIndex:0];
}

- (NSArray *) textView:(NSTextView *) textView completions:(NSArray *) words forPartialWordRange:(NSRange) charRange indexOfSelectedItem:(NSInteger *) index {
	NSEvent *event = [[NSApplication sharedApplication] currentEvent];
	NSString *search = [[[send textStorage] string] substringWithRange:charRange];
	NSMutableArray *ret = [NSMutableArray array];
	NSString *suffix = ( ! ( [event modifierFlags] & NSAlternateKeyMask ) ? ( charRange.location == 0 ? @": " : @" " ) : @"" );
	NSUInteger length = [search length];

	for( MVChatUser *user in _sortedMembers ) {
		if (!length) break;

		NSString *name = [user nickname];

		if( length <= [name length] && [search caseInsensitiveCompare:[name substringToIndex:length]] == NSOrderedSame )
			[ret addObject:[name stringByAppendingString:suffix]];
	}

	unichar chr = 0;
	if( [[event charactersIgnoringModifiers] length] )
		chr = [[event charactersIgnoringModifiers] characterAtIndex:0];

	if( chr != NSTabCharacter ) [ret addObjectsFromArray:words];
	return ret;
}

#pragma mark -
#pragma mark Toolbar Support
- (NSString *) toolbarIdentifier {
	return @"Chat Room";
}

- (NSArray *) toolbarDefaultItemIdentifiers:(NSToolbar *) toolbar {
	NSMutableArray *list = [NSMutableArray arrayWithArray:[super toolbarDefaultItemIdentifiers:toolbar]];
	[list addObject:JVToolbarTextEncodingItemIdentifier];
	[list addObject:NSToolbarFlexibleSpaceItemIdentifier];
	[list addObject:JVToolbarMarkItemIdentifier];
	[list addObject:JVToolbarClearScrollbackItemIdentifier];
	[list addObject:NSToolbarSeparatorItemIdentifier];
	[list addObject:JVToolbarQuickSearchItemIdentifier];
	return list;
}
@end

#pragma mark -

@implementation JVChatRoomPanel (JVChatRoomPrivate)

- (void) _didDisconnect:(NSNotification *) notification {
	_kickedFromRoom = NO;
	[super _didDisconnect:notification];
	[_windowController reloadListItem:self andChildren:YES];

	[[NSNotificationCenter defaultCenter] removeObserver:self name:MVChatConnectionNicknameAcceptedNotification object:nil];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:MVChatRoomTopicChangedNotification object:nil];
}

- (void) _partedRoom:(NSNotification *) notification {
	if( ! [[self connection] isConnected] ) return;

	_cantSendMessages = NO;

	NSMutableAttributedString *rstring = [self _convertRawMessage:[[notification userInfo] objectForKey:@"reason"]];
	[self addEventMessageToDisplay:NSLocalizedString( @"You left the room.", "you parted the room status message" ) withName:@"parted" andAttributes:[NSDictionary dictionaryWithObjectsAndKeys:( rstring ? (id) rstring : (id) [NSNull null] ), @"reason", nil]];
}

- (void) _roomModeChanged:(NSNotification *) notification {
	MVChatUser *user = [[notification userInfo] objectForKey:@"by"];

	if( ! user ) return;
	if( [[self connection] type] == MVChatConnectionIRCType && [[user nickname] rangeOfString:@"."].location != NSNotFound )
		return; // a server telling us the initial modes when we join, ignore these on IRC connections

	JVChatRoomMember *mbr = [self chatRoomMemberForUser:user];

	NSUInteger changedModes = [[[notification userInfo] objectForKey:@"changedModes"] unsignedIntValue];
	NSUInteger newModes = [[self target] modes];

	while( changedModes ) {
		NSString *message = nil;
		NSString *mode = nil;
		id parameter = nil;

		if( changedModes & MVChatRoomPrivateMode ) {
			changedModes &= ~MVChatRoomPrivateMode;
			mode = @"chatRoomPrivateMode";
			if( newModes & MVChatRoomPrivateMode ) {
				if( [mbr isLocalUser] ) {
					message = NSLocalizedString( @"You made this room private.", "private room status message" );
				} else {
					message = [NSString stringWithFormat:NSLocalizedString( @"%@ made this room private.", "someone else private room status message" ), ( mbr ? [[mbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[user nickname] stringByEncodingXMLSpecialCharactersAsEntities] )];
				}
			} else {
				if( [mbr isLocalUser] ) {
					message = NSLocalizedString( @"You made this room public.", "public room status message" );
				} else {
					message = [NSString stringWithFormat:NSLocalizedString( @"%@ made this room public.", "someone else public room status message" ), ( mbr ? [[mbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[user nickname] stringByEncodingXMLSpecialCharactersAsEntities] )];
				}
			}
		} else if( changedModes & MVChatRoomSecretMode ) {
			changedModes &= ~MVChatRoomSecretMode;
			mode = @"chatRoomSecretMode";
			if( newModes & MVChatRoomSecretMode ) {
				if( [mbr isLocalUser] ) {
					message = NSLocalizedString( @"You made this room secret.", "secret room status message" );
				} else {
					message = [NSString stringWithFormat:NSLocalizedString( @"%@ made this room secret.", "someone else secret room status message" ), ( mbr ? [[mbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[user nickname] stringByEncodingXMLSpecialCharactersAsEntities] )];
				}
			} else {
				if( [mbr isLocalUser] ) {
					message = NSLocalizedString( @"You made this room no longer a secret.", "no longer secret room status message" );
				} else {
					message = [NSString stringWithFormat:NSLocalizedString( @"%@ made this room no longer a secret.", "someone else no longer secret room status message" ), ( mbr ? [[mbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[user nickname] stringByEncodingXMLSpecialCharactersAsEntities] )];
				}
			}
		} else if( changedModes & MVChatRoomInviteOnlyMode ) {
			changedModes &= ~MVChatRoomInviteOnlyMode;
			mode = @"chatRoomInviteOnlyMode";
			if( newModes & MVChatRoomInviteOnlyMode ) {
				if( [mbr isLocalUser] ) {
					message = NSLocalizedString( @"You made this room invite only.", "invite only room status message" );
				} else {
					message = [NSString stringWithFormat:NSLocalizedString( @"%@ made this room invite only.", "someone else invite only room status message" ), ( mbr ? [[mbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[user nickname] stringByEncodingXMLSpecialCharactersAsEntities] )];
				}
			} else {
				if( [mbr isLocalUser] ) {
					message = NSLocalizedString( @"You made this room no longer invite only.", "no longer invite only room status message" );
				} else {
					message = [NSString stringWithFormat:NSLocalizedString( @"%@ made this room no longer invite only.", "someone else no longer invite only room status message" ), ( mbr ? [[mbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[user nickname] stringByEncodingXMLSpecialCharactersAsEntities] )];
				}
			}
		} else if( changedModes & MVChatRoomNormalUsersSilencedMode ) {
			changedModes &= ~MVChatRoomNormalUsersSilencedMode;
			mode = @"chatRoomNormalUsersSilencedMode";
			if( newModes & MVChatRoomNormalUsersSilencedMode ) {
				if( [mbr isLocalUser] ) {
					message = NSLocalizedString( @"You made this room moderated for normal users.", "moderated for normal users room status message" );
				} else {
					message = [NSString stringWithFormat:NSLocalizedString( @"%@ made this room moderated for normal users.", "someone else moderated for normal users room status message" ), ( mbr ? [[mbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[user nickname] stringByEncodingXMLSpecialCharactersAsEntities] )];
				}
			} else {
				if( [mbr isLocalUser] ) {
					message = NSLocalizedString( @"You made this room no longer moderated for normal users.", "no longer moderated for normal users room status message" );
				} else {
					message = [NSString stringWithFormat:NSLocalizedString( @"%@ made this room no longer moderated for normal users.", "someone else no longer moderated for normal users room status message" ), ( mbr ? [[mbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[user nickname] stringByEncodingXMLSpecialCharactersAsEntities] )];
				}
			}
		} else if( changedModes & MVChatRoomOperatorsSilencedMode ) {
			changedModes &= ~MVChatRoomOperatorsSilencedMode;
			mode = @"chatRoomOperatorsSilencedMode";
			if( newModes & MVChatRoomOperatorsSilencedMode ) {
				if( [mbr isLocalUser] ) {
					message = NSLocalizedString( @"You made this room moderated for operators.", "moderated for operators room status message" );
				} else {
					message = [NSString stringWithFormat:NSLocalizedString( @"%@ made this room moderated for operators.", "someone else moderated for operators room status message" ), ( mbr ? [[mbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[user nickname] stringByEncodingXMLSpecialCharactersAsEntities] )];
				}
			} else {
				if( [mbr isLocalUser] ) {
					message = NSLocalizedString( @"You made this room no longer moderated for operators.", "no longer moderated for operators room status message" );
				} else {
					message = [NSString stringWithFormat:NSLocalizedString( @"%@ made this room no longer moderated for operators.", "someone else no longer moderated for operators room status message" ), ( mbr ? [[mbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[user nickname] stringByEncodingXMLSpecialCharactersAsEntities] )];
				}
			}
		} else if( changedModes & MVChatRoomOperatorsOnlySetTopicMode ) {
			changedModes &= ~MVChatRoomOperatorsOnlySetTopicMode;
			mode = @"MVChatRoomOperatorsOnlySetTopicMode";
			if( newModes & MVChatRoomOperatorsOnlySetTopicMode ) {
				if( [mbr isLocalUser] ) {
					message = NSLocalizedString( @"You changed this room to require operator status to change the topic.", "require op to set topic room status message" );
				} else {
					message = [NSString stringWithFormat:NSLocalizedString( @"%@ changed this room to require operator status to change the topic.", "someone else required op to set topic room status message" ), ( mbr ? [[mbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[user nickname] stringByEncodingXMLSpecialCharactersAsEntities] )];
				}
			} else {
				if( [mbr isLocalUser] ) {
					message = NSLocalizedString( @"You changed this room to allow anyone to change the topic.", "don't require op to set topic room status message" );
				} else {
					message = [NSString stringWithFormat:NSLocalizedString( @"%@ changed this room to allow anyone to change the topic.", "someone else don't required op to set topic room status message" ), ( mbr ? [[mbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[user nickname] stringByEncodingXMLSpecialCharactersAsEntities] )];
				}
			}
		} else if( changedModes & MVChatRoomNoOutsideMessagesMode ) {
			changedModes &= ~MVChatRoomNoOutsideMessagesMode;
			mode = @"chatRoomNoOutsideMessagesMode";
			if( newModes & MVChatRoomNoOutsideMessagesMode ) {
				if( [mbr isLocalUser] ) {
					message = NSLocalizedString( @"You changed this room to prohibit outside messages.", "prohibit outside messages room status message" );
				} else {
					message = [NSString stringWithFormat:NSLocalizedString( @"%@ changed this room to prohibit outside messages.", "someone else prohibit outside messages room status message" ), ( mbr ? [[mbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[user nickname] stringByEncodingXMLSpecialCharactersAsEntities] )];
				}
			} else {
				if( [mbr isLocalUser] ) {
					message = NSLocalizedString( @"You changed this room to permit outside messages.", "permit outside messages room status message" );
				} else {
					message = [NSString stringWithFormat:NSLocalizedString( @"%@ changed this room to permit outside messages.", "someone else permit outside messages room status message" ), ( mbr ? [[mbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[user nickname] stringByEncodingXMLSpecialCharactersAsEntities] )];
				}
			}
		} else if( changedModes & MVChatRoomPassphraseToJoinMode ) {
			changedModes &= ~MVChatRoomPassphraseToJoinMode;
			mode = @"chatRoomPassphraseToJoinMode";
			if( newModes & MVChatRoomPassphraseToJoinMode ) {
				parameter = [[self target] attributeForMode:MVChatRoomPassphraseToJoinMode];
				if( [mbr isLocalUser] ) {
					message = [NSString stringWithFormat:NSLocalizedString( @"You changed this room to require a password of \"%@\".", "password required room status message" ), parameter];
				} else {
					message = [NSString stringWithFormat:NSLocalizedString( @"%@ changed this room to require a password of \"%@\".", "someone else password required room status message" ), ( mbr ? [[mbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[user nickname] stringByEncodingXMLSpecialCharactersAsEntities] ), parameter];
				}
			} else {
				if( [mbr isLocalUser] ) {
					message = NSLocalizedString( @"You changed this room to no longer require a password.", "no longer passworded room status message" );
				} else {
					message = [NSString stringWithFormat:NSLocalizedString( @"%@ changed this room to no longer require a password.", "someone else no longer passworded room status message" ), ( mbr ? [[mbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[user nickname] stringByEncodingXMLSpecialCharactersAsEntities] )];
				}
			}
		} else if( changedModes & MVChatRoomLimitNumberOfMembersMode ) {
			changedModes &= ~MVChatRoomLimitNumberOfMembersMode;
			mode = @"chatRoomLimitNumberOfMembersMode";
			if( newModes & MVChatRoomLimitNumberOfMembersMode ) {
				parameter = [[self target] attributeForMode:MVChatRoomLimitNumberOfMembersMode];
				if( [mbr isLocalUser] ) {
					message = [NSString stringWithFormat:NSLocalizedString( @"You set a limit on the number of room members to %@.", "member limit room status message" ), parameter];
				} else {
					message = [NSString stringWithFormat:NSLocalizedString( @"%@ set a limit on the number of room members to %@.", "someone else member limit room status message" ), ( mbr ? [[mbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[user nickname] stringByEncodingXMLSpecialCharactersAsEntities] ), parameter];
				}
			} else {
				if( [mbr isLocalUser] ) {
					message = NSLocalizedString( @"You removed the room member limit.", "no member limit room status message" );
				} else {
					message = [NSString stringWithFormat:NSLocalizedString( @"%@ removed the room member limit", "someone else no member limit room status message" ), ( mbr ? [[mbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[user nickname] stringByEncodingXMLSpecialCharactersAsEntities] )];
				}
			}
		}

		if( message && mode ) [self addEventMessageToDisplay:message withName:@"modeChange" andAttributes:[NSDictionary dictionaryWithObjectsAndKeys:( mbr ? (id) mbr : (id) user ), @"by", mode, @"mode", ( [[[notification userInfo] objectForKey:@"enabled"] boolValue] ? @"yes" : @"no" ), @"enabled", parameter, @"parameter", nil]];
	}
}

- (void) _selfNicknameChanged:(NSNotification *) notification {
	[self resortMembers];
	[self addEventMessageToDisplay:[NSString stringWithFormat:NSLocalizedString( @"You are now known as <span class=\"member\">%@</span>.", "you changed nicknames" ), [[[self connection] nickname] stringByEncodingXMLSpecialCharactersAsEntities]] withName:@"newNickname" andAttributes:[NSDictionary dictionaryWithObjectsAndKeys:[self localChatRoomMember], @"who", nil]];
}

- (void) _memberNicknameChanged:(NSNotification *) notification {
	if( ! [[self target] hasUser:[notification object]] ) return;

	[self resortMembers];

	JVChatRoomMember *member = [self chatRoomMemberForUser:[notification object]];
	if( ! member ) return;

	NSString *oldNickname = [[notification userInfo] objectForKey:@"oldNickname"];

	NSUInteger index = [_preferredTabCompleteNicknames indexOfObject:oldNickname];
	if( index != NSNotFound ) [_preferredTabCompleteNicknames replaceObjectAtIndex:index withObject:[member nickname]];

	[self addEventMessageToDisplay:[NSString stringWithFormat:NSLocalizedString( @"%@ is now known as <span class=\"member\">%@</span>.", "user has changed nicknames" ), [oldNickname stringByEncodingXMLSpecialCharactersAsEntities], [[member nickname] stringByEncodingXMLSpecialCharactersAsEntities]] withName:@"memberNewNickname" andAttributes:[NSDictionary dictionaryWithObjectsAndKeys:oldNickname, @"old", member, @"who", nil]];
}

- (void) _memberJoined:(NSNotification *) notification {
	MVChatUser *user = [[notification userInfo] objectForKey:@"user"];
	JVChatRoomMember *listItem = [[self chatRoomMemberForUser:user] retain];

	if( ! listItem ) {
		listItem = [[JVChatRoomMember alloc] initWithRoom:self andUser:user];
		[_sortedMembers addObject:listItem];
		[self resortMembers];
	}

	NSString *name = [listItem title];
	NSString *message = [NSString stringWithFormat:NSLocalizedString( @"<span class=\"member\">%@</span> joined the chat room.", "a user has join a chat room status message" ), [name stringByEncodingXMLSpecialCharactersAsEntities]];
	[self addEventMessageToDisplay:message withName:@"memberJoined" andAttributes:[NSDictionary dictionaryWithObjectsAndKeys:listItem, @"who", nil]];

	NSMethodSignature *signature = [NSMethodSignature methodSignatureWithReturnAndArgumentTypes:@encode( void ), @encode( JVChatRoomMember * ), @encode( JVChatRoomPanel * ), nil];
	NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];

	[invocation setSelector:@selector( memberJoined:inRoom: )];
	[invocation setArgument:&listItem atIndex:2];
	[invocation setArgument:&self atIndex:3];

	[[MVChatPluginManager defaultManager] makePluginsPerformInvocation:invocation];

	NSMutableDictionary *context = [NSMutableDictionary dictionary];
	[context setObject:NSLocalizedString( @"Room Member Joined", "member joined title" ) forKey:@"title"];
	[context setObject:[NSString stringWithFormat:NSLocalizedString( @"%@ joined the chat room %@.", "bubble message member joined string" ), name, _target] forKey:@"description"];
	[context setObject:self forKey:@"target"];
	[context setObject:NSStringFromSelector( @selector( activate: ) ) forKey:@"action"];
	[self performNotification:@"JVChatMemberJoinedRoom" withContextInfo:context];

	[listItem release];
}

- (void) _memberParted:(NSNotification *) notification {
	MVChatUser *user = [[notification userInfo] objectForKey:@"user"];
	JVChatRoomMember *mbr = [self chatRoomMemberForUser:user];
	if( ! mbr ) return;

	NSMutableAttributedString *rstring = [self _convertRawMessage:[[notification userInfo] objectForKey:@"reason"]];

	NSMethodSignature *signature = [NSMethodSignature methodSignatureWithReturnAndArgumentTypes:@encode( void ), @encode( JVChatRoomMember * ), @encode( JVChatRoomPanel * ), @encode( NSAttributedString * ), nil];
	NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];

	[invocation setSelector:@selector( memberParted:fromRoom:forReason: )];
	[invocation setArgument:&mbr atIndex:2];
	[invocation setArgument:&self atIndex:3];
	[invocation setArgument:&rstring atIndex:4];

	[[MVChatPluginManager defaultManager] makePluginsPerformInvocation:invocation];

	if( [_windowController selectedListItem] == mbr )
		[_windowController showChatViewController:[_windowController activeChatViewController]];

	NSString *name = [mbr title];
	NSString *message = [NSString stringWithFormat:NSLocalizedString( @"<span class=\"member\">%@</span> left the chat room.", "a user has left the chat room status message" ), [name stringByEncodingXMLSpecialCharactersAsEntities]];

	[self addEventMessageToDisplay:message withName:@"memberParted" andAttributes:[NSDictionary dictionaryWithObjectsAndKeys:mbr, @"who", ( rstring ? (id) rstring : (id) [NSNull null] ), @"reason", nil]];

	NSMutableDictionary *context = [NSMutableDictionary dictionary];
	[context setObject:NSLocalizedString( @"Room Member Left", "member left title" ) forKey:@"title"];
	[context setObject:[NSString stringWithFormat:NSLocalizedString( @"%@ left the chat room %@.", "bubble message member left string" ), name, _target] forKey:@"description"];
	[context setObject:self forKey:@"target"];
	[context setObject:NSStringFromSelector( @selector( activate: ) ) forKey:@"action"];
	[self performNotification:@"JVChatMemberLeftRoom" withContextInfo:context];

	[mbr _detach];

	[_preferredTabCompleteNicknames removeObject:[mbr nickname]];
	[_sortedMembers removeObjectIdenticalTo:mbr];
	[_nextMessageAlertMembers removeObject:mbr];
	[_windowController reloadListItem:self andChildren:YES];
}

- (void) _userBricked:(NSNotification *) notification {
	MVChatUser *user = [[notification userInfo] objectForKey:@"user"];

	NSString *message = nil;
	NSString *ctxmessage = nil;
	if( user ) {
		if( [user isLocalUser] ) {
			message = NSLocalizedString( @"You have been bricked.", "you have been bricked status message" );
			ctxmessage = NSLocalizedString( @"You have been bricked.", "bubble message user bricked string" );
		} else {
			NSString *name = [user nickname];
			message = [NSString stringWithFormat:NSLocalizedString( @"<span class=\"member\">%@</span> has been bricked.", "a user has been bricked status message" ), [name stringByEncodingXMLSpecialCharactersAsEntities]];
			ctxmessage = [NSString stringWithFormat:NSLocalizedString( @"%@ has been bricked.", "bubble message user bricked string" ), name];
		}

		[self addEventMessageToDisplay:message withName:@"userBricked" andAttributes:[NSDictionary dictionaryWithObjectsAndKeys:user, @"who", nil]];
	} else {
		message = NSLocalizedString( @"A brick flies off into the ether.", "a brick flies off into the ether status message" );
		ctxmessage = NSLocalizedString( @"A brick flies off into the ether.", "bubble message nobody bricked string" );

		[self addEventMessageToDisplay:message withName:@"userBricked" andAttributes:nil];
	}
	NSAssert( message, @"message not initialized in conditional" );
	NSAssert( ctxmessage, @"ctxmessage not initialized in conditional" );

	NSMethodSignature *signature = [NSMethodSignature methodSignatureWithReturnAndArgumentTypes:@encode( void ), @encode( MVChatUser * ), @encode( JVChatRoomPanel * ), nil];
	NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];

	[invocation setSelector:@selector( userBricked:inRoom: )];
	[invocation setArgument:&user atIndex:2];
	[invocation setArgument:&self atIndex:3];

	[[MVChatPluginManager defaultManager] makePluginsPerformInvocation:invocation];

	NSMutableDictionary *context = [NSMutableDictionary dictionary];
	[context setObject:NSLocalizedString( @"Chat User Bricked", "user bricked title" ) forKey:@"title"];
	[context setObject:ctxmessage forKey:@"description"];
	[context setObject:self forKey:@"target"];
	[context setObject:NSStringFromSelector( @selector( activate: ) ) forKey:@"action"];
}

- (void) _kicked:(NSNotification *) notification {
	MVChatUser *byUser = [[notification userInfo] objectForKey:@"byUser"];
	JVChatRoomMember *byMbr = [self chatRoomMemberForUser:byUser];
	NSMutableAttributedString *rstring = [self _convertRawMessage:[[notification userInfo] objectForKey:@"reason"]];
	NSString *message = [NSString stringWithFormat:NSLocalizedString( @"You were kicked from the chat room by %@.", "you were removed by force from a chat room status message" ), ( byMbr ? [[byMbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[byUser nickname] stringByEncodingXMLSpecialCharactersAsEntities] )];

	[self addEventMessageToDisplay:message withName:@"kicked" andAttributes:[NSDictionary dictionaryWithObjectsAndKeys:( byMbr ? (id) byMbr : (id) byUser ), @"by", ( rstring ? (id) rstring : (id) [NSNull null] ), @"reason", nil]];

	NSMethodSignature *signature = [NSMethodSignature methodSignatureWithReturnAndArgumentTypes:@encode( void ), @encode( JVChatRoomPanel * ), @encode( JVChatRoomMember * ), @encode( NSAttributedString * ), nil];
	NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];

	[invocation setSelector:@selector( kickedFromRoom:by:forReason: )];
	[invocation setArgument:&self atIndex:2];
	[invocation setArgument:&byMbr atIndex:3];
	[invocation setArgument:&rstring atIndex:4];

	[[MVChatPluginManager defaultManager] makePluginsPerformInvocation:invocation];

	JVChatRoomMember *mbr = [[self localChatRoomMember] retain];
	if( [_windowController selectedListItem] == mbr )
		[_windowController showChatViewController:[_windowController activeChatViewController]];

	[mbr _detach];

	[_preferredTabCompleteNicknames removeObject:[mbr nickname]];
	[_sortedMembers removeObjectIdenticalTo:mbr];
	[_nextMessageAlertMembers removeObject:mbr];
	[_windowController reloadListItem:self andChildren:YES];

	_kickedFromRoom = YES;
	_cantSendMessages = YES;

	NSMutableDictionary *context = [NSMutableDictionary dictionary];
	[context setObject:NSLocalizedString( @"You Were Kicked", "member kicked title" ) forKey:@"title"];
	[context setObject:[NSString stringWithFormat:NSLocalizedString( @"You were kicked from %@ by %@.", "bubble message member kicked string" ), [self title], ( byMbr ? [[byMbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[byUser nickname] stringByEncodingXMLSpecialCharactersAsEntities] )] forKey:@"description"];
	[context setObject:self forKey:@"target"];
	[context setObject:NSStringFromSelector( @selector( activate: ) ) forKey:@"action"];
	[self performNotification:@"JVChatMemberKicked" withContextInfo:context];

	// auto-rejoin on kick
	if( [[NSUserDefaults standardUserDefaults] boolForKey:@"JVAutoRejoinRoomsOnKick"] ) {
		[self performSelector:@selector(joinChat:) withObject:nil afterDelay:[[NSUserDefaults standardUserDefaults] floatForKey:@"JVAutoRejoinRoomsDelay"]];
	} else {
		[self showAlert:NSGetInformationalAlertPanel( NSLocalizedString( @"You have been kicked from the chat room.", "you were removed by force from a chat room error message title" ), NSLocalizedString( @"You have been kicked from the chat room by %@ with the reason \"%@\" and cannot send further messages without rejoining.", "you were removed by force from a chat room error message" ), @"OK", nil, nil, ( byMbr ? [[byMbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[byUser nickname] stringByEncodingXMLSpecialCharactersAsEntities] ), ( rstring ? [rstring string] : @"" ) ) withName:nil];
	}

	[mbr release];
}

- (void) _memberKicked:(NSNotification *) notification {
	MVChatUser *user = [[notification userInfo] objectForKey:@"user"];
	JVChatRoomMember *mbr = [[self chatRoomMemberForUser:user] retain];
	if( ! mbr ) return;

	MVChatUser *byUser = [[notification userInfo] objectForKey:@"byUser"];
	JVChatRoomMember *byMbr = [self chatRoomMemberForUser:byUser];
	NSMutableAttributedString *rstring = [self _convertRawMessage:[[notification userInfo] objectForKey:@"reason"]];

	NSMethodSignature *signature = [NSMethodSignature methodSignatureWithReturnAndArgumentTypes:@encode( void ), @encode( JVChatRoomMember * ), @encode( JVChatRoomPanel * ), @encode( JVChatRoomMember * ), @encode( NSAttributedString * ), nil];
	NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];

	[invocation setSelector:@selector( memberKicked:fromRoom:by:forReason: )];
	[invocation setArgument:&mbr atIndex:2];
	[invocation setArgument:&self atIndex:3];
	[invocation setArgument:&byMbr atIndex:4];
	[invocation setArgument:&rstring atIndex:5];

	[[MVChatPluginManager defaultManager] makePluginsPerformInvocation:invocation];

	if( [_windowController selectedListItem] == mbr )
		[_windowController showChatViewController:[_windowController activeChatViewController]];

	[mbr _detach];

	[_preferredTabCompleteNicknames removeObject:[mbr nickname]];
	[_sortedMembers removeObjectIdenticalTo:mbr];
	[_nextMessageAlertMembers removeObject:mbr];
	[_windowController reloadListItem:self andChildren:YES];

	NSString *message = nil;
	if( [byMbr isLocalUser] ) {
		message = [NSString stringWithFormat:NSLocalizedString( @"You kicked %@ from the chat room.", "you removed a user by force from a chat room status message" ), ( mbr ? [[mbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[user nickname] stringByEncodingXMLSpecialCharactersAsEntities] )];
	} else {
		message = [NSString stringWithFormat:NSLocalizedString( @"%@ was kicked from the chat room by <span class=\"member\">%@</span>.", "user has been removed by force from a chat room status message" ), ( mbr ? [[mbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[user nickname] stringByEncodingXMLSpecialCharactersAsEntities] ), ( byMbr ? [[byMbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[byUser nickname] stringByEncodingXMLSpecialCharactersAsEntities] )];
	}

	[self addEventMessageToDisplay:message withName:@"memberKicked" andAttributes:[NSDictionary dictionaryWithObjectsAndKeys:( mbr ? (id) mbr : (id) user ), @"who", ( byMbr ? (id) byMbr : (id) byUser ), @"by", ( rstring ? (id) rstring : (id) [NSNull null] ), @"reason", nil]];

	NSMutableDictionary *context = [NSMutableDictionary dictionary];
	[context setObject:NSLocalizedString( @"Room Member Kicked", "member kicked title" ) forKey:@"title"];
	[context setObject:[NSString stringWithFormat:NSLocalizedString( @"%@ was kicked from %@ by %@.", "bubble message member kicked string" ), ( mbr ? [[mbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[user nickname] stringByEncodingXMLSpecialCharactersAsEntities] ), [self title], ( byMbr ? [[byMbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[byUser nickname] stringByEncodingXMLSpecialCharactersAsEntities] )] forKey:@"description"];
	[context setObject:self forKey:@"target"];
	[context setObject:NSStringFromSelector( @selector( activate: ) ) forKey:@"action"];
	[self performNotification:@"JVChatMemberKicked" withContextInfo:context];

	[mbr release];
}

- (void) _memberBanned:(NSNotification *) notification {
	if( ! _banListSynced ) return;

	MVChatUser *byUser = [[notification userInfo] objectForKey:@"byUser"];
	JVChatRoomMember *byMbr = [self chatRoomMemberForUser:byUser];

	MVChatUser *ban = [[notification userInfo] objectForKey:@"user"];

	NSString *message = nil;
	NSString *banned = nil;

	if ([[ban nickname] hasCaseInsensitiveSubstring:@"$"] || [[ban nickname] hasCaseInsensitiveSubstring:@":"] || [[ban nickname] hasCaseInsensitiveSubstring:@"~"]) { // extended bans on ircd-seven, inspircd and unrealircd
		if ([[ban nickname] hasCaseInsensitiveSubstring:@"~q"] || [[ban nickname] hasCaseInsensitiveSubstring:@"~n"]) {
			banned = [ban displayName]; // These two extended bans on unreal-style ircds take full hostmasks as their arguments
		} else {
			banned = [ban nickname];
		}
	}

	if( [byMbr isLocalUser] ) {
		message = [NSString stringWithFormat:NSLocalizedString( @"You set a ban on %@.", "you set a ban chat room status message" ), (banned ? banned : [[ban description] stringByEncodingXMLSpecialCharactersAsEntities])];
	} else {
		message = [NSString stringWithFormat:NSLocalizedString( @"<span class=\"member\">%@</span> set a ban on %@.", "user set a ban chat room status message" ), ( byMbr ? [[byMbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[byUser nickname] stringByEncodingXMLSpecialCharactersAsEntities] ), (banned ? banned : [[ban description] stringByEncodingXMLSpecialCharactersAsEntities])];
	}

	[self addEventMessageToDisplay:message withName:@"memberBanned" andAttributes:[NSDictionary dictionaryWithObjectsAndKeys:[ban description], @"ban", byMbr, @"by", nil]];
}

- (void) _memberBanRemoved:(NSNotification *) notification {
	MVChatUser *byUser = [[notification userInfo] objectForKey:@"byUser"];
	JVChatRoomMember *byMbr = [self chatRoomMemberForUser:byUser];

	MVChatUser *ban = [[notification userInfo] objectForKey:@"user"];

	NSString *message = nil;
	NSString *banned = nil;

	if ([[ban nickname] hasCaseInsensitiveSubstring:@"$"] || [[ban nickname] hasCaseInsensitiveSubstring:@":"] || [[ban nickname] hasCaseInsensitiveSubstring:@"~"]) { // extended bans on ircd-seven, inspircd and unrealircd
		if ([[ban nickname] hasCaseInsensitiveSubstring:@"~q"] || [[ban nickname] hasCaseInsensitiveSubstring:@"~n"]) {
			banned = [ban displayName]; // These two extended bans on unreal-style ircds take full hostmasks as their arguments
		} else {
			banned = [ban nickname];
		}
	}

	if( [byMbr isLocalUser] ) {
		message = [NSString stringWithFormat:NSLocalizedString( @"You removed the ban on %@.", "you removed a ban chat room status message" ), (banned ? banned : [[ban description] stringByEncodingXMLSpecialCharactersAsEntities])];
	} else {
		message = [NSString stringWithFormat:NSLocalizedString( @"<span class=\"member\">%@</span> removed the ban on %@.", "user removed a ban chat room status message" ), ( byMbr ? [[byMbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[byUser nickname] stringByEncodingXMLSpecialCharactersAsEntities] ), (banned ? banned : [[ban description] stringByEncodingXMLSpecialCharactersAsEntities])];
	}

	[self addEventMessageToDisplay:message withName:@"banRemoved" andAttributes:[NSDictionary dictionaryWithObjectsAndKeys:[ban description], @"ban", byMbr, @"by", nil]];
}

- (void) _memberModeChanged:(NSNotification *) notification {
	// sort again if needed
	if( [[NSUserDefaults standardUserDefaults] boolForKey:@"JVSortRoomMembersByStatus"] )
		[self resortMembers];

	MVChatUser *user = [[notification userInfo] objectForKey:@"who"];
	MVChatUser *byUser = [[notification userInfo] objectForKey:@"by"];

	if( ! user ) return;

	JVChatRoomMember *mbr = [self chatRoomMemberForUser:user];
	JVChatRoomMember *byMbr = [self chatRoomMemberForUser:byUser];

	NSString *name = nil;
	NSString *message = nil;
	NSString *title = nil;
	NSString *description = nil;
	NSString *notificationKey = nil;
	NSUInteger mode = [[[notification userInfo] objectForKey:@"mode"] unsignedLongValue];
	BOOL enabled = [[[notification userInfo] objectForKey:@"enabled"] boolValue];

	if( mode == MVChatRoomMemberFounderMode && enabled ) {
		name = @"memberPromotedToFounder";
		if( [mbr isLocalUser] && [byMbr isLocalUser] ) { // only server oppers would ever see this
			message = NSLocalizedString( @"You promoted yourself to room founder.", "we gave ourself the chat room founder privilege status message" );
			name = @"promotedToFounder";
		} else if( [mbr isLocalUser] ) {
			message = [NSString stringWithFormat:NSLocalizedString( @"You were promoted to room founder by <span class=\"member\">%@</span>.", "we are now a chat room founder status message" ), ( byMbr ? [[byMbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[byUser nickname] stringByEncodingXMLSpecialCharactersAsEntities] )];
			name = @"promotedToFounder";
		} else if( [byMbr isLocalUser] ) {
			message = [NSString stringWithFormat:NSLocalizedString( @"<span class=\"member\">%@</span> was promoted to room founder by you.", "we gave user chat room founder status message" ), ( mbr ? [[mbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[user nickname] stringByEncodingXMLSpecialCharactersAsEntities] )];
		} else {
			message = [NSString stringWithFormat:NSLocalizedString( @"<span class=\"member\">%@</span> was promoted to room founder by <span class=\"member\">%@</span>.", "user is now a chat room founder status message" ), ( mbr ? [[mbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[user nickname] stringByEncodingXMLSpecialCharactersAsEntities] ), ( byMbr ? [[byMbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[byUser nickname] stringByEncodingXMLSpecialCharactersAsEntities] )];
		}
	} else if( mode == MVChatRoomMemberFounderMode && ! enabled ) {
		name = @"memberDemotedFromFounder";
		if( [mbr isLocalUser] && [byMbr isLocalUser] ) {
			message = NSLocalizedString( @"You demoted yourself from room founder.", "we removed our chat room founder privilege status message" );
			name = @"demotedFromFounder";
		} else if( [mbr isLocalUser] ) {
			message = [NSString stringWithFormat:NSLocalizedString( @"You were demoted from room founder by <span class=\"member\">%@</span>.", "we are no longer a chat room founder status message" ), ( byMbr ? [[byMbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[byUser nickname] stringByEncodingXMLSpecialCharactersAsEntities] )];
			name = @"demotedFromFounder";
		} else if( [byMbr isLocalUser] ) {
			message = [NSString stringWithFormat:NSLocalizedString( @"<span class=\"member\">%@</span> was demoted from room founder by you.", "we removed user's chat room founder status message" ), ( mbr ? [[mbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[user nickname] stringByEncodingXMLSpecialCharactersAsEntities] )];
		} else {
			message = [NSString stringWithFormat:NSLocalizedString( @"<span class=\"member\">%@</span> was demoted from room founder by <span class=\"member\">%@</span>.", "user is no longer a chat room founder status message" ), ( mbr ? [[mbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[user nickname] stringByEncodingXMLSpecialCharactersAsEntities] ), ( byMbr ? [[byMbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[byUser nickname] stringByEncodingXMLSpecialCharactersAsEntities] )];
		}
	} else if( mode == MVChatRoomMemberAdministratorMode && enabled ) {
		name = @"memberPromotedToAdministrator";
		notificationKey = @"JVChatMemberPromotedAdministrator";
		title = NSLocalizedString( @"New Room Administrator", "room administrator promoted title" );
		description = [NSString stringWithFormat:NSLocalizedString( @"%@ was promoted to administrator by %@ in %@.", "bubble message member administrator promotion string" ), ( mbr ? [[mbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[user nickname] stringByEncodingXMLSpecialCharactersAsEntities] ), ( byMbr ? [[byMbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[byUser nickname] stringByEncodingXMLSpecialCharactersAsEntities] ), [[self title] stringByEncodingXMLSpecialCharactersAsEntities]];
		if( [mbr isLocalUser] && [byMbr isLocalUser] ) { // only server oppers would ever see this
			message = NSLocalizedString( @"You promoted yourself to Administrator.", "we gave ourself the chat room administrator privilege status message" );
			name = @"promotedToAdministrator";
		} else if( [mbr isLocalUser] ) {
			message = [NSString stringWithFormat:NSLocalizedString( @"You were promoted to administrator by <span class=\"member\">%@</span>.", "we are now a chat room administrator status message" ), ( byMbr ? [[byMbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[byUser nickname] stringByEncodingXMLSpecialCharactersAsEntities] )];
			name = @"promotedToAdministrator";
		} else if( [byMbr isLocalUser] ) {
			message = [NSString stringWithFormat:NSLocalizedString( @"<span class=\"member\">%@</span> was promoted to administrator by you.", "we gave user chat room administrator status message" ), ( mbr ? [[mbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[user nickname] stringByEncodingXMLSpecialCharactersAsEntities] )];
		} else {
			message = [NSString stringWithFormat:NSLocalizedString( @"<span class=\"member\">%@</span> was promoted to administrator by <span class=\"member\">%@</span>.", "user is now a chat room administrator status message" ), ( mbr ? [[mbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[user nickname] stringByEncodingXMLSpecialCharactersAsEntities] ), ( byMbr ? [[byMbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[byUser nickname] stringByEncodingXMLSpecialCharactersAsEntities] )];
		}
	} else if( mode == MVChatRoomMemberAdministratorMode && ! enabled ) {
		name = @"memberDemotedFromAdministrator";
		notificationKey = @"JVChatMemberDemotedAdministrator";
		title = NSLocalizedString( @"Room Administrator Demoted", "room administrator demoted title" );
		description = [NSString stringWithFormat:NSLocalizedString( @"%@ was demoted from administrator by %@ in %@.", "bubble message member administrator demotion string" ), ( mbr ? [[mbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[user nickname] stringByEncodingXMLSpecialCharactersAsEntities] ), ( byMbr ? [[byMbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[byUser nickname] stringByEncodingXMLSpecialCharactersAsEntities] ), [[self title] stringByEncodingXMLSpecialCharactersAsEntities]];
		if( [mbr isLocalUser] && [byMbr isLocalUser] ) {
			message = NSLocalizedString( @"You demoted yourself from administrator.", "we removed our chat room administrator privilege status message" );
			name = @"demotedFromAdministrator";
		} else if( [mbr isLocalUser] ) {
			message = [NSString stringWithFormat:NSLocalizedString( @"You were demoted from administrator by <span class=\"member\">%@</span>.", "we are no longer a chat room administrator status message" ), ( byMbr ? [[byMbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[byUser nickname] stringByEncodingXMLSpecialCharactersAsEntities] )];
			name = @"demotedFromAdministrator";
		} else if( [byMbr isLocalUser] ) {
			message = [NSString stringWithFormat:NSLocalizedString( @"<span class=\"member\">%@</span> was demoted from administrator by you.", "we removed user's chat room administrator status message" ), ( mbr ? [[mbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[user nickname] stringByEncodingXMLSpecialCharactersAsEntities] )];
		} else {
			message = [NSString stringWithFormat:NSLocalizedString( @"<span class=\"member\">%@</span> was demoted from administrator by <span class=\"member\">%@</span>.", "user is no longer a chat room administrator status message" ), ( mbr ? [[mbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[user nickname] stringByEncodingXMLSpecialCharactersAsEntities] ), ( byMbr ? [[byMbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[byUser nickname] stringByEncodingXMLSpecialCharactersAsEntities] )];
		}
	} else if( mode == MVChatRoomMemberOperatorMode && enabled ) {
		name = @"memberPromotedToOperator";
		notificationKey = @"JVChatMemberPromotedOperator";
		title = NSLocalizedString( @"New Room Operator", "member promoted title" );
		description = [NSString stringWithFormat:NSLocalizedString( @"%@ was promoted to operator by %@ in %@.", "bubble message member operator promotion string" ), ( mbr ? [[mbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[user nickname] stringByEncodingXMLSpecialCharactersAsEntities] ), ( byMbr ? [[byMbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[byUser nickname] stringByEncodingXMLSpecialCharactersAsEntities] ), [[self title] stringByEncodingXMLSpecialCharactersAsEntities]];
		if( [mbr isLocalUser] && [byMbr isLocalUser] ) { // only server oppers would ever see this
			message = NSLocalizedString( @"You promoted yourself to operator.", "we gave ourself the chat room operator privilege status message" );
			name = @"promotedToOperator";
		} else if( [mbr isLocalUser] ) {
			message = [NSString stringWithFormat:NSLocalizedString( @"You were promoted to operator by <span class=\"member\">%@</span>.", "we are now a chat room operator status message" ), ( byMbr ? [[byMbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[byUser nickname] stringByEncodingXMLSpecialCharactersAsEntities] )];
			name = @"promotedToOperator";
		} else if( [byMbr isLocalUser] ) {
			message = [NSString stringWithFormat:NSLocalizedString( @"<span class=\"member\">%@</span> was promoted to operator by you.", "we gave user chat room operator status message" ), ( mbr ? [[mbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[user nickname] stringByEncodingXMLSpecialCharactersAsEntities] )];
		} else {
			message = [NSString stringWithFormat:NSLocalizedString( @"<span class=\"member\">%@</span> was promoted to operator by <span class=\"member\">%@</span>.", "user is now a chat room operator status message" ), ( mbr ? [[mbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[user nickname] stringByEncodingXMLSpecialCharactersAsEntities] ), ( byMbr ? [[byMbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[byUser nickname] stringByEncodingXMLSpecialCharactersAsEntities] )];
		}
	} else if( mode == MVChatRoomMemberOperatorMode && ! enabled ) {
		name = @"memberDemotedFromOperator";
		notificationKey = @"JVChatMemberDemotedOperator";
		title = NSLocalizedString( @"Room Operator Demoted", "room operator demoted title" );
		description = [NSString stringWithFormat:NSLocalizedString( @"%@ was demoted from operator by %@ in %@.", "bubble message member operator demotion string" ), ( mbr ? [[mbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[user nickname] stringByEncodingXMLSpecialCharactersAsEntities] ), ( byMbr ? [[byMbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[byUser nickname] stringByEncodingXMLSpecialCharactersAsEntities] ), [[self title] stringByEncodingXMLSpecialCharactersAsEntities]];
		if( [mbr isLocalUser] && [byMbr isLocalUser] ) {
			message = NSLocalizedString( @"You demoted yourself from operator.", "we removed our chat room operator privilege status message" );
			name = @"demotedFromOperator";
		} else if( [mbr isLocalUser] ) {
			message = [NSString stringWithFormat:NSLocalizedString( @"You were demoted from operator by <span class=\"member\">%@</span>.", "we are no longer a chat room operator status message" ), ( byMbr ? [[byMbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[byUser nickname] stringByEncodingXMLSpecialCharactersAsEntities] )];
			name = @"demotedFromOperator";
		} else if( [byMbr isLocalUser] ) {
			message = [NSString stringWithFormat:NSLocalizedString( @"<span class=\"member\">%@</span> was demoted from operator by you.", "we removed user's chat room operator status message" ), ( mbr ? [[mbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[user nickname] stringByEncodingXMLSpecialCharactersAsEntities] )];
		} else {
			message = [NSString stringWithFormat:NSLocalizedString( @"<span class=\"member\">%@</span> was demoted from operator by <span class=\"member\">%@</span>.", "user is no longer a chat room operator status message" ), ( mbr ? [[mbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[user nickname] stringByEncodingXMLSpecialCharactersAsEntities] ), ( byMbr ? [[byMbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[byUser nickname] stringByEncodingXMLSpecialCharactersAsEntities] )];
		}
	} else if( mode == MVChatRoomMemberHalfOperatorMode && enabled ) {
		name = @"memberPromotedToHalfOperator";
		notificationKey = @"JVChatMemberPromotedHalfOperator";
		title = NSLocalizedString( @"New Room Half-Operator", "member promoted to half-operator title" );
		description = [NSString stringWithFormat:NSLocalizedString( @"%@ was promoted to half-operator by %@ in %@.", "bubble message member half-operator promotion string" ), ( mbr ? [[mbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[user nickname] stringByEncodingXMLSpecialCharactersAsEntities] ), ( byMbr ? [[byMbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[byUser nickname] stringByEncodingXMLSpecialCharactersAsEntities] ), [[self title] stringByEncodingXMLSpecialCharactersAsEntities]];
		if( [mbr isLocalUser] && [byMbr isLocalUser] ) { // only server oppers would ever see this
			message = NSLocalizedString( @"You promoted yourself to half-operator.", "we gave ourself the chat room half-operator privilege status message" );
			name = @"promotedToHalfOperator";
		} else if( [mbr isLocalUser] ) {
			message = [NSString stringWithFormat:NSLocalizedString( @"You were promoted to half-operator by <span class=\"member\">%@</span>.", "we are now a chat room half-operator status message" ), ( byMbr ? [[byMbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[byUser nickname] stringByEncodingXMLSpecialCharactersAsEntities] )];
			name = @"promotedToHalfOperator";
		} else if( [byMbr isLocalUser] ) {
			message = [NSString stringWithFormat:NSLocalizedString( @"<span class=\"member\">%@</span> was promoted to half-operator by you.", "we gave user chat room half-operator status message" ), ( mbr ? [[mbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[user nickname] stringByEncodingXMLSpecialCharactersAsEntities] )];
		} else {
			message = [NSString stringWithFormat:NSLocalizedString( @"<span class=\"member\">%@</span> was promoted to half-operator by <span class=\"member\">%@</span>.", "user is now a chat room half-operator status message" ), ( mbr ? [[mbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[user nickname] stringByEncodingXMLSpecialCharactersAsEntities] ), ( byMbr ? [[byMbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[byUser nickname] stringByEncodingXMLSpecialCharactersAsEntities] )];
		}
	} else if( mode == MVChatRoomMemberHalfOperatorMode && ! enabled ) {
		name = @"memberDemotedFromHalfOperator";
		notificationKey = @"JVChatMemberDemotedHalfOperator";
		title = NSLocalizedString( @"Room Half-Operator Demoted", "room half-operator demoted title" );
		description = [NSString stringWithFormat:NSLocalizedString( @"%@ was demoted from half-operator by %@ in %@.", "bubble message member operator demotion string" ), ( mbr ? [[mbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[user nickname] stringByEncodingXMLSpecialCharactersAsEntities] ), ( byMbr ? [[byMbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[byUser nickname] stringByEncodingXMLSpecialCharactersAsEntities] ), [[self title] stringByEncodingXMLSpecialCharactersAsEntities]];
		if( [mbr isLocalUser] && [byMbr isLocalUser] ) {
			message = NSLocalizedString( @"You demoted yourself from half-operator.", "we removed our chat room half-operator privilege status message" );
			name = @"demotedFromHalfOperator";
		} else if( [mbr isLocalUser] ) {
			message = [NSString stringWithFormat:NSLocalizedString( @"You were demoted from half-operator by <span class=\"member\">%@</span>.", "we are no longer a chat room half-operator status message" ), ( byMbr ? [[byMbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[byUser nickname] stringByEncodingXMLSpecialCharactersAsEntities] )];
			name = @"demotedFromHalfOperator";
		} else if( [byMbr isLocalUser] ) {
			message = [NSString stringWithFormat:NSLocalizedString( @"<span class=\"member\">%@</span> was demoted from half-operator by you.", "we removed user's chat room half-operator status message" ), ( mbr ? [[mbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[user nickname] stringByEncodingXMLSpecialCharactersAsEntities] )];
		} else {
			message = [NSString stringWithFormat:NSLocalizedString( @"<span class=\"member\">%@</span> was demoted from half-operator by <span class=\"member\">%@</span>.", "user is no longer a chat room half-operator status message" ), ( mbr ? [[mbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[user nickname] stringByEncodingXMLSpecialCharactersAsEntities] ), ( byMbr ? [[byMbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[byUser nickname] stringByEncodingXMLSpecialCharactersAsEntities] )];
		}
	} else if( mode == MVChatRoomMemberVoicedMode && enabled ) {
		name = @"memberVoiced";
		notificationKey = @"JVChatMemberVoiced";
		title = NSLocalizedString( @"Room Member Voiced", "member voiced title" );
		description = [NSString stringWithFormat:NSLocalizedString( @"%@ was granted voice by %@ in %@.", "bubble message member voiced string" ), ( mbr ? [[mbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[user nickname] stringByEncodingXMLSpecialCharactersAsEntities] ), ( byMbr ? [[byMbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[byUser nickname] stringByEncodingXMLSpecialCharactersAsEntities] ), [[self title] stringByEncodingXMLSpecialCharactersAsEntities]];
		if( [mbr isLocalUser] && [byMbr isLocalUser] ) {
			message = NSLocalizedString( @"You gave yourself voice.", "we gave ourself special voice status to talk in moderated rooms status message" );
			name = @"voiced";
		} else if( [mbr isLocalUser] ) {
			message = [NSString stringWithFormat:NSLocalizedString( @"You were granted voice by <span class=\"member\">%@</span>.", "we now have special voice status to talk in moderated rooms status message" ), ( byMbr ? [[byMbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[byUser nickname] stringByEncodingXMLSpecialCharactersAsEntities] )];
			name = @"voiced";
		} else if( [byMbr isLocalUser] ) {
			message = [NSString stringWithFormat:NSLocalizedString( @"<span class=\"member\">%@</span> was granted voice by you.", "we gave user special voice status to talk in moderated rooms status message" ), ( mbr ? [[mbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[user nickname] stringByEncodingXMLSpecialCharactersAsEntities] )];
		} else {
			message = [NSString stringWithFormat:NSLocalizedString( @"<span class=\"member\">%@</span> was granted voice by <span class=\"member\">%@</span>.", "user now has special voice status to talk in moderated rooms status message" ), ( mbr ? [[mbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[user nickname] stringByEncodingXMLSpecialCharactersAsEntities] ), ( byMbr ? [[byMbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[byUser nickname] stringByEncodingXMLSpecialCharactersAsEntities] )];
		}
	} else if( mode == MVChatRoomMemberVoicedMode && ! enabled ) {
		name = @"memberDevoiced";
		notificationKey = @"JVChatMemberDevoiced";
		title = NSLocalizedString( @"Room Member Lost Voice", "member devoiced title" );
		description = [NSString stringWithFormat:NSLocalizedString( @"%@ had voice removed by %@ in %@.", "bubble message member lost voice string" ), ( mbr ? [[mbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[user nickname] stringByEncodingXMLSpecialCharactersAsEntities] ), ( byMbr ? [[byMbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[byUser nickname] stringByEncodingXMLSpecialCharactersAsEntities] ), [[self title] stringByEncodingXMLSpecialCharactersAsEntities]];
		if( [mbr isLocalUser] && [byMbr isLocalUser] ) {
			message = NSLocalizedString( @"You removed voice from yourself.", "we removed our special voice status to talk in moderated rooms status message" );
			name = @"devoiced";
		} else if( [mbr isLocalUser] ) {
			message = [NSString stringWithFormat:NSLocalizedString( @"You had voice removed by <span class=\"member\">%@</span>.", "we no longer has special voice status and can't talk in moderated rooms status message" ), ( byMbr ? [[byMbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[byUser nickname] stringByEncodingXMLSpecialCharactersAsEntities] )];
			name = @"devoiced";
		} else if( [byMbr isLocalUser] ) {
			message = [NSString stringWithFormat:NSLocalizedString( @"<span class=\"member\">%@</span> had voice removed by you.", "we removed user's special voice status and can't talk in moderated rooms status message" ), ( mbr ? [[mbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[user nickname] stringByEncodingXMLSpecialCharactersAsEntities] )];
		} else {
			message = [NSString stringWithFormat:NSLocalizedString( @"<span class=\"member\">%@</span> had voice removed by <span class=\"member\">%@</span>.", "user no longer has special voice status and can't talk in moderated rooms status message" ), ( mbr ? [[mbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[user nickname] stringByEncodingXMLSpecialCharactersAsEntities] ), ( byMbr ? [[byMbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[byUser nickname] stringByEncodingXMLSpecialCharactersAsEntities] )];
		}
	} else if( mode == MVChatRoomMemberQuietedMode && enabled ) {
		name = @"memberQuieted";
		notificationKey = @"JVChatMemberQuieted";
		title = NSLocalizedString( @"Room Member Quieted", "member quieted title" );
		description = [NSString stringWithFormat:NSLocalizedString( @"%@ was quieted by %@ in %@.", "bubble message member quieted string" ), ( mbr ? [[mbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[user nickname] stringByEncodingXMLSpecialCharactersAsEntities] ), ( byMbr ? [[byMbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[byUser nickname] stringByEncodingXMLSpecialCharactersAsEntities] ), [[self title] stringByEncodingXMLSpecialCharactersAsEntities]];
		if( [mbr isLocalUser] && [byMbr isLocalUser] ) {
			message = NSLocalizedString( @"You quieted yourself.", "we quieted and can't talk ourself status message" );
			name = @"quieted";
		} else if( [mbr isLocalUser] ) {
			message = [NSString stringWithFormat:NSLocalizedString( @"You were quieted by <span class=\"member\">%@</span>.", "we are now quieted and can't talk status message" ), ( byMbr ? [[byMbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[byUser nickname] stringByEncodingXMLSpecialCharactersAsEntities] )];
			name = @"quieted";
		} else if( [byMbr isLocalUser] ) {
			message = [NSString stringWithFormat:NSLocalizedString( @"<span class=\"member\">%@</span> was quieted by you.", "we quieted someone else in the room status message" ), ( mbr ? [[mbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[user nickname] stringByEncodingXMLSpecialCharactersAsEntities] )];
		} else {
			message = [NSString stringWithFormat:NSLocalizedString( @"<span class=\"member\">%@</span> was quieted by <span class=\"member\">%@</span>.", "user was quieted by someone else in the room status message" ), ( mbr ? [[mbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[user nickname] stringByEncodingXMLSpecialCharactersAsEntities] ), ( byMbr ? [[byMbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[byUser nickname] stringByEncodingXMLSpecialCharactersAsEntities] )];
		}
	} else if( mode == MVChatRoomMemberQuietedMode && ! enabled ) {
		name = @"memberDequieted";
		notificationKey = @"JVChatMemberDequieted";
		title = NSLocalizedString( @"Quieted Room Member Annulled", "quieted member annulled title" );
		description = [NSString stringWithFormat:NSLocalizedString( @"Quieted %@ was annulled by %@ in %@.", "bubble message quieted member annulled string" ), ( mbr ? [[mbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[user nickname] stringByEncodingXMLSpecialCharactersAsEntities] ), ( byMbr ? [[byMbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[byUser nickname] stringByEncodingXMLSpecialCharactersAsEntities] ), [[self title] stringByEncodingXMLSpecialCharactersAsEntities]];
		if( [mbr isLocalUser] && [byMbr isLocalUser] ) {
			message = NSLocalizedString( @"You made yourself no longer quieted.", "we are no longer quieted and can talk ourself status message" );
			name = @"dequieted";
		} else if( [mbr isLocalUser] ) {
			message = [NSString stringWithFormat:NSLocalizedString( @"You are no longer quieted, thanks to <span class=\"member\">%@</span>.", "we are no longer quieted and can talk status message" ), ( byMbr ? [[byMbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[byUser nickname] stringByEncodingXMLSpecialCharactersAsEntities] )];
			name = @"dequieted";
		} else if( [byMbr isLocalUser] ) {
			message = [NSString stringWithFormat:NSLocalizedString( @"<span class=\"member\">%@</span> is no longer quieted because of you.", "a user is no longer quieted because of us status message" ), ( mbr ? [[mbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[user nickname] stringByEncodingXMLSpecialCharactersAsEntities] )];
		} else {
			message = [NSString stringWithFormat:NSLocalizedString( @"<span class=\"member\">%@</span> is no longer quieted because of <span class=\"member\">%@</span>.", "user is no longer quieted because of someone else in the room status message" ), ( mbr ? [[mbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[user nickname] stringByEncodingXMLSpecialCharactersAsEntities] ), ( byMbr ? [[byMbr title] stringByEncodingXMLSpecialCharactersAsEntities] : [[byUser nickname] stringByEncodingXMLSpecialCharactersAsEntities] )];
		}
	}

	[self addEventMessageToDisplay:message withName:name andAttributes:[NSDictionary dictionaryWithObjectsAndKeys:( mbr ? (id) mbr : (id) user ), @"who", ( byMbr ? (id) byMbr : (id) byUser ), @"by", nil]];

	if( title && description && notificationKey ) {
		NSMutableDictionary *context = [NSMutableDictionary dictionary];
		[context setObject:title forKey:@"title"];
		[context setObject:description forKey:@"description"];
		[context setObject:self forKey:@"target"];
		[context setObject:NSStringFromSelector( @selector( activate: ) ) forKey:@"action"];
		[self performNotification:notificationKey withContextInfo:context];
	}
}

- (void) _membersSynced:(NSNotification *) notification {
	NSDictionary *userInfo = [notification userInfo];
	if( userInfo ) {
		NSArray *added = [userInfo objectForKey:@"added"];
		if( added ) {
			MVChatUser *member = nil;
			for( member in added ) {
				if( ! [self chatRoomMemberForUser:member] ) {
					JVChatRoomMember *listItem = [[JVChatRoomMember alloc] initWithRoom:self andUser:member];
					[_sortedMembers addObject:listItem];
					[listItem release];
				}
			}
		}

		NSArray *removed = [userInfo objectForKey:@"removed"];
		if( removed ) {
			MVChatUser *member = nil;
			for( member in removed ) {
				JVChatRoomMember *listItem = [self chatRoomMemberForUser:member];
				if( listItem ) {
					[listItem _detach];
					[_sortedMembers removeObjectIdenticalTo:listItem];
				}
			}
		}
	}

	[self resortMembers];
}

- (void) _bannedMembersSynced:(NSNotification *) notification {
	_banListSynced = YES;
}

- (void) _topicChanged:(id) sender {
	NSAttributedString *topic = [self _convertRawMessage:[[self target] topic]];
	JVChatRoomMember *author = ( [[self target] topicAuthor] ? [self chatRoomMemberForUser:[[self target] topicAuthor]] : nil );
	NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:YES], @"IgnoreFonts", [NSNumber numberWithBool:YES], @"IgnoreFontSizes", nil];
	NSString *topicString = [topic HTMLFormatWithOptions:options];

	if( topic && [[self target] topicAuthor] && sender ) {
		if( [[[self target] topicAuthor] isLocalUser] ) {
			[self addEventMessageToDisplay:[NSString stringWithFormat:NSLocalizedString( @"You changed the topic to \"%@\".", "you changed the topic chat room status message" ), topicString] withName:@"topicChanged" andAttributes:[NSDictionary dictionaryWithObjectsAndKeys:( author ? (id) author : (id) [[self target] topicAuthor] ), @"by", topic, @"topic", nil]];
		} else {
			[self addEventMessageToDisplay:[NSString stringWithFormat:NSLocalizedString( @"Topic changed to \"%@\" by <span class=\"member\">%@</span>.", "topic changed chat room status message" ), topicString, ( author ? [[author title] stringByEncodingXMLSpecialCharactersAsEntities] : [[[[self target] topicAuthor] displayName] stringByEncodingXMLSpecialCharactersAsEntities] )] withName:@"topicChanged" andAttributes:[NSDictionary dictionaryWithObjectsAndKeys:( author ? (id) author : (id) [[self target] topicAuthor] ), @"by", topic, @"topic", nil]];
		}

		NSMethodSignature *signature = [NSMethodSignature methodSignatureWithReturnAndArgumentTypes:@encode( void ), @encode( NSAttributedString * ), @encode( JVChatRoomPanel * ), @encode( JVChatRoomMember * ), nil];
		NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];

		[invocation setSelector:@selector( topicChangedTo:inRoom:by: )];
		[invocation setArgument:&topic atIndex:2];
		[invocation setArgument:&self atIndex:3];
		[invocation setArgument:&author atIndex:4];

		[[MVChatPluginManager defaultManager] makePluginsPerformInvocation:invocation];
	}

	BOOL emptyTopic = NO;
	if( ! [topic length] ) {
		topicString = NSLocalizedString( @"(no chat topic is set)", "no chat topic is set message" );
		emptyTopic = YES;
	}

	id authorArg = ( author ? [author title] : [[[self target] topicAuthor] displayName] );
	NSArray *args = [NSArray arrayWithObjects:topicString, ( authorArg ? authorArg : [NSNull null] ), [NSNumber numberWithBool:emptyTopic], nil];
	[[display windowScriptObject] callWebScriptMethod:@"changeTopic" withArguments:args];
}

- (void) _didClearDisplay:(NSNotification *) notification {
	[self performSelector:@selector(_topicChanged:) withObject:nil afterDelay:0.3];
}
@end

#pragma mark -

@implementation JVChatRoomPanel (JVChatRoomScripting)
- (NSArray *) chatMembers {
	return _sortedMembers;
}

- (JVChatRoomMember *) valueInChatMembersWithName:(NSString *) name {
	return [self firstChatRoomMemberWithName:name];
}

- (JVChatRoomMember *) valueInChatMembersWithUniqueID:(id) identifier {
	JVChatRoomMember *member = nil;

	for( member in _sortedMembers )
		if( [[member uniqueIdentifier] isEqual:identifier] )
			return member;

	return nil;
}

- (NSTextStorage *) scriptTypedTopic {
	NSAttributedString *topic = [self _convertRawMessage:[[self target] topic] withBaseFont:[NSFont systemFontOfSize:11.]];
	return [[[NSTextStorage alloc] initWithAttributedString:topic] autorelease];
}

- (void) setScriptTypedTopic:(NSString *) topic {
	NSAttributedString *attributeMsg = [NSAttributedString attributedStringWithHTMLFragment:topic baseURL:nil];
	[[self target] changeTopic:attributeMsg];
}
@end

#pragma mark -

@implementation JVChatRoomMember (JVChatRoomMemberObjectSpecifier)
- (NSScriptObjectSpecifier *) objectSpecifier {
	id classDescription = [NSClassDescription classDescriptionForClass:[JVChatRoomPanel class]];
	NSScriptObjectSpecifier *container = [[self room] objectSpecifier];
	return [[[NSUniqueIDSpecifier alloc] initWithContainerClassDescription:classDescription containerSpecifier:container key:@"chatMembers" uniqueID:[self uniqueIdentifier]] autorelease];
}
@end
