#import <ExceptionHandling/NSExceptionHandler.h>
#import <ChatCore/MVFileTransfer.h>
#import <ChatCore/MVChatPluginManager.h>
#import <ChatCore/MVChatScriptPlugin.h>
#import <ChatCore/NSURLAdditions.h>
#import "MVColorPanel.h"
#import "MVApplicationController.h"
#import "JVChatWindowController.h"
#import "MVCrashCatcher.h"
#import "MVSoftwareUpdate.h"
#import "JVInspectorController.h"
#import "JVPreferencesController.h"
#import "JVGeneralPreferences.h"
#import "JVAppearancePreferences.h"
#import "JVNotificationPreferences.h"
#import "JVFileTransferPreferences.h"
#import "JVBehaviorPreferences.h"
#import "MVConnectionsController.h"
#import "MVFileTransferController.h"
#import "JVTranscriptPreferences.h"
#import "MVBuddyListController.h"
#import "JVChatController.h"
#import "MVChatConnection.h"
#import "JVChatRoomBrowser.h"
#import "NSBundleAdditions.h"
#import "JVStyle.h"

#import <Foundation/NSDebug.h>

@interface WebCoreCache
+ (void) setDisabled:(BOOL) disabled;
@end

#pragma mark -

NSString *JVChatStyleInstalledNotification = @"JVChatStyleInstalledNotification";
NSString *JVChatEmoticonSetInstalledNotification = @"JVChatEmoticonSetInstalledNotification";
static BOOL applicationIsTerminating = NO;

@implementation MVApplicationController
+ (BOOL) isTerminating {
	extern BOOL applicationIsTerminating;
	return applicationIsTerminating;
}

#pragma mark -

- (IBAction) checkForUpdate:(id) sender {
	[MVSoftwareUpdate checkAutomatically:NO];
}

- (IBAction) connectToSupportRoom:(id) sender {
	[[MVConnectionsController defaultManager] handleURL:[NSURL URLWithString:@"irc://irc.freenode.net/#colloquy"] andConnectIfPossible:YES];
}

- (IBAction) emailDeveloper:(id) sender {
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:[NSString stringWithFormat:@"mailto:timothy@colloquy.info?subject=Colloquy%%20%%28build%%20%@%%29", [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"]]]];
}

- (IBAction) productWebsite:(id) sender {
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://colloquy.info"]];
}

#pragma mark -

- (IBAction) showInspector:(id) sender {
	if ( [[[JVInspectorController sharedInspector] window] isVisible] )
		[[[JVInspectorController sharedInspector] window] orderOut:nil];
	else [[JVInspectorController sharedInspector] show:nil];
}

- (IBAction) showPreferences:(id) sender {
	[[NSPreferences sharedPreferences] showPreferencesPanel];
}

- (IBAction) showTransferManager:(id) sender {
	if( [[[MVFileTransferController defaultManager] window] isVisible] )
		[[MVFileTransferController defaultManager] hideTransferManager:nil];
	else [[MVFileTransferController defaultManager] showTransferManager:nil];
}

- (IBAction) showConnectionManager:(id) sender {
	if( [[[MVConnectionsController defaultManager] window] isVisible] )
		[[MVConnectionsController defaultManager] hideConnectionManager:nil];
	else [[MVConnectionsController defaultManager] showConnectionManager:nil];
}

- (IBAction) showBuddyList:(id) sender {
	if( [[[MVBuddyListController sharedBuddyList] window] isVisible] )
		[[MVBuddyListController sharedBuddyList] hideBuddyList:nil];
	else [[MVBuddyListController sharedBuddyList] showBuddyList:nil];
}

#pragma mark -

- (JVChatController *) chatController {
	return [JVChatController defaultManager];
}

- (MVConnectionsController *) connectionsController {
	return [MVConnectionsController defaultManager];
}

- (MVFileTransferController *) transferManager {
	return [MVFileTransferController defaultManager];
}

- (MVBuddyListController *) buddyList {
	return [MVBuddyListController sharedBuddyList];
}

#pragma mark -

- (IBAction) newConnection:(id) sender {
	[[MVConnectionsController defaultManager] newConnection:nil];
}

- (IBAction) joinRoom:(id) sender {
	[[JVChatRoomBrowser chatRoomBrowserForConnection:nil] showWindow:nil];
}

#pragma mark -

- (void) setupPreferences {
	static BOOL setupAlready = NO;
	if( setupAlready ) return;

	[[NSUserDefaults standardUserDefaults] removeObjectForKey:@"NSToolbar Configuration NSPreferences"];

	[NSPreferences setDefaultPreferencesClass:[JVPreferencesController class]];
	[[NSPreferences sharedPreferences] addPreferenceNamed:NSLocalizedString( @"General", "general preference pane name" ) owner:[JVGeneralPreferences sharedInstance]];
	[[NSPreferences sharedPreferences] addPreferenceNamed:NSLocalizedString( @"Appearance", "appearance preference pane name" ) owner:[JVAppearancePreferences sharedInstance]];
	[[NSPreferences sharedPreferences] addPreferenceNamed:NSLocalizedString( @"Notification", "notification preference pane name" ) owner:[JVNotificationPreferences sharedInstance]];
	[[NSPreferences sharedPreferences] addPreferenceNamed:NSLocalizedString( @"Transfers", "file transfers preference pane name" ) owner:[JVFileTransferPreferences sharedInstance]];
	[[NSPreferences sharedPreferences] addPreferenceNamed:NSLocalizedString( @"Transcripts", "chat transcript preference pane name" ) owner:[JVTranscriptPreferences sharedInstance]];
	[[NSPreferences sharedPreferences] addPreferenceNamed:NSLocalizedString( @"Behavior", "behavior preference pane name" ) owner:[JVBehaviorPreferences sharedInstance]];

	setupAlready = YES;
}

#pragma mark -

- (BOOL) application:(NSApplication *) sender openFile:(NSString *) filename {
	NSDictionary *attributes = [[NSFileManager defaultManager] fileAttributesAtPath:filename traverseLink:YES];
	if( [[NSFileManager defaultManager] isReadableFileAtPath:filename] && ( [[filename pathExtension] caseInsensitiveCompare:@"colloquyTranscript"] == NSOrderedSame || ( [[attributes objectForKey:NSFileHFSTypeCode] unsignedLongValue] == 'coTr' && [[attributes objectForKey:NSFileHFSCreatorCode] unsignedLongValue] == 'coRC' ) ) ) {
		[[JVChatController defaultManager] chatViewControllerForTranscript:filename];
		return YES;
	} else if( [[NSWorkspace sharedWorkspace] isFilePackageAtPath:filename] && ( [[filename pathExtension] caseInsensitiveCompare:@"colloquyStyle"] == NSOrderedSame || [[filename pathExtension] caseInsensitiveCompare:@"fireStyle"] == NSOrderedSame || ( [[attributes objectForKey:NSFileHFSTypeCode] unsignedLongValue] == 'coSt' && [[attributes objectForKey:NSFileHFSCreatorCode] unsignedLongValue] == 'coRC' ) ) ) {
		if( [[NSFileManager defaultManager] movePath:filename toPath:[NSString stringWithFormat:@"%@/%@", [@"~/Library/Application Support/Colloquy/Styles" stringByExpandingTildeInPath], [filename lastPathComponent]] handler:nil] ) {
			NSBundle *bundle = [NSBundle bundleWithPath:[NSString stringWithFormat:@"%@/%@", [@"~/Library/Application Support/Colloquy/Styles" stringByExpandingTildeInPath], [filename lastPathComponent]]];
			JVStyle *style = [JVStyle newWithBundle:bundle];

			[[NSNotificationCenter defaultCenter] postNotificationName:JVChatStyleInstalledNotification object:style]; 

			if( NSRunInformationalAlertPanel( [NSString stringWithFormat:NSLocalizedString( @"%@ Successfully Installed", "style installed title" ), [style displayName]], [NSString stringWithFormat:NSLocalizedString( @"%@ is ready to be used in your colloquies. Would you like to view %@ and it's options in the Appearance Preferences?", "would you like to view the style in the Appearance Preferences" ), [style displayName], [style displayName]], NSLocalizedString( @"Yes", "yes button" ), NSLocalizedString( @"No", "no button" ), nil ) == NSOKButton ) {
				[self setupPreferences];
				[[JVPreferencesController sharedPreferences] showPreferencesPanelForOwner:[JVAppearancePreferences sharedInstance]];
				[[JVAppearancePreferences sharedInstance] selectStyleWithIdentifier:[style identifier]];
			}

			return YES;
		} else {
			NSRunCriticalAlertPanel( NSLocalizedString( @"Style Installation Error", "error installing style title" ), NSLocalizedString( @"The style could not be installed, please make sure you have permission to install this item.", "style install error message" ), nil, nil, nil );
		}
		return NO;
	} else if( [[NSWorkspace sharedWorkspace] isFilePackageAtPath:filename] && ( [[filename pathExtension] caseInsensitiveCompare:@"colloquyEmoticons"] == NSOrderedSame || ( [[attributes objectForKey:NSFileHFSTypeCode] unsignedLongValue] == 'coEm' && [[attributes objectForKey:NSFileHFSCreatorCode] unsignedLongValue] == 'coRC' ) ) ) {
		if( [[NSFileManager defaultManager] movePath:filename toPath:[NSString stringWithFormat:@"%@/%@", [@"~/Library/Application Support/Colloquy/Emoticons" stringByExpandingTildeInPath], [filename lastPathComponent]] handler:nil] ) {
			NSBundle *emoticon = [NSBundle bundleWithPath:[NSString stringWithFormat:@"%@/%@", [@"~/Library/Application Support/Colloquy/Emoticons" stringByExpandingTildeInPath], [filename lastPathComponent]]];
			[[NSNotificationCenter defaultCenter] postNotificationName:JVChatEmoticonSetInstalledNotification object:emoticon]; 

			if( NSRunInformationalAlertPanel( [NSString stringWithFormat:NSLocalizedString( @"%@ Successfully Installed", "emoticon installed title" ), [emoticon displayName]], [NSString stringWithFormat:NSLocalizedString( @"%@ is ready to be used in your colloquies. Would you like to view %@ and it's options in the Appearance Preferences?", "would you like to view the emoticons in the Appearance Preferences" ), [emoticon displayName], [emoticon displayName]], NSLocalizedString( @"Yes", "yes button" ), NSLocalizedString( @"No", "no button" ), nil ) == NSOKButton ) {
				[self setupPreferences];
				[[JVPreferencesController sharedPreferences] showPreferencesPanelForOwner:[JVAppearancePreferences sharedInstance]];
				[[JVAppearancePreferences sharedInstance] selectEmoticonsWithIdentifier:[emoticon bundleIdentifier]];
			}

			return YES;
		} else {
			NSRunCriticalAlertPanel( NSLocalizedString( @"Emoticon Installation Error", "error installing emoticons title" ), NSLocalizedString( @"The emoticons could not be installed, please make sure you have permission to install this item.", "emoticons install error message" ), nil, nil, nil );
		}
		return NO;
	}
	return NO;
}

- (BOOL) application:(NSApplication *) sender printFile:(NSString *) filename {
	NSLog( @"printFile %@", filename );
	return NO;
}

- (void) handleURLEvent:(NSAppleEventDescriptor *) event withReplyEvent:(NSAppleEventDescriptor *) replyEvent {
	NSURL *url = [NSURL URLWithString:[[event descriptorAtIndex:1] stringValue]];
	if( [url isChatURL] ) [[MVConnectionsController defaultManager] handleURL:url andConnectIfPossible:YES];
	else [[NSWorkspace sharedWorkspace] openURL:url];
}

- (BOOL) exceptionHandler:(NSExceptionHandler *) sender shouldLogException:(NSException *) exception mask:(unsigned int) mask {
	return NO;
}

- (BOOL) exceptionHandler:(NSExceptionHandler *) sender shouldHandleException:(NSException *) exception mask:(unsigned int) mask {
	static BOOL _exceptionHandlerLoop = NO;
	if( _exceptionHandlerLoop ) return NO;
	_exceptionHandlerLoop = YES;

	NSTask *ls = [[NSTask alloc] init];
	NSString *pid = [[NSNumber numberWithInt:[[NSProcessInfo processInfo] processIdentifier]] stringValue];
	NSMutableArray *args = [NSMutableArray arrayWithCapacity:20];
	NSPipe *pipe = [NSPipe pipe];

	NSString *stack = [[exception userInfo] objectForKey:NSStackTraceKey];
	NSMutableArray *stackArray = [[[stack componentsSeparatedByString:@"  "] mutableCopy] autorelease];

	if( [stackArray count] > 4 ) [stackArray removeObjectsInRange:NSMakeRange( 0, 4 )];

#ifndef DEBUG
	[stackArray removeObjectsInRange:NSMakeRange( 1, [stackArray count] - 1 )];
#endif

	[args addObject:@"-p"];
	[args addObject:pid];
	[args addObjectsFromArray:stackArray];

	[ls setStandardOutput:pipe];
	[ls setLaunchPath:@"/usr/bin/atos"];
	[ls setArguments:args];
	[ls launch];
	[ls waitUntilExit];

	NSData *result = [[pipe fileHandleForReading] readDataToEndOfFile];
	NSString *trace = [[[NSString alloc] initWithData:result encoding:NSASCIIStringEncoding] autorelease];

#ifdef DEBUG
	NSLog( @"Exception Stack Trace:\n%@", trace );
	NSRange loc = [trace rangeOfString:@"\n"];
	if( loc.location != NSNotFound )
		trace = [trace substringWithRange:[trace lineRangeForRange:NSMakeRange( 0, loc.location )]];
#endif

	NSString *reason = [exception reason];
	if( [reason hasPrefix:@"*** "] ) reason = [reason substringFromIndex:4];

	NSRunCriticalAlertPanel( NSLocalizedString( @"An unresolved error has occurred.", "exception error title" ), NSLocalizedString( @"Please report this message to the Colloquy development team with a brief synopsis of your actions leading to this message.\n\n%@\n\nThe error occurred in:\n%@", "exception error message" ), nil, nil, nil, reason, trace );

	[ls release];

	_exceptionHandlerLoop = NO;
	return YES;
}

#pragma mark -

- (void) applicationWillFinishLaunching:(NSNotification *) notification {
	[[NSUserDefaults standardUserDefaults] registerDefaults:[NSDictionary dictionaryWithContentsOfFile:[[NSBundle mainBundle] pathForResource:[[NSBundle mainBundle] bundleIdentifier] ofType:@"plist"]]];
	[[NSAppleEventManager sharedAppleEventManager] setEventHandler:self andSelector:@selector( handleURLEvent:withReplyEvent: ) forEventClass:kInternetEventClass andEventID:kAEGetURL];
#ifdef DEBUG
	NSDebugEnabled = YES;
//	NSZombieEnabled = YES;
//	NSDeallocateZombies = NO;
	[NSAutoreleasePool enableFreedObjectCheck:YES];
#endif
}

- (void) applicationDidFinishLaunching:(NSNotification *) notification {
	NSExceptionHandler *handler = [NSExceptionHandler defaultExceptionHandler];
	[handler setExceptionHandlingMask:NSLogAndHandleEveryExceptionMask];
	[handler setDelegate:self];

	[MVCrashCatcher check];

	if( [[NSUserDefaults standardUserDefaults] boolForKey:@"JVEnableAutomaticSoftwareUpdateCheck"] )
		[MVSoftwareUpdate checkAutomatically:YES];

	[[MVColorPanel sharedColorPanel] attachColorList:[[[NSColorList alloc] initWithName:@"Chat" fromFile:[[NSBundle mainBundle] pathForResource:@"Chat" ofType:@"clr"]] autorelease]];

	[WebCoreCache setDisabled:[[NSUserDefaults standardUserDefaults] boolForKey:@"JVDisableWebCoreCache"]];

	[self setupPreferences];

	[[NSFileManager defaultManager] createDirectoryAtPath:[@"~/Library/Application Support/Colloquy" stringByExpandingTildeInPath] attributes:nil];
	[[NSFileManager defaultManager] createDirectoryAtPath:[@"~/Library/Application Support/Colloquy/Plugins" stringByExpandingTildeInPath] attributes:nil];
	[[NSFileManager defaultManager] createDirectoryAtPath:[@"~/Library/Application Support/Colloquy/Styles" stringByExpandingTildeInPath] attributes:nil];
	[[NSFileManager defaultManager] createDirectoryAtPath:[@"~/Library/Application Support/Colloquy/Styles/Variants" stringByExpandingTildeInPath] attributes:nil];
	[[NSFileManager defaultManager] createDirectoryAtPath:[@"~/Library/Application Support/Colloquy/Emoticons" stringByExpandingTildeInPath] attributes:nil];
	[[NSFileManager defaultManager] createDirectoryAtPath:[@"~/Library/Application Support/Colloquy/Favorites" stringByExpandingTildeInPath] attributes:nil];
	[[NSFileManager defaultManager] createDirectoryAtPath:[@"~/Library/Application Support/Colloquy/Recent Chat Rooms" stringByExpandingTildeInPath] attributes:nil];
	[[NSFileManager defaultManager] createDirectoryAtPath:[@"~/Library/Application Support/Colloquy/Recent Acquaintances" stringByExpandingTildeInPath] attributes:nil];
	[[NSFileManager defaultManager] createDirectoryAtPath:[@"~/Library/Application Support/Colloquy/Silc" stringByExpandingTildeInPath] attributes:nil];
	[[NSFileManager defaultManager] createDirectoryAtPath:[@"~/Library/Application Support/Colloquy/Silc/Client Keys" stringByExpandingTildeInPath] attributes:nil];
	[[NSFileManager defaultManager] createDirectoryAtPath:[@"~/Library/Application Support/Colloquy/Silc/Server Keys" stringByExpandingTildeInPath] attributes:nil];
	[[NSFileManager defaultManager] createDirectoryAtPath:[@"~/Library/Scripts/Applications" stringByExpandingTildeInPath] attributes:nil];
	[[NSFileManager defaultManager] createDirectoryAtPath:[@"~/Library/Scripts/Applications/Colloquy" stringByExpandingTildeInPath] attributes:nil];

	[MVChatPluginManager defaultManager];
	[MVConnectionsController defaultManager];
	[JVChatController defaultManager];
	[MVFileTransferController defaultManager];
	[MVBuddyListController sharedBuddyList];

	[[[[[[NSApplication sharedApplication] mainMenu] itemAtIndex:1] submenu] itemWithTag:20] setSubmenu:[MVConnectionsController favoritesMenu]];

	NSRange range = NSRangeFromString( [[NSUserDefaults standardUserDefaults] stringForKey:@"JVFileTransferPortRange"] );
	[MVFileTransfer setFileTransferPortRange:range];
}

- (void) applicationWillBecomeActive:(NSNotification *) notification {
	[MVConnectionsController refreshFavoritesMenu];
}

- (void) applicationWillTerminate:(NSNotification *) notification {
	extern BOOL applicationIsTerminating;
	applicationIsTerminating = YES;

	[[NSAppleEventManager sharedAppleEventManager] removeEventHandlerForEventClass:kInternetEventClass andEventID:kAEGetURL];

	[NSAutoreleasePool enableRelease:NO];

	[[MVBuddyListController sharedBuddyList] release];
	[[MVFileTransferController defaultManager] release];
	[[MVChatPluginManager defaultManager] release];
	[[JVChatController defaultManager] release];
	[[MVConnectionsController defaultManager] release];

	[[NSUserDefaults standardUserDefaults] synchronize];
	[[NSURLCache sharedURLCache] removeAllCachedResponses];
}

- (BOOL) application:(NSApplication *) sender delegateHandlesKey:(NSString *) key {
	if( [key isEqualToString:@"chatController"] || [key isEqualToString:@"connectionsController"] || [key isEqualToString:@"transferManager"] || [key isEqualToString:@"buddyList"] )
		return YES;
	return NO;
}

- (BOOL) validateMenuItem:(NSMenuItem *) menuItem {
	if( [menuItem action] == @selector( joinRoom: ) ) {
		if( [[[MVConnectionsController defaultManager] connections] count] ) return YES;
		else return NO;
	}
	return YES;
}
@end

#pragma mark -

@implementation MVChatScriptPlugin (MVChatPluginContextualMenuSupport)
- (IBAction) performContextualMenuItemAction:(id) sender {
	id object = [sender representedObject];
	NSString *title = [sender title];
	NSDictionary *args = [NSDictionary dictionaryWithObjectsAndKeys:title, @"----", object, @"pcM1", nil];
	[self callScriptHandler:'pcMX' withArguments:args forSelector:_cmd];
}

- (NSArray *) contextualMenuItemsForObject:(id) object {
	NSDictionary *args = [NSDictionary dictionaryWithObjectsAndKeys:object, @"----", nil];
	id result = [self callScriptHandler:'cMiX' withArguments:args forSelector:_cmd];

	if( [result isKindOfClass:[NSArray class]] ) {
		NSMutableArray *ret = [NSMutableArray array];
		NSEnumerator *enumerator = [result objectEnumerator];
		id item = nil;

		while( ( item = [enumerator nextObject] ) ) {
			if( [item isKindOfClass:[NSString class]] ) {
				if( [item isEqualToString:@"-"] ) {
					[ret addObject:[NSMenuItem separatorItem]];
				} else {
					NSMenuItem *mitem = [[[NSMenuItem alloc] initWithTitle:item action:@selector( performContextualMenuItemAction: ) keyEquivalent:@""] autorelease];
					[mitem setTarget:self];
					[mitem setRepresentedObject:object];
					[ret addObject:mitem];
				}
			}
		}

		if( [ret count] )
			return ret;
	}

	return nil;
}
@end

#pragma mark -

@implementation NSApplication (NSApplicationScripting)
- (void) newConnection:(NSScriptCommand *) command {
	[[MVConnectionsController defaultManager] newConnection:nil];
}
@end

#pragma mark -

@implementation JVChatController (JVChatControllerObjectSpecifier)
- (NSScriptObjectSpecifier *) objectSpecifier {
	id classDescription = [NSClassDescription classDescriptionForClass:[NSApplication class]];
	NSScriptObjectSpecifier *container = [[NSApplication sharedApplication] objectSpecifier];
	return [[[NSPropertySpecifier alloc] initWithContainerClassDescription:classDescription containerSpecifier:container key:@"chatController"] autorelease];
}
@end

#pragma mark -

@implementation MVConnectionsController (MVConnectionsControllerObjectSpecifier)
- (NSScriptObjectSpecifier *) objectSpecifier {
	id classDescription = [NSClassDescription classDescriptionForClass:[NSApplication class]];
	NSScriptObjectSpecifier *container = [[NSApplication sharedApplication] objectSpecifier];
	return [[[NSPropertySpecifier alloc] initWithContainerClassDescription:classDescription containerSpecifier:container key:@"connectionsController"] autorelease];
}
@end

#pragma mark -

@implementation MVBuddyListController (MVBuddyListControllerObjectSpecifier)
- (NSScriptObjectSpecifier *) objectSpecifier {
	id classDescription = [NSClassDescription classDescriptionForClass:[NSApplication class]];
	NSScriptObjectSpecifier *container = [[NSApplication sharedApplication] objectSpecifier];
	return [[[NSPropertySpecifier alloc] initWithContainerClassDescription:classDescription containerSpecifier:container key:@"buddyList"] autorelease];
}
@end