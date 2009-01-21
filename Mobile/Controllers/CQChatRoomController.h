#import "CQDirectChatController.h"

@class CQChatUserListViewController;

@interface CQChatRoomController : CQDirectChatController {
	@protected
	NSMutableArray *_orderedMembers;
	BOOL _membersNeedSorted;
	BOOL _banListSynced;
	BOOL _joined;
	BOOL _parting;
	NSUInteger _joinCount;
	CQChatUserListViewController *_currentUserListViewController;
}
- (MVChatRoom *) room;

- (void) join;
- (void) part;

- (void) joined;
@end
