#import <ChatCore/MVChatConnection.h>
#import <ChatCore/MVChatRoom.h>
#import <ChatCore/MVChatUser.h>
#import <ChatCore/NSAttributedStringAdditions.h>

#import "JVChatController.h"
#import "MVConnectionsController.h"
#import "JVChatWindowController.h"
#import "JVTabbedChatWindowController.h"
#import "JVNotificationController.h"
#import "JVChatTranscriptPanel.h"
#import "JVDirectChatPanel.h"
#import "JVChatRoomPanel.h"
#import "JVChatConsolePanel.h"
#import "KAIgnoreRule.h"
#import "JVChatMessage.h"

#import <libxml/parser.h>

static JVChatController *sharedInstance = nil;

@interface JVChatController (JVChatControllerPrivate)
- (void) _addWindowController:(JVChatWindowController *) windowController;
- (void) _addViewControllerToPreferedWindowController:(id <JVChatViewController>) controller andFocus:(BOOL) focus;
@end

#pragma mark -

@implementation JVChatController
+ (JVChatController *) defaultManager {
	extern JVChatController *sharedInstance;
	return ( sharedInstance ? sharedInstance : ( sharedInstance = [[self alloc] init] ) );
}

#pragma mark -

- (id) init {
	if( ( self = [super init] ) ) {
		_chatWindows = [[NSMutableArray array] retain];
		_chatControllers = [[NSMutableArray array] retain];
		_ignoreRules = [[NSMutableArray alloc] init];

		NSEnumerator *permanentRulesEnumerator = [[[NSUserDefaults standardUserDefaults] objectForKey:@"JVIgnoreRules"] objectEnumerator];
		NSData *archivedRule = nil;
		while( ( archivedRule = [permanentRulesEnumerator nextObject] ) )
			[_ignoreRules addObject:[NSKeyedUnarchiver unarchiveObjectWithData:archivedRule]];

		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector( _joinedRoom: ) name:MVChatRoomJoinedNotification object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector( _invitedToRoom: ) name:MVChatRoomInvitedNotification object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector( _gotPrivateMessage: ) name:MVChatConnectionGotPrivateMessageNotification object:nil];
	}
	return self;
}

- (void) dealloc {
	extern JVChatController *sharedInstance;

	[[NSNotificationCenter defaultCenter] removeObserver:self];
	if( self == sharedInstance ) sharedInstance = nil;

	[_ignoreRules release];
	[_chatWindows release];
	[_chatControllers release];

	_chatWindows = nil;
	_chatControllers = nil;

	[super dealloc];
}

#pragma mark -

- (NSSet *) allChatWindowControllers {
	return [[[NSSet setWithArray:_chatWindows] retain] autorelease];
}

- (JVChatWindowController *) newChatWindowController {
	JVChatWindowController *windowController = nil;
	if( [[NSUserDefaults standardUserDefaults] boolForKey:@"JVUseTabbedWindows"] )
		windowController = [[[JVTabbedChatWindowController alloc] init] autorelease];
	else windowController = [[[JVChatWindowController alloc] init] autorelease];
	[self _addWindowController:windowController];
	return [[windowController retain] autorelease];
}

- (void) disposeChatWindowController:(JVChatWindowController *) controller {
	NSParameterAssert( controller != nil );

	id view = nil;
	NSEnumerator *enumerator = [[controller allChatViewControllers] objectEnumerator];
	while( ( view = [enumerator nextObject] ) )
		[self disposeViewController:view];

	[_chatWindows removeObject:controller];
}

#pragma mark -

- (NSSet *) allChatViewControllers {
	return [[[NSSet setWithArray:_chatControllers] retain] autorelease];
}

- (NSSet *) chatViewControllersWithConnection:(MVChatConnection *) connection {
	NSMutableSet *ret = [NSMutableSet set];
	id <JVChatViewController> item = nil;
	NSEnumerator *enumerator = nil;

	NSParameterAssert( connection != nil );

	enumerator = [_chatControllers objectEnumerator];
	while( ( item = [enumerator nextObject] ) )
		if( [item connection] == connection )
			[ret addObject:item];

	return [[ret retain] autorelease];
}

- (NSSet *) chatViewControllersOfClass:(Class) class {
	NSMutableSet *ret = [NSMutableSet set];
	id <JVChatViewController> item = nil;
	NSEnumerator *enumerator = nil;

	NSParameterAssert( class != NULL );

	enumerator = [_chatControllers objectEnumerator];
	while( ( item = [enumerator nextObject] ) )
		if( [item isMemberOfClass:class] )
			[ret addObject:item];

	return [[ret retain] autorelease];
}

- (NSSet *) chatViewControllersKindOfClass:(Class) class {
	NSMutableSet *ret = [NSMutableSet set];
	id <JVChatViewController> item = nil;
	NSEnumerator *enumerator = nil;

	NSParameterAssert( class != NULL );

	enumerator = [_chatControllers objectEnumerator];
	while( ( item = [enumerator nextObject] ) )
		if( [item isKindOfClass:class] )
			[ret addObject:item];

	return [[ret retain] autorelease];
}

#pragma mark -

- (JVChatRoomPanel *) chatViewControllerForRoom:(MVChatRoom *) room ifExists:(BOOL) exists {
	NSParameterAssert( room != nil );

	NSEnumerator *enumerator = [_chatControllers objectEnumerator];
	id ret = nil;

	while( ( ret = [enumerator nextObject] ) )
		if( [ret isMemberOfClass:[JVChatRoomPanel class]] && [[ret target] isEqual:room] )
			break;

	if( ! ret && ! exists ) {
		if( ( ret = [[[JVChatRoomPanel alloc] initWithTarget:room] autorelease] ) ) {
			[_chatControllers addObject:ret];
			[self _addViewControllerToPreferedWindowController:ret andFocus:YES];
		}
	}

	return [[ret retain] autorelease];
}

- (JVDirectChatPanel *) chatViewControllerForUser:(MVChatUser *) user ifExists:(BOOL) exists {
	return [self chatViewControllerForUser:user ifExists:exists userInitiated:YES];
}

- (JVDirectChatPanel *) chatViewControllerForUser:(MVChatUser *) user ifExists:(BOOL) exists userInitiated:(BOOL) initiated {
	NSParameterAssert( user != nil );

	NSEnumerator *enumerator = [_chatControllers objectEnumerator];
	id ret = nil;

	while( ( ret = [enumerator nextObject] ) )
		if( [ret isMemberOfClass:[JVDirectChatPanel class]] && [[ret target] isEqual:user] )
			break;

	if( ! ret && ! exists ) {
		if( ( ret = [[[JVDirectChatPanel alloc] initWithTarget:user] autorelease] ) ) {
			[_chatControllers addObject:ret];
			[self _addViewControllerToPreferedWindowController:ret andFocus:initiated];
		}
	}

	return [[ret retain] autorelease];
}

- (JVChatTranscriptPanel *) chatViewControllerForTranscript:(NSString *) filename {
	id ret = nil;
	if( ( ret = [[[JVChatTranscriptPanel alloc] initWithTranscript:filename] autorelease] ) ) {
		[_chatControllers addObject:ret];
		[self _addViewControllerToPreferedWindowController:ret andFocus:YES];
	}
	return [[ret retain] autorelease];
}

#pragma mark -

- (JVChatConsolePanel *) chatConsoleForConnection:(MVChatConnection *) connection ifExists:(BOOL) exists {
	NSParameterAssert( connection != nil );

	NSEnumerator *enumerator = [_chatControllers objectEnumerator];
	id <JVChatViewController> ret = nil;

	while( ( ret = [enumerator nextObject] ) )
		if( [ret isMemberOfClass:[JVChatConsolePanel class]] && [ret connection] == connection )
			break;

	if( ! ret && ! exists ) {
		if( ( ret = [[[JVChatConsolePanel alloc] initWithConnection:connection] autorelease] ) ) {
			[_chatControllers addObject:ret];
			[self _addViewControllerToPreferedWindowController:ret andFocus:YES];
		}
	}

	return [[ret retain] autorelease];
}

#pragma mark -

- (void) disposeViewController:(id <JVChatViewController>) controller {
	NSParameterAssert( controller != nil );
	if( [controller respondsToSelector:@selector( willDispose )] )
		[(NSObject *)controller willDispose];
	[[controller windowController] removeChatViewController:controller];
	[_chatControllers removeObject:controller];
}

- (void) detachViewController:(id <JVChatViewController>) controller {
	NSParameterAssert( controller != nil );

	[[controller retain] autorelease];

	JVChatWindowController *windowController = [self newChatWindowController];
	[[controller windowController] removeChatViewController:controller];

	[[windowController window] setFrameUsingName:[NSString stringWithFormat:@"Chat Window %@", [controller identifier]]];

	NSRect frame = [[windowController window] frame];
	NSPoint point = [[windowController window] cascadeTopLeftFromPoint:NSMakePoint( NSMinX( frame ), NSMaxY( frame ) )];
	[[windowController window] setFrameTopLeftPoint:point];

	[[windowController window] saveFrameUsingName:[NSString stringWithFormat:@"Chat Window %@", [controller identifier]]];

	[windowController addChatViewController:controller];
}

#pragma mark -

- (IBAction) detachView:(id) sender {
	id <JVChatViewController> view = [sender representedObject];
	if( ! view ) return;
	[self detachViewController:view];
}

#pragma mark -
#pragma mark Ignores

- (JVIgnoreMatchResult) shouldIgnoreUser:(MVChatUser *) user withMessage:(NSAttributedString *) message inView:(id <JVChatViewController>) view {
	JVIgnoreMatchResult ignoreResult = JVNotIgnored;
	NSEnumerator *renum = [[[MVConnectionsController defaultManager] ignoreRulesForConnection:[view connection]] objectEnumerator];
	KAIgnoreRule *rule = nil;

	while( ( ignoreResult == JVNotIgnored ) && ( ( rule = [renum nextObject] ) ) )
		ignoreResult = [rule matchUser:user message:[message string] inView:view];

	return ignoreResult;
}
@end

#pragma mark -

@implementation JVChatController (JVChatControllerPrivate)
- (void) _joinedRoom:(NSNotification *) notification {
	MVChatRoom *rm = [notification object];
	if( ! [[MVConnectionsController defaultManager] managesConnection:[rm connection]] ) return;
	JVChatRoomPanel *room = [self chatViewControllerForRoom:rm ifExists:NO];
	[room joined];
}

- (void) _invitedToRoom:(NSNotification *) notification {
	NSString *room = [[notification userInfo] objectForKey:@"room"];
	MVChatUser *user = [[notification userInfo] objectForKey:@"user"];
	MVChatConnection *connection = [notification object];

	if( ! [[MVConnectionsController defaultManager] managesConnection:connection] ) return;

	NSString *title = NSLocalizedString( @"Chat Room Invite", "member invited to room title" );
	NSString *message = [NSString stringWithFormat:NSLocalizedString( @"You were invited to join %@ by %@. Would you like to accept this invitation and join this room?", "you were invited to join a chat room status message" ), room, [user nickname]];

	if( NSRunInformationalAlertPanel( title, message, NSLocalizedString( @"Join", "join button" ), NSLocalizedString( @"Decline", "decline button" ), nil ) == NSOKButton )
		[connection joinChatRoomNamed:room];

	NSMutableDictionary *context = [NSMutableDictionary dictionary];
	[context setObject:NSLocalizedString( @"Invited to Chat", "bubble title invited to room" ) forKey:@"title"];
	[context setObject:[NSString stringWithFormat:NSLocalizedString( @"You were invited to %@ by %@.", "bubble message invited to room" ), room, [user nickname]] forKey:@"description"];
	[[JVNotificationController defaultManager] performNotification:@"JVChatRoomInvite" withContextInfo:context];
}

- (void) _gotPrivateMessage:(NSNotification *) notification {
	BOOL hideFromUser = NO;
	MVChatUser *user = [notification object];
	NSData *message = [[notification userInfo] objectForKey:@"message"];

	if( ! [[MVConnectionsController defaultManager] managesConnection:[user connection]] ) return;

	if( [[[notification userInfo] objectForKey:@"notice"] boolValue] ) {
		MVChatConnection *connection = [user connection];

		if( ! [self chatViewControllerForUser:user ifExists:YES] )
			hideFromUser = YES;

		if( [[NSUserDefaults standardUserDefaults] boolForKey:@"JVChatAlwaysShowNotices"] ) 
			hideFromUser = NO;

		if( [[user nickname] isEqualToString:@"NickServ"] || [[user nickname] isEqualToString:@"MemoServ"] ) {
			NSMutableDictionary *options = [NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithUnsignedInt:[connection encoding]], @"StringEncoding", [NSNumber numberWithBool:[[NSUserDefaults standardUserDefaults] boolForKey:@"JVChatStripMessageColors"]], @"IgnoreFontColors", [NSNumber numberWithBool:[[NSUserDefaults standardUserDefaults] boolForKey:@"JVChatStripMessageFormatting"]], @"IgnoreFontTraits", [NSFont systemFontOfSize:11.], @"BaseFont", nil];
			NSAttributedString *messageString = [NSAttributedString attributedStringWithChatFormat:message options:options];
			if( ! messageString ) {
				[options setObject:[NSNumber numberWithUnsignedInt:[NSString defaultCStringEncoding]] forKey:@"StringEncoding"];
				messageString = [NSAttributedString attributedStringWithChatFormat:message options:options];
			}

			if( [[user nickname] isEqualToString:@"NickServ"] ) {
				if( [[messageString string] rangeOfString:@"password accepted" options:NSCaseInsensitiveSearch].location != NSNotFound ) {
					NSMutableDictionary *context = [NSMutableDictionary dictionary];
					[context setObject:NSLocalizedString( @"You Have Been Identified", "identified bubble title" ) forKey:@"title"];
					[context setObject:[NSString stringWithFormat:@"%@ on %@", [messageString string], [connection server]] forKey:@"description"];
					[context setObject:[NSImage imageNamed:@"Keychain"] forKey:@"image"];
					[[JVNotificationController defaultManager] performNotification:@"JVNickNameIdentifiedWithServer" withContextInfo:context];
				}
			} else if( [[user nickname] isEqualToString:@"MemoServ"] ) {
				if( [[messageString string] rangeOfString:@"new memo" options:NSCaseInsensitiveSearch].location != NSNotFound && [[messageString string] rangeOfString:@" no " options:NSCaseInsensitiveSearch].location == NSNotFound ) {
					NSMutableDictionary *context = [NSMutableDictionary dictionary];
					[context setObject:NSLocalizedString( @"You Have New Memos", "new memos bubble title" ) forKey:@"title"];
					[context setObject:messageString forKey:@"description"];
					[context setObject:[NSImage imageNamed:@"Stickies"] forKey:@"image"];
					[context setObject:self forKey:@"target"];
					[context setObject:NSStringFromSelector( @selector( _checkMemos: ) ) forKey:@"action"];
					[context setObject:connection forKey:@"representedObject"];
					[[JVNotificationController defaultManager] performNotification:@"JVNewMemosFromServer" withContextInfo:context];
				}	
			}
		}
	}

	if( ! hideFromUser && ( [self shouldIgnoreUser:user withMessage:nil inView:nil] == JVNotIgnored ) ) {
		JVDirectChatPanel *controller = [self chatViewControllerForUser:user ifExists:NO userInitiated:NO];
		JVChatMessageType type = ( [[[notification userInfo] objectForKey:@"notice"] boolValue] ? JVChatMessageNoticeType : JVChatMessageNormalType );
		[controller addMessageToDisplay:message fromUser:user asAction:[[[notification userInfo] objectForKey:@"action"] boolValue] withIdentifier:[[notification userInfo] objectForKey:@"identifier"] andType:type];
	}
}

- (void) _addWindowController:(JVChatWindowController *) windowController {
	[_chatWindows addObject:windowController];
}

- (void) _addViewControllerToPreferedWindowController:(id <JVChatViewController>) controller andFocus:(BOOL) focus {
	JVChatWindowController *windowController = nil;
	id <JVChatViewController> viewController = nil;
	Class modeClass = NULL;
	NSEnumerator *enumerator = nil;
	BOOL kindOfClass = NO;

	NSParameterAssert( controller != nil );

	int mode = [[NSUserDefaults standardUserDefaults] integerForKey:[NSStringFromClass( [controller class] ) stringByAppendingString:@"PreferredOpenMode"]];
	BOOL groupByServer = (BOOL) mode & 32;
	mode &= ~32;

	switch( mode ) {
	default:
	case 0:
		windowController = nil;
		break;
	case 1:
		enumerator = [_chatWindows objectEnumerator];
		while( ( windowController = [enumerator nextObject] ) )
			if( [[windowController window] isMainWindow] || ! [[NSApplication sharedApplication] isActive] )
				break;
		if( ! windowController ) windowController = [_chatWindows lastObject];
		break;
	case 2:
		modeClass = [JVChatRoomPanel class];
		goto groupByClass;
	case 3:
		modeClass = [JVDirectChatPanel class];
		goto groupByClass;
	case 4:
		modeClass = [JVChatTranscriptPanel class];
		goto groupByClass;
	case 5:
		modeClass = [JVChatConsolePanel class];
		goto groupByClass;
	case 6:
		modeClass = [JVDirectChatPanel class];
		kindOfClass = YES;
		goto groupByClass;
	groupByClass:
		if( groupByServer ) {
			if( kindOfClass ) enumerator = [[self chatViewControllersKindOfClass:modeClass] objectEnumerator];
			else enumerator = [[self chatViewControllersOfClass:modeClass] objectEnumerator];
			while( ( viewController = [enumerator nextObject] ) ) {
				if( controller != viewController && [viewController connection] == [controller connection] ) {
					windowController = [viewController windowController];
					if( windowController ) break;
				}
			}
		} else {
			if( kindOfClass ) enumerator = [[self chatViewControllersKindOfClass:modeClass] objectEnumerator];
			else enumerator = [[self chatViewControllersOfClass:modeClass] objectEnumerator];
			while( ( viewController = [enumerator nextObject] ) ) {
				if( controller != viewController ) {
					windowController = [viewController windowController];
					if( windowController ) break;
				}
			}
		}
		break;
	}

	if( ! windowController ) windowController = [self newChatWindowController];

	if( [[[NSApplication sharedApplication] currentEvent] modifierFlags] & NSCommandKeyMask ) focus = NO;
	if( [[[NSApplication sharedApplication] currentEvent] modifierFlags] & NSShiftKeyMask ) focus = NO;

	[windowController addChatViewController:controller];
	if( focus || [[windowController allChatViewControllers] count] == 1 ) {
		[windowController showChatViewController:controller];
		if( focus ) [[windowController window] makeKeyAndOrderFront:nil];
	}

	if( ! focus && [_chatWindows count] == 1 )
		[[windowController window] makeKeyAndOrderFront:nil];
}

- (IBAction) _checkMemos:(id) sender {
	MVChatConnection *connection = [sender representedObject];
	NSAttributedString *message = [[[NSAttributedString alloc] initWithString:@"read all"] autorelease];
	MVChatUser *user = [connection chatUserWithUniqueIdentifier:@"MemoServ"];
	[user sendMessage:message withEncoding:[connection encoding] asAction:NO];
	[self chatViewControllerForUser:user ifExists:NO];
}

@end

#pragma mark -

@implementation JVChatWindowController (JVChatWindowControllerObjectSpecifier)
- (NSScriptObjectSpecifier *) objectSpecifier {
	id classDescription = [NSClassDescription classDescriptionForClass:[JVChatController class]];
	NSScriptObjectSpecifier *container = [[JVChatController defaultManager] objectSpecifier];
	return [[[NSUniqueIDSpecifier alloc] initWithContainerClassDescription:classDescription containerSpecifier:container key:@"chatWindows" uniqueID:[self uniqueIdentifier]] autorelease];
}
@end

#pragma mark -

@implementation JVChatTranscriptPanel (JVChatTranscriptObjectSpecifier)
- (NSScriptObjectSpecifier *) objectSpecifier {
	id classDescription = [NSClassDescription classDescriptionForClass:[JVChatController class]];
	NSScriptObjectSpecifier *container = [[JVChatController defaultManager] objectSpecifier];
	return [[[NSUniqueIDSpecifier alloc] initWithContainerClassDescription:classDescription containerSpecifier:container key:@"chatViews" uniqueID:[self uniqueIdentifier]] autorelease];
}
@end

#pragma mark -

@implementation JVChatConsolePanel (JVChatConsolePanelObjectSpecifier)
- (NSScriptObjectSpecifier *) objectSpecifier {
	id classDescription = [NSClassDescription classDescriptionForClass:[JVChatController class]];
	NSScriptObjectSpecifier *container = [[JVChatController defaultManager] objectSpecifier];
	return [[[NSUniqueIDSpecifier alloc] initWithContainerClassDescription:classDescription containerSpecifier:container key:@"chatViews" uniqueID:[self uniqueIdentifier]] autorelease];
}
@end

#pragma mark -

@implementation JVChatController (JVChatControllerScripting)
- (JVChatWindowController *) newChatWindowScriptCommand:(NSScriptCommand *) command {
	return [self newChatWindowController];
}

- (void) startChatScriptCommand:(NSScriptCommand *) command {
	MVChatConnection *connection = [[command evaluatedArguments] objectForKey:@"connection"];
	NSString *user = [[command evaluatedArguments] objectForKey:@"user"];

	if( ! [user length] ) {
		[NSException raise:NSInvalidArgumentException format:@"Invalid user nickname."];
		return;
	}

	if( ! connection || ! [connection isConnected] ) {
		[NSException raise:NSInvalidArgumentException format:@"Invalid conenction or it is not connected."];
		return;
	}

	MVChatUser *u = [connection chatUserWithUniqueIdentifier:user];
	[self chatViewControllerForUser:u ifExists:NO];
}

#pragma mark -

- (NSArray *) chatWindows {
	return _chatWindows;
}

- (JVChatWindowController *) valueInChatWindowsAtIndex:(unsigned) index {
	return [_chatWindows objectAtIndex:index];
}

- (JVChatWindowController *) valueInChatWindowsWithUniqueID:(id) identifier {
	NSEnumerator *enumerator = [_chatWindows objectEnumerator];
	JVChatWindowController *window = nil;

	while( ( window = [enumerator nextObject] ) )
		if( [[window uniqueIdentifier] isEqual:identifier] )
			return window;

	return nil;
}

- (void) addInChatWindows:(JVChatWindowController *) window {
	[self _addWindowController:window];
}

- (void) insertInChatWindows:(JVChatWindowController *) window {
	[self _addWindowController:window];
}

- (void) insertInChatWindows:(JVChatWindowController *) window atIndex:(unsigned) index {
	[self _addWindowController:window];
}

- (void) removeFromChatWindowsAtIndex:(unsigned) index {
	JVChatWindowController *window = [[self chatWindows] objectAtIndex:index];
	[[window window] orderOut:nil];
	[self disposeChatWindowController:window];
}

- (void) replaceInChatWindows:(JVChatWindowController *) window atIndex:(unsigned) index {
	[NSException raise:NSOperationNotSupportedForKeyException format:@"Can't replace a chat window."];
}

#pragma mark -

- (void) raiseCantAddChatViewsException {
	[NSException raise:NSOperationNotSupportedForKeyException format:@"Can't insert a chat view. Read only."];
}

#pragma mark -

- (NSArray *) chatViews {
	return _chatControllers;
}

- (id <JVChatViewController>) valueInChatViewsAtIndex:(unsigned) index {
	return [_chatControllers objectAtIndex:index];
}

- (id <JVChatViewController>) valueInChatViewsWithUniqueID:(id) identifier {
	NSEnumerator *enumerator = [_chatControllers objectEnumerator];
	id <JVChatViewController, JVChatListItemScripting> view = nil;

	while( ( view = [enumerator nextObject] ) )
		if( [[view uniqueIdentifier] isEqual:identifier] )
			return view;

	return nil;
}

- (id <JVChatViewController>) valueInChatViewsWithName:(NSString *) name {
	NSEnumerator *enumerator = [_chatControllers objectEnumerator];
	id <JVChatViewController> view = nil;

	while( ( view = [enumerator nextObject] ) )
		if( [[view title] isEqualToString:name] )
			return view;

	return nil;
}

- (void) addInChatViews:(id <JVChatViewController>) view {
	[self raiseCantAddChatViewsException];
}

- (void) insertInChatViews:(id <JVChatViewController>) view {
	[self raiseCantAddChatViewsException];
}

- (void) insertInChatViews:(id <JVChatViewController>) view atIndex:(unsigned) index {
	[self raiseCantAddChatViewsException];
}

- (void) removeFromChatViewsAtIndex:(unsigned) index {
	id <JVChatViewController> view = [_chatControllers objectAtIndex:index];
	[self disposeViewController:view];
}

- (void) replaceInChatViews:(id <JVChatViewController>) view atIndex:(unsigned) index {
	[self raiseCantAddChatViewsException];
}

#pragma mark -

- (NSArray *) chatViewsWithClass:(Class) class {
	NSMutableArray *ret = [NSMutableArray array];
	id <JVChatViewController> item = nil;
	NSEnumerator *enumerator = nil;

	enumerator = [_chatControllers objectEnumerator];
	while( ( item = [enumerator nextObject] ) )
		if( [item isMemberOfClass:class] )
			[ret addObject:item];

	return ret;
}

- (id <JVChatViewController>) valueInChatViewsAtIndex:(unsigned) index withClass:(Class) class {
	return [[self chatViewsWithClass:class] objectAtIndex:index];
}

- (id <JVChatViewController>) valueInChatViewsWithUniqueID:(id) identifier andClass:(Class) class {
	return [self valueInChatViewsWithUniqueID:identifier];
}

- (id <JVChatViewController>) valueInChatViewsWithName:(NSString *) name andClass:(Class) class {
	NSEnumerator *enumerator = [[self chatViewsWithClass:class] objectEnumerator];
	id <JVChatViewController> view = nil;

	while( ( view = [enumerator nextObject] ) )
		if( [[view title] isEqualToString:name] )
			return view;

	return nil;
}

- (void) removeFromChatViewsAtIndex:(unsigned) index withClass:(Class) class {
	id <JVChatViewController> view = [[self chatViewsWithClass:class] objectAtIndex:index];
	[self disposeViewController:view];
}

#pragma mark -

- (NSArray *) chatRooms {
	return [self chatViewsWithClass:[JVChatRoomPanel class]];
}

- (id <JVChatViewController>) valueInChatRoomsAtIndex:(unsigned) index {
	return [self valueInChatViewsAtIndex:index withClass:[JVChatRoomPanel class]];
}

- (id <JVChatViewController>) valueInChatRoomsWithUniqueID:(id) identifier {
	return [self valueInChatViewsWithUniqueID:identifier andClass:[JVChatRoomPanel class]];
}

- (id <JVChatViewController>) valueInChatRoomsWithName:(NSString *) name {
	return [self valueInChatViewsWithName:name andClass:[JVChatRoomPanel class]];
}

- (void) addInChatRooms:(id <JVChatViewController>) view {
	[self raiseCantAddChatViewsException];
}

- (void) insertInChatRooms:(id <JVChatViewController>) view {
	[self raiseCantAddChatViewsException];
}

- (void) insertInChatRooms:(id <JVChatViewController>) view atIndex:(unsigned) index {
	[self raiseCantAddChatViewsException];
}

- (void) removeFromChatRoomsAtIndex:(unsigned) index {
	[self removeFromChatViewsAtIndex:index withClass:[JVChatRoomPanel class]];
}

- (void) replaceInChatRooms:(id <JVChatViewController>) view atIndex:(unsigned) index {
	[self raiseCantAddChatViewsException];
}

#pragma mark -

- (NSArray *) directChats {
	return [self chatViewsWithClass:[JVDirectChatPanel class]];
}

- (id <JVChatViewController>) valueInDirectChatsAtIndex:(unsigned) index {
	return [self valueInChatViewsAtIndex:index withClass:[JVDirectChatPanel class]];
}

- (id <JVChatViewController>) valueInDirectChatsWithUniqueID:(id) identifier {
	return [self valueInChatViewsWithUniqueID:identifier andClass:[JVDirectChatPanel class]];
}

- (id <JVChatViewController>) valueInDirectChatsWithName:(NSString *) name {
	return [self valueInChatViewsWithName:name andClass:[JVDirectChatPanel class]];
}

- (void) addInDirectChats:(id <JVChatViewController>) view {
	[self raiseCantAddChatViewsException];
}

- (void) insertInDirectChats:(id <JVChatViewController>) view {
	[self raiseCantAddChatViewsException];
}

- (void) insertInDirectChats:(id <JVChatViewController>) view atIndex:(unsigned) index {
	[self raiseCantAddChatViewsException];
}

- (void) removeFromDirectChatsAtIndex:(unsigned) index {
	[self removeFromChatViewsAtIndex:index withClass:[JVDirectChatPanel class]];
}

- (void) replaceInDirectChats:(id <JVChatViewController>) view atIndex:(unsigned) index {
	[self raiseCantAddChatViewsException];
}

#pragma mark -

- (NSArray *) chatTranscripts {
	return [self chatViewsWithClass:[JVChatTranscriptPanel class]];
}

- (id <JVChatViewController>) valueInChatTranscriptsAtIndex:(unsigned) index {
	return [self valueInChatViewsAtIndex:index withClass:[JVChatTranscriptPanel class]];
}

- (id <JVChatViewController>) valueInChatTranscriptsWithUniqueID:(id) identifier {
	return [self valueInChatViewsWithUniqueID:identifier andClass:[JVChatTranscriptPanel class]];
}

- (id <JVChatViewController>) valueInChatTranscriptsWithName:(NSString *) name {
	return [self valueInChatViewsWithName:name andClass:[JVChatTranscriptPanel class]];
}

- (void) addInChatTranscripts:(id <JVChatViewController>) view {
	[self raiseCantAddChatViewsException];
}

- (void) insertInChatTranscripts:(id <JVChatViewController>) view {
	[self raiseCantAddChatViewsException];
}

- (void) insertInChatTranscripts:(id <JVChatViewController>) view atIndex:(unsigned) index {
	[self raiseCantAddChatViewsException];
}

- (void) removeFromChatTranscriptsAtIndex:(unsigned) index {
	[self removeFromChatViewsAtIndex:index withClass:[JVChatTranscriptPanel class]];
}

- (void) replaceInChatTranscripts:(id <JVChatViewController>) view atIndex:(unsigned) index {
	[self raiseCantAddChatViewsException];
}

#pragma mark -

- (NSArray *) chatConsoles {
	return [self chatViewsWithClass:[JVChatConsolePanel class]];
}

- (id <JVChatViewController>) valueInChatConsolesAtIndex:(unsigned) index {
	return [self valueInChatViewsAtIndex:index withClass:[JVChatConsolePanel class]];
}

- (id <JVChatViewController>) valueInChatConsolesWithUniqueID:(id) identifier {
	return [self valueInChatViewsWithUniqueID:identifier andClass:[JVChatConsolePanel class]];
}

- (id <JVChatViewController>) valueInChatConsolesWithName:(NSString *) name {
	return [self valueInChatViewsWithName:name andClass:[JVChatConsolePanel class]];
}

- (void) addInChatConsoles:(id <JVChatViewController>) view {
	[self raiseCantAddChatViewsException];
}

- (void) insertInChatConsoles:(id <JVChatViewController>) view {
	[self raiseCantAddChatViewsException];
}

- (void) insertInChatConsoles:(id <JVChatViewController>) view atIndex:(unsigned) index {
	[self raiseCantAddChatViewsException];
}

- (void) removeFromChatConsolesAtIndex:(unsigned) index {
	[self removeFromChatViewsAtIndex:index withClass:[JVChatConsolePanel class]];
}

- (void) replaceInChatConsoles:(id <JVChatViewController>) view atIndex:(unsigned) index {
	[self raiseCantAddChatViewsException];
}

#pragma mark -

- (NSArray *) indicesOfObjectsByEvaluatingRangeSpecifier:(NSRangeSpecifier *) specifier {
	NSString *key = [specifier key];

	if( [key isEqual:@"chatViews"] || [key isEqual:@"chatRooms"] || [key isEqual:@"directChats"] || [key isEqual:@"chatConsoles"] || [key isEqual:@"chatTranscripts"] ) {
		NSScriptObjectSpecifier *startSpec = [specifier startSpecifier];
		NSScriptObjectSpecifier *endSpec = [specifier endSpecifier];
		NSString *startKey = [startSpec key];
		NSString *endKey = [endSpec key];
		NSArray *chatViews = [self chatViews];

		if( ! startSpec && ! endSpec ) return nil;

		if( ! [chatViews count] ) [NSArray array];

		if( ( ! startSpec || [startKey isEqual:@"chatViews"] || [startKey isEqual:@"chatRooms"] || [startKey isEqual:@"directChats"] || [startKey isEqual:@"chatConsoles"] || [startKey isEqual:@"chatTranscripts"] ) && ( ! endSpec || [endKey isEqual:@"chatViews"] || [endKey isEqual:@"chatRooms"] || [endKey isEqual:@"directChats"] || [endKey isEqual:@"chatConsoles"] || [endKey isEqual:@"chatTranscripts"] ) ) {
			int startIndex = 0;
			int endIndex = 0;

			// The strategy here is going to be to find the index of the start and stop object in the full graphics array, regardless of what its key is.  Then we can find what we're looking for in that range of the graphics key (weeding out objects we don't want, if necessary).
			// First find the index of the first start object in the graphics array
			if( startSpec ) {
				id startObject = [startSpec objectsByEvaluatingSpecifier];
				if( [startObject isKindOfClass:[NSArray class]] ) {
					if( ! [(NSArray *)startObject count] ) startObject = nil;
					else startObject = [startObject objectAtIndex:0];
				}
				if( ! startObject ) return nil;
				startIndex = [chatViews indexOfObjectIdenticalTo:startObject];
				if( startIndex == NSNotFound ) return nil;
			}

			// Now find the index of the last end object in the graphics array
			if( endSpec ) {
				id endObject = [endSpec objectsByEvaluatingSpecifier];
				if( [endObject isKindOfClass:[NSArray class]] ) {
					if( ! [(NSArray *)endObject count] ) endObject = nil;
					else endObject = [endObject lastObject];
				}
				if( ! endObject ) return nil;
				endIndex = [chatViews indexOfObjectIdenticalTo:endObject];
				if( endIndex == NSNotFound ) return nil;
			} else endIndex = ( [chatViews count] - 1 );

			// Accept backwards ranges gracefully
			if( endIndex < startIndex ) {
				int temp = endIndex;
				endIndex = startIndex;
				startIndex = temp;
			}

			// Now startIndex and endIndex specify the end points of the range we want within the main array.
			// We will traverse the range and pick the objects we want.
			// We do this by getting each object and seeing if it actually appears in the real key that we are trying to evaluate in.
			NSMutableArray *result = [NSMutableArray array];
			BOOL keyIsGeneric = [key isEqualToString:@"chatViews"];
			NSArray *rangeKeyObjects = ( keyIsGeneric ? nil : [self valueForKey:key] );
			unsigned curKeyIndex = 0, i = 0;
			id obj = nil;

			for( i = startIndex; i <= endIndex; i++ ) {
				if( keyIsGeneric ) {
					[result addObject:[NSNumber numberWithInt:i]];
				} else {
					obj = [chatViews objectAtIndex:i];
					curKeyIndex = [rangeKeyObjects indexOfObjectIdenticalTo:obj];
					if( curKeyIndex != NSNotFound )
						[result addObject:[NSNumber numberWithInt:curKeyIndex]];
				}
			}

			return result;
		}
	}

	return nil;
}

- (NSArray *) indicesOfObjectsByEvaluatingRelativeSpecifier:(NSRelativeSpecifier *) specifier {
	NSString *key = [specifier key];

	if( [key isEqual:@"chatViews"] || [key isEqual:@"chatRooms"] || [key isEqual:@"directChats"] || [key isEqual:@"chatConsoles"] || [key isEqual:@"chatTranscripts"] ) {
		NSScriptObjectSpecifier *baseSpec = [specifier baseSpecifier];
		NSString *baseKey = [baseSpec key];
		NSArray *chatViews = [self chatViews];
		NSRelativePosition relPos = [specifier relativePosition];

		if( ! baseSpec ) return nil;

		if( ! [chatViews count] ) return [NSArray array];

		if( [baseKey isEqual:@"chatViews"] || [baseKey isEqual:@"chatRooms"] || [baseKey isEqual:@"directChats"] || [baseKey isEqual:@"chatConsoles"] || [baseKey isEqual:@"chatTranscripts"] ) {
			int baseIndex = 0;

			// The strategy here is going to be to find the index of the base object in the full graphics array, regardless of what its key is.  Then we can find what we're looking for before or after it.
			// First find the index of the first or last base object in the master array
			// Base specifiers are to be evaluated within the same container as the relative specifier they are the base of. That's this container.

			id baseObject = [baseSpec objectsByEvaluatingWithContainers:self];
			if( [baseObject isKindOfClass:[NSArray class]] ) {
				int baseCount = [(NSArray *)baseObject count];
				if( baseCount ) {
					if( relPos == NSRelativeBefore ) baseObject = [baseObject objectAtIndex:0];
					else baseObject = [baseObject objectAtIndex:( baseCount - 1 )];
				} else baseObject = nil;
			}

			if( ! baseObject ) return nil;

			baseIndex = [chatViews indexOfObjectIdenticalTo:baseObject];
			if( baseIndex == NSNotFound ) return nil;

			// Now baseIndex specifies the base object for the relative spec in the master array.
			// We will start either right before or right after and look for an object that matches the type we want.
			// We do this by getting each object and seeing if it actually appears in the real key that we are trying to evaluate in.
			NSMutableArray *result = [NSMutableArray array];
			BOOL keyIsGeneric = [key isEqual:@"chatViews"];
			NSArray *relKeyObjects = ( keyIsGeneric ? nil : [self valueForKey:key] );
			unsigned curKeyIndex = 0, viewCount = [chatViews count];
			id obj = nil;

			if( relPos == NSRelativeBefore ) baseIndex--;
			else baseIndex++;

			while( baseIndex >= 0 && baseIndex < viewCount ) {
				if( keyIsGeneric ) {
					[result addObject:[NSNumber numberWithInt:baseIndex]];
					break;
				} else {
					obj = [chatViews objectAtIndex:baseIndex];
					curKeyIndex = [relKeyObjects indexOfObjectIdenticalTo:obj];
					if( curKeyIndex != NSNotFound ) {
						[result addObject:[NSNumber numberWithInt:curKeyIndex]];
						break;
					}
				}

				if( relPos == NSRelativeBefore ) baseIndex--;
				else baseIndex++;
			}

			return result;
		}
	}

	return nil;
}

- (NSArray *) indicesOfObjectsByEvaluatingObjectSpecifier:(NSScriptObjectSpecifier *) specifier {
	if( [specifier isKindOfClass:[NSRangeSpecifier class]] ) {
		return [self indicesOfObjectsByEvaluatingRangeSpecifier:(NSRangeSpecifier *) specifier];
	} else if( [specifier isKindOfClass:[NSRelativeSpecifier class]] ) {
		return [self indicesOfObjectsByEvaluatingRelativeSpecifier:(NSRelativeSpecifier *) specifier];
	}
	return nil;
}
@end