#import <AppKit/NSImageCell.h>

@interface JVDetailCell : NSImageCell {
	@private
	NSImage *_statusImage;
	NSImage *_altImage;
	NSString *_mainText;
	NSString *_infoText;
}
- (void) setStatusImage:(NSImage *) image;
- (NSImage *) statusImage;

- (void) setHighlightedImage:(NSImage *) image;
- (NSImage *) highlightedImage;

- (void) setMainText:(NSString *) text;
- (NSString *) mainText;

- (void) setInformationText:(NSString *) text;
- (NSString *) informationText;
@end
