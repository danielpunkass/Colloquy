#import "CQChatTableCell.h"
#import "CQChatController.h"

@interface UIRemoveControl : UIView
- (void) setRemoveConfirmationLabel:(NSString *) label;
@end

#pragma mark -

@interface UITableViewCell (UITableViewCellPrivate)
- (UIRemoveControl *) _createRemoveControl;
@end

#pragma mark -

@implementation CQChatTableCell
- (id) initWithFrame:(CGRect) frame reuseIdentifier:(NSString *) reuseIdentifier {
	if (!(self = [super initWithFrame:frame reuseIdentifier:reuseIdentifier]))
		return nil;

	_iconImageView = [[UIImageView alloc] initWithFrame:CGRectZero];
	_nameLabel = [[UILabel alloc] initWithFrame:CGRectZero];

	[self.contentView addSubview:_iconImageView];
	[self.contentView addSubview:_nameLabel];

	_nameLabel.font = [UIFont boldSystemFontOfSize:18.];
	_nameLabel.textColor = self.textColor;
	_nameLabel.highlightedTextColor = self.selectedTextColor;

	return self;
}

- (void) dealloc {
	[_iconImageView release];
	[_nameLabel release];
	[_removeConfirmationText release];
	[super dealloc];
}

#pragma mark -

- (void) takeValuesFromChatViewController:(id <CQChatViewController>) controller {
	self.name = controller.title;
	self.icon = controller.icon;
}

- (NSString *) name {
	return _nameLabel.text;
}

- (void) setName:(NSString *) name {
	_nameLabel.text = name;
}

- (UIImage *) icon {
	return _iconImageView.image;
}

- (void) setIcon:(UIImage *) icon {
	_iconImageView.image = icon;
}

@synthesize removeConfirmationText = _removeConfirmationText;

#pragma mark -

- (UIRemoveControl *) _createRemoveControl {
	UIRemoveControl *control = [super _createRemoveControl];
	if (_removeConfirmationText.length && [control respondsToSelector:@selector(setRemoveConfirmationLabel:)])
		[control setRemoveConfirmationLabel:_removeConfirmationText];
	return control;
}

#pragma mark -

- (void) setSelected:(BOOL) selected animated:(BOOL) animated {
	[super setSelected:selected animated:animated];

	UIColor *backgroundColor = nil;
	if (selected || animated) backgroundColor = nil;
	else backgroundColor = [UIColor whiteColor];

	_nameLabel.backgroundColor = backgroundColor;
	_nameLabel.highlighted = selected;
	_nameLabel.opaque = !selected && !animated;
}

- (void) layoutSubviews {
	[super layoutSubviews];

#define TOP_MARGIN 10.
#define LEFT_MARGIN 10.
#define RIGHT_MARGIN 10.
#define ICON_RIGHT_MARGIN 10.

	CGRect contentRect = self.contentView.bounds;

	CGRect frame = _iconImageView.frame;
	frame.size = [_iconImageView sizeThatFits:_iconImageView.bounds.size];
	frame.origin.x = contentRect.origin.x + LEFT_MARGIN;
	frame.origin.y = contentRect.origin.y + TOP_MARGIN;
	_iconImageView.frame = frame;

	frame = _nameLabel.frame;
	frame.size = [_nameLabel sizeThatFits:_nameLabel.bounds.size];
	frame.origin.x = CGRectGetMaxX(_iconImageView.frame) + ICON_RIGHT_MARGIN;
	frame.origin.y = contentRect.origin.y + TOP_MARGIN;
	frame.size.width = contentRect.size.width  - frame.origin.x - RIGHT_MARGIN;
	_nameLabel.frame = frame;
}
@end
