#import "KABubbleWindow.h"

@implementation KABubbleWindow

- (id)initWithContentRect:(NSRect)contentRect
				styleMask:(unsigned int)aStyle
				  backing:(NSBackingStoreType)bufferingType
					defer:(BOOL)flag {
	
	//use NSWindow to draw for us
	NSWindow* result = [super initWithContentRect:contentRect 
										styleMask:NSBorderlessWindowMask 
										  backing:NSBackingStoreBuffered 
											defer:NO];
	
	//set up our window
	[result setBackgroundColor: [NSColor clearColor]];
	[result setLevel: NSStatusWindowLevel];
	[result setAlphaValue:0.15];
	[result setOpaque:NO];
	[result setHasShadow: YES];
	[result setCanHide:NO ];
	
	return result;
}

@end
