#import <Cocoa/Cocoa.h>
#import "JVChatController.h"
#import "JVTabbedChatWindowController.h"
#import "AICustomTabsView.h"
#import "JVChatTabItem.h"

@interface JVChatWindowController (JVChatWindowControllerPrivate)
- (void) _refreshSelectionMenu;
- (void) _refreshWindow;
- (void) _refreshWindowTitle;
- (void) _refreshList;
@end

#pragma mark -

@interface JVTabbedChatWindowController (JVTabbedChatWindowControllerPrivate)
- (void) _supressTabBarHiding:(BOOL) supress;
- (void) _resizeTabBarTimer:(NSTimer *) inTimer;
- (BOOL) _resizeTabBarAbsolute:(BOOL) absolute;
@end

#pragma mark -

@interface AICustomTabsView (AICustomTabsViewPrivate)
- (void) smoothlyArrangeTabs;
@end

#pragma mark -

@implementation JVTabbedChatWindowController
+ (void) initialize {
	unichar left = NSLeftArrowFunctionKey;
	unichar right = NSRightArrowFunctionKey;

	NSMenu *windowMenu = [[[[NSApplication sharedApplication] mainMenu] itemWithTag:5] submenu];
	int index = [windowMenu indexOfItemWithTarget:nil andAction:@selector( selectPreviousPanel: )];
	id item = [windowMenu itemAtIndex:index];
	[item setKeyEquivalent:[NSString stringWithCharacters:&left length:1]];

	windowMenu = [[[[NSApplication sharedApplication] mainMenu] itemWithTag:5] submenu];
	index = [windowMenu indexOfItemWithTarget:nil andAction:@selector( selectPreviousActivePanel: )];
	item = [windowMenu itemAtIndex:index];
	[item setKeyEquivalent:[NSString stringWithCharacters:&left length:1]];

	windowMenu = [[[[NSApplication sharedApplication] mainMenu] itemWithTag:5] submenu];
	index = [windowMenu indexOfItemWithTarget:nil andAction:@selector( selectNextPanel: )];
	item = [windowMenu itemAtIndex:index];
	[item setKeyEquivalent:[NSString stringWithCharacters:&right length:1]];

	windowMenu = [[[[NSApplication sharedApplication] mainMenu] itemWithTag:5] submenu];
	index = [windowMenu indexOfItemWithTarget:nil andAction:@selector( selectNextActivePanel: )];
	item = [windowMenu itemAtIndex:index];
	[item setKeyEquivalent:[NSString stringWithCharacters:&right length:1]];

	[super initialize];	
}

- (id) init {
	return ( self = [self initWithWindowNibName:@"JVTabbedChatWindow"] );
}

- (id) initWithWindowNibName:(NSString *) windowNibName {
	if( ( self = [super initWithWindowNibName:windowNibName] ) ) {
		_tabItems = [[NSMutableArray array] retain];
		_tabIsShowing = YES;
		_supressHiding = NO;
		_autoHideTabBar = YES;
		_forceTabBarVisible = -1;
	}
	return self;
}

- (void) windowDidLoad {
	_tabHeight = NSHeight( [customTabsView frame] );

	[super windowDidLoad];

    // Remove any tabs from our tab view, it needs to start out empty
    while( [tabView numberOfTabViewItems] > 0 )
        [tabView removeTabViewItem:[tabView tabViewItemAtIndex:0]];

	[chatViewsOutlineView setRefusesFirstResponder:NO];
	[chatViewsOutlineView setAllowsEmptySelection:YES];

	[[self window] registerForDraggedTypes:[NSArray arrayWithObjects:TAB_CELL_IDENTIFIER, nil]];

	[self updateTabBarVisibilityAndAnimate:NO];

	[[self window] useOptimizedDrawing:YES];
}

#pragma mark -

- (void) insertChatViewController:(id <JVChatViewController>) controller atIndex:(unsigned int) index {
	NSParameterAssert( controller != nil );
	NSAssert1( ! [_views containsObject:controller], @"%@ already added.", controller );
	NSAssert( index >= 0 && index <= [_views count], @"Index is beyond bounds." );
	NSAssert( index >= 0 && index <= [_tabItems count], @"Index is beyond bounds." );

	[icon setImage:nil];

	JVChatTabItem *newTab = [[[JVChatTabItem alloc] initWithChatViewController:controller] autorelease];

	[_tabItems insertObject:newTab atIndex:index];
	[tabView insertTabViewItem:newTab atIndex:index];

	[super insertChatViewController:controller atIndex:index];
}

#pragma mark -

- (void) removeChatViewController:(id <JVChatViewController>) controller {
	unsigned int index = [_views indexOfObjectIdenticalTo:controller];
	[_tabItems removeObjectAtIndex:index];
	[tabView removeTabViewItem:[tabView tabViewItemAtIndex:index]];
	if( ! [_tabItems count] ) [icon setImage:[NSImage imageNamed:@"colloquy-alpha"]];
	[super removeChatViewController:controller];
}

- (void) removeAllChatViewControllers {
	[icon setImage:[NSImage imageNamed:@"colloquy-alpha"]];
	[_tabItems removeAllObjects];
	while( [tabView numberOfTabViewItems] > 0 )
        [tabView removeTabViewItem:[tabView tabViewItemAtIndex:0]];
	[super removeAllChatViewControllers];
}

#pragma mark -

- (void) replaceChatViewControllerAtIndex:(unsigned int) index withController:(id <JVChatViewController>) controller {
	NSParameterAssert( controller != nil );
	NSAssert1( ! [_views containsObject:controller], @"%@ is already a member of this window controller.", controller );
	NSAssert( index >= 0 && index <= [_views count], @"Index is beyond bounds." );
	NSAssert( index >= 0 && index <= [_tabItems count], @"Index is beyond bounds." );

	JVChatTabItem *newTab = [[[JVChatTabItem alloc] initWithChatViewController:controller] autorelease];

	[_tabItems replaceObjectAtIndex:index withObject:newTab];
	[tabView removeTabViewItem:[tabView tabViewItemAtIndex:index]];
	[tabView insertTabViewItem:newTab atIndex:index];

	[super replaceChatViewControllerAtIndex:index withController:controller];
}

#pragma mark -

- (void) showChatViewController:(id <JVChatViewController>) controller {
	NSAssert1( [_views containsObject:controller], @"%@ is not a member of this window controller.", controller );

	unsigned int index = [_views indexOfObjectIdenticalTo:controller];
	[tabView selectTabViewItemAtIndex:index];

	[self _refreshWindow];
	[self _refreshList];
}

- (void) reloadListItem:(id <JVChatListItem>) item andChildren:(BOOL) children {
	if( item == _activeViewController ) {
		[customTabsView smoothlyArrangeTabs];
		[customTabsView resetCursorTracking];
//		[customTabsView redisplayTabForTabViewItem:[tabView selectedTabViewItem]];
		[self _refreshList];
		[self _refreshWindowTitle];
	} else if( [_views containsObject:item] ) {
		[customTabsView smoothlyArrangeTabs];
		[customTabsView resetCursorTracking];
//		[customTabsView redisplayTabForTabViewItem:[tabView tabViewItemAtIndex:[_views indexOfObjectIdenticalTo:item]]];
	} else {
		[chatViewsOutlineView reloadItem:item reloadChildren:( children && [chatViewsOutlineView isItemExpanded:item] ? YES : NO )];
		[chatViewsOutlineView sizeLastColumnToFit];
		if( item == [self selectedListItem] )
			[self _refreshSelectionMenu];
	}
}

#pragma mark -

- (id <JVInspection>) objectToInspect {
	if( [[chatViewsOutlineView window] firstResponder] == chatViewsOutlineView )
		return [super objectToInspect];
	if( [_activeViewController conformsToProtocol:@protocol( JVInspection )] )
		return (id <JVInspection>)_activeViewController;
	return nil;
}

- (IBAction) getInfo:(id) sender {
	if( [[chatViewsOutlineView window] firstResponder] == chatViewsOutlineView ) {
		[super getInfo:sender];
	} else if( [_activeViewController conformsToProtocol:@protocol( JVInspection )] && [_activeViewController conformsToProtocol:@protocol( JVInspection )] ) {
		if( [[[NSApplication sharedApplication] currentEvent] modifierFlags] & NSAlternateKeyMask )
			[JVInspectorController showInspector:_activeViewController];
		else [[JVInspectorController inspectorOfObject:(id <JVInspection>)_activeViewController] show:sender];
	}
}

#pragma mark -

- (BOOL) validateMenuItem:(NSMenuItem *) menuItem {
	if( [menuItem action] == @selector( toggleTabBarVisible: ) ) {
		if( ! _tabIsShowing ) {
			[menuItem setTitle:[NSString stringWithFormat:NSLocalizedString( @"Show Tab Bar", "show tab bar menu title" )]];
		} else {
			[menuItem setTitle:[NSString stringWithFormat:NSLocalizedString( @"Hide Tab Bar", "hide tab bar menu title" )]];
		}
		return YES;
	}
	return [super validateMenuItem:menuItem];
}

#pragma mark -

- (void) customTabView:(AICustomTabsView *) view didSelectTabViewItem:(NSTabViewItem *) tabViewItem {
	if( tabViewItem ) {
		[self _refreshWindow];
		[self _refreshList];
	}
}

- (void) customTabViewDidChangeNumberOfTabViewItems:(AICustomTabsView *) view {
	[self updateTabBarVisibilityAndAnimate:NO];
}

- (void) customTabViewDidChangeOrderOfTabViewItems:(AICustomTabsView *) view {
	[_views removeAllObjects];

	NSEnumerator *tabs = [[tabView tabViewItems] objectEnumerator];
	JVChatTabItem *tab = nil;
	while( ( tab = [tabs nextObject] ) )
		[_views addObject:[tab chatViewController]];
}

- (void) customTabView:(AICustomTabsView *) view closeTabViewItem:(NSTabViewItem *) tabViewItem {
	[[JVChatController defaultManager] disposeViewController:[(JVChatTabItem *)tabViewItem chatViewController]];
}

- (void) customTabView:(AICustomTabsView *) view didMoveTabViewItem:(NSTabViewItem *) tabViewItem toCustomTabView:(AICustomTabsView *) destTabView index:(int) index screenPoint:(NSPoint) screenPoint {
	id chatController = [(JVChatTabItem *)tabViewItem chatViewController];
	id oldWindowController = [chatController windowController];
	id newWindowController = [[destTabView window] windowController];

	if( oldWindowController != newWindowController ) {
		[chatController retain];
		[[chatController windowController] removeChatViewController:chatController];

		if( ! newWindowController ) {
			NSRect newFrame;
			newWindowController = [[JVChatController defaultManager] newChatWindowController];
			newFrame.origin = screenPoint;
			newFrame.size = [[oldWindowController window] frame].size;
			[[newWindowController window] setFrame:newFrame display:NO];
		}

		if( index > 0 ) [newWindowController insertChatViewController:chatController atIndex:index];
		else [newWindowController addChatViewController:chatController];
		[chatController release];
	}

	[self _supressTabBarHiding:NO];
}

- (NSMenu *) customTabView:(AICustomTabsView *) view menuForTabViewItem:(NSTabViewItem *) tabViewItem {
	if( [[(JVChatTabItem *)tabViewItem chatViewController] respondsToSelector:@selector( menu )] ) {
		[[self window] makeFirstResponder:[[_activeViewController view] nextKeyView]];
		return [[(JVChatTabItem *)tabViewItem chatViewController] menu];
	}

	return nil;
}

- (NSString *) customTabView:(AICustomTabsView *) view toolTipForTabViewItem:(NSTabViewItem *) tabViewItem {
	if( [[(JVChatTabItem *)tabViewItem chatViewController] respondsToSelector:@selector( toolTip )] )
		return [[(JVChatTabItem *)tabViewItem chatViewController] toolTip];
	return nil;
}

#pragma mark -

- (int) outlineView:(NSOutlineView *) outlineView numberOfChildrenOfItem:(id) item {
	if( item && [item respondsToSelector:@selector( numberOfChildren )] ) return [item numberOfChildren];
	else if( [_activeViewController respondsToSelector:@selector( numberOfChildren )] ) return [(id)_activeViewController numberOfChildren];
	else return 0;
}

- (id) outlineView:(NSOutlineView *) outlineView child:(int) index ofItem:(id) item {
	if( item ) {
		if( [item respondsToSelector:@selector( childAtIndex: )] )
			return [item childAtIndex:index];
		else return nil;
	} else return [(id)_activeViewController childAtIndex:index];
}

- (id) outlineView:(NSOutlineView *) outlineView objectValueForTableColumn:(NSTableColumn *) tableColumn byItem:(id) item {
	NSImage *ret = [[[item icon] copy] autorelease];
	[ret setScalesWhenResized:YES];
	[ret setSize:NSMakeSize( 16., 16. )];
	return ret;
}

- (BOOL) outlineView:(NSOutlineView *) outlineView shouldCollapseItem:(id) item {
	return YES;
}

- (int) outlineView:(NSOutlineView *) outlineView heightOfRow:(int) row {
	return 18;
}

#pragma mark -
#pragma mark Tab Bar Visibility toggle

// Toggles whether we should hide or show the tab bar
- (IBAction) toggleTabBarVisible:(id) sender {
	if( _forceTabBarVisible < 0 ) {
		if( _tabIsShowing ) _forceTabBarVisible = 0;
		else _forceTabBarVisible = 1;
	} else if( ! _forceTabBarVisible ) _forceTabBarVisible = 1;
	else if( _forceTabBarVisible > 0 ) _forceTabBarVisible = 0;

	[self updateTabBarVisibilityAndAnimate:NO];
}

// Update the visibility of our tab bar (tab bar is visible if there are 2 or more tabs present)
- (void) updateTabBarVisibilityAndAnimate:(BOOL) animate {
	if( tabView ) { // Ignore if our tabs haven't loaded yet
		BOOL shouldShowTabs = ( _supressHiding || ! _autoHideTabBar || ( [tabView numberOfTabViewItems] > 1 ) );

		if( _forceTabBarVisible != -1 ) shouldShowTabs = ( _forceTabBarVisible || _supressHiding );

		if( shouldShowTabs != _tabIsShowing ) {
			_tabIsShowing = shouldShowTabs;
			if( animate ) [self _resizeTabBarTimer:nil];
			else [self _resizeTabBarAbsolute:YES];
		}
	}    
}

// Drag entered, enable suppression
- (NSDragOperation) draggingEntered:(id <NSDraggingInfo>) sender {
	NSString *type = [[sender draggingPasteboard] availableTypeFromArray:[NSArray arrayWithObjects:TAB_CELL_IDENTIFIER, nil]];
	NSDragOperation	operation = NSDragOperationNone;

	if( ! sender || type ) {
		[self _supressTabBarHiding:YES]; // show the tab bar
		if( ! [[self window] isKeyWindow] ) [[self window] makeKeyAndOrderFront:nil]; // bring our window to the front
		operation = NSDragOperationPrivate;
	}

	return operation;
}

// Drag exited, disable suppression
- (void) draggingExited:(id <NSDraggingInfo>) sender {
	NSString *type = [[sender draggingPasteboard] availableTypeFromArray:[NSArray arrayWithObjects:TAB_CELL_IDENTIFIER, nil]];
	if( ! sender || type ) [self _supressTabBarHiding:NO]; // hide the tab bar
}
@end

#pragma mark -

@implementation JVTabbedChatWindowController (JVTabbedChatWindowControllerPrivate)
- (void) _supressTabBarHiding:(BOOL) supress {
	_supressHiding = supress; // temporarily suppress bar hiding
	[self updateTabBarVisibilityAndAnimate:NO];
}

// Smoothly resize the tab bar (calls itself with a timer until the tabbar is correctly positioned)
- (void) _resizeTabBarTimer:(NSTimer *) inTimer {
	// If the tab bar isn't at the right height, we set ourself to adjust it again
	if( inTimer == nil || ! [self _resizeTabBarAbsolute:NO] ) { //Do nothing when called from outside a timer.  This prevents the tabs from jumping when set from show to hide, and back rapidly.
		[NSTimer scheduledTimerWithTimeInterval:( 1. / 30. ) target:self selector:@selector( _resizeTabBarTimer: ) userInfo:nil repeats:NO];
	}
}

// Resize the tab bar towards it's desired height
- (BOOL) _resizeTabBarAbsolute:(BOOL) absolute {   
	NSSize tabSize = [customTabsView frame].size;
	double destHeight = 0.;
	NSRect newFrame = NSZeroRect;

	// determine the desired height
	destHeight = ( _tabIsShowing ? _tabHeight : 0. );

	// move the tab view's height towards this desired height
	int distance = ( destHeight - tabSize.height ) * 0.6;
	if( absolute || ( distance > -1 && distance < 1 ) ) distance = destHeight - tabSize.height;

	tabSize.height += distance;
	[customTabsView setFrameSize:tabSize];
	[customTabsView setNeedsDisplay:YES];

	// adjust other views
	newFrame = [tabView frame];
	newFrame.size.height -= distance;
	newFrame.origin.y += distance;
	[tabView setFrame:newFrame];
	[tabView setNeedsDisplay:YES];

	[[self window] displayIfNeeded];

	// return YES when the desired height is reached
	return ( tabSize.height == destHeight );
}

- (void) _refreshList {
	[super _refreshList];
	[customTabsView smoothlyArrangeTabs];
	[customTabsView resetCursorTracking];
}

- (void) _refreshWindow {
	id item = [(JVChatTabItem *)[tabView selectedTabViewItem] chatViewController];

	if( ( [item conformsToProtocol:@protocol( JVChatViewController )] && item != (id) _activeViewController ) || ( ! _activeViewController && [[item parent] conformsToProtocol:@protocol( JVChatViewController )] && ( item = [item parent] ) ) ) {
		id lastActive = _activeViewController;
		if( [_activeViewController respondsToSelector:@selector( willUnselect )] )
			[(NSObject *)_activeViewController willUnselect];
		if( [item respondsToSelector:@selector( willSelect )] )
			[(NSObject *)item willSelect];

		[_activeViewController autorelease];
		_activeViewController = [item retain];

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
@end