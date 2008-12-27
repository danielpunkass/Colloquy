#import "CQDirectChatController.h"

@class CQChatUserListViewController;

@interface CQChatRoomController : CQDirectChatController {
	NSMutableArray *_orderedMembers;
	BOOL _membersNeedSorted;
	NSUInteger _joinCount;
	CQChatUserListViewController *_currentUserListViewController;
}
- (MVChatRoom *) room;

- (void) joined;
- (void) close;
@end
