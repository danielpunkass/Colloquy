#import <Cocoa/Cocoa.h>
#import "JVNotificationController.h"
#import "MVApplicationController.h"
#import "KABubbleWindowController.h"
#import "KABubbleWindowView.h"

static JVNotificationController *sharedInstance = nil;

@interface JVNotificationController (JVNotificationControllerPrivate)
- (void) _bounceIconOnce;
- (void) _bounceIconContinuously;
- (void) _showBubbleWithContext:(NSDictionary *) context andPrefs:(NSDictionary *) eventPrefs;
- (void) _playSound:(NSString *) path;
- (void) _threadPlaySound:(NSString *) path;
@end

#pragma mark -

@implementation JVNotificationController
+ (JVNotificationController *) defaultManager {
	extern JVNotificationController *sharedInstance;
	if( ! sharedInstance && [MVApplicationController isTerminating] ) return nil;
	return ( sharedInstance ? sharedInstance : ( sharedInstance = [[self alloc] init] ) );
}

#pragma mark -

- (id) init {
	self = [super init];
	_bubbles = [[NSMutableDictionary dictionary] retain];
	return self;
}

- (void) dealloc {
	extern JVNotificationController *sharedInstance;

	[_bubbles release];

	[[NSNotificationCenter defaultCenter] removeObserver:self];
	if( self == sharedInstance ) sharedInstance = nil;

	_bubbles = nil;

	[super dealloc];
}

- (void) performNotification:(NSString *) identifier withContextInfo:(NSDictionary *) context {
	NSDictionary *eventPrefs = [[NSUserDefaults standardUserDefaults] dictionaryForKey:[NSString stringWithFormat:@"JVNotificationSettings %@", identifier]];

	if( [[eventPrefs objectForKey:@"playSound"] boolValue] )
		[self _playSound:[eventPrefs objectForKey:@"soundPath"]];

	if( [[eventPrefs objectForKey:@"bounceIcon"] boolValue] ) {
		if( [[eventPrefs objectForKey:@"bounceIconUntilFront"] boolValue] )
			[self _bounceIconContinuously];
		else [self _bounceIconOnce];
	}

	if( [[eventPrefs objectForKey:@"showBubble"] boolValue] ) {
		if( [[eventPrefs objectForKey:@"showBubbleOnlyIfBackground"] boolValue] && ! [[NSApplication sharedApplication] isActive] )
			[self _showBubbleWithContext:context andPrefs:eventPrefs];
		else if( ! [[eventPrefs objectForKey:@"showBubbleOnlyIfBackground"] boolValue] )
			[self _showBubbleWithContext:context andPrefs:eventPrefs];
	}
}
@end

#pragma mark -

@implementation JVNotificationController (JVNotificationControllerPrivate)
- (void) _bounceIconOnce {
	[[NSApplication sharedApplication] requestUserAttention:NSInformationalRequest];
}

- (void) _bounceIconContinuously {
	[[NSApplication sharedApplication] requestUserAttention:NSCriticalRequest];
}

- (void) _showBubbleWithContext:(NSDictionary *) context andPrefs:(NSDictionary *) eventPrefs {
	NSImage *icon = [context objectForKey:@"image"];
	KABubbleWindowController *bubble = nil;

	if( ( bubble = [_bubbles objectForKey:[context objectForKey:@"coalesceKey"]] ) ) {
		[(id)bubble setTitle:[context objectForKey:@"title"]];
		[(id)bubble setText:[context objectForKey:@"description"]];
		[(id)bubble setIcon:( icon ? icon : [[NSApplication sharedApplication] applicationIconImage] )];
	} else {
		bubble = [KABubbleWindowController bubbleWithTitle:[context objectForKey:@"title"] text:[context objectForKey:@"description"] icon:( icon ? icon : [[NSApplication sharedApplication] applicationIconImage] )];
	}

	[bubble setAutomaticallyFadesOut:(! [[eventPrefs objectForKey:@"keepBubbleOnScreen"] boolValue] )];
	[bubble setTarget:[context objectForKey:@"target"]];
	[bubble setAction:NSSelectorFromString( [context objectForKey:@"action"] )];
	[bubble setRepresentedObject:[context objectForKey:@"representedObject"]];
	[bubble startFadeIn];

	if( [(NSString *)[context objectForKey:@"coalesceKey"] length] ) {
		[bubble setDelegate:self];
		[_bubbles setObject:bubble forKey:[context objectForKey:@"coalesceKey"]];
	}
}

- (void) bubbleDidFadeOut:(KABubbleWindowController *) bubble {
	NSEnumerator *e = [[[_bubbles copy] autorelease] objectEnumerator];
	NSEnumerator *ke = [[[_bubbles copy] autorelease] keyEnumerator];
	KABubbleWindowController *cBubble = nil;
	NSString *key = nil;

	while( ( key = [ke nextObject] ) && ( cBubble = [e nextObject] ) )
		if( cBubble == bubble ) [_bubbles removeObjectForKey:key];
}

- (void) _playSound:(NSString *) path {
	if( ! path ) return;
	[NSThread detachNewThreadSelector:@selector( _threadPlaySound: ) toTarget:self withObject:path];
}

- (void) _threadPlaySound:(NSString *) path {
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	if( ! [path isAbsolutePath] ) path = [[NSString stringWithFormat:@"%@/Sounds", [[NSBundle mainBundle] resourcePath]] stringByAppendingPathComponent:path];

	NSSound *sound = [[NSSound alloc] initWithContentsOfFile:path byReference:YES];
	[sound setDelegate:self];

// When run on a laptop using battery power, the play method may block while the audio
// hardware warms up.  If it blocks, the sound WILL NOT PLAY after the block ends.
// To get around this, we check to make sure the sound is playing, and if it isn't
// we call the play method again.

	[sound play];
	if( ! [sound isPlaying] ) [sound play];

	[pool release];
}

- (void) sound:(NSSound *) sound didFinishPlaying:(BOOL) finish {
	[sound autorelease];
}
@end