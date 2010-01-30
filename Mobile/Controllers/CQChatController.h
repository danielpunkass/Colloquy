#import <ChatCore/MVIRCChatRoom.h>

@class CQChatListViewController;
@class CQChatNavigationController;
@class CQChatRoomController;
@class CQDirectChatController;
@class CQFileTransferController;
@class MVChatConnection;
@class MVChatUser;
@class MVDirectChatConnection;
@class MVFileTransfer;
@protocol CQChatViewController;

extern NSString *CQChatControllerAddedChatViewControllerNotification;
extern NSString *CQChatControllerChangedTotalImportantUnreadCountNotification;

@interface CQChatController : NSObject <UIActionSheetDelegate, UIAlertViewDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate> {
	@protected
	NSMutableArray *_chatControllers;
	CQChatNavigationController *_chatNavigationController;
	id <CQChatViewController> _nextController;
	MVChatConnection *_nextRoomConnection;
	NSInteger _totalImportantUnreadCount;
#if ENABLE(FILE_TRANSFERS)
	MVChatUser *_fileUser;
	UIImage *_transferImage;
	BOOL _png;
#endif
}
+ (CQChatController *) defaultController;

@property (nonatomic, readonly) CQChatNavigationController *chatNavigationController;

@property (nonatomic, readonly) NSArray *chatViewControllers;

@property (nonatomic) NSInteger totalImportantUnreadCount;

- (NSDictionary *) persistentStateForConnection:(MVChatConnection *) connection;
- (void) restorePersistentState:(NSDictionary *) state forConnection:(MVChatConnection *) connection;

- (void) showNewChatActionSheet:(id) sender;

- (void) showChatControllerWhenAvailableForRoomNamed:(NSString *) room andConnection:(MVChatConnection *) connection;
- (void) showChatControllerForUserNicknamed:(NSString *) nickname andConnection:(MVChatConnection *) connection;
- (void) showChatController:(id <CQChatViewController>) controller animated:(BOOL) animated;
- (void) showPendingChatControllerAnimated:(BOOL) animated;

#if ENABLE(FILE_TRANSFERS)
- (void) showFilePickerWithUser:(MVChatUser *) user;
#endif

- (void) joinSupportRoom;

- (NSArray *) chatViewControllersForConnection:(MVChatConnection *) connection;
- (NSArray *) chatViewControllersOfClass:(Class) class;
- (NSArray *) chatViewControllersKindOfClass:(Class) class;

- (CQChatRoomController *) chatViewControllerForRoom:(MVChatRoom *) room ifExists:(BOOL) exists;
- (CQDirectChatController *) chatViewControllerForUser:(MVChatUser *) user ifExists:(BOOL) exists;
- (CQDirectChatController *) chatViewControllerForUser:(MVChatUser *) user ifExists:(BOOL) exists userInitiated:(BOOL) requested;
- (CQDirectChatController *) chatViewControllerForDirectChatConnection:(MVDirectChatConnection *) connection ifExists:(BOOL) exists;

- (BOOL) connectionHasAChatRoom:(MVChatConnection *) connection;
- (BOOL) connectionHasAPrivateChat:(MVChatConnection *) connection;

#if ENABLE(FILE_TRANSFERS)
- (CQFileTransferController *) chatViewControllerForFileTransfer:(MVFileTransfer *) transfer ifExists:(BOOL) exists;
#endif

- (void) closeViewController:(id) controller;
@end

@protocol CQChatViewController <NSObject>
@property (nonatomic, readonly) MVChatConnection *connection;
@property (nonatomic, readonly) id target;
@property (nonatomic, readonly) NSString *title;
@property (nonatomic, readonly) UIImage *icon;
@property (nonatomic, readonly) BOOL available;
@property (nonatomic, readonly) NSStringEncoding encoding;

@optional
- (id) initWithPersistentState:(NSDictionary *) state usingConnection:(MVChatConnection *) connection;
- (void) close;

@property (nonatomic, readonly) NSDictionary *persistentState;
@property (nonatomic, readonly) NSUInteger unreadCount;
@property (nonatomic, readonly) NSUInteger importantUnreadCount;
@end

@interface MVIRCChatRoom (CQChatControllerAdditions)
@property (nonatomic, readonly) NSString *displayName;
@end
