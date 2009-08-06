#import "CQWelcomeNavigationController.h"

#import "CQColloquyApplication.h"
#import "CQConnectionsController.h"
#import "CQHelpTopicsViewController.h"
#import "CQWelcomeViewController.h"

@implementation CQWelcomeNavigationController
- (id) init {
	if (!(self = [super init]))
		return nil;

	self.delegate = self;

	return self;
}

- (void) dealloc {
	[_rootViewController release];

	[super dealloc];
}

#pragma mark -

@synthesize shouldShowOnlyHelpTopics = _shouldShowOnlyHelpTopics;

#pragma mark -

- (void) viewDidLoad {
	[super viewDidLoad];

	if (_shouldShowOnlyHelpTopics && !_rootViewController)
		_rootViewController = [[CQHelpTopicsViewController alloc] init];
	else if (!_rootViewController)
		_rootViewController = [[CQWelcomeViewController alloc] init];

	UIBarButtonItem *doneItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close:)];
	_rootViewController.navigationItem.rightBarButtonItem = doneItem;
	[doneItem release];

	[self pushViewController:_rootViewController animated:NO];
}

- (void) viewWillAppear:(BOOL) animated {
	[super viewWillAppear:animated];

	_previousStatusBarStyle = [UIApplication sharedApplication].statusBarStyle;

	[[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleDefault animated:animated];
}

- (void) viewWillDisappear:(BOOL) animated {
	[super viewWillDisappear:animated];

	[[UIApplication sharedApplication] setStatusBarStyle:_previousStatusBarStyle animated:animated];
}

#pragma mark -

- (void) close:(id) sender {
	[self.view endEditing:YES];

	if (!_shouldShowOnlyHelpTopics)
		[CQColloquyApplication sharedApplication].tabBarController.selectedViewController = [CQConnectionsController defaultController];

	[self dismissModalViewControllerAnimated:YES];
}
@end
