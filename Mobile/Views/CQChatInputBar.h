#import "CQTextCompletionView.h"

@protocol CQChatInputBarDelegate;
@class CQTextCompletionView;

@interface CQChatInputBar : UIView <UITextFieldDelegate, CQTextCompletionViewDelegate> {
	UITextField *_inputField;
	BOOL _inferAutocapitalizationType;
	IBOutlet id <CQChatInputBarDelegate> delegate;
	UIWindow *_completionWindow;
	CQTextCompletionView *_completionView;
	NSRange _completionRange;
}
@property (nonatomic,assign) id <CQChatInputBarDelegate> delegate;

@property (nonatomic) BOOL inferAutocapitalizationType;
@property (nonatomic) UITextAutocapitalizationType autocapitalizationType;
@end

@protocol CQChatInputBarDelegate <NSObject>
@optional
- (BOOL) chatInputBarShouldBeginEditing:(CQChatInputBar *) chatInputBar;
- (void) chatInputBarDidBeginEditing:(CQChatInputBar *) chatInputBar;
- (BOOL) chatInputBarShouldEndEditing:(CQChatInputBar *) chatInputBar;
- (void) chatInputBarDidEndEditing:(CQChatInputBar *) chatInputBar;
- (BOOL) chatInputBar:(CQChatInputBar *) chatInputBar sendText:(NSString *) text;
- (BOOL) chatInputBar:(CQChatInputBar *) chatInputBar shouldAutocorrectWordWithPrefix:(NSString *) word;
- (NSArray *) chatInputBar:(CQChatInputBar *) chatInputBar completionsForWordWithPrefix:(NSString *) word inRange:(NSRange) range;
@end
