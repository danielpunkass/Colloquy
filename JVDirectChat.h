#import "JVChatTranscript.h"
#import <AppKit/NSNibDeclarations.h>

@class NSView;
@class MVTextView;
@class NSString;
@class MVChatConnection;
@class NSDate;
@class NSMutableArray;
@class NSMutableString;
@class NSBundle;
@class NSDictionary;
@class NSToolbar;
@class NSData;
@class NSAttributedString;
@class NSMutableAttributedString;

@interface JVDirectChat : JVChatTranscript {
	@protected
	IBOutlet MVTextView *send;
	NSString *_target;
	MVChatConnection *_connection;
	NSMutableArray *_sendHistory;
	NSMutableArray *_waitingAlerts;
	NSMutableDictionary *_waitingAlertNames;
	unsigned int _messageId;
	BOOL _firstMessage;
	BOOL _isActive;
	BOOL _newMessage;
	BOOL _newHighlightMessage;
	BOOL _cantSendMessages;
	int _historyIndex;
}
- (id) initWithTarget:(NSString *) target forConnection:(MVChatConnection *) connection;

- (void) setTarget:(NSString *) target;
- (NSString *) target;

- (void) showAlert:(NSPanel *) alert withName:(NSString *) name;

- (void) addEventMessageToDisplay:(NSString *) message withName:(NSString *) name andAttributes:(NSDictionary *) attributes;
- (void) addMessageToDisplay:(NSData *) message fromUser:(NSString *) user asAction:(BOOL) action;

- (IBAction) send:(id) sender;
- (BOOL) processUserCommand:(NSString *) command withArguments:(NSAttributedString *) arguments;
- (NSMutableAttributedString *) sendAttributedMessage:(NSMutableAttributedString *) message asAction:(BOOL) action;

- (IBAction) clear:(id) sender;
- (IBAction) clearDisplay:(id) sender;
@end
