@protocol CQChatTranscriptViewDelegate;

typedef enum {
	CQChatMessageNormalType,
	CQChatMessageNoticeType
} CQChatMessageType;

@interface CQChatTranscriptView : UIWebView <UIWebViewDelegate> {
	IBOutlet id <CQChatTranscriptViewDelegate> delegate;
	NSMutableArray *_pendingMessages;
	BOOL _scrolling;
	BOOL _loading;
}
@property (nonatomic, assign) id <CQChatTranscriptViewDelegate> delegate;

- (void) addMessages:(NSArray *) messages;
- (void) addMessage:(NSDictionary *) info;

- (void) scrollToBottom;
- (void) flashScrollIndicators;
@end

@protocol CQChatTranscriptViewDelegate
@optional
@end
