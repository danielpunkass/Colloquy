@class MVChatConnection;

@interface CQConnectionsViewController : UITableViewController <UIActionSheetDelegate> {
	@protected
	NSTimer *_connectTimeUpdateTimer;
	BOOL _active;
}
- (void) addConnection:(MVChatConnection *) connection;
- (void) removeConnection:(MVChatConnection *) connection;
@end
