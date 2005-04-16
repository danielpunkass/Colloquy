#import "JVChatTranscriptPanel.h"

@interface JVSmartTranscriptPanel : JVChatTranscriptPanel <NSCoding> {
	IBOutlet NSWindow *settingsSheet;
	IBOutlet NSTableView *subviewTableView;
	IBOutlet NSPopUpButton *operation;
	IBOutlet NSButton *ignoreCase;
	IBOutlet NSTextField *titleField;
	BOOL _settingsNibLoaded;
	NSMutableArray *_editingRules;
	NSMutableArray *_rules;
	NSString *_title;
	unsigned int _operation;
	BOOL _ignoreCase;
	BOOL _isActive;
	unsigned long _newMessages;
	unsigned int _origSheetHeight;
}
- (id) initWithSettings:(NSDictionary *) settings;

- (NSComparisonResult) compare:(JVSmartTranscriptPanel *) panel;

- (NSMutableArray *) rules;

- (unsigned int) newMessagesWaiting;
- (void) matchMessage:(JVChatMessage *) message fromView:(id <JVChatViewController>) view;

- (IBAction) editSettings:(id) sender;
- (IBAction) closeEditSettingsSheet:(id) sender;
- (IBAction) saveSettings:(id) sender;

- (IBAction) addRow:(id) sender;
- (IBAction) removeRow:(id) sender;	
@end
