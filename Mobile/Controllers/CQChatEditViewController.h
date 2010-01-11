#import "CQPreferencesTableViewController.h"

@class MVChatConnection;

@interface CQChatEditViewController : CQPreferencesTableViewController {
	@protected
	BOOL _roomTarget;
	NSMutableArray *_sortedConnections;
	MVChatConnection *_selectedConnection;
	NSString *_name;
	NSString *_password;
}
@property (nonatomic, getter=isRoomTarget) BOOL roomTarget;
@property (nonatomic, retain) MVChatConnection *selectedConnection;
@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) NSString *password;

- (void) showRoomListFilteredWithSearchString:(NSString *) searchString;
@end
