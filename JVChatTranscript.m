#import "JVChatTranscript.h"

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import <ChatCore/MVChatConnection.h>
#import <ChatCore/MVChatPluginManager.h>
#import <ChatCore/MVChatScriptPlugin.h>
#import <ChatCore/NSMethodSignatureAdditions.h>

#import "JVChatController.h"
#import "JVChatMessage.h"
#import "MVConnectionsController.h"
#import "MVFileTransferController.h"
#import "MVMenuButton.h"
#import "NSPreferences.h"
#import "JVAppearancePreferences.h"
#import "JVChatTranscriptPrivates.h"
#import "JVMarkedScroller.h"

#import <libxml/xinclude.h>
#import <libxml/debugXML.h>
#import <libxslt/transform.h>
#import <libxslt/xsltutils.h>

NSMutableSet *JVChatStyleBundles = nil;
NSMutableSet *JVChatEmoticonBundles = nil;

static NSString *JVToolbarChooseStyleItemIdentifier = @"JVToolbarChooseStyleItem";
static NSString *JVToolbarEmoticonsItemIdentifier = @"JVToolbarEmoticonsItem";

#pragma mark -

@interface WebCoreCache
+ (void) setDisabled:(BOOL) disabled;
@end

#pragma mark -

@interface NSScrollView (NSScrollViewWebKitPrivate)
- (void) setAllowsHorizontalScrolling:(BOOL) allow;
@end

#pragma mark -
#pragma mark Style and Emoticon Bundle Sort

NSComparisonResult sortBundlesByName( id style1, id style2, void *context ) {
	NSString *styleName1 = [JVChatTranscript _nameForBundle:style1];
	NSString *styleName2 = [JVChatTranscript _nameForBundle:style2];
    return [styleName1 caseInsensitiveCompare:styleName2];
}

#pragma mark -

@implementation JVChatTranscript
- (id) init {
	extern NSMutableSet *JVChatStyleBundles;
	extern NSMutableSet *JVChatEmoticonBundles;

	if( ( self = [super init] ) ) {
		display = nil;
		contents = nil;
		_isArchive = NO;
		_params = NULL;
		_styleParams = nil;
		_styleMenu = nil;
		_chatStyle = nil;
		_chatStyleVariant = nil;
		_chatEmoticons = nil;
		_emoticonMenu = nil;
		_emoticonMappings = nil;
		_chatXSLStyle = NULL;
		_windowController = nil;
		_filePath = nil;
		_chatXSLStyle = NULL;
		_messages = [[NSMutableArray arrayWithCapacity:50] retain];

		[[self class] _scanForChatStyles];
		[[self class] _scanForEmoticons];

		[JVChatStyleBundles retain];
		[JVChatEmoticonBundles retain];

		_logLock = [[NSLock alloc] init];

		_xmlLog = xmlNewDoc( "1.0" );
		xmlDocSetRootElement( _xmlLog, xmlNewNode( NULL, "log" ) );
		xmlSetProp( xmlDocGetRootElement( _xmlLog ), "began", [[[NSDate date] description] UTF8String] );
	}
	return self;
}

- (id) initWithTranscript:(NSString *) filename {
	if( ( self = [self init] ) ) {
		xmlFreeDoc( _xmlLog );
		if( ! ( _xmlLog = xmlParseFile( [filename fileSystemRepresentation] ) ) ) return nil;

		_filePath = [filename copy];
		_isArchive = YES;

		[[NSDocumentController sharedDocumentController] noteNewRecentDocumentURL:[NSURL fileURLWithPath:filename]];
	}
	return self;
}

- (void) awakeFromNib {
	[display setUIDelegate:self];
	[display setPolicyDelegate:self];

	[[[[[display mainFrame] frameView] documentView] enclosingScrollView] setAllowsHorizontalScrolling:NO];
	[[[[[display mainFrame] frameView] documentView] enclosingScrollView] setVerticalScroller:[[[JVMarkedScroller alloc] initWithFrame:NSMakeRect( 0., 0., 10., 20. )] autorelease]];

	if( ! _chatStyle && xmlHasProp( xmlDocGetRootElement( _xmlLog ), "style" ) ) {
		xmlChar *styleProp = xmlGetProp( xmlDocGetRootElement( _xmlLog ), "style" );
		[self setChatStyle:[NSBundle bundleWithIdentifier:[NSString stringWithUTF8String:styleProp]] withVariant:nil];
		xmlFree( styleProp );
	}

	if( ! _chatEmoticons && xmlHasProp( xmlDocGetRootElement( _xmlLog ), "emoticon" ) ) {
		xmlChar *emoticonProp = xmlGetProp( xmlDocGetRootElement( _xmlLog ), "emoticon" );
		[self setChatEmoticons:[NSBundle bundleWithIdentifier:[NSString stringWithUTF8String:emoticonProp]]];
		xmlFree( emoticonProp );
	}

	if( ! _chatStyle ) {
		NSBundle *style = [NSBundle bundleWithIdentifier:[[NSUserDefaults standardUserDefaults] objectForKey:@"JVChatDefaultStyle"]];
		NSString *variant = [[NSUserDefaults standardUserDefaults] stringForKey:[NSString stringWithFormat:@"JVChatDefaultStyleVariant %@", [style bundleIdentifier]]];		
		if( ! style ) {
			[[NSUserDefaults standardUserDefaults] removeObjectForKey:@"JVChatDefaultStyle"];
			style = [NSBundle bundleWithIdentifier:[[NSUserDefaults standardUserDefaults] objectForKey:@"JVChatDefaultStyle"]];
			variant = [[NSUserDefaults standardUserDefaults] stringForKey:[NSString stringWithFormat:@"JVChatDefaultStyleVariant %@", [style bundleIdentifier]]];
		}
		[self setChatStyle:style withVariant:variant];
	}

	if( ! _chatEmoticons && ! [self _usingSpecificEmoticons] ) {
		NSBundle *emoticon = [NSBundle bundleWithIdentifier:[[NSUserDefaults standardUserDefaults] objectForKey:[NSString stringWithFormat:@"JVChatDefaultEmoticons %@", [_chatStyle bundleIdentifier]]]];
		if( ! emoticon ) {
			[[NSUserDefaults standardUserDefaults] removeObjectForKey:[NSString stringWithFormat:@"JVChatDefaultEmoticons %@", [_chatStyle bundleIdentifier]]];
			emoticon = [NSBundle bundleWithIdentifier:[[NSUserDefaults standardUserDefaults] objectForKey:[NSString stringWithFormat:@"JVChatDefaultEmoticons %@", [_chatStyle bundleIdentifier]]]];
		}
		[self setChatEmoticons:emoticon];
	}

	[self _updateChatStylesMenu];
	[self _updateChatEmoticonsMenu];
}

- (void) dealloc {
	extern NSMutableSet *JVChatStyleBundles;
	extern NSMutableSet *JVChatEmoticonBundles;

	[display setUIDelegate:nil];
	[display setPolicyDelegate:nil];

	[contents release];
	[_styleMenu release];
	[_chatStyle release];
	[_chatStyleVariant release];
	[_chatEmoticons release];
	[_emoticonMenu release];
	[_emoticonMappings release];
	[_logLock release];
	[_styleParams release];
	[_filePath release];
	[_messages release];

	[JVChatStyleBundles autorelease];
	[JVChatEmoticonBundles autorelease];

	xmlFreeDoc( _xmlLog );
	_xmlLog = NULL;

	xsltFreeStylesheet( _chatXSLStyle );
	_chatXSLStyle = NULL;

	[[self class] _freeXsltParamArray:_params];
	_params = NULL;

	if( [JVChatStyleBundles retainCount] == 1 ) JVChatStyleBundles = nil;
	if( [JVChatEmoticonBundles retainCount] == 1 ) JVChatEmoticonBundles = nil;

	contents = nil;
	_styleMenu = nil;
	_chatStyle = nil;
	_chatStyleVariant = nil;
	_chatEmoticons = nil;
	_emoticonMenu = nil;
	_emoticonMappings = nil;
	_logLock = nil;
	_styleParams = nil;
	_filePath = nil;
	_windowController = nil;
	_messages = nil;

	[super dealloc];
}

#pragma mark -
#pragma mark Window Controller and Proxy Icon Support

- (JVChatWindowController *) windowController {
	return [[_windowController retain] autorelease];
}

- (void) setWindowController:(JVChatWindowController *) controller {
	if( [[[_windowController window] representedFilename] isEqualToString:_filePath] )
		[[_windowController window] setRepresentedFilename:@""];
	_windowController = controller;
	[display setHostWindow:[_windowController window]];
}

- (void) didUnselect {
	[[_windowController window] setRepresentedFilename:@""];
}

- (void) didSelect {
	[[_windowController window] setRepresentedFilename:( _filePath ? _filePath : @"" )];
}

#pragma mark -
#pragma mark Miscellaneous Window Info

- (NSString *) title {
	return [[NSFileManager defaultManager] displayNameAtPath:_filePath];
}

- (NSString *) windowTitle {
	xmlChar *began = xmlGetProp( xmlDocGetRootElement( _xmlLog ), "began" );
	NSCalendarDate *date = ( began ? [NSCalendarDate dateWithString:[NSString stringWithUTF8String:began]] : nil );
	xmlFree( began );
	return [NSString stringWithFormat:NSLocalizedString( @"%@ - %@ Transcript", "chat transcript/log - window title" ), [self title], ( date ? [date descriptionWithCalendarFormat:[[NSUserDefaults standardUserDefaults] stringForKey:NSShortDateFormatString]] : @"" )];
}

- (NSString *) information {
	xmlChar *began = xmlGetProp( xmlDocGetRootElement( _xmlLog ), "began" );
	NSCalendarDate *date = ( began ? [NSCalendarDate dateWithString:[NSString stringWithUTF8String:began]] : nil );
	xmlFree( began );
	return [date descriptionWithCalendarFormat:[[NSUserDefaults standardUserDefaults] stringForKey:NSShortDateFormatString]];
}

- (NSString *) toolTip {
	return [NSString stringWithFormat:@"%@\n%@", [self title], [self information]];
}

- (IBAction) leaveChat:(id) sender {
	[[JVChatController defaultManager] disposeViewController:self];
}

- (NSString *) identifier {
	return [NSString stringWithFormat:@"Transcript %@", [self title]];
}

- (MVChatConnection *) connection {
	return nil;
}

- (NSView *) view {
	if( ! _nibLoaded ) _nibLoaded = [NSBundle loadNibNamed:@"JVChatTranscript" owner:self];
	return contents;
}

- (NSResponder *) firstResponder {
	return display;
}

#pragma mark -
#pragma mark Drawer/Outline View Methods

- (id <JVChatListItem>) parent {
	return nil;
}

- (NSMenu *) menu {
	NSMenu *menu = [[[NSMenu alloc] initWithTitle:@""] autorelease];
	NSMenuItem *item = nil;

	item = [[[NSMenuItem alloc] initWithTitle:NSLocalizedString( @"Close", "close contextual menu item title" ) action:@selector( leaveChat: ) keyEquivalent:@""] autorelease];
	[item setTarget:self];
	[menu addItem:item];

	item = [[[NSMenuItem alloc] initWithTitle:NSLocalizedString( @"Detach From Window", "detach from window contextual menu item title" ) action:@selector( detachView: ) keyEquivalent:@""] autorelease];
	[item setRepresentedObject:self];
	[item setTarget:[JVChatController defaultManager]];
	[menu addItem:item];

	return [[menu retain] autorelease];
}

- (NSImage *) icon {
	NSImage *ret = [NSImage imageNamed:@"Generic"];
	[ret setSize:NSMakeSize( 32., 32. )];
	return [[ret retain] autorelease];
}

#pragma mark -
#pragma mark File Saving

- (IBAction) saveDocumentTo:(id) sender {
	NSSavePanel *savePanel = [[NSSavePanel savePanel] retain];
	[savePanel setDelegate:self];
	[savePanel setCanSelectHiddenExtension:YES];
	[savePanel setRequiredFileType:@"colloquyTranscript"];
	[savePanel beginSheetForDirectory:NSHomeDirectory() file:[self title] modalForWindow:[_windowController window] modalDelegate:self didEndSelector:@selector( savePanelDidEnd:returnCode:contextInfo: ) contextInfo:NULL];
}

- (void) savePanelDidEnd:(NSSavePanel *) sheet returnCode:(int) returnCode contextInfo:(void *) contextInfo {
	[sheet autorelease];
	if( returnCode == NSOKButton ) {
		[self saveTranscriptTo:[sheet filename]];
		[[NSFileManager defaultManager] changeFileAttributes:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:[sheet isExtensionHidden]], NSFileExtensionHidden, nil] atPath:[sheet filename]];
	}
}

- (void) saveTranscriptTo:(NSString *) path {
	if( ! _chatEmoticons ) xmlSetProp( xmlDocGetRootElement( _xmlLog ), "emoticon", "" );
	else xmlSetProp( xmlDocGetRootElement( _xmlLog ), "emoticon", [[_chatEmoticons bundleIdentifier] UTF8String] );
	xmlSetProp( xmlDocGetRootElement( _xmlLog ), "style", [[_chatStyle bundleIdentifier] UTF8String] );
	xmlSaveFormatFile( [path fileSystemRepresentation], _xmlLog, (int) [[NSUserDefaults standardUserDefaults] boolForKey:@"JVChatFormatXMLLogs"] );	
	[[NSFileManager defaultManager] changeFileAttributes:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithUnsignedLong:'coTr'], NSFileHFSTypeCode, [NSNumber numberWithUnsignedLong:'coRC'], NSFileHFSCreatorCode, nil] atPath:path];
	[[NSDocumentController sharedDocumentController] noteNewRecentDocumentURL:[NSURL fileURLWithPath:path]];
}

- (void) downloadLinkToDisk:(id) sender {
	NSURL *url = [[sender representedObject] objectForKey:@"WebElementLinkURL"];
	[[MVFileTransferController defaultManager] downloadFileAtURL:url toLocalFile:nil];
}

#pragma mark -
#pragma mark Styles

- (IBAction) changeChatStyle:(id) sender {
	NSBundle *style = [NSBundle bundleWithIdentifier:[sender representedObject]];
	if( ! style ) {
		style = [NSBundle bundleWithIdentifier:[[NSUserDefaults standardUserDefaults] stringForKey:@"JVChatDefaultStyle"]];
		xmlUnsetProp( xmlDocGetRootElement( _xmlLog ), "style" );
	} else xmlSetProp( xmlDocGetRootElement( _xmlLog ), "style", [[style bundleIdentifier] UTF8String] );

	[self setChatStyle:style withVariant:nil];
}

- (void) setChatStyle:(NSBundle *) style withVariant:(NSString *) variant {
	int result = NSOKButton;
	BOOL manyMessages = NO;

	NSParameterAssert( style != nil );

	if( style == _chatStyle ) {
		if( ! [variant isEqualToString:_chatStyleVariant] )
			[self setChatStyleVariant:variant];
		return;
	}

	manyMessages = ( xmlLsCountNode( xmlDocGetRootElement( _xmlLog ) ) > 2000 ? YES : NO );
	
	NSString *styleswitch = NSLocalizedString( @"Time Consuming Style Switch", "time consuming style switch alert title" );

	if( _isArchive && _previousStyleSwitch && manyMessages ) {
		result = NSRunInformationalAlertPanel( styleswitch, NSLocalizedString( @"This transcript is large and will take a considerable amount of time to switch the style. Would you like to continue anyway?", "large transcript style switch alert message" ), NSLocalizedString( @"Continue", "continue button name" ), @"Cancel", nil );
	} else if( ! _isArchive && manyMessages ) {
		result = NSRunInformationalAlertPanel( styleswitch, NSLocalizedString( @"This converstaion is large and will take a considerable amount of time to switch the style. Would you like to do a full switch and wait until the switch is complete or a quick switch by hiding previous messages and return to the conversation?", "large transcript style switch alert message" ), NSLocalizedString( @"Full Switch", "full switch button name" ), @"Cancel", NSLocalizedString( @"Quick Switch", "clear button name" ) );
	}
	if( result == NSCancelButton ) return;

	if( ! [_logLock tryLock] ) return;	

	if( ! [self _usingSpecificEmoticons] ) {
		NSBundle *emoticon = [NSBundle bundleWithIdentifier:[[NSUserDefaults standardUserDefaults] objectForKey:[NSString stringWithFormat:@"JVChatDefaultEmoticons %@", style]]];
		[self setChatEmoticons:emoticon performRefresh:NO];
	}

	_previousStyleSwitch = YES;

	[_chatStyle autorelease];
	_chatStyle = [style retain];

	[_chatStyleVariant autorelease];
	_chatStyleVariant = [variant retain];

	[_styleParams autorelease];
	_styleParams = [[NSMutableDictionary dictionaryWithContentsOfFile:[_chatStyle pathForResource:@"parameters" ofType:@"plist"]] retain];
	if( ! [_styleParams count] ) _styleParams = [[NSMutableDictionary dictionary] retain];

	[_styleParams setObject:@"'/tmp/'" forKey:@"buddyIconDirectory"];
	[_styleParams setObject:@"'.tif'" forKey:@"buddyIconExtension"];

	if( _params ) [[self class] _freeXsltParamArray:_params];
	_params = [[self class] _xsltParamArrayWithDictionary:_styleParams];

	if( _chatXSLStyle ) xsltFreeStylesheet( _chatXSLStyle );
	_chatXSLStyle = xsltParseStylesheetFile( (const xmlChar *)[self _chatStyleXSLFilePath] );

	xmlSetProp( xmlDocGetRootElement( _xmlLog ), "style", [[_chatStyle bundleIdentifier] UTF8String] );

	[self _changeChatStyleMenuSelection];

	if( result == NSAlertOtherReturn ) {
		[self _switchingStyleEnded:@""];
	} else [NSThread detachNewThreadSelector:@selector( _switchStyle: ) toTarget:self withObject:nil];
}

- (NSBundle *) chatStyle {
	return [[_chatStyle retain] autorelease];
}

- (IBAction) changeChatStyleVariant:(id) sender {
	NSString *variant = [[sender representedObject] objectForKey:@"variant"];
	NSString *style = [[sender representedObject] objectForKey:@"style"];

	if( ! [style isEqual:_chatStyle] ) {
		[self setChatStyle:[NSBundle bundleWithIdentifier:style] withVariant:variant];
	} else {
		[self setChatStyleVariant:variant];
	}
}

- (void) setChatStyleVariant:(NSString *) variant {
	[_chatStyleVariant autorelease];
	_chatStyleVariant = [variant retain];

	[display stringByEvaluatingJavaScriptFromString:[NSString stringWithFormat:@"setStylesheet( \"variantStyle\", \"%@\" );", [self _chatStyleVariantCSSFileURL]]];

	[self _changeChatStyleMenuSelection];
}

- (NSString *) chatStyleVariant {
	return [[_chatStyleVariant retain] autorelease];
}

#pragma mark -
#pragma mark Emoticons

- (IBAction) changeChatEmoticons:(id) sender {
	if( [sender representedObject] && ! [(NSString *)[sender representedObject] length] ) {
		[self setChatEmoticons:nil];
		xmlSetProp( xmlDocGetRootElement( _xmlLog ), "emoticon", "" );
		return;
	}

	NSBundle *emoticons = [NSBundle bundleWithIdentifier:[sender representedObject]];
	if( ! emoticons ) {
		emoticons = [NSBundle bundleWithIdentifier:[[NSUserDefaults standardUserDefaults] objectForKey:[NSString stringWithFormat:@"JVChatDefaultEmoticons %@", [_chatStyle bundleIdentifier]]]];
		xmlUnsetProp( xmlDocGetRootElement( _xmlLog ), "emoticon" );
	} else xmlSetProp( xmlDocGetRootElement( _xmlLog ), "emoticon", [[emoticons bundleIdentifier] UTF8String] );

	[self setChatEmoticons:emoticons];
}

- (void) setChatEmoticons:(NSBundle *) emoticons {
	[self setChatEmoticons:emoticons performRefresh:YES];
}

- (void) setChatEmoticons:(NSBundle *) emoticons performRefresh:(BOOL) refresh {
	[_chatEmoticons autorelease];
	_chatEmoticons = [emoticons retain];

	[_emoticonMappings autorelease];
	_emoticonMappings = [[NSDictionary dictionaryWithContentsOfFile:[self _chatEmoticonsMappingFilePath]] retain];

	xmlSetProp( xmlDocGetRootElement( _xmlLog ), "emoticon", [[_chatEmoticons bundleIdentifier] UTF8String] );

	if( refresh )
		[display stringByEvaluatingJavaScriptFromString:[NSString stringWithFormat:@"setStylesheet( \"emoticonStyle\", \"%@\" );", [self _chatEmoticonsCSSFileURL]]];

	[self _updateChatEmoticonsMenu];
}

- (NSBundle *) chatEmoticons {
	return [[_chatEmoticons retain] autorelease];
}

#pragma mark -
#pragma mark Message Numbering

- (unsigned long) numberOfMessages {
	xmlXPathContextPtr ctx = xmlXPathNewContext( _xmlLog );
	if( ! ctx ) return 0;

	xmlXPathObjectPtr result = xmlXPathEval( "/log/envelope", ctx );
	if( ! result ) return 0;

	unsigned long ret = result -> nodesetval -> nodeNr;

	xmlXPathFreeContext( ctx );
	xmlXPathFreeObject( result );

	return ret;
}

- (NSArray *) messages {
	if( [_messages containsObject:[NSNull null]] || [_messages count] < [self numberOfMessages] )
		[self messagesInRange:NSMakeRange( 0, [self numberOfMessages] )];
	return _messages;
}

- (JVChatMessage *) messageAtIndex:(unsigned long) index {
	NSArray *msgs = [self messagesInRange:NSMakeRange( index, 1 )];
	if( [msgs count] ) return [msgs objectAtIndex:0];
	return nil;
}

- (NSArray *) messagesInRange:(NSRange) range {
	xmlXPathContextPtr ctx = xmlXPathNewContext( _xmlLog );
	if( ! ctx ) return nil;

	xmlXPathObjectPtr result = xmlXPathEval( [[NSString stringWithFormat:@"/log/envelope[@id >= %ld and @id < %ld]", range.location, range.location + range.length] UTF8String], ctx );

	if( ! result || ! result -> nodesetval -> nodeNr )
		return nil;

	unsigned int i = 0;

	if( [_messages count] < range.location )
		for( i = [_messages count]; i < range.location; i++ )
			[_messages insertObject:[NSNull null] atIndex:i];

	xmlNodePtr node = NULL;
	unsigned int size = result -> nodesetval -> nodeNr;
	NSMutableArray *ret = [NSMutableArray arrayWithCapacity:size];
	JVChatMessage *msg = nil;

	for( i = 0; i < size; i++ ) {
		node = result -> nodesetval -> nodeTab[i];
		if( ! node ) continue;
		if( [_messages count] > (range.location + i) && [[_messages objectAtIndex:(range.location + i)] isKindOfClass:[NSNull class]] ) {
			msg = [JVChatMessage messageWithNode:node andTranscript:self];
			[_messages replaceObjectAtIndex:(range.location + i) withObject:msg];
		} else if( [_messages count] > (range.location + i) && [[_messages objectAtIndex:(range.location + i)] isKindOfClass:[JVChatMessage class]] ) {
			msg = [_messages objectAtIndex:(range.location + i)];
		} else if( [_messages count] == (range.location + i) ) {
			msg = [JVChatMessage messageWithNode:node andTranscript:self];
			[_messages insertObject:msg atIndex:(range.location + i)];
		} else continue;
		if( msg ) [ret addObject:msg];
	}

	xmlXPathFreeContext( ctx );
	xmlXPathFreeObject( result );
	return ret;
}

#pragma mark -
#pragma mark Toolbar Methods

- (NSToolbar *) toolbar {
	NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:@"Chat Transcript"];
	[toolbar setDelegate:self];
	[toolbar setAllowsUserCustomization:YES];
	[toolbar setAutosavesConfiguration:YES];
	return [toolbar autorelease];
}

- (NSToolbarItem *) toolbar:(NSToolbar *) toolbar itemForItemIdentifier:(NSString *) identifier willBeInsertedIntoToolbar:(BOOL) willBeInserted {
	NSToolbarItem *toolbarItem = [[[NSToolbarItem alloc] initWithItemIdentifier:identifier] autorelease];

	if( [identifier isEqualToString:JVToolbarToggleChatDrawerItemIdentifier] ) {
		toolbarItem = [_windowController toggleChatDrawerToolbarItem];
	} else if( [identifier isEqualToString:JVToolbarToggleChatActivityItemIdentifier] ) {
//		toolbarItem = [_windowController chatActivityToolbarItem];
	} else if( [identifier isEqualToString:JVToolbarChooseStyleItemIdentifier] && ! willBeInserted ) {
		[toolbarItem setLabel:NSLocalizedString( @"Style", "choose style toolbar item label" )];
		[toolbarItem setPaletteLabel:NSLocalizedString( @"Style", "choose style toolbar item patlette label" )];
		[toolbarItem setImage:[NSImage imageNamed:@"chooseStyle"]];
	} else if( [identifier isEqualToString:JVToolbarChooseStyleItemIdentifier] && willBeInserted ) {
		[toolbarItem setLabel:NSLocalizedString( @"Style", "choose style toolbar item label" )];
		[toolbarItem setPaletteLabel:NSLocalizedString( @"Style", "choose style toolbar item patlette label" )];

		MVMenuButton *button = [[[MVMenuButton alloc] initWithFrame:NSMakeRect( 0., 0., 32., 32. )] autorelease];
		[button setImage:[NSImage imageNamed:@"chooseStyle"]];
		[button setDrawsArrow:YES];
		[button setMenu:_styleMenu];

		[toolbarItem setToolTip:NSLocalizedString( @"Change chat style", "choose style toolbar item tooltip" )];
		[button setToolbarItem:toolbarItem];
		[toolbarItem setTarget:self];
		[toolbarItem setView:button];

		NSMenuItem *menuItem = [[[NSMenuItem alloc] initWithTitle:NSLocalizedString( @"Style", "choose style toolbar item menu representation title" ) action:NULL keyEquivalent:@""] autorelease];
		NSImage *icon = [[[NSImage imageNamed:@"chooseStyle"] copy] autorelease];
		[icon setScalesWhenResized:YES];
		[icon setSize:NSMakeSize( 16., 16. )];
		[menuItem setImage:icon];
		[menuItem setSubmenu:_styleMenu];

		[toolbarItem setMenuFormRepresentation:menuItem];
	} else if( [identifier isEqualToString:JVToolbarEmoticonsItemIdentifier] && ! willBeInserted ) {
		[toolbarItem setLabel:NSLocalizedString( @"Emoticons", "choose emoticons toolbar item label" )];
		[toolbarItem setPaletteLabel:NSLocalizedString( @"Emoticons", "choose emoticons toolbar item patlette label" )];
		[toolbarItem setImage:[NSImage imageNamed:@"emoticon"]];
	} else if( [identifier isEqualToString:JVToolbarEmoticonsItemIdentifier] && willBeInserted ) {
		[toolbarItem setLabel:NSLocalizedString( @"Emoticons", "choose emoticons toolbar item label" )];
		[toolbarItem setPaletteLabel:NSLocalizedString( @"Emoticons", "choose emoticons toolbar item patlette label" )];

		MVMenuButton *button = [[[MVMenuButton alloc] initWithFrame:NSMakeRect( 0., 0., 32., 32. )] autorelease];
		[button setImage:[NSImage imageNamed:@"emoticon"]];
		[button setDrawsArrow:YES];
		[button setMenu:_emoticonMenu];

		[toolbarItem setToolTip:NSLocalizedString( @"Change Emoticons", "choose emoticons toolbar item tooltip" )];
		[button setToolbarItem:toolbarItem];
		[toolbarItem setTarget:self];
		[toolbarItem setView:button];

		NSMenuItem *menuItem = [[[NSMenuItem alloc] initWithTitle:NSLocalizedString( @"Emoticons", "choose emoticons toolbar item menu representation title" ) action:NULL keyEquivalent:@""] autorelease];
		NSImage *icon = [[[NSImage imageNamed:@"emoticon"] copy] autorelease];
		[icon setScalesWhenResized:YES];
		[icon setSize:NSMakeSize( 16., 16. )];
		[menuItem setImage:icon];
		[menuItem setSubmenu:_emoticonMenu];

		[toolbarItem setMenuFormRepresentation:menuItem];
	} else toolbarItem = nil;

	return toolbarItem;
}

- (NSArray *) toolbarDefaultItemIdentifiers:(NSToolbar *) toolbar {
	NSArray *list = [NSArray arrayWithObjects:JVToolbarToggleChatDrawerItemIdentifier/*, JVToolbarToggleChatActivityItemIdentifier */, 
		JVToolbarChooseStyleItemIdentifier, 
		JVToolbarEmoticonsItemIdentifier, nil];
	return [[list retain] autorelease];
}

- (NSArray *) toolbarAllowedItemIdentifiers:(NSToolbar *) toolbar {
	NSArray *list = [NSArray arrayWithObjects: JVToolbarToggleChatDrawerItemIdentifier/*, JVToolbarToggleChatActivityItemIdentifier */, 
		JVToolbarChooseStyleItemIdentifier, JVToolbarEmoticonsItemIdentifier, NSToolbarShowColorsItemIdentifier,
		NSToolbarCustomizeToolbarItemIdentifier, NSToolbarFlexibleSpaceItemIdentifier, 
		NSToolbarSpaceItemIdentifier, NSToolbarSeparatorItemIdentifier, nil];

	return [[list retain] autorelease];
}

- (BOOL) validateToolbarItem:(NSToolbarItem *) toolbarItem {
	if( [[NSUserDefaults standardUserDefaults] boolForKey:@"MVChatIgnoreColors"] && [[toolbarItem itemIdentifier] isEqualToString:NSToolbarShowColorsItemIdentifier] ) return NO;
	else if( ! [[NSUserDefaults standardUserDefaults] boolForKey:@"MVChatIgnoreColors"] && [[toolbarItem itemIdentifier] isEqualToString:NSToolbarShowColorsItemIdentifier] ) return YES;
	return YES;
}

#pragma mark -
#pragma mark WebView

- (NSArray *) webView:(WebView *) sender contextMenuItemsForElement:(NSDictionary *) element defaultMenuItems:(NSArray *) defaultMenuItems {
	NSMutableArray *ret = [[defaultMenuItems mutableCopy] autorelease];
	NSMenuItem *item = nil;
	unsigned i = 0;

	for( i = 0; i < [ret count]; i++ ) {
		item = [ret objectAtIndex:i];
		switch( [item tag] ) {
		case WebMenuItemTagOpenLinkInNewWindow:
		case WebMenuItemTagOpenImageInNewWindow:
		case WebMenuItemTagOpenFrameInNewWindow:
			[ret removeObjectAtIndex:i];
			i--;
			break;
		case WebMenuItemTagDownloadLinkToDisk:
		case WebMenuItemTagDownloadImageToDisk:
			[item setTarget:[sender UIDelegate]];
			break;
		}
	}
	return ret;
}

- (void) webView:(WebView *) sender decidePolicyForNavigationAction:(NSDictionary *) actionInformation request:(NSURLRequest *) request frame:(WebFrame *) frame decisionListener:(id <WebPolicyDecisionListener>) listener {
	if( [[[actionInformation objectForKey:WebActionOriginalURLKey] scheme] isEqualToString:@"about"] ) {
		if( [[[actionInformation objectForKey:WebActionOriginalURLKey] standardizedURL] path] )
			[listener ignore];
		else [listener use];
	} else if( [[[actionInformation objectForKey:WebActionOriginalURLKey] scheme] isEqualToString:@"self"] ) {
		NSString *resource = [[actionInformation objectForKey:WebActionOriginalURLKey] resourceSpecifier];
		NSRange range = [resource rangeOfString:@"?"];
		NSString *command = [resource substringToIndex:( range.location != NSNotFound ? range.location : [resource length] )];
		if( [self respondsToSelector:NSSelectorFromString( [command stringByAppendingString:@":"] )] ) {
			NSString *arg = [resource substringFromIndex:( range.location != NSNotFound ? range.location : 0 )];
			[self performSelector:NSSelectorFromString( [command stringByAppendingString:@":"] ) withObject:( range.location != NSNotFound ? arg : nil )];
		}
		[listener ignore];
	} else {
		NSMethodSignature *signature = [NSMethodSignature methodSignatureWithReturnAndArgumentTypes:@encode( BOOL ), @encode( NSURL * ), @encode( id ), nil];
		NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
		NSURL *url = [actionInformation objectForKey:WebActionOriginalURLKey];

		[invocation setSelector:@selector( handleClickedLink:inView: )];
		[invocation setArgument:&url atIndex:2];
		[invocation setArgument:&self atIndex:3];

		NSArray *results = [[MVChatPluginManager defaultManager] makePluginsPerformInvocation:invocation stoppingOnFirstSuccessfulReturn:YES];

		if( ! [[results lastObject] boolValue] ) {
			if( [url isChatURL] ) {
				[[MVConnectionsController defaultManager] handleURL:url andConnectIfPossible:YES];
			} else if( [[actionInformation objectForKey:WebActionModifierFlagsKey] unsignedIntValue] & NSAlternateKeyMask ) {
				[[MVFileTransferController defaultManager] downloadFileAtURL:url toLocalFile:nil];
			} else {
				if( ( [[actionInformation objectForKey:WebActionModifierFlagsKey] unsignedIntValue] & NSCommandKeyMask ) &&
					[[NSWorkspace sharedWorkspace] respondsToSelector:@selector(openURLs:withAppBundleIdentifier:options:additionalEventParamDescriptor:launchIdentifiers:)] ) {
					[[NSWorkspace sharedWorkspace] openURLs:[NSArray arrayWithObject:url] withAppBundleIdentifier:nil options:NSWorkspaceLaunchWithoutActivation additionalEventParamDescriptor:nil launchIdentifiers:nil];
				} else {
					[[NSWorkspace sharedWorkspace] openURL:url];
				}
			}
		}

		[listener ignore];
	}
}

- (void) webView:(WebView *) sender didFinishLoadForFrame:(WebFrame *) frame {
	[display setFrameLoadDelegate:nil];
	[[display preferences] setJavaScriptEnabled:YES];
	[_logLock unlock];

	NSScroller *scroller = [[[[[display mainFrame] frameView] documentView] enclosingScrollView] verticalScroller];
	if( [scroller isMemberOfClass:[JVMarkedScroller class]] ) {
		[(JVMarkedScroller *)scroller removeAllMarks];

		xmlXPathContextPtr ctx = xmlXPathNewContext( _xmlLog );
		if( ! ctx ) return;

		xmlXPathObjectPtr result = xmlXPathEval( "/log/envelope/message[@highlight = 'yes']/..", ctx );
		if( ! result ) {
			xmlXPathFreeContext( ctx );
			return;
		}

		xmlNodePtr cur = NULL;
		unsigned int c = ( result -> nodesetval ? result -> nodesetval -> nodeNr : 0 );
		unsigned int i = 0;
		for( i = 0; i < c; i++ ) {
			cur = result -> nodesetval -> nodeTab[i];   	    
			unsigned int loc = [[display stringByEvaluatingJavaScriptFromString:[NSString stringWithFormat:@"locationOfMessage( \"%s\" );", xmlGetProp( cur, "id" )]] intValue];
			if( loc ) [(JVMarkedScroller *)[[[[[display mainFrame] frameView] documentView] enclosingScrollView] verticalScroller] addMarkAt:loc];
		}

		xmlXPathFreeContext( ctx );
		xmlXPathFreeObject( result );
	}
}
@end

#pragma mark -

@implementation JVChatTranscript (JVChatTranscriptPrivate)
+ (const char **) _xsltParamArrayWithDictionary:(NSDictionary *) dictionary {
	NSEnumerator *keyEnumerator = [dictionary keyEnumerator];
	NSEnumerator *enumerator = [dictionary objectEnumerator];
	NSString *key = nil;
	NSString *value = nil;
	const char **temp = NULL, **ret = NULL;
	
	if( ! [dictionary count] ) return NULL;
	
	ret = temp = malloc( ( ( [dictionary count] * 2 ) + 1 ) * sizeof( char * ) );
	
	while( ( key = [keyEnumerator nextObject] ) && ( value = [enumerator nextObject] ) ) {
		*(temp++) = (char *) strdup( [key UTF8String] );
		*(temp++) = (char *) strdup( [value UTF8String] );
	}
	
	*(temp) = NULL;
	
	return ret;
}

+ (void) _freeXsltParamArray:(const char **) params {
	const char **temp = params;
	
	if( ! params ) return;
	
	while( *(temp) ) {
		free( (void *)*(temp++) );
		free( (void *)*(temp++) );
	}
	
	free( params );
}

+ (NSString *) _nameForBundle:(NSBundle *) bundle {
	NSDictionary *info = [bundle localizedInfoDictionary];
	NSString *label = [info objectForKey:@"CFBundleName"];
	if( ! label ) label = [bundle objectForInfoDictionaryKey:@"CFBundleName"];
	if( ! label ) label = [bundle bundleIdentifier];
	return [[label retain] autorelease];
}

#pragma mark -
#pragma mark Style Support

+ (NSSet *) _chatStyleBundles {
	extern NSMutableSet *JVChatStyleBundles;
	return [[JVChatStyleBundles retain] autorelease];
}

+ (void) _scanForChatStyles {
	extern NSMutableSet *JVChatStyleBundles;
	NSMutableArray *paths = [NSMutableArray arrayWithCapacity:4];
	NSEnumerator *enumerator = nil, *denumerator = nil;
	NSString *file = nil, *path = nil;
	NSBundle *bundle = nil;
	
	if( ! JVChatStyleBundles )
		JVChatStyleBundles = [NSMutableSet set];
	
	[paths addObject:[NSString stringWithFormat:@"%@/Styles", [[NSBundle mainBundle] resourcePath]]];
	[paths addObject:[[NSString stringWithFormat:@"~/Library/Application Support/%@/Styles", [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"]] stringByExpandingTildeInPath]];
	[paths addObject:[NSString stringWithFormat:@"/Library/Application Support/%@/Styles", [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"]]];
	[paths addObject:[NSString stringWithFormat:@"/Network/Library/Application Support/%@/Styles", [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"]]];
	
	enumerator = [paths objectEnumerator];
	while( ( path = [enumerator nextObject] ) ) {
		denumerator = [[[NSFileManager defaultManager] directoryContentsAtPath:path] objectEnumerator];
		while( ( file = [denumerator nextObject] ) ) {
			if( [[file pathExtension] isEqualToString:@"colloquyStyle"] ) {
				if( ( bundle = [NSBundle bundleWithPath:[NSString stringWithFormat:@"%@/%@", path, file]] ) ) {
					[bundle load];
					[JVChatStyleBundles addObject:bundle];
				}
			}
		}
	}
}

- (void) _reloadCurrentStyle:(id) sender {
	NSBundle *style = [[_chatStyle retain] autorelease];

	[WebCoreCache setDisabled:YES];

	[_chatStyle autorelease];
	_chatStyle = nil;

	[self setChatStyle:style withVariant:_chatStyleVariant];

	if( ! _chatStyle ) _chatStyle = [style retain];
}

- (void) _switchingStyleEnded:(in NSString *) html {
	[display setPreferencesIdentifier:[_chatStyle bundleIdentifier]];
	[display setFrameLoadDelegate:self];
	[[display mainFrame] loadHTMLString:[self _fullDisplayHTMLWithBody:(html ? html : @"")] baseURL:nil];
}

- (oneway void) _switchStyle:(id) sender {
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSString *result = [self _applyStyleOnXMLDocument:_xmlLog];
	[self performSelectorOnMainThread:@selector( _switchingStyleEnded: ) withObject:result waitUntilDone:YES];
	[pool release];
}

- (NSMenu *) _stylesMenu {
	return [[_styleMenu retain] autorelease];
}

- (void) _changeChatStyleMenuSelection {
	NSEnumerator *enumerator = [[_styleMenu itemArray] objectEnumerator];
	NSEnumerator *senumerator = nil;
	NSMenuItem *menuItem = nil, *subMenuItem = nil;
	BOOL hasPerRoomStyle = [self _usingSpecificStyle];
	NSString *style = [_chatStyle bundleIdentifier];

	while( ( menuItem = [enumerator nextObject] ) ) {
		if( [menuItem tag] ) continue;
		if( [style isEqualToString:[menuItem representedObject]] && hasPerRoomStyle ) [menuItem setState:NSOnState];
		else if( ! [menuItem representedObject] && ! hasPerRoomStyle ) [menuItem setState:NSOnState];
		else if( [style isEqualToString:[menuItem representedObject]] && ! hasPerRoomStyle ) [menuItem setState:NSMixedState];
		else [menuItem setState:NSOffState];

		senumerator = [[[menuItem submenu] itemArray] objectEnumerator];
		while( ( subMenuItem = [senumerator nextObject] ) ) {
			if( [subMenuItem action] == @selector( changeChatStyle: ) && [style isEqualToString:[subMenuItem representedObject]] && ! [_chatStyleVariant length] )
				[subMenuItem setState:NSOnState];
			else if( [subMenuItem action] == @selector( changeChatStyleVariant: ) && [style isEqualToString:[[subMenuItem representedObject] objectForKey:@"style"]] && [_chatStyleVariant isEqualToString:[[subMenuItem representedObject] objectForKey:@"variant"]] ) 
				[subMenuItem setState:NSOnState];
			else [subMenuItem setState:NSOffState];
		}
	}
}

- (void) _updateChatStylesMenu {
	extern NSMutableSet *JVChatStyleBundles;
	NSEnumerator *enumerator = [[[JVChatStyleBundles allObjects] sortedArrayUsingFunction:sortBundlesByName context:self] objectEnumerator];
	NSEnumerator *denumerator = nil;
	NSMenu *menu = nil, *subMenu = nil;
	NSMenuItem *menuItem = nil, *subMenuItem = nil;
	NSBundle *style = nil;
	id file = nil;

	if( ! ( menu = _styleMenu ) ) {
		menu = [[NSMenu alloc] initWithTitle:NSLocalizedString( @"Style", "choose style toolbar menu title" )];
		_styleMenu = menu;
	} else {
		NSEnumerator *enumerator = [[[[menu itemArray] copy] autorelease] objectEnumerator];

		if( [menu numberOfItems] > ( [JVChatStyleBundles count] + 2 ) )
			[enumerator nextObject];

		while( ( menuItem = [enumerator nextObject] ) )
			[menu removeItem:menuItem];
	}

	menuItem = [[[NSMenuItem alloc] initWithTitle:NSLocalizedString( @"Default", "default style menu item title" ) action:@selector( changeChatStyle: ) keyEquivalent:@""] autorelease];
	[menuItem setTarget:self];
	[menu addItem:menuItem];

	[menu addItem:[NSMenuItem separatorItem]];

	while( ( style = [enumerator nextObject] ) ) {
		menuItem = [[[NSMenuItem alloc] initWithTitle:[[self class] _nameForBundle:style] action:@selector( changeChatStyle: ) keyEquivalent:@""] autorelease];
		[menuItem setTarget:self];
		[menuItem setRepresentedObject:[style bundleIdentifier]];
		[menu addItem:menuItem];

		if( [[style pathsForResourcesOfType:@"css" inDirectory:@"Variants"] count] ) {
			denumerator = [[style pathsForResourcesOfType:@"css" inDirectory:@"Variants"] objectEnumerator];
			subMenu = [[[NSMenu alloc] initWithTitle:@""] autorelease];
			subMenuItem = [[[NSMenuItem alloc] initWithTitle:( [style objectForInfoDictionaryKey:@"JVBaseStyleVariantName"] ? [style objectForInfoDictionaryKey:@"JVBaseStyleVariantName"] : NSLocalizedString( @"Normal", "normal style variant menu item title" ) ) action:@selector( changeChatStyle: ) keyEquivalent:@""] autorelease];
			[subMenuItem setTarget:self];
			[subMenuItem setRepresentedObject:[style bundleIdentifier]];
			[subMenu addItem:subMenuItem];

			while( ( file = [denumerator nextObject] ) ) {
				file = [[file lastPathComponent] stringByDeletingPathExtension];
				subMenuItem = [[[NSMenuItem alloc] initWithTitle:file action:@selector( changeChatStyleVariant: ) keyEquivalent:@""] autorelease];
				[subMenuItem setTarget:self];
				[subMenuItem setRepresentedObject:[NSDictionary dictionaryWithObjectsAndKeys:[style bundleIdentifier], @"style", file, @"variant", nil]];
				[subMenu addItem:subMenuItem];
			}

			[menuItem setSubmenu:subMenu];
		}

		subMenu = nil;
	}

	[menu addItem:[NSMenuItem separatorItem]];

	menuItem = [[[NSMenuItem alloc] initWithTitle:NSLocalizedString( @"Appearance Preferences...", "appearance preferences menu item title" ) action:@selector( _openAppearancePreferences: ) keyEquivalent:@""] autorelease];
	[menuItem setTarget:self];
	[menuItem setTag:10];
	[menu addItem:menuItem];

	[self _changeChatStyleMenuSelection];
}

- (NSString *) _applyStyleOnXMLDocument:(xmlDocPtr) doc {
	xmlDocPtr res = NULL;
	xmlChar *result = NULL;
	NSString *ret = nil;
	int len = 0;

	NSParameterAssert( doc != NULL );
	NSAssert( _chatXSLStyle, @"XSL not allocated." );

	if( ( res = xsltApplyStylesheet( _chatXSLStyle, doc, _params ) ) ) {
		xsltSaveResultToString( &result, &len, res, _chatXSLStyle );
		xmlFreeDoc( res );
	}

	if( result ) {
		ret = [NSString stringWithUTF8String:result];
		free( result );
	}

	return [[ret retain] autorelease];
}

- (NSString *) _chatStyleBaseURL {
	NSString *path = [_chatStyle resourcePath];
	if( path ) return [[[[NSURL fileURLWithPath:path] absoluteString] retain] autorelease];
	else return @"";
}

- (NSString *) _chatStyleCSSFileURL {
	NSString *path = [_chatStyle pathForResource:@"main" ofType:@"css"];
	if( path ) return [[[[NSURL fileURLWithPath:path] absoluteString] retain] autorelease];
	else return @"";
}

- (NSString *) _chatStyleVariantCSSFileURL {
	NSString *path = nil;
	if( _chatStyleVariant ) {
		if( [_chatStyleVariant isAbsolutePath] ) {
			path = [[NSURL fileURLWithPath:_chatStyleVariant] absoluteString];
		} else {
			path = [_chatStyle pathForResource:_chatStyleVariant ofType:@"css" inDirectory:@"Variants"];
			if( path ) path = [[NSURL fileURLWithPath:[_chatStyle pathForResource:_chatStyleVariant ofType:@"css" inDirectory:@"Variants"]] absoluteString];
			if( ! path ) {
				[_chatStyleVariant autorelease];
				_chatStyleVariant = nil;

				[self _changeChatStyleMenuSelection];
			}
		}
	}
	if( ! path ) path = @"";
	return [[path retain] autorelease];
}

- (const char *) _chatStyleXSLFilePath {
	NSString *path = [_chatStyle pathForResource:@"main" ofType:@"xsl"];
	if( ! path ) path = [[NSBundle mainBundle] pathForResource:@"default" ofType:@"xsl"];
	return [path fileSystemRepresentation];
}

- (NSString *) _chatStyleHeaderFileContents {
	NSString *path = [_chatStyle pathForResource:@"supplement" ofType:@"html"];
	return ( path ? [NSString stringWithContentsOfFile:path] : @"" );
}

- (BOOL) _usingSpecificStyle {
	return ( xmlHasProp( xmlDocGetRootElement( _xmlLog ), "style" ) ? YES : NO );
}

#pragma mark -
#pragma mark Emoticons Support

+ (NSSet *) _emoticonBundles {
	extern NSMutableSet *JVChatEmoticonBundles;
	return [[JVChatEmoticonBundles retain] autorelease];
}

+ (void) _scanForEmoticons {
	extern NSMutableSet *JVChatEmoticonBundles;
	NSMutableArray *paths = [NSMutableArray arrayWithCapacity:4];
	NSEnumerator *enumerator = nil, *denumerator = nil;
	NSString *file = nil, *path = nil;
	NSBundle *bundle = nil;
	
	if( ! JVChatEmoticonBundles )
		JVChatEmoticonBundles = [NSMutableSet set];
	
	[paths addObject:[NSString stringWithFormat:@"%@/Emoticons", [[NSBundle mainBundle] resourcePath]]];
	[paths addObject:[[NSString stringWithFormat:@"~/Library/Application Support/%@/Emoticons", [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"]] stringByExpandingTildeInPath]];
	[paths addObject:[NSString stringWithFormat:@"/Library/Application Support/%@/Emoticons", [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"]]];
	[paths addObject:[NSString stringWithFormat:@"/Network/Library/Application Support/%@/Emoticons", [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"]]];
	
	enumerator = [paths objectEnumerator];
	while( ( path = [enumerator nextObject] ) ) {
		denumerator = [[[NSFileManager defaultManager] directoryContentsAtPath:path] objectEnumerator];
		while( ( file = [denumerator nextObject] ) ) {
			if( [[file pathExtension] isEqualToString:@"colloquyEmoticons"] ) {
				if( ( bundle = [NSBundle bundleWithPath:[NSString stringWithFormat:@"%@/%@", path, file]] ) ) {
					[bundle load];
					[JVChatEmoticonBundles addObject:bundle];
				}
			}
		}
	}
}

- (NSMenu *) _emoticonsMenu {
	if( [_emoticonMenu itemWithTag:20] )
		return [[_emoticonMenu itemWithTag:20] submenu];
	return [[_emoticonMenu retain] autorelease];
}

- (void) _changeChatEmoticonsMenuSelection {
	NSEnumerator *enumerator = nil;
	NSMenuItem *menuItem = nil;
	BOOL hasPerRoomEmoticons = [self _usingSpecificEmoticons];
	NSString *emoticons = [_chatEmoticons bundleIdentifier];

	enumerator = [[[[_emoticonMenu itemWithTag:20] submenu] itemArray] objectEnumerator];
	if( ! enumerator ) enumerator = [[_emoticonMenu itemArray] objectEnumerator];
	while( ( menuItem = [enumerator nextObject] ) ) {
		if( [menuItem tag] ) continue;
		if( [menuItem representedObject] && ! [(NSString *)[menuItem representedObject] length] && ! _chatEmoticons && hasPerRoomEmoticons ) [menuItem setState:NSOnState];
		else if( [emoticons isEqualToString:[menuItem representedObject]] && hasPerRoomEmoticons ) [menuItem setState:NSOnState];
		else if( ! [menuItem representedObject] && ! hasPerRoomEmoticons ) [menuItem setState:NSOnState];
		else if( [menuItem representedObject] && ! [(NSString *)[menuItem representedObject] length] && ! _chatEmoticons && ! hasPerRoomEmoticons ) [menuItem setState:NSMixedState];
		else if( [emoticons isEqualToString:[menuItem representedObject]] && ! hasPerRoomEmoticons ) [menuItem setState:NSMixedState];
		else [menuItem setState:NSOffState];
	}
}

- (void) _updateChatEmoticonsMenu {
	extern NSMutableSet *JVChatEmoticonBundles;
	NSEnumerator *enumerator = nil;
	NSMenu *menu = nil;
	NSMenuItem *menuItem = nil;
	BOOL new = YES;
	NSBundle *emoticon = nil;

	if( ! ( menu = _emoticonMenu ) ) {
		menu = [[NSMenu alloc] initWithTitle:@""];
		_emoticonMenu = menu;
	} else {
		NSEnumerator *enumerator = [[[[menu itemArray] copy] autorelease] objectEnumerator];
		new = NO;
		while( ( menuItem = [enumerator nextObject] ) )
			[menu removeItem:menuItem];
	}

	menuItem = [[[NSMenuItem alloc] initWithTitle:NSLocalizedString( @"Style Default", "default style emoticons menu item title" ) action:@selector( changeChatEmoticons: ) keyEquivalent:@""] autorelease];
	[menuItem setTarget:self];
	[menu addItem:menuItem];

	[menu addItem:[NSMenuItem separatorItem]];

	menuItem = [[[NSMenuItem alloc] initWithTitle:NSLocalizedString( @"Text Only", "text only emoticons menu item title" ) action:@selector( changeChatEmoticons: ) keyEquivalent:@""] autorelease];
	[menuItem setTarget:self];
	[menuItem setRepresentedObject:@""];
	[menu addItem:menuItem];

	[menu addItem:[NSMenuItem separatorItem]];

	enumerator = [[[JVChatEmoticonBundles allObjects] sortedArrayUsingFunction:sortBundlesByName context:self] objectEnumerator];
	while( ( emoticon = [enumerator nextObject] ) ) {
		menuItem = [[[NSMenuItem alloc] initWithTitle:[[self class] _nameForBundle:emoticon] action:@selector( changeChatEmoticons: ) keyEquivalent:@""] autorelease];
		[menuItem setTarget:self];
		[menuItem setRepresentedObject:[emoticon bundleIdentifier]];
		[menu addItem:menuItem];
	}

	[menu addItem:[NSMenuItem separatorItem]];

	menuItem = [[[NSMenuItem alloc] initWithTitle:NSLocalizedString( @"Appearance Preferences...", "appearance preferences menu item title" ) action:@selector( _openAppearancePreferences: ) keyEquivalent:@""] autorelease];
	[menuItem setTarget:self];
	[menuItem setTag:10];
	[menu addItem:menuItem];

	[self _changeChatEmoticonsMenuSelection];
}

- (NSString *) _chatEmoticonsMappingFilePath {
	NSString *path = [_chatEmoticons pathForResource:@"emoticons" ofType:@"plist"];
	if( ! path ) path = [[NSBundle mainBundle] pathForResource:@"emoticons" ofType:@"plist"];
	return [[path retain] autorelease];
}

- (NSString *) _chatEmoticonsCSSFileURL {
	NSString *path = [_chatEmoticons pathForResource:@"emoticons" ofType:@"css"];
	if( path ) return [[[[NSURL fileURLWithPath:path] absoluteString] retain] autorelease];
	else return @"";
}

- (IBAction) _openAppearancePreferences:(id) sender {
	[[NSPreferences sharedPreferences] showPreferencesPanelForOwner:[JVAppearancePreferences sharedInstance]];
}

- (BOOL) _usingSpecificEmoticons {
	return ( xmlHasProp( xmlDocGetRootElement( _xmlLog ), "emoticon" ) ? YES : NO );
}

#pragma mark -
#pragma mark Web View Template

- (NSString *) _fullDisplayHTMLWithBody:(NSString *) html {
	NSString *shell = [NSString stringWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"template" ofType:@"html"]];
	return [[[NSString stringWithFormat:shell, [self title], [self _chatEmoticonsCSSFileURL], [self _chatStyleCSSFileURL], [self _chatStyleVariantCSSFileURL], [self _chatStyleBaseURL], [self _chatStyleHeaderFileContents], html] retain] autorelease];
}
@end

#pragma mark -

@implementation JVChatTranscript (JVChatTranscriptScripting)
- (NSNumber *) uniqueIdentifier {
	return [NSNumber numberWithUnsignedInt:(unsigned long) self];
}

- (JVChatMessage *) valueInMessagesAtIndex:(unsigned) index {
	return [self messageAtIndex:index];
}

#pragma mark -

- (void) saveScriptCommand:(NSScriptCommand *) command {
	NSString *path = [[command evaluatedArguments] objectForKey:@"File"];

	if( ! [[path pathComponents] count] ) {
		[NSException raise:NSInvalidArgumentException format:@"Invalid path."];
		return;
	}

	[self saveTranscriptTo:path];
}
@end

#pragma mark -

@implementation MVChatScriptPlugin (MVChatScriptPluginLinkClickSupport)
- (BOOL) handleClickedLink:(NSURL *) url inView:(id <JVChatViewController>) view {
	NSDictionary *args = [NSDictionary dictionaryWithObjectsAndKeys:[url absoluteString], @"----", view, @"hCl1", nil];
	id result = [self callScriptHandler:'hClX' withArguments:args];
	if( ! result ) [self doesNotRespondToSelector:_cmd];
	return ( [result isKindOfClass:[NSNumber class]] ? [result boolValue] : NO );
}
@end