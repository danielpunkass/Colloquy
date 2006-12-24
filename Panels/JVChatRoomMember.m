#import "JVChatRoomPanel.h"
#import "JVChatRoomMember.h"
#import "JVChatController.h"
#import "MVBuddyListController.h"
#import "MVFileTransferController.h"
#import "JVBuddy.h"
#import "JVChatUserInspector.h"
#import "MVConnectionsController.h"
#import "MVChatUserAdditions.h"

@interface JVChatRoomMember (JVChatMemberPrivate)
- (NSString *) _selfStoredNickname;
- (NSString *) _selfCompositeName;
@end

#pragma mark -

@implementation JVChatRoomMember
+ (void) initialize {
	[super initialize];
	static BOOL tooLate = NO;
	if( ! tooLate ) {
		[[NSScriptCoercionHandler sharedCoercionHandler] registerCoercer:[self class] selector:@selector( coerceChatRoomMember:toString: ) toConvertFromClass:[JVChatRoomMember class] toClass:[NSString class]];
		tooLate = YES;
	}
}

+ (id) coerceChatRoomMember:(id) value toString:(Class) class {
	return [value nickname];
}

#pragma mark -

- (id) initWithRoom:(JVChatRoomPanel *) room andUser:(MVChatUser *) user {
	if( ( self = [self init] ) ) {
		_room = room; // prevent circular retain
		_user = [user retain];

		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector( _refreshIcon: ) name:MVChatUserInformationUpdatedNotification object:user];
	}

	return self;
}

- (id) initLocalMemberWithRoom:(JVChatRoomPanel *) room {
	return ( self = [self initWithRoom:room andUser:[[room connection] localUser]] );
}

- (void) dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self name:MVChatUserInformationUpdatedNotification object:_user];

	[_user release];

	_room = nil;
	_user = nil;

	[super dealloc];
}

#pragma mark -
#pragma mark Comparisons

- (NSComparisonResult) compare:(JVChatRoomMember *) member {
	return [[self title] caseInsensitiveCompare:[member title]];
}

- (NSComparisonResult) compareUsingStatus:(JVChatRoomMember *) member {
	NSComparisonResult retVal = NSOrderedSame;
	unsigned long myStatus = 0, yourStatus = 0;

	myStatus = ( [self serverOperator] ? 1 << 8 : [[_room target] modesForMemberUser:_user] & ~MVChatRoomMemberQuietedMode );
	yourStatus = ( [member serverOperator] ? 1 << 8 : [[[member room] target] modesForMemberUser:[member user]] & ~MVChatRoomMemberQuietedMode );

	if( myStatus > yourStatus ) {
		retVal = NSOrderedAscending;
	} else if( yourStatus > myStatus ) {
		retVal = NSOrderedDescending;
	} else {
		// retVal = [self compareUsingBuddyStatus:member];
		retVal = [[self title] caseInsensitiveCompare:[member title]];
	}

	return retVal;
}

- (NSComparisonResult) compareUsingBuddyStatus:(JVChatRoomMember *) member {
	NSComparisonResult retVal;

	if( ( [self buddy] && [member buddy]) || ( ! [self buddy] && ! [member buddy]) ) {
		if( [self buddy] && [member buddy] ) {
			// if both are buddies, sort by availability
			retVal = [[self buddy] availabilityCompare:[member buddy]];
		} else {
			retVal = [[self title] caseInsensitiveCompare:[member title]]; // maybe an alpha sort here
		}
	} else if( [self buddy] ) {
		// we have a buddy but since the first test failed, member does not
		// so of course the buddy is greater :)
		retVal = NSOrderedAscending;
	} else {
		// member is a buddy
		retVal = NSOrderedDescending;
	}

	return retVal;
}

#pragma mark -
#pragma mark Associations

- (JVChatRoomPanel *) room {
	return _room;
}

- (MVChatConnection *) connection {
	return [_user connection];
}

- (MVChatUser *) user {
	return _user;
}

- (JVBuddy *) buddy {
	return [[MVBuddyListController sharedBuddyList] buddyForUser:_user];
}

#pragma mark -
#pragma mark User Info

- (NSString *) displayName {
	return [_user displayName];
}

- (NSString *) nickname {
	return [_user nickname];
}

- (NSString *) realName {
	return [_user realName];
}

- (NSString *) username {
	return [_user username];
}

- (NSString *) address {
	return [_user address];
}

- (NSString *) hostmask {
	if( ! [[_user username] length] || ! [[_user address] length] ) return nil;
	return [NSString stringWithFormat:@"%@@%@", [_user username], [_user address]];
}

#pragma mark -
#pragma mark User Status

- (BOOL) quieted {
	return ( [[_room target] modesForMemberUser:_user] & MVChatRoomMemberQuietedMode );
}

- (BOOL) voice {
	return ( [[_room target] modesForMemberUser:_user] & MVChatRoomMemberVoicedMode );
}

- (BOOL) operator {
	return ( [[_room target] modesForMemberUser:_user] & MVChatRoomMemberOperatorMode );
}

- (BOOL) halfOperator {
	return ( [[_room target] modesForMemberUser:_user] & MVChatRoomMemberHalfOperatorMode );
}

- (BOOL) roomAdministrator {
	return ( [[_room target] modesForMemberUser:_user] & MVChatRoomMemberAdministratorMode );
}

- (BOOL) roomFounder {
	return ( [[_room target] modesForMemberUser:_user] & MVChatRoomMemberFounderMode );
}

- (BOOL) serverOperator {
	return [_user isServerOperator];
}

- (BOOL) isLocalUser {
	return [_user isLocalUser];
}

- (NSString *) description {
	return [self nickname];
}

- (NSString *) xmlDescription {
	return [self xmlDescriptionWithTagName:@"member"];
}

- (NSString *) xmlDescriptionWithTagName:(NSString *) tag {
	NSParameterAssert( [tag length] != 0 );

	// Full format will look like:
	// <member self="yes" nickname="..." hostmask="..." identifier="..." class="..." buddy="...">...</member>

	NSMutableString *ret = [NSMutableString string];
	[ret appendFormat:@"<%@", tag];

	if( [self isLocalUser] ) [ret appendString:@" self=\"yes\""];

	if( ! [[self displayName] isEqualToString:[self nickname]] )
		[ret appendFormat:@" nickname=\"%@\"", [[self nickname] stringByEncodingXMLSpecialCharactersAsEntities]];

	id hostmask = [self hostmask];
	if( hostmask ) [ret appendFormat:@" hostmask=\"%@\"", [hostmask stringByEncodingXMLSpecialCharactersAsEntities]];

	id uniqueId = [_user uniqueIdentifier];
	if( ! [uniqueId isEqual:[self nickname]] ) {
		if( [uniqueId isKindOfClass:[NSData class]] ) uniqueId = [uniqueId base64Encoding];
		else if( [uniqueId isKindOfClass:[NSString class]] ) uniqueId = [uniqueId stringByEncodingXMLSpecialCharactersAsEntities];
		[ret appendFormat:@" identifier=\"%@\"", uniqueId];
	}

	NSString *class = nil;
	if( [self serverOperator] ) class = @"server operator";
	else if( [self roomFounder] ) class = @"founder";
	else if( [self roomAdministrator] ) class = @"administrator";
	else if( [self operator] ) class = @"operator";
	else if( [self halfOperator] ) class = @"half operator";
	else if( [self voice] ) class = @"voice";

	if( class ) [ret appendFormat:@" class=\"%@\"", class];

	if( [self buddy] && ! [self isLocalUser] )
		[ret appendFormat:@" buddy=\"%@\"", [[[self buddy] uniqueIdentifier] stringByEncodingXMLSpecialCharactersAsEntities]];

	[ret appendFormat:@">%@</%@>", [[self displayName] stringByEncodingXMLSpecialCharactersAsEntities], tag];

	[ret stripIllegalXMLCharacters];
	return [NSString stringWithString:ret];
}

#pragma mark -
#pragma mark List Item Protocol Support

- (id <JVChatListItem>) parent {
	return _room;
}

- (NSImage *) icon {
	unsigned long modes = [[_room target] modesForMemberUser:_user];
	NSString *iconName = @"person";

	if( [_user isServerOperator] ) iconName = @"admin";
	else if( modes & MVChatRoomMemberFounderMode ) iconName = @"founder";
	else if( modes & MVChatRoomMemberAdministratorMode ) iconName = @"super-op";
	else if( modes & MVChatRoomMemberOperatorMode ) iconName = @"op";
	else if( modes & MVChatRoomMemberHalfOperatorMode ) iconName = @"half-op";
	else if( modes & MVChatRoomMemberVoicedMode ) iconName = @"voice";

	return [NSImage imageNamed:iconName];
}

- (NSImage *) statusImage {
	if( [self buddy] ) {
		switch( [[self buddy] status] ) {
			case MVChatUserAwayStatus: return [NSImage imageNamed:@"statusAway"];
			case MVChatUserAvailableStatus:
				if( [[self buddy] idleTime] >= 600. ) return [NSImage imageNamed:@"statusIdle"];
				else return [NSImage imageNamed:@"statusAvailable"];
			case MVChatUserOfflineStatus:
			default: return nil;
		}
	}

	return nil;
}

- (NSString *) title {
	if( [self isLocalUser] ) {
		JVBuddyName nameStyle = [[NSUserDefaults standardUserDefaults] integerForKey:@"JVChatSelfNameStyle"];
		if( nameStyle == JVBuddyFullName ) return [self _selfCompositeName];
		else if( nameStyle == JVBuddyGivenNickname ) return [self _selfStoredNickname];
	} else if( [self buddy] ) return [[self buddy] displayName];
	return [self nickname];
}

- (NSString *) information {
	return nil;
}

- (NSString *) toolTip {
	if( ! [[self address] length] || ! [[self username] length] ) {
		if( [[self realName] length] )
			return [NSString stringWithFormat:@"%@ (%@)", [self nickname], [self realName]];
		return [self nickname];
	}

	if( [[self realName] length] )
		return [NSString stringWithFormat:@"%@ (%@)\n%@@%@", [self nickname], [self realName], [self username], [self address]];
	return [NSString stringWithFormat:@"%@\n%@@%@", [self nickname], [self username], [self address]];
}

- (BOOL) isEnabled {
	return [_room isEnabled] && ! ( [_user status] == MVChatUserAwayStatus || [_user idleTime] > 600. );
}

#pragma mark -

- (BOOL) acceptsDraggedFileOfType:(NSString *) type {
	return YES;
}

- (void) handleDraggedFile:(NSString *) path {
	BOOL passive = [[NSUserDefaults standardUserDefaults] boolForKey:@"JVSendFilesPassively"];
	[[MVFileTransferController defaultController] addFileTransfer:[_user sendFile:path passively:passive]];
}

#pragma mark -

- (IBAction) getInfo:(id) sender {
	[[JVInspectorController inspectorOfObject:self] show:sender];
}

- (NSMenu *) menu {
	NSMenu *menu = [[[NSMenu alloc] initWithTitle:@""] autorelease];
	NSMenuItem *item = nil;

	NSArray *standardItems = [_user standardMenuItems];
	NSEnumerator *enumerator = [standardItems objectEnumerator];
	while( ( item = [enumerator nextObject] ) )
		[menu addItem:item];

	unsigned int localUserModes = ( [[self connection] localUser] ? [(MVChatRoom *)[_room target] modesForMemberUser:[[self connection] localUser]] : 0 );
	BOOL canEdit = ( localUserModes & MVChatRoomMemberOperatorMode );
	if( ! canEdit ) canEdit = ( localUserModes & MVChatRoomMemberHalfOperatorMode );
	if( ! canEdit ) canEdit = ( localUserModes & MVChatRoomMemberAdministratorMode );
	if( ! canEdit ) canEdit = ( localUserModes & MVChatRoomMemberFounderMode );
	if( ! canEdit ) canEdit = [[[self connection] localUser] isServerOperator];

	if( canEdit ) {
		[menu addItem:[NSMenuItem separatorItem]];

		item = [[[NSMenuItem alloc] initWithTitle:NSLocalizedString( @"Kick From Room", "kick from room contextual menu - admin only" ) action:@selector( kick: ) keyEquivalent:@""] autorelease];
		[item setTarget:self];
		[menu addItem:item];

		item = [[[NSMenuItem alloc] initWithTitle:NSLocalizedString( [NSString stringWithUTF8String:"Kick From Room..."], "kick from room (customized) contextual menu - admin only" ) action:@selector( customKick: ) keyEquivalent:@""] autorelease];
		[item setKeyEquivalentModifierMask:NSAlternateKeyMask];
		if( [item respondsToSelector:@selector( setAlternate: )] )
			[item setAlternate:YES];
		[item setTarget:self];
		[menu addItem:item];

		if( [self address] ) {
			item = [[[NSMenuItem alloc] initWithTitle:NSLocalizedString( @"Ban From Room", "ban from room contextual menu - admin only" ) action:@selector( ban: ) keyEquivalent:@""] autorelease];
			[item setTarget:self];
			[menu addItem:item];

			item = [[[NSMenuItem alloc] initWithTitle:NSLocalizedString( [NSString stringWithUTF8String:"Ban From Room..."], "ban from room (customized) contextual menu - admin only" ) action:@selector( customBan: ) keyEquivalent:@""] autorelease];
			[item setKeyEquivalentModifierMask:NSAlternateKeyMask];
			if( [item respondsToSelector:@selector( setAlternate: )] )
				[item setAlternate:YES];
			[item setTarget:self];
			[menu addItem:item];

			item = [[[NSMenuItem alloc] initWithTitle:NSLocalizedString( @"Kick & Ban From Room", "kickban from room contextual menu - admin only" ) action:@selector( kickban: ) keyEquivalent:@""] autorelease];
			[item setTarget:self];
			[menu addItem:item];

			item = [[[NSMenuItem alloc] initWithTitle:NSLocalizedString( [NSString stringWithUTF8String:"Kick & Ban From Room..."], "kickban from room (customized) contextual menu - admin only" ) action:@selector( customKickban: ) keyEquivalent:@""] autorelease];
			[item setKeyEquivalentModifierMask:NSAlternateKeyMask];
			if( [item respondsToSelector:@selector( setAlternate: )] )
				[item setAlternate:YES];
			[item setTarget:self];
			[menu addItem:item];
		}

		[menu addItem:[NSMenuItem separatorItem]];

		NSSet *features = [[self connection] supportedFeatures];

		if( [features containsObject:MVChatRoomMemberOperatorFeature] ) {
			// correct title is added later in validateMenuItem:
			item = [[[NSMenuItem alloc] initWithTitle:@"" action:@selector( toggleOperatorStatus: ) keyEquivalent:@""] autorelease];
			[item setTarget:self];
			[menu addItem:item];
		}

		if( [features containsObject:MVChatRoomMemberHalfOperatorFeature] ) {
			// correct title is added later in validateMenuItem:
			item = [[[NSMenuItem alloc] initWithTitle:@"" action:@selector( toggleHalfOperatorStatus: ) keyEquivalent:@""] autorelease];
			[item setTarget:self];
			[menu addItem:item];
		}

		if( [features containsObject:MVChatRoomMemberVoicedFeature] ) {
			// correct title is added later in validateMenuItem:
			item = [[[NSMenuItem alloc] initWithTitle:@"" action:@selector( toggleVoiceStatus: ) keyEquivalent:@""] autorelease];
			[item setTarget:self];
			[menu addItem:item];
		}

		if( [features containsObject:MVChatRoomMemberQuietedFeature] ) {
			// correct title is added later in validateMenuItem:
			item = [[[NSMenuItem alloc] initWithTitle:@"" action:@selector( toggleQuietedStatus: ) keyEquivalent:@""] autorelease];
			[item setTarget:self];
			[menu addItem:item];
		}
	}

	return menu;
}

- (BOOL) validateMenuItem:(NSMenuItem *) menuItem {
	if( ! [[self connection] isConnected] ) return NO;
	if( [menuItem action] == @selector( toggleVoiceStatus: ) ) {
		if( [self voice] ) {
			[menuItem setTitle:NSLocalizedString( @"Remove Voice", "remove voice contextual menu - admin only" )];
		} else {
			[menuItem setTitle:NSLocalizedString( @"Grant Voice", "grant voice contextual menu - admin only" )];
			if( [self operator] || ! [[self connection] isConnected] ) return NO;
		}
	} else if( [menuItem action] == @selector( toggleQuietedStatus: ) ) {
		if( [self quieted] ) {
			[menuItem setTitle:NSLocalizedString( @"Remove Quiet", "remove quiet contextual menu - admin only" )];
		} else {
			[menuItem setTitle:NSLocalizedString( @"Force Quiet", "force quiet contextual menu - admin only" )];
		}
	} else if( [menuItem action] == @selector( toggleOperatorStatus: ) ) {
		if( [self operator] ) {
			[menuItem setTitle:NSLocalizedString( @"Demote Operator", "demote operator contextual menu - admin only" )];
		} else {
			[menuItem setTitle:NSLocalizedString( @"Make Operator", "make operator contextual menu - admin only" )];
		}
	} else if( [menuItem action] == @selector( toggleHalfOperatorStatus: ) ) {
		if( [self halfOperator] ) {
			[menuItem setTitle:NSLocalizedString( @"Demote Half Operator", "demote half-operator contextual menu - admin only" )];
		} else {
			[menuItem setTitle:NSLocalizedString( @"Make Half Operator", "make half-operator contextual menu - admin only" )];
		}
	}
	return YES;
}

#pragma mark -
#pragma mark Scripting Support

- (NSNumber *) uniqueIdentifier {
	return [NSNumber numberWithUnsignedInt:(unsigned long) self];
}

- (NSArray *) children {
	return nil;
}

#pragma mark -
#pragma mark GUI Actions

- (IBAction) doubleClicked:(id) sender {
	[_user startChat:sender];
}

- (IBAction) startChat:(id) sender {
	[_user startChat:sender];
}

- (IBAction) sendFile:(id) sender {
	[_user sendFile:sender];
}

- (IBAction) addBuddy:(id) sender {
	[_user addBuddy:sender];
}

- (IBAction) toggleIgnore:(id) sender {
	[_user toggleIgnore:sender];
}

#pragma mark -
#pragma mark Operator Actions

- (IBAction) toggleOperatorStatus:(id) sender {
	if( [self operator] ) [[_room target] removeMode:MVChatRoomMemberOperatorMode forMemberUser:_user];
	else [[_room target] setMode:MVChatRoomMemberOperatorMode forMemberUser:_user];
}

- (IBAction) toggleHalfOperatorStatus:(id) sender {
	if( [self halfOperator] ) [[_room target] removeMode:MVChatRoomMemberHalfOperatorMode forMemberUser:_user];
	else [[_room target] setMode:MVChatRoomMemberHalfOperatorMode forMemberUser:_user];
}

- (IBAction) toggleVoiceStatus:(id) sender {
	if( [self voice] ) [[_room target] removeMode:MVChatRoomMemberVoicedMode forMemberUser:_user];
	else [[_room target] setMode:MVChatRoomMemberVoicedMode forMemberUser:_user];
}

- (IBAction) toggleQuietedStatus:(id) sender {
	if( [self quieted] ) [[_room target] removeMode:MVChatRoomMemberQuietedMode forMemberUser:_user];
	else [[_room target] setMode:MVChatRoomMemberQuietedMode forMemberUser:_user];
}

#pragma mark -

- (IBAction) kick:(id) sender {
	[[_room target] kickOutMemberUser:_user forReason:nil];
}

- (IBAction) ban:(id) sender {
	MVChatUser *user = [MVChatUser wildcardUserWithNicknameMask:nil andHostMask:[NSString stringWithFormat:@"*@%@", [self address]]];
	[[_room target] addBanForUser:user];
}

- (IBAction) customKick:(id) sender {
	if( ! _nibLoaded ) _nibLoaded = [NSBundle loadNibNamed:@"TSCustomBan" owner:self];
	if( ! _nibLoaded ) { NSLog( @"Can't load TSCustomBan.nib" ); return; }

	[banTitle setStringValue:[NSString stringWithFormat:NSLocalizedString( @"Kick %@ from the %@ room.", "kick user from room" ), [self title], [_room title]]];
	[firstTitle setStringValue:NSLocalizedString( @"With reason:", "kick reason label" )];

	[firstField setStringValue:@""];
	[banWindow makeFirstResponder:firstField];

	if( [secondTitle respondsToSelector:@selector(setHidden:)] ) {
		[secondTitle setHidden:YES];
		[secondField setHidden:YES];
	} else {
		NSRect frame = [secondTitle frame];
		frame.origin.x = 0. - frame.size.width - 10.;
		[secondTitle setFrame:frame];
		frame = [secondField frame];
		frame.origin.x = 0. - frame.size.width - 10.;
		[secondField setFrame:frame];
	}

	NSRect frame = [banWindow frame];
	frame.size.height = ( frame.size.height - [firstField frame].origin.y ) + 60.;
	[banWindow setFrame:frame display:YES];

	[banButton setAction:@selector( closeKickSheet: )];
	[banButton setTitle:NSLocalizedString( @"Kick User", "kick user button" )];
	[banButton setTarget:self];

	[[NSApplication sharedApplication] beginSheet:banWindow modalForWindow:[[_room view] window] modalDelegate:nil didEndSelector:nil contextInfo:nil];
}

- (IBAction) customBan:(id) sender {
	if( ! _nibLoaded ) _nibLoaded = [NSBundle loadNibNamed:@"TSCustomBan" owner:self];
	if( ! _nibLoaded ) { NSLog( @"Can't load TSCustomBan.nib" ); return; }

	[banTitle setStringValue:[NSString stringWithFormat:NSLocalizedString( @"Ban %@ from the %@ room.", "ban user from room label" ), [self title], [_room title]]];
	[firstTitle setStringValue:NSLocalizedString( @"With hostmask:", "ban hostmask label")];

	if( [self username] && [self address] )
		[firstField setStringValue:[NSString stringWithFormat:@"%@!%@@%@", [self nickname], [self username], [self address]]];
	else [firstField setStringValue:@""];

	[banWindow makeFirstResponder:firstField];

	if( [secondTitle respondsToSelector:@selector( setHidden: )] ) {
		[secondTitle setHidden:YES];
		[secondField setHidden:YES];
	} else {
		NSRect frame = [secondTitle frame];
		frame.origin.x = 0. - frame.size.width - 10.;
		[secondTitle setFrame:frame];
		frame = [secondField frame];
		frame.origin.x = 0. - frame.size.width - 10.;
		[secondField setFrame:frame];
	}

	NSRect frame = [banWindow frame];
	frame.size.height = ( frame.size.height - [firstField frame].origin.y ) + 60.;
	[banWindow setFrame:frame display:YES];

	[banButton setAction:@selector( closeBanSheet: )];
	[banButton setTitle:NSLocalizedString( @"Ban User", "ban user button" )];
	[banButton setTarget:self];

	[[NSApplication sharedApplication] beginSheet:banWindow modalForWindow:[[_room view] window] modalDelegate:nil didEndSelector:nil contextInfo:nil];
}

- (IBAction) kickban:(id) sender {
	[self ban:nil];
	[self kick:nil];
}

- (IBAction) customKickban:(id) sender {
	if( ! _nibLoaded ) _nibLoaded = [NSBundle loadNibNamed:@"TSCustomBan" owner:self];
	if( ! _nibLoaded ) { NSLog(@"Can't load TSCustomBan.nib"); return; }

	[banTitle setStringValue:[NSString stringWithFormat:NSLocalizedString( @"Kick and ban %@ from the %@ room.", "kickban user from room" ), [self title], [_room title]]];
	[banTitle sizeToFit];

	[firstTitle setStringValue:NSLocalizedString( @"With hostmask:", "ban hostmask" )];
	[secondTitle setStringValue:NSLocalizedString( @"And reason:", "kick reason (secondary)" )];

	if( [self username] && [self address] )
		[firstField setStringValue:[NSString stringWithFormat:@"%@!%@@%@", [self nickname], [self username], [self address]]];
	else [firstField setStringValue:@""];
	[secondField setStringValue:@""];

	[banWindow makeFirstResponder:firstField];

	if( [secondTitle respondsToSelector:@selector( setHidden: )] ) {
		[secondTitle setHidden:NO];
		[secondField setHidden:NO];
	} else {
		NSRect frame = [secondTitle frame];
		frame.origin.y = [firstField frame].origin.y - frame.size.height - 8;
		frame.origin.x = [firstField frame].origin.x;
		[secondTitle setFrame:frame];
		frame.size = [secondField frame].size;
		frame.origin.y = frame.origin.y - frame.size.height - 8;
		[secondField setFrame:frame];
	}

	NSRect frame = [banWindow frame];
	frame.size.height = ( frame.size.height - [secondField frame].origin.y ) + 60;
	[banWindow setFrame:frame display:YES];

	[banButton setAction:@selector( closeKickbanSheet: )];
	[banButton setTitle:NSLocalizedString( @"Kick & Ban User", "kick and ban user button" )];
	[banButton setTarget:self];

	[[NSApplication sharedApplication] beginSheet:banWindow modalForWindow:[[_room view] window] modalDelegate:nil didEndSelector:nil contextInfo:nil];
}

- (IBAction) closeKickSheet:(id) sender {
	[[NSApplication sharedApplication] endSheet:banWindow];
	[banWindow orderOut:self];

	NSAttributedString *reason = [[[NSAttributedString alloc] initWithString:[firstField stringValue]] autorelease];
	[[_room target] kickOutMemberUser:_user forReason:reason];
}

- (IBAction) closeBanSheet:(id) sender {
	[[NSApplication sharedApplication] endSheet:banWindow];
	[banWindow orderOut:self];

	MVChatUser *user = [MVChatUser wildcardUserFromString:[firstField stringValue]];
	[[_room target] addBanForUser:user];
}

- (IBAction) closeKickbanSheet:(id) sender {
	[[NSApplication sharedApplication] endSheet:banWindow];
	[banWindow orderOut:self];

	MVChatUser *user = [MVChatUser wildcardUserFromString:[firstField stringValue]];
	[[_room target] addBanForUser:user];

	NSAttributedString *reason = [[[NSAttributedString alloc] initWithString:[secondField stringValue]] autorelease];
	[[_room target] kickOutMemberUser:_user forReason:reason];
}

- (IBAction) cancelSheet:(id) sender {
	[[NSApplication sharedApplication] endSheet:banWindow];
	[banWindow orderOut:self];
}

#pragma mark -

- (id) valueForUndefinedKey:(NSString *) key {
	if( [NSScriptCommand currentCommand] ) {
		[[NSScriptCommand currentCommand] setScriptErrorNumber:1000];
		[[NSScriptCommand currentCommand] setScriptErrorString:[NSString stringWithFormat:@"The member id %@ of chat room panel id %@ doesn't have the \"%@\" property.", [self uniqueIdentifier], [_room uniqueIdentifier], key]];
		return nil;
	}

	return [super valueForUndefinedKey:key];
}

- (void) setValue:(id) value forUndefinedKey:(NSString *) key {
	if( [NSScriptCommand currentCommand] ) {
		[[NSScriptCommand currentCommand] setScriptErrorNumber:1000];
		[[NSScriptCommand currentCommand] setScriptErrorString:[NSString stringWithFormat:@"The \"%@\" property of member id %@ of chat room panel id %@ is read only.", key, [self uniqueIdentifier], [_room uniqueIdentifier]]];
		return;
	}

	[super setValue:value forUndefinedKey:key];
}
@end

#pragma mark -

@implementation JVChatRoomMember (JVChatMemberPrivate)
- (void) _refreshIcon:(NSNotification *) notification {
	[[_room windowController] reloadListItem:self andChildren:NO];
}

- (NSString *) _selfCompositeName {
	ABPerson *_person = [[ABAddressBook sharedAddressBook] me];
	NSString *firstName = [_person valueForProperty:kABFirstNameProperty];
	NSString *lastName = [_person valueForProperty:kABLastNameProperty];

	if( ! firstName && lastName ) return lastName;
	else if( firstName && ! lastName ) return firstName;
	else if( firstName && lastName ) {
		return [NSString stringWithFormat:@"%@ %@", firstName, lastName];
	}

	firstName = [_person valueForProperty:kABNicknameProperty];
	if( firstName ) return firstName;

	return [[self connection] nickname];
}

- (NSString *) _selfStoredNickname {
	NSString *nickname = [[[ABAddressBook sharedAddressBook] me] valueForProperty:kABNicknameProperty];
	if( nickname ) return nickname;
	return [[self connection] nickname];
}
@end
