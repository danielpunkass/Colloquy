#import <ChatCore/NSAttributedStringAdditions.h>
#import <ChatCore/NSStringAdditions.h>
#import <libxml/xinclude.h>
#import <libxml/debugXML.h>
#import <libxslt/transform.h>
#import <libxslt/xsltutils.h>

#import "JVChatMessage.h"
#import "JVChatTranscript.h"
#import "JVChatRoom.h"
#import "JVChatRoomMember.h"
#import "NSAttributedStringMoreAdditions.h"

@implementation JVChatMessage
+ (void) initialize {
	[super initialize];
	static BOOL tooLate = NO;
	if( ! tooLate ) {
		[[NSScriptCoercionHandler sharedCoercionHandler] registerCoercer:[self class] selector:@selector( coerceValue:toClass: ) toConvertFromClass:[self class] toClass:[NSString class]];
		[[NSScriptCoercionHandler sharedCoercionHandler] registerCoercer:[self class] selector:@selector( coerceValue:toClass: ) toConvertFromClass:[NSString class] toClass:[self class]];
		[[NSScriptCoercionHandler sharedCoercionHandler] registerCoercer:[self class] selector:@selector( coerceValue:toClass: ) toConvertFromClass:[JVMutableChatMessage class] toClass:[NSString class]];
		[[NSScriptCoercionHandler sharedCoercionHandler] registerCoercer:[self class] selector:@selector( coerceValue:toClass: ) toConvertFromClass:[NSString class] toClass:[JVMutableChatMessage class]];
		tooLate = YES;
	}
}

+ (id) coerceValue:(id) value toClass:(Class) class {
	if( class == [NSString class] && [value isKindOfClass:[self class]] ) {
		return [value bodyAsPlainText];
	} else if( ( class == [JVChatMessage class] || class == [JVMutableChatMessage class] ) && [value isKindOfClass:[NSString class]] ) {
		return [[[JVMutableChatMessage alloc] initWithText:value sender:nil andTranscript:nil] autorelease];
	} return nil;
}

#pragma mark -

+ (id) messageWithNode:(/* xmlNode */ void *) node andTranscript:(JVChatTranscript *) transcript {
	return [[[self alloc] initWithNode:node andTranscript:transcript] autorelease];
}

#pragma mark -

- (void) load {
	if( _loaded ) return;

	xmlChar *dateStr = xmlGetProp( _node, "received" );
	_date = ( dateStr ? [[NSDate dateWithString:[NSString stringWithUTF8String:dateStr]] retain] : nil );
	xmlFree( dateStr );

	_attributedMessage = [[NSTextStorage attributedStringWithXHTMLTree:_node baseURL:nil defaultAttributes:nil] retain];
	_action = ( xmlHasProp( _node, "action" ) ? YES : NO );
	_highlighted = ( xmlHasProp( _node, "highlight" ) ? YES : NO );
	_ignoreStatus = ( xmlHasProp( _node, "ignored" ) ? JVMessageIgnored : _ignoreStatus );
	_ignoreStatus = ( xmlHasProp( ((xmlNode *) _node ) -> parent, "ignored" ) ? JVUserIgnored : _ignoreStatus );

	xmlNode *subNode = ((xmlNode *) _node ) -> parent -> children;

	do {
		if( ! strncmp( "sender", subNode -> name, 6 ) ) {
			xmlChar *senderStr = xmlGetProp( subNode, "nickname" );
			if( ! senderStr ) senderStr = xmlNodeGetContent( subNode );
			if( senderStr ) _sender = [NSString stringWithUTF8String:senderStr];
			xmlFree( senderStr );

			xmlChar *selfStr = xmlGetProp( subNode, "self" );
			if( selfStr && ! strcmp( selfStr, "yes" ) ) _senderIsLocalUser = YES;
			else _senderIsLocalUser = NO;
			xmlFree( selfStr );

/*			if( _sender && [[self transcript] isKindOfClass:[JVChatRoom class]] ) {
				JVChatRoomMember *member = [(JVChatRoom *)[self transcript] chatRoomMemberWithName:_sender];
				if( member ) _sender = member;
			} */

			[_sender retain];
		}
	} while( ( subNode = subNode -> next ) ); 

	_loaded = YES;
}

#pragma mark -

- (id) init {
	if( ( self = [super init] ) ) {
		_loaded = NO;
		_objectSpecifier = nil;
		_transcript = nil;
		_messageIdentifier = nil;
		_sender = nil;
		_htmlMessage = nil;
		_attributedMessage = nil;
		_date = nil;
		_action = NO;
		_highlighted = NO;
		_senderIsLocalUser = NO;
		_ignoreStatus = JVNotIgnored;
	}

	return self;
}

- (id) initWithNode:(/* xmlNode */ void *) node andTranscript:(JVChatTranscript *) transcript {
	if( ( self = [self init] ) ) {
		_node = node;
		_transcript = transcript; // weak reference

		xmlChar *idStr = xmlGetProp( (xmlNode *) _node, "id" );
		_messageIdentifier = ( idStr ? [[NSString allocWithZone:[self zone]] initWithUTF8String:idStr] : nil );
		xmlFree( idStr );
	}

	return self;
}

- (id) mutableCopyWithZone:(NSZone *) zone {
	[self load];

	JVMutableChatMessage *ret = [[JVMutableChatMessage allocWithZone:zone] initWithText:_attributedMessage sender:_sender andTranscript:_transcript];
	[ret setDate:_date];
	[ret setAction:_action];
	[ret setHighlighted:_highlighted];
	[ret setMessageIdentifier:_messageIdentifier];

	return ret;
}

- (void) dealloc {
	[_messageIdentifier release];
	[_sender release];
	[_htmlMessage release];
	[_attributedMessage release];
	[_date release];
	[_objectSpecifier release];

	_node = NULL;
	_transcript = nil;
	_sender = nil;
	_messageIdentifier = nil;
	_htmlMessage = nil;
	_attributedMessage = nil;
	_date = nil;
	_objectSpecifier = nil;

	[super dealloc];
}

#pragma mark -

- (void *) node {
	return _node;
}

#pragma mark -

- (NSDate *) date {
	[self load];
	return _date;
}

- (id) sender {
	[self load];
	return _sender;
}

- (BOOL) senderIsLocalUser {
	[self load];
	return _senderIsLocalUser;
}

#pragma mark -

- (NSTextStorage *) body {
	[self load];
	return _attributedMessage;
}

- (NSString *) bodyAsPlainText {
	return [[self body] string];
}

- (NSString *) bodyAsHTML {
	NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:YES], @"IgnoreFonts", [NSNumber numberWithBool:YES], @"IgnoreFontSizes", nil];
	return [[self body] HTMLFormatWithOptions:options];
}

#pragma mark -

- (BOOL) isAction {
	[self load];
	return _action;
}

- (BOOL) isHighlighted {
	[self load];
	return _highlighted;
}

- (JVIgnoreMatchResult) ignoreStatus {
	[self load];
	return _ignoreStatus;
}

#pragma mark -

- (JVChatTranscript *) transcript {
	return _transcript;
}

- (NSString *) messageIdentifier {
	return _messageIdentifier;
}

#pragma mark -

- (NSScriptObjectSpecifier *) objectSpecifier {
	return _objectSpecifier;
}

- (void) setObjectSpecifier:(NSScriptObjectSpecifier *) objectSpecifier {
	[_objectSpecifier autorelease];
	_objectSpecifier = [objectSpecifier retain];
}

#pragma mark -

- (NSString *) description {
	[self load];
	return [self bodyAsPlainText];
}

- (NSString *) debugDescription {
	[self load];
	return [NSString stringWithFormat:@"<%@ 0x%x: (%@) %@>", NSStringFromClass( [self class] ), (unsigned long) self, [self sender], [self body]];
}
@end

#pragma mark -

@implementation JVMutableChatMessage
+ (id) messageWithText:(id) body sender:(id) sender andTranscript:(JVChatTranscript *) transcript {
	return [[[self alloc] initWithText:body sender:sender andTranscript:transcript] autorelease];
}

- (id) initWithText:(id) body sender:(id) sender andTranscript:(JVChatTranscript *) transcript {
	if( ( self = [self init] ) ) {
		_loaded = YES;
		[self setTranscript:transcript];
		[self setDate:[NSDate date]];
		[self setBody:body];
		[self setSender:sender];
		[self setMessageIdentifier:[NSString locallyUniqueString]];
	}

	return self;
}

#pragma mark -

- (void) setNode:(/* xmlNode */ void *) node {
	_node = node;
}

#pragma mark -

- (void) setDate:(NSDate *) date {
	[_date autorelease];
	_date = [date copy];
}

- (void) setSender:(id) sender {
/*	if( [sender isKindOfClass:[NSString class]] && [[self transcript] isKindOfClass:[JVChatRoom class]] ) {
		JVChatRoomMember *member = [(JVChatRoom *)[self transcript] chatRoomMemberWithName:sender];
		if( member ) sender = member;
	} */

	[_sender autorelease];
	_sender = ( [sender conformsToProtocol:@protocol( NSCopying)] ? [sender copy] : [sender retain] );
}

#pragma mark -

- (void) setBody:(id) message {
	if( ! _attributedMessage ) {
		if( [message isKindOfClass:[NSTextStorage class]] ) _attributedMessage = [message retain];
		else if( [message isKindOfClass:[NSAttributedString class]] ) _attributedMessage = [[NSTextStorage alloc] initWithAttributedString:message];
		else if( [message isKindOfClass:[NSString class]] ) _attributedMessage = [[NSAttributedString alloc] initWithString:(NSString *)message];
	} else if( _attributedMessage && [message isKindOfClass:[NSAttributedString class]] ) {
		[_attributedMessage setAttributedString:message];
	} else if( _attributedMessage && [message isKindOfClass:[NSString class]] ) {
		id string = [[[NSAttributedString alloc] initWithString:(NSString *)message] autorelease];
		[_attributedMessage setAttributedString:string];
	}
}

- (void) setBodyAsPlainText:(NSString *) message {
	[self setBody:message];
}

- (void) setBodyAsHTML:(NSString *) message {
	[self setBody:[NSAttributedString attributedStringWithHTMLFragment:message baseURL:nil]];
}

#pragma mark -

- (void) setAction:(BOOL) action {
	_action = action;
}

- (void) setHighlighted:(BOOL) highlighted {
	_highlighted = highlighted;
}

- (void) setIgnoreStatus:(JVIgnoreMatchResult) ignoreStatus {
	_ignoreStatus = ignoreStatus;
}

#pragma mark -

- (void) setTranscript:(JVChatTranscript *) transcript {
	_transcript = transcript; // weak reference
}

- (void) setMessageIdentifier:(NSString *) identifier {
	[_messageIdentifier autorelease];
	_messageIdentifier = [identifier copyWithZone:[self zone]];
}
@end
