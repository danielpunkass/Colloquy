#import <Foundation/NSObject.h>
#import <AppKit/NSNibDeclarations.h>
#import "JVChatWindowController.h"

@interface JVChatRoomMember : NSObject <JVChatListItem> {
	id <JVChatListItem> _parent;
	NSString *_memberName;
	BOOL _operator;
	BOOL _voice;
}
- (void) setParent:(id <JVChatListItem>) parent;

- (void) setMemberName:(NSString *) name;
- (NSString *) memberName;

- (void) setVoice:(BOOL) voice;
- (void) setOperator:(BOOL) operator;	
@end
