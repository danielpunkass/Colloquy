#import "JVChatRoomMember.h"
#import "JVInspectorController.h"

@interface JVChatRoomMember (JVChatRoomMemberInspection) <JVInspection>
- (id <JVInspector>) inspector;
@end

@interface JVChatMemberInspector : NSObject <JVInspector> {
	IBOutlet NSView *view;
	IBOutlet NSImageView *image;
	IBOutlet NSTextField *nickname;
	IBOutlet NSProgressIndicator *progress;
	IBOutlet NSTextField *class;
	IBOutlet NSTextField *away;
	IBOutlet NSTextField *address;
	IBOutlet NSTextField *hostname;
	IBOutlet NSTextField *username;
	IBOutlet NSTextField *realName;
	IBOutlet NSTextField *server;
	IBOutlet NSTextField *rooms;
	IBOutlet NSTextField *connected;
	IBOutlet NSTextField *idle;
	IBOutlet NSTextField *ping;
	IBOutlet NSButton *sendPing;
	IBOutlet NSTextField *localTime;
	IBOutlet NSButton *requestTime;
	IBOutlet NSTextField *clientInfo;
	IBOutlet NSButton *requestInfo;
	JVChatRoomMember *_member;
	BOOL _localOnly;
	BOOL _nibLoaded;
	BOOL _classSet;
	BOOL _addressResolved;
	BOOL _whoisComplete;
}
- (id) initWithChatMember:(JVChatRoomMember *) member;

- (void) setFetchLocalServerInfoOnly:(BOOL) localOnly;

- (IBAction) sendPing:(id) sender;
- (IBAction) requestLocalTime:(id) sender;
- (IBAction) requestClientInfo:(id) sender;
@end
