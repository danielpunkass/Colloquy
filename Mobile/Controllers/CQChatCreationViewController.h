@class CQChatEditViewController;

@interface CQChatCreationViewController : UINavigationController <UINavigationControllerDelegate> {
	CQChatEditViewController *_editViewController;
	BOOL _roomTarget;
}
@property (nonatomic, getter=isRoomTarget) BOOL roomTarget;
@end
