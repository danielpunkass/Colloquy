#import <Foundation/NSObject.h>
#import <AppKit/NSNibDeclarations.h>
#import <ChatCore/MVChatConnection.h>
#import "JVInspectorController.h"

@class NSTextField;
@class NSPopUpButton;
@class NSButton;
@class NSTableView;
@class NSTextView;

@interface MVChatConnection (MVChatConnectionInspection) <JVInspection>
- (id <JVInspector>) inspector;
@end

@interface JVConnectionInspector : NSObject <JVInspector> {
	IBOutlet NSView *view;
	IBOutlet NSTextField *editNickname;
	IBOutlet NSTextField *editAltNicknames;
	IBOutlet NSTextField *editPassword;
	IBOutlet NSTextField *editRealName;
	IBOutlet NSTextField *editUsername;
	IBOutlet NSTextField *editServerPassword;
	IBOutlet NSTextField *editAddress;
	IBOutlet NSPopUpButton *encoding;
	IBOutlet NSPopUpButton *editProxy;
	IBOutlet NSTextField *editPort;
	IBOutlet NSButton *editAutomatic;
	IBOutlet NSTableView *editRooms;
	IBOutlet NSButton *editRemoveRoom;
	IBOutlet NSTextView *connectCommands;
	IBOutlet NSButton *sslConnection;
	MVChatConnection *_connection;
	BOOL _nibLoaded;
	NSMutableArray *_editingRooms;
}
- (id) initWithConnection:(MVChatConnection *) connection;

- (void) buildEncodingMenu;
- (IBAction) changeEncoding:(id) sender;

- (IBAction) openNetworkPreferences:(id) sender;
- (IBAction) editText:(id) sender;
- (IBAction) toggleAutoConnect:(id) sender;
- (IBAction) toggleSSLConnection:(id) sender;
- (IBAction) changeProxy:(id) sender;

- (IBAction) addRoom:(id) sender;
- (IBAction) removeRoom:(id) sender;
@end
