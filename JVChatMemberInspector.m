#import <Cocoa/Cocoa.h>
#import <ChatCore/MVChatConnection.h>
#import "JVChatMemberInspector.h"
#import "MVFileTransferController.h"

@implementation JVChatRoomMember (JVChatRoomMemberInspection)
- (id <JVInspector>) inspector {
	return [[[JVChatMemberInspector alloc] initWithChatMember:self] autorelease];
}
@end

#pragma mark -

@implementation JVChatMemberInspector
- (id) initWithChatMember:(JVChatRoomMember *) member {
	if( ( self = [self init] ) ) {
		_member = [member retain];
		_localOnly = NO;
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector( gotUserInfo: ) name:MVChatConnectionGotUserInfoNotification object:[_member connection]];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector( gotAwayStatus: ) name:MVChatConnectionUserAwayStatusNotification object:[_member connection]];
	}
	return self;
}

- (void) dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];

	[_member release];
	_member = nil;

	[super dealloc];
}

#pragma mark -

- (NSView *) view {
	if( ! _nibLoaded ) _nibLoaded = [NSBundle loadNibNamed:@"JVChatMemberInspector" owner:self];
	return view;
}

- (NSSize) minSize {
	return NSMakeSize( 220., 359. );
}

- (NSString *) title {
	return [_member nickname];
}

- (NSString *) type {
	return NSLocalizedString( @"User", "chat user inspector type" );
}

- (void) willLoad {
	[progress startAnimation:nil];
	[nickname setObjectValue:[_member nickname]];
	[[_member connection] fetchInformationForUser:[_member nickname] withPriority:NO fromLocalServer:_localOnly];
}

#pragma mark -

- (void) setFetchLocalServerInfoOnly:(BOOL) localOnly {
	_localOnly = localOnly;
}

- (void) gotAddress:(NSString *) ip {
	[address setObjectValue:( ip ? ip : NSLocalizedString( @"n/a", "not applicable or not available" ) )];
	[address setToolTip:( ip ? ip : nil )];
	[progress stopAnimation:nil];
}

- (oneway void) lookupAddress:(NSString *) host {
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSString *ip = [[NSHost hostWithName:host] address];
	[self gotAddress:ip];
	[pool release];
}

- (void) gotUserInfo:(NSNotification *) notification {
	if( [[[notification userInfo] objectForKey:@"who"] caseInsensitiveCompare:[_member nickname]] != NSOrderedSame ) return;
	NSDictionary *info = [[notification userInfo] objectForKey:@"info"];
	NSString *clas = nil;
	if( [[info objectForKey:@"flags"] intValue] == 0 ) {
		clas = NSLocalizedString( @"Restricted user", "restricted user class" );
	} else if( [[info objectForKey:@"flags"] intValue] & 0x02 ) {
		clas = NSLocalizedString( @"Normal user", "normal user class" );
	} else if( [[info objectForKey:@"flags"] intValue] & 0x04 ) {
		clas = NSLocalizedString( @"Server operator", "server operator class" );
	}
	[class setObjectValue:clas];
	[username setObjectValue:[info objectForKey:@"username"]];
	[hostname setObjectValue:[info objectForKey:@"hostname"]];
	[hostname setToolTip:[info objectForKey:@"hostname"]];
	[NSThread detachNewThreadSelector:@selector( lookupAddress: ) toTarget:self withObject:[[[info objectForKey:@"hostname"] copy] autorelease]];
	[server setObjectValue:[info objectForKey:@"server"]];
	[realName setObjectValue:[info objectForKey:@"realName"]];
	[realName setToolTip:[info objectForKey:@"realName"]];
	[connected setObjectValue:MVReadableTime( [[info objectForKey:@"connected"] doubleValue], YES )];
	[idle setObjectValue:MVReadableTime( [[NSDate date] timeIntervalSince1970] + [[info objectForKey:@"idle"] doubleValue], YES )];
}

- (void) gotAwayStatus:(NSNotification *) notification {
	NSData *data = [[notification userInfo] objectForKey:@"message"];
	NSString *strMsg = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
	if( ! strMsg ) strMsg = [NSString stringWithCString:[data bytes] length:[data length]];
	[away setObjectValue:strMsg];
}

- (IBAction) sendPing:(id) sender {
	
}

- (IBAction) requestLocalTime:(id) sender {
	
}

- (IBAction) requestClientInfo:(id) sender {
	
}
@end