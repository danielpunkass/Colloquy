#import <AppKit/NSWindowController.h>
#import <AppKit/NSNibDeclarations.h>
#import "JVInspectorController.h"

@class NSTableView;
@class NSWindow;
@class NSPanel;
@class NSTextField;
@class NSButton;
@class NSComboBox;
@class NSString;
@class NSMutableArray;
@class MVChatConnection;
@class NSURL;

@interface MVConnectionsController : NSWindowController <JVInspectionDelegator> {
@private
	IBOutlet NSTableView *connections;
	IBOutlet NSWindow *editConnection;
	IBOutlet NSPanel *openConnection;
	IBOutlet NSPanel *joinRoom;
	IBOutlet NSPanel *messageUser;
	IBOutlet NSPanel *nicknameAuth;

	/* Nick Auth */
	IBOutlet NSTextField *authNickname;
	IBOutlet NSTextField *authAddress;
	IBOutlet NSTextField *authPassword;
	IBOutlet NSButton *authKeychain;

	/* New Connection */
	IBOutlet NSTextField *newNickname;
	IBOutlet NSTextField *newAddress;
	IBOutlet NSTextField *newPort;
	IBOutlet NSButton *newRemember;

	/* Join Room & Message User */
	IBOutlet NSComboBox *roomToJoin;
	IBOutlet NSTextField *roomPassword;
	IBOutlet NSTextField *userToMessage;

	NSString *_target;
	BOOL _targetRoom;
	NSMutableArray *_bookmarks;
	MVChatConnection *_passConnection;
}
+ (MVConnectionsController *) defaultManager;

- (IBAction) showConnectionManager:(id) sender;

- (IBAction) newConnection:(id) sender;
- (IBAction) conenctNewConnection:(id) sender;

- (IBAction) messageUser:(id) sender;
- (IBAction) joinRoom:(id) sender;

- (IBAction) sendPassword:(id) sender;

- (void) setAutoConnect:(BOOL) autoConnect forConnection:(MVChatConnection *) connection;
- (BOOL) autoConnectForConnection:(MVChatConnection *) connection;

- (void) setJoinRooms:(NSArray *) rooms forConnection:(MVChatConnection *) connection;
- (NSArray *) joinRoomsForConnection:(MVChatConnection *) connection;

- (void) addConnection:(MVChatConnection *) connection keepBookmark:(BOOL) keep;
- (void) handleURL:(NSURL *) url andConnectIfPossible:(BOOL) connect;
@end
