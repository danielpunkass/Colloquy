@interface CQPreferencesTextCell : UITableViewCell {
	UILabel *_label;
	UITextField *_textField;
}
@property (nonatomic, copy) NSString *label;

@property (nonatomic, readonly) UITextField *textField;
@end
