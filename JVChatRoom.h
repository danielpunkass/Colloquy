#import "JVDirectChat.h"
#import <AppKit/NSNibDeclarations.h>

@class NSTextView;
@class WebView;
@class NSMutableDictionary;
@class NSMutableArray;
@class NSData;
@class NSString;
@class JVChatRoomMember;

@interface JVChatRoom : JVDirectChat {
	@protected
	IBOutlet NSTextView *topicLine;
	NSMutableDictionary *_members;
	NSMutableArray *_sortedMembers;
	NSAttributedString *_topicAttributed;
	NSData *_topic;
	NSString *_topicAuth;
	BOOL _invalidateMembers;
	BOOL _kickedFromRoom;
}
- (void) addMemberToChat:(NSString *) member asPreviousMember:(BOOL) previous;
- (void) removeChatMember:(NSString *) member withReason:(NSData *) reason;
- (void) changeChatMember:(NSString *) member to:(NSString *) nick;

- (void) promoteChatMember:(NSString *) member by:(NSString *) by;
- (void) demoteChatMember:(NSString *) member by:(NSString *) by;
- (void) voiceChatMember:(NSString *) member by:(NSString *) by;
- (void) devoiceChatMember:(NSString *) member by:(NSString *) by;

- (void) chatMember:(NSString *) member kickedBy:(NSString *) by forReason:(NSData *) reason;
- (void) kickedFromChatBy:(NSString *) by forReason:(NSData *) reason;

- (void) changeTopic:(NSData *) topic by:(NSString *) author;
- (NSAttributedString *) topic;

- (JVChatRoomMember *) chatRoomMemberWithName:(NSString *) name;
@end

@interface NSObject (MVChatPluginRoomSupport)
- (BOOL) processUserCommand:(NSString *) command withArguments:(NSAttributedString *) arguments toRoom:(JVChatRoom *) room;

- (void) processMessage:(NSMutableData *) message asAction:(BOOL) action fromMember:(JVChatRoomMember *) member inRoom:(JVChatRoom *) room;
- (void) processMessage:(NSMutableAttributedString *) message asAction:(BOOL) action toRoom:(JVChatRoom *) room;
@end