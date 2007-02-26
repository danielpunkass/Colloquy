#import "MVChatConnection.h"

extern NSString *MVDirectChatConnectionOfferNotification;

extern NSString *MVDirectChatConnectionDidConnectNotification;
extern NSString *MVDirectChatConnectionDidDisconnectNotification;
extern NSString *MVDirectChatConnectionErrorOccurredNotification;

extern NSString *MVDirectChatConnectionGotMessageNotification;

extern NSString *MVDirectChatConnectionErrorDomain;

typedef enum {
	MVDirectChatConnectionConnectedStatus = 'dcCo',
	MVDirectChatConnectionWaitingStatus = 'dcWa',
	MVDirectChatConnectionDisconnectedStatus = 'dcDs',
	MVDirectChatConnectionErrorStatus = 'dcEr'
} MVDirectChatConnectionStatus;

@class MVDirectClientConnection;
@class MVChatUser;

@interface MVDirectChatConnection : NSObject {
@private
	MVDirectClientConnection *_directClientConnection;
	MVChatMessageFormat _outgoingChatFormat;
	NSStringEncoding _encoding;
	NSHost *_host;
	NSHost *_connectedHost;
	BOOL _passive;
	BOOL _localRequest;
	unsigned short _port;
	unsigned int _passiveId;
	MVChatUser *_user;
	MVDirectChatConnectionStatus _status;
	NSError *_lastError;
	unsigned int _hash;
	BOOL _releasing;
}
+ (id) directChatConnectionWithUser:(MVChatUser *) user passively:(BOOL) passive;

- (BOOL) isPassive;
- (MVDirectChatConnectionStatus) status;

- (MVChatUser *) user;
- (NSHost *) host;
- (NSHost *) connectedHost;
- (unsigned short) port;

- (void) initiate;
- (void) disconnect;

- (void) setEncoding:(NSStringEncoding) encoding;
- (NSStringEncoding) encoding;

- (void) setOutgoingChatFormat:(MVChatMessageFormat) format;
- (MVChatMessageFormat) outgoingChatFormat;

- (void) sendMessage:(NSAttributedString *) message withEncoding:(NSStringEncoding) encoding asAction:(BOOL) action;
- (void) sendMessage:(NSAttributedString *) message withEncoding:(NSStringEncoding) encoding withAttributes:(NSDictionary *)attributes;
@end
