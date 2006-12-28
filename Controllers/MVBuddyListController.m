#import "MVBuddyListController.h"
#import "JVBuddy.h"
#import "JVChatController.h"
#import "MVConnectionsController.h"
#import "MVFileTransferController.h"
#import "JVNotificationController.h"
#import "JVInspectorController.h"
#import "MVTableView.h"
#import "JVDetailCell.h"

static MVBuddyListController *sharedInstance = nil;

@interface MVBuddyListController (MVBuddyListControllerPrivate)
- (void) _loadBuddyList;
- (void) _sortBuddies;
- (void) _manuallySortAndUpdate;
- (void) _setBuddiesNeedSortAnimated;
- (void) _sortBuddiesAnimated:(id) sender;
@end

#pragma mark -

@implementation MVBuddyListController
+ (MVBuddyListController *) sharedBuddyList {
	return ( sharedInstance ? sharedInstance : ( sharedInstance = [[self alloc] initWithWindowNibName:nil] ) );
}

#pragma mark -

- (id) initWithWindowNibName:(NSString *) windowNibName {
	if( ( self = [super initWithWindowNibName:@"MVBuddyList"] ) ) {
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector( _buddyOnline: ) name:JVBuddyCameOnlineNotification object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector( _buddyOffline: ) name:JVBuddyWentOfflineNotification object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector( _buddyChanged: ) name:JVBuddyUserCameOnlineNotification object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector( _buddyChanged: ) name:JVBuddyUserWentOfflineNotification object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector( _buddyChanged: ) name:JVBuddyActiveUserChangedNotification object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector( _buddyChanged: ) name:JVBuddyUserStatusChangedNotification object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector( _buddyChanged: ) name:JVBuddyUserIdleTimeUpdatedNotification object:nil];

		_onlineBuddies = [[NSMutableSet allocWithZone:nil] initWithCapacity:20];
		_buddyList = [[NSMutableSet allocWithZone:nil] initWithCapacity:40];
		_buddyOrder = [[NSMutableArray allocWithZone:nil] initWithCapacity:40];

		[self _loadBuddyList];

		[JVBuddy setPreferredName:[[NSUserDefaults standardUserDefaults] integerForKey:@"JVChatBuddyNameStyle"]];

		[self setShowIcons:[[NSUserDefaults standardUserDefaults] boolForKey:@"JVChatBuddyListShowIcons"]];
		[self setShowFullNames:[[NSUserDefaults standardUserDefaults] boolForKey:@"JVChatBuddyListShowFullNames"]];
		[self setShowNicknameAndServer:[[NSUserDefaults standardUserDefaults] boolForKey:@"JVChatBuddyListShowNicknameAndServer"]];
		[self setShowOfflineBuddies:[[NSUserDefaults standardUserDefaults] boolForKey:@"JVChatBuddyListShowOfflineBuddies"]];
		[self setSortOrder:[[NSUserDefaults standardUserDefaults] integerForKey:@"JVChatBuddyListSortOrder"]];
	}

	return self;
}

- (void) release {
	if( ( [self retainCount] - 1 ) == 1 )
		[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector( _sortBuddiesAnimated: ) object:nil];
	[super release];
}

- (void) dealloc {
	[self save];

	[[NSNotificationCenter defaultCenter] removeObserver:self];
	if( self == sharedInstance ) sharedInstance = nil;

	[_onlineBuddies release];
	[_buddyList release];
	[_buddyOrder release];
	[_oldPositions release];
	[_addPerson release];
	[_addServers release];

	_onlineBuddies = nil;
	_buddyList = nil;
	_buddyOrder = nil;
	_oldPositions = nil;
	_addPerson = nil;
	_addServers = nil;

	[super dealloc];
}

- (void) windowDidLoad {
	NSTableColumn *theColumn = nil;

	[(NSPanel *)[self window] setFloatingPanel:NO];
	[(NSPanel *)[self window] setHidesOnDeactivate:NO];
	[[self window] setFrameAutosaveName:@"buddylist"];

	[buddies setVerticalMotionCanBeginDrag:NO];
	[buddies setTarget:self];
	[buddies setDoubleAction:@selector( messageSelectedBuddy: )];

	theColumn = [buddies tableColumnWithIdentifier:@"buddy"];
	JVDetailCell *prototypeCell = [[JVDetailCell new] autorelease];
	[prototypeCell setFont:[NSFont systemFontOfSize:11.]];
	[theColumn setDataCell:prototypeCell];

	[pickerView addProperty:kABNicknameProperty];
	[pickerView addProperty:kABAIMInstantProperty];
	[pickerView addProperty:kABJabberInstantProperty];
	[pickerView addProperty:kABMSNInstantProperty];
	[pickerView addProperty:kABYahooInstantProperty];
	[pickerView addProperty:kABICQInstantProperty];
	[pickerView addProperty:kABEmailProperty];

	[pickerView setAllowsMultipleSelection:NO];
	[pickerView setAllowsGroupSelection:NO];
	[pickerView setTarget:self];
	[pickerView setNameDoubleAction:@selector( confirmBuddySelection: )];

	[buddies registerForDraggedTypes:[NSArray arrayWithObject:NSFilenamesPboardType]];

	if( _showIcons || _showNicknameAndServer ) [buddies setRowHeight:36.];
	else [buddies setRowHeight:18.];

	[buddies reloadData];
	[self _setBuddiesNeedSortAnimated];
}

#pragma mark -

- (void) save {
	NSMutableArray *list = [[NSMutableArray allocWithZone:nil] initWithCapacity:[_buddyList count]];
	NSEnumerator *enumerator = [_buddyList objectEnumerator];
	JVBuddy *buddy = nil;

	while( ( buddy = [enumerator nextObject] ) ) {
		NSDictionary *buddyRep = [buddy dictionaryRepresentation];
		if( buddyRep ) [list addObject:buddyRep];
	}

	[list writeToFile:[@"~/Library/Application Support/Colloquy/Buddy List.plist" stringByExpandingTildeInPath] atomically:YES];
	[list release];
}

#pragma mark -

- (id <JVInspection>) objectToInspect {
	if( [buddies selectedRow] == -1 ) return nil;
	id item = [_buddyOrder objectAtIndex:[buddies selectedRow]];
	if( [item conformsToProtocol:@protocol( JVInspection )] ) return item;
	else return nil;
}

- (IBAction) getInfo:(id) sender {
	if( [buddies selectedRow] == -1 ) return;
	id item = [_buddyOrder objectAtIndex:[buddies selectedRow]];
	if( [item conformsToProtocol:@protocol( JVInspection )] )
		[[JVInspectorController inspectorOfObject:item] show:sender];
}

#pragma mark -

- (IBAction) showBuddyList:(id) sender {
	[[self window] makeKeyAndOrderFront:nil];
}

- (IBAction) hideBuddyList:(id) sender {
	[[self window] orderOut:nil];
}

#pragma mark -

- (void) addBuddy:(JVBuddy *) buddy {
	[_buddyList addObject:buddy];
	if( _showOfflineBuddies && ! [_buddyOrder containsObject:buddy] ) {
		[_buddyOrder addObject:buddy];
		[self _manuallySortAndUpdate];
	}

	[buddy registerWithApplicableConnections];
}

#pragma mark -

- (JVBuddy *) buddyForUser:(MVChatUser *) user {
	NSEnumerator *enumerator = [_onlineBuddies objectEnumerator];
	JVBuddy *buddy = nil;

	while( ( buddy = [enumerator nextObject] ) )
		if( [[buddy users] containsObject:user] )
			return buddy;

	return nil;
}

- (NSArray *) buddies {
	return _buddyOrder;
}

- (NSSet *) onlineBuddies {
	return _onlineBuddies;
}

#pragma mark -

- (IBAction) showBuddyPickerSheet:(id) sender {
	[self showBuddyList:nil];

	if( [[self window] attachedSheet] ) {
		[[NSApplication sharedApplication] endSheet:[[self window] attachedSheet]];
		[[[self window] attachedSheet] orderOut:nil];
	}

	[_addPerson release];
	_addPerson = nil;

	[[NSApplication sharedApplication] beginSheet:pickerWindow modalForWindow:[self window] modalDelegate:nil didEndSelector:NULL contextInfo:NULL];
}

- (IBAction) cancelBuddySelection:(id) sender {
	if( [[self window] attachedSheet] ) {
		[[NSApplication sharedApplication] endSheet:[[self window] attachedSheet]];
		[[[self window] attachedSheet] orderOut:nil];
	}
}

- (IBAction) confirmBuddySelection:(id) sender {
	if( [[self window] attachedSheet] ) {
		[[NSApplication sharedApplication] endSheet:[[self window] attachedSheet]];
		[[[self window] attachedSheet] orderOut:nil];
	}

	ABPerson *person = [[pickerView selectedRecords] lastObject];
	[_addPerson release];
	_addPerson = [[person uniqueId] copy];

	[self showNewPersonSheet:nil];
}

#pragma mark -

- (IBAction) showNewPersonSheet:(id) sender {
	if( [[self window] attachedSheet] ) {
		[[NSApplication sharedApplication] endSheet:[[self window] attachedSheet]];
		[[[self window] attachedSheet] orderOut:nil];
	}

	[_addServers release];
	_addServers = [[NSMutableSet allocWithZone:nil] init];

	[servers reloadData];

	if( _addPerson ) {
		ABPerson *person = (ABPerson *)[[ABAddressBook sharedAddressBook] recordForUniqueId:_addPerson];
		if( person ) {
			[nickname setObjectValue:[person valueForProperty:kABNicknameProperty]];
			[firstName setObjectValue:[person valueForProperty:kABFirstNameProperty]];
			[lastName setObjectValue:[person valueForProperty:kABLastNameProperty]];

			ABMultiValue *value = [person valueForProperty:kABEmailProperty];
			unsigned index = [value indexForIdentifier:[value primaryIdentifier]];
			if( index != NSNotFound ) [email setObjectValue:[value valueAtIndex:index]];

			[image setImage:[[[NSImage alloc] initWithData:[person imageData]] autorelease]];
		}
	} else {
		[nickname setObjectValue:@""];
		[firstName setObjectValue:@""];
		[lastName setObjectValue:@""];
		[email setObjectValue:@""];
		[image setImage:nil];
	}

	if( [[nickname stringValue] length] && [_addServers count] )
		[addButton setEnabled:YES];
	else [addButton setEnabled:NO];

	[[NSApplication sharedApplication] beginSheet:newPersonWindow modalForWindow:[self window] modalDelegate:nil didEndSelector:NULL contextInfo:NULL];
}

- (IBAction) cancelNewBuddy:(id) sender {
	if( [[self window] attachedSheet] ) {
		[[NSApplication sharedApplication] endSheet:[[self window] attachedSheet]];
		[[[self window] attachedSheet] orderOut:nil];
	}

	[_addPerson release];
	_addPerson = nil;

	[_addServers release];
	_addServers = nil;
}

- (IBAction) confirmNewBuddy:(id) sender {
	if( [[self window] attachedSheet] ) {
		[[NSApplication sharedApplication] endSheet:[[self window] attachedSheet]];
		[[[self window] attachedSheet] orderOut:nil];
	}

	JVBuddy *buddy = [[JVBuddy allocWithZone:nil] init];

	[buddy setGivenNickname:[nickname stringValue]];
	[buddy setFirstName:[firstName stringValue]];
	[buddy setLastName:[lastName stringValue]];
	[buddy setPrimaryEmail:[email stringValue]];
	[buddy setPicture:[image image]];

	if( _addPerson ) {
		ABPerson *person = (ABPerson *)[[ABAddressBook sharedAddressBook] recordForUniqueId:_addPerson];
		if( person ) [buddy setAddressBookPersonRecord:person];
	}

	MVChatUserWatchRule *rule = [[MVChatUserWatchRule allocWithZone:nil] init];
	[rule setNickname:[nickname stringValue]];

	NSMutableArray *newServers = [[NSMutableArray allocWithZone:nil] initWithCapacity:[_addServers count]];
	NSEnumerator *enumerator = [_addServers objectEnumerator];
	NSString *server = nil;

	while( ( server = [enumerator nextObject] ) ) {
		unsigned int ip = 0;
		BOOL ipAddress = ( sscanf( [server UTF8String], "%u.%u.%u.%u", &ip, &ip, &ip, &ip ) == 4 );

		if( ! ipAddress ) {
			NSArray *parts = [server componentsSeparatedByString:@"."];
			unsigned count = [parts count];
			if( count > 2 )
				server = [NSString stringWithFormat:@"%@.%@", [parts objectAtIndex:(count - 2)], [parts objectAtIndex:(count - 1)]];
		}

		[newServers addObject:server];
	}

	[rule setApplicableServerDomains:newServers];
	[newServers release];

	[buddy addWatchRule:rule];

	[self addBuddy:buddy];
	[self save];

	[_addPerson release];
	_addPerson = nil;

	[_addServers release];
	_addServers = nil;
}

- (void) controlTextDidChange:(NSNotification *) notification {
	if( [[nickname stringValue] length] && [_addServers count] )
		[addButton setEnabled:YES];
	else [addButton setEnabled:NO];
}

#pragma mark -

- (void) setNewBuddyNickname:(NSString *) nick {
	[nickname setObjectValue:nick];

	if( [nick length] >= 1 ) [addButton setEnabled:YES];
	else [addButton setEnabled:NO];
}

- (void) setNewBuddyFullname:(NSString *) name {
	NSRange range = [name rangeOfString:@" "];
	if( range.location != NSNotFound ) {
		[firstName setObjectValue:[name substringToIndex:range.location]];
		if( ( range.location + 1 ) < [name length] ) {
			[lastName setObjectValue:[name substringFromIndex:( range.location + 1 )]];
		} else [lastName setObjectValue:@""];
	} else {
		[firstName setObjectValue:@""];
		[lastName setObjectValue:@""];
	}
}

- (void) setNewBuddyServer:(MVChatConnection *) connection {
	
}

#pragma mark -

- (IBAction) messageSelectedBuddy:(id) sender {
	if( [buddies selectedRow] == -1 ) return;
	JVBuddy *buddy = [_buddyOrder objectAtIndex:[buddies selectedRow]];
	MVChatUser *user = [buddy activeUser];
	if( [user type] != MVChatRemoteUserType ) return;
	[[JVChatController defaultController] chatViewControllerForUser:user ifExists:NO];
}

- (IBAction) sendFileToSelectedBuddy:(id) sender {
	if( [buddies selectedRow] == -1 ) return;
	BOOL passive = [[NSUserDefaults standardUserDefaults] boolForKey:@"JVSendFilesPassively"];
	JVBuddy *buddy = [_buddyOrder objectAtIndex:[buddies selectedRow]];
	MVChatUser *user = [buddy activeUser];
	if( [user type] != MVChatRemoteUserType ) return;

	NSOpenPanel *panel = [NSOpenPanel openPanel];
	[panel setResolvesAliases:YES];
	[panel setCanChooseFiles:YES];
	[panel setCanChooseDirectories:NO];
	[panel setAllowsMultipleSelection:YES];

	NSView *view = [[NSView alloc] initWithFrame:NSMakeRect( 0., 0., 200., 28. )];
	[view setAutoresizingMask:( NSViewWidthSizable | NSViewMaxXMargin )];

	NSButton *passiveButton = [[NSButton alloc] initWithFrame:NSMakeRect( 0., 6., 200., 18. )];
	[[passiveButton cell] setButtonType:NSSwitchButton];
	[passiveButton setState:passive];
	[passiveButton setTitle:NSLocalizedString( @"Send File Passively", "send files passively file send open dialog button" )];
	[passiveButton sizeToFit];

	NSRect frame = [view frame];
	frame.size.width = NSWidth( [passiveButton frame] );

	[view setFrame:frame];
	[view addSubview:passiveButton];
	[passiveButton release];

	[panel setAccessoryView:view];
	[view release];

	if( [panel runModalForTypes:nil] == NSOKButton ) {
		NSEnumerator *enumerator = [[panel filenames] objectEnumerator];
		passive = [passiveButton state];
		NSString *path = nil;
		while( ( path = [enumerator nextObject] ) )
			[[MVFileTransferController defaultController] addFileTransfer:[user sendFile:path passively:passive]];
	}
}

#pragma mark -

- (void) setShowFullNames:(BOOL) flag {
	_showFullNames = flag;
	[buddies reloadData];
	[self _sortBuddiesAnimated:nil];
	[[NSUserDefaults standardUserDefaults] setBool:flag forKey:@"JVChatBuddyListShowFullNames"];
	[[NSUserDefaults standardUserDefaults] synchronize];
}

- (BOOL) showFullNames {
	return _showFullNames;
}

- (IBAction) toggleShowFullNames:(id) sender {
	[self setShowFullNames:(! _showFullNames)];
}

#pragma mark -

- (void) setShowNicknameAndServer:(BOOL) flag {
	_showNicknameAndServer = flag;
	if( _showIcons || _showNicknameAndServer ) [buddies setRowHeight:36.];
	else [buddies setRowHeight:18.];
	[buddies reloadData];
	[[NSUserDefaults standardUserDefaults] setBool:flag forKey:@"JVChatBuddyListShowNicknameAndServer"];
	[[NSUserDefaults standardUserDefaults] synchronize];
}

- (BOOL) showNicknameAndServer {
	return _showNicknameAndServer;
}

- (IBAction) toggleShowNicknameAndServer:(id) sender {
	[self setShowNicknameAndServer:(! _showNicknameAndServer)];
}

#pragma mark -

- (void) setShowIcons:(BOOL) flag {
	_showIcons = flag;
	if( _showIcons || _showNicknameAndServer ) [buddies setRowHeight:36.];
	else [buddies setRowHeight:18.];
	[buddies reloadData];
	[[NSUserDefaults standardUserDefaults] setBool:flag forKey:@"JVChatBuddyListShowIcons"];
	[[NSUserDefaults standardUserDefaults] synchronize];
}

- (BOOL) showIcons {
	return _showIcons;
}

- (IBAction) toggleShowIcons:(id) sender {
	[self setShowIcons:(! _showIcons)];
}

#pragma mark -

- (void) setShowOfflineBuddies:(BOOL) flag {
	_showOfflineBuddies = flag;
	NSMutableSet *offlineBuddies = [NSMutableSet setWithSet:_buddyList];
	[offlineBuddies minusSet:_onlineBuddies];
	if( ! _showOfflineBuddies ) [_buddyOrder removeObjectsInArray:[offlineBuddies allObjects]];
	else [_buddyOrder addObjectsFromArray:[offlineBuddies allObjects]];
	[self _manuallySortAndUpdate];
	[[NSUserDefaults standardUserDefaults] setBool:flag forKey:@"JVChatBuddyListShowOfflineBuddies"];
	[[NSUserDefaults standardUserDefaults] synchronize];
}

- (BOOL) showOfflineBuddies {
	return _showOfflineBuddies;
}

- (IBAction) toggleShowOfflineBuddies:(id) sender {
	[self setShowOfflineBuddies:(! _showOfflineBuddies)];
}

#pragma mark -

- (void) setSortOrder:(MVBuddyListSortOrder) order {
	_sortOrder = order;
	[self _sortBuddiesAnimated:nil];
	[[NSUserDefaults standardUserDefaults] setInteger:order forKey:@"JVChatBuddyListSortOrder"];
	[[NSUserDefaults standardUserDefaults] synchronize];
}

- (MVBuddyListSortOrder) sortOrder {
	return _sortOrder;
}

- (IBAction) sortByAvailability:(id) sender {
	[self setSortOrder:MVAvailabilitySortOrder];
}

- (IBAction) sortByFirstName:(id) sender {
	[self setSortOrder:MVFirstNameSortOrder];
}

- (IBAction) sortByLastName:(id) sender {
	[self setSortOrder:MVLastNameSortOrder];
}

- (IBAction) sortByServer:(id) sender {
	[self setSortOrder:MVServerSortOrder];
}

#pragma mark -

- (BOOL) validateMenuItem:(NSMenuItem *) menuItem {
	if( [menuItem action] == @selector( toggleShowFullNames: ) ) {
		[menuItem setState:( _showFullNames ? NSOnState : NSOffState )];
		return YES;
	} else if( [menuItem action] == @selector( toggleShowNicknameAndServer: ) ) {
		[menuItem setState:( _showNicknameAndServer ? NSOnState : NSOffState )];
		return YES;
	} else if( [menuItem action] == @selector( toggleShowIcons: ) ) {
		[menuItem setState:( _showIcons ? NSOnState : NSOffState )];
		return YES;
	} else if( [menuItem action] == @selector( toggleShowOfflineBuddies: ) ) {
		[menuItem setState:( _showOfflineBuddies ? NSOnState : NSOffState )];
		return YES;
	} else if( [menuItem action] == @selector( messageSelectedBuddy: ) ) {
		if( [buddies selectedRow] == -1 ) return NO;
		else return YES;
	} else if( [menuItem action] == @selector( sendFileToSelectedBuddy: ) ) {
		if( [buddies selectedRow] == -1 ) return NO;
		else return YES;
	} else if( [menuItem action] == @selector( getInfo: ) ) {
		if( [buddies selectedRow] == -1 ) return NO;
		else return YES;
	} else if( [menuItem action] == @selector( sortByAvailability: ) ) {
		[menuItem setState:( _sortOrder == MVAvailabilitySortOrder || ! _sortOrder ? NSOnState : NSOffState )];
		return YES;
	} else if( [menuItem action] == @selector( sortByFirstName: ) ) {
		[menuItem setState:( _sortOrder == MVFirstNameSortOrder ? NSOnState : NSOffState )];
		return YES;
	} else if( [menuItem action] == @selector( sortByLastName: ) ) {
		[menuItem setState:( _sortOrder == MVLastNameSortOrder ? NSOnState : NSOffState )];
		return YES;
	} else if( [menuItem action] == @selector( sortByServer: ) ) {
		[menuItem setState:( _sortOrder == MVServerSortOrder ? NSOnState : NSOffState )];
		return YES;
	}
	return YES;
}
@end

#pragma mark -

@implementation MVBuddyListController (MVBuddyListControllerDelegate)
- (void) clear:(id) sender {
	if( [buddies selectedRow] == -1 ) return;
	JVBuddy *buddy = [[_buddyOrder objectAtIndex:[buddies selectedRow]] retain];
	[_buddyList removeObject:buddy];
	[_onlineBuddies removeObject:buddy];
	[_buddyOrder removeObjectIdenticalTo:buddy];
	[buddy release];
	[self _manuallySortAndUpdate];
	[self save];
}

- (int) numberOfRowsInTableView:(NSTableView *) view {
	if( view == servers )
		return [[[MVConnectionsController defaultController] connections] count];

	if( view == buddies )
		return [_buddyOrder count];

	return 0;
}

- (id) tableView:(NSTableView *) view objectValueForTableColumn:(NSTableColumn *) column row:(int) row {
	if( view == servers ) {
		MVChatConnection *connection = [[[MVConnectionsController defaultController] connections] objectAtIndex:row];
		if( [[column identifier] isEqualToString:@"domain"] )
			return [connection server];
		return nil;
	}

	if( view != buddies || row == -1 || row >= (int)[_buddyOrder count] )
		return nil;

	if( [[column identifier] isEqualToString:@"buddy"] ) {
		if( _showIcons ) {
			JVBuddy *buddy = [_buddyOrder objectAtIndex:row];
			NSImage *ret = [buddy picture];
			if( ! ret ) ret = [[[NSImage imageNamed:@"largePerson"] copy] autorelease];
			if( [ret size].width > 32 || [ret size].height > 32 ) {
				[ret setScalesWhenResized:YES];
				[ret setSize:NSMakeSize( 32., 32. )];
			}

			return ret;
		}
	}

	return nil;
}

- (void) tableView:(NSTableView *) view willDisplayCell:(id) cell forTableColumn:(NSTableColumn *) column row:(int) row {
	if( view == servers ) {
		MVChatConnection *connection = [[[MVConnectionsController defaultController] connections] objectAtIndex:row];
		if( [[column identifier] isEqualToString:@"check"] )
			[cell setState:( [_addServers containsObject:[connection server]] )];
		return;
	}

	if( view != buddies || row == -1 || row >= (int)[_buddyOrder count] )
		return;

	if( [[column identifier] isEqualToString:@"buddy"] ) {
		JVBuddy *buddy = [_buddyOrder objectAtIndex:row];
		MVChatUser *user = [buddy activeUser];

		if( user && ( ! _showFullNames || ! [[buddy compositeName] length] ) ) {
			[cell setMainText:[user nickname]];
			if( _showNicknameAndServer ) [cell setInformationText:[user serverAddress]];
			else [cell setInformationText:nil];
		} else {
			[cell setMainText:[buddy compositeName]];
			if( user && _showNicknameAndServer ) [cell setInformationText:[NSString stringWithFormat:@"%@ (%@)", [user nickname], [user serverAddress]]];
			else [cell setInformationText:nil];
		}

		[cell setEnabled:( [user status] == MVChatUserAvailableStatus || [user status] == MVChatUserAwayStatus )];

		switch( [buddy status] ) {
		case MVChatUserAwayStatus:
			[cell setStatusImage:[NSImage imageNamed:@"statusAway"]];
			break;
		case MVChatUserAvailableStatus:
			if( [buddy idleTime] >= 600. ) [cell setStatusImage:[NSImage imageNamed:@"statusIdle"]];
			else [cell setStatusImage:[NSImage imageNamed:@"statusAvailable"]];
			break;
		default:
			[cell setStatusImage:[NSImage imageNamed:@"statusOffline"]];
		}
	} else if( [[column identifier] isEqualToString:@"switch"] ) {
		JVBuddy *buddy = [_buddyOrder objectAtIndex:row];
		NSSet *users = [buddy users];

		if( [users count] >= 2 ) {
			NSMutableArray *ordered = [[users allObjects] mutableCopyWithZone:nil];
			[ordered sortUsingSelector:@selector( compareByNickname: )];

			NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];
			[menu setAutoenablesItems:NO];

			NSEnumerator *userEnumerator = [ordered objectEnumerator];
			MVChatUser *activeUser = [buddy activeUser];
			NSMenuItem *item = nil;
			MVChatUser *user = nil;

			while( ( user = [userEnumerator nextObject] ) ) {
				item = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"%@ (%@)", [user nickname], [user serverAddress]] action:NULL keyEquivalent:@""];
				if( [user isEqualToChatUser:activeUser] ) [item setState:NSOnState];
				[menu addItem:item];
				[item release];
			}

			[ordered release];

			[cell setMenu:menu];
			[menu release];

			[cell setArrowPosition:NSPopUpArrowAtCenter];
			[cell setEnabled:YES];

			if( _showIcons || _showNicknameAndServer ) [cell setControlSize:NSRegularControlSize];
			else [cell setControlSize:NSSmallControlSize];
		} else {
			[cell setArrowPosition:NSPopUpNoArrow];
			[cell setEnabled:NO];
		}
	}
}

- (void) tableView:(NSTableView *) tableView setObjectValue:(id) object forTableColumn:(NSTableColumn *) tableColumn row:(int) row {
	if( tableView == servers ) {
		if( [[tableColumn identifier] isEqualToString:@"check"] ) {
			if( [object isKindOfClass:[NSNumber class]] ) {
				MVChatConnection *connection = [[[MVConnectionsController defaultController] connections] objectAtIndex:row];
				if( [object boolValue] ) [_addServers addObject:[connection server]];
				else [_addServers removeObject:[connection server]];

				if( [[nickname stringValue] length] && [_addServers count] )
					[addButton setEnabled:YES];
				else [addButton setEnabled:NO];
			}
		}

		return;
	}

	if( tableView != buddies || row == -1 || row >= (int)[_buddyOrder count] )
		return;

	JVBuddy *buddy = [_buddyOrder objectAtIndex:row];
	NSSet *users = [buddy users];

	NSMutableArray *ordered = [[users allObjects] mutableCopyWithZone:nil];
	[ordered sortUsingSelector:@selector( compareByNickname: )];

	[buddy setActiveUser:[ordered objectAtIndex:[object unsignedIntValue]]];

	[ordered release];

	[buddies reloadData];
	[self _sortBuddiesAnimated:nil];
}

- (NSMenu *) tableView:(MVTableView *) tableView menuForTableColumn:(NSTableColumn *) tableColumn row:(int) row {
	if( tableView != buddies ) return nil;

	NSMenu *menu = [actionMenu copyWithZone:[self zone]];
	JVBuddy *buddy = [_buddyOrder objectAtIndex:row];

	NSMethodSignature *signature = [NSMethodSignature methodSignatureWithReturnAndArgumentTypes:@encode( NSArray * ), @encode( id ), @encode( id ), nil];
	NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
	id view = nil;

	[invocation setSelector:@selector( contextualMenuItemsForObject:inView: )];
	[invocation setArgument:&buddy atIndex:2];
	[invocation setArgument:&view atIndex:3];

	NSArray *results = [[MVChatPluginManager defaultManager] makePluginsPerformInvocation:invocation];
	if( [results count] ) {
		[menu addItem:[NSMenuItem separatorItem]];

		NSArray *items = nil;
		NSMenuItem *item = nil;
		NSEnumerator *enumerator = [results objectEnumerator];
		while( ( items = [enumerator nextObject] ) ) {
			if( ! [items respondsToSelector:@selector( objectEnumerator )] ) continue;
			NSEnumerator *ienumerator = [items objectEnumerator];
			while( ( item = [ienumerator nextObject] ) )
				if( [item isKindOfClass:[NSMenuItem class]] ) [menu addItem:item];
		}

		if( [[[menu itemArray] lastObject] isSeparatorItem] )
			[menu removeItem:[[menu itemArray] lastObject]];
	}

	return [menu autorelease];
}

- (NSString *) tableView:(MVTableView *) tableView toolTipForTableColumn:(NSTableColumn *) column row:(int) row {
	if( tableView != buddies || row == -1 || row >= (int)[_buddyOrder count] ) return nil;

	NSMutableString *ret = [NSMutableString string];
	JVBuddy *buddy = [_buddyOrder objectAtIndex:row];
	MVChatUser *user = [buddy activeUser];

	[ret appendFormat:@"%@\n", [buddy compositeName]];
	[ret appendFormat:@"%@ (%@)\n", [user nickname], [user serverAddress]];

	switch( [buddy status] ) {
	case MVChatUserAwayStatus:
		[ret appendString:NSLocalizedString( @"Away", "away buddy status" )];
		break;
	case MVChatUserAvailableStatus:
		if( [buddy idleTime] >= 600. ) [ret appendString:NSLocalizedString( @"Idle", "idle buddy status" )];
		else [ret appendString:NSLocalizedString( @"Available", "available buddy status" )];
		break;
	default:
		[ret appendString:NSLocalizedString( @"Offline", "offline buddy status" )];
	}

	return ret;
}

- (void) tableViewSelectionDidChange:(NSNotification *) notification {
	if( [notification object] != buddies ) return;

	BOOL enabled = ! ( [buddies selectedRow] == -1 );
	[sendMessageButton setEnabled:enabled];
	[infoButton setEnabled:enabled];
	[[JVInspectorController sharedInspector] inspectObject:[self objectToInspect]];
}

- (NSDragOperation) tableView:(NSTableView *) tableView validateDrop:(id <NSDraggingInfo>) info proposedRow:(int) row proposedDropOperation:(NSTableViewDropOperation) operation {
	if( tableView != buddies ) return NSDragOperationNone;

	if( operation == NSTableViewDropOn && row != -1 )
		return NSDragOperationMove;
	return NSDragOperationNone;
}

- (BOOL) tableView:(NSTableView *) tableView acceptDrop:(id <NSDraggingInfo>) info row:(int) row dropOperation:(NSTableViewDropOperation) operation {
	if( tableView != buddies ) return NO;

	NSPasteboard *board = [info draggingPasteboard];
	if( [board availableTypeFromArray:[NSArray arrayWithObject:NSFilenamesPboardType]] ) {
		BOOL passive = [[NSUserDefaults standardUserDefaults] boolForKey:@"JVSendFilesPassively"];
		JVBuddy *buddy = [_buddyOrder objectAtIndex:row];
		MVChatUser *user = [buddy activeUser];
		NSArray *files = [[info draggingPasteboard] propertyListForType:NSFilenamesPboardType];
		NSEnumerator *enumerator = [files objectEnumerator];
		id file = nil;

		while( ( file = [enumerator nextObject] ) )
			[[MVFileTransferController defaultController] addFileTransfer:[user sendFile:file passively:passive]];

		return YES;
	}

	return NO;
}

- (NSRange) tableView:(MVTableView *) tableView rowsInRect:(NSRect) rect defaultRange:(NSRange) defaultRange {
	if( tableView != buddies ) return defaultRange;

	if( _animating ) return NSMakeRange( 0, [_buddyOrder count] );
	else return defaultRange;
}

#define curveFunction(t,p) ( pow( 1 - pow( ( 1 - t ), p ), ( p ? ( 1 / p ) : 0. ) ) )
#define easeFunction(t) ( ( sin( ( t * M_PI ) - M_PI_2 ) + 1. ) / 2. )

- (NSRect) tableView:(MVTableView *) tableView rectOfRow:(int) row defaultRect:(NSRect) defaultRect {
	if( _animating ) {
		int oldPosition = [[_oldPositions objectAtIndex:row] intValue];
		NSRect oldR = [tableView originalRectOfRow:oldPosition];
		NSRect newR = [tableView originalRectOfRow:row];

		float t = _animationPosition;

		unsigned count = [_buddyOrder count];
		float rowPos = ( (float) row / (float) count );
		float rowPosAdjusted = _viewingTop ? ( 1. - rowPos ) : rowPos;
		float curve = 0.3;
		float p = rowPosAdjusted * ( curve * 2. ) + 1. - curve;

		t = curveFunction( t, p );
		t = easeFunction( t );

		return NSMakeRect( NSMinX( oldR ) + ( t * ( NSMinX( newR ) - NSMinX( oldR ) ) ), NSMinY( oldR ) + ( t * ( NSMinY( newR ) - NSMinY( oldR ) ) ), NSWidth( newR ), NSHeight( newR ) );
	} else return defaultRect;
}
@end

#pragma mark -

@implementation MVBuddyListController (MVBuddyListControllerPrivate)
- (void) _animateStep:(NSTimer *) timer {
	static NSDate *start = nil;
	if( ! _animationPosition ) {
		[start release];
		start = [[NSDate date] retain];
	}

	NSTimeInterval elapsed = fabs( [start timeIntervalSinceNow] );
	_animationPosition = MIN( 1., elapsed / .25 );

	if( fabs( _animationPosition - 1. ) <= 0.01 ) {
		[start release];
		start = nil;

		[timer invalidate];
		[timer release];

		_animationPosition = 0.;
		_animating = NO;
	}

	[buddies display];
}

- (void) _manuallySortAndUpdate {
	if( _animationPosition ) return;
	[self _sortBuddies];
	[buddies reloadData];
}

- (void) _sortBuddies {
	switch( _sortOrder ) {
	default:
	case MVAvailabilitySortOrder:
		[_buddyOrder sortUsingSelector:@selector( availabilityCompare: )];
		break;
	case MVFirstNameSortOrder:
		[_buddyOrder sortUsingSelector:@selector( firstNameCompare: )];
		break;
	case MVLastNameSortOrder:
		[_buddyOrder sortUsingSelector:@selector( lastNameCompare: )];
		break;
	case MVServerSortOrder:
		[_buddyOrder sortUsingSelector:@selector( serverCompare: )];
	}
}

- (void) _setBuddiesNeedSortAnimated {
	if( _needsToAnimate ) return; // already queued to animate
	_needsToAnimate = YES;

	[self performSelector:@selector( _sortBuddiesAnimated: ) withObject:nil afterDelay:0.5];
}

- (void) _sortBuddiesAnimated:(id) sender {
	_needsToAnimate = NO;
	if( _animating ) return;

	NSRange visibleRows;
	NSArray *oldOrder = [_buddyOrder copy];

	id selectedObject = nil;
	if( [buddies selectedRow] != -1 && [buddies selectedRow] < (int)[oldOrder count] )
		selectedObject = [oldOrder objectAtIndex:[buddies selectedRow]];

	[self _sortBuddies];

	if( [oldOrder isEqualToArray:_buddyOrder] ) return;

	if( selectedObject ) {
		[buddies deselectAll:nil];
		[buddies selectRow:[_buddyOrder indexOfObjectIdenticalTo:selectedObject] byExtendingSelection:NO];
		[buddies setNeedsDisplay:NO];
	}

	_animating = YES;

	[_oldPositions release];
	_oldPositions = [[NSMutableArray arrayWithCapacity:[_buddyOrder count]] retain];

	NSEnumerator *enumerator = [_buddyOrder objectEnumerator];
	id object = nil;

	while( ( object = [enumerator nextObject] ) )
		[_oldPositions addObject:[NSNumber numberWithInt:[oldOrder indexOfObject:object]]];

	visibleRows = [buddies rowsInRect:[buddies visibleRect]];
	_viewingTop = NSMaxRange( visibleRows ) < 0.6 * [_buddyOrder count];

	[[NSTimer scheduledTimerWithTimeInterval:( 1. / 240. ) target:self selector:@selector( _animateStep: ) userInfo:nil repeats:YES] retain];

	[oldOrder release];
}

- (void) _buddyChanged:(NSNotification *) notification {
	JVBuddy *buddy = [notification object];
	if( ! [_onlineBuddies containsObject:buddy] ) return;
	[self _setBuddiesNeedSortAnimated];
	if( ! _animating ) [buddies reloadData];
}

- (void) _buddyOnline:(NSNotification *) notification {
	JVBuddy *buddy = [notification object];
	if( ! [_buddyList containsObject:buddy] ) return;

	[_onlineBuddies addObject:buddy];
	if( ! [_buddyOrder containsObject:buddy] )
		[_buddyOrder addObject:buddy];

	[self _buddyChanged:notification];

	NSMutableDictionary *context = [NSMutableDictionary dictionary];
	[context setObject:NSLocalizedString( @"Buddy Available", "available buddy bubble title" )  forKey:@"title"];
	[context setObject:[NSString stringWithFormat:NSLocalizedString( @"Your buddy %@ is now online.", "available buddy bubble text" ), [buddy displayName]] forKey:@"description"];

	NSImage *icon = [buddy picture];
	if( ! icon ) icon = [NSImage imageNamed:@"largePerson"];
	[context setObject:icon forKey:@"image"];

	[[JVNotificationController defaultController] performNotification:@"JVChatBuddyOnline" withContextInfo:context];
}

- (void) _buddyOffline:(NSNotification *) notification {
	JVBuddy *buddy = [notification object];
	if( ! [_onlineBuddies containsObject:buddy] ) return;

	[_onlineBuddies removeObject:buddy];
	if( ! _showOfflineBuddies )
		[_buddyOrder removeObject:buddy];

	[self _buddyChanged:notification];

	MVChatConnection *buddyConnection = [[buddy activeUser] connection];
	if( [buddyConnection isConnected] ) {
		NSMutableDictionary *context = [NSMutableDictionary dictionary];
		[context setObject:NSLocalizedString( @"Buddy Unavailable", "unavailable buddy bubble title" ) forKey:@"title"];
		[context setObject:[NSString stringWithFormat:NSLocalizedString( @"Your buddy %@ is now offline.", "unavailable buddy bubble text" ), [buddy displayName]] forKey:@"description"];

		NSImage *icon = [buddy picture];
		if( ! icon ) icon = [NSImage imageNamed:@"largePerson"];
		[context setObject:icon forKey:@"image"];

		[[JVNotificationController defaultController] performNotification:@"JVChatBuddyOffline" withContextInfo:context];
	}
}

- (void) _loadBuddyList {
	NSArray *list = [[NSArray allocWithZone:nil] initWithContentsOfFile:[@"~/Library/Application Support/Colloquy/Buddy List.plist" stringByExpandingTildeInPath]];
	NSEnumerator *enumerator = [list objectEnumerator];
	NSDictionary *buddyDictionary = nil;

	while( ( buddyDictionary = [enumerator nextObject] ) ) {
		JVBuddy *buddy = [[JVBuddy allocWithZone:[self zone]] initWithDictionaryRepresentation:buddyDictionary];
		if( buddy ) [self addBuddy:buddy];
		[buddy release];
	}

	[list release];
}
@end

#pragma mark -

@implementation JVBuddy (JVBuddyObjectSpecifier)
- (NSScriptObjectSpecifier *) objectSpecifier {
	id classDescription = [NSClassDescription classDescriptionForClass:[MVBuddyListController class]];
	NSScriptObjectSpecifier *container = [[MVBuddyListController sharedBuddyList] objectSpecifier];
	return [[[NSUniqueIDSpecifier alloc] initWithContainerClassDescription:classDescription containerSpecifier:container key:@"buddies" uniqueID:[self uniqueIdentifier]] autorelease];
}
@end

#pragma mark -

@implementation MVBuddyListController (MVBuddyListControllerScripting)
- (MVChatConnection *) valueInBuddiesAtIndex:(unsigned) index {
	return [_buddyOrder objectAtIndex:index];
}

- (void) addInBuddies:(JVBuddy *) buddy {
	[NSException raise:NSOperationNotSupportedForKeyException format:@"Can't add a buddy."];
}

- (void) insertInBuddies:(JVBuddy *) buddy {
	[NSException raise:NSOperationNotSupportedForKeyException format:@"Can't insert a buddy."];
}

- (void) insertInBuddies:(JVBuddy *) buddy atIndex:(unsigned) index {
	[NSException raise:NSOperationNotSupportedForKeyException format:@"Can't insert a buddy."];
}

- (void) removeFromBuddiesAtIndex:(unsigned) index {
	JVBuddy *buddy = [[_buddyOrder objectAtIndex:index] retain];
	[_buddyList removeObject:buddy];
	[_onlineBuddies removeObject:buddy];
	[_buddyOrder removeObjectIdenticalTo:buddy];
	[buddy release];
	[self _manuallySortAndUpdate];
	[self save];
}

- (void) replaceInBuddies:(JVBuddy *) buddy atIndex:(unsigned) index {
	[NSException raise:NSOperationNotSupportedForKeyException format:@"Can't replace a buddy."];
}

- (JVBuddy *) valueInBuddiesWithUniqueID:(id) identifier {
	NSEnumerator *enumerator = [_buddyList objectEnumerator];
	JVBuddy *buddy = nil;

	while( ( buddy = [enumerator nextObject] ) )
		if( [[buddy uniqueIdentifier] isEqualTo:identifier] )
			return buddy;

	return nil;
}

- (JVBuddy *) valueInBuddiesWithName:(NSString *) name {
	NSEnumerator *enumerator = [_buddyList objectEnumerator];
	JVBuddy *buddy = nil;

	while( ( buddy = [enumerator nextObject] ) )
		if( [[buddy compositeName] isEqualToString:name] )
			return buddy;

	return nil;
}
@end
