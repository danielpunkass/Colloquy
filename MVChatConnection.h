#import <Foundation/NSObject.h>
#import <AppKit/NSNibDeclarations.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/IOTypes.h>

#define MVURLEncodeString(t) ((NSString *)CFURLCreateStringByAddingPercentEscapes(NULL, (CFStringRef)(t), NULL, CFSTR(",;:/?@&$="), kCFStringEncodingUTF8))
#define MVURLDecodeString(t) ((NSString *)CFURLCreateStringByReplacingPercentEscapes(NULL, (CFStringRef)(t), NULL))

typedef enum {
	MVChatConnectionDisconnectedStatus = 0x0,
	MVChatConnectionConnectingStatus = 0x1,
	MVChatConnectionConnectedStatus = 0x2,
	MVChatConnectionSuspendedStatus = 0x3
} MVChatConnectionStatus;

extern NSString *MVChatConnectionWillConnectNotification;
extern NSString *MVChatConnectionDidConnectNotification;
extern NSString *MVChatConnectionDidNotConnectNotification;
extern NSString *MVChatConnectionWillDisconnectNotification;
extern NSString *MVChatConnectionDidDisconnectNotification;
extern NSString *MVChatConnectionDidGetErrorNotification;

extern NSString *MVChatConnectionNeedPasswordNotification;

extern NSString *MVChatConnectionGotPrivateMessageNotification;

extern NSString *MVChatConnectionBuddyIsOnlineNotification;
extern NSString *MVChatConnectionBuddyIsOfflineNotification;
extern NSString *MVChatConnectionBuddyIsAwayNotification;
extern NSString *MVChatConnectionBuddyIsUnawayNotification;
extern NSString *MVChatConnectionBuddyIsIdleNotification;

extern NSString *MVChatConnectionGotUserInfoNotification;
extern NSString *MVChatConnectionGotRoomInfoNotification;

extern NSString *MVChatConnectionJoinedRoomNotification;
extern NSString *MVChatConnectionLeftRoomNotification;
extern NSString *MVChatConnectionUserJoinedRoomNotification;
extern NSString *MVChatConnectionUserLeftRoomNotification;
extern NSString *MVChatConnectionUserNicknameChangedNotification;
extern NSString *MVChatConnectionUserOppedInRoomNotification;
extern NSString *MVChatConnectionUserDeoppedInRoomNotification;
extern NSString *MVChatConnectionUserVoicedInRoomNotification;
extern NSString *MVChatConnectionUserDevoicedInRoomNotification;
extern NSString *MVChatConnectionUserKickedFromRoomNotification;
extern NSString *MVChatConnectionGotRoomMessageNotification;
extern NSString *MVChatConnectionGotRoomTopicNotification;

extern NSString *MVChatConnectionKickedFromRoomNotification;
extern NSString *MVChatConnectionInvitedToRoomNotification;

extern NSString *MVChatConnectionNicknameAcceptedNotification;
extern NSString *MVChatConnectionNicknameRejectedNotification;

extern NSString *MVChatConnectionFileTransferAvailableNotification;
extern NSString *MVChatConnectionFileTransferOfferedNotification;
extern NSString *MVChatConnectionFileTransferStartedNotification;
extern NSString *MVChatConnectionFileTransferFinishedNotification;
extern NSString *MVChatConnectionFileTransferErrorNotification;
extern NSString *MVChatConnectionFileTransferStatusNotification;

extern NSString *MVChatConnectionSubcodeRequestNotification;
extern NSString *MVChatConnectionSubcodeReplyNotification;

@class NSString;

@interface MVChatConnection : NSObject {
@private
	NSString *_nickname, *_npassword, *_password, *_server;
	unsigned short _port;
	MVChatConnectionStatus _status;
	void *_chatConnection;
	NSTimer *_firetalkSelectTimer;
	NSMutableArray *_joinList;
	NSMutableDictionary *_roomsCache;
	NSDate *_cachedDate;
	NSTimeInterval _backlogDelay;
	io_object_t _sleepNotifier;
	io_connect_t _powerConnection;
}
- (id) initWithURL:(NSURL *) url;
- (id) initWithServer:(NSString *) server port:(unsigned short) port user:(NSString *) nickname;

- (void) connect;
- (void) connectToServer:(NSString *) server onPort:(unsigned short) port asUser:(NSString *) nickname;
- (void) disconnect;

- (NSURL *) url;

- (void) setNickname:(NSString *) nickname;
- (NSString *) nickname;

- (void) setNicknamePassword:(NSString *) password;
- (NSString *) nicknamePassword;

- (void) setPassword:(NSString *) password;
- (NSString *) password;

- (void) setServer:(NSString *) server;
- (NSString *) server;

- (void) setServerPort:(unsigned short) port;
- (unsigned short) serverPort;

- (void) sendMessageToUser:(NSString *) user attributedMessage:(NSAttributedString *) message withEncoding:(NSStringEncoding) encoding asAction:(BOOL) action;
- (void) sendMessageToChatRoom:(NSString *) room attributedMessage:(NSAttributedString *) message withEncoding:(NSStringEncoding) encoding asAction:(BOOL) action;

- (void) sendFileToUser:(NSString *) user withFilePath:(NSString *) path;
- (void) acceptFileTransfer:(NSString *) identifier saveToPath:(NSString *) path resume:(BOOL) resume;
- (void) cancelFileTransfer:(NSString *) identifier;

- (void) joinChatForRoom:(NSString *) room;
- (void) partChatForRoom:(NSString *) room;

- (void) promoteMember:(NSString *) member inRoom:(NSString *) room;
- (void) demoteMember:(NSString *) member inRoom:(NSString *) room;
- (void) voiceMember:(NSString *) member inRoom:(NSString *) room;
- (void) devoiceMember:(NSString *) member inRoom:(NSString *) room;
- (void) kickMember:(NSString *) member inRoom:(NSString *) room forReason:(NSString *) reason;

- (void) addUserToNotificationList:(NSString *) user;
- (void) removeUserFromNotificationList:(NSString *) user;

- (void) fetchInformationForUser:(NSString *) user;

- (void) fetchRoomList;
- (void) fetchRoomListWithRooms:(NSArray *) rooms;
- (void) stopFetchingRoomList;
- (NSDictionary *) roomListResults;

- (void) setAwayStatusWithMessage:(NSString *) message;
- (void) clearAwayStatus;

- (BOOL) isConnected;
- (MVChatConnectionStatus) status;
@end
