#import <Cocoa/Cocoa.h>

#import "JVChatWindowController.h"
#import "MVConnectionsController.h"
#import "JVChatController.h"
#import "JVChatRoom.h"
#import "JVChatRoomBrowser.h"
#import "JVDirectChat.h"
#import "JVDetailCell.h"
#import "MVMenuButton.h"

NSString *JVToolbarToggleChatDrawerItemIdentifier = @"JVToolbarToggleChatDrawerItem";
NSString *JVToolbarToggleChatActivityItemIdentifier = @"JVToolbarToggleChatActivityItem";
NSString *JVChatViewPboardType = @"Colloquy Chat View v1.0 pasteboard type";

@interface NSToolbar (NSToolbarPrivate)
- (NSView *) _toolbarView;
@end

#pragma mark -

@interface JVChatWindowController (JVChatWindowControllerPrivate)
- (void) _claimMenuCommands;
- (void) _resignMenuCommands;
- (void) _refreshSelectionMenu;
- (void) _refreshWindow;
- (void) _refreshWindowTitle;
- (void) _refreshList;
- (void) _refreshChatActivityToolbarItemWithListItem:(id <JVChatListItem>) item;
@end

#pragma mark -

@interface NSOutlineView (ASEntendedOutlineView)
- (void) redisplayItemEqualTo:(id) item;
@end

#pragma mark -

@implementation JVChatWindowController
- (id) init {
	return ( self = [self initWithWindowNibName:nil] );
}

- (id) initWithWindowNibName:(NSString *) windowNibName {
	if( ( self = [super initWithWindowNibName:@"JVChatWindow"] ) ) {
		viewsDrawer = nil;
		chatViewsOutlineView = nil;
		viewActionButton = nil;
		favoritesButton = nil;
		activityToolbarButton = nil;
		_activityToolbarItem = nil;
		_activeViewController = nil;
		_currentlyDragging = NO;
		_views = [[NSMutableArray array] retain];
		_usesSmallIcons = [[NSUserDefaults standardUserDefaults] boolForKey:@"JVChatWindowUseSmallDrawerIcons"];

		[[self window] makeKeyAndOrderFront:nil];
	}
	return self;
}

- (void) windowDidLoad {
	NSTableColumn *column = nil;
	id prototypeCell = nil;

	_placeHolder = [[[self window] contentView] retain];

	column = [chatViewsOutlineView outlineTableColumn];
	prototypeCell = [[JVDetailCell new] autorelease];
	[prototypeCell setFont:[NSFont toolTipsFontOfSize:11.]];
	[column setDataCell:prototypeCell];

	[chatViewsOutlineView setRefusesFirstResponder:YES];
	[chatViewsOutlineView setDoubleAction:@selector( _doubleClickedListItem: )];
	[chatViewsOutlineView setAutoresizesOutlineColumn:YES];
	[chatViewsOutlineView setMenu:[[[NSMenu alloc] initWithTitle:@""] autorelease]];
	[chatViewsOutlineView registerForDraggedTypes:[NSArray arrayWithObjects:JVChatViewPboardType, NSFilenamesPboardType, nil]];

	[favoritesButton setMenu:[MVConnectionsController favoritesMenu]];
	_currentlyDragging = NO;

//	[activityToolbarButton retain];
//	[activityToolbarButton removeFromSuperview];
//	[activityToolbarButton setDrawsArrow:YES];

	[[self window] setFrameUsingName:@"Chat Window"];
	[[self window] setFrameAutosaveName:@"Chat Window"];

	NSSize drawerSize = NSSizeFromString( [[NSUserDefaults standardUserDefaults] stringForKey:@"JVChatWindowDrawerSize"] );
	if( drawerSize.width ) [viewsDrawer setContentSize:drawerSize];

	if( [[NSUserDefaults standardUserDefaults] boolForKey:@"JVChatWindowDrawerOpen"] )
		[viewsDrawer open:nil];

	[self _refreshList];
}

- (void) dealloc {
	[[self window] setDelegate:nil];
	[[self window] setToolbar:nil];
	[[self window] setContentView:_placeHolder];

	[viewsDrawer setDelegate:nil];
	[chatViewsOutlineView setDelegate:nil];
	[chatViewsOutlineView setDataSource:nil];
	[favoritesButton setMenu:nil];

	[[NSNotificationCenter defaultCenter] removeObserver:self];

	NSEnumerator *enumerator = [_views objectEnumerator];
	id <JVChatViewController> controller = nil;
	while( ( controller = [enumerator nextObject] ) )
		[controller setWindowController:nil];

	[_placeHolder release];
	[_activeViewController release];
	[_activityToolbarItem release];
	[_views release];

	_placeHolder = nil;
	_activityToolbarItem = nil;
	_activeViewController = nil;
	_views = nil;

	[super dealloc];
}

#pragma mark -

- (BOOL) respondsToSelector:(SEL) selector {
	if( [_activeViewController respondsToSelector:selector] )
		return [_activeViewController respondsToSelector:selector];
	else return [super respondsToSelector:selector];
}

- (void) forwardInvocation:(NSInvocation *) invocation {
	if( [_activeViewController respondsToSelector:[invocation selector]] )
		[invocation invokeWithTarget:_activeViewController];
	else [super forwardInvocation:invocation];
}

- (NSMethodSignature *) methodSignatureForSelector:(SEL) selector {
	if( [_activeViewController respondsToSelector:selector] )
		return [(NSObject *)_activeViewController methodSignatureForSelector:selector];
	else return [super methodSignatureForSelector:selector];
}

#pragma mark -

- (void) showChatViewController:(id <JVChatViewController>) controller {
	NSAssert1( [_views containsObject:controller], @"%@ is not a member of this window controller.", controller );
	[chatViewsOutlineView selectRow:[chatViewsOutlineView rowForItem:controller] byExtendingSelection:NO];
	[self _refreshList];
	[self _refreshWindow];
}

#pragma mark -

- (id <JVInspection>) objectToInspect {
	id item = [self selectedListItem];
	if( [item conformsToProtocol:@protocol( JVInspection )] ) return item;
	else return nil;
}

- (IBAction) getInfo:(id) sender {
	id item = [self selectedListItem];
	if( [item conformsToProtocol:@protocol( JVInspection )] )
		if( [[[NSApplication sharedApplication] currentEvent] modifierFlags] & NSAlternateKeyMask )
			[JVInspectorController showInspector:sender];
		else [[JVInspectorController inspectorOfObject:item] show:sender];
}

#pragma mark -

- (IBAction) joinRoom:(id) sender {
	[[JVChatRoomBrowser chatRoomBrowserForConnection:[_activeViewController connection]] showWindow:nil];
}

#pragma mark -

- (void) close {
	[[JVChatController defaultManager] performSelector:@selector( disposeChatWindowController: ) withObject:self afterDelay:0.];
	[[self window] orderOut:nil];
	[super close];
}

- (IBAction) closeCurrentPanel:(id) sender {
	[[JVChatController defaultManager] disposeViewController:_activeViewController];
}

- (IBAction) selectPreviousPanel:(id) sender {
	int currentIndex = [_views indexOfObject:_activeViewController];
	int index = 0;

	if( currentIndex - 1 >= 0 ) index = ( currentIndex - 1 );
	else index = ( [_views count] - 1 );

	[self showChatViewController:[_views objectAtIndex:index]];
}

- (IBAction) selectPreviousActivePanel:(id) sender {
	int currentIndex = [_views indexOfObject:_activeViewController];
	int index = currentIndex;
	BOOL done = NO;
	
	do {
		if( [[_views objectAtIndex:index] respondsToSelector:@selector( newMessagesWaiting )] && [[_views objectAtIndex:index] newMessagesWaiting] > 0 ){
			done = YES;
		}
			
		if ( !done ) {
			if ( index == 0 ) index = [_views count]-1;
			else index--;
		}
	}while ( index != currentIndex && !done );

	
	[self showChatViewController:[_views objectAtIndex:index]];
}

- (IBAction) selectNextPanel:(id) sender {
	int currentIndex = [_views indexOfObject:_activeViewController];
	int index = 0;

	if( currentIndex + 1 < [_views count] ) index = ( currentIndex + 1 );
	else index = 0;

	[self showChatViewController:[_views objectAtIndex:index]];
}

- (IBAction) selectNextActivePanel:(id) sender {
	int currentIndex = [_views indexOfObject:_activeViewController];
	int index = currentIndex;
	BOOL done = NO;
	
	do {
		if( [[_views objectAtIndex:index] respondsToSelector:@selector( newMessagesWaiting )] && [[_views objectAtIndex:index] newMessagesWaiting] > 0 ){
			done = YES;
		}
		
		if ( !done ) {
			if ( index == [_views count]-1 ) index = 0;
			else index++;
		}
	}while ( index != currentIndex && !done );
	
	
	[self showChatViewController:[_views objectAtIndex:index]];
}

#pragma mark -

- (id <JVChatViewController>) activeChatViewController {
	return [[_activeViewController retain] autorelease];
}

- (id <JVChatListItem>) selectedListItem {
	long index = -1;
	if( ( index = [chatViewsOutlineView selectedRow] ) == -1 )
		return nil;
	return [chatViewsOutlineView itemAtRow:index];
}

#pragma mark -

- (void) addChatViewController:(id <JVChatViewController>) controller {
	NSParameterAssert( controller != nil );
	NSAssert1( ! [_views containsObject:controller], @"%@ already added.", controller );

	[_views addObject:controller];
	[controller setWindowController:self];

	if( [_views count] >= 2 ) [viewsDrawer open];

	[self _refreshList];
	[self _refreshWindow];
}

- (void) insertChatViewController:(id <JVChatViewController>) controller atIndex:(unsigned int) index {
	NSParameterAssert( controller != nil );
	NSAssert1( ! [_views containsObject:controller], @"%@ already added.", controller );
	NSAssert( index >= 0 && index <= [_views count], @"Index is beyond bounds." );

	[_views insertObject:controller atIndex:index];
	[controller setWindowController:self];

	if( [_views count] >= 2 ) [viewsDrawer open];

	[self _refreshList];
	[self _refreshWindow];
}

#pragma mark -

- (void) removeChatViewController:(id <JVChatViewController>) controller {
	NSParameterAssert( controller != nil );
	NSAssert1( [_views containsObject:controller], @"%@ is not a member of this window controller.", controller );

	if( _activeViewController == controller ) {
		[_activeViewController autorelease];
		_activeViewController = nil;
	}

	[controller setWindowController:nil];
	[_views removeObjectIdenticalTo:controller];

	[self _refreshList];
	[self _refreshWindow];

	if( ! [_views count] && [[self window] isVisible] )
		[self close];
}

- (void) removeChatViewControllerAtIndex:(unsigned int) index {
	NSAssert( index >= 0 && index <= [_views count], @"Index is beyond bounds." );
	[self removeChatViewController:[_views objectAtIndex:index]];
}

- (void) removeAllChatViewControllers {
	[_activeViewController autorelease];
	_activeViewController = nil;

	NSEnumerator *enumerator = [_views objectEnumerator];
	id <JVChatViewController> controller = nil;

	while( ( controller = [enumerator nextObject] ) )
		[controller setWindowController:nil];

	[_views removeAllObjects];

	[self _refreshList];
	[self _refreshWindow];

	if( [[self window] isVisible] )
		[self close];
}

#pragma mark -

- (void) replaceChatViewController:(id <JVChatViewController>) controller withController:(id <JVChatViewController>) newController {
	NSParameterAssert( controller != nil );
	NSParameterAssert( newController != nil );
	NSAssert1( [_views containsObject:controller], @"%@ is not a member of this window controller.", controller );
	NSAssert1( ! [_views containsObject:newController], @"%@ is already a member of this window controller.", newController );

	[self replaceChatViewControllerAtIndex:[_views indexOfObjectIdenticalTo:controller] withController:newController];
}

- (void) replaceChatViewControllerAtIndex:(unsigned int) index withController:(id <JVChatViewController>) controller {
	id <JVChatViewController> oldController = nil;
	NSParameterAssert( controller != nil );
	NSAssert1( ! [_views containsObject:controller], @"%@ is already a member of this window controller.", controller );
	NSAssert( index >= 0 && index <= [_views count], @"Index is beyond bounds." );

	oldController = [_views objectAtIndex:index];

	if( _activeViewController == oldController ) {
		[_activeViewController autorelease];
		_activeViewController = nil;
	}

	[oldController setWindowController:nil];
	[_views replaceObjectAtIndex:index withObject:controller];
	[controller setWindowController:self];

	[self _refreshList];
	[self _refreshWindow];
}

#pragma mark -

- (NSArray *) chatViewControllersForConnection:(MVChatConnection *) connection {
	NSMutableArray *ret = [NSMutableArray array];
	NSEnumerator *enumerator = [_views objectEnumerator];
	id <JVChatViewController> controller = nil;

	NSParameterAssert( connection != nil );

	while( ( controller = [enumerator nextObject] ) )
		if( [controller connection] == connection )
			[ret addObject:controller];

	return [[ret retain] autorelease];
}

- (NSArray *) chatViewControllersWithControllerClass:(Class) class {
	NSMutableArray *ret = [NSMutableArray array];
	NSEnumerator *enumerator = [_views objectEnumerator];
	id <JVChatViewController> controller = nil;

	NSParameterAssert( class != NULL );
	NSAssert( [class conformsToProtocol:@protocol( JVChatViewController )], @"The tab controller class must conform to the JVChatViewController protocol." );

	ret = [NSMutableArray array];
	while( ( controller = [enumerator nextObject] ) )
		if( [controller isMemberOfClass:class] )
			[ret addObject:controller];

	return [[ret retain] autorelease];
}

- (NSArray *) allChatViewControllers {
	return [[_views retain] autorelease];
}

#pragma mark -

- (NSToolbarItem *) toggleChatDrawerToolbarItem {
	NSToolbarItem *toolbarItem = [[[NSToolbarItem alloc] initWithItemIdentifier:JVToolbarToggleChatDrawerItemIdentifier] autorelease];

	[toolbarItem setLabel:NSLocalizedString( @"Drawer", "chat panes drawer toolbar item name" )];
	[toolbarItem setPaletteLabel:NSLocalizedString( @"Panel Drawer", "chat panes drawer toolbar customize palette name" )];

	[toolbarItem setToolTip:NSLocalizedString( @"Toggle Chat Panel Drawer", "chat panes drawer toolbar item tooltip" )];
	[toolbarItem setImage:[NSImage imageNamed:@"showdrawer"]];

	[toolbarItem setTarget:self];
	[toolbarItem setAction:@selector( toggleViewsDrawer: )];

	return toolbarItem;
}

- (NSToolbarItem *) chatActivityToolbarItem {
	return nil;

/*	if( _activityToolbarItem ) return _activityToolbarItem;

	_activityToolbarItem = [[NSToolbarItem alloc] initWithItemIdentifier:JVToolbarToggleChatActivityItemIdentifier];

	[_activityToolbarItem setLabel:NSLocalizedString( @"Activity", "chat activity toolbar item name" )];
	[_activityToolbarItem setPaletteLabel:NSLocalizedString( @"Chat Activity", "chat activity drawer toolbar customize palette name" )];

	[activityToolbarButton setToolbarItem:_activityToolbarItem];
	[_activityToolbarItem setView:activityToolbarButton];

	return _activityToolbarItem;*/
}

- (IBAction) toggleViewsDrawer:(id) sender {
	[viewsDrawer toggle:sender];

	if( [viewsDrawer state] == NSDrawerClosedState || [viewsDrawer state] == NSDrawerClosingState )
		[[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"JVChatWindowDrawerOpen"];
	else if( [viewsDrawer state] == NSDrawerOpenState || [viewsDrawer state] == NSDrawerOpeningState )
		[[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"JVChatWindowDrawerOpen"];
}

- (IBAction) openViewsDrawer:(id) sender {
	[viewsDrawer open:sender];
	[[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"JVChatWindowDrawerOpen"];
}

- (IBAction) closeViewsDrawer:(id) sender {
	[viewsDrawer close:sender];
	[[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"JVChatWindowDrawerOpen"];
}

- (IBAction) toggleSmallDrawerIcons:(id) sender {
	_usesSmallIcons = ! _usesSmallIcons;
	[[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithBool:_usesSmallIcons] forKey:@"JVChatWindowUseSmallDrawerIcons"];
	[self _refreshList];
}

#pragma mark -

- (void) reloadListItem:(id <JVChatListItem>) item andChildren:(BOOL) children {
	[chatViewsOutlineView reloadItem:item reloadChildren:( children && [chatViewsOutlineView isItemExpanded:item] ? YES : NO )];
	[chatViewsOutlineView sizeLastColumnToFit];
	if( _activeViewController == item )
		[self _refreshWindowTitle];
	if( item == [self selectedListItem] )
		[self _refreshSelectionMenu];
//	[self _refreshChatActivityToolbarItemWithListItem:item];
}

- (void) expandListItem:(id <JVChatListItem>) item {
	[chatViewsOutlineView expandItem:item];
}

#pragma mark -

- (BOOL) validateMenuItem:(NSMenuItem *) menuItem {
	if( [menuItem action] == @selector( toggleSmallDrawerIcons: ) ) {
		[menuItem setState:( _usesSmallIcons ? NSOnState : NSOffState )];
		return YES;
	} else if( [menuItem action] == @selector( toggleViewsDrawer: ) ) {
		if( [viewsDrawer state] == NSDrawerClosedState || [viewsDrawer state] == NSDrawerClosingState ) {
			[menuItem setTitle:[NSString stringWithFormat:NSLocalizedString( @"Show Drawer", "show drawer menu title" )]];
		} else {
			[menuItem setTitle:[NSString stringWithFormat:NSLocalizedString( @"Hide Drawer", "hide drawer menu title" )]];
		}
		return YES;
	} else if( [menuItem action] == @selector( getInfo: ) ) {
		id item = [self selectedListItem];
		if( [item conformsToProtocol:@protocol( JVInspection )] ) return YES;
		else return NO;
	} else if( [menuItem action] == @selector( closeCurrentPanel: ) ) {
		if( [[menuItem keyEquivalent] length] ) return YES;
		else return NO;
	}
	return YES;
}
@end

#pragma mark -

@implementation JVChatWindowController (JVChatWindowControllerDelegate)
- (NSSize) drawerWillResizeContents:(NSDrawer *) drawer toSize:(NSSize) contentSize {
	[[NSUserDefaults standardUserDefaults] setObject:NSStringFromSize( contentSize ) forKey:@"JVChatWindowDrawerSize"];
	return contentSize;
}

#pragma mark -

- (void) windowWillClose:(NSNotification *) notification {
    if( ! [[[[[NSApplication sharedApplication] keyWindow] windowController] className] isEqual:[self className]] )
		[self _resignMenuCommands];
    if( [[self window] isVisible] )
		[self close];
}

- (void) windowDidResignKey:(NSNotification *) notification {
    if( ! [[[[[NSApplication sharedApplication] keyWindow] windowController] className] isEqual:[self className]] )
		[self _resignMenuCommands];
}

- (void) windowDidResignMain:(NSNotification *) notification {
    if( ! [[[[[NSApplication sharedApplication] keyWindow] windowController] className] isEqual:[self className]] )
		[self _resignMenuCommands];
}

- (void) windowDidBecomeMain:(NSNotification *) notification {
	[self _claimMenuCommands];
	[[self window] makeFirstResponder:[_activeViewController firstResponder]];
	if( _activeViewController )
		[self reloadListItem:_activeViewController andChildren:NO];
}

- (void) windowDidBecomeKey:(NSNotification *) notification {
	[self _claimMenuCommands];
	[[self window] makeFirstResponder:[_activeViewController firstResponder]];
	if( _activeViewController )
		[self reloadListItem:_activeViewController andChildren:NO];
}

#pragma mark -

- (void) outlineView:(NSOutlineView *) outlineView willDisplayCell:(id) cell forTableColumn:(NSTableColumn *) tableColumn item:(id) item {
	[(JVDetailCell *) cell setRepresentedObject:item];
	[(JVDetailCell *) cell setMainText:[item title]];

	if( [item respondsToSelector:@selector( information )] ) {
		[(JVDetailCell *) cell setInformationText:[item information]];
	} else [(JVDetailCell *) cell setInformationText:nil];

	if( [item respondsToSelector:@selector( statusImage )] ) {
		[(JVDetailCell *) cell setStatusImage:[item statusImage]];
	} else [(JVDetailCell *) cell setStatusImage:nil];

	if( [item respondsToSelector:@selector( isEnabled )] ) {
		[cell setEnabled:[item isEnabled]];
	} else [cell setEnabled:YES];

	// This is needed if we reorder the list and selection dosen't change.
	// This will catch it incase the previous selected item moved.
	// We could follow the item through the sort, but we don't sort in
	// this object, so it is almost impossible.

	if( item == [self selectedListItem] )
		[self _refreshSelectionMenu];
}

- (NSString *) outlineView:(NSOutlineView *) outlineView toolTipForItem:(id) item inTrackingRect:(NSRect) rect forCell:(id) cell {
	if( [item respondsToSelector:@selector( toolTip )] )
		return [item toolTip];
	return nil;
}

- (int) outlineView:(NSOutlineView *) outlineView numberOfChildrenOfItem:(id) item {
	if( item && [item respondsToSelector:@selector( numberOfChildren )] ) return [item numberOfChildren];
	else return [_views count];
}

- (BOOL) outlineView:(NSOutlineView *) outlineView isItemExpandable:(id) item {
	return ( [item respondsToSelector:@selector( numberOfChildren )] && [item numberOfChildren] ? YES : NO );
}

- (id) outlineView:(NSOutlineView *) outlineView child:(int) index ofItem:(id) item {
	if( item ) {
		if( [item respondsToSelector:@selector( childAtIndex: )] )
			return [item childAtIndex:index];
		else return nil;
	} else return [_views objectAtIndex:index];
}

- (id) outlineView:(NSOutlineView *) outlineView objectValueForTableColumn:(NSTableColumn *) tableColumn byItem:(id) item {
	NSImage *ret = [[[item icon] copy] autorelease];
	[ret setScalesWhenResized:YES];
	if( [outlineView levelForRow:[outlineView rowForItem:item]] || _usesSmallIcons ) {
		[ret setSize:NSMakeSize( 16., 16. )];
	} else {
		[ret setSize:NSMakeSize( 32., 32. )];
	}
	return ret;
}

- (BOOL) outlineView:(NSOutlineView *) outlineView shouldEditTableColumn:(NSTableColumn *) tableColumn item:(id) item {
	return NO;
}

- (BOOL) outlineView:(NSOutlineView *) outlineView shouldExpandItem:(id) item {
	BOOL retVal = YES; 
	if ( _currentlyDragging )retVal = NO; // if we are dragging don't expand
	return retVal;
}

- (BOOL) outlineView:(NSOutlineView *) outlineView shouldCollapseItem:(id) item {
	if( [self selectedListItem] != [self activeChatViewController] )
		[outlineView selectRow:[outlineView rowForItem:[self activeChatViewController]] byExtendingSelection:NO];
	return YES;
}

- (int) outlineView:(NSOutlineView *) outlineView heightOfRow:(int) row {
	return ( [outlineView levelForRow:row] || _usesSmallIcons ? 18 : 36 );
}

- (void) outlineViewSelectionDidChange:(NSNotification *) notification {
	id item = [self selectedListItem];

	[[JVInspectorController sharedInspector] inspectObject:[self objectToInspect]];

	if( [item conformsToProtocol:@protocol( JVChatViewController )] && item != (id) _activeViewController )
		[self _refreshWindow];

	[self _refreshSelectionMenu];
//	[self _refreshChatActivityToolbarItemWithListItem:item];
}

- (BOOL) outlineView:(NSOutlineView *) outlineView writeItems:(NSArray *) items toPasteboard:(NSPasteboard *) board {
	id item = [items lastObject];
	NSData *data = [NSData dataWithBytes:&item length:sizeof( &item )];
	if( ! [item conformsToProtocol:@protocol( JVChatViewController )] ) return NO;
	[board declareTypes:[NSArray arrayWithObjects:JVChatViewPboardType, nil] owner:self];
	[board setData:data forType:JVChatViewPboardType];
	return YES;
}

- (NSDragOperation) outlineView:(NSOutlineView *) outlineView validateDrop:(id <NSDraggingInfo>) info proposedItem:(id) item proposedChildIndex:(int) index {
	if( [[info draggingPasteboard] availableTypeFromArray:[NSArray arrayWithObject:NSFilenamesPboardType]] ) {
		if( [item respondsToSelector:@selector( acceptsDraggedFileOfType: )] ) {
			NSArray *files = [[info draggingPasteboard] propertyListForType:NSFilenamesPboardType];
			NSEnumerator *enumerator = [files objectEnumerator];
			_currentlyDragging = NO;
			
			id file = nil;
			while( ( file = [enumerator nextObject] ) )
				if( [item acceptsDraggedFileOfType:[file pathExtension]] )
					return NSDragOperationMove;
			return NSDragOperationNone;
		} else return NSDragOperationNone;
	} else if( [[info draggingPasteboard] availableTypeFromArray:[NSArray arrayWithObject:JVChatViewPboardType]] ) {
		_currentlyDragging = YES;
		if( ! item ) return NSDragOperationMove;
		else return NSDragOperationNone;
	} else return NSDragOperationNone;
}

- (BOOL) outlineView:(NSOutlineView *) outlineView acceptDrop:(id <NSDraggingInfo>) info item:(id) item childIndex:(int) index {
	_currentlyDragging = NO;
	
	NSPasteboard *board = [info draggingPasteboard];
	if( [board availableTypeFromArray:[NSArray arrayWithObject:NSFilenamesPboardType]] ) {
		NSArray *files = [[info draggingPasteboard] propertyListForType:NSFilenamesPboardType];
		NSEnumerator *enumerator = [files objectEnumerator];
		id file = nil;

		if( ! [item respondsToSelector:@selector( acceptsDraggedFileOfType: )] || ! [item respondsToSelector:@selector( handleDraggedFile: )] ) return NO;

		while( ( file = [enumerator nextObject] ) )
			if( [item acceptsDraggedFileOfType:[file pathExtension]] )
				[item handleDraggedFile:file];

		return YES;
	} else if( [board availableTypeFromArray:[NSArray arrayWithObject:JVChatViewPboardType]] ) {
		NSData *pointerData = [board dataForType:JVChatViewPboardType];
		id <JVChatViewController> dragedController = nil;
		[pointerData getBytes:&dragedController];

		[[dragedController retain] autorelease];

		if( [_views containsObject:dragedController] ) {
			if( index != NSOutlineViewDropOnItemIndex && index >= [_views indexOfObjectIdenticalTo:dragedController] ) index--;
			[_views removeObjectIdenticalTo:dragedController];
		} else {
			[[dragedController windowController] removeChatViewController:dragedController];
		}

		if( index == NSOutlineViewDropOnItemIndex ) [self addChatViewController:dragedController];
		else [self insertChatViewController:dragedController atIndex:index];

		return YES;
	}

	return NO;
}

- (void) outlineViewItemDidExpand:(NSNotification *) notification {
	[chatViewsOutlineView sizeLastColumnToFit];
}
@end

#pragma mark -

@implementation JVChatWindowController (JVChatWindowControllerPrivate)
- (void) _claimMenuCommands {
	NSMenuItem *closeItem = [[[[[NSApplication sharedApplication] mainMenu] itemAtIndex:1] submenu] itemWithTag:1];
	[closeItem setKeyEquivalentModifierMask:NSCommandKeyMask];
	[closeItem setKeyEquivalent:@"W"];

	closeItem = (NSMenuItem *)[[[[[NSApplication sharedApplication] mainMenu] itemAtIndex:1] submenu] itemWithTag:2];
	[closeItem setKeyEquivalentModifierMask:NSCommandKeyMask];
	[closeItem setKeyEquivalent:@"w"];
}

- (void) _resignMenuCommands {
	NSMenuItem *closeItem = [[[[[NSApplication sharedApplication] mainMenu] itemAtIndex:1] submenu] itemWithTag:1];
	[closeItem setKeyEquivalentModifierMask:NSCommandKeyMask];
	[closeItem setKeyEquivalent:@"w"];

	closeItem = (NSMenuItem *)[[[[[NSApplication sharedApplication] mainMenu] itemAtIndex:1] submenu] itemWithTag:2];
	[closeItem setKeyEquivalentModifierMask:0];
	[closeItem setKeyEquivalent:@""];
}

- (IBAction) _doubleClickedListItem:(id) sender {
	id item = [self selectedListItem];
	if( [item respondsToSelector:@selector( doubleClicked: )] )
		[item doubleClicked:sender];
}

- (void) _refreshSelectionMenu {
	id item = [self selectedListItem];
	id menuItem = nil;
	NSMenu *menu = [chatViewsOutlineView menu];
	NSMenu *newMenu = ( [item respondsToSelector:@selector( menu )] ? [item menu] : nil );
	NSEnumerator *enumerator = [[[[menu itemArray] copy] autorelease] objectEnumerator];

	while( ( menuItem = [enumerator nextObject] ) )
		[menu removeItem:menuItem];

	enumerator = [[[[newMenu itemArray] copy] autorelease] objectEnumerator];
	while( ( menuItem = [enumerator nextObject] ) ) {
		[newMenu removeItem:menuItem];
		[menu addItem:menuItem];
	}

	[viewActionButton setMenu:menu];
}

- (void) _refreshWindow {
	id item = [self selectedListItem];

	if( ( [item conformsToProtocol:@protocol( JVChatViewController )] && item != (id) _activeViewController ) || ( ! _activeViewController && [[item parent] conformsToProtocol:@protocol( JVChatViewController )] && ( item = [item parent] ) ) ) {
		id lastActive = _activeViewController;
		if( [_activeViewController respondsToSelector:@selector( willUnselect )] )
			[(NSObject *)_activeViewController willUnselect];
		if( [item respondsToSelector:@selector( willSelect )] )
			[(NSObject *)item willSelect];

		[_activeViewController autorelease];
		_activeViewController = [item retain];

		[[self window] setContentView:[_activeViewController view]];
		[[self window] setToolbar:[_activeViewController toolbar]];
		[[self window] makeFirstResponder:[[_activeViewController view] nextKeyView]];

		if( [lastActive respondsToSelector:@selector( didUnselect )] )
			[(NSObject *)lastActive didUnselect];
		if( [_activeViewController respondsToSelector:@selector( didSelect )] )
			[(NSObject *)_activeViewController didSelect];
	} else if( ! [_views count] || ! _activeViewController ) {
		[[self window] setContentView:_placeHolder];
		[[[self window] toolbar] setDelegate:nil];
		[[self window] setToolbar:nil];
		[[self window] makeFirstResponder:nil];
	}

	[self _refreshWindowTitle];
}

- (void) _refreshWindowTitle {
	NSString *title = [_activeViewController windowTitle];
	if( ! title ) title = @"";
	[[self window] setTitle:title];
}

- (void) _refreshList {
	[chatViewsOutlineView reloadData];
	[chatViewsOutlineView noteNumberOfRowsChanged];
	[chatViewsOutlineView sizeLastColumnToFit];
	[self _refreshSelectionMenu];
}

- (void) _refreshChatActivityToolbarItemWithListItem:(id <JVChatListItem>) item {
	NSMutableArray *chats = [NSMutableArray array];
	NSEnumerator *enumerator = [_views objectEnumerator];
	id <JVChatViewController> controller = nil;

	while( ( controller = [enumerator nextObject] ) )
		if( [controller isKindOfClass:[JVDirectChat class]] )
			[chats addObject:controller];

	NSMenu *menu = [[[NSMenu alloc] initWithTitle:@""] autorelease];
	NSMenuItem *menuItem = nil;
	JVDirectChat *chat = nil;
	BOOL newMsg = NO;
	BOOL newHighMsg = NO;

	enumerator = [chats objectEnumerator];
	while( ( chat = [enumerator nextObject] ) ) {
		NSImage *icon = [[[chat icon] copy] autorelease];
		[icon setScalesWhenResized:YES];
		[icon setSize:NSMakeSize( 16., 16. )];

		menuItem = [[[NSMenuItem alloc] initWithTitle:[chat title] action:@selector( _switchViews: ) keyEquivalent:@""] autorelease];
		[menuItem setTarget:self];
		[menuItem setRepresentedObject:chat];
		[menuItem setImage:icon];
		[menu addItem:menuItem];

		if( chat == _activeViewController ) [menuItem setState:NSOnState];
		else if( [chat newMessagesWaiting] ) [menuItem setState:NSMixedState];

		if( [chat newMessagesWaiting] && chat != _activeViewController ) newMsg = YES;
		if( [chat newHighlightMessagesWaiting] && chat != _activeViewController ) newHighMsg = YES;
	}

	if( newHighMsg ) [activityToolbarButton setImage:[NSImage imageNamed:@"activityNewImportant"]];
	else if( newMsg ) [activityToolbarButton setImage:[NSImage imageNamed:@"activityNew"]];
	else [activityToolbarButton setImage:[NSImage imageNamed:@"activity"]];

	[activityToolbarButton setMenu:menu];
}

- (void) _switchViews:(id) sender {
	[self showChatViewController:[sender representedObject]];
}
@end

#pragma mark -

@implementation JVChatWindowController (JVChatWindowControllerScripting)
- (NSNumber *) uniqueIdentifier {
	return [NSNumber numberWithUnsignedInt:(unsigned long) self];
}

#pragma mark -

- (NSArray *) views {
	return _views;
}

- (id <JVChatViewController>) valueInViewsAtIndex:(unsigned) index {
	return [_views objectAtIndex:index];
}

- (id <JVChatViewController>) valueInViewsWithUniqueID:(id) identifier {
	NSEnumerator *enumerator = [_views objectEnumerator];
	id <JVChatViewController, JVChatListItemScripting> view = nil;

	while( ( view = [enumerator nextObject] ) )
		if( [[view uniqueIdentifier] isEqual:identifier] )
			return view;

	return nil;
}

- (id <JVChatViewController>) valueInViewsWithName:(NSString *) name {
	NSEnumerator *enumerator = [_views objectEnumerator];
	id <JVChatViewController> view = nil;

	while( ( view = [enumerator nextObject] ) )
		if( [[view title] isEqualToString:name] )
			return view;

	return nil;
}

- (void) addInViews:(id <JVChatViewController>) view {
	[self addChatViewController:view];
}

- (void) insertInViews:(id <JVChatViewController>) view {
	[self addChatViewController:view];
}

- (void) insertInViews:(id <JVChatViewController>) view atIndex:(int) index {
	[self insertChatViewController:view atIndex:index];
}

- (void) removeFromViewsAtIndex:(unsigned) index {
	[self removeChatViewControllerAtIndex:index];
}

- (void) replaceInViews:(id <JVChatViewController>) view atIndex:(unsigned) index {
	[self replaceChatViewControllerAtIndex:index withController:view];
}

#pragma mark -

- (NSArray *) chatViewsWithClass:(Class) class {
	NSMutableArray *ret = [NSMutableArray array];
	NSEnumerator *enumerator = [_views objectEnumerator];
	id <JVChatViewController> item = nil;

	while( ( item = [enumerator nextObject] ) )
		if( [item isMemberOfClass:class] )
			[ret addObject:item];

	return ret;
}

- (id <JVChatViewController>) valueInChatViewsAtIndex:(unsigned) index withClass:(Class) class {
	return [[self chatViewsWithClass:class] objectAtIndex:index];
}

- (id <JVChatViewController>) valueInChatViewsWithUniqueID:(id) identifier andClass:(Class) class {
	return [self valueInViewsWithUniqueID:identifier];
}

- (id <JVChatViewController>) valueInChatViewsWithName:(NSString *) name andClass:(Class) class {
	NSEnumerator *enumerator = [[self chatViewsWithClass:class] objectEnumerator];
	id <JVChatViewController> view = nil;

	while( ( view = [enumerator nextObject] ) )
		if( [[view title] isEqualToString:name] )
			return view;

	return nil;
}

- (void) addInChatViews:(id <JVChatViewController>) view withClass:(Class) class {
	unsigned int index = [_views indexOfObject:[[self chatViewsWithClass:class] lastObject]];
	[self insertChatViewController:view atIndex:( index + 1 )];
}

- (void) insertInChatViews:(id <JVChatViewController>) view atIndex:(unsigned) index withClass:(Class) class {
	if( index == [[self chatViewsWithClass:class] count] ) {
		[self addInChatViews:view withClass:class];
	} else {
		unsigned int indx = [_views indexOfObject:[[self chatViewsWithClass:class] objectAtIndex:index]];
		[self insertChatViewController:view atIndex:indx];
	}
}

- (void) removeFromChatViewsAtIndex:(unsigned) index withClass:(Class) class {
	unsigned int indx = [_views indexOfObject:[[self chatViewsWithClass:class] objectAtIndex:index]];
	[self removeChatViewControllerAtIndex:indx];
}

- (void) replaceInChatViews:(id <JVChatViewController>) view atIndex:(unsigned) index withClass:(Class) class {
	unsigned int indx = [_views indexOfObject:[[self chatViewsWithClass:class] objectAtIndex:index]];
	[self replaceChatViewControllerAtIndex:indx withController:view];
}

#pragma mark -

- (NSArray *) chatRooms {
	return [self chatViewsWithClass:[JVChatRoom class]];
}

- (id <JVChatViewController>) valueInChatRoomsAtIndex:(unsigned) index {
	return [self valueInChatViewsAtIndex:index withClass:[JVChatRoom class]];
}

- (id <JVChatViewController>) valueInChatRoomsWithUniqueID:(id) identifier {
	return [self valueInChatViewsWithUniqueID:identifier andClass:[JVChatRoom class]];
}

- (id <JVChatViewController>) valueInChatRoomsWithName:(NSString *) name {
	return [self valueInChatViewsWithName:name andClass:[JVChatRoom class]];
}

- (void) addInChatRooms:(id <JVChatViewController>) view {
	[self addInChatViews:view withClass:[JVChatRoom class]];
}

- (void) insertInChatRooms:(id <JVChatViewController>) view {
	[self addInChatViews:view withClass:[JVChatRoom class]];
}

- (void) insertInChatRooms:(id <JVChatViewController>) view atIndex:(unsigned) index {
	[self insertInChatViews:view atIndex:index withClass:[JVChatRoom class]];
}

- (void) removeFromChatRoomsAtIndex:(unsigned) index {
	[self removeFromChatViewsAtIndex:index withClass:[JVChatRoom class]];
}

- (void) replaceInChatRooms:(id <JVChatViewController>) view atIndex:(unsigned) index {
	[self replaceInChatViews:view atIndex:index withClass:[JVChatRoom class]];
}

#pragma mark -

- (NSArray *) directChats {
	return [self chatViewsWithClass:[JVDirectChat class]];
}

- (id <JVChatViewController>) valueInDirectChatsAtIndex:(unsigned) index {
	return [self valueInChatViewsAtIndex:index withClass:[JVDirectChat class]];
}

- (id <JVChatViewController>) valueInDirectChatsWithUniqueID:(id) identifier {
	return [self valueInChatViewsWithUniqueID:identifier andClass:[JVDirectChat class]];
}

- (id <JVChatViewController>) valueInDirectChatsWithName:(NSString *) name {
	return [self valueInChatViewsWithName:name andClass:[JVDirectChat class]];
}

- (void) addInDirectChats:(id <JVChatViewController>) view {
	[self addInChatViews:view withClass:[JVDirectChat class]];
}

- (void) insertInDirectChats:(id <JVChatViewController>) view {
	[self addInChatViews:view withClass:[JVDirectChat class]];
}

- (void) insertInDirectChats:(id <JVChatViewController>) view atIndex:(unsigned) index {
	[self insertInChatViews:view atIndex:index withClass:[JVDirectChat class]];
}

- (void) removeFromDirectChatsAtIndex:(unsigned) index {
	[self removeFromChatViewsAtIndex:index withClass:[JVDirectChat class]];
}

- (void) replaceInDirectChats:(id <JVChatViewController>) view atIndex:(unsigned) index {
	[self replaceInChatViews:view atIndex:index withClass:[JVDirectChat class]];
}

#pragma mark -

- (NSArray *) chatTranscripts {
	return [self chatViewsWithClass:[JVChatTranscript class]];
}

- (id <JVChatViewController>) valueInChatTranscriptsAtIndex:(unsigned) index {
	return [self valueInChatViewsAtIndex:index withClass:[JVChatTranscript class]];
}

- (id <JVChatViewController>) valueInChatTranscriptsWithUniqueID:(id) identifier {
	return [self valueInChatViewsWithUniqueID:identifier andClass:[JVChatTranscript class]];
}

- (id <JVChatViewController>) valueInChatTranscriptsWithName:(NSString *) name {
	return [self valueInChatViewsWithName:name andClass:[JVChatTranscript class]];
}

- (void) addInChatTranscripts:(id <JVChatViewController>) view {
	[self addInChatViews:view withClass:[JVChatTranscript class]];
}

- (void) insertInChatTranscripts:(id <JVChatViewController>) view {
	[self addInChatViews:view withClass:[JVChatTranscript class]];
}

- (void) insertInChatTranscripts:(id <JVChatViewController>) view atIndex:(unsigned) index {
	[self insertInChatViews:view atIndex:index withClass:[JVChatTranscript class]];
}

- (void) removeFromChatTranscriptsAtIndex:(unsigned) index {
	[self removeFromChatViewsAtIndex:index withClass:[JVChatTranscript class]];
}

- (void) replaceInChatTranscripts:(id <JVChatViewController>) view atIndex:(unsigned) index {
	[self replaceInChatViews:view atIndex:index withClass:[JVChatTranscript class]];
}

#pragma mark -

- (NSArray *) chatConsoles {
	return [self chatViewsWithClass:[JVChatConsole class]];
}

- (id <JVChatViewController>) valueInChatConsolesAtIndex:(unsigned) index {
	return [self valueInChatViewsAtIndex:index withClass:[JVChatConsole class]];
}

- (id <JVChatViewController>) valueInChatConsolesWithUniqueID:(id) identifier {
	return [self valueInChatViewsWithUniqueID:identifier andClass:[JVChatConsole class]];
}

- (id <JVChatViewController>) valueInChatConsolesWithName:(NSString *) name {
	return [self valueInChatViewsWithName:name andClass:[JVChatConsole class]];
}

- (void) addInChatConsoles:(id <JVChatViewController>) view {
	[self addInChatViews:view withClass:[JVChatConsole class]];
}

- (void) insertInChatConsoles:(id <JVChatViewController>) view {
	[self addInChatViews:view withClass:[JVChatConsole class]];
}

- (void) insertInChatConsoles:(id <JVChatViewController>) view atIndex:(unsigned) index {
	[self insertInChatViews:view atIndex:index withClass:[JVChatConsole class]];
}

- (void) removeFromChatConsolesAtIndex:(unsigned) index {
	[self removeFromChatViewsAtIndex:index withClass:[JVChatConsole class]];
}

- (void) replaceInChatConsoles:(id <JVChatViewController>) view atIndex:(unsigned) index {
	[self replaceInChatViews:view atIndex:index withClass:[JVChatConsole class]];
}

#pragma mark -

- (NSArray *) indicesOfObjectsByEvaluatingRangeSpecifier:(NSRangeSpecifier *) specifier {
	NSString *key = [specifier key];
	
	if( [key isEqual:@"views"] || [key isEqual:@"chatRooms"] || [key isEqual:@"directChats"] || [key isEqual:@"chatConsoles"] || [key isEqual:@"chatTranscripts"] ) {
		NSScriptObjectSpecifier *startSpec = [specifier startSpecifier];
		NSScriptObjectSpecifier *endSpec = [specifier endSpecifier];
		NSString *startKey = [startSpec key];
		NSString *endKey = [endSpec key];
		NSArray *chatViews = [self views];
		
		if( ! startSpec && ! endSpec ) return nil;
		
		if( ! [chatViews count] ) [NSArray array];
		
		if( ( ! startSpec || [startKey isEqual:@"views"] || [startKey isEqual:@"chatRooms"] || [startKey isEqual:@"directChats"] || [startKey isEqual:@"chatConsoles"] || [startKey isEqual:@"chatTranscripts"] ) && ( ! endSpec || [endKey isEqual:@"views"] || [endKey isEqual:@"chatRooms"] || [endKey isEqual:@"directChats"] || [endKey isEqual:@"chatConsoles"] || [endKey isEqual:@"chatTranscripts"] ) ) {
			int startIndex = 0;
			int endIndex = 0;
			
			// The strategy here is going to be to find the index of the start and stop object in the full graphics array, regardless of what its key is.  Then we can find what we're looking for in that range of the graphics key (weeding out objects we don't want, if necessary).
			// First find the index of the first start object in the graphics array
			if( startSpec ) {
				id startObject = [startSpec objectsByEvaluatingSpecifier];
				if( [startObject isKindOfClass:[NSArray class]] ) {
					if( ! [startObject count] ) startObject = nil;
					else startObject = [startObject objectAtIndex:0];
				}
				if( ! startObject ) return nil;
				startIndex = [chatViews indexOfObjectIdenticalTo:startObject];
				if( startIndex == NSNotFound ) return nil;
			}
			
			// Now find the index of the last end object in the graphics array
			if( endSpec ) {
				id endObject = [endSpec objectsByEvaluatingSpecifier];
				if( [endObject isKindOfClass:[NSArray class]] ) {
					if( ! [endObject count] ) endObject = nil;
					else endObject = [endObject lastObject];
				}
				if( ! endObject ) return nil;
				endIndex = [chatViews indexOfObjectIdenticalTo:endObject];
				if( endIndex == NSNotFound ) return nil;
			} else endIndex = ( [chatViews count] - 1 );
			
			// Accept backwards ranges gracefully
			if( endIndex < startIndex ) {
				int temp = endIndex;
				endIndex = startIndex;
				startIndex = temp;
			}
			
			// Now startIndex and endIndex specify the end points of the range we want within the main array.
			// We will traverse the range and pick the objects we want.
			// We do this by getting each object and seeing if it actually appears in the real key that we are trying to evaluate in.
			NSMutableArray *result = [NSMutableArray array];
			BOOL keyIsGeneric = [key isEqualToString:@"views"];
			NSArray *rangeKeyObjects = ( keyIsGeneric ? nil : [self valueForKey:key] );
			unsigned curKeyIndex = 0, i = 0;
			id obj = nil;
			
			for( i = startIndex; i <= endIndex; i++ ) {
				if( keyIsGeneric ) {
					[result addObject:[NSNumber numberWithInt:i]];
				} else {
					obj = [chatViews objectAtIndex:i];
					curKeyIndex = [rangeKeyObjects indexOfObjectIdenticalTo:obj];
					if( curKeyIndex != NSNotFound )
						[result addObject:[NSNumber numberWithInt:curKeyIndex]];
				}
			}
			
			return result;
		}
	}
	
	return nil;
}

- (NSArray *) indicesOfObjectsByEvaluatingRelativeSpecifier:(NSRelativeSpecifier *) specifier {
	NSString *key = [specifier key];
	
	if( [key isEqual:@"views"] || [key isEqual:@"chatRooms"] || [key isEqual:@"directChats"] || [key isEqual:@"chatConsoles"] || [key isEqual:@"chatTranscripts"] ) {
		NSScriptObjectSpecifier *baseSpec = [specifier baseSpecifier];
		NSString *baseKey = [baseSpec key];
		NSArray *chatViews = [self views];
		NSRelativePosition relPos = [specifier relativePosition];
		
		if( ! baseSpec ) return nil;
		
		if( ! [chatViews count] ) return [NSArray array];
		
		if( [baseKey isEqual:@"views"] || [baseKey isEqual:@"chatRooms"] || [baseKey isEqual:@"directChats"] || [baseKey isEqual:@"chatConsoles"] || [baseKey isEqual:@"chatTranscripts"] ) {
			int baseIndex = 0;
			
			// The strategy here is going to be to find the index of the base object in the full graphics array, regardless of what its key is.  Then we can find what we're looking for before or after it.
			// First find the index of the first or last base object in the master array
			// Base specifiers are to be evaluated within the same container as the relative specifier they are the base of. That's this container.
			
			id baseObject = [baseSpec objectsByEvaluatingWithContainers:self];
			if( [baseObject isKindOfClass:[NSArray class]] ) {
				int baseCount = [baseObject count];
				if( baseCount ) {
					if( relPos == NSRelativeBefore ) baseObject = [baseObject objectAtIndex:0];
					else baseObject = [baseObject objectAtIndex:( baseCount - 1 )];
				} else baseObject = nil;
			}
			
			if( ! baseObject ) return nil;
			
			baseIndex = [chatViews indexOfObjectIdenticalTo:baseObject];
			if( baseIndex == NSNotFound ) return nil;
			
			// Now baseIndex specifies the base object for the relative spec in the master array.
			// We will start either right before or right after and look for an object that matches the type we want.
			// We do this by getting each object and seeing if it actually appears in the real key that we are trying to evaluate in.
			NSMutableArray *result = [NSMutableArray array];
			BOOL keyIsGeneric = [key isEqual:@"views"];
			NSArray *relKeyObjects = ( keyIsGeneric ? nil : [self valueForKey:key] );
			unsigned curKeyIndex = 0, viewCount = [chatViews count];
			id obj = nil;
			
			if( relPos == NSRelativeBefore ) baseIndex--;
			else baseIndex++;
			
			while( baseIndex >= 0 && baseIndex < viewCount ) {
				if( keyIsGeneric ) {
					[result addObject:[NSNumber numberWithInt:baseIndex]];
					break;
				} else {
					obj = [chatViews objectAtIndex:baseIndex];
					curKeyIndex = [relKeyObjects indexOfObjectIdenticalTo:obj];
					if( curKeyIndex != NSNotFound ) {
						[result addObject:[NSNumber numberWithInt:curKeyIndex]];
						break;
					}
				}
				
				if( relPos == NSRelativeBefore ) baseIndex--;
				else baseIndex++;
			}
			
			return result;
		}
	}
	
	return nil;
}

- (NSArray *) indicesOfObjectsByEvaluatingObjectSpecifier:(NSScriptObjectSpecifier *) specifier {
	if( [specifier isKindOfClass:[NSRangeSpecifier class]] ) {
		return [self indicesOfObjectsByEvaluatingRangeSpecifier:(NSRangeSpecifier *) specifier];
	} else if( [specifier isKindOfClass:[NSRelativeSpecifier class]] ) {
		return [self indicesOfObjectsByEvaluatingRelativeSpecifier:(NSRelativeSpecifier *) specifier];
	}
	return nil;
}
@end