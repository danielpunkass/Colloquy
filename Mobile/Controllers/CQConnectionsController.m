#import "CQConnectionsController.h"
#import "CQConnectionsViewController.h"
#import "CQConnectionEditViewController.h"
#import "CQConnectionCreationViewController.h"
#import "CQChatController.h"
#import "CQKeychain.h"

#import <ChatCore/MVChatConnection.h>

@interface CQConnectionsController (CQConnectionsControllerPrivate)
- (void) _loadConnectionList;
@end

#pragma mark -

@implementation CQConnectionsController
+ (CQConnectionsController *) defaultController {
	static BOOL creatingSharedInstance = NO;
	static CQConnectionsController *sharedInstance = nil;

	if (!sharedInstance && !creatingSharedInstance) {
		creatingSharedInstance = YES;
		sharedInstance = [[self alloc] init];
	}

	return sharedInstance;
}

- (id) init {
	if (!(self = [super init]))
		return nil;

	self.title = NSLocalizedString(@"Connections", @"Connections tab title");
	self.tabBarItem.image = [UIImage imageNamed:@"connections.png"];
	self.delegate = self;

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillTerminate) name:UIApplicationWillTerminateNotification object:[UIApplication sharedApplication]];

	_connections = [[NSMutableArray alloc] init];

	[self _loadConnectionList];

	return self;
}

- (void) dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationWillTerminateNotification object:[UIApplication sharedApplication]];

	[_connections release];
	[_connectionsViewController release];

	[super dealloc];
}

#pragma mark -

- (void) viewDidLoad {
	[super viewDidLoad];

	if (!_connectionsViewController) {
		_connectionsViewController = [[CQConnectionsViewController alloc] init];

		for (MVChatConnection *connection in _connections)
			[_connectionsViewController addConnection:connection];
	}

	[self pushViewController:_connectionsViewController animated:NO];
}

- (void) viewWillAppear:(BOOL) animated {
	[super viewWillAppear:animated];

	[self popToRootViewControllerAnimated:NO];
}

- (void) viewDidAppear:(BOOL) animated {
	[super viewDidAppear:animated];

	static BOOL offeredToCreate;
	if (!_connections.count && !offeredToCreate) {
		[self showModalNewConnectionView];
		offeredToCreate = YES;
	}
}

- (BOOL) shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation) interfaceOrientation {
	// This should support UIDeviceOrientationLandscapeLeft too, but convertPoint: returns bad results in that orientation.
	return (interfaceOrientation == UIDeviceOrientationPortrait || interfaceOrientation == UIDeviceOrientationLandscapeRight);
}

#pragma mark -

- (void) applicationWillTerminate {
	for (MVChatConnection *connection in _connections)
		[connection disconnect];

	[self saveConnections];
}

#pragma mark -

- (void) showModalNewConnectionView {
	CQConnectionCreationViewController *connectionCreationViewController = [[CQConnectionCreationViewController alloc] init];
	[self presentModalViewController:connectionCreationViewController animated:YES];
	[connectionCreationViewController release];
}

- (void) editConnection:(MVChatConnection *) connection {
	CQConnectionEditViewController *editViewController = [[CQConnectionEditViewController alloc] init];
	editViewController.connection = connection;

	_wasEditingConnection = YES;
	[self pushViewController:editViewController animated:YES];

	[editViewController release];
}

- (void) navigationController:(UINavigationController *) navigationController didShowViewController:(UIViewController *) viewController animated:(BOOL) animated {
	if (viewController == _connectionsViewController && _wasEditingConnection) {
		[self saveConnections];
		_wasEditingConnection = NO;
	}
}

#pragma mark -

- (void) _deregisterNotificationsForConnection:(MVChatConnection *) connection {
	[[NSNotificationCenter defaultCenter] removeObserver:self name:MVChatConnectionWillConnectNotification object:connection];
}

- (void) _registerNotificationsForConnection:(MVChatConnection *) connection {
	// Remove any previous observers, to prevent registering twice.
	[self _deregisterNotificationsForConnection:connection];

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_willConnect:) name:MVChatConnectionWillConnectNotification object:connection];
}

- (void) _willConnect:(NSNotification *) notification {
	MVChatConnection *connection = notification.object;
	NSArray *rooms = connection.automaticJoinedRooms;
	if (rooms.count)
		[connection joinChatRoomsNamed:rooms];
}

#pragma mark -

- (void) _loadConnectionList {
	if (_connections.count)
		return; // already loaded connections

	NSArray *list = [[NSUserDefaults standardUserDefaults] arrayForKey:@"MVChatBookmarks"];
	for (NSMutableDictionary *info in list) {
		MVChatConnectionType type = MVChatConnectionIRCType;
		if ([[info objectForKey:@"type"] isEqualToString:@"icb"])
			type = MVChatConnectionICBType;
		else if ([[info objectForKey:@"type"] isEqualToString:@"irc"])
			type = MVChatConnectionIRCType;
		else if ([[info objectForKey:@"type"] isEqualToString:@"silc"])
			type = MVChatConnectionSILCType;
		else if ([[info objectForKey:@"type"] isEqualToString:@"xmpp"])
			type = MVChatConnectionXMPPType;

		MVChatConnection *connection = nil;
		if ([info objectForKey:@"url"])
			connection = [[MVChatConnection alloc] initWithURL:[NSURL URLWithString:[info objectForKey:@"url"]]];
		else connection = [[MVChatConnection alloc] initWithServer:[info objectForKey:@"server"] type:type port:[[info objectForKey:@"port"] unsignedShortValue] user:[info objectForKey:@"nickname"]];

		if (!connection) continue;

		NSMutableDictionary *persistentInformation = [[NSMutableDictionary alloc] init];
		[persistentInformation addEntriesFromDictionary:[info objectForKey:@"persistentInformation"]];

		if ([info objectForKey:@"automatic"])
			[persistentInformation setObject:[info objectForKey:@"automatic"] forKey:@"automatic"];
		if ([info objectForKey:@"rooms"])
			[persistentInformation setObject:[info objectForKey:@"rooms"] forKey:@"rooms"];
		if ([info objectForKey:@"description"])
			[persistentInformation setObject:[info objectForKey:@"description"] forKey:@"description"];
		if ([info objectForKey:@"commands"] && ((NSString *)[info objectForKey:@"commands"]).length)
			[persistentInformation setObject:[[info objectForKey:@"commands"] componentsSeparatedByString:@"\n"] forKey:@"commands"];

		connection.persistentInformation = persistentInformation;

		[persistentInformation release];

		connection.proxyType = [[info objectForKey:@"proxy"] unsignedLongValue];
		connection.secure = [[info objectForKey:@"secure"] boolValue];

		if ([[info objectForKey:@"encoding"] longValue])
			connection.encoding = [[info objectForKey:@"encoding"] longValue];
		else connection.encoding = [[NSUserDefaults standardUserDefaults] integerForKey:@"JVChatEncoding"];

		if ([info objectForKey:@"realName"]) connection.realName = [info objectForKey:@"realName"];
		if ([info objectForKey:@"nickname"]) connection.nickname = [info objectForKey:@"nickname"];
		if ([info objectForKey:@"username"]) connection.username = [info objectForKey:@"username"];
		if ([info objectForKey:@"alternateNicknames"])
			connection.alternateNicknames = [info objectForKey:@"alternateNicknames"];

		NSString *password = nil;
		if ((password = [info objectForKey:@"nicknamePassword"]))
			[[CQKeychain standardKeychain] setPassword:password forServer:connection.server account:connection.preferredNickname];

		if ((password = [info objectForKey:@"password"]))
			[[CQKeychain standardKeychain] setPassword:password forServer:connection.server account:nil];

		if ((password = [[CQKeychain standardKeychain] passwordForServer:connection.server account:connection.preferredNickname]) && password.length)
			connection.nicknamePassword = password;

		if ((password = [[CQKeychain standardKeychain] passwordForServer:connection.server account:nil]) && password.length)
			connection.password = password;

		[_connections addObject:connection];

		[self _registerNotificationsForConnection:connection];

		if ([[info objectForKey:@"automatic"] boolValue])
			[connection connect];

		[connection release];
	}
}

- (void) saveConnections {
	if (!_connections.count)
		return; // we have nothing to save

	NSMutableArray *saveList = [[NSMutableArray alloc] initWithCapacity:_connections.count];

	for (MVChatConnection *connection in _connections) {
		NSMutableDictionary *info = [NSMutableDictionary dictionary];

		NSMutableDictionary *persistentInformation = [connection.persistentInformation mutableCopy];
		if ([persistentInformation objectForKey:@"automatic"])
			[info setObject:[persistentInformation objectForKey:@"automatic"] forKey:@"automatic"];
		if ([persistentInformation objectForKey:@"rooms"])
			[info setObject:[persistentInformation objectForKey:@"rooms"] forKey:@"rooms"];
		if ([persistentInformation objectForKey:@"description"])
			[info setObject:[persistentInformation objectForKey:@"description"] forKey:@"description"];
		if ([persistentInformation objectForKey:@"commands"])
			[info setObject:[[persistentInformation objectForKey:@"commands"] componentsJoinedByString:@"\n"] forKey:@"commands"];

		[persistentInformation removeObjectForKey:@"rooms"];
		[persistentInformation removeObjectForKey:@"commands"];
		[persistentInformation removeObjectForKey:@"description"];
		[persistentInformation removeObjectForKey:@"automatic"];

		if (persistentInformation.count)
			[info setObject:persistentInformation forKey:@"persistentInformation"];

		[persistentInformation release];

		[info setObject:connection.server forKey:@"server"];
		[info setObject:connection.urlScheme forKey:@"type"];
		[info setObject:[NSNumber numberWithBool:connection.secure] forKey:@"secure"];
		[info setObject:[NSNumber numberWithLong:connection.proxyType] forKey:@"proxy"];
		[info setObject:[NSNumber numberWithLong:connection.encoding] forKey:@"encoding"];
		[info setObject:[NSNumber numberWithUnsignedShort:connection.serverPort] forKey:@"port"];
		if (connection.realName) [info setObject:connection.realName forKey:@"realName"];
		if (connection.username) [info setObject:connection.username forKey:@"username"];
		if (connection.preferredNickname) [info setObject:connection.preferredNickname forKey:@"nickname"];

		if (connection.alternateNicknames.count)
			[info setObject:connection.alternateNicknames forKey:@"alternateNicknames"];

		[saveList addObject:info];
	}

	[[NSUserDefaults standardUserDefaults] setObject:saveList forKey:@"MVChatBookmarks"];
	[[NSUserDefaults standardUserDefaults] synchronize];

	[saveList release];
}

#pragma mark -

@synthesize connections = _connections;

- (NSArray *) connectedConnections {
	NSMutableArray *result = [NSMutableArray arrayWithCapacity:_connections.count];

	for (MVChatConnection *connection in _connections)
		if (connection.connected)
			[result addObject:connection];

	return result;
}

- (MVChatConnection *) connectionForServerAddress:(NSString *) address {
	NSArray *connections = [self connectionsForServerAddress:address];
	if (connections.count)
		return [connections objectAtIndex:0];
	return nil;
}

- (NSArray *) connectionsForServerAddress:(NSString *) address {
	NSMutableArray *result = [NSMutableArray arrayWithCapacity:_connections.count];

	address = [address stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@". \t\n"]];

	for (MVChatConnection *connection in _connections) {
		NSString *server = connection.server;
		NSRange range = [server rangeOfString:address options:(NSCaseInsensitiveSearch | NSLiteralSearch | NSBackwardsSearch | NSAnchoredSearch) range:NSMakeRange(0, server.length)];
		if (range.location != NSNotFound && (range.location == 0 || [server characterAtIndex:(range.location - 1)] == '.'))
			[result addObject:connection];
	}

	return result;
}

- (BOOL) managesConnection:(MVChatConnection *) connection {
	return [_connections containsObject:connection];
}

#pragma mark -

- (void) addConnection:(MVChatConnection *) connection {
	[self insertConnection:connection atIndex:_connections.count];
}

- (void) insertConnection:(MVChatConnection *) connection atIndex:(NSUInteger) index {
	if (!connection) return;

	[_connections insertObject:connection atIndex:index];

	[_connectionsViewController addConnection:connection];

	[self _registerNotificationsForConnection:connection];

	[self saveConnections];
}

- (void) moveConnection:(MVChatConnection *) connection toIndex:(NSUInteger) newIndex {
	NSUInteger oldIndex = [_connections indexOfObjectIdenticalTo:connection];
	if (oldIndex != NSNotFound)
		[self moveConnectionAtIndex:oldIndex toIndex:newIndex];
}

- (void) moveConnectionAtIndex:(NSUInteger) oldIndex toIndex:(NSUInteger) newIndex {
	MVChatConnection *connection = [[_connections objectAtIndex:oldIndex] retain];

	[_connections removeObjectAtIndex:oldIndex];
	[_connections insertObject:connection atIndex:newIndex];

	[connection release];

	[self saveConnections];
}

- (void) removeConnection:(MVChatConnection *) connection {
	NSUInteger index = [_connections indexOfObjectIdenticalTo:connection];
	if (index != NSNotFound)
		[self removeConnectionAtIndex:index];
}

- (void) removeConnectionAtIndex:(NSUInteger) index {
	MVChatConnection *connection = [[_connections objectAtIndex:index] retain];
	if (!connection) return;

	[connection disconnect];

	[_connectionsViewController removeConnection:connection];

	[self _deregisterNotificationsForConnection:connection];

	[connection release];

	[_connections removeObjectAtIndex:index];

	[self saveConnections];
}

- (void) replaceConnection:(MVChatConnection *) previousConnection withConnection:(MVChatConnection *) newConnection {
	NSUInteger index = [_connections indexOfObjectIdenticalTo:previousConnection];
	if (index != NSNotFound)
		[self replaceConnectionAtIndex:index withConnection:newConnection];
}

- (void) replaceConnectionAtIndex:(NSUInteger) index withConnection:(MVChatConnection *) connection {
	if (!connection) return;

	MVChatConnection *oldConnection = [[_connections objectAtIndex:index] retain];
	if (!oldConnection) return;

	[oldConnection disconnect];

	[_connectionsViewController removeConnection:oldConnection];

	[self _deregisterNotificationsForConnection:oldConnection];

	[oldConnection release];

	[_connections replaceObjectAtIndex:index withObject:connection];

	[_connectionsViewController addConnection:connection];

	[self _registerNotificationsForConnection:connection];

	[self saveConnections];
}
@end

#pragma mark -

@implementation MVChatConnection (CQConnectionsControllerAdditions)
- (void) setDisplayName:(NSString *) name {
	NSParameterAssert(name != nil);

	NSMutableDictionary *persistentInformation = [self.persistentInformation mutableCopy];
	[persistentInformation setObject:name forKey:@"description"];
	self.persistentInformation = persistentInformation;
	[persistentInformation release];
}

- (NSString *) displayName {
	NSString *name = [self.persistentInformation objectForKey:@"description"];
	if (!name.length)
		return self.server;
	return [self.persistentInformation objectForKey:@"description"];
}

#pragma mark -

- (void) setAutomaticJoinedRooms:(NSArray *) rooms {
	NSParameterAssert(rooms != nil);

	NSMutableDictionary *persistentInformation = [self.persistentInformation mutableCopy];
	[persistentInformation setObject:rooms forKey:@"rooms"];
	self.persistentInformation = persistentInformation;
	[persistentInformation release];
}

- (NSArray *) automaticJoinedRooms {
	return [self.persistentInformation objectForKey:@"rooms"];
}

#pragma mark -

- (void) setAutomaticCommands:(NSArray *) commands {
	NSParameterAssert(commands != nil);

	NSMutableDictionary *persistentInformation = [self.persistentInformation mutableCopy];
	[persistentInformation setObject:commands forKey:@"commands"];
	self.persistentInformation = persistentInformation;
	[persistentInformation release];
}

- (NSArray *) automaticCommands {
	return [self.persistentInformation objectForKey:@"commands"];
}

#pragma mark -

- (void) setAutomaticallyConnect:(BOOL) autoConnect {
	NSMutableDictionary *persistentInformation = [self.persistentInformation mutableCopy];
	[persistentInformation setObject:[NSNumber numberWithBool:autoConnect] forKey:@"automatic"];
	self.persistentInformation = persistentInformation;
	[persistentInformation release];
}

- (BOOL) automaticallyConnect {
	return [[self.persistentInformation objectForKey:@"automatic"] boolValue];
}
@end
