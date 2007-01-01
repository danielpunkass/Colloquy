#import "MVIRCChatConnection.h"
#import "MVIRCChatRoom.h"
#import "MVIRCChatUser.h"
#import "MVIRCFileTransfer.h"
#import "MVIRCNumerics.h"

#import "AsyncSocket.h"
#import "InterThreadMessaging.h"
#import "MVChatuserWatchRule.h"
#import "MVChatPluginManager.h"
#import "NSAttributedStringAdditions.h"
#import "NSColorAdditions.h"
#import "NSMethodSignatureAdditions.h"
#import "NSNotificationAdditions.h"
#import "NSStringAdditions.h"
#import "NSDataAdditions.h"

#define JVMinimumSendQueueDelay 0.2
#define JVMaximumSendQueueDelay 2.0
#define JVQueueWaitBeforeConnected 120.
#define JVPingServerInterval 120.
#define JVPeriodicEventsInterval 600.
#define JVSendQueueDelayIncrement 0.01
#define JVWatchedUserWHOISDelay 300.
#define JVWatchedUserISONDelay 60.
#define JVMaximumISONCommandLength 510
#define JVMaximumMembersForWhoRequest 100
#define JVFallbackEncoding NSISOLatin1StringEncoding

static const NSStringEncoding supportedEncodings[] = {
	/* Universal */
	NSUTF8StringEncoding,
	/* Western */
	NSASCIIStringEncoding,
	NSISOLatin1StringEncoding,			// ISO Latin 1
	(NSStringEncoding) 0x80000203,		// ISO Latin 3
	(NSStringEncoding) 0x8000020F,		// ISO Latin 9
	NSMacOSRomanStringEncoding,			// Mac
	NSWindowsCP1252StringEncoding,		// Windows
	/* Baltic */
	(NSStringEncoding) 0x8000020D,		// ISO Latin 7
	(NSStringEncoding) 0x80000507,		// Windows
	/* Central European */
	NSISOLatin2StringEncoding,			// ISO Latin 2
	(NSStringEncoding) 0x80000204,		// ISO Latin 4
	(NSStringEncoding) 0x8000001D,		// Mac
	NSWindowsCP1250StringEncoding,		// Windows
	/* Cyrillic */
	(NSStringEncoding) 0x80000A02,		// KOI8-R
	(NSStringEncoding) 0x80000205,		// ISO Latin 5
	(NSStringEncoding) 0x80000007,		// Mac
	NSWindowsCP1251StringEncoding,		// Windows
	/* Greek */
	(NSStringEncoding) 0x80000207,		// ISO Latin 7
	(NSStringEncoding) 0x80000006,		// Mac
	NSWindowsCP1253StringEncoding,		// Windows
	/* Japanese */
	(NSStringEncoding) 0x80000A01,		// ShiftJIS
	NSISO2022JPStringEncoding,			// ISO-2022-JP
	NSJapaneseEUCStringEncoding,		// EUC
	(NSStringEncoding) 0x80000001,		// Mac
	NSShiftJISStringEncoding,			// Windows
	/* Simplified Chinese */
	(NSStringEncoding) 0x80000632,		// GB 18030
	(NSStringEncoding) 0x80000631,		// GBK
	(NSStringEncoding) 0x80000930,		// EUC
	(NSStringEncoding) 0x80000019,		// Mac
	(NSStringEncoding) 0x80000421,		// Windows
	/* Traditional Chinese */
	(NSStringEncoding) 0x80000A03,		// Big5
	(NSStringEncoding) 0x80000A06,		// Big5 HKSCS
	(NSStringEncoding) 0x80000931,		// EUC
	(NSStringEncoding) 0x80000002,		// Mac
	(NSStringEncoding) 0x80000423,		// Windows
	/* Korean */
	(NSStringEncoding) 0x80000940,		// EUC
	(NSStringEncoding) 0x80000003,		// Mac
	(NSStringEncoding) 0x80000422,		// Windows
	/* Thai */
	(NSStringEncoding) 0x8000020b,		// ISO-8859-11
	(NSStringEncoding) 0x80000015,		// Mac
	(NSStringEncoding) 0x8000041d,		// Windows
	/* Hebrew */
	(NSStringEncoding) 0x80000208,		// ISO-8859-8
	(NSStringEncoding) 0x80000005,		// Mac
	(NSStringEncoding) 0x80000505,		// Windows
	/* Arabic */
	(NSStringEncoding) 0x80000206,		// ISO-8859-6
	(NSStringEncoding) 0x80000004,		// Mac
	(NSStringEncoding) 0x80000506,		// Windows
	0
};

@implementation MVIRCChatConnection
+ (NSArray *) defaultServerPorts {
	return [NSArray arrayWithObjects:[NSNumber numberWithUnsignedShort:6667],[NSNumber numberWithUnsignedShort:6660],[NSNumber numberWithUnsignedShort:6669],[NSNumber numberWithUnsignedShort:7000],[NSNumber numberWithUnsignedShort:994], nil];
}

#pragma mark -

- (id) init {
	if( ( self = [super init] ) ) {
		_serverPort = 6667;
		_server = @"irc.freenode.net";
		_username = [NSUserName() retain];
		_nickname = [_username retain];
		_currentNickname = [_nickname retain];
		_realName = [NSFullUserName() retain];
		_threadWaitLock = [[NSConditionLock allocWithZone:nil] initWithCondition:0];
		_supportedFeatures = [[NSMutableSet allocWithZone:nil] initWithCapacity:10];
		[self _resetSupportedFeatures];
	}

	return self;
}

- (void) finalize {
	[self disconnect];
	if( [_connectionThread respondsToSelector:@selector( cancel )] )
		[_connectionThread cancel];
	[super finalize];
}

- (void) dealloc {
	[self disconnect];

	[_chatConnection setDelegate:nil];

	[_chatConnection release];
	[_knownUsers release];
	[_fileTransfers release];
	[_server release];
	[_currentNickname release];
	[_nickname release];
	[_username release];
	[_password release];
	[_realName release];
	[_threadWaitLock release];
	[_lastSentIsonNicknames release];
	[_sendQueue release];
	[_queueWait release];
	[_lastCommand release];
	[_pendingWhoisUsers release];
	[_roomPrefixes release];
	[_serverInformation release];
	[_supportedFeatures release];

	if( [_connectionThread respondsToSelector:@selector( cancel )] )
		[_connectionThread cancel];

	_chatConnection = nil;
	_connectionThread = nil;
	_knownUsers = nil;
	_fileTransfers = nil;
	_server = nil;
	_currentNickname = nil;
	_nickname = nil;
	_username = nil;
	_password = nil;
	_realName = nil;
	_threadWaitLock = nil;
	_lastSentIsonNicknames = nil;
	_sendQueue = nil;
	_queueWait = nil;
	_lastCommand = nil;
	_pendingWhoisUsers = nil;
	_roomPrefixes = nil;
	_serverInformation = nil;
	_supportedFeatures = nil;

	[super dealloc];
}

#pragma mark -

- (NSString *) urlScheme {
	return @"irc";
}

- (MVChatConnectionType) type {
	return MVChatConnectionIRCType;
}

- (NSSet *) supportedFeatures {
	@synchronized( _supportedFeatures ) {
		return [NSSet setWithSet:_supportedFeatures];
	} return nil;
}

- (BOOL) supportsFeature:(NSString *) key {
	NSParameterAssert( key != nil );
	@synchronized( _supportedFeatures ) {
		return [_supportedFeatures containsObject:key];
	} return NO;
}

- (const NSStringEncoding *) supportedStringEncodings {
	return supportedEncodings;
}

#pragma mark -

- (void) connect {
	if( _status != MVChatConnectionDisconnectedStatus && _status != MVChatConnectionServerDisconnectedStatus && _status != MVChatConnectionSuspendedStatus ) return;

	id old = _lastConnectAttempt;
	_lastConnectAttempt = [[NSDate allocWithZone:nil] init];
	[old release];

	old = _queueWait;
	_queueWait = [[NSDate dateWithTimeIntervalSinceNow:JVQueueWaitBeforeConnected] retain];
	[old release];

	[self _resetSendQueueInterval];
	[self _resetSupportedFeatures];

	[self _willConnect]; // call early so other code has a chance to change our info

	[NSThread detachNewThreadSelector:@selector( _ircRunloop ) toTarget:self withObject:nil];

	[_threadWaitLock lockWhenCondition:1];
	[_threadWaitLock unlockWithCondition:0];

	if( _connectionThread )
		[self performSelector:@selector( _connect ) inThread:_connectionThread];
}

- (void) disconnectWithReason:(NSAttributedString *) reason {
	[self cancelPendingReconnectAttempts];
	if( _sendQueueProcessing && _connectionThread )
		[self performSelector:@selector( _stopSendQueue ) withObject:nil inThread:_connectionThread];

	if( _status == MVChatConnectionConnectedStatus ) {
		if( [[reason string] length] ) {
			NSData *msg = [[self class] _flattenedIRCDataForMessage:reason withEncoding:[self encoding] andChatFormat:[self outgoingChatFormat]];
			[self sendRawMessageImmediatelyWithComponents:@"QUIT :", msg, nil];
		} else [self sendRawMessage:@"QUIT" immediately:YES];
	} else if( _status == MVChatConnectionConnectingStatus ) {
		if( _connectionThread )
			[[self _chatConnection] performSelector:@selector( disconnect ) inThread:_connectionThread];
	}
}

#pragma mark -

- (void) setRealName:(NSString *) name {
	NSParameterAssert( name != nil );

	id old = _realName;
	_realName = [name copyWithZone:nil];
	[old release];
}

- (NSString *) realName {
	return _realName;
}

#pragma mark -

- (void) setNickname:(NSString *) newNickname {
	NSParameterAssert( newNickname != nil );
	NSParameterAssert( [newNickname length] > 0 );

	if( [newNickname isEqualToString:[self nickname]] )
		return;

	id old = _nickname;
	_nickname = [newNickname copyWithZone:nil];
	[old release];

	if( ! _currentNickname || ! [self isConnected] ) {
		id old = _currentNickname;
		_currentNickname = [_nickname retain];
		[old release];
	}

	if( [self isConnected] )
		[self sendRawMessageImmediatelyWithFormat:@"NICK %@", newNickname];
}

- (NSString *) nickname {
	return _currentNickname;
}

- (NSString *) preferredNickname {
	return _nickname;
}

#pragma mark -

- (void) setNicknamePassword:(NSString *) newPassword {
	if( ! [[self localUser] isIdentified] && newPassword && [self isConnected] )
		[self sendRawMessageImmediatelyWithFormat:@"NickServ IDENTIFY %@", newPassword];
	[super setNicknamePassword:newPassword];
}

#pragma mark -

- (void) setPassword:(NSString *) newPassword {
	id old = _password;
	_password = [newPassword copyWithZone:nil];
	[old release];
}

- (NSString *) password {
	return _password;
}

#pragma mark -

- (void) setUsername:(NSString *) newUsername {
	NSParameterAssert( newUsername != nil );
	NSParameterAssert( [newUsername length] > 0 );

	id old = _username;
	_username = [newUsername copyWithZone:nil];
	[old release];
}

- (NSString *) username {
	return _username;
}

#pragma mark -

- (void) setServer:(NSString *) newServer {
	NSParameterAssert( newServer != nil );
	NSParameterAssert( [newServer length] > 0 );

	id old = _server;
	_server = [newServer copyWithZone:nil];
	[old release];
}

- (NSString *) server {
	return _server;
}

#pragma mark -

- (void) setServerPort:(unsigned short) port {
	_serverPort = ( port ? port : 6667 );
}

- (unsigned short) serverPort {
	return _serverPort;
}

#pragma mark -

- (void) sendRawMessage:(id) raw immediately:(BOOL) now {
	NSParameterAssert( raw != nil );
	NSParameterAssert( [raw isKindOfClass:[NSData class]] || [raw isKindOfClass:[NSString class]] );

	if( ! now ) {
		@synchronized( _sendQueue ) {
			now = ! [_sendQueue count];
		}

		if( now ) now = ( ! _queueWait || [_queueWait timeIntervalSinceNow] <= 0. );
		if( now ) now = ( ! _lastCommand || [_lastCommand timeIntervalSinceNow] <= -JVMinimumSendQueueDelay );
	}

	if( now ) {
		if( _connectionThread )
			[self performSelector:@selector( _writeDataToServer: ) withObject:raw inThread:_connectionThread];

		id old = _lastCommand;
		_lastCommand = [[NSDate allocWithZone:nil] init];
		[old release];
	} else {
		if( ! _sendQueue )
			_sendQueue = [[NSMutableArray allocWithZone:nil] initWithCapacity:20];

		@synchronized( _sendQueue ) {
			[_sendQueue addObject:raw];
		}

		if( ! _sendQueueProcessing && _connectionThread )
			[self performSelector:@selector( _startSendQueue ) withObject:nil inThread:_connectionThread];
	}
}

#pragma mark -

- (void) joinChatRoomsNamed:(NSArray *) rooms {
	NSParameterAssert( rooms != nil );

	if( ! [rooms count] ) return;

	NSMutableArray *roomList = [[NSMutableArray allocWithZone:nil] initWithCapacity:[rooms count]];
	NSEnumerator *enumerator = [rooms objectEnumerator];
	NSString *room = nil;

	while( ( room = [enumerator nextObject] ) ) {
		if( [room length] && [room rangeOfString:@" "].location == NSNotFound ) { // join non-password rooms in bulk
			[roomList addObject:[self properNameForChatRoomNamed:room]];
		} else if( [room length] && [room rangeOfString:@" "].location != NSNotFound ) { // has a password, join separately
			if( [roomList count] ) {
				// join all requested rooms before this one so we do things in order
				[self sendRawMessageWithFormat:@"JOIN %@", [roomList componentsJoinedByString:@","]];
				[roomList removeAllObjects]; // clear list since we joined them
			}

			[self sendRawMessageWithFormat:@"JOIN %@", [self properNameForChatRoomNamed:room]];
		}
	}

	if( [roomList count] ) [self sendRawMessageWithFormat:@"JOIN %@", [roomList componentsJoinedByString:@","]];
	[roomList release];
}

- (void) joinChatRoomNamed:(NSString *) room withPassphrase:(NSString *) passphrase {
	NSParameterAssert( room != nil );
	NSParameterAssert( [room length] > 0 );
	if( [passphrase length] ) [self sendRawMessageWithFormat:@"JOIN %@ %@", [self properNameForChatRoomNamed:room], passphrase];
	else [self sendRawMessageWithFormat:@"JOIN %@", [self properNameForChatRoomNamed:room]];
}

#pragma mark -

- (NSCharacterSet *) chatRoomNamePrefixes {
	static NSCharacterSet *defaultPrefixes = nil;
	if( ! _roomPrefixes && ! defaultPrefixes )
		defaultPrefixes = [[NSCharacterSet characterSetWithCharactersInString:@"#&+!"] retain];
	if( ! _roomPrefixes ) return defaultPrefixes;
	return _roomPrefixes;
}

- (NSString *) properNameForChatRoomNamed:(NSString *) room {
	if( ! [room length] ) return room;
	return ( [[self chatRoomNamePrefixes] characterIsMember:[room characterAtIndex:0]] ? room : [@"#" stringByAppendingString:room] );
}

#pragma mark -

- (NSSet *) knownChatUsers {
	@synchronized( _knownUsers ) {
		return [NSSet setWithArray:[_knownUsers allValues]];
	} return nil;
}

- (NSSet *) chatUsersWithNickname:(NSString *) name {
	return [NSSet setWithObject:[self chatUserWithUniqueIdentifier:name]];
}

- (MVChatUser *) chatUserWithUniqueIdentifier:(id) identifier {
	NSParameterAssert( [identifier isKindOfClass:[NSString class]] );

	NSString *uniqueIdentfier = [identifier lowercaseString];
	if( [uniqueIdentfier isEqualToString:[[self localUser] uniqueIdentifier]] )
		return [self localUser];

	if( ! _knownUsers )
		_knownUsers = [[NSMutableDictionary allocWithZone:nil] initWithCapacity:200];

	MVChatUser *user = nil;
	@synchronized( _knownUsers ) {
		user = [_knownUsers objectForKey:uniqueIdentfier];
		if( user ) return user;

		user = [[MVIRCChatUser allocWithZone:nil] initWithNickname:identifier andConnection:self];
		if( user ) [_knownUsers setObject:user forKey:uniqueIdentfier];
	}

	return [user autorelease];
}

#pragma mark -

- (void) addChatUserWatchRule:(MVChatUserWatchRule *) rule {
	@synchronized( _chatUserWatchRules ) {
		if( [_chatUserWatchRules containsObject:rule] ) return;
	}

	[super addChatUserWatchRule:rule];

	if( [rule nickname] && ! [rule nicknameIsRegularExpression] ) {
		MVChatUser *user = [self chatUserWithUniqueIdentifier:[rule nickname]];
		[rule matchChatUser:user];
		if( [self isConnected] ) {
			if( _watchCommandSupported ) [self sendRawMessageWithFormat:@"WATCH +%@", [rule nickname]];
			else [self sendRawMessageWithFormat:@"ISON %@", [rule nickname]];
		}
	} else {
		@synchronized( _knownUsers ) {
			NSEnumerator *enumerator = [_knownUsers objectEnumerator];
			MVChatUser *user = nil;
			while( ( user = [enumerator nextObject] ) )
				[rule matchChatUser:user];
		}
	}
}

- (void) removeChatUserWatchRule:(MVChatUserWatchRule *) rule {
	[super removeChatUserWatchRule:rule];

	if( [self isConnected] && _watchCommandSupported && [rule nickname] && ! [rule nicknameIsRegularExpression] )
		[self sendRawMessageWithFormat:@"WATCH -%@", [rule nickname]];
}

#pragma mark -

- (void) fetchChatRoomList {
	if( ! _cachedDate || ABS( [_cachedDate timeIntervalSinceNow] ) > 300. ) {
		[self sendRawMessage:@"LIST"];

		id old = _cachedDate;
		_cachedDate = [[NSDate allocWithZone:nil] init];
		[old release];
	}
}

- (void) stopFetchingChatRoomList {
	if( _cachedDate && ABS( [_cachedDate timeIntervalSinceNow] ) < 600. )
		[self sendRawMessage:@"LIST STOP" immediately:YES];
}

#pragma mark -

- (void) setAwayStatusMessage:(NSAttributedString *) message {
	[_awayMessage release];
	_awayMessage = nil;

	if( [[message string] length] ) {
		[[self localUser] _setStatus:MVChatUserAwayStatus];

		_awayMessage = [message copyWithZone:nil];

		NSData *msg = [[self class] _flattenedIRCDataForMessage:message withEncoding:[self encoding] andChatFormat:[self outgoingChatFormat]];
		[self sendRawMessageImmediatelyWithComponents:@"AWAY :", msg, nil];
	} else {
		[[self localUser] _setStatus:MVChatUserAvailableStatus];
		[self sendRawMessage:@"AWAY" immediately:YES];
	}
}
@end

#pragma mark -

@implementation MVIRCChatConnection (MVIRCChatConnectionPrivate)
- (AsyncSocket *) _chatConnection {
	return _chatConnection;
}

- (void) _connect {
	id old = _chatConnection;
	_chatConnection = [[AsyncSocket allocWithZone:nil] initWithDelegate:self];
	[old setDelegate:nil];
	[old disconnect];
	[old release];

	if( ! [_chatConnection connectToHost:[self server] onPort:[self serverPort] error:NULL] )
		[self _didNotConnect];
}

- (oneway void) _ircRunloop {
	NSAutoreleasePool *pool = [[NSAutoreleasePool allocWithZone:nil] init];

	[_threadWaitLock lockWhenCondition:0];

	if( [_connectionThread respondsToSelector:@selector( cancel )] )
		[_connectionThread cancel];

	_connectionThread = [NSThread currentThread];
	if( [_connectionThread respondsToSelector:@selector( setName: )] )
		[_connectionThread setName:[[self url] absoluteString]];
	[NSThread prepareForInterThreadMessages];

	[_threadWaitLock unlockWithCondition:1];

	if( [pool respondsToSelector:@selector( drain )] )
		[pool drain];
	[pool release];
	pool = nil;

	BOOL active = YES;
	while( active && ( _status == MVChatConnectionConnectedStatus || _status == MVChatConnectionConnectingStatus || [_chatConnection isConnected] ) ) {
		pool = [[NSAutoreleasePool allocWithZone:nil] init];
		active = [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:5.]];
		if( [pool respondsToSelector:@selector( drain )] )
			[pool drain];
		[pool release];
	}

	pool = [[NSAutoreleasePool allocWithZone:nil] init];

	// make sure the connection has sent all the delegate calls it has scheduled
	[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:1.]];

	if( [NSThread currentThread] == _connectionThread )
		_connectionThread = nil;

	if( [pool respondsToSelector:@selector( drain )] )
		[pool drain];
	[pool release];
}

#pragma mark -

- (void) _didDisconnect {
	if( _status == MVChatConnectionServerDisconnectedStatus ) {
		if( ABS( [_lastConnectAttempt timeIntervalSinceNow] ) > 300. )
			[self performSelector:@selector( connect ) withObject:nil afterDelay:5.];
		[self scheduleReconnectAttemptEvery:30.];
	}

	[super _didDisconnect];
}

#pragma mark -

- (BOOL) socketWillConnect:(AsyncSocket *) sock {
	if( [[self proxyServer] length] && [self proxyServerPort] ) {
		if( _proxy == MVChatConnectionHTTPSProxy || _proxy == MVChatConnectionHTTPProxy ) {
			NSMutableDictionary *settings = [[NSMutableDictionary allocWithZone:nil] init];
			if( _proxy == MVChatConnectionHTTPSProxy ) {
				[settings setObject:[self proxyServer] forKey:(NSString *)kCFStreamPropertyHTTPSProxyHost];
				[settings setObject:[NSNumber numberWithUnsignedShort:[self proxyServerPort]] forKey:(NSString *)kCFStreamPropertyHTTPSProxyPort];
			} else {
				[settings setObject:[self proxyServer] forKey:(NSString *)kCFStreamPropertyHTTPProxyHost];
				[settings setObject:[NSNumber numberWithUnsignedShort:[self proxyServerPort]] forKey:(NSString *)kCFStreamPropertyHTTPProxyPort];
			}

			CFReadStreamSetProperty( [sock getCFReadStream], kCFStreamPropertyHTTPProxy, (CFDictionaryRef) settings );
			CFWriteStreamSetProperty( [sock getCFWriteStream], kCFStreamPropertyHTTPProxy, (CFDictionaryRef) settings );
			[settings release];
		} else if( _proxy == MVChatConnectionSOCKS4Proxy || _proxy == MVChatConnectionSOCKS5Proxy ) {
			NSMutableDictionary *settings = [[NSMutableDictionary allocWithZone:nil] init];

			[settings setObject:[self proxyServer] forKey:(NSString *)kCFStreamPropertySOCKSProxyHost];
			[settings setObject:[NSNumber numberWithUnsignedShort:[self proxyServerPort]] forKey:(NSString *)kCFStreamPropertySOCKSProxyPort];

			if( [[self proxyUsername] length] )
				[settings setObject:[self proxyUsername] forKey:(NSString *)kCFStreamPropertySOCKSUser];
			if( [[self proxyPassword] length] )
				[settings setObject:[self proxyPassword] forKey:(NSString *)kCFStreamPropertySOCKSPassword];

			if( _proxy == MVChatConnectionSOCKS4Proxy )
				[settings setObject:(NSString *)kCFStreamSocketSOCKSVersion4 forKey:(NSString *)kCFStreamPropertySOCKSVersion];

			CFReadStreamSetProperty( [sock getCFReadStream], kCFStreamPropertySOCKSProxy, (CFDictionaryRef) settings );
			CFWriteStreamSetProperty( [sock getCFWriteStream], kCFStreamPropertySOCKSProxy, (CFDictionaryRef) settings );
			[settings release];
		}
	}

	if( [self isSecure] ) {
		CFReadStreamSetProperty( [sock getCFReadStream], kCFStreamPropertySocketSecurityLevel, kCFStreamSocketSecurityLevelNegotiatedSSL );
		CFWriteStreamSetProperty( [sock getCFWriteStream], kCFStreamPropertySocketSecurityLevel, kCFStreamSocketSecurityLevelNegotiatedSSL );

		NSMutableDictionary *settings = [[NSMutableDictionary allocWithZone:nil] init];
		[settings setObject:[NSNumber numberWithBool:YES] forKey:(NSString *)kCFStreamSSLAllowsAnyRoot];

		CFReadStreamSetProperty( [sock getCFReadStream], kCFStreamPropertySSLSettings, (CFDictionaryRef) settings );
		CFWriteStreamSetProperty( [sock getCFWriteStream], kCFStreamPropertySSLSettings, (CFDictionaryRef) settings );
	}

	return YES;
}

- (void) socket:(AsyncSocket *) sock willDisconnectWithError:(NSError *) error {
	NSLog(@"connection error: %@", error );
	id old = _lastError;
	_lastError = [error retain];
	[old release];
}

- (void) socketDidDisconnect:(AsyncSocket *) sock {
	if( sock != _chatConnection ) return;

	id old = _chatConnection;
	_chatConnection = nil;
	[old setDelegate:nil];
	[old release];

	[self _stopSendQueue];

	@synchronized( _sendQueue ) {
		[_sendQueue removeAllObjects];
	}

	old = _lastCommand;
	_lastCommand = nil;
	[old release];

	old = _queueWait;
	_queueWait = nil;
	[old release];

	old = _lastSentIsonNicknames;
	_lastSentIsonNicknames = nil;
	[old release];

	old = _pendingWhoisUsers;
	_pendingWhoisUsers = nil;
	[old release];

	_isonSentCount = 0;

	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector( _pingServer ) object:nil];
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector( _periodicEvents ) object:nil];
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector( _whoisWatchedUsers ) object:nil];
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector( _checkWatchedUsers ) object:nil];

	if( _status == MVChatConnectionConnectingStatus && _lastError ) {
		[self performSelectorOnMainThread:@selector( _didNotConnect ) withObject:nil waitUntilDone:NO];
	} else {
		if( _lastError )
			_status = MVChatConnectionServerDisconnectedStatus;

		[self performSelectorOnMainThread:@selector( _didDisconnect ) withObject:nil waitUntilDone:NO];
	}

	@synchronized( _knownUsers ) {
		NSEnumerator *enumerator = [_knownUsers objectEnumerator];
		MVChatUser *user = nil;

		while( ( user = [enumerator nextObject] ) )
			[user _setStatus:MVChatUserUnknownStatus];
	}

	@synchronized( _chatUserWatchRules ) {
		NSEnumerator *enumerator = [_chatUserWatchRules objectEnumerator];
		MVChatUserWatchRule *rule = nil;
		while( ( rule = [enumerator nextObject] ) )
			[rule removeMatchedUsersForConnection:self];
	}
}

- (void) socket:(AsyncSocket *) sock didConnectToHost:(NSString *) host port:(UInt16) port {
	[self setNickname:[self preferredNickname]];

	if( [[self password] length] ) [self sendRawMessageImmediatelyWithFormat:@"PASS %@", [self password]];
	[self sendRawMessageImmediatelyWithFormat:@"NICK %@", [self nickname]];
	[self sendRawMessageImmediatelyWithFormat:@"USER %@ 0 * :%@", ( [[self username] length] ? [self username] : @"anonymous" ), ( [[self realName] length] ? [self realName] : @"anonymous" )];

	id old = _localUser;
	_localUser = [[MVIRCChatUser allocWithZone:nil] initLocalUserWithConnection:self];
	[old release];

	[self performSelector:@selector( _periodicEvents ) withObject:nil afterDelay:JVPeriodicEventsInterval];
	[self performSelector:@selector( _pingServer ) withObject:nil afterDelay:JVPingServerInterval];

	[self _readNextMessageFromServer];
}

- (void) socket:(AsyncSocket *) sock didReadData:(NSData *) data withTag:(long) tag {
	NSString *rawString = [self _newStringWithBytes:[data bytes] length:[data length]];

	const char *line = (const char *)[data bytes];
	unsigned int len = [data length];
	const char *end = line + len - 2; // minus the line endings

	if( *( line + len - 2 ) != '\x0D' )
		end = line + len - 1; // this server only uses \x0A for the message line ending, lets work with it

	const char *sender = NULL;
	unsigned senderLength = 0;
	const char *user = NULL;
	unsigned userLength = 0;
	const char *host = NULL;
	unsigned hostLength = 0;
	const char *command = NULL;
	unsigned commandLength = 0;

	NSMutableArray *parameters = [[NSMutableArray allocWithZone:nil] initWithCapacity:15];

	// Parsing as defined in 2.3.1 at http://www.irchelp.org/irchelp/rfc/rfc2812.txt

	if( len <= 2 || len > 512 )
		goto end; // bad message

#define checkAndMarkIfDone() if( line == end ) done = YES
#define consumeWhitespace() while( *line == ' ' && line != end && ! done ) line++
#define notEndOfLine() line != end && ! done

	BOOL done = NO;
	if( notEndOfLine() ) {
		if( *line == ':' ) {
			// prefix: ':' <sender> [ '!' <user> ] [ '@' <host> ] ' ' { ' ' }
			sender = ++line;
			while( notEndOfLine() && *line != ' ' && *line != '!' && *line != '@' ) line++;
			senderLength = (line - sender);
			checkAndMarkIfDone();

			if( ! done && *line == '!' ) {
				user = ++line;
				while( notEndOfLine() && *line != ' ' && *line != '@' ) line++;
				userLength = (line - user);
				checkAndMarkIfDone();
			}

			if( ! done && *line == '@' ) {
				host = ++line;
				while( notEndOfLine() && *line != ' ' ) line++;
				hostLength = (line - host);
				checkAndMarkIfDone();
			}

			if( ! done ) line++;
			consumeWhitespace();
		}

		if( notEndOfLine() ) {
			// command: <letter> { <letter> } | <number> <number> <number>
			// letter: 'a' ... 'z' | 'A' ... 'Z'
			// number: '0' ... '9'
			command = line;
			while( notEndOfLine() && *line != ' ' ) line++;
			commandLength = (line - command);
			checkAndMarkIfDone();

			if( ! done ) line++;
			consumeWhitespace();
		}

		while( notEndOfLine() ) {
			// params: [ ':' <trailing data> | <letter> { <letter> } ] [ ' ' { ' ' } ] [ <params> ]
			const char *currentParameter = NULL;
			id param = nil;
			if( *line == ':' ) {
				currentParameter = ++line;
				param = [[NSMutableData allocWithZone:nil] initWithBytes:currentParameter length:(end - currentParameter)];
				done = YES;
			} else {
				currentParameter = line;
				while( notEndOfLine() && *line != ' ' ) line++;
				param = [self _newStringWithBytes:currentParameter length:(line - currentParameter)];
				checkAndMarkIfDone();
				if( ! done ) line++;
			}

			if( param ) [parameters addObject:param];
			[param release];

			consumeWhitespace();
		}
	}

#undef checkAndMarkIfDone()
#undef consumeWhitespace()
#undef notEndOfLine()

end:
	[[NSNotificationCenter defaultCenter] postNotificationOnMainThreadWithName:MVChatConnectionGotRawMessageNotification object:self userInfo:[NSDictionary dictionaryWithObjectsAndKeys:rawString, @"message", [NSNumber numberWithBool:NO], @"outbound", nil]];

	if( command && commandLength ) {
		NSString *commandString = [[NSString allocWithZone:nil] initWithBytes:command length:commandLength encoding:NSASCIIStringEncoding];
		NSString *selectorString = [[NSString allocWithZone:nil] initWithFormat:@"_handle%@WithParameters:fromSender:", [commandString capitalizedString]];
		SEL selector = NSSelectorFromString( selectorString );
		[selectorString release];
		[commandString release];

		if( [self respondsToSelector:selector] ) {
			NSString *senderString = [self _newStringWithBytes:sender length:senderLength];

			MVChatUser *chatUser = nil;
			// if user is not null that shows it was a user not a server sender.
			// the sender was also a user if senderString equals the current local nickname (some bouncers will do this).
			if( ( senderString && user && userLength ) || [senderString isEqualToString:_currentNickname] ) {
				chatUser = [self chatUserWithUniqueIdentifier:senderString];
				if( ! [chatUser address] && host && hostLength ) {
					NSString *hostString = [self _newStringWithBytes:host length:hostLength];
					[chatUser _setAddress:hostString];
					[hostString release];
				}

				if( ! [chatUser username] ) {
					NSString *userString = [self _newStringWithBytes:user length:userLength];
					[chatUser _setUsername:userString];
					[userString release];
				}
			}

			[self performSelector:selector withObject:parameters withObject:( chatUser ? (id) chatUser : (id) senderString )];
			[senderString release];
		}
	}

	[rawString release];
	[parameters release];

	[self _readNextMessageFromServer];
}

#pragma mark -

- (void) _writeDataToServer:(id) raw {
	NSMutableData *data = nil;
	NSString *string = nil;

	if( [raw isKindOfClass:[NSMutableData class]] ) {
		data = [raw retain];
		string = [[NSString allocWithZone:nil] initWithData:data encoding:[self encoding]];
	} else if( [raw isKindOfClass:[NSData class]] ) {
		data = [raw mutableCopyWithZone:nil];
		string = [[NSString allocWithZone:nil] initWithData:data encoding:[self encoding]];
	} else if( [raw isKindOfClass:[NSString class]] ) {
		data = [[raw dataUsingEncoding:[self encoding] allowLossyConversion:YES] mutableCopyWithZone:nil];
		string = [raw retain];
	}

	// IRC messages are always lines of characters terminated with a CR-LF
	// (Carriage Return - Line Feed) pair, and these messages SHALL NOT
	// exceed 512 characters in length, counting all characters including
	// the trailing CR-LF. Thus, there are 510 characters maximum allowed
	// for the command and its parameters.

	if( [data length] > 510 ) [data setLength:510];
	[data appendBytes:"\x0D\x0A" length:2];

	[_chatConnection writeData:data withTimeout:-1. tag:0];

	[[NSNotificationCenter defaultCenter] postNotificationOnMainThreadWithName:MVChatConnectionGotRawMessageNotification object:self userInfo:[NSDictionary dictionaryWithObjectsAndKeys:string, @"message", [NSNumber numberWithBool:YES], @"outbound", nil]];

	[string release];
	[data release];
}

- (void) _readNextMessageFromServer {
	static NSData *delimiter = nil;
	// IRC messages end in \x0D\x0A, but some non-compliant servers only use \x0A during the connecting phase
	if( ! delimiter ) delimiter = [[NSData allocWithZone:nil] initWithBytes:"\x0A" length:1];
	[_chatConnection readDataToData:delimiter withTimeout:-1. tag:0];
}

#pragma mark -

+ (NSData *) _flattenedIRCDataForMessage:(NSAttributedString *) message withEncoding:(NSStringEncoding) enc andChatFormat:(MVChatMessageFormat) format {
	NSString *cformat = nil;

	switch( format ) {
	case MVChatConnectionDefaultMessageFormat:
	case MVChatWindowsIRCMessageFormat:
		cformat = NSChatWindowsIRCFormatType;
		break;
	case MVChatCTCPTwoMessageFormat:
		cformat = NSChatCTCPTwoFormatType;
		break;
	default:
	case MVChatNoMessageFormat:
		cformat = nil;
	}

	NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithUnsignedInt:enc], @"StringEncoding", cformat, @"FormatType", nil];
	return [message chatFormatWithOptions:options];
}

- (void) _sendMessage:(NSAttributedString *) message withEncoding:(NSStringEncoding) msgEncoding toTarget:(NSString *) target asAction:(BOOL) action {
	NSData *msg = [[self class] _flattenedIRCDataForMessage:message withEncoding:msgEncoding andChatFormat:[self outgoingChatFormat]];
	if( action ) {
		NSString *prefix = [[NSString allocWithZone:nil] initWithFormat:@"PRIVMSG %@ :\001ACTION ", target];
		[self sendRawMessageWithComponents:prefix, msg, @"\001", nil];
		[prefix release];
	} else {
		NSString *prefix = [[NSString allocWithZone:nil] initWithFormat:@"PRIVMSG %@ :", target];
		[self sendRawMessageWithComponents:prefix, msg, nil];
		[prefix release];
	}
}

/*

#pragma mark -

- (void) _processErrorCode:(int) errorCode withContext:(char *) context {
	NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
	NSError *error = nil;

	[userInfo setObject:self forKey:@"connection"];

	switch( errorCode ) {
		case ERR_NOSUCHNICK: {
			MVChatUser *user = [self chatUserWithUniqueIdentifier:[self stringWithEncodedBytes:context]];
			[user _setStatus:MVChatUserOfflineStatus];
			[userInfo setObject:user forKey:@"user"];
			[userInfo setObject:[NSString stringWithFormat:NSLocalizedString( @"The user \"%@\" is no longer connected (or never was connected) to the \"%@\" server.", "user not on the server" ), [user nickname], [self server]] forKey:NSLocalizedDescriptionKey];
			error = [NSError errorWithDomain:MVChatConnectionErrorDomain code:MVChatConnectionNoSuchUserError userInfo:userInfo];
			break;
		}
		case ERR_UNKNOWNCOMMAND: {
			NSString *command = [self stringWithEncodedBytes:context];
			[userInfo setObject:command forKey:@"command"];
			[userInfo setObject:[NSString stringWithFormat:NSLocalizedString( @"The command \"%@\" is not a valid command on the \"%@\" server.", "user not on the server" ), command, [self server]] forKey:NSLocalizedDescriptionKey];
			error = [NSError errorWithDomain:MVChatConnectionErrorDomain code:MVChatConnectionUnknownCommandError userInfo:userInfo];
			break;
		}
	}

	if( error ) [self performSelectorOnMainThread:@selector( _postError: ) withObject:error waitUntilDone:NO];
}
*/

#pragma mark -

- (void) _updateKnownUser:(MVChatUser *) user withNewNickname:(NSString *) newNickname {
	@synchronized( _knownUsers ) {
		[user retain];
		[_knownUsers removeObjectForKey:[user uniqueIdentifier]];
		[user _setUniqueIdentifier:[newNickname lowercaseString]];
		[user _setNickname:newNickname];
		[_knownUsers setObject:user forKey:[user uniqueIdentifier]];
		[user release];
	}
}

- (void) _setCurrentNickname:(NSString *) currentNickname {
	id old = _currentNickname;
	_currentNickname = [currentNickname copyWithZone:nil];
	[old release];
}

#pragma mark -

- (void) _periodicEvents {
	@synchronized( _knownUsers ) {
		NSMutableArray *removeList = [[NSMutableArray allocWithZone:nil] initWithCapacity:[_knownUsers count]];
		NSEnumerator *keyEnumerator = [_knownUsers keyEnumerator];
		NSEnumerator *enumerator = [_knownUsers objectEnumerator];
		id key = nil, object = nil;

		while( ( key = [keyEnumerator nextObject] ) && ( object = [enumerator nextObject] ) )
			if( [object retainCount] == 1 ) [removeList addObject:key];

		[_knownUsers removeObjectsForKeys:removeList];
		[removeList release];
	}

	@synchronized( _joinedRooms ) {
		NSEnumerator *enumerator = [_joinedRooms objectEnumerator];
		MVChatRoom *room = nil;

		while( ( room = [enumerator nextObject] ) )
			if( [[room memberUsers] count] <= JVMaximumMembersForWhoRequest )
				[self sendRawMessageWithFormat:@"WHO %@", [room name]];
	}

	[self performSelector:@selector( _periodicEvents ) withObject:nil afterDelay:JVPeriodicEventsInterval];
}

- (void) _pingServer {
	[self sendRawMessageImmediatelyWithFormat:@"PING %@", [self server]];
	[self performSelector:@selector( _pingServer ) withObject:nil afterDelay:JVPingServerInterval];
}

- (void) _startSendQueue {
	if( _sendQueueProcessing ) return;
	_sendQueueProcessing = YES;
	if( _queueWait && [_queueWait timeIntervalSinceNow] > 0. )
		[self performSelector:@selector( _sendQueue ) withObject:nil afterDelay:[_queueWait timeIntervalSinceNow]];
	else [self performSelector:@selector( _sendQueue ) withObject:nil afterDelay:JVMinimumSendQueueDelay];
}

- (void) _stopSendQueue {
	_sendQueueProcessing = NO;
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector( _sendQueue ) object:nil];
}

- (void) _resetSendQueueInterval {
	[self _stopSendQueue];
	@synchronized( _sendQueue ) {
		if( [_sendQueue count] )
			[self _startSendQueue];
	}
}

- (void) _sendQueue {
	@synchronized( _sendQueue ) {
		if( ! [_sendQueue count] ) {
			_sendQueueProcessing = NO;
			return;
		}
	}

	if( _queueWait && [_queueWait timeIntervalSinceNow] > 0. ) {
		[self performSelector:@selector( _sendQueue ) withObject:nil afterDelay:[_queueWait timeIntervalSinceNow]];
		return;
	}

	NSData *data = nil;
	@synchronized( _sendQueue ) {
		data = [[_sendQueue objectAtIndex:0] retain];
		[_sendQueue removeObjectAtIndex:0];

		if( [_sendQueue count] )
			[self performSelector:@selector( _sendQueue ) withObject:nil afterDelay:MIN( JVMinimumSendQueueDelay + ( [_sendQueue count] * JVSendQueueDelayIncrement ), JVMaximumSendQueueDelay )];
		else _sendQueueProcessing = NO;
	}

	[self _writeDataToServer:data];
	[data release];

	id old = _lastCommand;
	_lastCommand = [[NSDate allocWithZone:nil] init];
	[old release];
}

#pragma mark -

- (void) _addFileTransfer:(MVFileTransfer *) transfer {
	if( ! _fileTransfers )
		_fileTransfers = [[NSMutableSet allocWithZone:nil] initWithCapacity:5];
	@synchronized( _fileTransfers ) {
		if( transfer ) [_fileTransfers addObject:transfer];
	}
}

- (void) _removeFileTransfer:(MVFileTransfer *) transfer {
	@synchronized( _fileTransfers ) {
		if( transfer ) [_fileTransfers removeObject:transfer];
	}
}

- (void) _resetSupportedFeatures {
	@synchronized( _supportedFeatures ) {
		[_supportedFeatures removeAllObjects];

		// all server should support these features per RFC 1459
		[_supportedFeatures addObject:MVChatRoomMemberVoicedFeature];
		[_supportedFeatures addObject:MVChatRoomMemberOperatorFeature];
	}
}

#pragma mark -

- (void) _scheduleWhoisForUser:(MVChatUser *) user {
	if( ! _pendingWhoisUsers )
		_pendingWhoisUsers = [[NSMutableSet allocWithZone:nil] initWithCapacity:50];
	[_pendingWhoisUsers addObject:user];
	if( [_pendingWhoisUsers count] == 1 )
		[self _whoisNextScheduledUser];
}

- (void) _whoisNextScheduledUser {
	if( [_pendingWhoisUsers count] ) {
		MVChatUser *user = [_pendingWhoisUsers anyObject];
		[user refreshInformation];
	}
}

- (void) _whoisWatchedUsers {
	[self performSelector:@selector( _whoisWatchedUsers ) withObject:nil afterDelay:JVWatchedUserWHOISDelay];

	NSMutableSet *matchedUsers = [NSMutableSet set];
	@synchronized( _chatUserWatchRules ) {
		if( ! [_chatUserWatchRules count] ) return; // nothing to do, return and wait until the next scheduled fire

		NSEnumerator *enumerator = [_chatUserWatchRules objectEnumerator];
		MVChatUserWatchRule *rule = nil;
		while( ( rule = [enumerator nextObject] ) )
			[matchedUsers unionSet:[rule matchedChatUsers]];
	}

	NSEnumerator *enumerator = [matchedUsers objectEnumerator];
	MVChatUser *user = nil;
	while( ( user = [enumerator nextObject] ) )
		[self _scheduleWhoisForUser:user];
}

- (void) _checkWatchedUsers {
	if( _watchCommandSupported ) return; // we don't need to call this anymore, return before we reschedule

	[self performSelector:@selector( _checkWatchedUsers ) withObject:nil afterDelay:JVWatchedUserISONDelay];

	if( [_lastSentIsonNicknames count] ) return; // there is already pending ISON requests, skip this round to catch up

	NSMutableSet *matchedUsers = [NSMutableSet set];
	@synchronized( _chatUserWatchRules ) {
		if( ! [_chatUserWatchRules count] ) return; // nothing to do, return and wait until the next scheduled fire

		NSEnumerator *enumerator = [_chatUserWatchRules objectEnumerator];
		MVChatUserWatchRule *rule = nil;
		while( ( rule = [enumerator nextObject] ) )
			[matchedUsers unionSet:[rule matchedChatUsers]];
	}

	NSMutableString *request = [[NSMutableString allocWithZone:nil] initWithCapacity:JVMaximumISONCommandLength];
	[request setString:@"ISON "];

	_isonSentCount = 0;

	[_lastSentIsonNicknames release];
	_lastSentIsonNicknames = [[NSMutableSet allocWithZone:nil] initWithCapacity:( [_chatUserWatchRules count] * 5 )];

	NSEnumerator *enumerator = [matchedUsers objectEnumerator];
	MVChatUser *user = nil;

	while( ( user = [enumerator nextObject] ) ) {
		if( ! [[user connection] isEqual:self] )
			continue;

		NSString *nick = [user nickname];
		NSString *nickLower = [nick lowercaseString];

		if( [nick length] && ! [_lastSentIsonNicknames containsObject:nickLower] ) { 
			if( ( [nick length] + [request length] ) > JVMaximumISONCommandLength ) {
				[self sendRawMessage:request];
				[request release];
				_isonSentCount++;

				request = [[NSMutableString allocWithZone:nil] initWithCapacity:JVMaximumISONCommandLength];
				[request setString:@"ISON "];
			}

			[request appendString:nick];
			[request appendString:@" "];

			[_lastSentIsonNicknames addObject:nickLower];
		}
	}

	@synchronized( _chatUserWatchRules ) {
		NSEnumerator *enumerator = [_chatUserWatchRules objectEnumerator];
		MVChatUserWatchRule *rule = nil;

		while( ( rule = [enumerator nextObject] ) ) {
			NSString *nick = [rule nickname];
			NSString *nickLower = [nick lowercaseString];

			if( [nick length] && ! [rule nicknameIsRegularExpression] && ! [_lastSentIsonNicknames containsObject:nickLower] ) { 
				if( ( [nick length] + [request length] ) > JVMaximumISONCommandLength ) {
					[self sendRawMessage:request];
					[request release];
					_isonSentCount++;

					request = [[NSMutableString allocWithZone:nil] initWithCapacity:JVMaximumISONCommandLength];
					[request setString:@"ISON "];
				}

				[request appendString:nick];
				[request appendString:@" "];

				[_lastSentIsonNicknames addObject:nickLower];
			}
		}
	}

	if( ! [request isEqualToString:@"ISON "] ) {
		[self sendRawMessage:request];
		_isonSentCount++;
	}

	[request release];
}

#pragma mark -

- (NSString *) _newStringWithBytes:(const char *) bytes length:(unsigned) length {
	if( bytes && length ) {
		NSStringEncoding encoding = [self encoding];
		if( encoding != NSUTF8StringEncoding && isValidUTF8( bytes, length ) )
			encoding = NSUTF8StringEncoding;
		NSString *ret = [[NSString allocWithZone:nil] initWithBytes:bytes length:length encoding:encoding];
		if( ! ret && encoding != JVFallbackEncoding ) ret = [[NSString allocWithZone:nil] initWithBytes:bytes length:length encoding:JVFallbackEncoding];
		return ret;
	}

	if( ! length ) return @"";
	return nil;
}

- (NSString *) _stringFromPossibleData:(id) input {
	if( [input isKindOfClass:[NSData class]] )
		return [[self _newStringWithBytes:[input bytes] length:[input length]] autorelease];
	return input;
}
@end

#pragma mark -

@implementation MVIRCChatConnection (MVIRCChatConnectionProtocolHandlers)

#pragma mark Connecting Replies

- (void) _handle001WithParameters:(NSArray *) parameters fromSender:(id) sender {
	id old = _queueWait;
	_queueWait = [[NSDate dateWithTimeIntervalSinceNow:0.5] retain];
	[old release];

	[self _resetSendQueueInterval];

	[self performSelectorOnMainThread:@selector( _didConnect ) withObject:nil waitUntilDone:NO];	

	// Identify if we have a user password
	if( [[self nicknamePassword] length] )
		[self sendRawMessageImmediatelyWithFormat:@"NickServ IDENTIFY %@", [self nicknamePassword]];

	// set the current nick name if it is not the same as what re requested (some servers/bouncers will give us a new nickname)
	if( [parameters count] >= 1 ) {
		NSString *nick = [parameters objectAtIndex:0];
		if( ! [nick isEqualToString:[self nickname]] ) {
			[self _setCurrentNickname:nick];
			[[self localUser] _setUniqueIdentifier:[nick lowercaseString]];
			[[NSNotificationCenter defaultCenter] postNotificationOnMainThreadWithName:MVChatConnectionNicknameAcceptedNotification object:self userInfo:nil];
		}
	}

	[self performSelector:@selector( _checkWatchedUsers ) withObject:nil afterDelay:2.];
}

- (void) _handle005WithParameters:(NSArray *) parameters fromSender:(id) sender { // RPL_ISUPPORT
	if( ! _serverInformation )
		_serverInformation = [[NSMutableDictionary allocWithZone:nil] initWithCapacity:5];

	NSEnumerator *enumerator = [parameters objectEnumerator];
	NSString *feature = nil;
	while( ( feature = [enumerator nextObject] ) ) {
		if( [feature isKindOfClass:[NSString class]] && [feature hasPrefix:@"WATCH"] ) {
			_watchCommandSupported = YES;

			NSMutableString *request = [[NSMutableString allocWithZone:nil] initWithCapacity:510];
			[request setString:@"WATCH "];

			@synchronized( _chatUserWatchRules ) {
				NSEnumerator *ruleEnumerator = [_chatUserWatchRules objectEnumerator];
				MVChatUserWatchRule *rule = nil;

				while( ( rule = [ruleEnumerator nextObject] ) ) {
					NSString *nick = [rule nickname];
					if( nick && ! [rule nicknameIsRegularExpression] ) {
						if( ( [nick length] + [request length] + 1 ) > 510 ) {
							[self sendRawMessage:request];
							[request release];

							request = [[NSMutableString allocWithZone:nil] initWithCapacity:510];
							[request setString:@"WATCH "];
						}

						[request appendFormat:@"+%@ ", nick];
					}
				}
			}

			if( ! [request isEqualToString:@"WATCH "] )
				[self sendRawMessage:request];

			[request release];

			[self performSelector:@selector( _whoisWatchedUsers ) withObject:nil afterDelay:JVWatchedUserWHOISDelay];
		} else if( [feature isKindOfClass:[NSString class]] && [feature hasPrefix:@"CHANTYPES="] ) {
			NSString *types = [feature substringFromIndex:10]; // length of "CHANTYPES="
			if( [types length] ) {
				id old = _roomPrefixes;
				_roomPrefixes = [[NSCharacterSet characterSetWithCharactersInString:types] retain];
				[old release];
			}
		} else if( [feature isKindOfClass:[NSString class]] && [feature hasPrefix:@"PREFIX="] ) {
			NSScanner *scanner = [NSScanner scannerWithString:feature];
			[scanner setScanLocation:7]; // length of "PREFIX="
			if( [scanner scanString:@"(" intoString:NULL] ) {
				NSString *modes = nil;
				if( [scanner scanUpToString:@")" intoString:&modes] ) {
					[scanner scanString:@")" intoString:NULL];

					@synchronized( _supportedFeatures ) {
						// remove these in case the server does not support them when we parse the modes
						[_supportedFeatures removeObject:MVChatRoomMemberVoicedFeature];
						[_supportedFeatures removeObject:MVChatRoomMemberOperatorFeature];
					}

					NSMutableDictionary *modesTable = [[NSMutableDictionary allocWithZone:nil] initWithCapacity:[modes length]];
					unsigned length = [modes length];
					unsigned i = 0;
					for( i = 0; i < length; i++ ) {
						MVChatRoomMemberMode mode = MVChatRoomMemberNoModes;
						NSString *modeFeature = nil;
						switch( [modes characterAtIndex:i] ) {
							case 'v': mode = MVChatRoomMemberVoicedMode; modeFeature = MVChatRoomMemberVoicedFeature; break;
							case 'h': mode = MVChatRoomMemberHalfOperatorMode; modeFeature = MVChatRoomMemberHalfOperatorFeature; break;
							case 'o': mode = MVChatRoomMemberOperatorMode; modeFeature = MVChatRoomMemberOperatorFeature; break;
							case 'a':
							case 'u': mode = MVChatRoomMemberAdministratorMode; modeFeature = MVChatRoomMemberAdministratorFeature; break;
							case 'q': mode = MVChatRoomMemberFounderMode; modeFeature = MVChatRoomMemberFounderFeature; break;
							default: break;
						}

						if( mode != MVChatRoomMemberNoModes ) {
							NSString *key = [[NSString allocWithZone:nil] initWithFormat:@"%c", [modes characterAtIndex:i]];
							[modesTable setObject:[NSNumber numberWithUnsignedLong:mode] forKey:key];
							[key release];

							if( modeFeature ) {
								@synchronized( _supportedFeatures ) {
									 [_supportedFeatures addObject:modeFeature];
								}
							}
						}
					}

					if( [modesTable count] ) [_serverInformation setObject:modesTable forKey:@"roomMemberModeTable"];
					[_serverInformation setObject:[NSCharacterSet characterSetWithCharactersInString:modes] forKey:@"roomMemberModes"];

					NSString *prefixes = [feature substringFromIndex:[scanner scanLocation]];
					if( [prefixes length] ) {
						NSMutableDictionary *prefixTable = [[NSMutableDictionary allocWithZone:nil] initWithCapacity:[modes length]];
						unsigned length = [prefixes length];
						unsigned i = 0;
						for( i = 0; i < length; i++ ) {
							MVChatRoomMemberMode mode = MVChatRoomMemberNoModes;
							switch( [prefixes characterAtIndex:i] ) {
								case '+': mode = MVChatRoomMemberVoicedMode; break;
								case '%': mode = MVChatRoomMemberHalfOperatorMode; break;
								case '@': mode = MVChatRoomMemberOperatorMode; break;
								case '&': mode = MVChatRoomMemberAdministratorMode; break;
								case '!': mode = MVChatRoomMemberAdministratorMode; break;
								case '*': mode = MVChatRoomMemberAdministratorMode; break;
								case '~': mode = MVChatRoomMemberFounderMode; break;
								case '.': mode = MVChatRoomMemberFounderMode; break;
								default: break;
							}

							if( mode != MVChatRoomMemberNoModes ) {
								NSString *key = [[NSString allocWithZone:nil] initWithFormat:@"%c", [prefixes characterAtIndex:i]];
								[prefixTable setObject:[NSNumber numberWithUnsignedLong:mode] forKey:key];
								[key release];
							}
						}

						if( [prefixTable count] ) [_serverInformation setObject:prefixTable forKey:@"roomMemberPrefixTable"];
						[_serverInformation setObject:[NSCharacterSet characterSetWithCharactersInString:prefixes] forKey:@"roomMemberPrefixes"];
					}
				}
			}
		}
	}
}

- (void) _handle433WithParameters:(NSArray *) parameters fromSender:(id) sender { // ERR_NICKNAMEINUSE
	if( ! [self isConnected] ) {
		NSString *nick = [self nextAlternateNickname];
		if( ! [nick length] ) nick = [[self nickname] stringByAppendingString:@"_"];
		if( [nick length] ) [self sendRawMessage:[NSString stringWithFormat:@"NICK %@", nick] immediately:YES];
	}
}

#pragma mark -
#pragma mark Incoming Message Replies

- (void) _handlePrivmsgWithParameters:(NSArray *) parameters fromSender:(MVChatUser *) sender {
	// if the sender is a server lets make a user for the server name
	// this is not ideal but the notifications need user objects
	if( [sender isKindOfClass:[NSString class]] )
		sender = [self chatUserWithUniqueIdentifier:(NSString *) sender];

	if( [parameters count] == 2 && [sender isKindOfClass:[MVChatUser class]] ) {
		NSString *targetName = [parameters objectAtIndex:0];
		if( ! [targetName length] ) return;

		if( [targetName characterAtIndex:0] == '@' ) {
			// This is a special filtered target.
			// @#room	sends only to the operators on the room
			// @%#room	sends to the operators and half-operators on the room
			// @+#room	sends to the operators and half-operators and voices on the room
			BOOL subFilter = [targetName length] >= 2 && ( [targetName characterAtIndex:1] == '%' || [targetName characterAtIndex:1] == '+' ); 
			targetName = [targetName substringFromIndex:( subFilter ? 2 : 1 )];
			if( ! [targetName length] ) return;
		}

		NSMutableData *msgData = [parameters objectAtIndex:1];
		const char *bytes = (const char *)[msgData bytes];
		BOOL ctcp = ( *bytes == '\001' && [msgData length] > 2 );

		[sender _setIdleTime:0.];
		[self _markUserAsOnline:sender];

		if( [[self chatRoomNamePrefixes] characterIsMember:[targetName characterAtIndex:0]] ) {
			MVChatRoom *room = [self joinedChatRoomWithName:targetName];
			if( ctcp ) [self _handleCTCP:msgData asRequest:YES fromSender:sender forRoom:room];
			else [[NSNotificationCenter defaultCenter] postNotificationOnMainThreadWithName:MVChatRoomGotMessageNotification object:room userInfo:[NSDictionary dictionaryWithObjectsAndKeys:sender, @"user", msgData, @"message", [NSString locallyUniqueString], @"identifier", nil]];
		} else {
			if( ctcp ) [self _handleCTCP:msgData asRequest:YES fromSender:sender forRoom:nil];
			else [[NSNotificationCenter defaultCenter] postNotificationOnMainThreadWithName:MVChatConnectionGotPrivateMessageNotification object:sender userInfo:[NSDictionary dictionaryWithObjectsAndKeys:msgData, @"message", [NSString locallyUniqueString], @"identifier", nil]];
		}
	}
}

- (void) _handleNoticeWithParameters:(NSArray *) parameters fromSender:(MVChatUser *) sender {
	// if the sender is a server lets make a user for the server name
	// this is not ideal but the notifications need user objects
	if( [sender isKindOfClass:[NSString class]] )
		sender = [self chatUserWithUniqueIdentifier:(NSString *) sender];

	if( [parameters count] == 2 && [sender isKindOfClass:[MVChatUser class]] ) {
		NSString *targetName = [parameters objectAtIndex:0];
		if( ! [targetName length] ) return;

		if( [targetName characterAtIndex:0] == '@' ) {
			// This is a special filtered target.
			// @#room	sends only to the operators on the room
			// @%#room	sends to the operators and half-operators on the room
			// @+#room	sends to the operators and half-operators and voices on the room
			BOOL subFilter = [targetName length] >= 2 && ( [targetName characterAtIndex:1] == '%' || [targetName characterAtIndex:1] == '+' ); 
			targetName = [targetName substringFromIndex:( subFilter ? 2 : 1 )];
			if( ! [targetName length] ) return;
		}

		NSMutableData *msgData = [parameters objectAtIndex:1];
		const char *bytes = (const char *)[msgData bytes];
		BOOL ctcp = ( *bytes == '\001' && [msgData length] > 2 );

		if( [[self chatRoomNamePrefixes] characterIsMember:[targetName characterAtIndex:0]] ) {
			MVChatRoom *room = [self joinedChatRoomWithName:targetName];
			if( ctcp ) [self _handleCTCP:msgData asRequest:NO fromSender:sender forRoom:room];
			else [[NSNotificationCenter defaultCenter] postNotificationOnMainThreadWithName:MVChatRoomGotMessageNotification object:room userInfo:[NSDictionary dictionaryWithObjectsAndKeys:sender, @"user", msgData, @"message", [NSString locallyUniqueString], @"identifier", [NSNumber numberWithBool:YES], @"notice", nil]];
		} else {
			if( ctcp ) [self _handleCTCP:msgData asRequest:NO fromSender:sender forRoom:nil];
			else {
				[[NSNotificationCenter defaultCenter] postNotificationOnMainThreadWithName:MVChatConnectionGotPrivateMessageNotification object:sender userInfo:[NSDictionary dictionaryWithObjectsAndKeys:msgData, @"message", [NSString locallyUniqueString], @"identifier", [NSNumber numberWithBool:YES], @"notice", nil]];
				if( [[sender nickname] isEqualToString:@"NickServ"] ) {
					NSString *msg = [self _newStringWithBytes:[msgData bytes] length:[msgData length]];

					if( [msg rangeOfString:@"NickServ"].location != NSNotFound && [msg rangeOfString:@"IDENTIFY"].location != NSNotFound ) {
						if( ! [self nicknamePassword] ) {
							[[NSNotificationCenter defaultCenter] postNotificationOnMainThreadWithName:MVChatConnectionNeedNicknamePasswordNotification object:self userInfo:nil];
						} else [self sendRawMessageImmediatelyWithFormat:@"NickServ IDENTIFY %@", [self nicknamePassword]];
					} else if( [msg rangeOfString:@"Password accepted"].location != NSNotFound ) {
						[[self localUser] _setIdentified:YES];
					} else if( [msg rangeOfString:@"authentication required"].location != NSNotFound ) {
						[[self localUser] _setIdentified:NO];
					}

					[msg release];
				}
			}
		}
	}
}

- (void) _handleCTCP:(NSDictionary *) ctcpInfo {
	BOOL request = [[ctcpInfo objectForKey:@"request"] boolValue];
	NSData *data = [ctcpInfo objectForKey:@"data"];
	MVChatUser *sender = [ctcpInfo objectForKey:@"sender"];
	MVChatRoom *room = [ctcpInfo objectForKey:@"room"];

	const char *line = (const char *)[data bytes] + 1; // skip the \001 char
	const char *end = line + [data length] - 2; // minus the first and last \001 char
	const char *current = line;

	while( line != end && *line != ' ' ) line++;

	NSString *command = [self _newStringWithBytes:current length:(line - current)];
	NSMutableData *arguments = nil;
	if( line != end ) {
		line++;
		arguments = [[NSMutableData allocWithZone:nil] initWithBytes:line length:(end - line)];
	}

	if( [command caseInsensitiveCompare:@"ACTION"] == NSOrderedSame && arguments ) {
		// special case ACTION and send it out like a message with the action flag
		if( room ) [[NSNotificationCenter defaultCenter] postNotificationOnMainThreadWithName:MVChatRoomGotMessageNotification object:room userInfo:[NSDictionary dictionaryWithObjectsAndKeys:sender, @"user", arguments, @"message", [NSString locallyUniqueString], @"identifier", [NSNumber numberWithBool:YES], @"action", nil]];
		else [[NSNotificationCenter defaultCenter] postNotificationOnMainThreadWithName:MVChatConnectionGotPrivateMessageNotification object:sender userInfo:[NSDictionary dictionaryWithObjectsAndKeys:arguments, @"message", [NSString locallyUniqueString], @"identifier", [NSNumber numberWithBool:YES], @"action", nil]];
		[command release];
		[arguments release];
		[ctcpInfo release];
		return;
	}

	[[NSNotificationCenter defaultCenter] postNotificationOnMainThreadWithName:( request ? MVChatConnectionSubcodeRequestNotification : MVChatConnectionSubcodeReplyNotification ) object:sender userInfo:[NSDictionary dictionaryWithObjectsAndKeys:command, @"command", arguments, @"arguments", nil]];

	NSMethodSignature *signature = [NSMethodSignature methodSignatureWithReturnAndArgumentTypes:@encode( BOOL ), @encode( NSString * ), @encode( NSString * ), @encode( MVChatUser * ), nil];
	NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
	if( request ) [invocation setSelector:@selector( processSubcodeRequest:withArguments:fromUser: )];
	else [invocation setSelector:@selector( processSubcodeReply:withArguments:fromUser: )];
	[invocation setArgument:&command atIndex:2];
	[invocation setArgument:&arguments atIndex:3];
	[invocation setArgument:&sender atIndex:4];

	NSArray *results = [[MVChatPluginManager defaultManager] makePluginsPerformInvocation:invocation stoppingOnFirstSuccessfulReturn:YES];
	if( [[results lastObject] boolValue] ) {
		[command release];
		[arguments release];
		[ctcpInfo release];
		return;
	}

	if( request ) {
		if( [command caseInsensitiveCompare:@"VERSION"] == NSOrderedSame ) {
			NSDictionary *systemVersion = [[NSDictionary allocWithZone:nil] initWithContentsOfFile:@"/System/Library/CoreServices/ServerVersion.plist"];
			if( ! [systemVersion count] ) systemVersion = [[NSDictionary allocWithZone:nil] initWithContentsOfFile:@"/System/Library/CoreServices/SystemVersion.plist"];
			NSDictionary *clientVersion = [[NSBundle mainBundle] infoDictionary];

#if __ppc__
			NSString *processor = @"PowerPC";
#elif __i386__
			NSString *processor = @"Intel";
#else
			NSString *processor = @"Unknown Architecture";
#endif

			NSString *reply = [[NSString allocWithZone:nil] initWithFormat:@"%@ %@ (%@) - %@ %@ (%@) - %@", [clientVersion objectForKey:@"CFBundleName"], [clientVersion objectForKey:@"CFBundleShortVersionString"], [clientVersion objectForKey:@"CFBundleVersion"], [systemVersion objectForKey:@"ProductName"], [systemVersion objectForKey:@"ProductUserVisibleVersion"], processor, [clientVersion objectForKey:@"MVChatCoreCTCPVersionReplyInfo"]];
			[sender sendSubcodeReply:command withArguments:reply];

			[reply release];
			[systemVersion release];
		} else if( [command caseInsensitiveCompare:@"TIME"] == NSOrderedSame ) {
			[sender sendSubcodeReply:command withArguments:[[NSDate date] description]];
		} else if( [command caseInsensitiveCompare:@"PING"] == NSOrderedSame ) {
			// only reply with packets less than 100 bytes, anything over that is bad karma
			if( [arguments length] < 100 ) [sender sendSubcodeReply:command withArguments:arguments];
		} else if( [command caseInsensitiveCompare:@"DCC"] == NSOrderedSame ) {
			NSString *msg = [self _newStringWithBytes:[arguments bytes] length:[arguments length]];
			NSString *subCommand = nil;
			NSString *fileName = nil;
			BOOL quotedFileName = NO;

			NSCharacterSet *whitespace = [NSCharacterSet whitespaceCharacterSet];
			NSScanner *scanner = [NSScanner scannerWithString:msg];

			[scanner scanUpToCharactersFromSet:whitespace intoString:&subCommand];

			if( [scanner scanString:@"\"" intoString:NULL] && [scanner scanUpToString:@"\"" intoString:&fileName] && [scanner scanString:@"\"" intoString:NULL] ) {
				quotedFileName = YES;
			} else {
				[scanner scanUpToCharactersFromSet:whitespace intoString:&fileName];
			}

			if( [subCommand caseInsensitiveCompare:@"SEND"] == NSOrderedSame ) {
				NSString *address = nil;
				int port = 0;
				long long size = 0;
				long long passiveId = 0;

				[scanner scanUpToCharactersFromSet:whitespace intoString:&address];
				[scanner scanInt:&port];
				[scanner scanLongLong:&size];

				if( [address rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@".:"]].location == NSNotFound ) {
					unsigned int ip4 = 0;
					sscanf( [address UTF8String], "%u", &ip4 );
					address = [NSString stringWithFormat:@"%lu.%lu.%lu.%lu", (ip4 & 0xff000000) >> 24, (ip4 & 0x00ff0000) >> 16, (ip4 & 0x0000ff00) >> 8, (ip4 & 0x000000ff)];
				}

				NSHost *host = [NSHost hostWithAddress:address];

				if( [scanner scanLongLong:&passiveId] && port > 0 ) {
					// this is a passive reply, look up the original transfer
					MVIRCUploadFileTransfer *transfer = nil;

					@synchronized( _fileTransfers ) {
						NSEnumerator *enumerator = [_fileTransfers objectEnumerator];
						while( ( transfer = [enumerator nextObject] ) )
							if( [transfer isUpload] && [transfer isPassive] && [[transfer user] isEqualToChatUser:sender] && [(id)transfer _passiveIdentifier] == passiveId )
								break;
					}

					if( transfer ) {
						[transfer _setHost:host];
						[transfer _setPort:port];
						[transfer _setupAndStart];
					}
				} else {
					MVIRCDownloadFileTransfer *transfer = [(MVIRCDownloadFileTransfer *)[MVIRCDownloadFileTransfer allocWithZone:nil] initWithUser:sender];

					if( port == 0 ) {
						[transfer _setPassiveIdentifier:passiveId];
						[transfer _setPassive:YES];
					}

					[transfer _setTurbo:[scanner scanString:@"T" intoString:NULL]];
					[transfer _setOriginalFileName:fileName];
					[transfer _setFileNameQuoted:quotedFileName];
					[transfer _setFinalSize:(unsigned long long)size];
					[transfer _setHost:host];
					[transfer _setPort:port];

					[[NSNotificationCenter defaultCenter] postNotificationOnMainThreadWithName:MVDownloadFileTransferOfferNotification object:transfer];

					[self _addFileTransfer:transfer];
					[transfer release];
				}
			} else if( [subCommand caseInsensitiveCompare:@"ACCEPT"] == NSOrderedSame ) {
				BOOL passive = NO;
				int port = 0;
				long long size = 0;
				long long passiveId = 0;

				[scanner scanInt:&port];
				[scanner scanLongLong:&size];

				if( [scanner scanLongLong:&passiveId] )
					passive = YES;

				@synchronized( _fileTransfers ) {
					NSEnumerator *enumerator = [_fileTransfers objectEnumerator];
					MVFileTransfer *transfer = nil;
					while( ( transfer = [enumerator nextObject] ) ) {
						if( [transfer isDownload] && [transfer isPassive] == passive && [[transfer user] isEqualToChatUser:sender] &&
							( ! passive ? [transfer port] == port : [(id)transfer _passiveIdentifier] == passiveId ) ) {
							[transfer _setTransfered:(unsigned long long)size];
							[transfer _setStartOffset:(unsigned long long)size];
							[(MVIRCDownloadFileTransfer *)transfer _setupAndStart];
						}
					}
				}
			} else if( [subCommand caseInsensitiveCompare:@"RESUME"] == NSOrderedSame ) {
				BOOL passive = NO;
				int port = 0;
				long long size = 0;
				long long passiveId = 0;

				[scanner scanInt:&port];
				[scanner scanLongLong:&size];

				if( [scanner scanLongLong:&passiveId] )
					passive = YES;

				@synchronized( _fileTransfers ) {
					NSEnumerator *enumerator = [_fileTransfers objectEnumerator];
					MVFileTransfer *transfer = nil;
					while( ( transfer = [enumerator nextObject] ) ) {
						if( [transfer isUpload] && [transfer isPassive] == passive && [[transfer user] isEqualToChatUser:sender] &&
							( ! passive ? [transfer port] == port : [(id)transfer _passiveIdentifier] == passiveId ) ) {
							[transfer _setTransfered:(unsigned long long)size];
							[transfer _setStartOffset:(unsigned long long)size];
							[sender sendSubcodeRequest:@"DCC ACCEPT" withArguments:[msg substringFromIndex:7]];
						}
					}
				}
			}

			[msg release];
		} else if( [command caseInsensitiveCompare:@"CLIENTINFO"] == NSOrderedSame ) {
			// make this extnesible later with a plugin registration method
			[sender sendSubcodeReply:command withArguments:@"VERSION TIME PING DCC CLIENTINFO"];
		}
	}

	[command release];
	[arguments release];
	[ctcpInfo release];
}

- (void) _handleCTCP:(NSMutableData *) data asRequest:(BOOL) request fromSender:(MVChatUser *) sender forRoom:(MVChatRoom *) room {
	NSMutableDictionary *info = [[NSMutableDictionary allocWithZone:nil] initWithCapacity:4];
	if( data ) [info setObject:data forKey:@"data"];
	if( sender ) [info setObject:sender forKey:@"sender"];
	if( room ) [info setObject:room forKey:@"room"];
	[info setObject:[NSNumber numberWithBool:request] forKey:@"request"];

	[self performSelectorOnMainThread:@selector( _handleCTCP: ) withObject:info waitUntilDone:NO];
}

#pragma mark -
#pragma mark Room Replies

- (void) _handleJoinWithParameters:(NSArray *) parameters fromSender:(MVChatUser *) sender {
	if( [parameters count] && [sender isKindOfClass:[MVChatUser class]] ) {
		NSString *name = [self _stringFromPossibleData:[parameters objectAtIndex:0]];
		MVChatRoom *room = [self joinedChatRoomWithName:name];

		if( [sender isLocalUser] ) {
			if( ! room ) {
				room = [[MVIRCChatRoom allocWithZone:nil] initWithName:name andConnection:self];
				[self _addJoinedRoom:room];
			} else [room retain];

			[room _setDateJoined:[NSDate date]];
			[room _setDateParted:nil];
			[room _setNamesSynced:NO];
			[room _clearMemberUsers];
			[room _clearBannedUsers];
		} else {
			[sender _setIdleTime:0.];
			[self _markUserAsOnline:sender];
			[room _addMemberUser:sender];
			[[NSNotificationCenter defaultCenter] postNotificationOnMainThreadWithName:MVChatRoomUserJoinedNotification object:room userInfo:[NSDictionary dictionaryWithObjectsAndKeys:sender, @"user", nil]];
		}
	}
}

- (void) _handlePartWithParameters:(NSArray *) parameters fromSender:(MVChatUser *) sender {
	if( [parameters count] >= 1 && [sender isKindOfClass:[MVChatUser class]] ) {
		NSString *roomName = [self _stringFromPossibleData:[parameters objectAtIndex:0]];
		MVChatRoom *room = [self joinedChatRoomWithName:roomName];
		if( ! room ) return;
		if( [sender isLocalUser] ) {
			[room _setDateParted:[NSDate date]];
			[[NSNotificationCenter defaultCenter] postNotificationOnMainThreadWithName:MVChatRoomPartedNotification object:room];
		} else {
			[room _removeMemberUser:sender];
			NSData *reason = ( [parameters count] >= 2 ? [parameters objectAtIndex:1] : nil );
			if( ! [reason isKindOfClass:[NSData class]] ) reason = nil;
			[[NSNotificationCenter defaultCenter] postNotificationOnMainThreadWithName:MVChatRoomUserPartedNotification object:room userInfo:[NSDictionary dictionaryWithObjectsAndKeys:sender, @"user", reason, @"reason", nil]];
		}
	}
}

- (void) _handleQuitWithParameters:(NSArray *) parameters fromSender:(MVChatUser *) sender {
	if( [parameters count] && [sender isKindOfClass:[MVChatUser class]] ) {
		if( [sender isLocalUser] ) return;

		[self _markUserAsOffline:sender];
		[_pendingWhoisUsers removeObject:sender];

		NSData *reason = [parameters objectAtIndex:0];
		if( ! [reason isKindOfClass:[NSData class]] ) reason = nil;
		NSDictionary *info = [[NSDictionary allocWithZone:nil] initWithObjectsAndKeys:sender, @"user", reason, @"reason", nil];

		MVChatRoom *room = nil;
		NSEnumerator *enumerator = [[self joinedChatRooms] objectEnumerator];
		while( ( room = [enumerator nextObject] ) ) {
			if( ! [room isJoined] || ! [room hasUser:sender] ) continue;
			[room _removeMemberUser:sender];
			[[NSNotificationCenter defaultCenter] postNotificationOnMainThreadWithName:MVChatRoomUserPartedNotification object:room userInfo:info];
		}

		[info release];
	}
}

- (void) _handleKickWithParameters:(NSArray *) parameters fromSender:(MVChatUser *) sender {
	// if the sender is a server lets make a user for the server name
	// this is not ideal but the notifications need user objects
	if( [sender isKindOfClass:[NSString class]] )
		sender = [self chatUserWithUniqueIdentifier:(NSString *) sender];

	if( [parameters count] >= 2 && [sender isKindOfClass:[MVChatUser class]] ) {
		MVChatRoom *room = [self joinedChatRoomWithName:[parameters objectAtIndex:0]];
		MVChatUser *user = [self chatUserWithUniqueIdentifier:[parameters objectAtIndex:1]];
		if( ! room || ! user ) return;

		NSData *reason = ( [parameters count] == 3 ? [parameters objectAtIndex:2] : nil );
		if( ! [reason isKindOfClass:[NSData class]] ) reason = nil;
		if( [user isLocalUser] ) {
			[room _setDateParted:[NSDate date]];
			[[NSNotificationCenter defaultCenter] postNotificationOnMainThreadWithName:MVChatRoomKickedNotification object:room userInfo:[NSDictionary dictionaryWithObjectsAndKeys:sender, @"byUser", reason, @"reason", nil]];
		} else {
			[room _removeMemberUser:user];
			[[NSNotificationCenter defaultCenter] postNotificationOnMainThreadWithName:MVChatRoomUserKickedNotification object:room userInfo:[NSDictionary dictionaryWithObjectsAndKeys:user, @"user", sender, @"byUser", reason, @"reason", nil]];
		}
	}
}

- (void) _handleTopicWithParameters:(NSArray *) parameters fromSender:(MVChatUser *) sender {
	// if the sender is a server lets make a user for the server name
	// this is not ideal but the notifications need user objects
	if( [sender isKindOfClass:[NSString class]] )
		sender = [self chatUserWithUniqueIdentifier:(NSString *) sender];

	if( [parameters count] == 2 && [sender isKindOfClass:[MVChatUser class]] ) {
		MVChatRoom *room = [self joinedChatRoomWithName:[parameters objectAtIndex:0]];
		[room _setTopic:[parameters objectAtIndex:1]];
		[room _setTopicAuthor:sender];
		[room _setTopicDate:[NSDate date]];
		[[NSNotificationCenter defaultCenter] postNotificationOnMainThreadWithName:MVChatRoomTopicChangedNotification object:room userInfo:nil];
	}
}

- (void) _parseRoomModes:(NSArray *) parameters forRoom:(MVChatRoom *) room fromSender:(MVChatUser *) sender {
#define enabledHighBit ( 1 << 31 )
#define banMode ( 1 << 30 )
#define banExcludeMode ( 1 << 29 )
#define inviteExcludeMode ( 1 << 28 )

	unsigned long oldModes = [room modes];
	unsigned long value = 0;
	NSMutableArray *argsNeeded = [[NSMutableArray allocWithZone:nil] initWithCapacity:10];
	unsigned int i = 0, count = [parameters count];
	while( i < count ) {
		NSString *param = [parameters objectAtIndex:i++];
		if( [param length] ) {
			char chr = [param characterAtIndex:0];
			if( chr == '+' || chr == '-' ) {
				unsigned enabled = YES;
				unsigned int j = 0, length = [param length];
				while( j < length ) {
					chr = [param characterAtIndex:j++];
					switch( chr ) {
						case '+': enabled = YES; break;
						case '-': enabled = NO; break;
						case 'i':
							if( enabled ) [room _setMode:MVChatRoomInviteOnlyMode withAttribute:nil];
							else [room _removeMode:MVChatRoomInviteOnlyMode];
							break;
						case 'p':
							if( enabled ) [room _setMode:MVChatRoomPrivateMode withAttribute:nil];
							else [room _removeMode:MVChatRoomPrivateMode];
							break;
						case 's':
							if( enabled ) [room _setMode:MVChatRoomSecretMode withAttribute:nil];
							else [room _removeMode:MVChatRoomSecretMode];
							break;
						case 'm':
							if( enabled ) [room _setMode:MVChatRoomNormalUsersSilencedMode withAttribute:nil];
							else [room _removeMode:MVChatRoomNormalUsersSilencedMode];
							break;
						case 'n':
							if( enabled ) [room _setMode:MVChatRoomNoOutsideMessagesMode withAttribute:nil];
							else [room _removeMode:MVChatRoomNoOutsideMessagesMode];
							break;
						case 't':
							if( enabled ) [room _setMode:MVChatRoomOperatorsOnlySetTopicMode withAttribute:nil];
							else [room _removeMode:MVChatRoomOperatorsOnlySetTopicMode];
							break;
						case 'l':
							if( ! enabled ) {
								[room _removeMode:MVChatRoomLimitNumberOfMembersMode];
								break;
							}
							value = MVChatRoomLimitNumberOfMembersMode;
							goto queue;
						case 'k':
							if( ! enabled ) [room _removeMode:MVChatRoomPassphraseToJoinMode];
							value = MVChatRoomPassphraseToJoinMode;
							goto queue;
						case 'b':
							value = banMode;
							goto queue;
						case 'e':
							value = banExcludeMode;
							goto queue;
						case 'I':
							value = inviteExcludeMode;
							goto queue;
						case 'o':
							value = MVChatRoomMemberOperatorMode;
							goto queue;
						case 'v':
							value = MVChatRoomMemberVoicedMode;
							goto queue;
						queue:
							if( enabled ) value |= enabledHighBit;
							[argsNeeded addObject:[NSNumber numberWithUnsignedLong:value]];
							break;
						default: {
							if( _serverInformation ) {
								NSMutableDictionary *supportedModes = [_serverInformation objectForKey:@"roomMemberModeTable"];
								value = [[supportedModes objectForKey:[NSString stringWithFormat:@"%c", chr]] unsignedLongValue];
								if( value ) goto queue;
							}
						}
					}
				}
			} else {
				if( [argsNeeded count] ) {
					unsigned long value = [[argsNeeded objectAtIndex:0] unsignedLongValue];
					BOOL enabled = ( ( value & enabledHighBit ) ? YES : NO );
					unsigned long mode = ( value & ~enabledHighBit );

					if( mode == MVChatRoomMemberOperatorMode || mode == MVChatRoomMemberHalfOperatorMode || mode == MVChatRoomMemberVoicedMode ) {
						MVChatUser *member = [self chatUserWithUniqueIdentifier:param];
						if( enabled ) [room _setMode:mode forMemberUser:member];
						else [room _removeMode:mode forMemberUser:member];
						[[NSNotificationCenter defaultCenter] postNotificationOnMainThreadWithName:MVChatRoomUserModeChangedNotification object:room userInfo:[NSDictionary dictionaryWithObjectsAndKeys:member, @"who", [NSNumber numberWithBool:enabled], @"enabled", [NSNumber numberWithUnsignedLong:mode], @"mode", sender, @"by", nil]];
					} else if( mode == banMode ) {
						MVChatUser *user = [MVChatUser wildcardUserFromString:param];
						if( enabled ) {
							[room _addBanForUser:user];
							[[NSNotificationCenter defaultCenter] postNotificationOnMainThreadWithName:MVChatRoomUserBannedNotification object:room userInfo:[NSDictionary dictionaryWithObjectsAndKeys:user, @"user", sender, @"byUser", nil]];
						} else {
							[room _removeBanForUser:user];
							[[NSNotificationCenter defaultCenter] postNotificationOnMainThreadWithName:MVChatRoomUserBanRemovedNotification object:room userInfo:[NSDictionary dictionaryWithObjectsAndKeys:user, @"user", sender, @"byUser", nil]];
						}
					} else if( mode == MVChatRoomLimitNumberOfMembersMode && enabled ) {
						[room _setMode:MVChatRoomLimitNumberOfMembersMode withAttribute:[NSNumber numberWithInt:[param intValue]]];
					} else if( mode == MVChatRoomPassphraseToJoinMode ) {
						if( enabled ) [room _setMode:MVChatRoomPassphraseToJoinMode withAttribute:param];
						else [room _removeMode:MVChatRoomPassphraseToJoinMode];
					}

					[argsNeeded removeObjectAtIndex:0];
				}
			}
		}
	}

#undef enabledHighBit
#undef banMode
#undef banExcludeMode
#undef inviteExcludeMode

	[argsNeeded release];

	unsigned int changedModes = ( oldModes ^ [room modes] );
	[[NSNotificationCenter defaultCenter] postNotificationOnMainThreadWithName:MVChatRoomModesChangedNotification object:room userInfo:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithUnsignedInt:changedModes], @"changedModes", sender, @"by", nil]];
}

- (void) _handleModeWithParameters:(NSArray *) parameters fromSender:(MVChatUser *) sender {
	// if the sender is a server lets make a user for the server name
	// this is not ideal but the notifications need user objects
	if( [sender isKindOfClass:[NSString class]] )
		sender = [self chatUserWithUniqueIdentifier:(NSString *) sender];

	if( [parameters count] >= 2 ) {
		NSString *targetName = [parameters objectAtIndex:0];
		if( [[self chatRoomNamePrefixes] characterIsMember:[targetName characterAtIndex:0]] ) {
			MVChatRoom *room = [self joinedChatRoomWithName:targetName];
			[self _parseRoomModes:[parameters subarrayWithRange:NSMakeRange( 1, [parameters count] - 1)] forRoom:room fromSender:sender];
		} else {
			// user modes
		}
	}
}

- (void) _handle324WithParameters:(NSArray *) parameters fromSender:(id) sender { // RPL_CHANNELMODEIS
	if( [parameters count] >= 3 ) {
		MVChatRoom *room = [self joinedChatRoomWithName:[parameters objectAtIndex:1]];
		[self _parseRoomModes:[parameters subarrayWithRange:NSMakeRange( 2, [parameters count] - 2)] forRoom:room fromSender:nil];
	}
}

#pragma mark -
#pragma mark Misc. Replies

- (void) _handlePingWithParameters:(NSArray *) parameters fromSender:(id) sender {
	if( [parameters count] >= 1 ) {
		if( [parameters count] == 1 )
			[self sendRawMessageImmediatelyWithComponents:@"PONG :", [parameters objectAtIndex:0], nil];
		else [self sendRawMessageImmediatelyWithComponents:@"PONG ", [parameters objectAtIndex:1], @" :", [parameters objectAtIndex:0], nil];

		if( [sender isKindOfClass:[MVChatUser class]] )
			[self _markUserAsOnline:sender];
	}
}

- (void) _handleInviteWithParameters:(NSArray *) parameters fromSender:(MVChatUser *) sender {
	// if the sender is a server lets make a user for the server name
	// this is not ideal but the notifications need user objects
	if( [sender isKindOfClass:[NSString class]] )
		sender = [self chatUserWithUniqueIdentifier:(NSString *) sender];

	if( [parameters count] == 2 && [sender isKindOfClass:[MVChatUser class]] ) {
		NSString *roomName = [self _stringFromPossibleData:[parameters objectAtIndex:1]];
		[self _markUserAsOnline:sender];
		[[NSNotificationCenter defaultCenter] postNotificationOnMainThreadWithName:MVChatRoomInvitedNotification object:self userInfo:[NSDictionary dictionaryWithObjectsAndKeys:sender, @"user", roomName, @"room", nil]];
	}
}

- (void) _handleNickWithParameters:(NSArray *) parameters fromSender:(MVChatUser *) sender {
	if( [parameters count] == 1 && [sender isKindOfClass:[MVChatUser class]] ) {
		NSString *nick = [self _stringFromPossibleData:[parameters objectAtIndex:0]];
		NSString *oldNickname = [[sender nickname] retain];
		NSString *oldIdentifier = [[sender uniqueIdentifier] retain];

		[sender _setIdleTime:0.];
		[self _markUserAsOnline:sender];

		NSNotification *note = nil;
		if( [sender isLocalUser] ) {
			[self _setCurrentNickname:nick];
			[sender _setIdentified:NO];
			[sender _setUniqueIdentifier:[nick lowercaseString]];
			note = [NSNotification notificationWithName:MVChatConnectionNicknameAcceptedNotification object:self userInfo:nil];
		} else {
			[self _updateKnownUser:sender withNewNickname:nick];
			note = [NSNotification notificationWithName:MVChatUserNicknameChangedNotification object:sender userInfo:[NSDictionary dictionaryWithObjectsAndKeys:oldNickname, @"oldNickname", nil]];
		}

		NSEnumerator *enumerator = [[self joinedChatRooms] objectEnumerator];
		MVChatRoom *room = nil;

		while( ( room = [enumerator nextObject] ) ) {
			if( ! [room isJoined] || ! [room hasUser:sender] ) continue;
			[room _updateMemberUser:sender fromOldUniqueIdentifier:oldIdentifier];
		}

		[[NSNotificationCenter defaultCenter] postNotificationOnMainThread:note]; 

		[oldNickname release];
		[oldIdentifier release];
	}
}

- (void) _handle303WithParameters:(NSArray *) parameters fromSender:(id) sender { // RPL_ISON
	if( [parameters count] == 2 && _isonSentCount > 0 ) {
		_isonSentCount--;

		NSString *names = [self _stringFromPossibleData:[parameters objectAtIndex:1]];
		NSArray *users = [names componentsSeparatedByString:@" "];
		NSEnumerator *enumerator = [users objectEnumerator];
		NSString *nick = nil;

		while( ( nick = [enumerator nextObject] ) ) {
			if( ! [nick length] ) continue;

			NSString *nickLower = [nick lowercaseString];
			if( [_lastSentIsonNicknames containsObject:nickLower] ) {
				MVChatUser *user = [self chatUserWithUniqueIdentifier:nick];
				if( ! [[user nickname] isEqualToString:nick] && [[user nickname] caseInsensitiveCompare:nick] == NSOrderedSame )
					[user _setNickname:nick]; // nick differed only in case, change to the proper case
				if( [[user dateUpdated] timeIntervalSinceNow] < -JVWatchedUserWHOISDelay || ! [user dateUpdated] )
					[self _scheduleWhoisForUser:user];
				[self _markUserAsOnline:user];
				[_lastSentIsonNicknames removeObject:nickLower];
			}
		}

		if( ! _isonSentCount ) {
			enumerator = [_lastSentIsonNicknames objectEnumerator];
			while( ( nick = [enumerator nextObject] ) ) {
				MVChatUser *user = [self chatUserWithUniqueIdentifier:nick];
				[self _markUserAsOffline:user];
			}

			[_lastSentIsonNicknames release];
			_lastSentIsonNicknames = nil;
		}
	} else if( [parameters count] == 2 ) {
		NSString *names = [self _stringFromPossibleData:[parameters objectAtIndex:1]];
		NSArray *users = [names componentsSeparatedByString:@" "];
		NSEnumerator *enumerator = [users objectEnumerator];
		NSString *nick = nil;

		while( ( nick = [enumerator nextObject] ) ) {
			if( ! [nick length] ) continue;

			MVChatUser *user = [self chatUserWithUniqueIdentifier:nick];
			if( ! [[user nickname] isEqualToString:nick] && [[user nickname] caseInsensitiveCompare:nick] == NSOrderedSame )
				[user _setNickname:nick]; // nick differed only in case, change to the proper case
			[self _markUserAsOnline:user];
		}
	}
}

#pragma mark -
#pragma mark Away Replies

- (void) _handle301WithParameters:(NSArray *) parameters fromSender:(id) sender { // RPL_AWAY
	if( [parameters count] == 3 ) {
		MVChatUser *user = [self chatUserWithUniqueIdentifier:[parameters objectAtIndex:1]];
		if( ! [[user awayStatusMessage] isEqual:[parameters objectAtIndex:2]] ) {
			[user _setStatus:MVChatUserAwayStatus];
			[user _setAwayStatusMessage:[parameters objectAtIndex:2]];
			[[NSNotificationCenter defaultCenter] postNotificationOnMainThreadWithName:MVChatUserAwayStatusMessageChangedNotification object:user userInfo:nil];
		}
	}
}

- (void) _handle305WithParameters:(NSArray *) parameters fromSender:(id) sender { // RPL_UNAWAY
	[[NSNotificationCenter defaultCenter] postNotificationOnMainThreadWithName:MVChatConnectionSelfAwayStatusChangedNotification object:self userInfo:nil];
}

- (void) _handle306WithParameters:(NSArray *) parameters fromSender:(id) sender { // RPL_NOWAWAY
	[[NSNotificationCenter defaultCenter] postNotificationOnMainThreadWithName:MVChatConnectionSelfAwayStatusChangedNotification object:self userInfo:nil];
}

#pragma mark -
#pragma mark NAMES Replies

- (void) _handle353WithParameters:(NSArray *) parameters fromSender:(id) sender { // RPL_NAMREPLY
	if( [parameters count] == 4 ) {
		MVChatRoom *room = [self joinedChatRoomWithName:[parameters objectAtIndex:2]];
		if( room && ! [room _namesSynced] ) {
			NSAutoreleasePool *pool = [[NSAutoreleasePool allocWithZone:nil] init];
			NSString *names = [self _stringFromPossibleData:[parameters objectAtIndex:3]];
			NSArray *members = [names componentsSeparatedByString:@" "];
			NSEnumerator *enumerator = [members objectEnumerator];
			NSString *memberName = nil;

			while( ( memberName = [enumerator nextObject] ) ) {
				if( ! [memberName length] ) break;

				MVChatRoomMemberMode modes = MVChatRoomMemberNoModes;
				if( _serverInformation ) {
					NSMutableDictionary *prefixes = [_serverInformation objectForKey:@"roomMemberPrefixTable"];
					NSString *key = [[NSString allocWithZone:nil] initWithFormat:@"%c", [memberName characterAtIndex:0]];
					modes = [[prefixes objectForKey:key] unsignedLongValue];
					[key release];
				} else {
					switch( [memberName characterAtIndex:0] ) {
						case '+': modes = MVChatRoomMemberVoicedMode; break;
						case '@': modes = MVChatRoomMemberOperatorMode; break;
						default: break;
					}
				}

				if( modes != MVChatRoomMemberNoModes )
					memberName = [memberName substringFromIndex:1];

				MVChatUser *member = [self chatUserWithUniqueIdentifier:memberName];
				[room _addMemberUser:member];
				[room _setModes:modes forMemberUser:member];

				[self _markUserAsOnline:member];
			}

			if( [pool respondsToSelector:@selector( drain )] )
				[pool drain];
			[pool release];
		}
	}
}

- (void) _handle366WithParameters:(NSArray *) parameters fromSender:(id) sender { // RPL_ENDOFNAMES
	if( [parameters count] >= 2 ) {
		MVChatRoom *room = [self joinedChatRoomWithName:[parameters objectAtIndex:1]];
		if( room && ! [room _namesSynced] ) {
			[room _setNamesSynced:YES];
			[[NSNotificationCenter defaultCenter] postNotificationOnMainThreadWithName:MVChatRoomJoinedNotification object:room];

			if( [[room memberUsers] count] <= JVMaximumMembersForWhoRequest )
				[self sendRawMessageImmediatelyWithFormat:@"WHO %@", [room name]];
			[self sendRawMessageImmediatelyWithFormat:@"MODE %@ b", [room name]];

			[room release]; // balance the alloc or retain from _handleJoinWithParameters
		}
	}
}

#pragma mark -
#pragma mark WHO Replies

- (void) _handle352WithParameters:(NSArray *) parameters fromSender:(id) sender { // RPL_WHOREPLY
	if( [parameters count] >= 7 ) {
		MVChatUser *member = [self chatUserWithUniqueIdentifier:[parameters objectAtIndex:5]];
		[member _setUsername:[parameters objectAtIndex:2]];
		[member _setAddress:[parameters objectAtIndex:3]];

		NSString *statusString = [self _stringFromPossibleData:[parameters objectAtIndex:6]];
		unichar userStatus = ( [statusString length] ? [statusString characterAtIndex:0] : 0 );
		if( userStatus == 'H' ) {
			[member _setAwayStatusMessage:nil];
			[member _setStatus:MVChatUserAvailableStatus];
		} else if( userStatus == 'G' ) {
			[member _setStatus:MVChatUserAwayStatus];
		}

		[member _setServerOperator:( [statusString length] >= 2 && [statusString characterAtIndex:1] == '*' )];

		if( [parameters count] >= 8 ) {
			NSString *lastParam = [self _stringFromPossibleData:[parameters objectAtIndex:7]];
			NSRange range = [lastParam rangeOfCharacterFromSet:[NSCharacterSet whitespaceCharacterSet]];
			if( range.location != NSNotFound ) {
				NSString *name = [lastParam substringFromIndex:range.location + range.length];
				if( [name length] ) [member _setRealName:name];
				else [member _setRealName:nil];
			} else [member _setRealName:nil];
		}

		[self _markUserAsOnline:member];
	}
}

- (void) _handle315WithParameters:(NSArray *) parameters fromSender:(id) sender { // RPL_ENDOFWHO
	if( [parameters count] >= 2 ) {
		MVChatRoom *room = [self joinedChatRoomWithName:[parameters objectAtIndex:1]];
		if( room ) [[NSNotificationCenter defaultCenter] postNotificationOnMainThreadWithName:MVChatRoomMemberUsersSyncedNotification object:room];
	}
}

#pragma mark -
#pragma mark Channel List Reply

- (void) _handle322WithParameters:(NSArray *) parameters fromSender:(id) sender { // RPL_LIST
	if( [parameters count] == 4 ) {
		NSString *room = [parameters objectAtIndex:1];
		unsigned int users = [[parameters objectAtIndex:2] intValue];
		NSData *topic = [parameters objectAtIndex:3];
		if( ! [topic isKindOfClass:[NSData class]] ) topic = nil;

		NSMutableDictionary *info = [[NSMutableDictionary allocWithZone:nil] initWithObjectsAndKeys:[NSNumber numberWithUnsignedInt:users], @"users", [NSDate date], @"cached", room, @"room", topic, @"topic", nil];
		[self performSelectorOnMainThread:@selector( _addRoomToCache: ) withObject:info waitUntilDone:NO];
		[info release];
	}
}

#pragma mark -
#pragma mark Ban List Replies

- (void) _handle367WithParameters:(NSArray *) parameters fromSender:(id) sender { // RPL_BANLIST
	if( [parameters count] >= 3 ) {
		MVChatRoom *room = [self joinedChatRoomWithName:[parameters objectAtIndex:1]];
		MVChatUser *user = [MVChatUser wildcardUserFromString:[parameters objectAtIndex:2]];
		if( [parameters count] >= 5 ) {
			[user setAttribute:[parameters objectAtIndex:3] forKey:MVChatUserBanServerAttribute];

			NSString *dateString = [self _stringFromPossibleData:[parameters objectAtIndex:4]];
			NSTimeInterval time = [dateString doubleValue];
			if( time > 631138520 ) // this makes sure it is a viable date
				[user setAttribute:[NSDate dateWithTimeIntervalSince1970:time] forKey:MVChatUserBanDateAttribute];
		}

		if( [room _bansSynced] ) [room _clearBannedUsers];
		[room _addBanForUser:user];
	}
}

- (void) _handle368WithParameters:(NSArray *) parameters fromSender:(id) sender { // RPL_ENDOFBANLIST
	if( [parameters count] >= 2 ) {
		MVChatRoom *room = [self joinedChatRoomWithName:[parameters objectAtIndex:1]];
		[room _setBansSynced:YES];
		if( room ) [[NSNotificationCenter defaultCenter] postNotificationOnMainThreadWithName:MVChatRoomBannedUsersSyncedNotification object:room];
	}
}

#pragma mark -
#pragma mark Topic Replies

- (void) _handle332WithParameters:(NSArray *) parameters fromSender:(id) sender { // RPL_TOPIC
	if( [parameters count] == 3 ) {
		MVChatRoom *room = [self joinedChatRoomWithName:[parameters objectAtIndex:1]];
		[room _setTopic:[parameters objectAtIndex:2]];
	}
}

- (void) _handle333WithParameters:(NSArray *) parameters fromSender:(id) sender { // RPL_TOPICWHOTIME_IRCU
	if( [parameters count] >= 4 ) {
		MVChatRoom *room = [self joinedChatRoomWithName:[parameters objectAtIndex:1]];
		MVChatUser *author = [MVChatUser wildcardUserFromString:[parameters objectAtIndex:2]];
		[room _setTopicAuthor:author];
		if( [[parameters objectAtIndex:3] doubleValue] > 631138520 )
			[room _setTopicDate:[NSDate dateWithTimeIntervalSince1970:[[parameters objectAtIndex:3] doubleValue]]];
		[[NSNotificationCenter defaultCenter] postNotificationOnMainThreadWithName:MVChatRoomTopicChangedNotification object:room userInfo:nil];
	}
}

#pragma mark -
#pragma mark WHOIS Replies

- (void) _handle311WithParameters:(NSArray *) parameters fromSender:(id) sender { // RPL_WHOISUSER
	if( [parameters count] == 6 ) {
		NSString *nick = [parameters objectAtIndex:1];
		MVChatUser *user = [self chatUserWithUniqueIdentifier:nick];
		if( ! [[user nickname] isEqualToString:nick] && [[user nickname] caseInsensitiveCompare:nick] == NSOrderedSame )
			[user _setNickname:nick]; // nick differed only in case, change to the proper case
		[user _setUsername:[parameters objectAtIndex:2]];
		[user _setAddress:[parameters objectAtIndex:3]];
		[user _setRealName:[self _stringFromPossibleData:[parameters objectAtIndex:5]]];
		[user _setStatus:MVChatUserAvailableStatus]; // set this to available, we will change it if we get a RPL_AWAY
		[user _setAwayStatusMessage:nil]; // set this to nil, we will get it if we get a RPL_AWAY
		[user _setServerOperator:NO]; // set this to NO now so we get the true values later in the RPL_WHOISOPERATOR

		[self _markUserAsOnline:user];
	}
}

- (void) _handle312WithParameters:(NSArray *) parameters fromSender:(id) sender { // RPL_WHOISSERVER
	if( [parameters count] >= 3 ) {
		MVChatUser *user = [self chatUserWithUniqueIdentifier:[parameters objectAtIndex:1]];
		[user _setServerAddress:[parameters objectAtIndex:2]];
	}
}

- (void) _handle313WithParameters:(NSArray *) parameters fromSender:(id) sender { // RPL_WHOISOPERATOR
	if( [parameters count] >= 2 ) {
		MVChatUser *user = [self chatUserWithUniqueIdentifier:[parameters objectAtIndex:1]];
		[user _setServerOperator:YES];
	}
}

- (void) _handle317WithParameters:(NSArray *) parameters fromSender:(id) sender { // RPL_WHOISIDLE
	if( [parameters count] >= 3 ) {
		MVChatUser *user = [self chatUserWithUniqueIdentifier:[parameters objectAtIndex:1]];
		[user _setIdleTime:[[parameters objectAtIndex:2] doubleValue]];
		[user _setDateConnected:nil];

		// parameter 4 is connection time on some servers
		if( [parameters count] >= 4 ) {
			NSString *connectedTime = [self _stringFromPossibleData:[parameters objectAtIndex:3]];
			NSTimeInterval time = [connectedTime doubleValue];
			// prevent showing 34+ years connected time, this makes sure it is a viable date
			if( time > 631138520 ) [user _setDateConnected:[NSDate dateWithTimeIntervalSince1970:time]];
		}
	}
}

- (void) _handle318WithParameters:(NSArray *) parameters fromSender:(id) sender { // RPL_ENDOFWHOIS
	if( [parameters count] >= 2 ) {
		MVChatUser *user = [self chatUserWithUniqueIdentifier:[parameters objectAtIndex:1]];
		[user _setDateUpdated:[NSDate date]];

		[[NSNotificationCenter defaultCenter] postNotificationOnMainThreadWithName:MVChatUserInformationUpdatedNotification object:user userInfo:nil];

		if( [_pendingWhoisUsers containsObject:user] ) {
			[_pendingWhoisUsers removeObject:user];
			[self _whoisNextScheduledUser];
		}
	}
}

- (void) _handle319WithParameters:(NSArray *) parameters fromSender:(id) sender { // RPL_WHOISCHANNELS
	if( [parameters count] == 3 ) {
		NSString *rooms = [self _stringFromPossibleData:[parameters objectAtIndex:2]];
		NSArray *chanArray = [[rooms stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] componentsSeparatedByString:@" "];
		NSMutableArray *results = [[NSMutableArray allocWithZone:nil] initWithCapacity:[chanArray count]];
		NSEnumerator *enumerator = [chanArray objectEnumerator];
		NSString *room = nil;

		NSCharacterSet *modeChars = nil;
		if( _serverInformation ) modeChars = [[_serverInformation objectForKey:@"roomMemberPrefixes"] retain];
		if( ! modeChars ) modeChars = [[NSCharacterSet characterSetWithCharactersInString:@"@+"] retain];

		while( ( room = [enumerator nextObject] ) ) {
			NSRange prefixRange = [room rangeOfCharacterFromSet:modeChars options:NSAnchoredSearch];
			if( prefixRange.location != NSNotFound )
				room = [room substringFromIndex:( prefixRange.location + prefixRange.length )];
			room = [room stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
			if( [room length] ) [results addObject:room];
		}

		if( [results count] ) {
			MVChatUser *user = [self chatUserWithUniqueIdentifier:[parameters objectAtIndex:1]];
			[user setAttribute:results forKey:MVChatUserKnownRoomsAttribute];
		}

		[modeChars release];
		[results release];
	}
}

- (void) _handle320WithParameters:(NSArray *) parameters fromSender:(id) sender { // RPL_WHOISIDENTIFIED
	if( [parameters count] == 3 ) {
		NSString *comment = [self _stringFromPossibleData:[parameters objectAtIndex:2]];
		if( [comment rangeOfString:@"identified" options:NSCaseInsensitiveSearch].location != NSNotFound ) {
			MVChatUser *user = [self chatUserWithUniqueIdentifier:[parameters objectAtIndex:1]];
			[user _setIdentified:YES];
		}
	}
}

#pragma mark -
#pragma mark Error Replies

- (void) _handle401WithParameters:(NSArray *) parameters fromSender:(id) sender { // ERR_NOSUCHNICK
	if( [parameters count] >= 2 ) {
		MVChatUser *user = [self chatUserWithUniqueIdentifier:[parameters objectAtIndex:1]];
		[self _markUserAsOffline:user];
		if( [_pendingWhoisUsers containsObject:user] ) {
			[_pendingWhoisUsers removeObject:user];
			[self _whoisNextScheduledUser];
		}
	}
}

- (void) _handle402WithParameters:(NSArray *) parameters fromSender:(id) sender { // ERR_NOSUCHSERVER
	// some servers send back 402 (No such server) when we send our double nickname WHOIS requests, treat as a user
	if( [parameters count] >= 2 ) {
		MVChatUser *user = [self chatUserWithUniqueIdentifier:[parameters objectAtIndex:1]];
		[self _markUserAsOffline:user];
		if( [_pendingWhoisUsers containsObject:user] ) {
			[_pendingWhoisUsers removeObject:user];
			[self _whoisNextScheduledUser];
		}
	}
}

- (void) _handle421WithParameters:(NSArray *) parameters fromSender:(id) sender { // ERR_UNKNOWNCOMMAND
	if( [parameters count] >= 2 ) {
		NSString *command = [parameters objectAtIndex:1];
		if( [command caseInsensitiveCompare:@"NickServ"] == NSOrderedSame ) {
			// the NickServ command isn't supported, this is an older server
			// lets send a private message to NickServ to identify
			if( [[self nicknamePassword] length] )
				[self sendRawMessageWithFormat:@"PRIVMSG NickServ :IDENTIFY %@", [self nicknamePassword]];
		}
	}
}

#pragma mark -
#pragma mark Watch Replies

- (void) _handle604WithParameters:(NSArray *) parameters fromSender:(id) sender { // RPL_NOWON_BAHAMUT_UNREAL
	if( [parameters count] >= 5 ) {
		MVChatUser *user = [self chatUserWithUniqueIdentifier:[parameters objectAtIndex:1]];
		[user _setUsername:[parameters objectAtIndex:2]];
		[user _setAddress:[parameters objectAtIndex:3]];

		[self _markUserAsOnline:user];

		if( [[user dateUpdated] timeIntervalSinceNow] < -JVWatchedUserWHOISDelay || ! [user dateUpdated] )
			[self _scheduleWhoisForUser:user];
	}
}

- (void) _handle600WithParameters:(NSArray *) parameters fromSender:(id) sender { // RPL_LOGON_BAHAMUT_UNREAL
	if( [parameters count] >= 5 ) {
		[self _handle604WithParameters:parameters fromSender:sender]; // do everything we do above
	}
}
@end
