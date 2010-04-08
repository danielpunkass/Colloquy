#import "CQChatPresentationController.h"

#import "CQChatController.h"

@implementation CQChatPresentationController
- (id) init {
	if (!(self = [super init]))
		return nil;

	_standardToolbarItems = [[NSArray alloc] init];

	return self;
}

- (void) dealloc {
	[_toolbar release];
	[_standardToolbarItems release];
	[_currentViewToolbarItems release];

    [super dealloc];
}

#pragma mark -

- (void) loadView {
	UIView *view = [[UIView alloc] initWithFrame:CGRectZero];
	self.view = view;

	view.backgroundColor = [UIColor scrollViewTexturedBackgroundColor];
	view.clipsToBounds = YES;

	_toolbar = [[UIToolbar alloc] initWithFrame:CGRectZero];
	_toolbar.layer.shadowOpacity = 1.;
	_toolbar.layer.shadowRadius = 3.;
	_toolbar.layer.shadowOffset = CGSizeMake(0., 0.);
	_toolbar.items = _standardToolbarItems;

	[_toolbar sizeToFit];

	[view addSubview:_toolbar];

	[view release];
}

- (void) viewDidUnload {
	[super viewDidUnload];

	[_toolbar release];
	_toolbar = nil;
}

- (BOOL) shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation) interfaceOrientation {
	return ![[NSUserDefaults standardUserDefaults] boolForKey:@"CQDisableLandscape"];
}

- (void) willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration {
	[_toolbar performSelector:@selector(sizeToFit) withObject:nil afterDelay:.08];
}

#pragma mark -

@synthesize currentViewToolbarItems = _currentViewToolbarItems;
@synthesize standardToolbarItems = _standardToolbarItems;

- (void) setStandardToolbarItems:(NSArray *) items {
	[self setStandardToolbarItems:items animated:YES];
}

- (void) setStandardToolbarItems:(NSArray *) items animated:(BOOL) animated {
	NSParameterAssert(items);

	id old = _standardToolbarItems;
	_standardToolbarItems = [items copy];
	[old release];

	NSArray *allItems = [_standardToolbarItems arrayByAddingObjectsFromArray:_currentViewToolbarItems];
	[_toolbar setItems:allItems animated:animated];
}

#pragma mark -

@synthesize topChatViewController = _topChatViewController;

- (void) reloadToolbar {
	id oldToolbarItems = _currentViewToolbarItems;
	_currentViewToolbarItems = [_topChatViewController.currentViewToolbarItems retain];
	[oldToolbarItems release];

	[self setStandardToolbarItems:_standardToolbarItems animated:YES];	
}

- (void) setTopChatViewController:(id <CQChatViewController>) chatViewController {
	if (chatViewController == _topChatViewController)
		return;

	UIViewController <CQChatViewController> *oldViewController = _topChatViewController;

	if (oldViewController) {
		[oldViewController viewWillDisappear:NO];
		if ([oldViewController respondsToSelector:@selector(dismissPopoversAnimated:)])
			[oldViewController dismissPopoversAnimated:NO];
		[oldViewController.view removeFromSuperview];
		[oldViewController viewDidDisappear:NO];
	}

	_topChatViewController = [chatViewController retain];
	[oldViewController release];

	if (!_topChatViewController)
		return;

	UIView *view = _topChatViewController.view;

	CGRect frame = self.view.bounds;
	frame.origin.y += _toolbar.frame.size.height;
	frame.size.height -= _toolbar.frame.size.height;
	frame.size.width = [UIScreen mainScreen].applicationFrame.size.width;
	view.frame = frame;

	[self reloadToolbar];

	[_topChatViewController viewWillAppear:NO];
	[self.view insertSubview:view aboveSubview:_toolbar];
	[_topChatViewController viewDidAppear:NO];
}
@end
