@class MVChatConnection;

@interface CQConnectionEditViewController : UITableViewController <UIActionSheetDelegate> {
	@protected
	MVChatConnection *_connection;
	BOOL _newConnection;
}
@property (nonatomic, retain) MVChatConnection *connection;
@property (nonatomic, getter=isNewConnection) BOOL newConnection;
@end
