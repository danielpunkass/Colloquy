#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import <AGRegex/AGRegex.h>
#import <ChatCore/NSColorAdditions.h>
#import <ChatCore/NSStringAdditions.h>

#import "JVAppearancePreferences.h"
#import "JVChatTranscriptPrivates.h"
#import "JVFontPreviewField.h"
#import "JVColorWellCell.h"
#import "JVDetailCell.h"

#import <libxml/xinclude.h>
#import <libxslt/transform.h>
#import <libxslt/xsltutils.h>

@implementation JVAppearancePreferences
- (id) init {
	if( ( self = [super init] ) ) {
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector( colorWellDidChangeColor: ) name:JVColorWellCellColorDidChangeNotification object:nil];

		[JVChatTranscript _scanForChatStyles];
		[JVChatTranscript _scanForEmoticons];

		_styleBundles = [[JVChatTranscript _chatStyleBundles] retain];
		_emoticonBundles = [[JVChatTranscript _emoticonBundles] retain];
	}
	return self;
}

- (void) dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];

	[_styleBundles release];
	[_emoticonBundles release];

	_styleBundles = nil;
	_emoticonBundles = nil;

	[super dealloc];
}

- (NSString *) preferencesNibName {
	return @"JVAppearancePreferences";
}

- (BOOL) hasChangesPending {
	return NO;
}

- (NSImage *) imageForPreferenceNamed:(NSString *) name {
	return [[[NSImage imageNamed:@"AppearancePreferences"] retain] autorelease];
}

- (BOOL) isResizable {
	return NO;
}

- (void) moduleWillBeRemoved {
	[optionsDrawer close];
}

#pragma mark -

- (void) initializeFromDefaults {
	[preview setPolicyDelegate:self];
	[optionsTable setRefusesFirstResponder:YES];

	NSTableColumn *column = [optionsTable tableColumnWithIdentifier:@"key"];
	JVDetailCell *prototypeCell = [[JVDetailCell new] autorelease];
	[prototypeCell setFont:[NSFont boldSystemFontOfSize:11.]];
	[prototypeCell setAlignment:NSRightTextAlignment];
	[column setDataCell:prototypeCell];

	[self changePreferences:nil];
}

- (IBAction) changeBaseFontSize:(id) sender {
	int size = [sender intValue];
	[baseFontSize setIntValue:size];
	[baseFontSizeStepper setIntValue:size];
	[[preview preferences] setDefaultFontSize:size];
}

- (IBAction) changeMinimumFontSize:(id) sender {
	int size = [sender intValue];
	[minimumFontSize setIntValue:size];
	[minimumFontSizeStepper setIntValue:size];
	[[preview preferences] setMinimumFontSize:size];
}

- (IBAction) changeDefaultChatStyle:(id) sender {
	NSString *variant = [[sender representedObject] objectForKey:@"variant"];
	NSString *style = [[sender representedObject] objectForKey:@"style"];

	[[NSUserDefaults standardUserDefaults] setObject:style forKey:@"JVChatDefaultStyle"];
	if( ! variant ) [[NSUserDefaults standardUserDefaults] removeObjectForKey:[NSString stringWithFormat:@"JVChatDefaultStyleVariant %@", style]];
	else [[NSUserDefaults standardUserDefaults] setObject:variant forKey:[NSString stringWithFormat:@"JVChatDefaultStyleVariant %@", style]];

	[self performSelector:@selector( changePreferences: ) withObject:nil afterDelay:0.];
}

- (void) changePreferences:(id) sender {
	[self updateChatStylesMenu];
	[self updateEmoticonsMenu];

	NSBundle *style = [NSBundle bundleWithIdentifier:[[NSUserDefaults standardUserDefaults] objectForKey:@"JVChatDefaultStyle"]];

	[_styleOptions autorelease];
	_styleOptions = [[NSMutableArray arrayWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"styleOptions" ofType:@"plist"]] retain];
	if( [style objectForInfoDictionaryKey:@"JVStyleOptions"] )
		[_styleOptions addObjectsFromArray:[[[style objectForInfoDictionaryKey:@"JVStyleOptions"] mutableCopy] autorelease]];

	[preview setPreferencesIdentifier:[[NSUserDefaults standardUserDefaults] objectForKey:@"JVChatDefaultStyle"]];
	// we shouldn't have to post this notification manually, but this seems to make webkit refresh with new prefs
	[[NSNotificationCenter defaultCenter] postNotificationName:@"WebPreferencesChangedNotification" object:[preview preferences]];

	WebPreferences *prefs = [preview preferences];
	[prefs setAutosaves:YES];

	[standardFont setFont:[NSFont fontWithName:[prefs standardFontFamily] size:[prefs defaultFontSize]]];

	[minimumFontSize setIntValue:[prefs minimumFontSize]];
	[minimumFontSizeStepper setIntValue:[prefs minimumFontSize]];

	[baseFontSize setIntValue:[prefs defaultFontSize]];
	[baseFontSizeStepper setIntValue:[prefs defaultFontSize]];

	[self setUserStyle:[NSString stringWithContentsOfFile:[[[preview preferences] userStyleSheetLocation] path]]];

	[self updatePreview];
	[self parseUserStyleOptions];
}

- (IBAction) noGraphicEmoticons:(id) sender {
	NSString *style = [[NSUserDefaults standardUserDefaults] objectForKey:@"JVChatDefaultStyle"];
	[[NSUserDefaults standardUserDefaults] setObject:@"" forKey:[NSString stringWithFormat:@"JVChatDefaultEmoticons %@", style]];
	[self updatePreview];
}

- (IBAction) changeDefaultEmoticons:(id) sender {
	NSString *style = [[NSUserDefaults standardUserDefaults] objectForKey:@"JVChatDefaultStyle"];
	[[NSUserDefaults standardUserDefaults] setObject:[sender representedObject] forKey:[NSString stringWithFormat:@"JVChatDefaultEmoticons %@", style]];
	[self updatePreview];
}

#pragma mark -

- (void) updateChatStylesMenu {
	NSEnumerator *enumerator = [[[_styleBundles allObjects] sortedArrayUsingFunction:sortBundlesByName context:self] objectEnumerator];
	NSEnumerator *denumerator = nil;
	NSMenu *menu = nil, *subMenu = nil;
	NSMenuItem *menuItem = nil, *subMenuItem = nil;
	NSString *defaultStyle = [[NSUserDefaults standardUserDefaults] objectForKey:@"JVChatDefaultStyle"];
	NSString *variant = [[NSUserDefaults standardUserDefaults] stringForKey:[NSString stringWithFormat:@"JVChatDefaultStyleVariant %@", defaultStyle]];		
	NSBundle *style = [NSBundle bundleWithIdentifier:defaultStyle];
	id file = nil;

	if( ! style ) {
		[[NSUserDefaults standardUserDefaults] removeObjectForKey:@"JVChatDefaultStyle"];
		defaultStyle = [[NSUserDefaults standardUserDefaults] objectForKey:@"JVChatDefaultStyle"];
		variant = [[NSUserDefaults standardUserDefaults] stringForKey:[NSString stringWithFormat:@"JVChatDefaultStyleVariant %@", defaultStyle]];
	}

	menu = [[[NSMenu alloc] initWithTitle:@""] autorelease];

	while( ( style = [enumerator nextObject] ) ) {
		menuItem = [[[NSMenuItem alloc] initWithTitle:[JVChatTranscript _nameForBundle:style] action:@selector( changeDefaultChatStyle: ) keyEquivalent:@""] autorelease];
		[menuItem setTarget:self];
		[menuItem setRepresentedObject:[NSDictionary dictionaryWithObjectsAndKeys:[style bundleIdentifier], @"style", nil]];
		if( [defaultStyle isEqualToString:[style bundleIdentifier]] )
			[menuItem setState:NSOnState];
		[menu addItem:menuItem];

		if( [[style pathsForResourcesOfType:@"css" inDirectory:@"Variants"] count] ) {
			denumerator = [[style pathsForResourcesOfType:@"css" inDirectory:@"Variants"] objectEnumerator];
			subMenu = [[[NSMenu alloc] initWithTitle:@""] autorelease];
			subMenuItem = [[[NSMenuItem alloc] initWithTitle:( [style objectForInfoDictionaryKey:@"JVBaseStyleVariantName"] ? [style objectForInfoDictionaryKey:@"JVBaseStyleVariantName"] : NSLocalizedString( @"Normal", "normal style variant menu item title" ) ) action:@selector( changeDefaultChatStyle: ) keyEquivalent:@""] autorelease];
			[subMenuItem setTarget:self];
			[subMenuItem setRepresentedObject:[NSDictionary dictionaryWithObjectsAndKeys:[style bundleIdentifier], @"style", nil]];
			if( [defaultStyle isEqualToString:[style bundleIdentifier]] && ! variant )
				[subMenuItem setState:NSOnState];
			[subMenu addItem:subMenuItem];

			while( ( file = [denumerator nextObject] ) ) {
				file = [[file lastPathComponent] stringByDeletingPathExtension];
				subMenuItem = [[[NSMenuItem alloc] initWithTitle:file action:@selector( changeDefaultChatStyle: ) keyEquivalent:@""] autorelease];
				[subMenuItem setTarget:self];
				[subMenuItem setRepresentedObject:[NSDictionary dictionaryWithObjectsAndKeys:[style bundleIdentifier], @"style", file, @"variant", nil]];
				if( [defaultStyle isEqualToString:[style bundleIdentifier]] && [variant isEqualToString:file] )
					[subMenuItem setState:NSOnState];
				[subMenu addItem:subMenuItem];
			}

			[menuItem setSubmenu:subMenu];
		}

		subMenu = nil;
	}

	[styles setMenu:menu];
}

- (void) updateEmoticonsMenu {
	NSEnumerator *enumerator = [[[_emoticonBundles allObjects] sortedArrayUsingFunction:sortBundlesByName context:self] objectEnumerator];
	NSMenu *menu = nil;
	NSMenuItem *menuItem = nil;
	NSString *style = [[NSUserDefaults standardUserDefaults] objectForKey:@"JVChatDefaultStyle"];
	NSString *defaultEmoticons = [[NSUserDefaults standardUserDefaults] objectForKey:[NSString stringWithFormat:@"JVChatDefaultEmoticons %@", style]];
	NSBundle *emoticon = [NSBundle bundleWithIdentifier:defaultEmoticons];

	if( ! emoticon && [defaultEmoticons length] ) {
		[[NSUserDefaults standardUserDefaults] removeObjectForKey:[NSString stringWithFormat:@"JVChatDefaultEmoticons %@", style]];
		defaultEmoticons = [[NSUserDefaults standardUserDefaults] objectForKey:[NSString stringWithFormat:@"JVChatDefaultEmoticons %@", style]];
	}

	menu = [[[NSMenu alloc] initWithTitle:@""] autorelease];

	menuItem = [[[NSMenuItem alloc] initWithTitle:NSLocalizedString( @"Text Only", "text only emoticons menu item title" ) action:@selector( noGraphicEmoticons: ) keyEquivalent:@""] autorelease];
	[menuItem setTarget:self];
	if( ! [defaultEmoticons length] ) [menuItem setState:NSOnState];
	[menu addItem:menuItem];

	[menu addItem:[NSMenuItem separatorItem]];

	while( ( emoticon = [enumerator nextObject] ) ) {
		menuItem = [[[NSMenuItem alloc] initWithTitle:[JVChatTranscript _nameForBundle:emoticon] action:@selector( changeDefaultEmoticons: ) keyEquivalent:@""] autorelease];
		[menuItem setTarget:self];
		[menuItem setRepresentedObject:[emoticon bundleIdentifier]];
		if( [defaultEmoticons isEqualToString:[emoticon bundleIdentifier]] )
			[menuItem setState:NSOnState];
		[menu addItem:menuItem];
	}

	[emoticons setMenu:menu];
}

- (void) updatePreview {
	xsltStylesheetPtr xsltStyle = NULL;
	xmlDocPtr doc = NULL;
	xmlDocPtr res = NULL;
	xmlChar *result = NULL;
	NSString *html = nil;
	int len = 0;
	const char **params = NULL;
	NSBundle *style = [NSBundle bundleWithIdentifier:[[NSUserDefaults standardUserDefaults] objectForKey:@"JVChatDefaultStyle"]];
	NSString *variant = [[NSUserDefaults standardUserDefaults] stringForKey:[NSString stringWithFormat:@"JVChatDefaultStyleVariant %@", [style bundleIdentifier]]];
	NSBundle *emoticon = nil;
	NSString *emoticonStyle = @"";
	NSString *emoticonSetting = [[NSUserDefaults standardUserDefaults] objectForKey:[NSString stringWithFormat:@"JVChatDefaultEmoticons %@", [style bundleIdentifier]]];
	if( [emoticonSetting length] ) {
		emoticon = [NSBundle bundleWithIdentifier:emoticonSetting];
		emoticonStyle = ( emoticon ? [[NSURL fileURLWithPath:[emoticon pathForResource:@"emoticons" ofType:@"css"]] absoluteString] : @"" );
	}

	NSString *path = [style pathForResource:@"main" ofType:@"xsl"];
	if( ! path ) path = [[NSBundle mainBundle] pathForResource:@"default" ofType:@"xsl"];	

	params = [JVChatTranscript _xsltParamArrayWithDictionary:[NSDictionary dictionaryWithContentsOfFile:[style pathForResource:@"parameters" ofType:@"plist"]]];
	xsltStyle = xsltParseStylesheetFile( (const xmlChar *)[path fileSystemRepresentation] );

	if( [style pathForResource:@"preview" ofType:@"colloquyTranscript"] ) {
		doc = xmlParseFile( [[style pathForResource:@"preview" ofType:@"colloquyTranscript"] fileSystemRepresentation] );
	} else {
		doc = xmlParseFile( [[[NSBundle mainBundle] pathForResource:@"preview" ofType:@"colloquyTranscript"] fileSystemRepresentation] );
	}

	if( ( res = xsltApplyStylesheet( xsltStyle, doc, params ) ) ) {
		xsltSaveResultToString( &result, &len, res, xsltStyle );
		xmlFreeDoc( res );
		xmlFreeDoc( doc );
	}

	if( xsltStyle ) xsltFreeStylesheet( xsltStyle );
	if( params ) [JVChatTranscript _freeXsltParamArray:params];

	if( result ) {
		html = [NSString stringWithUTF8String:result];
		free( result );
	}

	NSString *headerPath = [style pathForResource:@"supplement" ofType:@"html"];
	NSString *shell = [NSString stringWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"template" ofType:@"html"]];
	if( variant ) path = ( [variant isAbsolutePath] ? [[NSURL fileURLWithPath:variant] absoluteString] : [[NSURL fileURLWithPath:[style pathForResource:variant ofType:@"css" inDirectory:@"Variants"]] absoluteString] );
	else path = @"";
	NSString *basePath = [style resourcePath];
	basePath = ( basePath ? [[NSURL fileURLWithPath:basePath] absoluteString] : @"" );
	html = [NSString stringWithFormat:shell, @"Preview", emoticonStyle, ( style ? [[NSURL fileURLWithPath:[style pathForResource:@"main" ofType:@"css"]] absoluteString] : @"" ), path, basePath, ( headerPath ? [NSString stringWithContentsOfFile:headerPath] : @"" ), html];

	[[preview mainFrame] loadHTMLString:html baseURL:nil];
}

#pragma mark -

- (void) fontPreviewField:(JVFontPreviewField *) field didChangeToFont:(NSFont *) font {
	[[preview preferences] setStandardFontFamily:[font fontName]];
	[[preview preferences] setFixedFontFamily:[font fontName]];
	[[preview preferences] setSerifFontFamily:[font fontName]];
	[[preview preferences] setSansSerifFontFamily:[font fontName]];
	[self updatePreview];
}

- (void) webView:(WebView *) sender decidePolicyForNavigationAction:(NSDictionary *) actionInformation request:(NSURLRequest *) request frame:(WebFrame *) frame decisionListener:(id <WebPolicyDecisionListener>) listener {
	if( [[[actionInformation objectForKey:WebActionOriginalURLKey] scheme] isEqualToString:@"about"]  ) {
		[listener use];
	} else {
		NSURL *url = [actionInformation objectForKey:WebActionOriginalURLKey];
		[[NSWorkspace sharedWorkspace] openURL:url];	
		[listener ignore];
	}
}

#pragma mark -

- (void) parseUserStyleOptions {
	NSBundle *bundle = [NSBundle bundleWithIdentifier:[[NSUserDefaults standardUserDefaults] objectForKey:@"JVChatDefaultStyle"]];
	NSString *variant = [[NSUserDefaults standardUserDefaults] stringForKey:[NSString stringWithFormat:@"JVChatDefaultStyleVariant %@", [bundle bundleIdentifier]]];
	NSString *css = _userStyle;

	if( variant ) css = [css stringByAppendingString:[NSString stringWithContentsOfFile:( [variant isAbsolutePath] ? variant : [bundle pathForResource:variant ofType:@"css" inDirectory:@"Variants"] )]];
	css = [css stringByAppendingString:[NSString stringWithContentsOfFile:( bundle ? [bundle pathForResource:@"main" ofType:@"css"] : @"" )]];

	NSEnumerator *enumerator = [_styleOptions objectEnumerator];
	NSMutableDictionary *info = nil;

	while( ( info = [enumerator nextObject] ) ) {
		NSMutableArray *styleLayouts = [NSMutableArray array];
		NSArray *sarray = nil;
		NSEnumerator *senumerator = nil;
		if( ! [info objectForKey:@"style"] ) continue;
		if( [[info objectForKey:@"style"] isKindOfClass:[NSArray class]] && [[info objectForKey:@"type"] isEqualToString:@"list"] )
			sarray = [info objectForKey:@"style"];
		else sarray = [NSArray arrayWithObject:[info objectForKey:@"style"]];
		senumerator = [sarray objectEnumerator];

		int listOption = -1, count = 0;
		NSString *style = nil;
		while( ( style = [senumerator nextObject] ) ) {
			AGRegex *regex = [AGRegex regexWithPattern:@"([^\\s].*?)\\s*\{([^\\}]*?)\\}" options:( AGRegexCaseInsensitive | AGRegexDotAll )];
			NSEnumerator *selectors = [regex findEnumeratorInString:style];
			AGRegexMatch *selector = nil;

			NSMutableArray *styleLayout = [NSMutableArray array];
			[styleLayouts addObject:styleLayout];

			while( ( selector = [selectors nextObject] ) ) {
				regex = [AGRegex regexWithPattern:@"([^\\s]*?):\\s*(.*?);" options:( AGRegexCaseInsensitive | AGRegexDotAll )];
				NSEnumerator *properties = [regex findEnumeratorInString:[selector groupAtIndex:2]];
				AGRegexMatch *property = nil;

				while( ( property = [properties nextObject] ) ) {
					NSMutableDictionary *propertyInfo = [NSMutableDictionary dictionary];
					NSString *p = [property groupAtIndex:1];
					NSString *s = [selector groupAtIndex:1];
					NSString *v = [property groupAtIndex:2];

					[propertyInfo setObject:s forKey:@"selector"];
					[propertyInfo setObject:p forKey:@"property"];
					[propertyInfo setObject:v forKey:@"value"];
					[styleLayout addObject:propertyInfo];

					NSString *value = [self valueOfProperty:p forSelector:s inStyle:css];
					if( [[info objectForKey:@"type"] isEqualToString:@"list"] ) {
						regex = [AGRegex regexWithPattern:@"\\s*!\\s*important\\s*$" options:AGRegexCaseInsensitive];
						NSString *compare = [regex replaceWithString:@"" inString:[propertyInfo objectForKey:@"value"]];
						listOption = count;
						if( ! [value isEqualToString:compare] ) listOption = -1;
						else [info setObject:[NSNumber numberWithInt:listOption] forKey:@"value"];
					} else if( [[info objectForKey:@"type"] isEqualToString:@"color"] ) {
						if( value && [[propertyInfo objectForKey:@"value"] rangeOfString:@"%@"].location != NSNotFound ) {
							NSString *expression = [NSString stringWithFormat:v, @"(.*)"];
							regex = [AGRegex regexWithPattern:@"\\s*!\\s*important\\s*$" options:AGRegexCaseInsensitive];
							expression = [regex replaceWithString:@"" inString:expression];
							regex = [AGRegex regexWithPattern:expression options:AGRegexCaseInsensitive];
							AGRegexMatch *vmatch = [regex findInString:value];
							if( [vmatch count] ) [info setObject:[vmatch groupAtIndex:1] forKey:@"value"];
						}
					}
				}
			}

			count++;
		}

		[info setObject:styleLayouts forKey:@"layouts"];
	}

	[optionsTable reloadData];
}

- (NSString *) valueOfProperty:(NSString *) property forSelector:(NSString *) selector inStyle:(NSString *) style {
	NSCharacterSet *escapeSet = [NSCharacterSet characterSetWithCharactersInString:@"^[]{}()\\.$*+?|"];
	selector = [selector stringByEscapingCharactersInSet:escapeSet];
	property = [property stringByEscapingCharactersInSet:escapeSet];

	AGRegex *regex = [AGRegex regexWithPattern:[NSString stringWithFormat:@"%@\\s*\\{[^\\}]*?\\s%@:\\s*(.*?)(?:\\s*!\\s*important\\s*)?;.*?\\}", selector, property] options:( AGRegexCaseInsensitive | AGRegexDotAll )];
	AGRegexMatch *match = [regex findInString:style];
	if( [match count] > 1 ) return [match groupAtIndex:1];

	return nil;
}

- (void) setUserStyleProperty:(NSString *) property forSelector:(NSString *) selector toValue:(NSString *) value {
	NSCharacterSet *escapeSet = [NSCharacterSet characterSetWithCharactersInString:@"^[]{}()\\.$*+?|"];
	NSString *rselector = [selector stringByEscapingCharactersInSet:escapeSet];
	NSString *rproperty = [property stringByEscapingCharactersInSet:escapeSet];

	AGRegex *regex = [AGRegex regexWithPattern:[NSString stringWithFormat:@"(%@\\s*\\{[^\\}]*?\\s%@:\\s*)(?:.*?)(;.*?\\})", rselector, rproperty] options:( AGRegexCaseInsensitive | AGRegexDotAll )];
	if( [[regex findInString:_userStyle] count] ) { // Change existing property in selector block
		[self setUserStyle:[regex replaceWithString:[NSString stringWithFormat:@"$1%@$2", value] inString:_userStyle]];
	} else {
		regex = [AGRegex regexWithPattern:[NSString stringWithFormat:@"(\\s%@\\s*\\{)(\\s*)", rselector] options:AGRegexCaseInsensitive];
		if( [[regex findInString:_userStyle] count] ) { // Append to existing selector block
			[self setUserStyle:[regex replaceWithString:[NSString stringWithFormat:@"$1$2%@: %@;$2", rproperty, value] inString:_userStyle]];
		} else { // Create new selector block
			[self setUserStyle:[_userStyle stringByAppendingFormat:@"%@%@ {\n\t%@: %@;\n}", ( [_userStyle length] ? @"\n\n": @"" ), selector, property, value]];
		}
	}
}

- (void) setUserStyle:(NSString *) style {
	[_userStyle autorelease];
	if( ! style ) _userStyle = [[NSString string] retain];
	else _userStyle = [style retain];
}

- (void) saveUserStyleOptions {
	NSString *path = [[NSString stringWithFormat:@"~/Library/Application Support/Colloquy/Styles/Overrides/%@.css", [[NSUserDefaults standardUserDefaults] objectForKey:@"JVChatDefaultStyle"]] stringByExpandingTildeInPath];
	[_userStyle writeToFile:path atomically:NO];

	[[preview preferences] setUserStyleSheetLocation:[NSURL fileURLWithPath:path]];
	[[preview preferences] setUserStyleSheetEnabled:YES];
}

- (IBAction) showOptions:(id) sender {
	[optionsDrawer setParentWindow:[sender window]];
	[optionsDrawer setPreferredEdge:NSMaxXEdge];
	if( [optionsDrawer contentSize].width < [optionsDrawer minContentSize].width )
		[optionsDrawer setContentSize:[optionsDrawer minContentSize]];
	[optionsDrawer toggle:sender];
}

#pragma mark -

- (int) numberOfRowsInTableView:(NSTableView *) view {
	return [_styleOptions count];
}

- (id) tableView:(NSTableView *) view objectValueForTableColumn:(NSTableColumn *) column row:(int) row {
	if( [[column identifier] isEqualToString:@"key"] ) {
		return [[_styleOptions objectAtIndex:row] objectForKey:@"description"];
	} else if( [[column identifier] isEqualToString:@"value"] ) {
		NSDictionary *info = [_styleOptions objectAtIndex:row];
		id value = [info objectForKey:@"value"];
		if( value ) return value;
		return [info objectForKey:@"default"];
	}
	return nil;
}

- (void) tableView:(NSTableView *) view setObjectValue:(id) object forTableColumn:(NSTableColumn *) column row:(int) row {
	if( [[column identifier] isEqualToString:@"value"] ) {
		NSMutableDictionary *info = [_styleOptions objectAtIndex:row];
		NSArray *style = nil;

		if( [[info objectForKey:@"type"] isEqualToString:@"list"] ) {
			[info setObject:object forKey:@"value"];
			style = [[info objectForKey:@"layouts"] objectAtIndex:[object intValue]];
		} else return;

		NSEnumerator *enumerator = [style objectEnumerator];
		NSDictionary *styleInfo = nil;

		while( ( styleInfo = [enumerator nextObject] ) ) {
			[self setUserStyleProperty:[styleInfo objectForKey:@"property"] forSelector:[styleInfo objectForKey:@"selector"] toValue:[styleInfo objectForKey:@"value"]];
		}

		[self saveUserStyleOptions];
		[self updatePreview];
	}
}

- (void) colorWellDidChangeColor:(NSNotification *) notification {
	JVColorWellCell *cell = [notification object];
	if( ! [[cell representedObject] isKindOfClass:[NSNumber class]] ) return;
	int row = [[cell representedObject] intValue];

	NSMutableDictionary *info = [_styleOptions objectAtIndex:row];
	[info setObject:[cell color] forKey:@"value"];

	NSArray *style = [[info objectForKey:@"layouts"] objectAtIndex:0];
	NSString *value = [[cell color] CSSAttributeValue];
	NSEnumerator *enumerator = [style objectEnumerator];
	NSDictionary *styleInfo = nil;
	NSString *setting = nil;

	while( ( styleInfo = [enumerator nextObject] ) ) {
		setting = [NSString stringWithFormat:[styleInfo objectForKey:@"value"], value];
		[self setUserStyleProperty:[styleInfo objectForKey:@"property"] forSelector:[styleInfo objectForKey:@"selector"] toValue:setting];
	}

	[self saveUserStyleOptions];
	[self updatePreview];
}

- (id) tableView:(NSTableView *) view dataCellForRow:(int) row tableColumn:(NSTableColumn *) column {
	if( [[column identifier] isEqualToString:@"value"] ) {
		NSMutableDictionary *options = [_styleOptions objectAtIndex:row];
		if( [options objectForKey:@"cell"] ) {
			return [[[options objectForKey:@"cell"] retain] autorelease];
		} else if( [[options objectForKey:@"type"] isEqualToString:@"color"] ) {
			id cell = [[JVColorWellCell new] autorelease];
			[cell setRepresentedObject:[NSNumber numberWithInt:row]];
			[options setObject:cell forKey:@"cell"];
			return cell;
		} else if( [[options objectForKey:@"type"] isEqualToString:@"list"] ) {
			id cell = [[NSPopUpButtonCell new] autorelease];
			[cell setControlSize:NSSmallControlSize];
			[cell setFont:[NSFont menuFontOfSize:[NSFont smallSystemFontSize]]];
			[cell addItemsWithTitles:[options objectForKey:@"options"]];
			[options setObject:cell forKey:@"cell"];
			return cell;
		}
	}

	return nil;
}
@end