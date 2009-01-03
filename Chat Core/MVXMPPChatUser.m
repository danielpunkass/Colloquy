#import <Acid/acid.h>

#import "MVXMPPChatUser.h"
#import "MVXMPPChatConnection.h"
#import "MVUtilities.h"
#import "MVChatString.h"

@implementation MVXMPPChatUser
- (id) initWithJabberID:(JabberID *) identifier andConnection:(MVXMPPChatConnection *) userConnection {
	if( ( self = [self init] ) ) {
		_type = MVChatRemoteUserType;
		_connection = userConnection; // prevent circular retain
		MVSafeRetainAssign( &_uniqueIdentifier, identifier );
		[_connection _addKnownUser:self];
	}

	return self;
}

- (void) dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[super dealloc];
}

#pragma mark -

- (NSString *) displayName {
	return [self username];
}

- (NSString *) nickname {
	return [self username];
}

- (NSString *) realName {
	return nil;
}

- (NSString *) username {
	if( _roomMember )
		return [_uniqueIdentifier resource];
	return [_uniqueIdentifier username];
}

- (NSString *) address {
	return [_uniqueIdentifier hostname];
}

- (NSString *) serverAddress {
	return [_uniqueIdentifier hostname];
}

#pragma mark -

- (unsigned long) supportedModes {
	return MVChatUserNoModes;
}

- (NSSet *) supportedAttributes {
	return [NSSet set];
}

#pragma mark -

- (void) sendMessage:(MVChatString *) message withEncoding:(NSStringEncoding) encoding withAttributes:(NSDictionary *) attributes {
	NSParameterAssert( message != nil );

	JabberMessage *jabberMsg = [[JabberMessage alloc] initWithRecipient:_uniqueIdentifier andBody:[message string]];
	[jabberMsg setType:@"chat"];
	[jabberMsg addComposingRequest];
	[[(MVXMPPChatConnection *)_connection _chatSession] sendElement:jabberMsg];
	[jabberMsg release];
}
@end

#pragma mark -

@implementation MVXMPPChatUser (MVXMPPChatUserPrivate)
- (void) _setRoomMember:(BOOL) member {
	_roomMember = member;
}

- (BOOL) _isRoomMember {
	return _roomMember;
}
@end
