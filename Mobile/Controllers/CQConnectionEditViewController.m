#import "CQConnectionEditViewController.h"

#import "CQConnectionAdvancedEditController.h"
#import "CQConnectionsController.h"
#import "CQPreferencesTextCell.h"
#import "CQPreferencesDeleteCell.h"
#import "CQPreferencesSwitchCell.h"
#import "CQKeychain.h"

#import <ChatCore/MVChatConnection.h>

static inline NSString *currentPreferredNickname(MVChatConnection *connection) {
	NSString *preferredNickname = connection.preferredNickname;
	return ([preferredNickname isEqualToString:@"<<default>>"] ? NSUserName() : preferredNickname);
}

@implementation CQConnectionEditViewController
- (id) init {
	if (!(self = [super initWithStyle:UITableViewStyleGrouped]))
		return nil;
	return self;
}

- (void) dealloc {
	[_connection release];
	[super dealloc];
}

#pragma mark -

- (void) viewWillAppear:(BOOL) animated {
	[super viewWillAppear:animated];
	[self.tableView reloadData];
}

#pragma mark -

@synthesize newConnection = _newConnection;

- (void) setNewConnection:(BOOL)newConnection {
	if (_newConnection ==  newConnection)
		return;

	_newConnection = newConnection;
	_advancedEditViewController.newConnection = newConnection;

	if (_newConnection) self.title = NSLocalizedString(@"New Connection", @"New Connection view title");
	else self.title = _connection.server;
}

@synthesize connection = _connection;

- (void) setConnection:(MVChatConnection *) connection {
	id old = _connection;
	_connection = [connection retain];
	[old release];

	if (!_newConnection)
		self.title = connection.server;

	[self.tableView reloadData];
}

- (NSInteger) numberOfSectionsInTableView:(UITableView *) tableView {
	if (self.newConnection)
		return 3;
	return 4;
}

- (NSInteger) tableView:(UITableView *) tableView numberOfRowsInSection:(NSInteger) section {
	switch(section) {
		case 0: return 3;
		case 1: return 2;
		case 2: return 1;
		case 3: return 1;
		default: return 0;
	}
}

- (NSIndexPath *) tableView:(UITableView *) tableView willSelectRowAtIndexPath:(NSIndexPath *) indexPath {
	if (indexPath.section == 2 && indexPath.row == 0) {
		if (!_advancedEditViewController) {
			_advancedEditViewController = [[CQConnectionAdvancedEditController alloc] init];
			_advancedEditViewController.navigationItem.prompt = self.navigationItem.prompt;
			_advancedEditViewController.newConnection = _newConnection;
			_advancedEditViewController.connection = _connection;
		}

		[self.navigationController pushViewController:_advancedEditViewController animated:YES];

		return indexPath;
	}

	if (indexPath.section == 1 && indexPath.row == 1)
		return indexPath;

	return nil;
}

- (NSString *) tableView:(UITableView *) tableView titleForHeaderInSection:(NSInteger) section {
	if (section == 0)
		return NSLocalizedString(@"IRC Connection Information", @"IRC Connection Information section title");
	if (section == 1)
		return NSLocalizedString(@"Automatic Actions", @"Automatic Actions section title");
	return nil;
}

- (UITableViewCell *) tableView:(UITableView *) tableView cellForRowAtIndexPath:(NSIndexPath *) indexPath {
	if (indexPath.section == 0) {
		CQPreferencesTextCell *cell = [CQPreferencesTextCell reusableTableViewCellInTableView:tableView];
		cell.target = self;

		if (indexPath.row == 0) {
			cell.label = NSLocalizedString(@"Server", @"Server connection setting label");
			cell.text = ([_connection.server isEqualToString:@"<<placeholder>>"] ? @"" : _connection.server);
			cell.textField.placeholder = (_newConnection ? @"irc.example.com" : @"");
			cell.textField.keyboardType = UIKeyboardTypeURL;
			cell.textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
			cell.textField.autocorrectionType = UITextAutocorrectionTypeNo;
			cell.textEditAction = @selector(serverChanged:);
		} else if (indexPath.row == 1) {
			cell.label = NSLocalizedString(@"Nickname", @"Nickname connection setting label");
			cell.text = ([_connection.preferredNickname isEqualToString:@"<<default>>"] ? @"" : _connection.preferredNickname);
			cell.textField.placeholder = NSUserName();
			cell.textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
			cell.textField.autocorrectionType = UITextAutocorrectionTypeNo;
			cell.textEditAction = @selector(nicknameChanged:);
		} else if (indexPath.row == 2) {
			cell.label = NSLocalizedString(@"Real Name", @"Real Name connection setting label");
			cell.text = ([_connection.realName isEqualToString:@"<<default>>"] ? @"" : _connection.realName);
			cell.textField.placeholder = NSFullUserName();
			cell.textEditAction = @selector(realNameChanged:);
		}

		return cell;
	} else if (indexPath.section == 1) {
		if (indexPath.row == 0) {
			CQPreferencesSwitchCell *cell = [CQPreferencesSwitchCell reusableTableViewCellInTableView:tableView];

			cell.target = self;
			cell.switchAction = @selector(autoConnectChanged:);
			cell.label = NSLocalizedString(@"Connect on Launch", @"Connect on Launch connection setting label");
			cell.on = _connection.automaticallyConnect;

			return cell;
		} else if (indexPath.row == 1) {
			CQPreferencesTextCell *cell = [CQPreferencesTextCell reusableTableViewCellInTableView:tableView];

			cell.label = NSLocalizedString(@"Join Rooms", @"Join Rooms connection setting label");
			cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

			return cell;
		}
	} else if (indexPath.section == 2 && indexPath.row == 0) {
		CQPreferencesTextCell *cell = [CQPreferencesTextCell reusableTableViewCellInTableView:tableView];

		cell.label = NSLocalizedString(@"Advanced", @"Advanced connection setting label");
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

		return cell;
	} else if (indexPath.section == 3 && indexPath.row == 0) {
		CQPreferencesDeleteCell *cell = [CQPreferencesDeleteCell reusableTableViewCellInTableView:tableView];

		cell.text = NSLocalizedString(@"Delete Connection", @"Delete Connection button title");

		return cell;
	}

	NSAssert(NO, @"Should not reach this point.");
	return nil;
}

- (void) serverChanged:(CQPreferencesTextCell *) sender {
	BOOL wasPlaceholder = [_connection.server isEqualToString:@"<<placeholder>>"];

	if ([sender.text length] || _newConnection) {
		_connection.server = ([sender.text length] ? sender.text : @"<<placeholder>>");
		if (!_newConnection)
			self.title = _connection.server;
	}

	BOOL placeholder = [_connection.server isEqualToString:@"<<placeholder>>"];
	if (wasPlaceholder && !placeholder) {
		[[CQKeychain standardKeychain] setPassword:_connection.password forServer:_connection.server account:nil];
		[[CQKeychain standardKeychain] setPassword:_connection.nicknamePassword forServer:_connection.server account:currentPreferredNickname(_connection)];
	} else if (!placeholder) {
		_connection.password = [[CQKeychain standardKeychain] passwordForServer:_connection.server account:nil];
		_connection.nicknamePassword = [[CQKeychain standardKeychain] passwordForServer:_connection.server account:currentPreferredNickname(_connection)];
	} else {
		_connection.password = nil;
		_connection.nicknamePassword = nil;
	}

	if (self.navigationItem.rightBarButtonItem.tag == UIBarButtonSystemItemSave)
		self.navigationItem.rightBarButtonItem.enabled = !placeholder;

	[self.tableView reloadData];
}

- (void) nicknameChanged:(CQPreferencesTextCell *) sender {
	if ([sender.text length])
		_connection.preferredNickname = sender.text;
	else _connection.preferredNickname = (_newConnection ? @"<<default>>" : sender.textField.placeholder);

	if (![_connection.server isEqualToString:@"<<placeholder>>"])
		_connection.nicknamePassword = [[CQKeychain standardKeychain] passwordForServer:_connection.server account:currentPreferredNickname(_connection)];
	else _connection.nicknamePassword = nil;

	[self.tableView reloadData];
}

- (void) realNameChanged:(CQPreferencesTextCell *) sender {
	if ([sender.text length])
		_connection.realName = sender.text;
	else _connection.realName = (_newConnection ? @"<<default>>" : sender.textField.placeholder);

	[self.tableView reloadData];
}

- (void) autoConnectChanged:(CQPreferencesSwitchCell *) sender {
	_connection.automaticallyConnect = sender.on;
}
@end
