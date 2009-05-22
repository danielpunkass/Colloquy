@class JVMarkedScroller;
@class JVChatTranscript;
@class JVChatMessage;
@class JVStyle;
@class JVEmoticonSet;

@protocol JVChatTranscriptElement;

extern NSString *JVStyleViewDidClearNotification;
extern NSString *JVStyleViewDidChangeStylesNotification;

@interface JVStyleView : WebView {
	IBOutlet NSTextView *nextTextView;
	BOOL _forwarding;
	BOOL _switchingStyles;
	BOOL _ready;
	BOOL _mainFrameReady;
	BOOL _contentFrameReady;
	JVChatTranscript *_transcript;
	JVStyle *_style;
	NSString *_styleVariant;
	NSMutableDictionary *_styleParameters;
	JVEmoticonSet *_emoticons;
	DOMHTMLDocument *_mainDocument;
	DOMHTMLDocument *_domDocument;
	DOMHTMLElement *_body;
	NSString *_bodyTemplate;
	NSUInteger _scrollbackLimit;
	BOOL _requiresFullMessage;
	BOOL _rememberScrollPosition;
	NSUInteger _lastScrollPosition;
}
+ (void) emptyCache;

- (void) setTranscript:(JVChatTranscript *) transcript;
- (JVChatTranscript *) transcript;

- (void) setStyle:(JVStyle *) style;
- (void) setStyle:(JVStyle *) style withVariant:(NSString *) variant;
- (JVStyle *) style;

- (void) setStyleVariant:(NSString *) variant;
- (NSString *) styleVariant;

- (void) setBodyTemplate:(NSString *) bodyTemplate;
- (NSString *) bodyTemplate;

- (void) addBanner:(NSString *) name;

- (void) setStyleParameters:(NSDictionary *) parameters;
- (NSDictionary *) styleParameters;

- (void) setEmoticons:(JVEmoticonSet *) emoticons;
- (JVEmoticonSet *) emoticons;

- (void) setScrollbackLimit:(NSUInteger) limit;
- (NSUInteger) scrollbackLimit;

- (void) reloadCurrentStyle;
- (void) clear;
- (void) mark;

- (BOOL) appendChatMessage:(JVChatMessage *) message;
- (BOOL) appendChatTranscriptElement:(id <JVChatTranscriptElement>) element;

- (void) highlightMessage:(JVChatMessage *) message;
- (void) clearHighlightForMessage:(JVChatMessage *) message;
- (void) clearAllMessageHighlights;

- (void) highlightString:(NSString *) string inMessage:(JVChatMessage *) message;
- (void) clearStringHighlightsForMessage:(JVChatMessage *) message;
- (void) clearAllStringHighlights;

- (void) markScrollbarForMessage:(JVChatMessage *) message;
- (void) markScrollbarForMessage:(JVChatMessage *) message usingMarkIdentifier:(NSString *) identifier andColor:(NSColor *) color;
- (void) markScrollbarForMessages:(NSArray *) messages;

- (void) clearScrollbarMarks;
- (void) clearScrollbarMarksWithIdentifier:(NSString *) identifier;

- (JVMarkedScroller *) verticalMarkedScroller;
- (IBAction) jumpToMark:(id) sender;
- (IBAction) jumpToPreviousHighlight:(id) sender;
- (IBAction) jumpToNextHighlight:(id) sender;
- (void) jumpToMessage:(JVChatMessage *) message;
- (void) scrollToBottom;
- (BOOL) scrolledNearBottom;

- (NSTextView *) nextTextView;
- (void) setNextTextView:(NSTextView *) textView;
@end
