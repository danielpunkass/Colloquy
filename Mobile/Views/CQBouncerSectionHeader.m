#import "CQBouncerSectionHeader.h"

@implementation CQBouncerSectionHeader
- (id) initWithFrame:(CGRect) frame {
	if (!(self = [super initWithFrame:frame]))
		return nil;

	_backgroundImageView = [[UIImageView alloc] initWithFrame:CGRectZero];

	UIImage *image = [UIImage imageNamed:@"sectionHeader.png"];
	image = [image stretchableImageWithLeftCapWidth:0. topCapHeight:2.];

	_backgroundImage = [image retain];

	_backgroundImageView.alpha = 0.9;
	_backgroundImageView.image = image;

	image = [UIImage imageNamed:@"sectionHeaderHighlighted.png"];
	image = [image stretchableImageWithLeftCapWidth:0. topCapHeight:2.];

	_backgroundHighlightedImage = [image retain];

	_backgroundImageView.highlightedImage = image;

	_textLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	_textLabel.font = [UIFont boldSystemFontOfSize:18.];
	_textLabel.textColor = [UIColor whiteColor];
	_textLabel.backgroundColor = [UIColor clearColor];
	_textLabel.shadowOffset = CGSizeMake(0., 1.);
	_textLabel.shadowColor = [UIColor colorWithWhite:0. alpha:0.5];

	_textLabel.text = @"Direct Connections";

	image = [UIImage imageNamed:@"disclosureArrow.png"];
	_disclosureImageView = [[UIImageView alloc] initWithImage:image];

	[self addSubview:_backgroundImageView];
	[self addSubview:_textLabel];
	[self addSubview:_disclosureImageView];

	return self;
}

- (void) dealloc {
	[_textLabel release];
	[_backgroundImageView release];
	[_disclosureImageView release];
	[_backgroundImage release];
	[_backgroundHighlightedImage release];

	[super dealloc];
}

#pragma mark -

- (void) setHighlighted:(BOOL) highlighted {
	[super setHighlighted:highlighted];

	_backgroundImageView.alpha = (highlighted ? 1. : 0.9);
	_backgroundImageView.image = (highlighted ? _backgroundHighlightedImage : _backgroundImage);
}

#pragma mark -

- (void) layoutSubviews {
	_backgroundImageView.frame = self.bounds;

#define LEFT_TEXT_MARGIN 12.
#define RIGHT_TEXT_MARGIN 40.
#define TOP_IMAGE_MARGIN 5.
#define RIGHT_IMAGE_MARGIN 16.

	CGRect frame = self.bounds;
	frame.origin.x += LEFT_TEXT_MARGIN;
	frame.size.width -= (LEFT_TEXT_MARGIN + RIGHT_TEXT_MARGIN);

	_textLabel.frame = frame;

	frame = _disclosureImageView.bounds;
	frame.origin.x = CGRectGetMaxX(self.bounds) - frame.size.width - RIGHT_IMAGE_MARGIN;
	frame.origin.y = TOP_IMAGE_MARGIN;

	_disclosureImageView.frame = frame;

	[super layoutSubviews];
}

#pragma mark -

@synthesize textLabel = _textLabel;
@synthesize section = _section;
@end
