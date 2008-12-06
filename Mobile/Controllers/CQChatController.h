@class CQChatRoomController;
@class CQChatListViewController;
@class CQDirectChatController;
@class MVChatConnection;
@class MVChatRoom;
@class MVChatUser;
@class MVDirectChatConnection;
@protocol CQChatViewController;

@interface CQChatController : UINavigationController <UINavigationControllerDelegate> {
	@private
	NSMutableArray *_chatControllers;
	CQChatListViewController *_chatListViewController;
	id <CQChatViewController> _nextController; 
}
+ (CQChatController *) defaultController;

@property (nonatomic, readonly) NSArray *chatViewControllers;

- (void) showChatController:(id <CQChatViewController>) controller animated:(BOOL) animated;

- (NSArray *) chatViewControllersForConnection:(MVChatConnection *) connection;
- (NSArray *) chatViewControllersOfClass:(Class) class;
- (NSArray *) chatViewControllersKindOfClass:(Class) class;

- (CQChatRoomController *) chatViewControllerForRoom:(MVChatRoom *) room ifExists:(BOOL) exists;
- (CQDirectChatController *) chatViewControllerForUser:(MVChatUser *) user ifExists:(BOOL) exists;
- (CQDirectChatController *) chatViewControllerForUser:(MVChatUser *) user ifExists:(BOOL) exists userInitiated:(BOOL) requested;
- (CQDirectChatController *) chatViewControllerForDirectChatConnection:(MVDirectChatConnection *) connection ifExists:(BOOL) exists;

- (void) closeViewController:(id <CQChatViewController>) controller;
@end

@protocol CQChatViewController <NSObject>
@property (nonatomic, readonly) MVChatConnection *connection;
@property (nonatomic, readonly) id target;
@property (nonatomic, readonly) NSString *title;
@property (nonatomic, readonly) UIImage *icon;
@optional
- (void) close;
@end
