#import <Foundation/NSString.h>
#import <Foundation/NSObject.h>
#import <AppKit/NSNibDeclarations.h>
#import "JVChatWindowController.h"

@class WebView;
@class MVMenuButton;
@class NSString;
@class NSBundle;
@class NSDictionary;
@class NSMutableDictionary;
@class JVChatMessage;
@class NSLock;

@interface JVChatTranscript : NSObject <JVChatViewController> {
	@protected
	IBOutlet NSView			*contents;
	IBOutlet NSView			*toolbarItems;
	IBOutlet WebView		*display;
	IBOutlet MVMenuButton   *chooseStyle;
	IBOutlet MVMenuButton   *chooseEmoticon;
	
	void					*_chatXSLStyle;		/* xsltStylesheetPtr */
	void					*_xmlLog;			/* xmlDocPtr */
	void					*_xmlQueue;			/* xmlDocPtr */
	
	NSLock					*_logLock;
	JVChatWindowController  *_windowController;
	NSString				*_filePath;
	NSBundle				*_chatStyle;
	NSString				*_chatStyleVariant;
	NSBundle				*_chatEmoticons;
	NSDictionary			*_emoticonMappings;
	NSMutableDictionary		*_styleParams;
	NSMutableArray			*_messages;
	NSMutableDictionary		*_toolbarItems;
	
	const char				**_params;
	BOOL					_isArchive;
	BOOL					_nibLoaded;
	BOOL					_previousStyleSwitch;
}
- (id) initWithTranscript:(NSString *) filename;

- (void) saveTranscriptTo:(NSString *) path;

- (IBAction) changeChatStyle:(id) sender;
- (void) setChatStyle:(NSBundle *) style withVariant:(NSString *) variant;
- (NSBundle *) chatStyle;

- (IBAction) changeChatStyleVariant:(id) sender;
- (void) setChatStyleVariant:(NSString *) variant;
- (NSString *) chatStyleVariant;

- (IBAction) changeChatEmoticons:(id) sender;
- (void) setChatEmoticons:(NSBundle *) emoticons;
- (void) setChatEmoticons:(NSBundle *) emoticons performRefresh:(BOOL) refresh;
- (NSBundle *) chatEmoticons;

- (unsigned long) numberOfMessages;
- (JVChatMessage *) messageAtIndex:(unsigned long) index;
- (NSArray *) messagesInRange:(NSRange) range;

- (IBAction) leaveChat:(id) sender;
@end

#pragma mark -

@interface JVChatTranscript (JVChatTranscriptScripting) <JVChatListItemScripting>
- (NSNumber *) uniqueIdentifier;
@end

@interface NSObject (MVChatPluginLinkClickSupport)
- (BOOL) handleClickedLink:(NSURL *) url inView:(id <JVChatViewController>) view;
@end