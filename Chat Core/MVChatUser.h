#import <ChatCore/MVChatString.h>

typedef enum {
	MVChatRemoteUserType = 'remT',
	MVChatLocalUserType = 'locL',
	MVChatWildcardUserType = 'wilD'
} MVChatUserType;

typedef enum {
	MVChatUserUnknownStatus = 'uKnw',
	MVChatUserOfflineStatus = 'oflN',
	MVChatUserDetachedStatus = 'detA',
	MVChatUserAvailableStatus = 'avaL',
	MVChatUserAwayStatus = 'awaY'
} MVChatUserStatus;

typedef enum {
	MVChatUserNoModes = 0,
	MVChatUserInvisibleMode = 1 << 0
} MVChatUserMode;

extern NSString *MVChatUserKnownRoomsAttribute;
extern NSString *MVChatUserPictureAttribute;
extern NSString *MVChatUserPingAttribute;
extern NSString *MVChatUserLocalTimeAttribute;
extern NSString *MVChatUserClientInfoAttribute;
extern NSString *MVChatUserVCardAttribute;
extern NSString *MVChatUserServiceAttribute;
extern NSString *MVChatUserMoodAttribute;
extern NSString *MVChatUserStatusMessageAttribute;
extern NSString *MVChatUserPreferredLanguageAttribute;
extern NSString *MVChatUserPreferredContactMethodsAttribute;
extern NSString *MVChatUserTimezoneAttribute;
extern NSString *MVChatUserGeoLocationAttribute;
extern NSString *MVChatUserDeviceInfoAttribute;
extern NSString *MVChatUserExtensionAttribute;
extern NSString *MVChatUserPublicKeyAttribute;
extern NSString *MVChatUserServerPublicKeyAttribute;
extern NSString *MVChatUserDigitalSignatureAttribute;
extern NSString *MVChatUserServerDigitalSignatureAttribute;
extern NSString *MVChatUserBanServerAttribute;
extern NSString *MVChatUserBanAuthorAttribute;
extern NSString *MVChatUserBanDateAttribute;

extern NSString *MVChatUserNicknameChangedNotification;
extern NSString *MVChatUserStatusChangedNotification;
extern NSString *MVChatUserAwayStatusMessageChangedNotification;
extern NSString *MVChatUserIdleTimeUpdatedNotification;
extern NSString *MVChatUserModeChangedNotification;
extern NSString *MVChatUserInformationUpdatedNotification;
extern NSString *MVChatUserAttributeUpdatedNotification;

@class MVChatConnection;
@class MVUploadFileTransfer;

@interface MVChatUser : NSObject {
@protected
	MVChatConnection *_connection;
	id _uniqueIdentifier;
	NSString *_nickname;
	NSString *_realName;
	NSString *_username;
	NSString *_address;
	NSString *_serverAddress;
	NSData *_publicKey;
	NSString *_fingerprint;
	NSDate *_dateConnected;
	NSDate *_dateDisconnected;
	NSDate *_dateUpdated;
	NSData *_awayStatusMessage;
	NSMutableDictionary *_attributes;
	MVChatUserType _type;
	MVChatUserStatus _status;
	NSTimeInterval _idleTime;
	NSTimeInterval _lag;
	unsigned long _modes;
	unsigned int _hash;
	BOOL _identified;
	BOOL _serverOperator;
	BOOL _onlineNotificationSent;
}
+ (id) wildcardUserFromString:(NSString *) mask;
+ (id) wildcardUserWithNicknameMask:(NSString *) nickname andHostMask:(NSString *) host;
+ (id) wildcardUserWithFingerprint:(NSString *) fingerprint;

#if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_5
@property(readonly, ivar) MVChatConnection *connection;
@property(readonly, ivar) MVChatUserType type;

@property(readonly) BOOL remoteUser;
@property(readonly) BOOL localUser;
@property(readonly) BOOL wildcardUser;

@property(readonly) BOOL identified;
@property(readonly) BOOL serverOperator;
@property(readonly) BOOL watched;

@property(readonly, ivar) MVChatUserStatus status;
@property(readonly, ivar) NSData *awayStatusMessage;

@property(readonly, ivar) NSDate *dateConnected;
@property(readonly, ivar) NSDate *dateDisconnected;
@property(readonly, ivar) NSDate *dateUpdated;

@property(readonly, ivar) NSTimeInterval idleTime;
@property(readonly, ivar) NSTimeInterval lag;

@property(readonly) NSString *displayName;
@property(readonly) NSString *nickname;
@property(readonly) NSString *realName;
@property(readonly) NSString *username;
@property(readonly) NSString *address;
@property(readonly) NSString *serverAddress;

@property(readonly, ivar) id uniqueIdentifier;
@property(readonly, ivar) NSData *publicKey;
@property(readonly, ivar) NSString *fingerprint;

@property(readonly) unsigned long supportedModes;
@property(readonly, ivar) unsigned long modes;

@property(readonly) NSSet *supportedAttributes;
@property(readonly) NSDictionary *attributes;

#else

- (MVChatConnection *) connection;
- (MVChatUserType) type;

- (MVChatUserStatus) status;
- (NSData *) awayStatusMessage;

- (NSDate *) dateConnected;
- (NSDate *) dateDisconnected;
- (NSDate *) dateUpdated;

- (NSTimeInterval) idleTime;
- (NSTimeInterval) lag;

- (NSString *) displayName;
- (NSString *) nickname;
- (NSString *) realName;
- (NSString *) username;
- (NSString *) address;
- (NSString *) serverAddress;

- (id) uniqueIdentifier;
- (NSData *) publicKey;
- (NSString *) fingerprint;

- (unsigned long) supportedModes;
- (unsigned long) modes;

- (NSSet *) supportedAttributes;
- (NSDictionary *) attributes;
#endif

- (BOOL) isRemoteUser;
- (BOOL) isLocalUser;
- (BOOL) isWildcardUser;

- (BOOL) isIdentified;
- (BOOL) isServerOperator;

- (BOOL) isEqual:(id) object;
- (BOOL) isEqualToChatUser:(MVChatUser *) anotherUser;

- (NSComparisonResult) compare:(MVChatUser *) otherUser;
- (NSComparisonResult) compareByNickname:(MVChatUser *) otherUser;
- (NSComparisonResult) compareByUsername:(MVChatUser *) otherUser;
- (NSComparisonResult) compareByAddress:(MVChatUser *) otherUser;
- (NSComparisonResult) compareByRealName:(MVChatUser *) otherUser;
- (NSComparisonResult) compareByIdleTime:(MVChatUser *) otherUser;

- (void) refreshInformation;

- (void) refreshAttributes;
- (void) refreshAttributeForKey:(NSString *) key;

- (BOOL) hasAttributeForKey:(NSString *) key;
- (id) attributeForKey:(NSString *) key;
- (void) setAttribute:(id) attribute forKey:(id) key;

- (void) sendMessage:(MVChatString *) message withEncoding:(NSStringEncoding) encoding asAction:(BOOL) action;
- (void) sendMessage:(MVChatString *) message withEncoding:(NSStringEncoding) encoding withAttributes:(NSDictionary *) attributes;

- (MVUploadFileTransfer *) sendFile:(NSString *) path passively:(BOOL) passive;

- (void) sendSubcodeRequest:(NSString *) command withArguments:(id) arguments;
- (void) sendSubcodeReply:(NSString *) command withArguments:(id) arguments;
@end

#pragma mark -

@interface MVChatUser (MVChatUserScripting)
#if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_5
@property(readonly) NSString *scriptUniqueIdentifier;
@property(readonly) NSScriptObjectSpecifier *objectSpecifier;
#else
- (NSString *) scriptUniqueIdentifier;
- (NSScriptObjectSpecifier *) objectSpecifier;
#endif
@end
