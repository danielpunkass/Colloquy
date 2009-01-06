//  CQWhoisViewController.m
//  Mobile Colloquy
//
//  Created by August Joki on 1/3/09.
//  Copyright 2009 Concinnous Software. All rights reserved.

#import "CQWhoisViewController.h"
#import "CQPreferencesTextCell.h"
#import "CQWhoisChannelsViewController.h"

#import <ChatCore/MVChatUser.h>
#import <ChatCore/MVChatConnection.h>

static NSString *humanReadableTimeInterval(NSTimeInterval interval, BOOL longFormat) {
	static NSDictionary *singularWords;
	if (!singularWords)
		singularWords = [[NSDictionary alloc] initWithObjectsAndKeys:NSLocalizedString(@"second", "Singular second"), [NSNumber numberWithUnsignedInt:1], NSLocalizedString(@"minute", "Singular minute"), [NSNumber numberWithUnsignedInt:60], NSLocalizedString(@"hour", "Singular hour"), [NSNumber numberWithUnsignedInt:3600], NSLocalizedString(@"day", "Singular day"), [NSNumber numberWithUnsignedInt:86400], NSLocalizedString(@"week", "Singular week"), [NSNumber numberWithUnsignedInt:604800], NSLocalizedString(@"month", "Singular month"), [NSNumber numberWithUnsignedInt:2628000], NSLocalizedString(@"year", "Singular year"), [NSNumber numberWithUnsignedInt:31536000], nil];

	static NSDictionary *pluralWords;
	if (!pluralWords)
		pluralWords = [[NSDictionary alloc] initWithObjectsAndKeys:NSLocalizedString(@"seconds", "Plural seconds"), [NSNumber numberWithUnsignedInt:1], NSLocalizedString(@"minutes", "Plural minutes"), [NSNumber numberWithUnsignedInt:60], NSLocalizedString(@"hours", "Plural hours"), [NSNumber numberWithUnsignedInt:3600], NSLocalizedString(@"days", "Plural days"), [NSNumber numberWithUnsignedInt:86400], NSLocalizedString(@"weeks", "Plural weeks"), [NSNumber numberWithUnsignedInt:604800], NSLocalizedString(@"months", "Plural months"), [NSNumber numberWithUnsignedInt:2628000], NSLocalizedString(@"years", "Plural years"), [NSNumber numberWithUnsignedInt:31536000], nil];

	static NSArray *breaks;
	if (!breaks)
		breaks = [[NSArray alloc] initWithObjects:[NSNumber numberWithUnsignedInt:1], [NSNumber numberWithUnsignedInt:60], [NSNumber numberWithUnsignedInt:3600], [NSNumber numberWithUnsignedInt:86400], [NSNumber numberWithUnsignedInt:604800], [NSNumber numberWithUnsignedInt:2628000], [NSNumber numberWithUnsignedInt:31536000], nil];

	NSTimeInterval seconds = ABS(interval);

	NSUInteger i = 0;
	while (i < [breaks count] && seconds >= [[breaks objectAtIndex:i] doubleValue]) ++i;
	if (i > 0) --i;

	float stop = [[breaks objectAtIndex:i] floatValue];
	NSUInteger value = (seconds / stop);
	NSDictionary *words = (value != 1 ? pluralWords : singularWords);

	NSMutableString *result = [NSMutableString stringWithFormat:NSLocalizedString(@"%u %@", "Time with a unit word"), value, [words objectForKey:[NSNumber numberWithUnsignedInt:stop]]];
	if (longFormat && i > 0) {
		NSUInteger remainder = ((NSUInteger)seconds % (NSUInteger)stop);
		stop = [[breaks objectAtIndex:--i] floatValue];
		remainder = (remainder / stop);
		if (remainder) {
			words = (remainder != 1 ? pluralWords : singularWords);
			[result appendFormat:NSLocalizedString(@" %u %@", "Time with a unit word, appended to a previous larger unit of time"), remainder, [words objectForKey:[breaks objectAtIndex:i]]];
		}
	}

	return result;
}

#pragma mark -

@implementation CQWhoisViewController
- (id) init {
	if (!(self = [super initWithStyle:UITableViewStyleGrouped]))
		return nil;

	UIBarButtonItem *reloadItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(refreshInformation:)];
	self.navigationItem.rightBarButtonItem = reloadItem;
	[reloadItem release];

	return self;
}

- (void) dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];

	[_user release];
	[_updateInfoTimer release];
	[_updateTimesTimer release];

	[super dealloc];
}

#pragma mark -

- (void) viewDidAppear:(BOOL) animated {
	[super viewDidAppear:animated];

	_updateTimesTimer = [[NSTimer scheduledTimerWithTimeInterval:1. target:self selector:@selector(_updateTimes) userInfo:nil repeats:YES] retain];
	_updateInfoTimer = [[NSTimer scheduledTimerWithTimeInterval:20. target:self selector:@selector(_updateInfo) userInfo:nil repeats:YES] retain];
}

- (void) viewWillDisappear:(BOOL) animated {
	[super viewWillDisappear:animated];

	[_updateTimesTimer invalidate];
	[_updateTimesTimer release];
	_updateTimesTimer = nil;

	[_updateInfoTimer invalidate];
	[_updateInfoTimer release];
	_updateInfoTimer = nil;
}

#pragma mark -

- (NSInteger) numberOfSectionsInTableView:(UITableView *) tableView {
	return 4;
}

- (NSInteger) tableView:(UITableView *) tableView numberOfRowsInSection:(NSInteger) section {
	NSInteger rows = 0;
	switch (section) {
		case 0:
			rows = 2;
			break;
		case 1:
			rows = 3;
			break;
		case 2:
			rows = 2;
			break;
		case 3:
			rows = 2;
			break;
		default:
			break;
	}
	return rows;
}

- (UITableViewCell *) tableView:(UITableView *) tableView cellForRowAtIndexPath:(NSIndexPath *) indexPath {
	CQPreferencesTextCell *cell = [CQPreferencesTextCell reusableTableViewCellInTableView:tableView];
	cell.textField.enabled = NO;

	NSInteger section = indexPath.section;
	NSInteger row = indexPath.row;

	NSString *notAvailableString = NSLocalizedString(@"n/a", "Not Applicable or Not Available");

	if (section == 0) {
		if (row == 0) { // Real Name
			cell.label = NSLocalizedString(@"Real Name", "Real Name user info label");
			cell.text = (_user.realName.length ? _user.realName : notAvailableString);
		} else if (row == 1) { // Away Info
			cell.label = NSLocalizedString(@"Away Info", "Away Info user info label");
			NSString *value = [[NSString alloc] initWithData:_user.awayStatusMessage encoding:_user.connection.encoding];
			cell.text = (value.length ? value : notAvailableString);
			[value release];
		}
	} else if (section == 1) {
		 if (row == 0) { // Class
			cell.label = NSLocalizedString(@"Class", "Class user info label");
			NSString *value = nil;
			if (_user.identified)
				value = NSLocalizedString(@"Registered user", "Registered user class");
			else if (_user.serverOperator)
				value = NSLocalizedString(@"Server operator", "Server operator class");
			else value = NSLocalizedString(@"Normal user", "Normal user class");
			cell.text = value;
		} else if (row == 1) { // Username
			cell.label = NSLocalizedString(@"Username", "Username user info label");
			cell.text = (_user.username.length ? _user.username : notAvailableString);
		} else if (row == 2) { // Hostname
			cell.label = NSLocalizedString(@"Hostname", "Hostname user info label");
			cell.text = (_user.address.length ? _user.address : notAvailableString);
		}
	} else if (section == 2) {
		if (row == 0) { // Server
			cell.label = NSLocalizedString(@"Server", "Server user info label");
			cell.text = (_user.serverAddress) ? _user.serverAddress : notAvailableString;
		} else if (row == 1) { // Rooms
			cell.label = NSLocalizedString(@"Rooms", "Rooms user info label");
			NSString *rooms = [[_user attributeForKey:MVChatUserKnownRoomsAttribute] componentsJoinedByString:NSLocalizedString(@", ", "User info rooms list separator")];
			cell.text = (rooms.length ? rooms : notAvailableString);
			if (rooms.length) {
				cell.accessoryType = UITableViewCellAccessoryDetailDisclosureButton;
				cell.accessoryAction = @selector(showJoinedRooms:);
				cell.target = self;
			}
		}
	} else if (section == 3) {
		if (row == 0) { // Connected
			cell.label = NSLocalizedString(@"Connected", "Connected user info label");
			cell.text = (_user.status != MVChatUserOfflineStatus && _user.dateConnected ? humanReadableTimeInterval([_user.dateConnected timeIntervalSinceNow], YES) : NSLocalizedString(@"Offline", "Offline label"));
		} else if (row == 1) { // Idle Time
			cell.label = NSLocalizedString(@"Idle Time", "Idle Time user info label");
			cell.text = (_user.status != MVChatUserOfflineStatus ? humanReadableTimeInterval([NSDate timeIntervalSinceReferenceDate] - _idleTimeStart, YES) : NSLocalizedString(@"Offline", "Offline label"));
		}
	}

	return cell;
}

#pragma mark -

- (IBAction) showJoinedRooms:(id) sender {
	CQWhoisChannelsViewController *roomsController = [[CQWhoisChannelsViewController alloc] init];
	roomsController.rooms = [_user attributeForKey:MVChatUserKnownRoomsAttribute];
	roomsController.connection = _user.connection;

	[self.navigationController pushViewController:roomsController animated:YES];

	[roomsController release];
}

- (IBAction) refreshInformation:(id) sender {
	[_user refreshInformation];
}

#pragma mark -

- (void) _informationUpdated:(NSNotification *) notification {
	self.navigationItem.title = _user.nickname;

	_idleTimeStart = ([NSDate timeIntervalSinceReferenceDate] - _user.idleTime);

	[self.tableView reloadData];
}

- (void) _idleTimeUpdated:(NSNotification *) notification {
	_idleTimeStart = ([NSDate timeIntervalSinceReferenceDate] - _user.idleTime);
}

- (void) _updateInfo {
	if (!_user.serverOperator)
		[_user refreshInformation];
}

- (void) _updateTimes {
	// Connected time
	NSIndexPath *indexPath = [NSIndexPath indexPathForRow:0 inSection:3];
	UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
	if (cell) cell.text = (_user.status != MVChatUserOfflineStatus && _user.dateConnected ? humanReadableTimeInterval([_user.dateConnected timeIntervalSinceNow], YES) : NSLocalizedString(@"Offline", "Offline label"));

	// Idle time
	indexPath = [NSIndexPath indexPathForRow:1 inSection:3];
	cell = [self.tableView cellForRowAtIndexPath:indexPath];
	if (cell) cell.text = (_user.status != MVChatUserOfflineStatus ? humanReadableTimeInterval([NSDate timeIntervalSinceReferenceDate] - _idleTimeStart, YES) : NSLocalizedString(@"Offline", "Offline label"));
}

#pragma mark -

@synthesize user = _user;

- (void) setUser:(MVChatUser *) user {
	[[NSNotificationCenter defaultCenter] removeObserver:self name:MVChatUserAttributeUpdatedNotification object:_user];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:MVChatUserInformationUpdatedNotification object:_user];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:MVChatUserNicknameChangedNotification object:_user];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:MVChatUserStatusChangedNotification object:_user];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:MVChatUserAwayStatusMessageChangedNotification object:_user];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:MVChatUserIdleTimeUpdatedNotification object:_user];

	id old = _user;
	_user = [user retain];
	[old release];

	[_user refreshInformation];

	if (_user) {
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_informationUpdated:) name:MVChatUserAttributeUpdatedNotification object:_user];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_informationUpdated:) name:MVChatUserInformationUpdatedNotification object:_user];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_informationUpdated:) name:MVChatUserNicknameChangedNotification object:_user];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_informationUpdated:) name:MVChatUserStatusChangedNotification object:_user];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_informationUpdated:) name:MVChatUserAwayStatusMessageChangedNotification object:_user];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_idleTimeUpdated:) name:MVChatUserIdleTimeUpdatedNotification object:_user];
	}

	self.navigationItem.title = _user.nickname;

	[self.tableView reloadData];
}
@end
