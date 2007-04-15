#import "MVIRCChatUser.h"
#import "MVIRCChatConnection.h"
#import "NSStringAdditions.h"
#import "MVUtilities.h"

@implementation MVIRCChatUser
- (id) initLocalUserWithConnection:(MVIRCChatConnection *) userConnection {
	if( ( self = [self initWithNickname:nil andConnection:userConnection] ) ) {
		_type = MVChatLocalUserType;
		MVSafeCopyAssign( &_uniqueIdentifier, [[self nickname] lowercaseString] );
	}

	return self;
}

- (id) initWithNickname:(NSString *) userNickname andConnection:(MVIRCChatConnection *) userConnection {
	if( ( self = [self init] ) ) {
		_type = MVChatRemoteUserType;
		_connection = userConnection; // prevent circular retain
		MVSafeCopyAssign( &_nickname, userNickname );
		MVSafeCopyAssign( &_uniqueIdentifier, [userNickname lowercaseString] );
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector( ctcpReplyNotification: ) name:MVChatConnectionSubcodeReplyNotification object:self];
	}

	return self;
}

- (void) dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[super dealloc];
}

#pragma mark -

- (unsigned long) supportedModes {
	return MVChatUserInvisibleMode;
}

- (NSSet *) supportedAttributes {
	return [NSSet setWithObjects:MVChatUserPingAttribute, MVChatUserKnownRoomsAttribute, MVChatUserLocalTimeAttribute, MVChatUserClientInfoAttribute, nil];
}

#pragma mark -

- (void) sendMessage:(NSAttributedString *) message withEncoding:(NSStringEncoding) encoding withAttributes:(NSDictionary *) attributes {
	NSParameterAssert( message != nil );
	[[self connection] _sendMessage:message withEncoding:encoding toTarget:self withAttributes:attributes];
}

- (void) sendSubcodeRequest:(NSString *) command withArguments:(id) arguments {
	NSParameterAssert( command != nil );
	if( arguments && [arguments isKindOfClass:[NSData class]] && [arguments length] ) {
		NSString *prefix = [[NSString allocWithZone:nil] initWithFormat:@"PRIVMSG %@ :\001%@ ", [self nickname], command];
		[[self connection] sendRawMessageWithComponents:prefix, arguments, @"\001", nil];
		[prefix release];
	} else if( arguments && [arguments isKindOfClass:[NSString class]] && [arguments length] ) {
		[[self connection] sendRawMessageWithFormat:@"PRIVMSG %@ :\001%@ %@\001", [self nickname], command, arguments];
	} else [[self connection] sendRawMessageWithFormat:@"PRIVMSG %@ :\001%@\001", [self nickname], command];
}

- (void) sendSubcodeReply:(NSString *) command withArguments:(id) arguments {
	NSParameterAssert( command != nil );
	if( [[self connection] status] == MVChatConnectionConnectingStatus ) {
		if( arguments && [arguments isKindOfClass:[NSData class]] && [arguments length] ) {
			NSString *prefix = [[NSString allocWithZone:nil] initWithFormat:@"NOTICE %@ :\001%@ ", [self nickname], command];
			[[self connection] sendRawMessageImmediatelyWithComponents:prefix, arguments, @"\001", nil];
			[prefix release];
		} else if( arguments && [arguments isKindOfClass:[NSString class]] && [arguments length] ) {
			[[self connection] sendRawMessageImmediatelyWithFormat:@"NOTICE %@ :\001%@ %@\001", [self nickname], command, arguments];
		} else [[self connection] sendRawMessageImmediatelyWithFormat:@"NOTICE %@ :\001%@\001", [self nickname], command];
	} else {
		if( arguments && [arguments isKindOfClass:[NSData class]] && [arguments length] ) {
			NSString *prefix = [[NSString allocWithZone:nil] initWithFormat:@"NOTICE %@ :\001%@ ", [self nickname], command];
			[[self connection] sendRawMessageWithComponents:prefix, arguments, @"\001", nil];
			[prefix release];
		} else if( arguments && [arguments isKindOfClass:[NSString class]] && [arguments length] ) {
			[[self connection] sendRawMessageWithFormat:@"NOTICE %@ :\001%@ %@\001", [self nickname], command, arguments];
		} else [[self connection] sendRawMessageWithFormat:@"NOTICE %@ :\001%@\001", [self nickname], command];
	}
}

#pragma mark -

- (void) refreshInformation {
	if( _hasPendingRefreshInformationRequest ) return;
	_hasPendingRefreshInformationRequest = YES;
	[[self connection] sendRawMessageWithFormat:@"WHOIS %@ %1$@", [self nickname]];
}

- (void) _setDateUpdated:(NSDate *) date {
	_hasPendingRefreshInformationRequest = NO;
	[super _setDateUpdated:date];
}

- (void) refreshAttributeForKey:(NSString *) key {
	[super refreshAttributeForKey:key];
	if( [key isEqualToString:MVChatUserPingAttribute] ) {
		[self setAttribute:[NSDate date] forKey:@"MVChatUserPingSendDateAttribute"];
		[self sendSubcodeRequest:@"PING" withArguments:nil];
	} else if( [key isEqualToString:MVChatUserLocalTimeAttribute] ) {
		[self sendSubcodeRequest:@"TIME" withArguments:nil];
	} else if( [key isEqualToString:MVChatUserClientInfoAttribute] ) {
		[self sendSubcodeRequest:@"VERSION" withArguments:nil];
	} else if( [key isEqualToString:MVChatUserKnownRoomsAttribute] ) {
		[self refreshInformation];
	}
}

#pragma mark -

- (void) ctcpReplyNotification:(NSNotification *) notification {
	NSString *command = [[notification userInfo] objectForKey:@"command"];
	NSData *arguments = [[notification userInfo] objectForKey:@"arguments"];
	if( [command isCaseInsensitiveEqualToString:@"PING"] ) {
		NSTimeInterval diff = [[NSDate date] timeIntervalSinceDate:[self attributeForKey:@"MVChatUserPingSendDateAttribute"]];
		[self setAttribute:[NSNumber numberWithDouble:diff] forKey:MVChatUserPingAttribute];
		[self setAttribute:nil forKey:@"MVChatUserPingSendDateAttribute"];
	} else if( [command isCaseInsensitiveEqualToString:@"VERSION"] ) {
		NSString *info = [[NSString allocWithZone:nil] initWithData:arguments encoding:[[self connection] encoding]];
		[self setAttribute:info forKey:MVChatUserClientInfoAttribute];
		[info release];
	} else if( [command isCaseInsensitiveEqualToString:@"TIME"] ) {
		NSString *date = [[NSString allocWithZone:nil] initWithData:arguments encoding:[[self connection] encoding]];
		NSCalendarDate *localThere = [NSCalendarDate dateWithNaturalLanguageString:date];
		[self setAttribute:localThere forKey:MVChatUserLocalTimeAttribute];
		[date release];
	}
}
@end
