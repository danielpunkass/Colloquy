#import <ChatCore/MVChatConnection.h>
#import <ChatCore/MVChatRoom.h>
#import <ChatCore/MVChatUser.h>
#import <ChatCore/MVChatPluginManager.h>
#import <ChatCore/MVChatScriptPlugin.h>
#import <ChatCore/NSStringAdditions.h>
#import <ChatCore/NSAttributedStringAdditions.h>
#import <ChatCore/NSMethodSignatureAdditions.h>

#import "JVChatController.h"
#import "JVTabbedChatWindowController.h"
#import "MVApplicationController.h"
#import "MVConnectionsController.h"
#import "JVChatRoom.h"
#import "JVChatRoomMember.h"
#import "JVNotificationController.h"
#import "MVBuddyListController.h"
#import "JVBuddy.h"
#import "JVChatMessage.h"
#import "MVTextView.h"
#import "NSURLAdditions.h"

@interface JVChatRoom (JVChatRoomPrivate)
- (void) _topicChanged:(id) sender;
@end

#pragma mark -

@interface JVDirectChat (JVDirectChatPrivate)
- (NSString *) _selfCompositeName;
- (NSString *) _selfStoredNickname;
- (NSMutableAttributedString *) _convertRawMessage:(NSData *) message;
- (NSMutableAttributedString *) _convertRawMessage:(NSData *) message withBaseFont:(NSFont *) baseFont;
- (void) _didConnect:(NSNotification *) notification;
- (void) _didDisconnect:(NSNotification *) notification;
@end

#pragma mark -

@interface JVChatRoomMember (JVChatMemberPrivate)
- (NSString *) _selfStoredNickname;
- (NSString *) _selfCompositeName;
@end

#pragma mark -

@implementation JVChatRoom
- (id) initWithTarget:(id) target {
	if( ( self = [super initWithTarget:target] ) ) {
		topicLine = nil;
		_sortedMembers = [[NSMutableArray array] retain];
		_nextMessageAlertMembers = [[NSMutableSet set] retain];
		_kickedFromRoom = NO;
		_keepAfterPart = NO;
		_recentlyJoined = NO;

		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector( _partedRoom: ) name:MVChatRoomPartedNotification object:target];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector( _kicked: ) name:MVChatRoomKickedNotification object:target];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector( _gotMessage: ) name:MVChatRoomGotMessageNotification object:target];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector( _memberJoined: ) name:MVChatRoomUserJoinedNotification object:target];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector( _memberParted: ) name:MVChatRoomUserPartedNotification object:target];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector( _memberKicked: ) name:MVChatRoomUserKickedNotification object:target];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector( _roomModeChanged: ) name:MVChatRoomModeChangedNotification object:target];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector( _memberModeChanged: ) name:MVChatRoomUserModeChangedNotification object:target];
	}

	return self;
}

- (void) awakeFromNib {
	[super awakeFromNib];

	[topicLine setDrawsBackground:NO];
	[[topicLine enclosingScrollView] setDrawsBackground:NO];

	NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"irc://%@/%@", [[self connection] server], _target]];
	NSString *path = [[NSString stringWithFormat:@"~/Library/Application Support/Colloquy/Recent Chat Rooms/%@ (%@).inetloc", _target, [[self connection] server]] stringByExpandingTildeInPath];

	[url writeToInternetLocationFile:path];
	[[NSFileManager defaultManager] changeFileAttributes:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:YES], NSFileExtensionHidden, nil] atPath:path];
}

- (void) dealloc {
	if( [[self target] isJoined] && ! [MVApplicationController isTerminating] )
		[[self target] part];

	[[NSNotificationCenter defaultCenter] removeObserver:self];

	[_sortedMembers release];
	[_nextMessageAlertMembers release];

	_sortedMembers = nil;
	_nextMessageAlertMembers = nil;

	[super dealloc];
}

#pragma mark -
#pragma mark Chat View Protocol Support

- (void) willDispose {
	[self partChat:nil];
}

#pragma mark -

- (NSString *) title {
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
		if( [[[MVConnectionsController defaultManager] connectedConnections] count] == 1 )
			return [NSString stringWithFormat:NSLocalizedString( @"%d members", "number of room members information line" ), [_sortedMembers count]];
		else return [[self connection] server];
	}
	return NSLocalizedString( @"disconnected", "disconnected status info line in drawer" );
}

- (NSString *) toolTip {
	NSString *messageCount = @"";
	if( [self newMessagesWaiting] == 0 ) messageCount = NSLocalizedString( @"no messages waiting", "no messages waiting room tooltip" );
	else if( [self newMessagesWaiting] == 1 ) messageCount = NSLocalizedString( @"1 message waiting", "one message waiting room tooltip" );
	else messageCount = [NSString stringWithFormat:NSLocalizedString( @"%d messages waiting", "messages waiting room tooltip" ), [self newMessagesWaiting]];
	return [NSString stringWithFormat:NSLocalizedString( @"%@ (%@)\n%d members\n%@", "room status info tooltip in drawer" ), _target, [[self connection] server], [_sortedMembers count], messageCount];
}

- (NSView *) view {
	if( ! _nibLoaded ) _nibLoaded = [NSBundle loadNibNamed:@"JVChatRoom" owner:self];
	return contents;
}

- (NSString *) identifier {
	return [NSString stringWithFormat:@"Chat Room %@ (%@)", _target, [[self connection] server]];
}

#pragma mark -

- (NSImage *) icon {
	if( [_windowController isMemberOfClass:[JVTabbedChatWindowController class]] )
		return [NSImage imageNamed:@"roomTab"];
	return [NSImage imageNamed:@"room"];
}

- (NSImage *) statusImage {
	if( [_windowController isMemberOfClass:[JVTabbedChatWindowController class]] ) {
		if( _isActive && [[[self view] window] isKeyWindow] ) {
			_newMessageCount = 0;
			_newHighlightMessageCount = 0;
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

- (int) numberOfChildren {
	return [_sortedMembers count];
}

- (id) childAtIndex:(int) index {
	return [_sortedMembers objectAtIndex:index];
}

#pragma mark -

- (NSMenu *) menu {
	NSMenu *menu = [[[NSMenu alloc] initWithTitle:@""] autorelease];
	NSMenuItem *item = nil;

	item = [[[NSMenuItem alloc] initWithTitle:NSLocalizedString( @"Get Info", "get info contextual menu item title" ) action:@selector( getInfo: ) keyEquivalent:@""] autorelease];
	[item setTarget:_windowController];
	[menu addItem:item];

	item = [[[NSMenuItem alloc] initWithTitle:NSLocalizedString( @"Add to Favorites", "add to favorites contextual menu") action:@selector( addToFavorites: ) keyEquivalent:@""] autorelease];
	[item setTarget:self];
	[menu addItem:item];

	[menu addItem:[NSMenuItem separatorItem]];

	item = [[[NSMenuItem alloc] initWithTitle:NSLocalizedString( @"Detach From Window", "detach from window contextual menu item title" ) action:@selector( detachView: ) keyEquivalent:@""] autorelease];
	[item setRepresentedObject:self];
	[item setTarget:[JVChatController defaultManager]];
	[menu addItem:item];

	if( [[self target] isJoined] ) {
		item = [[[NSMenuItem alloc] initWithTitle:NSLocalizedString( @"Leave Room", "leave room contextual menu item title" ) action:@selector( close: ) keyEquivalent:@""] autorelease];
		[item setTarget:self];
		[menu addItem:item];
	} else {
		item = [[[NSMenuItem alloc] initWithTitle:NSLocalizedString( @"Rejoin Room", "rejoin room contextual menu item title" ) action:@selector( joinChat: ) keyEquivalent:@""] autorelease];
		[item setTarget:self];
		[menu addItem:item];
	}

	return [[menu retain] autorelease];
}

#pragma mark -

- (BOOL) acceptsDraggedFileOfType:(NSString *) type {
	return NO;
}

- (void) handleDraggedFile:(NSString *) path {
	[self doesNotRecognizeSelector:_cmd];
}

#pragma mark -
#pragma mark Miscellaneous

- (IBAction) addToFavorites:(id) sender {
	NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"irc://%@/%@", [[self connection] server], _target]];
	NSString *path = [[[NSString stringWithFormat:@"~/Library/Application Support/Colloquy/Favorites/%@ (%@).inetloc", _target, [[self connection] server]] stringByExpandingTildeInPath] retain];

	[url writeToInternetLocationFile:path];
	[[NSFileManager defaultManager] changeFileAttributes:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:YES], NSFileExtensionHidden, nil] atPath:path];
	[[NSWorkspace sharedWorkspace] noteFileSystemChanged:path];

	[MVConnectionsController refreshFavoritesMenu];
}

- (IBAction) changeEncoding:(id) sender {
	[super changeEncoding:sender];
	[[self target] setEncoding:[self encoding]];
	[self _topicChanged:nil];
}

#pragma mark -
#pragma mark Message Handling

- (void) processIncomingMessage:(JVMutableChatMessage *) message {
	if( [message ignoreStatus] == JVNotIgnored && [[message sender] isKindOfClass:[JVChatRoomMember class]] && ! [[message sender] isLocalUser] && ( ! [[[self view] window] isMainWindow] || ! _isActive ) ) {
		NSMutableDictionary *context = [NSMutableDictionary dictionary];
		[context setObject:[NSString stringWithFormat:NSLocalizedString( @"%@ Room Activity", "room activity bubble title" ), [self title]] forKey:@"title"];
		if( [self newMessagesWaiting] == 1 ) [context setObject:[NSString stringWithFormat:NSLocalizedString( @"%@ has 1 message waiting.", "new single room message bubble text" ), [self title]] forKey:@"description"];
		else [context setObject:[NSString stringWithFormat:NSLocalizedString( @"%@ has %d messages waiting.", "new room messages bubble text" ), [self title], [self newMessagesWaiting]] forKey:@"description"];
		[context setObject:[NSImage imageNamed:@"room"] forKey:@"image"];
		[context setObject:[[self windowTitle] stringByAppendingString:@" JVChatRoomActivity"] forKey:@"coalesceKey"];
		[context setObject:self forKey:@"target"];
		[context setObject:NSStringFromSelector( @selector( activate: ) ) forKey:@"action"];
		[[JVNotificationController defaultManager] performNotification:@"JVChatRoomActivity" withContextInfo:context];
	}

	if( [message ignoreStatus] == JVNotIgnored && [_nextMessageAlertMembers containsObject:[message sender]] ) {
		NSMutableDictionary *context = [NSMutableDictionary dictionary];
		[context setObject:[NSString stringWithFormat:NSLocalizedString( @"%@ Replied", "member replied bubble title" ), [[message sender] title]] forKey:@"title"];
		[context setObject:[NSString stringWithFormat:NSLocalizedString( @"%@ has possibly replied to your message.", "new room messages bubble text" ), [[message sender] title]] forKey:@"description"];
		[context setObject:[NSImage imageNamed:@"activityNewImportant"] forKey:@"image"];
		[context setObject:self forKey:@"target"];
		[context setObject:NSStringFromSelector( @selector( activate: ) ) forKey:@"action"];
		[[JVNotificationController defaultManager] performNotification:@"JVChatReplyAfterAddressing" withContextInfo:context];

		[_nextMessageAlertMembers removeObject:[message sender]];
	}

	NSCharacterSet *escapeSet = [NSCharacterSet characterSetWithCharactersInString:@"^[]{}()\\.$*+?|"];
	NSEnumerator *enumerator = [_sortedMembers objectEnumerator];
	NSString *name = nil;

	while( ( name = [[enumerator nextObject] nickname] ) ) {
		NSMutableString *escapedName = [name mutableCopy];
		[escapedName escapeCharactersInSet:escapeSet];

		NSString *pattern = [[NSString alloc] initWithFormat:@"\\b%@\\b", escapedName];
		AGRegex *regex = [AGRegex regexWithPattern:pattern options:AGRegexCaseInsensitive];

		[escapedName release];
		[pattern release];

		NSArray *matches = [regex findAllInString:[message bodyAsPlainText]];
		NSEnumerator *enumerator = [matches objectEnumerator];
		AGRegexMatch *match = nil;

		while( ( match = [enumerator nextObject] ) ) {
			NSRange foundRange = [match range];
			// don't highlight nicks in the middle of a link
			if( ! [[message body] attribute:NSLinkAttributeName atIndex:foundRange.location effectiveRange:NULL] ) {
				NSMutableSet *classes = [[message body] attribute:@"CSSClasses" atIndex:foundRange.location effectiveRange:NULL];
				if( ! classes ) classes = [NSMutableSet setWithObject:@"member"];
				else [classes addObject:@"member"];
				[[message body] addAttribute:@"CSSClasses" value:classes range:foundRange];
			}
		}
	}

	NSMethodSignature *signature = [NSMethodSignature methodSignatureWithReturnAndArgumentTypes:@encode( void ), @encode( JVMutableChatMessage * ), nil];
	NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];

	[invocation setSelector:@selector( processIncomingMessage: )];
	[invocation setArgument:&message atIndex:2];

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
	_recentlyJoined = YES;
	[_sortedMembers removeAllObjects];

	NSEnumerator *enumerator = [[[self target] memberUsers] objectEnumerator];
	MVChatUser *member = nil;

	while( ( member = [enumerator nextObject] ) ) {
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector( _memberNicknameChanged: ) name:MVChatUserNicknameChangedNotification object:member];

		JVChatRoomMember *listItem = [[[JVChatRoomMember alloc] initWithRoom:self andUser:member] autorelease];
		[_sortedMembers addObject:listItem];
	}

	[self resortMembers];

	_cantSendMessages = NO;
	_kickedFromRoom = NO;

	[_windowController reloadListItem:self andChildren:YES];

	NSMethodSignature *signature = [NSMethodSignature methodSignatureWithReturnAndArgumentTypes:@encode( void ), @encode( JVChatRoom * ), nil];
	NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];

	[invocation setSelector:@selector( joinedRoom: )];
	[invocation setArgument:&self atIndex:2];

	[[MVChatPluginManager defaultManager] makePluginsPerformInvocation:invocation];

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector( _selfNicknameChanged: ) name:MVChatConnectionNicknameAcceptedNotification object:[self connection]];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector( _topicChanged: ) name:MVChatRoomTopicChangedNotification object:[self target]];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector( _memberBanned: ) name:MVChatRoomUserBannedNotification object:[self target]];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector( _memberBanRemoved: ) name:MVChatRoomUserBanRemovedNotification object:[self target]];

	[self performSelector:@selector( _resetRecentlyJoinedStatus ) withObject:nil afterDelay:1.];
}	

- (void) parting {
	if( [[self target] isJoined] ) {
		_recentlyJoined = NO;
		_cantSendMessages = YES;

		NSMethodSignature *signature = [NSMethodSignature methodSignatureWithReturnAndArgumentTypes:@encode( void ), @encode( JVChatRoom * ), nil];
		NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];

		[invocation setSelector:@selector( partingFromRoom: )];
		[invocation setArgument:&self atIndex:2];

		[[MVChatPluginManager defaultManager] makePluginsPerformInvocation:invocation];

		[[NSNotificationCenter defaultCenter] removeObserver:self name:MVChatConnectionNicknameAcceptedNotification object:[self connection]];
		[[NSNotificationCenter defaultCenter] removeObserver:self name:MVChatRoomTopicChangedNotification object:[self target]];
		[[NSNotificationCenter defaultCenter] removeObserver:self name:MVChatRoomUserBannedNotification object:[self target]];
		[[NSNotificationCenter defaultCenter] removeObserver:self name:MVChatRoomUserBanRemovedNotification object:[self target]];
	}
}

#pragma mark -

- (void) joinChat:(id) sender {
	if( ! [[self target] isJoined] ) [[self target] join];
}

- (void) partChat:(id) sender {
	if( [[self target] isJoined] ) {
		[self parting];
		[[self target] part];
	}
}

#pragma mark -

- (BOOL) keepAfterPart {
	return _keepAfterPart;
}

- (void) setKeepAfterPart:(BOOL) keep {
	_keepAfterPart = keep;
}

#pragma mark -
#pragma mark User List Access

- (JVChatRoomMember *) firstChatRoomMemberWithName:(NSString *) name {
	NSEnumerator *enumerator = [_sortedMembers objectEnumerator];
	JVChatRoomMember *member = nil;

	while( ( member = [enumerator nextObject] ) ) {
		if( [[member nickname] caseInsensitiveCompare:name] == NSOrderedSame ) {
			return member;
		} else if( [[member realName] caseInsensitiveCompare:name] == NSOrderedSame ) {
			return member;
		} else if( [[member title] caseInsensitiveCompare:name] == NSOrderedSame ) {
			return member;
		}
	}

	return nil;
}

- (JVChatRoomMember *) chatRoomMemberForUser:(MVChatUser *) user {
	NSEnumerator *enumerator = [_sortedMembers objectEnumerator];
	JVChatRoomMember *member = nil;

	while( ( member = [enumerator nextObject] ) )
		if( [[member user] isEqualToChatUser:user] )
			return member;

	return nil;
}

- (JVChatRoomMember *) localChatRoomMember {
	NSEnumerator *enumerator = [_sortedMembers objectEnumerator];
	JVChatRoomMember *member = nil;

	while( ( member = [enumerator nextObject] ) )
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
	if( [[[element objectForKey:WebElementLinkURLKey] scheme] isEqualToString:@"member"] ) {
		NSMutableArray *ret = [NSMutableArray array];
		NSString *identifier = [[[element objectForKey:WebElementLinkURLKey] resourceSpecifier] stringByDecodingIllegalURLCharacters];
		MVChatUser *user = [[self connection] chatUserWithUniqueIdentifier:identifier];
		JVChatRoomMember *mbr = [self chatRoomMemberForUser:user];
		NSMenuItem *item = nil;

		if( mbr ) {
			NSEnumerator *enumerator = [[[mbr menu] itemArray] objectEnumerator];
			while( ( item = [enumerator nextObject] ) ) [ret addObject:[[item copy] autorelease]];

			NSMethodSignature *signature = [NSMethodSignature methodSignatureWithReturnAndArgumentTypes:@encode( NSArray * ), @encode( id ), @encode( id ), nil];
			NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];

			[invocation setSelector:@selector( contextualMenuItemsForObject:inView: )];
			[invocation setArgument:&mbr atIndex:2];
			[invocation setArgument:&self atIndex:3];

			NSArray *results = [[MVChatPluginManager defaultManager] makePluginsPerformInvocation:invocation];
			if( [results count] ) {
				[ret addObject:[NSMenuItem separatorItem]];

				NSArray *items = nil;
				enumerator = [results objectEnumerator];
				while( ( items = [enumerator nextObject] ) ) {
					if( ! [items respondsToSelector:@selector( objectEnumerator )] ) continue;
					NSEnumerator *ienumerator = [items objectEnumerator];
					while( ( item = [ienumerator nextObject] ) )
						if( [item isKindOfClass:[NSMenuItem class]] ) [ret addObject:item];
				}

				if( [[ret lastObject] isSeparatorItem] )
					[ret removeObjectIdenticalTo:[ret lastObject]];
			}
		} else {
			item = [[[NSMenuItem alloc] initWithTitle:NSLocalizedString( @"Send Message", "send message contextual menu") action:NULL keyEquivalent:@""] autorelease];
			[item setRepresentedObject:user];
			[item setTarget:self];
			[item setAction:@selector( _startChatWithNonMember: )];
			[ret addObject:item];
		}

		return ret;
	}

	return [super webView:sender contextMenuItemsForElement:element defaultMenuItems:defaultMenuItems];
}

- (void) webView:(WebView *) sender decidePolicyForNavigationAction:(NSDictionary *) actionInformation request:(NSURLRequest *) request frame:(WebFrame *) frame decisionListener:(id <WebPolicyDecisionListener>) listener {
	if( [[[actionInformation objectForKey:WebActionOriginalURLKey] scheme] isEqualToString:@"member"] ) {
		NSString *identifier = [[[actionInformation objectForKey:WebActionOriginalURLKey] resourceSpecifier] stringByDecodingIllegalURLCharacters];
		MVChatUser *user = [[self connection] chatUserWithUniqueIdentifier:identifier];

		if( ! [user isLocalUser] )
			[[JVChatController defaultManager] chatViewControllerForUser:user ifExists:NO];

		[listener ignore];
	} else {
		[super webView:sender decidePolicyForNavigationAction:actionInformation request:request frame:frame decisionListener:listener];
	}
}

#pragma mark -
#pragma mark TextView/Input Support

- (NSArray *) completionsFor:(NSString *) inFragment {
	NSEnumerator *enumerator = [_sortedMembers objectEnumerator];
	NSMutableArray *possibleNicks = [NSMutableArray array];
	NSString *name = nil;

	while( ( name = [[enumerator nextObject] nickname] ) )
		if( [name rangeOfString:inFragment options:( NSCaseInsensitiveSearch | NSAnchoredSearch )].location == 0 )
			[possibleNicks addObject:name];

	return possibleNicks;
}

- (NSArray *) textView:(NSTextView *) textView completions:(NSArray *) words forPartialWordRange:(NSRange) charRange indexOfSelectedItem:(int *) index {
	NSString *search = [[[send textStorage] string] substringWithRange:charRange];
	NSEnumerator *enumerator = [_sortedMembers objectEnumerator];
	NSMutableArray *ret = [NSMutableArray array];
	NSString *name = nil;
	unsigned int length = [search length];
	while( length && ( name = [[enumerator nextObject] nickname] ) ) {
		if( length <= [name length] && [search caseInsensitiveCompare:[name substringToIndex:length]] == NSOrderedSame ) {
			[ret addObject:name];
		}
	}
	[ret addObjectsFromArray:words];
	return ret;
}

#pragma mark -
#pragma mark Toolbar Support
- (NSToolbar *) toolbar {
	NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:@"Chat Room"];
	[toolbar setDelegate:self];
	[toolbar setAllowsUserCustomization:YES];
	[toolbar setAutosavesConfiguration:YES];

//	[_toolbarItems release];
//	_toolbarItems = [[NSMutableDictionary dictionary] retain];

	return [toolbar autorelease];
}

- (NSToolbarItem *) toolbar:(NSToolbar *) toolbar itemForItemIdentifier:(NSString *) identifier willBeInsertedIntoToolbar:(BOOL) willBeInserted {
	NSToolbarItem *toolbarItem = nil;
	if( toolbarItem ) return toolbarItem;
	else return [super toolbar:toolbar itemForItemIdentifier:identifier willBeInsertedIntoToolbar:willBeInserted];
}

- (NSArray *) toolbarDefaultItemIdentifiers:(NSToolbar *) toolbar {
	NSMutableArray *list = [NSMutableArray arrayWithArray:[super toolbarAllowedItemIdentifiers:toolbar]];
	return list;
}

- (NSArray *) toolbarAllowedItemIdentifiers:(NSToolbar *) toolbar {
	NSMutableArray *list = [NSMutableArray arrayWithArray:[super toolbarAllowedItemIdentifiers:toolbar]];
	return list;
}

- (BOOL) validateToolbarItem:(NSToolbarItem *) toolbarItem {
	return [super validateToolbarItem:toolbarItem];
}
@end

#pragma mark -

@implementation JVChatRoom (JVChatRoomPrivate)
- (void) _didConnect:(NSNotification *) notification {
	[[self target] join];
	[super _didConnect:notification];
	_cantSendMessages = YES;
}

- (void) _didDisconnect:(NSNotification *) notification {
	_kickedFromRoom = NO;
	[super _didDisconnect:notification];
	[_windowController reloadListItem:self andChildren:YES];

	[[NSNotificationCenter defaultCenter] removeObserver:self name:MVChatConnectionNicknameAcceptedNotification object:[self connection]];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:MVChatRoomTopicChangedNotification object:[self target]];
}

- (char *) _classificationForUser:(MVChatUser *) user {
	JVChatRoomMember *member = [self chatRoomMemberForUser:user];
	if( [member serverOperator] ) return "server operator";
	else if( [member operator] ) return "operator";
	else if( [member halfOperator] ) return "half operator";
	else if( [member voice] ) return "voice";
	return "normal";
}

- (void) _partedRoom:(NSNotification *) notification {
	if( ! [[self connection] isConnected] ) return;

	[self parting];

	if( ! [self keepAfterPart] )
		[self close:nil];
}

- (void) _roomModeChanged:(NSNotification *) notification {
	MVChatUser *user = [[notification userInfo] objectForKey:@"by"];

	if( ! user ) return;
	if( [[self connection] type] == MVChatConnectionIRCType && [[user nickname] rangeOfString:@"."].location != NSNotFound )
		return; // a server telling us the initial modes when we join, ignore these on IRC connections

	JVChatRoomMember *mbr = [self chatRoomMemberForUser:user];

	unsigned int changedModes = [[[notification userInfo] objectForKey:@"changedModes"] unsignedIntValue];
	unsigned int newModes = [[self target] modes];

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
					message = [NSString stringWithFormat:NSLocalizedString( @"%@ made this room private.", "someone else private room status message" ), ( mbr ? [mbr title] : [user nickname] )];
				}
			} else {
				if( [mbr isLocalUser] ) {
					message = NSLocalizedString( @"You made this room public.", "public room status message" );
				} else {
					message = [NSString stringWithFormat:NSLocalizedString( @"%@ made this room public.", "someone else public room status message" ), ( mbr ? [mbr title] : [user nickname] )];
				}
			}
		} else if( changedModes & MVChatRoomSecretMode ) {
			changedModes &= ~MVChatRoomSecretMode;
			mode = @"chatRoomSecretMode";
			if( newModes & MVChatRoomSecretMode ) {
				if( [mbr isLocalUser] ) {
					message = NSLocalizedString( @"You made this room secret.", "secret room status message" );
				} else {
					message = [NSString stringWithFormat:NSLocalizedString( @"%@ made this room secret.", "someone else secret room status message" ), ( mbr ? [mbr title] : [user nickname] )];
				}
			} else {
				if( [mbr isLocalUser] ) {
					message = NSLocalizedString( @"You made this room no longer a secret.", "no longer secret room status message" );
				} else {
					message = [NSString stringWithFormat:NSLocalizedString( @"%@ made this room no longer a secret.", "someone else no longer secret room status message" ), ( mbr ? [mbr title] : [user nickname] )];
				}
			}
		} else if( changedModes & MVChatRoomInviteOnlyMode ) {
			changedModes &= ~MVChatRoomInviteOnlyMode;
			mode = @"chatRoomInviteOnlyMode";
			if( newModes & MVChatRoomInviteOnlyMode ) {
				if( [mbr isLocalUser] ) {
					message = NSLocalizedString( @"You made this room invite only.", "invite only room status message" );
				} else {
					message = [NSString stringWithFormat:NSLocalizedString( @"%@ made this room invite only.", "someone else invite only room status message" ), ( mbr ? [mbr title] : [user nickname] )];
				}
			} else {
				if( [mbr isLocalUser] ) {
					message = NSLocalizedString( @"You made this room no longer invite only.", "no longer invite only room status message" );
				} else {
					message = [NSString stringWithFormat:NSLocalizedString( @"%@ made this room no longer invite only.", "someone else no longer invite only room status message" ), ( mbr ? [mbr title] : [user nickname] )];
				}
			}
		} else if( changedModes & MVChatRoomNormalUsersSilencedMode ) {
			changedModes &= ~MVChatRoomNormalUsersSilencedMode;
			mode = @"chatRoomNormalUsersSilencedMode";
			if( newModes & MVChatRoomNormalUsersSilencedMode ) {
				if( [mbr isLocalUser] ) {
					message = NSLocalizedString( @"You made this room moderated for normal users.", "moderated for normal users room status message" );
				} else {
					message = [NSString stringWithFormat:NSLocalizedString( @"%@ made this room moderated for normal users.", "someone else moderated for normal users room status message" ), ( mbr ? [mbr title] : [user nickname] )];
				}
			} else {
				if( [mbr isLocalUser] ) {
					message = NSLocalizedString( @"You made this room no longer moderated for normal users.", "no longer moderated for normal users room status message" );
				} else {
					message = [NSString stringWithFormat:NSLocalizedString( @"%@ made this room no longer moderated for normal users.", "someone else no longer moderated for normal users room status message" ), ( mbr ? [mbr title] : [user nickname] )];
				}
			}
		} else if( changedModes & MVChatRoomOperatorsSilencedMode ) {
			changedModes &= ~MVChatRoomOperatorsSilencedMode;
			mode = @"chatRoomOperatorsSilencedMode";
			if( newModes & MVChatRoomOperatorsSilencedMode ) {
				if( [mbr isLocalUser] ) {
					message = NSLocalizedString( @"You made this room moderated for operators.", "moderated for operators room status message" );
				} else {
					message = [NSString stringWithFormat:NSLocalizedString( @"%@ made this room moderated for operators.", "someone else moderated for operators room status message" ), ( mbr ? [mbr title] : [user nickname] )];
				}
			} else {
				if( [mbr isLocalUser] ) {
					message = NSLocalizedString( @"You made this room no longer moderated for operators.", "no longer moderated for operators room status message" );
				} else {
					message = [NSString stringWithFormat:NSLocalizedString( @"%@ made this room no longer moderated for operators.", "someone else no longer moderated for operators room status message" ), ( mbr ? [mbr title] : [user nickname] )];
				}
			}
		} else if( changedModes & MVChatRoomOperatorsOnlySetTopicMode ) {
			changedModes &= ~MVChatRoomOperatorsOnlySetTopicMode;
			mode = @"MVChatRoomOperatorsOnlySetTopicMode";
			if( newModes & MVChatRoomOperatorsOnlySetTopicMode ) {
				if( [mbr isLocalUser] ) {
					message = NSLocalizedString( @"You changed this room to require operator status to change the topic.", "require op to set topic room status message" );
				} else {
					message = [NSString stringWithFormat:NSLocalizedString( @"%@ changed this room to require operator status to change the topic.", "someone else required op to set topic room status message" ), ( mbr ? [mbr title] : [user nickname] )];
				}
			} else {
				if( [mbr isLocalUser] ) {
					message = NSLocalizedString( @"You changed this room to allow anyone to change the topic.", "don't require op to set topic room status message" );
				} else {
					message = [NSString stringWithFormat:NSLocalizedString( @"%@ changed this room to allow anyone to change the topic.", "someone else don't required op to set topic room status message" ), ( mbr ? [mbr title] : [user nickname] )];
				}
			}
		} else if( changedModes & MVChatRoomNoOutsideMessagesMode ) {
			changedModes &= ~MVChatRoomNoOutsideMessagesMode;
			mode = @"chatRoomNoOutsideMessagesMode";
			if( newModes & MVChatRoomNoOutsideMessagesMode ) {
				if( [mbr isLocalUser] ) {
					message = NSLocalizedString( @"You changed this room to prohibit outside messages.", "prohibit outside messages room status message" );
				} else {
					message = [NSString stringWithFormat:NSLocalizedString( @"%@ changed this room to prohibit outside messages.", "someone else prohibit outside messages room status message" ), ( mbr ? [mbr title] : [user nickname] )];
				}
			} else {
				if( [mbr isLocalUser] ) {
					message = NSLocalizedString( @"You changed this room to permit outside messages.", "permit outside messages room status message" );
				} else {
					message = [NSString stringWithFormat:NSLocalizedString( @"%@ changed this room to permit outside messages.", "someone else permit outside messages room status message" ), ( mbr ? [mbr title] : [user nickname] )];
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
					message = [NSString stringWithFormat:NSLocalizedString( @"%@ changed this room to require a password of \"%@\".", "someone else password required room status message" ), ( mbr ? [mbr title] : [user nickname] ), parameter];
				}
			} else {
				if( [mbr isLocalUser] ) {
					message = NSLocalizedString( @"You changed this room to no longer require a password.", "no longer passworded room status message" );
				} else {
					message = [NSString stringWithFormat:NSLocalizedString( @"%@ changed this room to no longer require a password.", "someone else no longer passworded room status message" ), ( mbr ? [mbr title] : [user nickname] )];
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
					message = [NSString stringWithFormat:NSLocalizedString( @"%@ set a limit on the number of room members to %@.", "someone else member limit room status message" ), ( mbr ? [mbr title] : [user nickname] ), parameter];
				}
			} else {
				if( [mbr isLocalUser] ) {
					message = NSLocalizedString( @"You removed the room member limit.", "no member limit room status message" );
				} else {
					message = [NSString stringWithFormat:NSLocalizedString( @"%@ removed the room member limit", "someone else no member limit room status message" ), ( mbr ? [mbr title] : [user nickname] )];
				}
			}
		}

		if( message && mode ) [self addEventMessageToDisplay:message withName:@"modeChange" andAttributes:[NSDictionary dictionaryWithObjectsAndKeys:( mbr ? [mbr title] : [user nickname] ), @"by", [user nickname], @"nickname", ( [mbr hostmask] ? (id) [mbr hostmask] : (id) [NSNull null] ), @"mask", mode, @"mode", ( [[[notification userInfo] objectForKey:@"enabled"] boolValue] ? @"yes" : @"no" ), @"enabled", parameter, @"parameter", nil]];
	}
}

- (void) _selfNicknameChanged:(NSNotification *) notification {
	[self resortMembers];
	[self addEventMessageToDisplay:[NSString stringWithFormat:NSLocalizedString( @"You are now known as <span class=\"member\">%@</span>.", "you changed nicknames" ), [[self connection] nickname]] withName:@"newNickname" andAttributes:[NSDictionary dictionaryWithObjectsAndKeys:[[self connection] nickname], @"nickname", nil]];
}

- (void) _memberNicknameChanged:(NSNotification *) notification {
	[self resortMembers];

	JVChatRoomMember *member = [self chatRoomMemberForUser:[notification object]];
	NSString *oldNickname = [[notification userInfo] objectForKey:@"oldNickname"];

	[self addEventMessageToDisplay:[NSString stringWithFormat:NSLocalizedString( @"%@ is now known as <span class=\"member\">%@</span>.", "user has changed nicknames" ), oldNickname, [member nickname]] withName:@"memberNewNickname" andAttributes:[NSDictionary dictionaryWithObjectsAndKeys:[member title], @"name", oldNickname, @"old", [member nickname], @"new", nil]];
}

- (void) _gotMessage:(NSNotification *) notification {
	[self addMessageToDisplay:[[notification userInfo] objectForKey:@"message"] fromUser:[[notification userInfo] objectForKey:@"user"] asAction:[[[notification userInfo] objectForKey:@"action"] boolValue]];
}

- (void) _memberJoined:(NSNotification *) notification {
	MVChatUser *user = [[notification userInfo] objectForKey:@"user"];
	JVChatRoomMember *listItem = [[[JVChatRoomMember alloc] initWithRoom:self andUser:user] autorelease];
	[_sortedMembers addObject:listItem];

	[self resortMembers];

	NSString *name = [listItem title];
	NSString *message = [NSString stringWithFormat:NSLocalizedString( @"<span class=\"member\">%@</span> joined the chat room.", "a user has join a chat room status message" ), name];
	[self addEventMessageToDisplay:message withName:@"memberJoined" andAttributes:[NSDictionary dictionaryWithObjectsAndKeys:[user nickname], @"nickname", name, @"who", ( [listItem hostmask] ? (id) [listItem hostmask] : (id) [NSNull null] ), @"mask", nil]];

	NSMethodSignature *signature = [NSMethodSignature methodSignatureWithReturnAndArgumentTypes:@encode( void ), @encode( JVChatRoomMember * ), @encode( JVChatRoom * ), nil];
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
	[[JVNotificationController defaultManager] performNotification:@"JVChatMemberJoinedRoom" withContextInfo:context];
}

- (void) _memberParted:(NSNotification *) notification {
	MVChatUser *user = [[notification userInfo] objectForKey:@"user"];
	JVChatRoomMember *mbr = [self chatRoomMemberForUser:user];
	if( ! mbr ) return;

	NSMutableAttributedString *rstring = [self _convertRawMessage:[[notification userInfo] objectForKey:@"reason"]];

	NSMethodSignature *signature = [NSMethodSignature methodSignatureWithReturnAndArgumentTypes:@encode( void ), @encode( JVChatRoomMember * ), @encode( JVChatRoom * ), @encode( NSAttributedString * ), nil];
	NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];

	[invocation setSelector:@selector( memberParted:fromRoom:forReason: )];
	[invocation setArgument:&mbr atIndex:2];
	[invocation setArgument:&self atIndex:3];
	[invocation setArgument:&rstring atIndex:4];

	[[MVChatPluginManager defaultManager] makePluginsPerformInvocation:invocation];

	if( [_windowController selectedListItem] == mbr )
		[_windowController showChatViewController:[_windowController activeChatViewController]];

	NSString *name = [mbr title];
	NSString *message = [NSString stringWithFormat:NSLocalizedString( @"<span class=\"member\">%@</span> left the chat room.", "a user has left the chat room status message" ), name];

	[self addEventMessageToDisplay:message withName:@"memberParted" andAttributes:[NSDictionary dictionaryWithObjectsAndKeys:( name ? name : [user nickname] ), @"who", [user nickname], @"nickname", ( [mbr hostmask] ? (id) [mbr hostmask] : (id) [NSNull null] ), @"mask", ( rstring ? (id) rstring : (id) [NSNull null] ), @"reason", nil]];

	NSMutableDictionary *context = [NSMutableDictionary dictionary];
	[context setObject:NSLocalizedString( @"Room Member Left", "member left title" ) forKey:@"title"];
	[context setObject:[NSString stringWithFormat:NSLocalizedString( @"%@ left the chat room %@.", "bubble message member left string" ), name, _target] forKey:@"description"];
	[context setObject:self forKey:@"target"];
	[context setObject:NSStringFromSelector( @selector( activate: ) ) forKey:@"action"];
	[[JVNotificationController defaultManager] performNotification:@"JVChatMemberLeftRoom" withContextInfo:context];

	[_sortedMembers removeObjectIdenticalTo:mbr];
	[_windowController reloadListItem:self andChildren:YES];
}

- (void) _kicked:(NSNotification *) notification {
	MVChatUser *byUser = [[notification userInfo] objectForKey:@"byUser"];
	JVChatRoomMember *byMbr = [self chatRoomMemberForUser:byUser];
	NSMutableAttributedString *rstring = [self _convertRawMessage:[[notification userInfo] objectForKey:@"reason"]];
	NSString *message = [NSString stringWithFormat:NSLocalizedString( @"You were kicked from the chat room by %@.", "you were removed by force from a chat room status message" ), ( byMbr ? [byMbr title] : [byUser nickname] )];

	[self addEventMessageToDisplay:message withName:@"kicked" andAttributes:[NSDictionary dictionaryWithObjectsAndKeys:( [byMbr title] ? [byMbr title] : [byUser nickname] ), @"by", [byUser nickname], @"by-nickname", ( rstring ? (id) rstring : (id) [NSNull null] ), @"reason", nil]];

	NSMethodSignature *signature = [NSMethodSignature methodSignatureWithReturnAndArgumentTypes:@encode( void ), @encode( JVChatRoom * ), @encode( JVChatRoomMember * ), @encode( NSAttributedString * ), nil];
	NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];

	[invocation setSelector:@selector( kickedFromRoom:by:forReason: )];
	[invocation setArgument:&self atIndex:2];
	[invocation setArgument:&byMbr atIndex:3];
	[invocation setArgument:&rstring atIndex:4];

	[[MVChatPluginManager defaultManager] makePluginsPerformInvocation:invocation];

	JVChatRoomMember *mbr = [[[self localChatRoomMember] retain] autorelease];
	if( [_windowController selectedListItem] == mbr )
		[_windowController showChatViewController:[_windowController activeChatViewController]];

	[_sortedMembers removeObjectIdenticalTo:mbr];
	[_windowController reloadListItem:self andChildren:YES];

	_kickedFromRoom = YES;
	_cantSendMessages = YES;

	NSMutableDictionary *context = [NSMutableDictionary dictionary];
	[context setObject:NSLocalizedString( @"You Were Kicked", "member kicked title" ) forKey:@"title"];
	[context setObject:[NSString stringWithFormat:NSLocalizedString( @"You were kicked from %@ by %@.", "bubble message member kicked string" ), [self title], ( byMbr ? [byMbr title] : [byUser nickname] )] forKey:@"description"];
	[context setObject:self forKey:@"target"];
	[context setObject:NSStringFromSelector( @selector( activate: ) ) forKey:@"action"];
	[[JVNotificationController defaultManager] performNotification:@"JVChatMemberKicked" withContextInfo:context];

	[self showAlert:NSGetInformationalAlertPanel( NSLocalizedString( @"You have been kicked from the chat room.", "you were removed by force from a chat room error message title" ), NSLocalizedString( @"You have been kicked from the chat room by %@ with the reason \"%@\" and cannot send further messages without rejoining.", "you were removed by force from a chat room error message" ), @"OK", nil, nil, ( byMbr ? [byMbr title] : [byUser nickname] ), ( rstring ? [rstring string] : @"" ) ) withName:nil];
}

- (void) _memberKicked:(NSNotification *) notification {
	MVChatUser *user = [[notification userInfo] objectForKey:@"user"];
	JVChatRoomMember *mbr = [[[self chatRoomMemberForUser:user] retain] autorelease];
	if( ! mbr ) return;

	MVChatUser *byUser = [[notification userInfo] objectForKey:@"byUser"];
	JVChatRoomMember *byMbr = [self chatRoomMemberForUser:byUser];
	NSMutableAttributedString *rstring = [self _convertRawMessage:[[notification userInfo] objectForKey:@"reason"]];

	NSMethodSignature *signature = [NSMethodSignature methodSignatureWithReturnAndArgumentTypes:@encode( void ), @encode( JVChatRoomMember * ), @encode( JVChatRoom * ), @encode( JVChatRoomMember * ), @encode( NSAttributedString * ), nil];
	NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];

	[invocation setSelector:@selector( memberKicked:fromRoom:by:forReason: )];
	[invocation setArgument:&mbr atIndex:2];
	[invocation setArgument:&self atIndex:3];
	[invocation setArgument:&byMbr atIndex:4];
	[invocation setArgument:&rstring atIndex:5];

	[[MVChatPluginManager defaultManager] makePluginsPerformInvocation:invocation];

	if( [_windowController selectedListItem] == mbr )
		[_windowController showChatViewController:[_windowController activeChatViewController]];

	[_sortedMembers removeObjectIdenticalTo:mbr];
	[_windowController reloadListItem:self andChildren:YES];

	NSString *message = nil;
	if( [byMbr isLocalUser] ) {
		message = [NSString stringWithFormat:NSLocalizedString( @"You kicked %@ from the chat room.", "you removed a user by force from a chat room status message" ), ( mbr ? [mbr title] : [user nickname] )];
	} else {
		message = [NSString stringWithFormat:NSLocalizedString( @"%@ was kicked from the chat room by <span class=\"member\">%@</span>.", "user has been removed by force from a chat room status message" ), ( mbr ? [mbr title] : [user nickname] ), ( byMbr ? [byMbr title] : [byUser nickname] )];
	}

	[self addEventMessageToDisplay:message withName:@"memberKicked" andAttributes:[NSDictionary dictionaryWithObjectsAndKeys:( [byMbr title] ? [byMbr title] : [byUser nickname] ), @"by", [byUser nickname], @"by-nickname", ( [mbr title] ? [mbr title] : [user nickname] ), @"who", [user nickname], @"who-nickname", ( [mbr hostmask] ? (id) [mbr hostmask] : (id) [NSNull null] ), @"mask", ( rstring ? (id) rstring : (id) [NSNull null] ), @"reason", nil]];

	NSMutableDictionary *context = [NSMutableDictionary dictionary];
	[context setObject:NSLocalizedString( @"Room Member Kicked", "member kicked title" ) forKey:@"title"];
	[context setObject:[NSString stringWithFormat:NSLocalizedString( @"%@ was kicked from %@ by %@.", "bubble message member kicked string" ), ( mbr ? [mbr title] : [user nickname] ), [self title], ( byMbr ? [byMbr title] : [byUser nickname] )] forKey:@"description"];
	[context setObject:self forKey:@"target"];
	[context setObject:NSStringFromSelector( @selector( activate: ) ) forKey:@"action"];
	[[JVNotificationController defaultManager] performNotification:@"JVChatMemberKicked" withContextInfo:context];
}

- (void) _memberBanned:(NSNotification *) notification {
	if( _recentlyJoined ) return;

	MVChatUser *byUser = [[notification userInfo] objectForKey:@"byUser"];
	JVChatRoomMember *byMbr = [self chatRoomMemberForUser:byUser];

	MVChatUser *ban = [[notification userInfo] objectForKey:@"user"];

	NSString *message = nil;
	if( [byMbr isLocalUser] ) {
		message = [NSString stringWithFormat:NSLocalizedString( @"You set a ban on %@.", "you set a ban chat room status message" ), ban];
	} else {
		message = [NSString stringWithFormat:NSLocalizedString( @"<span class=\"member\">%@</span> set a ban on %@.", "user set a ban chat room status message" ), ( byMbr ? [byMbr title] : [byUser nickname] ), [ban description]];
	}

	[self addEventMessageToDisplay:message withName:@"memberBanned" andAttributes:[NSDictionary dictionaryWithObjectsAndKeys:( byMbr ? [byMbr title] : [byUser nickname] ), @"by", [byUser nickname], @"by-nickname", ban, @"ban", nil]];
}

- (void) _memberBanRemoved:(NSNotification *) notification {
	MVChatUser *byUser = [[notification userInfo] objectForKey:@"byUser"];
	JVChatRoomMember *byMbr = [self chatRoomMemberForUser:byUser];

	MVChatUser *ban = [[notification userInfo] objectForKey:@"user"];

	NSString *message = nil;
	if( [byMbr isLocalUser] ) {
		message = [NSString stringWithFormat:NSLocalizedString( @"You removed the ban on %@.", "you removed a ban chat room status message" ), [ban description]];
	} else {
		message = [NSString stringWithFormat:NSLocalizedString( @"<span class=\"member\">%@</span> removed the ban on %@.", "user removed a ban chat room status message" ), ( byMbr ? [byMbr title] : [byUser nickname] ), [ban description]];
	}

	[self addEventMessageToDisplay:message withName:@"banRemoved" andAttributes:[NSDictionary dictionaryWithObjectsAndKeys:( byMbr ? [byMbr title] : [byUser nickname] ), @"by", [byUser nickname], @"by-nickname", [ban description], @"ban", nil]];
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
	unsigned long mode = [[[notification userInfo] objectForKey:@"mode"] unsignedLongValue];
	BOOL enabled = [[[notification userInfo] objectForKey:@"enabled"] boolValue];

	if( mode == MVChatRoomMemberFounderMode && enabled ) {
		name = @"memberPromotedToFounder";
		if( [mbr isLocalUser] && [byMbr isLocalUser] ) { // only server oppers would ever see this
			message = NSLocalizedString( @"You promoted yourself to room founder.", "we gave ourself the chat room founder privilege status message" );
			name = @"promotedToFounder";
		} else if( [mbr isLocalUser] ) {
			message = [NSString stringWithFormat:NSLocalizedString( @"You were promoted to room founder by <span class=\"member\">%@</span>.", "we are now a chat room founder status message" ), ( byMbr ? [byMbr title] : [byUser nickname] )];
			name = @"promotedToFounder";
		} else if( [byMbr isLocalUser] ) {
			message = [NSString stringWithFormat:NSLocalizedString( @"<span class=\"member\">%@</span> was promoted to room founder by you.", "we gave user chat room founder status message" ), ( mbr ? [mbr title] : [user nickname] )];
		} else {
			message = [NSString stringWithFormat:NSLocalizedString( @"<span class=\"member\">%@</span> was promoted to room founder by <span class=\"member\">%@</span>.", "user is now a chat room founder status message" ), ( mbr ? [mbr title] : [user nickname] ), ( byMbr ? [byMbr title] : [byUser nickname] )];
		}
	} else if( mode == MVChatRoomMemberOperatorMode && ! enabled ) {
		name = @"memberDemotedFromFounder";
		if( [mbr isLocalUser] && [byMbr isLocalUser] ) {
			message = NSLocalizedString( @"You demoted yourself from room founder.", "we removed our chat room founder privilege status message" );
			name = @"demotedFromFounder";
		} else if( [mbr isLocalUser] ) {
			message = [NSString stringWithFormat:NSLocalizedString( @"You were demoted from room founder by <span class=\"member\">%@</span>.", "we are no longer a chat room founder status message" ), ( byMbr ? [byMbr title] : [byUser nickname] )];
			name = @"demotedFromFounder";
		} else if( [byMbr isLocalUser] ) {
			message = [NSString stringWithFormat:NSLocalizedString( @"<span class=\"member\">%@</span> was demoted from room founder by you.", "we removed user's chat room founder status message" ), ( mbr ? [mbr title] : [user nickname] )];
		} else {
			message = [NSString stringWithFormat:NSLocalizedString( @"<span class=\"member\">%@</span> was demoted from room founder by <span class=\"member\">%@</span>.", "user is no longer a chat room founder status message" ), ( mbr ? [mbr title] : [user nickname] ), ( byMbr ? [byMbr title] : [byUser nickname] )];
		}
	} else if( mode == MVChatRoomMemberOperatorMode && enabled ) {
		name = @"memberPromotedToOperator";
		notificationKey = @"JVChatMemberPromoted";
		title = NSLocalizedString( @"New Room Operator", "member promoted title" );
		description = [NSString stringWithFormat:NSLocalizedString( @"%@ was promoted to operator by %@ in %@.", "bubble message member operator promotion string" ), ( mbr ? [mbr title] : [user nickname] ), ( byMbr ? [byMbr title] : [byUser nickname] ), [self title]];
		if( [mbr isLocalUser] && [byMbr isLocalUser] ) { // only server oppers would ever see this
			message = NSLocalizedString( @"You promoted yourself to operator.", "we gave ourself the chat room operator privilege status message" );
			name = @"promotedToOperator";
		} else if( [mbr isLocalUser] ) {
			message = [NSString stringWithFormat:NSLocalizedString( @"You were promoted to operator by <span class=\"member\">%@</span>.", "we are now a chat room operator status message" ), ( byMbr ? [byMbr title] : [byUser nickname] )];
			name = @"promotedToOperator";
		} else if( [byMbr isLocalUser] ) {
			message = [NSString stringWithFormat:NSLocalizedString( @"<span class=\"member\">%@</span> was promoted to operator by you.", "we gave user chat room operator status message" ), ( mbr ? [mbr title] : [user nickname] )];
		} else {
			message = [NSString stringWithFormat:NSLocalizedString( @"<span class=\"member\">%@</span> was promoted to operator by <span class=\"member\">%@</span>.", "user is now a chat room operator status message" ), ( mbr ? [mbr title] : [user nickname] ), ( byMbr ? [byMbr title] : [byUser nickname] )];
		}
	} else if( mode == MVChatRoomMemberOperatorMode && ! enabled ) {
		name = @"memberDemotedFromOperator";
		notificationKey = @"JVChatMemberDemoted";
		title = NSLocalizedString( @"Room Operator Demoted", "room operator demoted title" );
		description = [NSString stringWithFormat:NSLocalizedString( @"%@ was demoted from operator by %@ in %@.", "bubble message member operator demotion string" ), ( mbr ? [mbr title] : [user nickname] ), ( byMbr ? [byMbr title] : [byUser nickname] ), [self title]];
		if( [mbr isLocalUser] && [byMbr isLocalUser] ) {
			message = NSLocalizedString( @"You demoted yourself from operator.", "we removed our chat room operator privilege status message" );
			name = @"demotedFromOperator";
		} else if( [mbr isLocalUser] ) {
			message = [NSString stringWithFormat:NSLocalizedString( @"You were demoted from operator by <span class=\"member\">%@</span>.", "we are no longer a chat room operator status message" ), ( byMbr ? [byMbr title] : [byUser nickname] )];
			name = @"demotedFromOperator";
		} else if( [byMbr isLocalUser] ) {
			message = [NSString stringWithFormat:NSLocalizedString( @"<span class=\"member\">%@</span> was demoted from operator by you.", "we removed user's chat room operator status message" ), ( mbr ? [mbr title] : [user nickname] )];
		} else {
			message = [NSString stringWithFormat:NSLocalizedString( @"<span class=\"member\">%@</span> was demoted from operator by <span class=\"member\">%@</span>.", "user is no longer a chat room operator status message" ), ( mbr ? [mbr title] : [user nickname] ), ( byMbr ? [byMbr title] : [byUser nickname] )];
		}
	} else if( mode == MVChatRoomMemberHalfOperatorMode && enabled ) {
		name = @"memberPromotedToHalfOperator";
		notificationKey = @"JVChatMemberPromotedHalfOperator";
		title = NSLocalizedString( @"New Room Half-Operator", "member promoted to half-operator title" );
		description = [NSString stringWithFormat:NSLocalizedString( @"%@ was promoted to half-operator by %@ in %@.", "bubble message member half-operator promotion string" ), ( mbr ? [mbr title] : [user nickname] ), ( byMbr ? [byMbr title] : [byUser nickname] ), [self title]];
		if( [mbr isLocalUser] && [byMbr isLocalUser] ) { // only server oppers would ever see this
			message = NSLocalizedString( @"You promoted yourself to half-operator.", "we gave ourself the chat room half-operator privilege status message" );
			name = @"promotedToHalfOperator";
		} else if( [mbr isLocalUser] ) {
			message = [NSString stringWithFormat:NSLocalizedString( @"You were promoted to half-operator by <span class=\"member\">%@</span>.", "we are now a chat room half-operator status message" ), ( byMbr ? [byMbr title] : [byUser nickname] )];
			name = @"promotedToHalfOperator";
		} else if( [byMbr isLocalUser] ) {
			message = [NSString stringWithFormat:NSLocalizedString( @"<span class=\"member\">%@</span> was promoted to half-operator by you.", "we gave user chat room half-operator status message" ), ( mbr ? [mbr title] : [user nickname] )];
		} else {
			message = [NSString stringWithFormat:NSLocalizedString( @"<span class=\"member\">%@</span> was promoted to half-operator by <span class=\"member\">%@</span>.", "user is now a chat room half-operator status message" ), ( mbr ? [mbr title] : [user nickname] ), ( byMbr ? [byMbr title] : [byUser nickname] )];
		}
	} else if( mode == MVChatRoomMemberHalfOperatorMode && ! enabled ) {
		name = @"memberDemotedFromHalfOperator";
		notificationKey = @"JVChatMemberDemotedHalfOperator";
		title = NSLocalizedString( @"Room Half-Operator Demoted", "room half-operator demoted title" );
		description = [NSString stringWithFormat:NSLocalizedString( @"%@ was demoted from half-operator by %@ in %@.", "bubble message member operator demotion string" ), ( mbr ? [mbr title] : [user nickname] ), ( byMbr ? [byMbr title] : [byUser nickname] ), [self title]];
		if( [mbr isLocalUser] && [byMbr isLocalUser] ) {
			message = NSLocalizedString( @"You demoted yourself from half-operator.", "we removed our chat room half-operator privilege status message" );
			name = @"demotedFromHalfOperator";
		} else if( [mbr isLocalUser] ) {
			message = [NSString stringWithFormat:NSLocalizedString( @"You were demoted from half-operator by <span class=\"member\">%@</span>.", "we are no longer a chat room half-operator status message" ), ( byMbr ? [byMbr title] : [byUser nickname] )];
			name = @"demotedFromHalfOperator";
		} else if( [byMbr isLocalUser] ) {
			message = [NSString stringWithFormat:NSLocalizedString( @"<span class=\"member\">%@</span> was demoted from half-operator by you.", "we removed user's chat room half-operator status message" ), ( mbr ? [mbr title] : [user nickname] )];
		} else {
			message = [NSString stringWithFormat:NSLocalizedString( @"<span class=\"member\">%@</span> was demoted from half-operator by <span class=\"member\">%@</span>.", "user is no longer a chat room half-operator status message" ), ( mbr ? [mbr title] : [user nickname] ), ( byMbr ? [byMbr title] : [byUser nickname] )];
		}
	} else if( mode == MVChatRoomMemberVoicedMode && enabled ) {
		name = @"memberVoiced";
		notificationKey = @"JVChatMemberVoiced";
		title = NSLocalizedString( @"Room Member Voiced", "member voiced title" );
		description = [NSString stringWithFormat:NSLocalizedString( @"%@ was granted voice by %@ in %@.", "bubble message member voiced string" ), ( mbr ? [mbr title] : [user nickname] ), ( byMbr ? [byMbr title] : [byUser nickname] ), [self title]];
		if( [mbr isLocalUser] && [byMbr isLocalUser] ) {
			message = NSLocalizedString( @"You gave yourself voice.", "we gave ourself special voice status to talk in moderated rooms status message" );
			name = @"voiced";
		} else if( [mbr isLocalUser] ) {
			message = [NSString stringWithFormat:NSLocalizedString( @"You were granted voice by <span class=\"member\">%@</span>.", "we now have special voice status to talk in moderated rooms status message" ), ( byMbr ? [byMbr title] : [byUser nickname] )];
			name = @"voiced";
		} else if( [byMbr isLocalUser] ) {
			message = [NSString stringWithFormat:NSLocalizedString( @"<span class=\"member\">%@</span> was granted voice by you.", "we gave user special voice status to talk in moderated rooms status message" ), ( mbr ? [mbr title] : [user nickname] )];
		} else {
			message = [NSString stringWithFormat:NSLocalizedString( @"<span class=\"member\">%@</span> was granted voice by <span class=\"member\">%@</span>.", "user now has special voice status to talk in moderated rooms status message" ), ( mbr ? [mbr title] : [user nickname] ), ( byMbr ? [byMbr title] : [byUser nickname] )];
		}
	} else if( mode == MVChatRoomMemberVoicedMode && ! enabled ) {
		name = @"memberDevoiced";
		notificationKey = @"JVChatMemberDevoiced";
		title = NSLocalizedString( @"Room Member Lost Voice", "member devoiced title" );
		description = [NSString stringWithFormat:NSLocalizedString( @"%@ had voice removed by %@ in %@.", "bubble message member lost voice string" ), ( mbr ? [mbr title] : [user nickname] ), ( byMbr ? [byMbr title] : [byUser nickname] ), [self title]];
		if( [mbr isLocalUser] && [byMbr isLocalUser] ) {
			message = NSLocalizedString( @"You removed voice from yourself.", "we removed our special voice status to talk in moderated rooms status message" );
			name = @"devoiced";
		} else if( [mbr isLocalUser] ) {
			message = [NSString stringWithFormat:NSLocalizedString( @"You had voice removed by <span class=\"member\">%@</span>.", "we no longer has special voice status and can't talk in moderated rooms status message" ), ( byMbr ? [byMbr title] : [byUser nickname] )];
			name = @"devoiced";
		} else if( [byMbr isLocalUser] ) {
			message = [NSString stringWithFormat:NSLocalizedString( @"<span class=\"member\">%@</span> had voice removed by you.", "we removed user's special voice status and can't talk in moderated rooms status message" ), ( mbr ? [mbr title] : [user nickname] )];
		} else {
			message = [NSString stringWithFormat:NSLocalizedString( @"<span class=\"member\">%@</span> had voice removed by <span class=\"member\">%@</span>.", "user no longer has special voice status and can't talk in moderated rooms status message" ), ( mbr ? [mbr title] : [user nickname] ), ( byMbr ? [byMbr title] : [byUser nickname] )];
		}
	} else if( mode == MVChatRoomMemberQuietedMode && enabled ) {
		name = @"memberQuieted";
		notificationKey = @"JVChatMemberQuieted";
		title = NSLocalizedString( @"Room Member Quieted", "member quieted title" );
		description = [NSString stringWithFormat:NSLocalizedString( @"%@ was quieted by %@ in %@.", "bubble message member quieted string" ), ( mbr ? [mbr title] : [user nickname] ), ( byMbr ? [byMbr title] : [byUser nickname] ), [self title]];
		if( [mbr isLocalUser] && [byMbr isLocalUser] ) {
			message = NSLocalizedString( @"You quieted yourself.", "we quieted and can't talk ourself status message" );
			name = @"quieted";
		} else if( [mbr isLocalUser] ) {
			message = [NSString stringWithFormat:NSLocalizedString( @"You were quieted by <span class=\"member\">%@</span>.", "we are now quieted and can't talk status message" ), ( byMbr ? [byMbr title] : [byUser nickname] )];
			name = @"quieted";
		} else if( [byMbr isLocalUser] ) {
			message = [NSString stringWithFormat:NSLocalizedString( @"<span class=\"member\">%@</span> was quieted by you.", "we quieted someone else in the room status message" ), ( mbr ? [mbr title] : [user nickname] )];
		} else {
			message = [NSString stringWithFormat:NSLocalizedString( @"<span class=\"member\">%@</span> was quieted by <span class=\"member\">%@</span>.", "user was quieted by someone else in the room status message" ), ( mbr ? [mbr title] : [user nickname] ), ( byMbr ? [byMbr title] : [byUser nickname] )];
		}
	} else if( mode == MVChatRoomMemberQuietedMode && ! enabled ) {
		name = @"memberDequieted";
		notificationKey = @"JVChatMemberDequieted";
		title = NSLocalizedString( @"Quieted Room Member Annulled", "quieted member annulled title" );
		description = [NSString stringWithFormat:NSLocalizedString( @"Quieted %@ was annulled by %@ in %@.", "bubble message quieted member annulled string" ), ( mbr ? [mbr title] : [user nickname] ), ( byMbr ? [byMbr title] : [byUser nickname] ), [self title]];
		if( [mbr isLocalUser] && [byMbr isLocalUser] ) {
			message = NSLocalizedString( @"You made yourself no longer quieted.", "we are no longer quieted and can talk ourself status message" );
			name = @"dequieted";
		} else if( [mbr isLocalUser] ) {
			message = [NSString stringWithFormat:NSLocalizedString( @"You are no longer quieted, thanks to <span class=\"member\">%@</span>.", "we are no longer quieted and can talk status message" ), ( byMbr ? [byMbr title] : [byUser nickname] )];
			name = @"dequieted";
		} else if( [byMbr isLocalUser] ) {
			message = [NSString stringWithFormat:NSLocalizedString( @"<span class=\"member\">%@</span> is no longer quieted because of you.", "a user is no longer quieted because of us status message" ), ( mbr ? [mbr title] : [user nickname] )];
		} else {
			message = [NSString stringWithFormat:NSLocalizedString( @"<span class=\"member\">%@</span> is no longer quieted because of <span class=\"member\">%@</span>.", "user is no longer quieted because of someone else in the room status message" ), ( mbr ? [mbr title] : [user nickname] ), ( byMbr ? [byMbr title] : [byUser nickname] )];
		}
	}

	[self addEventMessageToDisplay:message withName:name andAttributes:[NSDictionary dictionaryWithObjectsAndKeys:( byMbr ? [byMbr title] : [byUser nickname] ), @"by", [byUser nickname], @"by-nickname", ( mbr ? [mbr title] : [user nickname] ), @"who", [user nickname], @"who-nickname", nil]];

	if( title && description && notificationKey ) {
		NSMutableDictionary *context = [NSMutableDictionary dictionary];
		[context setObject:title forKey:@"title"];
		[context setObject:description forKey:@"description"];
		[context setObject:self forKey:@"target"];
		[context setObject:NSStringFromSelector( @selector( activate: ) ) forKey:@"action"];
		[[JVNotificationController defaultManager] performNotification:notificationKey withContextInfo:context];
	}
}

- (void) _topicChanged:(id) sender {
	NSAttributedString *topic = [self _convertRawMessage:[[self target] topic] withBaseFont:[NSFont systemFontOfSize:11.]];
	JVChatRoomMember *author = [self chatRoomMemberForUser:[[self target] topicAuthor]];

	if( topic && author && sender ) {
		NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:YES], @"IgnoreFonts", [NSNumber numberWithBool:YES], @"IgnoreFontSizes", nil];
		NSString *topicString = [topic HTMLFormatWithOptions:options];

		if( [author isLocalUser] ) {
			[self addEventMessageToDisplay:[NSString stringWithFormat:NSLocalizedString( @"You changed the topic to \"%@\".", "you changed the topic chat room status message" ), topicString] withName:@"topicChanged" andAttributes:[NSDictionary dictionaryWithObjectsAndKeys:[author title], @"by", [author nickname], @"by-nickname", topic, @"topic", nil]];
		} else {
			[self addEventMessageToDisplay:[NSString stringWithFormat:NSLocalizedString( @"Topic changed to \"%@\" by <span class=\"member\">%@</span>.", "topic changed chat room status message" ), topicString, [author title]] withName:@"topicChanged" andAttributes:[NSDictionary dictionaryWithObjectsAndKeys:[author title], @"by", [author nickname], @"by-nickname", topic, @"topic", nil]];
		}

		NSMethodSignature *signature = [NSMethodSignature methodSignatureWithReturnAndArgumentTypes:@encode( void ), @encode( NSAttributedString * ), @encode( JVChatRoom * ), @encode( JVChatRoomMember * ), nil];
		NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];

		[invocation setSelector:@selector( topicChangedTo:inRoom:by: )];
		[invocation setArgument:&topic atIndex:2];
		[invocation setArgument:&self atIndex:3];
		[invocation setArgument:&author atIndex:4];

		[[MVChatPluginManager defaultManager] makePluginsPerformInvocation:invocation];
	}

	if( ! [topic length] ) {
		NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:[NSColor grayColor], NSForegroundColorAttributeName, [NSFont systemFontOfSize:11.], NSFontAttributeName, nil];
		topic = [[NSMutableAttributedString alloc] initWithString:NSLocalizedString( @"(no chat topic is set)", "no chat topic is set message" ) attributes:attributes];
	}

	NSMutableParagraphStyle *paraStyle = [[[NSParagraphStyle defaultParagraphStyle] mutableCopy] autorelease];
	[paraStyle setMaximumLineHeight:13.];
	[paraStyle setAlignment:NSCenterTextAlignment];
//	[paraStyle setLineBreakMode:NSLineBreakByTruncatingTail];
	[(NSMutableAttributedString *)topic addAttribute:NSParagraphStyleAttributeName value:paraStyle range:NSMakeRange( 0, [topic length] )];

	[[topicLine textStorage] setAttributedString:topic];

	if( author ) {
		NSMutableString *toolTip = [[[topic string] mutableCopy] autorelease];
		[toolTip appendString:@"\n"];
		[toolTip appendFormat:NSLocalizedString( @"Topic set by: %@", "topic author tooltip" ), [author title]];
		[[topicLine enclosingScrollView] setToolTip:toolTip];
	} else [[topicLine enclosingScrollView] setToolTip:[topic string]];
}

- (void) _startChatWithNonMember:(id) sender {
	[[JVChatController defaultManager] chatViewControllerForUser:[sender representedObject] ifExists:NO];
}

- (void) _resetRecentlyJoinedStatus {
	_recentlyJoined = NO;
}
@end

#pragma mark -

@implementation JVChatRoom (JVChatRoomScripting)
- (NSArray *) chatMembers {
	return [[_sortedMembers retain] autorelease];
}

- (JVChatRoomMember *) valueInChatMembersWithName:(NSString *) name {
	return [self firstChatRoomMemberWithName:name];
}

- (JVChatRoomMember *) valueInChatMembersWithUniqueID:(id) identifier {
	NSEnumerator *enumerator = [_sortedMembers objectEnumerator];
	JVChatRoomMember *member = nil;

	while( ( member = [enumerator nextObject] ) )
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
	[[self target] setTopic:attributeMsg];
}
@end

#pragma mark -

@implementation MVChatScriptPlugin (MVChatScriptPluginRoomSupport)
- (void) memberJoined:(JVChatRoomMember *) member inRoom:(JVChatRoom *) room {
	NSDictionary *args = [NSDictionary dictionaryWithObjectsAndKeys:member, @"----", room, @"mJr1", nil];
	[self callScriptHandler:'mJrX' withArguments:args forSelector:_cmd];
}

- (void) memberParted:(JVChatRoomMember *) member fromRoom:(JVChatRoom *) room forReason:(NSAttributedString *) reason {
	NSDictionary *args = [NSDictionary dictionaryWithObjectsAndKeys:member, @"----", room, @"mPr1", [reason string], @"mPr2", nil];
	[self callScriptHandler:'mPrX' withArguments:args forSelector:_cmd];
}

- (void) memberKicked:(JVChatRoomMember *) member fromRoom:(JVChatRoom *) room by:(JVChatRoomMember *) by forReason:(NSAttributedString *) reason {
	NSDictionary *args = [NSDictionary dictionaryWithObjectsAndKeys:member, @"----", room, @"mKr1", by, @"mKr2", [reason string], @"mKr3", nil];
	[self callScriptHandler:'mKrX' withArguments:args forSelector:_cmd];
}

- (void) memberPromoted:(JVChatRoomMember *) member inRoom:(JVChatRoom *) room by:(JVChatRoomMember *) by {
	NSDictionary *args = [NSDictionary dictionaryWithObjectsAndKeys:member, @"----", [NSValue valueWithBytes:"cOpr" objCType:@encode( char * )], @"mSc1", by, @"mSc2", room, @"mSc3", nil];
	[self callScriptHandler:'mScX' withArguments:args forSelector:_cmd];
}

- (void) memberDemoted:(JVChatRoomMember *) member inRoom:(JVChatRoom *) room by:(JVChatRoomMember *) by {
	NSDictionary *args = [NSDictionary dictionaryWithObjectsAndKeys:member, @"----", [NSValue valueWithBytes:( [member voice] ? "VoIc" : "noRm" ) objCType:@encode( char * )], @"mSc1", by, @"mSc2", room, @"mSc3", nil];
	[self callScriptHandler:'mScX' withArguments:args forSelector:_cmd];
}

- (void) memberVoiced:(JVChatRoomMember *) member inRoom:(JVChatRoom *) room by:(JVChatRoomMember *) by {
	NSDictionary *args = [NSDictionary dictionaryWithObjectsAndKeys:member, @"----", [NSValue valueWithBytes:"VoIc" objCType:@encode( char * )], @"mSc1", by, @"mSc2", room, @"mSc3", nil];
	[self callScriptHandler:'mScX' withArguments:args forSelector:_cmd];
}

- (void) memberDevoiced:(JVChatRoomMember *) member inRoom:(JVChatRoom *) room by:(JVChatRoomMember *) by {
	NSDictionary *args = [NSDictionary dictionaryWithObjectsAndKeys:member, @"----", [NSValue valueWithBytes:( [member operator] ? "cOpr" : "noRm" ) objCType:@encode( char * )], @"mSc1", by, @"mSc2", room, @"mSc3", nil];
	[self callScriptHandler:'mScX' withArguments:args forSelector:_cmd];
}

- (void) joinedRoom:(JVChatRoom *) room; {
	NSDictionary *args = [NSDictionary dictionaryWithObjectsAndKeys:room, @"----", nil];
	[self callScriptHandler:'jRmX' withArguments:args forSelector:_cmd];
}

- (void) partingFromRoom:(JVChatRoom *) room; {
	NSDictionary *args = [NSDictionary dictionaryWithObjectsAndKeys:room, @"----", nil];
	[self callScriptHandler:'pRmX' withArguments:args forSelector:_cmd];
}

- (void) kickedFromRoom:(JVChatRoom *) room by:(JVChatRoomMember *) by forReason:(NSAttributedString *) reason {
	NSDictionary *args = [NSDictionary dictionaryWithObjectsAndKeys:room, @"----", by, @"kRm1", [reason string], @"kRm2", nil];
	[self callScriptHandler:'kRmX' withArguments:args forSelector:_cmd];
}

- (void) topicChangedTo:(NSAttributedString *) topic inRoom:(JVChatRoom *) room by:(JVChatRoomMember *) member {
	NSDictionary *args = [NSDictionary dictionaryWithObjectsAndKeys:[topic string], @"rTc1", member, @"rTc2", room, @"rTc3", nil];
	[self callScriptHandler:'rTcX' withArguments:args forSelector:_cmd];
}
@end
