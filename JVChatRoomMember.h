#import <Foundation/NSObject.h>
#import "JVChatWindowController.h"

@class JVChatRoom;
@class NSString;
@class MVChatConnection;
@class JVBuddy;

@interface JVChatRoomMember : NSObject <JVChatListItem> {
	JVChatRoom *_parent;
	NSString *_nickname;
	NSString *_address;
	NSString *_realName;
	JVBuddy *_buddy;
	BOOL _operator;
	BOOL _halfOperator;
	BOOL _serverOperator;
	BOOL _voice;
}
- (id) initWithRoom:(JVChatRoom *) room andNickname:(NSString *) name;

- (NSComparisonResult) compare:(JVChatRoomMember *) member;
- (NSComparisonResult) compareUsingStatus:(JVChatRoomMember *) member;
- (NSComparisonResult) compareUsingBuddyStatus:(JVChatRoomMember *) member;

- (MVChatConnection *) connection;
- (NSString *) nickname;
- (NSString *) realName;
- (NSString *) address;
- (JVBuddy *) buddy;

- (BOOL) voice;
- (BOOL) operator;
- (BOOL) halfOperator;
- (BOOL) serverOperator;
- (BOOL) isLocalUser;

- (IBAction) startChat:(id) sender;
- (IBAction) sendFile:(id) sender;
- (IBAction) addBuddy:(id) sender;

- (IBAction) toggleOperatorStatus:(id) sender;
- (IBAction) toggleVoiceStatus:(id) sender;
- (IBAction) kick:(id) sender;
- (IBAction) ban:(id) sender;
@end

#pragma mark -

@interface JVChatRoomMember (JVChatRoomMemberScripting) <JVChatListItemScripting>
- (NSNumber *) uniqueIdentifier;
@end