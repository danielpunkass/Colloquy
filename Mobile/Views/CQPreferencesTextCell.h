@interface CQPreferencesTextCell : UITableViewCell <UITextFieldDelegate> {
	@protected
	UILabel *_label;
	UITextField *_textField;
	SEL _textEditAction;
}
@property (nonatomic, copy) NSString *label;

@property (nonatomic, readonly) UITextField *textField;

@property (nonatomic) SEL textEditAction;
@end
