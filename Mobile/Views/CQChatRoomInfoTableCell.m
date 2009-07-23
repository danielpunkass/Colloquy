#import "CQChatRoomInfoTableCell.h"

@implementation CQChatRoomInfoTableCell
- (id) initWithFrame:(CGRect) frame reuseIdentifier:(NSString *) reuseIdentifier {
	if (!(self = [super initWithFrame:frame reuseIdentifier:reuseIdentifier]))
		return nil;

	_iconImageView = [[UIImageView alloc] initWithFrame:CGRectZero];
	_memberIconImageView = [[UIImageView alloc] initWithFrame:CGRectZero];
	_nameLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	_topicLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	_memberCountLabel = [[UILabel alloc] initWithFrame:CGRectZero];

	[self.contentView addSubview:_iconImageView];
	[self.contentView addSubview:_memberIconImageView];
	[self.contentView addSubview:_memberCountLabel];
	[self.contentView addSubview:_topicLabel];
	[self.contentView addSubview:_nameLabel];

	_iconImageView.image = [UIImage imageNamed:@"roomIconSmall.png"];
	_memberIconImageView.image = [UIImage imageNamed:@"personBlueSmall.png"];
	_memberIconImageView.highlightedImage = [UIImage imageNamed:@"personWhiteSmall.png"];

	_nameLabel.font = [UIFont boldSystemFontOfSize:18.];
	_nameLabel.textColor = self.textColor;
	_nameLabel.highlightedTextColor = self.selectedTextColor;

	_topicLabel.font = [UIFont systemFontOfSize:14.];
	_topicLabel.textColor = self.textColor;
	_topicLabel.highlightedTextColor = self.selectedTextColor;

	_memberCountLabel.font = [UIFont systemFontOfSize:14.];
	_memberCountLabel.textColor = [UIColor colorWithRed:0.19607843 green:0.29803922 blue:0.84313725 alpha:1.];
	_memberCountLabel.highlightedTextColor = self.selectedTextColor;

	return self;
}

- (void) dealloc {
	[_iconImageView release];
	[_memberIconImageView release];
	[_nameLabel release];
	[_topicLabel release];
	[_memberCountLabel release];

	[super dealloc];
}

#pragma mark -

- (NSString *) name {
	return _nameLabel.text;
}

- (void) setName:(NSString *) name {
	_nameLabel.text = name;
}

- (NSString *) topic {
	return _topicLabel.text;
}

- (void) setTopic:(NSString *) topic {
	_topicLabel.text = topic;

	[self setNeedsLayout];
}

- (NSUInteger) memberCount {
	return [_memberCountLabel.text integerValue];
}

- (void) setMemberCount:(NSUInteger) memberCount {
	_memberCountLabel.text = [NSString stringWithFormat:@"%lu", memberCount];

	[self setNeedsLayout];
}

#pragma mark -

- (void) prepareForReuse {
	[super prepareForReuse];

	self.name = @"";
	self.topic = @"";
	self.memberCount = 0;
}

- (void) setEditing:(BOOL) editing animated:(BOOL) animated {
	if (animated) {
		[UIView beginAnimations:nil context:NULL];
		[UIView setAnimationCurve:(editing ? UIViewAnimationCurveEaseIn : UIViewAnimationCurveEaseOut)];
	}

	[super setEditing:editing animated:animated];

	_memberCountLabel.alpha = editing ? 0. : 1.;
	_memberIconImageView.alpha = editing ? 0. : 1.;

	if (animated)
		[UIView commitAnimations];
}

- (void) layoutSubviews {
	[super layoutSubviews];

#define ICON_LEFT_MARGIN 10.
#define ICON_RIGHT_MARGIN 10.
#define MEMBER_ICON_LEFT_MARGIN 3.
#define TEXT_RIGHT_MARGIN 7.

	CGRect contentRect = self.contentView.frame;

	CGRect frame = _iconImageView.frame;
	frame.size = [_iconImageView sizeThatFits:_iconImageView.bounds.size];
	frame.origin.x = ICON_LEFT_MARGIN;
	frame.origin.y = round((contentRect.size.height / 2.) - (frame.size.height / 2.));
	_iconImageView.frame = frame;

	frame = _memberIconImageView.frame;
	frame.size = [_memberIconImageView sizeThatFits:_memberIconImageView.bounds.size];
	frame.origin.y = round((contentRect.size.height / 2.) - frame.size.height - 1.);

	if (self.showingDeleteConfirmation || self.showsReorderControl)
		frame.origin.x = self.bounds.size.width - contentRect.origin.x + frame.size.width;
	else if (self.editing)
		frame.origin.x = contentRect.size.width - frame.size.width;
	else
		frame.origin.x = contentRect.size.width - frame.size.width - TEXT_RIGHT_MARGIN;

	_memberIconImageView.frame = frame;

	frame = _memberCountLabel.frame;
	frame.size = [_memberCountLabel sizeThatFits:_memberCountLabel.bounds.size];
	frame.origin.y = round((contentRect.size.height / 2.) - frame.size.height + 3.);

	if (self.showingDeleteConfirmation || self.showsReorderControl)
		frame.origin.x = self.bounds.size.width - contentRect.origin.x;
	else if (self.editing)
		frame.origin.x = contentRect.size.width - frame.size.width - _memberIconImageView.frame.size.width - MEMBER_ICON_LEFT_MARGIN;
	else
		frame.origin.x = contentRect.size.width - frame.size.width - _memberIconImageView.frame.size.width - MEMBER_ICON_LEFT_MARGIN - TEXT_RIGHT_MARGIN;

	_memberCountLabel.frame = frame;

	frame = _nameLabel.frame;
	frame.size = [_nameLabel sizeThatFits:_nameLabel.bounds.size];
	frame.origin.x = CGRectGetMaxX(_iconImageView.frame) + ICON_RIGHT_MARGIN;
	frame.origin.y = round((contentRect.size.height / 2.) - frame.size.height + 3.);
	frame.size.width = _memberCountLabel.frame.origin.x - frame.origin.x - TEXT_RIGHT_MARGIN;
	_nameLabel.frame = frame;

	frame = _topicLabel.frame;
	frame.size = [_topicLabel sizeThatFits:_topicLabel.bounds.size];
	frame.origin.x = CGRectGetMaxX(_iconImageView.frame) + ICON_RIGHT_MARGIN;
	frame.origin.y = round(contentRect.size.height / 2.);
	frame.size.width = contentRect.size.width - frame.origin.x - TEXT_RIGHT_MARGIN;
	_topicLabel.frame = frame;
}
@end
