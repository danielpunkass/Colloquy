@class MVChatConnection;

extern NSString *MVDownloadFileTransferOfferNotification;
extern NSString *MVFileTransferStartedNotification;
extern NSString *MVFileTransferFinishedNotification;
extern NSString *MVFileTransferErrorOccurredNotification;

extern NSString *MVFileTransferErrorDomain;

typedef enum {
	MVFileTransferDoneStatus = 'trDn',
	MVFileTransferNormalStatus = 'trNo',
	MVFileTransferHoldingStatus = 'trHo',
	MVFileTransferStoppedStatus = 'trSt',
	MVFileTransferErrorStatus = 'trEr'
} MVFileTransferStatus;

typedef enum {
	MVFileTransferConnectionError = -1,
	MVFileTransferFileCreationError = -2,
	MVFileTransferFileOpenError = -3,
	MVFileTransferAlreadyExistsError = -4,
	MVFileTransferUnexpectedlyEndedError = -5
} MVFileTransferError;

@interface MVFileTransfer : NSObject {
@protected
	unsigned long long _finalSize;
	unsigned long long _transfered;
	NSDate *_startDate;
	NSHost *_host;
	BOOL _passive;
	unsigned short _port;
	unsigned long long _startOffset;
	MVChatConnection *_connection;
	NSString *_user;
	MVFileTransferStatus _status;
	NSError *_lastError;
}
+ (void) setFileTransferPortRange:(NSRange) range;
+ (NSRange) fileTransferPortRange;

- (id) initWithUser:(NSString *) user fromConnection:(MVChatConnection *) connection;

- (BOOL) isUpload;
- (BOOL) isDownload;
- (BOOL) isPassive;
- (MVFileTransferStatus) status;
- (NSError *) lastError;

- (unsigned long long) finalSize;
- (unsigned long long) transfered;

- (NSDate *) startDate;
- (unsigned long long) startOffset;

- (NSHost *) host;
- (unsigned short) port;

- (MVChatConnection *) connection;
- (NSString *) user;

- (void) cancel;
@end

#pragma mark -

@interface MVUploadFileTransfer : MVFileTransfer {
@protected
	NSString *_source;
}
+ (id) transferWithSourceFile:(NSString *) path toUser:(NSString *) nickname onConnection:(MVChatConnection *) connection passively:(BOOL) passive;

- (NSString *) source;
@end

#pragma mark -

@interface MVDownloadFileTransfer : MVFileTransfer {
@protected
	NSString *_destination;
	NSString *_originalFileName;
}
- (void) setDestination:(NSString *) path renameIfFileExists:(BOOL) allow;
- (NSString *) destination;

- (NSString *) originalFileName;

- (void) reject;

- (void) accept;
- (void) acceptByResumingIfPossible:(BOOL) resume;
@end