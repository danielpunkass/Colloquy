#import <Cocoa/Cocoa.h>
#import "JVDetailCell.h"

@implementation JVDetailCell
- (id) init {
	self = [super init];

	_altImage = nil;
	_statusImage = nil;
	_mainText = nil;
	_infoText = nil;

	[self setImageAlignment:NSImageAlignLeft];
	[self setImageScaling:NSScaleProportionally];
	[self setImageFrameStyle:NSImageFrameNone];

	return self;
}

- (id) copyWithZone:(NSZone *) zone {
	JVDetailCell *cell = (JVDetailCell *)[super copyWithZone:zone];
	cell -> _statusImage = [_statusImage retain];
	cell -> _altImage = [_altImage retain];
	cell -> _mainText = [_mainText copy];
	cell -> _infoText = [_infoText copy];
	return cell;
}

- (void) dealloc {
	[self setStatusImage:nil];
	[self setHighlightedImage:nil];
	[self setMainText:nil];
	[self setInformationText:nil];

	[super dealloc];
}

#pragma mark -

- (void) setStatusImage:(NSImage *) image {
	[_statusImage autorelease];
	_statusImage = [image retain];
}

- (NSImage *) statusImage {
	return [[_statusImage retain] autorelease];
}

#pragma mark -

- (void) setHighlightedImage:(NSImage *) image {
	[_altImage autorelease];
	_altImage = [image retain];
}

- (NSImage *) highlightedImage {
	return [[_altImage retain] autorelease];
}

#pragma mark -

- (void) setMainText:(NSString *) text {
	[_mainText autorelease];
	_mainText = [text copy];
}

- (NSString *) mainText {
	return [[_mainText retain] autorelease];
}

#pragma mark -

- (void) setInformationText:(NSString *) text {
	[_infoText autorelease];
	_infoText = [text copy];
}

- (NSString *) informationText {
	return [[_infoText retain] autorelease];
}

#pragma mark -

- (void) drawWithFrame:(NSRect) cellFrame inView:(NSView *) controlView {
	float imageWidth = 0.;
	float longestStringWidth = 0.;
	BOOL highlighted = ( [self isHighlighted] && [[controlView window] firstResponder] == controlView && [[controlView window] isKeyWindow] && [[NSApplication sharedApplication] isActive] );
	NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:[self font], NSFontAttributeName, ( [self isEnabled] ? ( highlighted ? [NSColor alternateSelectedControlTextColor] : [NSColor controlTextColor] ) : ( highlighted ? [NSColor alternateSelectedControlTextColor] : [[NSColor controlTextColor] colorWithAlphaComponent:0.50] ) ), NSForegroundColorAttributeName, nil];
	NSDictionary *subAttributes = [NSDictionary dictionaryWithObjectsAndKeys:[NSFont toolTipsFontOfSize:9.], NSFontAttributeName, ( [self isEnabled] ? ( highlighted ? [NSColor alternateSelectedControlTextColor] : [[NSColor controlTextColor] colorWithAlphaComponent:0.75] ) : ( highlighted ? [NSColor alternateSelectedControlTextColor] : [[NSColor controlTextColor] colorWithAlphaComponent:0.40] ) ), NSForegroundColorAttributeName, nil];
	NSImage *mainImage = nil, *curImage = nil;
	NSSize mainStringSize = [_mainText sizeWithAttributes:attributes];
	NSSize subStringSize = [_infoText sizeWithAttributes:subAttributes];

	if( highlighted && _altImage ) {
		mainImage = [[self image] retain];
		[self setImage:_altImage];
	}

	if( ! [self isEnabled] && [self image] ) {
		NSImage *fadedImage = [[[NSImage alloc] initWithSize:[[self image] size]] autorelease];
		[fadedImage lockFocus];
		[[self image] dissolveToPoint:NSMakePoint( 0., 0. ) fraction:0.5];
		[fadedImage unlockFocus];
		curImage = [[self image] retain];
		[self setImage:fadedImage];
	}

	cellFrame = NSMakeRect( cellFrame.origin.x + 1., cellFrame.origin.y, cellFrame.size.width - 1., cellFrame.size.height );
	[super drawWithFrame:cellFrame inView:controlView];

	if( ! [self isEnabled] ) {
		[self setImage:curImage];
		[curImage autorelease];
	}

	if( highlighted && mainImage ) {
		[self setImage:mainImage];
		[mainImage autorelease];
	}

	switch( [self imageScaling] ) {
	case NSScaleProportionally:
		if( NSHeight( cellFrame ) < [[self image] size].height )
			imageWidth = ( NSHeight( cellFrame ) / [[self image] size].height ) * [[self image] size].width;
		else imageWidth = [[self image] size].width;
		break;
	default:
	case NSScaleNone:
		imageWidth = [[self image] size].width;
		break;
	case NSScaleToFit:
		imageWidth = 0.;
		break;
	}

#define JVDetailCellImageLabelPadding 5.
#define JVDetailCellTextLeading 2.
#define JVDetailCellStatusImageLeftPadding 2.
#define JVDetailCellStatusImageRightPadding JVDetailCellStatusImageLeftPadding

	if( ( ! [_infoText length] && [_mainText length] ) || ( ( subStringSize.height + mainStringSize.height ) >= NSHeight( cellFrame ) - 2. ) ) {
		float mainYLocation = 0.;

		longestStringWidth = mainStringSize.width;

		if( NSHeight( cellFrame ) >= mainStringSize.height ) {
			mainYLocation = NSMinY( cellFrame ) + ( NSHeight( cellFrame ) / 2 ) - ( mainStringSize.height / 2 );
			[_mainText drawAtPoint:NSMakePoint( NSMinX( cellFrame ) + imageWidth + ( imageWidth ? JVDetailCellImageLabelPadding : 0. ), mainYLocation ) withAttributes:attributes];
		}
	} else if( [_infoText length] && [_mainText length] ) {
		float mainYLocation = 0., subYLocation = 0.;

		if( mainStringSize.width > subStringSize.width ) longestStringWidth = mainStringSize.width;
		else longestStringWidth = subStringSize.width;

		if( NSHeight( cellFrame ) >= mainStringSize.height ) {
			mainYLocation = cellFrame.origin.y + ( NSHeight( cellFrame ) / 2 ) - mainStringSize.height + ( JVDetailCellTextLeading / 2. );
			[_mainText drawAtPoint:NSMakePoint( cellFrame.origin.x + imageWidth + ( imageWidth ? JVDetailCellImageLabelPadding : 0. ), mainYLocation ) withAttributes:attributes];

			subYLocation = NSMinY( cellFrame ) + ( NSHeight( cellFrame ) / 2 ) + subStringSize.height - mainStringSize.height + ( JVDetailCellTextLeading / 2. );
			[_infoText drawAtPoint:NSMakePoint( NSMinX( cellFrame ) + imageWidth + ( imageWidth ? JVDetailCellImageLabelPadding : 0. ), subYLocation ) withAttributes:subAttributes];
		}
	}

	if( _statusImage && NSHeight( cellFrame ) >= [_statusImage size].height ) {
		float finalWidth = imageWidth + ( imageWidth ? JVDetailCellImageLabelPadding : 0. ) + longestStringWidth + JVDetailCellStatusImageLeftPadding + [_statusImage size].width + JVDetailCellStatusImageRightPadding;
		if( finalWidth <= NSWidth( cellFrame ) )
			[_statusImage compositeToPoint:NSMakePoint( NSMinX( cellFrame ) + NSWidth( cellFrame ) - [_statusImage size].width - JVDetailCellStatusImageRightPadding, NSMaxY( cellFrame ) - ( ( NSHeight( cellFrame ) / 2 ) - ( [_statusImage size].width / 2 ) ) ) operation:NSCompositeSourceAtop fraction:( [self isEnabled] ? 1. : 0.5)];
	}
}

#pragma mark -

- (void) setImageScaling:(NSImageScaling) newScaling {
	[super setImageScaling:( newScaling == NSScaleProportionally || newScaling == NSScaleNone ? newScaling : NSScaleProportionally )];
}

- (void) setImageAlignment:(NSImageAlignment) newAlign {
	[super setImageAlignment:NSImageAlignLeft];
}
@end
