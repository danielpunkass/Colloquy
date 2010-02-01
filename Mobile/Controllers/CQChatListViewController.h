#import "CQChatTableCell.h"

@protocol CQChatViewController;

@interface CQChatListViewController : UITableViewController <UIActionSheetDelegate> {
	@protected
	UILongPressGestureRecognizer *_longPressGestureRecognizer;
	UIActionSheet *_currentChatViewActionSheet;
	id <UIActionSheetDelegate> _currentChatViewActionSheetDelegate;
	UITableViewCell *_highlightedTableViewCell;
	BOOL _active;
	BOOL _needsUpdate;
}
- (void) chatViewControllerAdded:(id) controller;

- (void) selectChatViewController:(id) controller animatedSelection:(BOOL) animatedSelection animatedScroll:(BOOL) animatedScroll;
@end
