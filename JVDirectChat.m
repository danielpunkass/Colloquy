#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

#import <ChatCore/MVChatConnection.h>
#import <ChatCore/MVChatPluginManager.h>
#import <ChatCore/MVChatPlugin.h>
#import <ChatCore/NSAttributedStringAdditions.h>
#import <libxml/xinclude.h>

#import "JVChatController.h"
#import "JVDirectChat.h"
#import "MVTextView.h"
#import "MVMenuButton.h"

const NSStringEncoding JVAllowedTextEncodings[] = {
	/* Universal */
	NSUTF8StringEncoding,
	NSNonLossyASCIIStringEncoding,
	/* Western */	(NSStringEncoding) -1, // Divider
	NSASCIIStringEncoding,
	NSISOLatin1StringEncoding, // ISO Latin 1
	(NSStringEncoding) 0x80000203, // ISO Latin 3
	(NSStringEncoding) 0x8000020F, // ISO Latin 9
	NSMacOSRomanStringEncoding, // Mac
	NSWindowsCP1252StringEncoding, // Windows
	/* European */	(NSStringEncoding) -1,
	NSISOLatin2StringEncoding, // ISO Latin 2
	(NSStringEncoding) 0x80000204, // ISO Latin 4
	(NSStringEncoding) 0x8000001D, // Mac
	NSWindowsCP1250StringEncoding, // Windows
	/* Cyrillic */	(NSStringEncoding) -1,
	(NSStringEncoding) 0x80000A02, // KOI8-R
	(NSStringEncoding) 0x80000205, // ISO Latin 5
	(NSStringEncoding) 0x80000007, // Mac
	NSWindowsCP1251StringEncoding, // Windows
	/* Japanese */	(NSStringEncoding) -1, // Divider
	(NSStringEncoding) 0x80000A01, // ShiftJIS
//	NSISO2022JPStringEncoding, // ISO-2022-JP
	NSJapaneseEUCStringEncoding, // EUC
	(NSStringEncoding) 0x80000001, // Mac
	NSShiftJISStringEncoding, // Windows
	/* Simplified Chinese */	(NSStringEncoding) -1, // Divider
	(NSStringEncoding) 0x80000632, // GB 18030
	(NSStringEncoding) 0x80000631, // GBK
	(NSStringEncoding) 0x80000930, // EUC
	(NSStringEncoding) 0x80000019, // Mac
	(NSStringEncoding) 0x80000421, // Windows
	/* Traditional Chinese */	(NSStringEncoding) -1, // Divider
	(NSStringEncoding) 0x80000A03, // Big5
	(NSStringEncoding) 0x80000A06, // Big5 HKSCS
	(NSStringEncoding) 0x80000931, // EUC
	(NSStringEncoding) 0x80000002, // Mac
	(NSStringEncoding) 0x80000423, // Windows
	/* Korean */	(NSStringEncoding) -1,
	(NSStringEncoding) 0x80000940, // EUC
	(NSStringEncoding) 0x80000003, // Mac
	(NSStringEncoding) 0x80000422, // Windows
	/* End */ 0 };

extern char *irc_html_to_irc(const char * const string);
extern char *irc_irc_to_html(const char * const string);

static NSString *JVToolbarTextEncodingItemIdentifier = @"JVToolbarTextEncodingItem";
static NSString *JVToolbarBoldFontItemIdentifier = @"JVToolbarBoldFontItem";
static NSString *JVToolbarItalicFontItemIdentifier = @"JVToolbarItalicFontItem";
static NSString *JVToolbarUnderlineFontItemIdentifier = @"JVToolbarUnderlineFontItem";

#pragma mark -

@interface JVChatTranscript (JVChatTranscriptPrivate)
- (NSString *) _fullDisplayHTMLWithBody:(NSString *) html;
- (NSString *) _applyStyleOnXMLDocument:(xmlDocPtr) doc;
- (void) savePanelDidEnd:(NSSavePanel *) sheet returnCode:(int) returnCode contextInfo:(void *) contextInfo;
@end

#pragma mark -

@interface JVDirectChat (JVDirectChatPrivate)
- (void) _makeHyperlinksInString:(NSMutableString *) string;
- (void) _breakLongLinesInString:(NSMutableString *) string;
- (void) _preformEmoticonSubstitutionOnString:(NSMutableString *) string;
@end

#pragma mark -

@implementation JVDirectChat
- (id) init {
	if( ( self = [super init] ) ) {
		send = nil;
		encodingView = nil;
		_messageId = 0;
		_target = nil;
		_connection = nil;
		_firstMessage = YES;
		_newMessage = NO;
		_newHighlightMessage = NO;
		_cantSendMessages = NO;
		_isActive = NO;
		_historyIndex = 0;

		_encoding = NSASCIIStringEncoding;

		_sendHistory = [[NSMutableArray array] retain];
		[_sendHistory insertObject:[[[NSAttributedString alloc] initWithString:@""] autorelease] atIndex:0];

		_waitingAlerts = [[NSMutableArray array] retain];
		_waitingAlertNames = [[NSMutableDictionary dictionary] retain];
	}
	return self;
}

- (id) initWithTarget:(NSString *) target forConnection:(MVChatConnection *) connection {
	if( ( self = [self init] ) ) {
		NSString *source = nil;
		_target = [target copy];
		_connection = [connection retain];
		source = [NSString stringWithFormat:@"%@/%@", [[[self connection] url] absoluteString], _target];
		xmlSetProp( xmlDocGetRootElement( _xmlLog ), "source", [source UTF8String] );

		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector( _didConnect: ) name:MVChatConnectionDidConnectNotification object:connection];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector( _didDisconnect: ) name:MVChatConnectionDidDisconnectNotification object:connection];

		_settings = [[[NSUserDefaults standardUserDefaults] dictionaryForKey:[[self identifier] stringByAppendingString:@" Settings"]] mutableCopy];
		if( ! _settings ) _settings = [[NSMutableDictionary dictionary] retain];
	}
	return self;
}

- (void) awakeFromNib {
	NSView *toolbarItemContainerView = nil;
	NSBundle *style = nil;
	NSString *variant = nil;

	[self changeEncoding:nil];

	if( [self preferenceForKey:@"style"] ) {
		style = [NSBundle bundleWithIdentifier:[self preferenceForKey:@"style"]];
		variant = [self preferenceForKey:@"style variant"];
		if( ! style ) {
			[self setPreference:nil forKey:@"style"];
			[self setPreference:nil forKey:@"style variant"];
		}
	}

//	[self setChatEmoticons:[NSBundle bundleWithIdentifier:[[NSUserDefaults standardUserDefaults] objectForKey:@"JVChatDefaultEmoticons"]]];
	if( style ) [self setChatStyle:style withVariant:variant];

	if( ( toolbarItemContainerView = [chooseStyle superview] ) ) {
		[chooseStyle retain];
		[chooseStyle removeFromSuperview];
	
		[encodingView retain];
		[encodingView removeFromSuperview];
	
		[toolbarItemContainerView autorelease];
	}

	[super awakeFromNib];

	[[[encodingView menu] itemAtIndex:0] setImage:[NSImage imageNamed:@"encoding"]];	

	[send setHorizontallyResizable:YES];
	[send setVerticallyResizable:YES];
	[send setAutoresizingMask:NSViewWidthSizable];
	[send setSelectable:YES];
	[send setEditable:YES];
	[send setRichText:YES];
	[send setImportsGraphics:NO];
	[send setUsesFontPanel:YES];
	[send setUsesRuler:NO];
	[send setDelegate:self];
	[send setContinuousSpellCheckingEnabled:[[NSUserDefaults standardUserDefaults] boolForKey:@"JVChatSpellChecking"]];
	[send reset:nil];
}

- (void) dealloc {
	NSEnumerator *enumerator = nil;
	id alert = nil;

	[_target autorelease];
	[_connection autorelease];
	[_sendHistory autorelease];
	[_waitingAlertNames autorelease];

	[[NSNotificationCenter defaultCenter] removeObserver:self];

	enumerator = [_waitingAlerts objectEnumerator];
	while( ( alert = [enumerator nextObject] ) )
		NSReleaseAlertPanel( alert );

	[_waitingAlerts release];

	_target = nil;
	_sendHistory = nil;
	_connection = nil;
	_waitingAlerts = nil;
	_waitingAlertNames = nil;

	[super dealloc];
}

#pragma mark -

- (NSString *) target {
	return [[_target retain] autorelease];
}

- (MVChatConnection *) connection {
	return [[_connection retain] autorelease];
}

#pragma mark -

- (NSView *) view {
	if( ! _nibLoaded ) _nibLoaded = [NSBundle loadNibNamed:@"JVDirectChat" owner:self];
	return contents;
}

- (NSToolbar *) toolbar {
	NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:@"Direct Chat"];
	[toolbar setDelegate:self];
	[toolbar setAllowsUserCustomization:YES];
	[toolbar setAutosavesConfiguration:YES];
	return [toolbar autorelease];
}

#pragma mark -

- (NSString *) title {
	return [[_target retain] autorelease];
}

- (NSString *) windowTitle {
	return [NSString stringWithFormat:NSLocalizedString( @"%@ - Private Message", "private message with user - window title" ), _target];
}

- (NSString *) information {
	return nil;
}

#pragma mark -

- (NSMenu *) menu {
	NSMenu *menu = [[[NSMenu alloc] initWithTitle:@""] autorelease];
	NSMenuItem *item = nil;

	item = [[[NSMenuItem alloc] initWithTitle:NSLocalizedString( @"Get Info", "get info contextual menu item title" ) action:NULL keyEquivalent:@""] autorelease];
	[item setTarget:self];
	[menu addItem:item];

	item = [[[NSMenuItem alloc] initWithTitle:NSLocalizedString( @"Send File...", "send file contextual menu") action:@selector( sendFileToSelectedUser: ) keyEquivalent:@""] autorelease];
	[item setTarget:self];
	[menu addItem:item];

	[menu addItem:[NSMenuItem separatorItem]];

	item = [[[NSMenuItem alloc] initWithTitle:NSLocalizedString( @"Leave Chat", "leave chat contextual menu item title" ) action:@selector( leaveChat: ) keyEquivalent:@""] autorelease];
	[item setTarget:self];
	[menu addItem:item];

	item = [[[NSMenuItem alloc] initWithTitle:NSLocalizedString( @"Detach From Window", "detach from window contextual menu item title" ) action:@selector( detachView: ) keyEquivalent:@""] autorelease];
	[item setRepresentedObject:self];
	[item setTarget:[JVChatController defaultManager]];
	[menu addItem:item];

	return [[menu retain] autorelease];
}

- (NSImage *) icon {
	return [NSImage imageNamed:@"messageUser"];
}

- (NSImage *) statusImage {
	return ( _isActive ? nil : ( [_waitingAlerts count] ? [NSImage imageNamed:@"viewAlert"] : ( _newMessage ? ( _newHighlightMessage ? [NSImage imageNamed:@"newHighlightMessage"] : [NSImage imageNamed:@"newMessage"] ) : nil ) ) );
}

#pragma mark -

- (NSString *) identifier {
	return [NSString stringWithFormat:@"Direct Chat %@ (%@)", _target, [[self connection] server]];
}

#pragma mark -

- (void) didUnselect {
	_newMessage = NO;
	_newHighlightMessage = NO;
	_isActive = NO;
}

- (void) didSelect {
	_newMessage = NO;
	_newHighlightMessage = NO;
	_isActive = YES;
	if( [_waitingAlerts count] ) {
		[[NSApplication sharedApplication] beginSheet:[_waitingAlerts objectAtIndex:0] modalForWindow:[_windowController window] modalDelegate:self didEndSelector:@selector( _alertSheetDidEnd:returnCode:contextInfo: ) contextInfo:NULL];
	}
}

#pragma mark -

- (BOOL) acceptsDraggedFileOfType:(NSString *) type {
	return YES;
}

- (void) handleDraggedFile:(NSString *) path {
	[[self connection] sendFileToUser:_target withFilePath:path];
}

#pragma mark -

- (void) savePanelDidEnd:(NSSavePanel *) sheet returnCode:(int) returnCode contextInfo:(void *) contextInfo {
	if( returnCode == NSOKButton ) xmlSetProp( xmlDocGetRootElement( _xmlLog ), "ended", [[[NSDate date] description] UTF8String] );
	[super savePanelDidEnd:sheet returnCode:returnCode contextInfo:contextInfo];
	if( returnCode == NSOKButton ) xmlUnsetProp( xmlDocGetRootElement( _xmlLog ), "ended" );
}

#pragma mark -

- (void) setTarget:(NSString *) target {
	[_target autorelease];
	_target = [target copy];

	[_windowController reloadListItem:self andChildren:YES];

	[_settings autorelease];
	_settings = [[[NSUserDefaults standardUserDefaults] dictionaryForKey:[[self identifier] stringByAppendingString:@" Settings"]] mutableCopy];
	if( ! _settings ) _settings = [[NSMutableDictionary dictionary] retain];

	NSString *source = [NSString stringWithFormat:@"%@/%@", [[[self connection] url] absoluteString], _target];
	xmlSetProp( xmlDocGetRootElement( _xmlLog ), "source", [source UTF8String] );
}

#pragma mark -

- (void) showAlert:(NSPanel *) alert withName:(NSString *) name {
	if( _isActive && ! [[_windowController window] attachedSheet] ) {
		if( alert ) [[NSApplication sharedApplication] beginSheet:alert modalForWindow:[_windowController window] modalDelegate:self didEndSelector:@selector( _alertSheetDidEnd:returnCode:contextInfo: ) contextInfo:NULL];
	} else {
		if( name && [_waitingAlertNames objectForKey:name] ) {
			NSPanel *sheet = [[[_waitingAlertNames objectForKey:name] retain] autorelease];
			if( alert ) {
				[_waitingAlerts replaceObjectAtIndex:[_waitingAlerts indexOfObjectIdenticalTo:[_waitingAlertNames objectForKey:name]] withObject:alert];
				[_waitingAlertNames setObject:alert forKey:name];
			} else {
				[_waitingAlerts removeObjectAtIndex:[_waitingAlerts indexOfObjectIdenticalTo:[_waitingAlertNames objectForKey:name]]];
				[_waitingAlertNames removeObjectForKey:name];
			}
			NSReleaseAlertPanel( sheet );
		} else {
			if( name && alert ) [_waitingAlertNames setObject:alert forKey:name];
			if( alert ) [_waitingAlerts addObject:alert];
		}
	}
	[_windowController reloadListItem:self andChildren:NO];
}

#pragma mark -

- (void) setPreference:(id) value forKey:(NSString *) key {
	NSParameterAssert( key != nil );
	NSParameterAssert( [key length] );

	if( value ) [_settings setObject:value forKey:key];
	else [_settings removeObjectForKey:key];

	[[NSUserDefaults standardUserDefaults] setObject:_settings forKey:[[self identifier] stringByAppendingString:@" Settings"]];
	[[NSUserDefaults standardUserDefaults] synchronize];
}

- (id) preferenceForKey:(NSString *) key {
	NSParameterAssert( key != nil );
	NSParameterAssert( [key length] );

	return [[[_settings objectForKey:key] retain] autorelease];
}

#pragma mark -

- (IBAction) changeChatStyle:(id) sender {
	NSBundle *style = [NSBundle bundleWithIdentifier:[sender representedObject]];
	NSString *variant = nil;
	if( style ) {
		[self setPreference:[style bundleIdentifier] forKey:@"style"];
		[self setPreference:nil forKey:@"style variant"];
	} else {
		style = [NSBundle bundleWithIdentifier:[[NSUserDefaults standardUserDefaults] stringForKey:@"JVChatDefaultStyle"]];
		[self setPreference:nil forKey:@"style"];
		[self setPreference:nil forKey:@"style variant"];
		if( ! style ) {
			[[NSUserDefaults standardUserDefaults] removeObjectForKey:@"JVChatDefaultStyle"];
			style = [NSBundle bundleWithIdentifier:[[NSUserDefaults standardUserDefaults] objectForKey:@"JVChatDefaultStyle"]];
		}
		variant = [[NSUserDefaults standardUserDefaults] stringForKey:[NSString stringWithFormat:@"JVChatDefaultStyleVariant %@", [style bundleIdentifier]]];
	}
	[self setChatStyle:style withVariant:variant];
}

- (IBAction) changeChatStyleVariant:(id) sender {
	NSString *variant = [[sender representedObject] objectForKey:@"variant"];
	NSString *style = [[sender representedObject] objectForKey:@"style"];

	[self setPreference:style forKey:@"style"];
	[self setPreference:variant forKey:@"style variant"];

	if( ! [style isEqualToString:[_chatStyle bundleIdentifier]] ) {
		[self setChatStyle:[NSBundle bundleWithIdentifier:style] withVariant:variant];
	} else {
		[self setChatStyleVariant:variant];
	}
}

- (IBAction) changeChatEmoticons:(id) sender {
	/*	NSBundle *style = [NSBundle bundleWithIdentifier:[sender representedObject]];
	NSString *key = [NSString stringWithFormat:@"chat.style.%@.%@", [[self connection] server], _target];
	if( style ) {
		[[NSUserDefaults standardUserDefaults] setObject:[style bundleIdentifier] forKey:key];
	} else {
		[[NSUserDefaults standardUserDefaults] removeObjectForKey:key];
		style = [NSBundle bundleWithIdentifier:[[NSUserDefaults standardUserDefaults] objectForKey:@"JVChatDefaultStyle"]];
	}
	[self setChatStyle:style];*/
}

#pragma mark -

- (NSStringEncoding) encoding {
	return _encoding;
}

- (IBAction) changeEncoding:(id) sender {
	NSMenuItem *menuItem = nil;
	unsigned i = 0, count = 0;
	BOOL new = YES;
	if( ! [sender tag] ) {
		_encoding = (NSStringEncoding) [[self preferenceForKey:@"encoding"] intValue];
		if( ! _encoding ) _encoding = (NSStringEncoding) [[NSUserDefaults standardUserDefaults] integerForKey:@"JVChatEncoding"];
	} else _encoding = (NSStringEncoding) [sender tag];

	if( [[encodingView menu] numberOfItems] > 1 ) new = NO;

	for( i = 0; JVAllowedTextEncodings[i]; i++ ) {
		if( JVAllowedTextEncodings[i] == (NSStringEncoding) -1 ) {
			if( new ) [[encodingView menu] addItem:[NSMenuItem separatorItem]];
			continue;
		}
		if( new ) menuItem = [[[NSMenuItem alloc] initWithTitle:[NSString localizedNameOfStringEncoding:JVAllowedTextEncodings[i]] action:@selector( changeEncoding: ) keyEquivalent:@""] autorelease];
		else menuItem = (NSMenuItem *)[[encodingView menu] itemAtIndex:i + 1];
		if( _encoding == JVAllowedTextEncodings[i] ) {
			[menuItem setState:NSOnState];
		} else [menuItem setState:NSOffState];
		if( new ) {
			[menuItem setTag:JVAllowedTextEncodings[i]];
			[[encodingView menu] addItem:menuItem];
		}
	}

	if( ! _spillEncodingMenu ) _spillEncodingMenu = [[NSMenu alloc] initWithTitle:NSLocalizedString( @"Encoding", "encoding menu toolbar item" )];
	count = [_spillEncodingMenu numberOfItems];
	for( i = 0; i < count; i++ ) [_spillEncodingMenu removeItemAtIndex:0];
	count = [[encodingView menu] numberOfItems];
	for( i = 1; i < count; i++ ) [_spillEncodingMenu addItem:[[(NSMenuItem *)[[encodingView menu] itemAtIndex:i] copy] autorelease]];

	if( _encoding != (NSStringEncoding) [[NSUserDefaults standardUserDefaults] integerForKey:@"JVChatEncoding"] ) {
		[self setPreference:[NSNumber numberWithInt:_encoding] forKey:@"encoding"];
	} else [self setPreference:nil forKey:@"encoding"];
}

#pragma mark -

- (void) addEventMessageToDisplay:(NSString *) message withName:(NSString *) name andAttributes:(NSDictionary *) attributes {
	NSEnumerator *enumerator = nil, *kenumerator = nil;
	NSString *key = nil, *value = nil;
	NSMutableString *messageString = nil;
	xmlDocPtr doc = NULL, msgDoc = NULL;
	xmlNodePtr root = NULL, child = NULL;
	const char *msgStr = NULL;

	NSParameterAssert( name != nil );
	NSParameterAssert( [name length] );

	if( ! _nibLoaded ) [self view];

	doc = xmlNewDoc( "1.0" );
	root = xmlNewNode( NULL, "event" );
	xmlSetProp( root, "name", [name UTF8String] );
	xmlSetProp( root, "occurred", [[[NSDate date] description] UTF8String] );
	xmlDocSetRootElement( doc, root );

	if( message ) {
		msgStr = [[NSString stringWithFormat:@"<message>%@</message>", message] UTF8String];
		if( msgStr ) {
			msgDoc = xmlParseMemory( msgStr, strlen( msgStr ) );
			child = xmlDocCopyNode( xmlDocGetRootElement( msgDoc ), doc, 1 );
			xmlAddChild( root, child );
			xmlFreeDoc( msgDoc );
		}
	}

	kenumerator = [attributes keyEnumerator];
	enumerator = [attributes objectEnumerator];
	while( ( key = [kenumerator nextObject] ) && ( value = [enumerator nextObject] ) ) {
		if( [value isMemberOfClass:[NSNull class]] )
			msgStr = [[NSString stringWithFormat:@"<%@ />", key] UTF8String];			
		else msgStr = [[NSString stringWithFormat:@"<%@>%@</%@>", key, value, key] UTF8String];
		if( msgStr ) {
			msgDoc = xmlParseMemory( msgStr, strlen( msgStr ) );
			child = xmlDocCopyNode( xmlDocGetRootElement( msgDoc ), doc, 1 );
			xmlAddChild( root, child );
			xmlFreeDoc( msgDoc );
		}
	}

	if( [_logLock tryLock] ) {
		xmlAddChild( xmlDocGetRootElement( _xmlLog ), xmlDocCopyNode( root, _xmlLog, 1 ) );

		if( _firstMessage ) { // If we just got a private message and this panel was just opened WebKit hasn't had time load the template.
			[[display mainFrame] loadHTMLString:[self _fullDisplayHTMLWithBody:[self _applyStyleOnXMLDocument:doc]] baseURL:nil];
		} else {
			messageString = [[[self _applyStyleOnXMLDocument:doc] mutableCopy] autorelease];
			if( [messageString length] ) {
				[messageString replaceOccurrencesOfString:@"\\" withString:@"\\\\" options:NSLiteralSearch range:NSMakeRange( 0, [messageString length] )];
				[messageString replaceOccurrencesOfString:@"\"" withString:@"\\\"" options:NSLiteralSearch range:NSMakeRange( 0, [messageString length] )];
				[messageString replaceOccurrencesOfString:@"\n" withString:@"" options:NSLiteralSearch range:NSMakeRange( 0, [messageString length] )];
				[display stringByEvaluatingJavaScriptFromString:[NSString stringWithFormat:@"documentAppend( \"%@\" ); scrollToBottom();", messageString]];
			}
		}

		[_logLock unlock];
	} else {
		if( ! _xmlQueue ) {
			_xmlQueue = xmlNewDoc( "1.0" );
			xmlDocSetRootElement( _xmlQueue, xmlNewNode( NULL, "queue" ) );
		}
		xmlAddChild( xmlDocGetRootElement( _xmlQueue ), xmlDocCopyNode( root, _xmlQueue, 1 ) );
	}

	xmlFreeDoc( doc );

	_firstMessage = NO;
}

- (void) addMessageToDisplay:(NSData *) message fromUser:(NSString *) user asAction:(BOOL) action {
	BOOL highlight = NO;
	xmlDocPtr doc = NULL, msgDoc = NULL;
	xmlNodePtr root = NULL, child = NULL;
	const char *msgStr = NULL;
	NSMutableString *messageString = nil;

	NSParameterAssert( message != nil );
	NSParameterAssert( user != nil );

	if( ! _nibLoaded ) [self view];

	messageString = [[[NSMutableString alloc] initWithData:message encoding:_encoding] autorelease];
	if( ! messageString ) {
		messageString = [NSMutableString stringWithCString:[message bytes] length:[message length]];
		[messageString appendFormat:@" <span class=\"error incompatible\">%@</span>", NSLocalizedString( @"incompatible encoding", "encoding of the message different than your current encoding" )];
	}

	if( ! [[NSUserDefaults standardUserDefaults] boolForKey:@"MVChatDisableLinkHighlighting"] )
		[self _makeHyperlinksInString:messageString];

	[self _preformEmoticonSubstitutionOnString:messageString];

	if( ! [user isEqualToString:[[self connection] nickname]] ) {
		NSEnumerator *enumerator = nil;
		NSMutableArray *names = nil;
		id item = nil;

//		if( _firstMessage ) MVChatPlaySoundForAction( @"MVChatFisrtMessageAction" );
//		if( ! _firstMessage ) MVChatPlaySoundForAction( @"MVChatAdditionalMessagesAction" );

		names = [[[[NSUserDefaults standardUserDefaults] stringArrayForKey:@"MVChatHighlightNames"] mutableCopy] autorelease];
		[names addObject:[[self connection] nickname]];
		enumerator = [names objectEnumerator];
		while( ( item = [enumerator nextObject] ) ) {
			if( [[messageString lowercaseString] rangeOfString:item].length ) {
//				MVChatPlaySoundForAction( @"MVChatMentionedAction" );
				_newHighlightMessage = YES;
				highlight = YES;
				break;
			}
		}

//		if( [[NSUserDefaults standardUserDefaults] boolForKey:@"MVChatBounceIconUntilFront"] )
//			[[NSApplication sharedApplication] requestUserAttention:NSCriticalRequest];
//		else [[NSApplication sharedApplication] requestUserAttention:NSInformationalRequest];
	}

	doc = xmlNewDoc( "1.0" );
	root = xmlNewNode( NULL, "envelope" );
	xmlSetProp( root, "count", [[NSString stringWithFormat:@"%d", _messageId++] UTF8String] );
	xmlSetProp( root, "received", [[[NSDate date] description] UTF8String] );
	xmlDocSetRootElement( doc, root );

	child = xmlNewTextChild( root, NULL, "sender", [user UTF8String] );
	if( [user isEqualToString:[[self connection] nickname]] ) xmlSetProp( child, "self", "yes" );

	msgStr = [[NSString stringWithFormat:@"<message>%@</message>", messageString] UTF8String];
	msgDoc = xmlParseMemory( msgStr, strlen( msgStr ) );

	child = xmlDocCopyNode( xmlDocGetRootElement( msgDoc ), doc, 1 );
	if( action ) xmlSetProp( child, "action", "yes" );
	if( highlight ) xmlSetProp( child, "highlight", "yes" );
	xmlAddChild( root, child );

	xmlFreeDoc( msgDoc );

	if( [_logLock tryLock] ) {
		xmlAddChild( xmlDocGetRootElement( _xmlLog ), xmlDocCopyNode( root, _xmlLog, 1 ) );

		if( _firstMessage ) { // If we just got a private message and this panel was just opened WebKit hasn't had time load the template.
			[[display mainFrame] loadHTMLString:[self _fullDisplayHTMLWithBody:[self _applyStyleOnXMLDocument:doc]] baseURL:nil];
		} else {
			messageString = [[[self _applyStyleOnXMLDocument:doc] mutableCopy] autorelease];
			if( [messageString length] ) {
				[messageString replaceOccurrencesOfString:@"\\" withString:@"\\\\" options:NSLiteralSearch range:NSMakeRange( 0, [messageString length] )];
				[messageString replaceOccurrencesOfString:@"\"" withString:@"\\\"" options:NSLiteralSearch range:NSMakeRange( 0, [messageString length] )];
				[messageString replaceOccurrencesOfString:@"\n" withString:@"" options:NSLiteralSearch range:NSMakeRange( 0, [messageString length] )];
				[display stringByEvaluatingJavaScriptFromString:[NSString stringWithFormat:@"documentAppend( \"%@\" ); scrollToBottom();", messageString]];
			}
		}

		[_logLock unlock];
	} else {
		if( ! _xmlQueue ) {
			_xmlQueue = xmlNewDoc( "1.0" );
			xmlDocSetRootElement( _xmlQueue, xmlNewNode( NULL, "queue" ) );
		}
		xmlAddChild( xmlDocGetRootElement( _xmlQueue ), xmlDocCopyNode( root, _xmlQueue, 1 ) );
	}

	xmlFreeDoc( doc );

	_firstMessage = NO;
	_newMessage = YES;

	[_windowController reloadListItem:self andChildren:NO];
}

- (void) echoSentMessageToDisplay:(NSAttributedString *) message asAction:(BOOL) action {
	char *msg = NULL;
	NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:YES], @"NSHTMLIgnoreFontSizes", [NSNumber numberWithBool:[[NSUserDefaults standardUserDefaults] boolForKey:@"MVChatIgnoreColors"]], @"NSHTMLIgnoreFontColors", [NSNumber numberWithBool:[[NSUserDefaults standardUserDefaults] boolForKey:@"MVChatIgnoreFormatting"]], @"NSHTMLIgnoreFontTraits", nil];
	NSMutableData *msgData = [[[message HTMLWithOptions:options usingEncoding:_encoding allowLossyConversion:YES] mutableCopy] autorelease];
	[msgData appendBytes:"\0" length:1];

	msg = irc_html_to_irc( (const char * const) [msgData bytes] );
	msg = irc_irc_to_html( msg );

	[self addMessageToDisplay:[[[NSData dataWithBytes:msg length:strlen( msg )] retain] autorelease] fromUser:[[self connection] nickname] asAction:action];
}

#pragma mark -

- (IBAction) send:(id) sender {
	NSMutableAttributedString *subMsg = nil;
	BOOL action = NO;
	NSRange range;

	if( ! [[self connection] isConnected] || _cantSendMessages ) return;

	_historyIndex = 0;
	if( ! [[send textStorage] length] ) return;
	if( [_sendHistory count] )
		[_sendHistory replaceObjectAtIndex:0 withObject:[[[NSAttributedString alloc] initWithString:@""] autorelease]];
	[_sendHistory insertObject:[[[send textStorage] copy] autorelease] atIndex:1];
	if( [_sendHistory count] > [[[NSUserDefaults standardUserDefaults] objectForKey:@"JVChatMaximumHistory"] unsignedIntValue] )
		[_sendHistory removeObjectAtIndex:[_sendHistory count] - 1];

	if( [sender isKindOfClass:[NSNumber class]] && [sender boolValue] ) action = YES;

	[[[send textStorage] mutableString] replaceOccurrencesOfString:@"&" withString:@"&amp;" options:NSLiteralSearch range:NSMakeRange( 0, [[send textStorage] length] )];
	[[[send textStorage] mutableString] replaceOccurrencesOfString:@"<" withString:@"&lt;" options:NSLiteralSearch range:NSMakeRange( 0, [[send textStorage] length] )];
	[[[send textStorage] mutableString] replaceOccurrencesOfString:@">" withString:@"&gt;" options:NSLiteralSearch range:NSMakeRange( 0, [[send textStorage] length] )];
	[[[send textStorage] mutableString] replaceOccurrencesOfString:@"\"" withString:@"&quot;" options:NSLiteralSearch range:NSMakeRange( 0, [[send textStorage] length] )];
	[[[send textStorage] mutableString] replaceOccurrencesOfString:@"'" withString:@"&apos;" options:NSLiteralSearch range:NSMakeRange( 0, [[send textStorage] length] )];
	[[[send textStorage] mutableString] replaceOccurrencesOfString:@"\r" withString:@"\n" options:NSLiteralSearch range:NSMakeRange( 0, [[send textStorage] length] )];

	while( [[send textStorage] length] ) {
		range = [[[send textStorage] string] rangeOfString:@"\n"];
		if( ! range.length ) range.location = [[send textStorage] length];
		subMsg = [[[[send textStorage] attributedSubstringFromRange:NSMakeRange( 0, range.location )] mutableCopy] autorelease];

		if( ( [subMsg length] >= 1 && range.length ) || ( [subMsg length] && ! range.length ) ) {
			if( [[subMsg string] hasPrefix:@"/"] ) {
				BOOL handled = NO;
				NSScanner *scanner = [NSScanner scannerWithString:[subMsg string]];
				NSString *command = nil;
				NSAttributedString *arguments = nil;

				[scanner scanString:@"/" intoString:nil];
				[scanner scanUpToCharactersFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet] intoString:&command];
				if( [[subMsg string] length] >= [scanner scanLocation] + 1 )
					[scanner setScanLocation:[scanner scanLocation] + 1];

				arguments = [subMsg attributedSubstringFromRange:NSMakeRange( [scanner scanLocation], range.location - [scanner scanLocation] )];

				handled = [self processUserCommand:command withArguments:arguments];

				if( ! handled ) {
//					NSRunInformationalAlertPanel( NSLocalizedString( @"Command not recognised", "IRC command not recognised dialog title" ), NSLocalizedString( @"The command you specified is not recognised by Colloquy or it's plugins. No action can be performed.", "IRC command not recognised dialog message" ), nil, nil, nil );
					[[self connection] sendRawMessage:[command stringByAppendingFormat:@" %@", [arguments string]]];
//					return;
				}
			} else {
/*				if( [[NSUserDefaults standardUserDefaults] boolForKey:@"MVChatNaturalActions"] && ! action ) {
					extern NSArray *chatActionVerbs;
					NSString *tempString = [[subMsg string] stringByAppendingString:@" "];
					enumerator = [chatActionVerbs objectEnumerator];
					while( ( item = [enumerator nextObject] ) ) {
						if( [tempString hasPrefix:[item stringByAppendingString:@" "]] ) {
							action = YES;
							break;
						}
					}
				}*/

				subMsg = [self sendAttributedMessage:subMsg asAction:action];
				[self echoSentMessageToDisplay:subMsg asAction:action];
			}
		}
		if( range.length ) range.location++;
		[[send textStorage] deleteCharactersInRange:NSMakeRange( 0, range.location )];
	}

	[send reset:nil];
	[display stringByEvaluatingJavaScriptFromString:@"document.body.scrollTop = document.body.offsetHeight;"];
}

- (BOOL) processUserCommand:(NSString *) command withArguments:(NSAttributedString *) arguments {
	BOOL handled = NO;
	id item = nil;
	NSEnumerator *enumerator = [[[MVChatPluginManager defaultManager] pluginsThatRespondToSelector:@selector( processUserCommand:withArguments:toUser:forConnection: )] objectEnumerator];

	while( ( item = [enumerator nextObject] ) ) {
		handled = [item processUserCommand:command withArguments:arguments toUser:[self target] forConnection:[self connection]];
		if( handled ) break;
	}

	return handled;
}

- (NSMutableAttributedString *) sendAttributedMessage:(NSMutableAttributedString *) message asAction:(BOOL) action {
	id item = nil;
	NSEnumerator *enumerator = [[[MVChatPluginManager defaultManager] pluginsThatRespondToSelector:@selector( processPrivateMessage:toUser:asAction:forConnection: )] objectEnumerator];

	while( ( item = [enumerator nextObject] ) )
		message = [item processPrivateMessage:message toUser:[self target] asAction:action forConnection:[self connection]];

	[[self connection] sendMessageToUser:[self target] attributedMessage:message withEncoding:_encoding asAction:action];

	return message;
}

#pragma mark -

- (IBAction) clear:(id) sender {
	[send reset:nil];
}

- (IBAction) clearDisplay:(id) sender {
	[[display mainFrame] loadHTMLString:[self _fullDisplayHTMLWithBody:@""] baseURL:nil];
}

#pragma mark -

- (BOOL) textView:(NSTextView *) textView enterHit:(NSEvent *) event {
	BOOL ret = NO;
	if( [[NSUserDefaults standardUserDefaults] boolForKey:@"MVChatSendOnEnter"] ) {
		[self send:nil];
		ret = YES;
	} else if( [[NSUserDefaults standardUserDefaults] boolForKey:@"MVChatActionOnEnter"] ) {
		[self send:[NSNumber numberWithBool:YES]];
		ret = YES;
	}
	return ret;
}

- (BOOL) textView:(NSTextView *) textView returnHit:(NSEvent *) event {
	BOOL ret = NO;
	if( [[NSUserDefaults standardUserDefaults] boolForKey:@"MVChatSendOnReturn"] ) {
		[self send:nil];
		ret = YES;
	} else if( [[NSUserDefaults standardUserDefaults] boolForKey:@"MVChatActionOnReturn"] ) {
		[self send:[NSNumber numberWithBool:YES]];
		ret = YES;
	}
	return ret;
}

- (BOOL) textView:(NSTextView *) textView upArrowHit:(NSEvent *) event {
	if( ! _historyIndex && [_sendHistory count] )
		[_sendHistory replaceObjectAtIndex:0 withObject:[[[send textStorage] copy] autorelease]];
	_historyIndex++;
	if( _historyIndex >= [_sendHistory count] ) {
		_historyIndex = [_sendHistory count] - 1;
		if( (signed) _historyIndex < 0 ) _historyIndex = 0;
		return YES;
	}
	[send reset:nil];
	[[send textStorage] insertAttributedString:[_sendHistory objectAtIndex:_historyIndex] atIndex:0];
	return YES;
}

- (BOOL) textView:(NSTextView *) textView downArrowHit:(NSEvent *) event {
	if( ! _historyIndex && [_sendHistory count] )
		[_sendHistory replaceObjectAtIndex:0 withObject:[[[send textStorage] copy] autorelease]];
	if( [[send textStorage] length] ) _historyIndex--;
	if( _historyIndex < 0 ) {
		[send reset:nil];
		_historyIndex = -1;
		return YES;
	} else if( ! [_sendHistory count] ) {
		_historyIndex = 0;
		return YES;
	}
	[send reset:nil];
	[[send textStorage] insertAttributedString:[_sendHistory objectAtIndex:_historyIndex] atIndex:0];
	return YES;
}

- (BOOL) textView:(NSTextView *) textView tabHit:(NSEvent *) event {
	if( [[NSUserDefaults standardUserDefaults] boolForKey:@"JVUsePantherTextCompleteOnTab"] ) {
		[textView complete:nil];
		return YES;
	}
	return NO;
}	
	
- (void) textDidChange:(NSNotification *) notification {
	_historyIndex = 0;
}

#pragma mark -

- (BOOL) splitView:(NSSplitView *) sender canCollapseSubview:(NSView *) subview {
	return NO;
}

- (float) splitView:(NSSplitView *) splitView constrainSplitPosition:(float) proposedPosition ofSubviewAt:(int) index {
//	float position = ( NSHeight( [splitView frame] ) - proposedPosition - [splitView dividerThickness] );
//	int lines = (int) floorf( position / 15. );
//	NSLog( @"%.2f %.2f / 15. = %.2f (%d)", proposedPosition, position, position / 15., lines );
	return ( roundf( proposedPosition / 15. ) * 15. ) + [splitView dividerThickness] + 2.;
	return proposedPosition;
}

#pragma mark -

- (NSToolbarItem *) toolbar:(NSToolbar *) toolbar itemForItemIdentifier:(NSString *) identifier willBeInsertedIntoToolbar:(BOOL) willBeInserted {
	NSToolbarItem *toolbarItem = nil;
	if( [identifier isEqual:JVToolbarTextEncodingItemIdentifier] ) {
		NSMenuItem *menuItem = nil;
		toolbarItem = [[[NSToolbarItem alloc] initWithItemIdentifier:identifier] autorelease];

		[toolbarItem setLabel:NSLocalizedString( @"Encoding", "encoding menu toolbar item" )];
		[toolbarItem setPaletteLabel:NSLocalizedString( @"Text Encoding", "encoding menu toolbar customize palette name" )];

		[toolbarItem setTarget:nil];
		[toolbarItem setAction:NULL];

		[toolbarItem setToolTip:NSLocalizedString( @"Text Encoding Options", "encoding menu toolbar item tooltip" )];
		[toolbarItem setView:encodingView];
		[toolbarItem setMinSize:NSMakeSize( 60., 24. )];
		[toolbarItem setMaxSize:NSMakeSize( 60., 32. )];

		menuItem = [[[NSMenuItem alloc] initWithTitle:NSLocalizedString( @"Encoding", "encoding menu toolbar item" ) action:NULL keyEquivalent:@""] autorelease];
		[menuItem setImage:[NSImage imageNamed:@"encoding"]];
		[menuItem setSubmenu:_spillEncodingMenu];

		[toolbarItem setMenuFormRepresentation:menuItem];
	} else if( [identifier isEqual:JVToolbarBoldFontItemIdentifier] ) {
		toolbarItem = [[[NSToolbarItem alloc] initWithItemIdentifier:identifier] autorelease];

		[toolbarItem setLabel:NSLocalizedString( @"Bold", "bold font toolbar item" )];
		[toolbarItem setPaletteLabel:NSLocalizedString( @"Bold", "bold font toolbar item" )];

		[toolbarItem setToolTip:NSLocalizedString( @"Toggle Bold Style", "bold font tooltip" )];
		[toolbarItem setImage:[NSImage imageNamed:@"bold"]];

		[toolbarItem setTarget:send];
		[toolbarItem setAction:@selector( bold: )];
	} else if( [identifier isEqual:JVToolbarItalicFontItemIdentifier] ) {
		toolbarItem = [[[NSToolbarItem alloc] initWithItemIdentifier:identifier] autorelease];
		
		[toolbarItem setLabel:NSLocalizedString( @"Italic", "italic font style toolbar item" )];
		[toolbarItem setPaletteLabel:NSLocalizedString( @"Italic", "italic font style toolbar item" )];

		[toolbarItem setToolTip:NSLocalizedString( @"Toggle Italic Style", "italic style tooltip" )];
		[toolbarItem setImage:[NSImage imageNamed:@"italic"]];

		[toolbarItem setTarget:send];
		[toolbarItem setAction:@selector( italic: )];
	} else if( [identifier isEqual:JVToolbarUnderlineFontItemIdentifier] ) {
		toolbarItem = [[[NSToolbarItem alloc] initWithItemIdentifier:identifier] autorelease];
		
		[toolbarItem setLabel:NSLocalizedString( @"Underline", "underline font style toolbar item" )];
		[toolbarItem setPaletteLabel:NSLocalizedString( @"Underline", "underline font style toolbar item" )];

		[toolbarItem setToolTip:NSLocalizedString( @"Toggle Underline Style", "underline style tooltip" )];
		[toolbarItem setImage:[NSImage imageNamed:@"underline"]];

		[toolbarItem setTarget:send];
		[toolbarItem setAction:@selector( underline: )];
	} else return [super toolbar:toolbar itemForItemIdentifier:identifier willBeInsertedIntoToolbar:willBeInserted];
	return toolbarItem;
}

- (NSArray *) toolbarDefaultItemIdentifiers:(NSToolbar *) toolbar {
	NSMutableArray *list = [NSMutableArray arrayWithArray:[super toolbarDefaultItemIdentifiers:toolbar]];
	return list;
}

- (NSArray *) toolbarAllowedItemIdentifiers:(NSToolbar *) toolbar {
	NSMutableArray *list = [NSMutableArray arrayWithArray:[super toolbarAllowedItemIdentifiers:toolbar]];
	[list addObject:JVToolbarTextEncodingItemIdentifier];
	[list addObject:JVToolbarBoldFontItemIdentifier];
	[list addObject:JVToolbarItalicFontItemIdentifier];
	[list addObject:JVToolbarUnderlineFontItemIdentifier];
	return list;
}

- (BOOL) validateToolbarItem:(NSToolbarItem *) toolbarItem {
	return [super validateToolbarItem:toolbarItem];
}
@end

#pragma mark -

@implementation JVDirectChat (JVDirectChatPrivate)
- (NSMenu *) _encodingMenu {
	if( ! _nibLoaded ) [self view];
	return [[[encodingView menu] retain] autorelease];
}

- (void) _makeHyperlinksInString:(NSMutableString *) string {
	unsigned i = 0, c = 0;
	NSMutableArray *parts = nil;
	NSMutableString *part = nil;
	NSScanner *urlScanner = nil;
	NSCharacterSet *urlStopSet = [NSCharacterSet characterSetWithCharactersInString:@" \t\n\r\"'!<>[]{}()|*^!"];
	NSCharacterSet *ircChannels = [NSCharacterSet characterSetWithCharactersInString:@"#&+"];
	NSCharacterSet *seperaters = [NSCharacterSet characterSetWithCharactersInString:@"<> \t\n\r"];
	NSString *link = nil, *urlHandle = nil;
	NSMutableString *mutableLink = nil;
	BOOL inTag = NO;
	NSRange range, srange;

	srange = NSMakeRange( 0, [string length] );
	range = [string rangeOfCharacterFromSet:seperaters options:NSLiteralSearch range:srange];
	while( range.location != NSNotFound ) {
		if( [string characterAtIndex:range.location] == '<' ) {
			[string insertString:@"\033" atIndex:range.location];
			inTag = ! inTag;
		} else if( [string characterAtIndex:range.location] == '>' ) {
			[string insertString:@"\033" atIndex:range.location + 1];
			inTag = ! inTag;
		} else if( [string characterAtIndex:range.location] == ' ' && ! inTag ) {
			[string insertString:@"\033" atIndex:range.location + 1];
		}
		if( range.location >= [string length] ) break;
		srange = NSMakeRange( range.location + 2, [string length] - range.location - 2 );
		range = [string rangeOfCharacterFromSet:seperaters options:NSLiteralSearch range:srange];
	}

	parts = [[[string componentsSeparatedByString:@"\033"] mutableCopy] autorelease];

	for( i = 0, c = [parts count]; i < c; i++ ) {
		part = [[[parts objectAtIndex:i] mutableCopy] autorelease];
		
		if( ! [part length] || ( [part length] >= 1 && [part characterAtIndex:0] == '<' ) )
			continue;

		// escape the special entities
		[part replaceOccurrencesOfString:@"*" withString:@"*star;" options:NSLiteralSearch range:NSMakeRange( 0, [part length] )];
		[part replaceOccurrencesOfString:@"<" withString:@"*lt;" options:NSLiteralSearch range:NSMakeRange( 0, [part length] )];
		[part replaceOccurrencesOfString:@">" withString:@"*gt;" options:NSLiteralSearch range:NSMakeRange( 0, [part length] )];
		[part replaceOccurrencesOfString:@"\"" withString:@"*quot;" options:NSLiteralSearch range:NSMakeRange( 0, [part length] )];
		[part replaceOccurrencesOfString:@"'" withString:@"*apos;" options:NSLiteralSearch range:NSMakeRange( 0, [part length] )];

		[part replaceOccurrencesOfString:@"&lt;" withString:@"<" options:NSLiteralSearch range:NSMakeRange( 0, [part length] )];
		[part replaceOccurrencesOfString:@"&gt;" withString:@">" options:NSLiteralSearch range:NSMakeRange( 0, [part length] )];
		[part replaceOccurrencesOfString:@"&quot;" withString:@"\"" options:NSLiteralSearch range:NSMakeRange( 0, [part length] )];
		[part replaceOccurrencesOfString:@"&apos;" withString:@"'" options:NSLiteralSearch range:NSMakeRange( 0, [part length] )];

		[part replaceOccurrencesOfString:@"&amp;" withString:@"~amp;" options:NSLiteralSearch range:NSMakeRange( 0, [part length] )];
		[part replaceOccurrencesOfString:@"&" withString:@"*amp;" options:NSLiteralSearch range:NSMakeRange( 0, [part length] )];
		[part replaceOccurrencesOfString:@"~amp;" withString:@"&" options:NSLiteralSearch range:NSMakeRange( 0, [part length] )];

		// catch well-formed urls like "http://www.apple.com" or "irc://irc.javelin.cc"
		urlScanner = [NSScanner scannerWithString:part];
		[urlScanner scanUpToCharactersFromSet:[urlStopSet invertedSet] intoString:NULL];
		if( [urlScanner scanUpToString:@"://" intoString:&urlHandle] && [urlScanner scanUpToCharactersFromSet:urlStopSet intoString:&link] ) {
			if( [link characterAtIndex:([link length] - 1)] == '.' || [link characterAtIndex:([link length] - 1)] == '?' )
				link = [link substringToIndex:( [link length] - 1 )];
			link = [urlHandle stringByAppendingString:link];
			if( [link length] >= 7 ) {
				mutableLink = [[link mutableCopy] autorelease];
				[mutableLink replaceOccurrencesOfString:@"/" withString:@"/*amp;#8203;" options:NSLiteralSearch range:NSMakeRange( 0, [mutableLink length] )];
				[mutableLink replaceOccurrencesOfString:@"+" withString:@"+*amp;#8203;" options:NSLiteralSearch range:NSMakeRange( 0, [mutableLink length] )];
				[mutableLink replaceOccurrencesOfString:@"%" withString:@"*amp;#8203;%" options:NSLiteralSearch range:NSMakeRange( 0, [mutableLink length] )];
				[mutableLink replaceOccurrencesOfString:@"&" withString:@"*amp;#8203;&" options:NSLiteralSearch range:NSMakeRange( 0, [mutableLink length] )];
				[part replaceOccurrencesOfString:link withString:[NSString stringWithFormat:@"*lt;a href=*quot;%@*quot;*gt;%@*lt;/a*gt;", link, mutableLink] options:NSLiteralSearch range:NSMakeRange( 0, [part length] )];
				goto finish;
			}
		}

		// catch well-formed email addresses like "timothy@hatcher.name" or "timothy@javelin.cc"
		urlStopSet = [NSCharacterSet characterSetWithCharactersInString:@" \t\n\r\"'@,!<>[]{}()|*^!"];
		urlScanner = [NSScanner scannerWithString:part];
		[urlScanner scanUpToCharactersFromSet:[urlStopSet invertedSet] intoString:NULL];
		if( [urlScanner scanUpToString:@"@" intoString:&urlHandle] && [urlScanner scanUpToCharactersFromSet:urlStopSet intoString:&link] ) {
			if( [link characterAtIndex:([link length] - 1)] == '.' || [link characterAtIndex:([link length] - 1)] == '?' )
				link = [link substringToIndex:( [link length] - 1 )];
			NSRange hasPeriod = [link rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"."]];
			if( [urlHandle length] && [link length] && hasPeriod.location < ([link length] - 1) && hasPeriod.location != NSNotFound ) {
				link = [urlHandle stringByAppendingString:link];
				[part replaceOccurrencesOfString:link withString:[NSString stringWithFormat:@"*lt;a href=*quot;mailto:%@*quot;*gt;%@*lt;/a*gt;", link, link] options:NSLiteralSearch range:NSMakeRange( 0, [part length] )];
				goto finish;
			}
		}

		// catch well-formed IRC channel names like "#php" or "&admins"
		urlStopSet = [NSCharacterSet characterSetWithCharactersInString:@" \t\n\r\"',!<>[]{}()|*^!"];
		urlScanner = [NSScanner scannerWithString:part];
		if( ( ( [urlScanner scanUpToCharactersFromSet:ircChannels intoString:NULL] && [urlScanner scanLocation] < [part length] && ! [[NSCharacterSet alphanumericCharacterSet] characterIsMember:[part characterAtIndex:( [urlScanner scanLocation] - 1 )]] ) || [part rangeOfCharacterFromSet:ircChannels].location == 0 ) && [urlScanner scanUpToCharactersFromSet:urlStopSet intoString:&urlHandle] ) {
			if( [urlHandle length] >= 3 && [urlHandle rangeOfCharacterFromSet:[NSCharacterSet decimalDigitCharacterSet]].location != 1 ) {
				if( [urlHandle characterAtIndex:([urlHandle length] - 1)] == '.' || [urlHandle characterAtIndex:([urlHandle length] - 1)] == '?' )
					urlHandle = [urlHandle substringToIndex:( [urlHandle length] - 1 )];
				link = [NSString stringWithFormat:@"irc://%@/%@", [[self connection] server], urlHandle];
				link = [NSString stringWithFormat:@"*lt;a href=*quot;%@*quot;*gt;%@*lt;/a*gt;", link, urlHandle];
				[part replaceOccurrencesOfString:urlHandle withString:link options:NSLiteralSearch range:NSMakeRange( 0, [part length] )];
				goto finish;
			}
		}

		continue;

	finish:
		// un-escape the special entities
		[part replaceOccurrencesOfString:@"&" withString:@"~amp;" options:NSLiteralSearch range:NSMakeRange( 0, [part length] )];
		[part replaceOccurrencesOfString:@"*amp;" withString:@"&" options:NSLiteralSearch range:NSMakeRange( 0, [part length] )];
		[part replaceOccurrencesOfString:@"~amp;" withString:@"&amp;" options:NSLiteralSearch range:NSMakeRange( 0, [part length] )];

		[part replaceOccurrencesOfString:@"<" withString:@"&lt;" options:NSLiteralSearch range:NSMakeRange( 0, [part length] )];
		[part replaceOccurrencesOfString:@">" withString:@"&gt;" options:NSLiteralSearch range:NSMakeRange( 0, [part length] )];
		[part replaceOccurrencesOfString:@"\"" withString:@"&quot;" options:NSLiteralSearch range:NSMakeRange( 0, [part length] )];
		[part replaceOccurrencesOfString:@"'" withString:@"&apos;" options:NSLiteralSearch range:NSMakeRange( 0, [part length] )];

		[part replaceOccurrencesOfString:@"*lt;" withString:@"<" options:NSLiteralSearch range:NSMakeRange( 0, [part length] )];
		[part replaceOccurrencesOfString:@"*gt;" withString:@">" options:NSLiteralSearch range:NSMakeRange( 0, [part length] )];
		[part replaceOccurrencesOfString:@"*quot;" withString:@"\"" options:NSLiteralSearch range:NSMakeRange( 0, [part length] )];
		[part replaceOccurrencesOfString:@"*apos;" withString:@"'" options:NSLiteralSearch range:NSMakeRange( 0, [part length] )];
		[part replaceOccurrencesOfString:@"*star;" withString:@"*" options:NSLiteralSearch range:NSMakeRange( 0, [part length] )];

		[parts replaceObjectAtIndex:i withObject:part];
	}

	[string setString:[parts componentsJoinedByString:@""]];
}

- (void) _breakLongLinesInString:(NSMutableString *) string { // Not good on strings that have prior HTML or HTML entities
	NSScanner *scanner = [NSScanner scannerWithString:string];
	NSCharacterSet *stopSet = [NSCharacterSet whitespaceAndNewlineCharacterSet];
	unsigned int lastLoc = 0;

	while( ! [scanner isAtEnd] ) {
		lastLoc = [scanner scanLocation];
		[scanner scanUpToCharactersFromSet:stopSet intoString:nil];
		if( ( [scanner scanLocation] - lastLoc ) > 34 ) { // Who says "supercalifragilisticexpialidocious" anyway?
			unsigned int times = (unsigned int) ( ( [scanner scanLocation] - lastLoc ) / 34 );
			while( times > 0 ) {
				[string insertString:@"&#8203;" atIndex:( lastLoc + ( times * 34 ) )];
				times--;
			}
		}
	}
}

- (void) _preformEmoticonSubstitutionOnString:(NSMutableString *) string {
	NSMutableString *str = nil;
	NSEnumerator *keyEnumerator = [_emoticonMappings keyEnumerator];
	NSEnumerator *objEnumerator = [_emoticonMappings objectEnumerator];
	NSEnumerator *srcEnumerator = nil;
	id key = nil, obj = nil;
	BOOL moreReplacements = YES;

	while( ( key = [keyEnumerator nextObject] ) && ( obj = [objEnumerator nextObject] ) ) {
		srcEnumerator = [obj objectEnumerator];
		while( ( str = [srcEnumerator nextObject] ) ) {
			str = [[str mutableCopy] autorelease];
			[str replaceOccurrencesOfString:@"&" withString:@"&amp;" options:NSLiteralSearch range:NSMakeRange( 0, [str length] )];
			[str replaceOccurrencesOfString:@"<" withString:@"&lt;" options:NSLiteralSearch range:NSMakeRange( 0, [str length] )];
			[str replaceOccurrencesOfString:@">" withString:@"&gt;" options:NSLiteralSearch range:NSMakeRange( 0, [str length] )];
			moreReplacements = YES;
			while( moreReplacements ) {
				NSRange range = [string rangeOfString:str];
				if( range.length ) {
					if( (signed)( range.location - 1 ) >= 0 && [string characterAtIndex:( range.location - 1 )] != ' ' )
						break;
					if( (signed)( range.location + [str length] ) < [string length] && [string characterAtIndex:( range.location + [str length] )] != ' ' )
						break;
					[string replaceCharactersInRange:range withString:[NSString stringWithFormat:@"<span class=\"emoticon %@\"><samp>%@</samp></span>", key, str]];
				} else moreReplacements = NO;
			}
		}
	}
}

- (void) _alertSheetDidEnd:(NSWindow *) sheet returnCode:(int) returnCode contextInfo:(void *) contextInfo {
	NSEnumerator *kenumerator = nil, *enumerator = nil;
	id key = nil, value = nil;

	[[NSApplication sharedApplication] endSheet:sheet];
	[sheet orderOut:nil];

	[_waitingAlerts removeObjectIdenticalTo:sheet];

	kenumerator = [_waitingAlertNames keyEnumerator];
	enumerator = [_waitingAlertNames objectEnumerator];
	while( ( key = [kenumerator nextObject] ) && ( value = [enumerator nextObject] ) )
		if( value == sheet ) break;

	if( key ) [_waitingAlertNames removeObjectForKey:key];

	NSReleaseAlertPanel( sheet );

	if( [_waitingAlerts count] )
		[[NSApplication sharedApplication] beginSheet:[_waitingAlerts objectAtIndex:0] modalForWindow:[_windowController window] modalDelegate:self didEndSelector:@selector( _alertSheetDidEnd:returnCode:contextInfo: ) contextInfo:NULL];
}

- (void) _didConnect:(NSNotification *) notification {
	[self showAlert:nil withName:@"disconnected"]; // cancel the disconnected alert
	_cantSendMessages = NO;
}

- (void) _didDisconnect:(NSNotification *) notification {
	[self showAlert:NSGetInformationalAlertPanel( NSLocalizedString( @"You're now offline", "title of the you're offline message sheet" ), NSLocalizedString( @"You are no longer connected to the server where you were chatting. No messages can be sent at this time. Reconnecting might be in progress.", "chat window error description for loosing connection" ), @"OK", nil, nil ) withName:@"disconnected"];
	_cantSendMessages = YES;
}
@end