@protocol CQBrowserViewControllerDelegate;

extern NSString *CQColloquyApplicationDidRecieveDeviceTokenNotification;

@interface CQColloquyApplication : UIApplication <UIApplicationDelegate, UITabBarControllerDelegate, UISplitViewControllerDelegate, UIAlertViewDelegate> {
	@protected
	UIWindow *_mainWindow;
	UIViewController *_mainViewController;
	UIPopoverController *_connectionsPopoverController;
	UIBarButtonItem *_connectionsBarButtonItem;
	UIPopoverController *_colloquiesPopoverController;
	UIBarButtonItem *_colloquiesBarButtonItem;
	UIToolbar *_toolbar;
	NSDate *_launchDate;
	NSDate *_resumeDate;
	NSString *_deviceToken;
	NSUInteger _networkIndicatorStack;
	BOOL _showingTabBar;
}
+ (CQColloquyApplication *) sharedApplication;

- (void) showHelp:(id) sender;
- (void) showWelcome:(id) sender;
- (void) showConnections:(id) sender;
- (void) showColloquies:(id) sender;

- (void) dismissPopoversAnimated:(BOOL) animated;

- (BOOL) isSpecialApplicationURL:(NSURL *) url;
- (NSString *) applicationNameForURL:(NSURL *) url;

- (BOOL) openURL:(NSURL *) url usingBuiltInBrowser:(BOOL) openWithBrowser;
- (BOOL) openURL:(NSURL *) url usingBuiltInBrowser:(BOOL) openWithBrowser withBrowserDelegate:(id <CQBrowserViewControllerDelegate>) delegate;
- (BOOL) openURL:(NSURL *) url usingBuiltInBrowser:(BOOL) openWithBrowser withBrowserDelegate:(id <CQBrowserViewControllerDelegate>) delegate promptForExternal:(BOOL) prompt;

- (void) showActionSheet:(UIActionSheet *) sheet;
- (void) showActionSheet:(UIActionSheet *) sheet forSender:(id) sender animated:(BOOL) animated;

@property (nonatomic, readonly) UIViewController *mainViewController;
@property (nonatomic, readonly) UIViewController *modalViewController;

- (void) presentModalViewController:(UIViewController *) modalViewController animated:(BOOL) animated;
- (void) presentModalViewController:(UIViewController *) modalViewController animated:(BOOL) animated singly:(BOOL) singly;
- (void) dismissModalViewControllerAnimated:(BOOL) animated;

- (void) hideTabBarWithTransition:(BOOL) transition;
- (void) showTabBarWithTransition:(BOOL) transition;

- (BOOL) areNotificationBadgesAllowed;
- (BOOL) areNotificationSoundsAllowed;
- (BOOL) areNotificationAlertsAllowed;

- (void) registerForRemoteNotifications;

@property (nonatomic, readonly) NSDate *launchDate;
@property (nonatomic, retain) NSDate *resumeDate;

- (void) submitRunTime;

@property (nonatomic, readonly) NSSet *handledURLSchemes;
@property (nonatomic, readonly) NSString *deviceToken;
@property (nonatomic, readonly) NSArray *highlightWords;
@property (nonatomic, readonly) UIColor *tintColor;
@end
