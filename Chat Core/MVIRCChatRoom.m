#import "MVIRCChatRoom.h"

#import "MVIRCChatConnection.h"
#import "MVIRCChatUser.h"
#import "NSStringAdditions.h"
#import "RegexKitLite.h"

@implementation MVIRCChatRoom
- (id) initWithName:(NSString *) roomName andConnection:(MVIRCChatConnection *) roomConnection {
	if( ( self = [self init] ) ) {
		_connection = [roomConnection retain];
		_name = [roomName copyWithZone:nil];
		_uniqueIdentifier = [[roomName lowercaseString] retain];
		[_connection _addKnownRoom:self];
	}

	return self;
}

#pragma mark -

- (NSUInteger) supportedModes {
	return ( MVChatRoomPrivateMode | MVChatRoomSecretMode | MVChatRoomInviteOnlyMode | MVChatRoomNormalUsersSilencedMode | MVChatRoomOperatorsOnlySetTopicMode | MVChatRoomNoOutsideMessagesMode | MVChatRoomPassphraseToJoinMode | MVChatRoomLimitNumberOfMembersMode );
}

- (NSUInteger) supportedMemberUserModes {
	NSUInteger supported = ( MVChatRoomMemberVoicedMode | MVChatRoomMemberOperatorMode );
	supported |= MVChatRoomMemberQuietedMode; // optional later
	supported |= MVChatRoomMemberHalfOperatorMode; // optional later
	supported |= MVChatRoomMemberAdministratorMode; // optional later
	supported |= MVChatRoomMemberFounderMode; // optional later
	return supported;
}

- (NSString *) displayName {
	if ([[self name] length] > 2 && [[self name] characterAtIndex:1] == '#') return [[self name] substringFromIndex:2];
	else if ([[self name] length] > 1 && [[self name] characterAtIndex:1] != '#') return [[self name] substringFromIndex:1];
	else return [self name];
}

#pragma mark -

- (void) partWithReason:(MVChatString *) reason {
	if( ! [self isJoined] ) return;

	if( [reason length] ) {
		NSData *reasonData = [MVIRCChatConnection _flattenedIRCDataForMessage:reason withEncoding:[self encoding] andChatFormat:[[self connection] outgoingChatFormat]];
		NSString *prefix = [[NSString allocWithZone:nil] initWithFormat:@"PART %@ :", [self name]];
		[[self connection] sendRawMessageWithComponents:prefix, reasonData, nil];
		[prefix release];
	} else [[self connection] sendRawMessageImmediatelyWithFormat:@"PART %@", [self name]];
}

#pragma mark -

- (void) changeTopic:(MVChatString *) newTopic {
	NSParameterAssert( newTopic != nil );
	NSData *msg = [MVIRCChatConnection _flattenedIRCDataForMessage:newTopic withEncoding:[self encoding] andChatFormat:[[self connection] outgoingChatFormat]];
	NSString *prefix = [[NSString allocWithZone:nil] initWithFormat:@"TOPIC %@ :", [self name]];
	[[self connection] sendRawMessageWithComponents:prefix, msg, nil];
	[prefix release];
}

#pragma mark -

- (void) sendMessage:(MVChatString *) message withEncoding:(NSStringEncoding) msgEncoding withAttributes:(NSDictionary *) attributes {
	NSParameterAssert( message != nil );
	[[self connection] _sendMessage:message withEncoding:msgEncoding toTarget:self withTargetPrefix:nil withAttributes:attributes localEcho:NO];
}

- (void) sendCommand:(NSString *) command withArguments:(MVChatString *) arguments withEncoding:(NSStringEncoding) encoding {
	NSParameterAssert( command != nil );
	[[self connection] _sendCommand:command withArguments:arguments withEncoding:encoding toTarget:self];
}

#pragma mark -

- (void) sendSubcodeRequest:(NSString *) command withArguments:(id) arguments {
	NSParameterAssert( command != nil );
	if( arguments && [arguments isKindOfClass:[NSData class]] && [arguments length] ) {
		NSString *prefix = [[NSString allocWithZone:nil] initWithFormat:@"PRIVMSG %@ :\001%@ ", [self name], command];
		[[self connection] sendRawMessageWithComponents:prefix, arguments, @"\001", nil];
		[prefix release];
	} else if( arguments && [arguments isKindOfClass:[NSString class]] && [arguments length] ) {
		[[self connection] sendRawMessageWithFormat:@"PRIVMSG %@ :\001%@ %@\001", [self name], command, arguments];
	} else [[self connection] sendRawMessageWithFormat:@"PRIVMSG %@ :\001%@\001", [self name], command];
}

- (void) sendSubcodeReply:(NSString *) command withArguments:(id) arguments {
	NSParameterAssert( command != nil );
	if( arguments && [arguments isKindOfClass:[NSData class]] && [arguments length] ) {
		NSString *prefix = [[NSString allocWithZone:nil] initWithFormat:@"NOTICE %@ :\001%@ ", [self name], command];
		[[self connection] sendRawMessageWithComponents:prefix, arguments, @"\001", nil];
		[prefix release];
	} else if( arguments && [arguments isKindOfClass:[NSString class]] && [arguments length] ) {
		[[self connection] sendRawMessageWithFormat:@"NOTICE %@ :\001%@ %@\001", [self name], command, arguments];
	} else [[self connection] sendRawMessageWithFormat:@"NOTICE %@ :\001%@\001", [self name], command];
}

#pragma mark -

- (void) setMode:(MVChatRoomMode) mode withAttribute:(id) attribute {
	[super setMode:mode withAttribute:attribute];

	switch( mode ) {
	case MVChatRoomPrivateMode:
		[[self connection] sendRawMessageWithFormat:@"MODE %@ +p", [self name]];
		break;
	case MVChatRoomSecretMode:
		[[self connection] sendRawMessageWithFormat:@"MODE %@ +s", [self name]];
		break;
	case MVChatRoomInviteOnlyMode:
		[[self connection] sendRawMessageWithFormat:@"MODE %@ +i", [self name]];
		break;
	case MVChatRoomNormalUsersSilencedMode:
		[[self connection] sendRawMessageWithFormat:@"MODE %@ +m", [self name]];
		break;
	case MVChatRoomOperatorsOnlySetTopicMode:
		[[self connection] sendRawMessageWithFormat:@"MODE %@ +t", [self name]];
		break;
	case MVChatRoomNoOutsideMessagesMode:
		[[self connection] sendRawMessageWithFormat:@"MODE %@ +n", [self name]];
		break;
	case MVChatRoomPassphraseToJoinMode:
		[[self connection] sendRawMessageWithFormat:@"MODE %@ +k %@", [self name], attribute];
		break;
	case MVChatRoomLimitNumberOfMembersMode:
		[[self connection] sendRawMessageWithFormat:@"MODE %@ +l %@", [self name], attribute];
	default:
		break;
	}
}

- (void) removeMode:(MVChatRoomMode) mode {
	[super removeMode:mode];

	switch( mode ) {
	case MVChatRoomPrivateMode:
		[[self connection] sendRawMessageWithFormat:@"MODE %@ -p", [self name]];
		break;
	case MVChatRoomSecretMode:
		[[self connection] sendRawMessageWithFormat:@"MODE %@ -s", [self name]];
		break;
	case MVChatRoomInviteOnlyMode:
		[[self connection] sendRawMessageWithFormat:@"MODE %@ -i", [self name]];
		break;
	case MVChatRoomNormalUsersSilencedMode:
		[[self connection] sendRawMessageWithFormat:@"MODE %@ -m", [self name]];
		break;
	case MVChatRoomOperatorsOnlySetTopicMode:
		[[self connection] sendRawMessageWithFormat:@"MODE %@ -t", [self name]];
		break;
	case MVChatRoomNoOutsideMessagesMode:
		[[self connection] sendRawMessageWithFormat:@"MODE %@ -n", [self name]];
		break;
	case MVChatRoomPassphraseToJoinMode:
		[[self connection] sendRawMessageWithFormat:@"MODE %@ -k %@", [self name], ( [self attributeForMode:MVChatRoomPassphraseToJoinMode] != nil ? [self attributeForMode:MVChatRoomPassphraseToJoinMode] : @"*" )];
		break;
	case MVChatRoomLimitNumberOfMembersMode:
		[[self connection] sendRawMessageWithFormat:@"MODE %@ -l", [self name]];
	default:
		break;
	}
}

#pragma mark -

- (void) setMode:(MVChatRoomMemberMode) mode forMemberUser:(MVChatUser *) user {
	[super setMode:mode forMemberUser:user];

	switch( mode ) {
	case MVChatRoomMemberFounderMode:
		[[self connection] sendRawMessageWithFormat:@"MODE %@ +q %@", [self name], [user nickname]];
		break;
	case MVChatRoomMemberAdministratorMode:
		[[self connection] sendRawMessageWithFormat:@"MODE %@ +a %@", [self name], [user nickname]];
		break;
	case MVChatRoomMemberOperatorMode:
		[[self connection] sendRawMessageWithFormat:@"MODE %@ +o %@", [self name], [user nickname]];
		break;
	case MVChatRoomMemberHalfOperatorMode:
		[[self connection] sendRawMessageWithFormat:@"MODE %@ +h %@", [self name], [user nickname]];
		break;
	case MVChatRoomMemberVoicedMode:
		[[self connection] sendRawMessageWithFormat:@"MODE %@ +v %@", [self name], [user nickname]];
		break;
	case MVChatRoomMemberQuietedMode:
		[[self connection] sendRawMessageWithFormat:@"MODE %@ +q %@", [self name], [user nickname]];
	default:
		break;
	}
}

- (void) removeMode:(MVChatRoomMemberMode) mode forMemberUser:(MVChatUser *) user {
	[super removeMode:mode forMemberUser:user];

	switch( mode ) {
	case MVChatRoomMemberFounderMode:
		[[self connection] sendRawMessageWithFormat:@"MODE %@ -q %@", [self name], [user nickname]];
		break;
	case MVChatRoomMemberAdministratorMode:
		[[self connection] sendRawMessageWithFormat:@"MODE %@ -a %@", [self name], [user nickname]];
		break;
	case MVChatRoomMemberOperatorMode:
		[[self connection] sendRawMessageWithFormat:@"MODE %@ -o %@", [self name], [user nickname]];
		break;
	case MVChatRoomMemberHalfOperatorMode:
		[[self connection] sendRawMessageWithFormat:@"MODE %@ -h %@", [self name], [user nickname]];
		break;
	case MVChatRoomMemberVoicedMode:
		[[self connection] sendRawMessageWithFormat:@"MODE %@ -v %@", [self name], [user nickname]];
		break;
	case MVChatRoomMemberQuietedMode:
		[[self connection] sendRawMessageWithFormat:@"MODE %@ -q %@", [self name], [user nickname]];
	default:
		break;
	}
}

#pragma mark -

- (NSSet *) memberUsersWithNickname:(NSString *) nickname {
	MVChatUser *user = [self memberUserWithUniqueIdentifier:nickname];
	if( user ) return [NSSet setWithObject:user];
	return nil;
}

- (MVChatUser *) memberUserWithUniqueIdentifier:(id) identifier {
	if( ! [identifier isKindOfClass:[NSString class]] ) return nil;

	NSString *uniqueIdentfier = [identifier lowercaseString];

	@synchronized( _memberUsers ) {
		MVChatUser *user = nil;
		NSEnumerator *enumerator = [_memberUsers objectEnumerator];
		while( ( user = [enumerator nextObject] ) )
			if( [[user uniqueIdentifier] isEqualToString:uniqueIdentfier] )
				return user;
	}

	return nil;
}

#pragma mark -

- (void) kickOutMemberUser:(MVChatUser *) user forReason:(MVChatString *) reason {
	[super kickOutMemberUser:user forReason:reason];

	if( reason ) {
		NSData *msg = [MVIRCChatConnection _flattenedIRCDataForMessage:reason withEncoding:[self encoding] andChatFormat:[[self connection] outgoingChatFormat]];
		NSString *prefix = [[NSString allocWithZone:nil] initWithFormat:@"KICK %@ %@ :", [self name], [user nickname]];
		[[self connection] sendRawMessageImmediatelyWithComponents:prefix, msg, nil];
		[prefix release];
	} else [[self connection] sendRawMessageImmediatelyWithFormat:@"KICK %@ %@", [self name], [user nickname]];
}

- (void) addBanForUser:(MVChatUser *) user {
	if ([[user nickname] hasCaseInsensitiveSubstring:@"$"] || [[user nickname] hasCaseInsensitiveSubstring:@":"] || [[user nickname] hasCaseInsensitiveSubstring:@"~"]) { // extended bans on ircd-seven, inspircd and unrealircd
		if ([[user nickname] hasCaseInsensitiveSubstring:@"~q"] || [[user nickname] hasCaseInsensitiveSubstring:@"~n"]) // These two extended bans on unreal-style ircds take full hostmasks as their arguments
			[[self connection] sendRawMessageImmediatelyWithFormat:@"MODE %@ +b %@", [self name], [user displayName]];
		else
			[[self connection] sendRawMessageImmediatelyWithFormat:@"MODE %@ +b %@", [self name], [user nickname]];
	} else if ( [user isWildcardUser] || ! [user username] || ! [user address] )
		[[self connection] sendRawMessageImmediatelyWithFormat:@"MODE %@ +b %@!%@@%@", [self name], ( [user nickname] ? [user nickname] : @"*" ), ( [user username] ? [user username] : @"*" ), ( [user address] ? [user address] : @"*" )];
	else {
		NSString *addressToBan = [self modifyAddressForBan:user];

		[[self connection] sendRawMessageImmediatelyWithFormat:@"MODE %@ +b *!*%@*@%@", [self name], [user username], addressToBan ];
	}
	[super addBanForUser:user];
}

- (void) removeBanForUser:(MVChatUser *) user {
	if ([[user nickname] hasCaseInsensitiveSubstring:@"$"] || [[user nickname] hasCaseInsensitiveSubstring:@":"] || [[user nickname] hasCaseInsensitiveSubstring:@"~"]) { // extended bans on ircd-seven, inspircd and unrealircd
		if ([[user nickname] hasCaseInsensitiveSubstring:@"~q"] || [[user nickname] hasCaseInsensitiveSubstring:@"~n"]) // These two extended bans on unreal-style ircds take full hostmasks as their arguments
			[[self connection] sendRawMessageImmediatelyWithFormat:@"MODE %@ -b %@", [self name], [user displayName]];
		else
			[[self connection] sendRawMessageImmediatelyWithFormat:@"MODE %@ -b %@", [self name], [user nickname]];
	} else if ( [user isWildcardUser] || ! [user username] || ! [user address] )
		[[self connection] sendRawMessageImmediatelyWithFormat:@"MODE %@ -b %@!%@@%@", [self name], ( [user nickname] ? [user nickname] : @"*" ), ( [user username] ? [user username] : @"*" ), ( [user address] ? [user address] : @"*" )];
	else {
		NSString *addressToBan = [self modifyAddressForBan:user];

		[[self connection] sendRawMessageImmediatelyWithFormat:@"MODE %@ -b *!*%@*@%@", [self name], [user username], addressToBan ];
	}
	[super removeBanForUser:user];
}

- (NSString *) modifyAddressForBan:(MVChatUser *) user {
	NSCharacterSet *newSectionOfHostmaskCharacterSet = [NSCharacterSet characterSetWithCharactersInString:@".:/"];
	NSString *addressMaskToRemove = nil;
	NSString *addressMaskToBan = @"*";
	NSString *addressMask = [user address];
	NSScanner *scanner = nil;

	NSString *regexForIPv4Addresses = @"\\b(?:\\d{1,3}\\.){3}\\d{1,3}\\b";
	NSString *regexForIPv6Addresses = @"/^\\s*((([0-9A-Fa-f]{1,4}:){7}(([0-9A-Fa-f]{1,4})|:))|(([0-9A-Fa-f]{1,4}:){6}(:|((25[0-5]|2[0-4]\\d|[01]?\\d{1,2})(\\.(25[0-5]|2[0-4]\\d|[01]?\\d{1,2})){3})|(:[0-9A-Fa-f]{1,4})))|(([0-9A-Fa-f]{1,4}:){5}((:((25[0-5]|2[0-4]\\d|[01]?\\d{1,2})(\\.(25[0-5]|2[0-4]\\d|[01]?\\d{1,2})){3})?)|((:[0-9A-Fa-f]{1,4}){1,2})))|(([0-9A-Fa-f]{1,4}:){4}(:[0-9A-Fa-f]{1,4}){0,1}((:((25[0-5]|2[0-4]\\d|[01]?\\d{1,2})(\\.(25[0-5]|2[0-4]\\d|[01]?\\d{1,2})){3})?)|((:[0-9A-Fa-f]{1,4}){1,2})))|(([0-9A-Fa-f]{1,4}:){3}(:[0-9A-Fa-f]{1,4}){0,2}((:((25[0-5]|2[0-4]\\d|[01]?\\d{1,2})(\\.(25[0-5]|2[0-4]\\d|[01]?\\d{1,2})){3})?)|((:[0-9A-Fa-f]{1,4}){1,2})))|(([0-9A-Fa-f]{1,4}:){2}(:[0-9A-Fa-f]{1,4}){0,3}((:((25[0-5]|2[0-4]\\d|[01]?\\d{1,2})(\\.(25[0-5]|2[0-4]\\d|[01]?\\d{1,2})){3})?)|((:[0-9A-Fa-f]{1,4}){1,2})))|(([0-9A-Fa-f]{1,4}:)(:[0-9A-Fa-f]{1,4}){0,4}((:((25[0-5]|2[0-4]\\d|[01]?\\d{1,2})(\\.(25[0-5]|2[0-4]\\d|[01]?\\d{1,2})){3})?)|((:[0-9A-Fa-f]{1,4}){1,2})))|(:(:[0-9A-Fa-f]{1,4}){0,5}((:((25[0-5]|2[0-4]\\d|[01]?\\d{1,2})(\\.(25[0-5]|2[0-4]\\d|[01]?\\d{1,2})){3})?)|((:[0-9A-Fa-f]{1,4}){1,2})))|(((25[0-5]|2[0-4]\\d|[01]?\\d{1,2})(\\.(25[0-5]|2[0-4]\\d|[01]?\\d{1,2})){3})))(%.+)?\\s*$/";

	if ( [addressMask hasCaseInsensitiveSuffix:@"IP"] ) {
		addressMaskToBan = [[addressMask substringToIndex:[addressMask length] - 2] stringByAppendingString:@"*"];
	} else if ( [addressMask isMatchedByRegex:regexForIPv4Addresses] || [addressMask isMatchedByRegex:regexForIPv6Addresses] ) {
		NSString *reversedIP = [NSString stringByReversingString:addressMask];
		scanner = [NSScanner scannerWithString:reversedIP];

		[scanner setCharactersToBeSkipped:nil];
		[scanner scanUpToCharactersFromSet:newSectionOfHostmaskCharacterSet intoString:&addressMaskToRemove];

		addressMaskToBan = [[addressMask substringToIndex:([addressMask length] - [addressMaskToRemove length])] stringByAppendingString:@"*"];
	} else {
		scanner = [NSScanner scannerWithString:addressMask];

		[scanner setCharactersToBeSkipped:nil];
		[scanner scanUpToCharactersFromSet:newSectionOfHostmaskCharacterSet intoString:&addressMaskToRemove];

		addressMaskToBan = [addressMaskToBan stringByAppendingString:[addressMask substringFromIndex:[addressMaskToRemove length]]];
	}

	if ( ! [scanner isAtEnd] )
		return addressMaskToBan;
	return addressMask;
}

@end

#pragma mark -

@implementation MVIRCChatRoom (MVIRCChatRoomPrivate)
- (BOOL) _namesSynced {
	return _namesSynced;
}

- (void) _setNamesSynced:(BOOL) synced {
	_namesSynced = synced;
}

- (BOOL) _bansSynced {
	return _bansSynced;
}

- (void) _setBansSynced:(BOOL) synced {
	_bansSynced = synced;
}

- (void) _clearMemberUsers {
	[super _clearMemberUsers];
	[self _setNamesSynced:NO];
}

- (void) _clearBannedUsers {
	[super _clearBannedUsers];
	[self _setBansSynced:NO];
}
@end
