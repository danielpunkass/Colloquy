// Concept by Joar Wingfors.
// Created by Timothy Hatcher for Colloquy.
// Copyright Joar Wingfors and Timothy Hatcher. All rights reserved.

#import "JVTranscriptCriterionController.h"
#import "JVChatMessage.h"

@implementation JVTranscriptCriterionController
+ (id) controller {
	return [[[self alloc] init] autorelease];
}

#pragma mark -

- (id) init {
	if( ( self = [super init] ) ) {
		_query = @"";
		_changed = NO;
		[self setKind:JVTranscriptMessageBodyCriterionKind];	
		[self setOperation:JVTranscriptTextContainCriterionOperation];
		[self setQueryUnits:JVTranscriptNoCriterionQueryUnits];
	}

	return self;
}

- (id) initWithCoder:(NSCoder *) coder {
	if( [coder allowsKeyedCoding] ) {
		self = [self init];
		[self setKind:[coder decodeIntForKey:@"kind"]];
		[self setQuery:[coder decodeObjectForKey:@"query"]];
		[self setOperation:[coder decodeIntForKey:@"operation"]];
		[self setQueryUnits:[coder decodeIntForKey:@"queryUnits"]];
		return self;
	} else [NSException raise:NSInvalidArchiveOperationException format:@"Only supports NSKeyedArchiver coders"];
	return nil;
}

- (void) encodeWithCoder:(NSCoder *) coder {
	if( [coder allowsKeyedCoding] ) {
		[coder encodeInt:[self kind] forKey:@"kind"];
		[coder encodeObject:[self query] forKey:@"query"];
		[coder encodeInt:[self operation] forKey:@"operation"];
		[coder encodeInt:[self queryUnits] forKey:@"queryUnits"];
	} else [NSException raise:NSInvalidArchiveOperationException format:@"Only supports NSKeyedArchiver coders"];
}

- (id) copyWithZone:(NSZone *) zone {
	JVTranscriptCriterionController *ret = [[JVTranscriptCriterionController alloc] init];
	[ret setKind:[self kind]];
	[ret setQuery:[self query]];
	[ret setOperation:[self operation]];
	[ret setQueryUnits:[self queryUnits]];
	return ret;
}

- (id) mutableCopyWithZone:(NSZone *) zone {
	return [self copyWithZone:zone];
}

- (void) dealloc {
	[subview release];
	[kindMenu release];
	[_query release];

	subview = nil;
	kindMenu = nil;
	_query = nil;

	[super dealloc];
}

#pragma mark -

- (void) awakeFromNib {
	[tabView selectTabViewItemWithIdentifier:[NSString stringWithFormat:@"%d", [self format]]];

	if( [self format] == JVTranscriptTextCriterionFormat ) {
		[textKindButton selectItemAtIndex:[textKindButton indexOfItemWithTag:[self kind]]];
		[textOperationButton selectItemAtIndex:[textOperationButton indexOfItemWithTag:[self operation]]];
		[textQuery setObjectValue:[self query]];
	} else if( [self format] == JVTranscriptDateCriterionFormat ) {
		[dateKindButton selectItemAtIndex:[dateKindButton indexOfItemWithTag:[self kind]]];
		[dateOperationButton selectItemAtIndex:[dateOperationButton indexOfItemWithTag:[self operation]]];
		[dateQuery setObjectValue:[self query]];
		[dateUnitsButton selectItemAtIndex:[dateUnitsButton indexOfItemWithTag:[self queryUnits]]];
	} else if( [self format] == JVTranscriptBooleanCriterionFormat ) {
		[booleanKindButton selectItemAtIndex:[booleanKindButton indexOfItemWithTag:[self kind]]];
	} else if( [self format] == JVTranscriptListCriterionFormat ) {
		[listKindButton selectItemAtIndex:[listKindButton indexOfItemWithTag:[self kind]]];
		[listOperationButton selectItemAtIndex:[listOperationButton indexOfItemWithTag:[self operation]]];
		int index = [listQuery indexOfItemWithRepresentedObject:[self query]];
		if( index == -1 && [[self query] isKindOfClass:[NSNumber class]] )
			index = [(NSNumber *)[self query] intValue];
		if( [listQuery numberOfItems] < index ) index = -1;
		[listQuery selectItemAtIndex:index];
	}
}

#pragma mark -

- (NSView *) view {
	if( ! subview ) [NSBundle loadNibNamed:@"JVTranscriptCriterion" owner:self];
	return subview;
}

#pragma mark -

- (JVTranscriptCriterionFormat) format {
	return _format;
}

- (void) setFormat:(JVTranscriptCriterionFormat) format {
	if( format != _format ) {
		_format = format;

		[tabView selectTabViewItemWithIdentifier:[NSString stringWithFormat:@"%d", format]];

		if( [self format] == JVTranscriptTextCriterionFormat ) {
			[textKindButton selectItemAtIndex:[textKindButton indexOfItemWithTag:[self kind]]];
		} else if( [self format] == JVTranscriptDateCriterionFormat ) {
			[dateKindButton selectItemAtIndex:[dateKindButton indexOfItemWithTag:[self kind]]];
		} else if( [self format] == JVTranscriptBooleanCriterionFormat ) {
			[booleanKindButton selectItemAtIndex:[booleanKindButton indexOfItemWithTag:[self kind]]];
		} else if( [self format] == JVTranscriptListCriterionFormat ) {
			[listKindButton selectItemAtIndex:[listKindButton indexOfItemWithTag:[self kind]]];
		}
	}
}

#pragma mark -

- (JVTranscriptCriterionKind) kind {
	return _kind;
}

- (void) setKind:(JVTranscriptCriterionKind) kind {
	if( kind != _kind ) {
		_kind = kind;

		switch( kind ) {
		case JVTranscriptSenderNameCriterionKind:
		case JVTranscriptMessageBodyCriterionKind:
			[self setFormat:JVTranscriptTextCriterionFormat];
			break;
		case JVTranscriptDateReceivedCriterionKind:
			[self setFormat:JVTranscriptDateCriterionFormat];
			break;
		default:
		case JVTranscriptSenderInBuddyListCriterionKind:
		case JVTranscriptSenderNotInBuddyListCriterionKind:
		case JVTranscriptSenderIgnoredCriterionKind:
		case JVTranscriptSenderNotIgnoredCriterionKind:
		case JVTranscriptMessageIgnoredCriterionKind:
		case JVTranscriptMessageNotIgnoredCriterionKind:
		case JVTranscriptMessageAddressedToMeCriterionKind:
		case JVTranscriptMessageNotAddressedToMeCriterionKind:
		case JVTranscriptMessageFromMeCriterionKind:
		case JVTranscriptMessageNotFromMeCriterionKind:
		case JVTranscriptMessageHighlightedCriterionKind:
		case JVTranscriptMessageNotHighlightedCriterionKind:
		case JVTranscriptMessageIsActionCriterionKind:
		case JVTranscriptMessageIsNotActionCriterionKind:
			[self setFormat:JVTranscriptBooleanCriterionFormat];
		}
	}
}

#pragma mark -

- (IBAction) selectCriterionKind:(id) sender {
	_changed = YES;
	[self setKind:[[sender selectedItem] tag]];

	if( [self format] == JVTranscriptTextCriterionFormat ) {
		[self setOperation:JVTranscriptTextContainCriterionOperation];
		[self setQueryUnits:JVTranscriptNoCriterionQueryUnits];
	} else if( [self format] == JVTranscriptDateCriterionFormat ) {
		[self setOperation:JVTranscriptIsLessThanCriterionOperation];
		[self setQueryUnits:JVTranscriptMinuteCriterionQueryUnits];
	} else if( [self format] == JVTranscriptBooleanCriterionFormat ) {
		[self setOperation:JVTranscriptNoCriterionOperation];
		[self setQueryUnits:JVTranscriptNoCriterionQueryUnits];
	} else if( [self format] == JVTranscriptListCriterionFormat ) {
		[self setOperation:JVTranscriptIsEqualCriterionOperation];
		[self setQueryUnits:JVTranscriptNoCriterionQueryUnits];
	}
}

- (IBAction) selectCriterionOperation:(id) sender {
	_changed = YES;
	[self setOperation:[[sender selectedItem] tag]];
}

- (IBAction) selectCriterionQueryUnits:(id) sender {
	_changed = YES;
	[self setQueryUnits:[[sender selectedItem] tag]];
}

- (IBAction) changeQuery:(id) sender {
	_changed = YES;
	if( [self format] == JVTranscriptTextCriterionFormat ) {
		[self setQuery:[textQuery stringValue]];
	} else if( [self format] == JVTranscriptDateCriterionFormat ) {
		[self setQuery:[NSNumber numberWithDouble:[dateQuery doubleValue]]];
	} else if( [self format] == JVTranscriptListCriterionFormat ) {
		NSMenuItem *mitem = [listQuery selectedItem];
		if( [mitem representedObject] ) [self setQuery:[mitem representedObject]];
		else [self setQuery:[NSNumber numberWithInt:[listQuery indexOfSelectedItem]]];
	}
}

- (void) controlTextDidChange:(NSNotification *) notification {
	_changed = YES;
}

- (IBAction) noteOtherChanges:(id) sender {
	_changed = YES;
}

#pragma mark -

- (BOOL) changedSinceLastMatch {
	return _changed;
}

- (BOOL) matchMessage:(JVChatMessage *) message ignoreCase:(BOOL) ignoreCase {
	_changed = NO;
	if( [self format] == JVTranscriptTextCriterionFormat ) {
		NSString *value = nil;
		if( [self kind] == JVTranscriptSenderNameCriterionKind ) value = [message senderName];
		else if( [self kind] == JVTranscriptMessageBodyCriterionKind ) value = [message bodyAsPlainText];

		BOOL match = NO;
		JVTranscriptCriterionOperation oper = [self operation];
		if( oper == JVTranscriptTextMatchCriterionOperation || oper == JVTranscriptTextDoesNotMatchCriterionOperation ) {
			AGRegex *regex = [AGRegex regexWithPattern:[self query] options:( ignoreCase ? AGRegexCaseInsensitive : 0 )];
			AGRegexMatch *result = [regex findInString:value];
			if( result ) match = YES;
			if( oper == JVTranscriptTextDoesNotMatchCriterionOperation ) match = ! match;
		} else if( oper >= 3 && oper <= 6 ) {
			unsigned int options = ( ignoreCase ? NSCaseInsensitiveSearch : 0 );
			if( oper == JVTranscriptTextBeginsWithCriterionOperation ) options = NSAnchoredSearch;
			else if( oper == JVTranscriptTextEndsWithCriterionOperation ) options = ( NSAnchoredSearch | NSBackwardsSearch );
			NSRange range = [value rangeOfString:[self query] options:options];
			match = ( range.location != NSNotFound );
			if( oper == JVTranscriptTextDoesNotContainsCriterionOperation ) match = ! match;
		} else if( oper == JVTranscriptIsEqualCriterionOperation ) {
			if( ! ignoreCase ) match = [value isEqualToString:[self query]];
			else match = ! [value caseInsensitiveCompare:[self query]];
		}

		return match;
	} else if( [self kind] == JVTranscriptDateReceivedCriterionKind ) {
		double diff = ABS( [[message date] timeIntervalSinceNow] );
		double comp = [[self query] doubleValue];
		JVTranscriptCriterionOperation oper = [self operation];
		JVTranscriptCriterionQueryUnits unit = [self queryUnits];

		switch( unit ) {
			case JVTranscriptMonthCriterionQueryUnits: comp *= 4.;
			case JVTranscriptWeekCriterionQueryUnits: comp *= 7.;
			case JVTranscriptDayCriterionQueryUnits: comp *= 24.;
			case JVTranscriptHourCriterionQueryUnits: comp *= 60.;
			case JVTranscriptMinuteCriterionQueryUnits: comp *= 60.;
			default: comp = comp; // no change
		}

		if( oper == JVTranscriptIsLessThanCriterionOperation ) return ( diff < comp );
		else return ( diff > comp );
	} else {
		switch( [self kind] ) {
		default:
			return YES;
		case JVTranscriptSenderInBuddyListCriterionKind:
		case JVTranscriptSenderNotInBuddyListCriterionKind:
			return YES;
		case JVTranscriptSenderIgnoredCriterionKind:
			return ( [message ignoreStatus] == JVUserIgnored );
		case JVTranscriptSenderNotIgnoredCriterionKind:
			return ( [message ignoreStatus] != JVUserIgnored );
		case JVTranscriptMessageIgnoredCriterionKind:
			return ( [message ignoreStatus] == JVMessageIgnored );
		case JVTranscriptMessageNotIgnoredCriterionKind:
			return ( [message ignoreStatus] != JVMessageIgnored );
		case JVTranscriptMessageFromMeCriterionKind:
			return [message senderIsLocalUser];
		case JVTranscriptMessageNotFromMeCriterionKind:
			return ( ! [message senderIsLocalUser] );
		case JVTranscriptMessageAddressedToMeCriterionKind:
		case JVTranscriptMessageNotAddressedToMeCriterionKind:
			return YES;
		case JVTranscriptMessageHighlightedCriterionKind:
			return [message isHighlighted];
		case JVTranscriptMessageNotHighlightedCriterionKind:
			return ( ! [message isHighlighted] );
		case JVTranscriptMessageIsActionCriterionKind:
			return [message isAction];
		case JVTranscriptMessageIsNotActionCriterionKind:
			return ( ! [message isAction] );
		}
	}

	return NO;
}

#pragma mark -

- (id) query {
	return _query;
}

- (void) setQuery:(id) query {
	[_query autorelease];
	_query = [query retain];

	if( [self format] == JVTranscriptTextCriterionFormat ) {
		[textQuery setObjectValue:query];
	} else if( [self format] == JVTranscriptDateCriterionFormat ) {
		[dateQuery setObjectValue:query];
	} else if( [self format] == JVTranscriptListCriterionFormat ) {
		int index = [listQuery indexOfItemWithRepresentedObject:query];
		if( index == -1 && [query isKindOfClass:[NSNumber class]] )
			index = [(NSNumber *)query intValue];
		if( [listQuery numberOfItems] < index ) index = -1;
		[listQuery selectItemAtIndex:index];
	}	
}

#pragma mark -

- (JVTranscriptCriterionOperation) operation {
	return _operation;
}

- (void) setOperation:(JVTranscriptCriterionOperation) operation {
	_operation = operation;

	if( [self format] == JVTranscriptTextCriterionFormat ) {
		[textOperationButton selectItemAtIndex:[textOperationButton indexOfItemWithTag:[self operation]]];
	} else if( [self format] == JVTranscriptDateCriterionFormat ) {
		[dateOperationButton selectItemAtIndex:[dateOperationButton indexOfItemWithTag:[self operation]]];
	} else if( [self format] == JVTranscriptListCriterionFormat ) {
		[listOperationButton selectItemAtIndex:[listOperationButton indexOfItemWithTag:[self operation]]];
	}
}

#pragma mark -

- (JVTranscriptCriterionQueryUnits) queryUnits {
	return _queryUnits;
}

- (void) setQueryUnits:(JVTranscriptCriterionQueryUnits) units {
	_queryUnits = units;

	if( [self format] == JVTranscriptDateCriterionFormat ) {
		[dateUnitsButton selectItemAtIndex:[dateUnitsButton indexOfItemWithTag:[self queryUnits]]];
	}
}

#pragma mark -

- (NSView *) firstKeyView {
	if( [self format] == JVTranscriptTextCriterionFormat ) {
		return textKindButton;
	} else if( [self format] == JVTranscriptDateCriterionFormat ) {
		return dateKindButton;
	} else if( [self format] == JVTranscriptBooleanCriterionFormat ) {
		return booleanKindButton;
	} else if( [self format] == JVTranscriptListCriterionFormat ) {
		return listKindButton;
	} else return nil;
}

- (NSView *) lastKeyView {
	if( [self format] == JVTranscriptTextCriterionFormat ) {
		return textQuery;
	} else if( [self format] == JVTranscriptDateCriterionFormat ) {
		return dateUnitsButton;
	} else if( [self format] == JVTranscriptBooleanCriterionFormat ) {
		return booleanKindButton;
	} else if( [self format] == JVTranscriptListCriterionFormat ) {
		return listQuery;
	} else return nil;
}
@end