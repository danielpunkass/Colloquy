#import <CoreServices/CoreServices.h> 
#import <Foundation/Foundation.h>

/* Sample transcript:
<log began="2005-07-11 12:19:09 -0400" source="irc://irc.freenode.net/%23barcamp">
 <event id="H5OI9GYEXB" name="memberJoined" occurred="2005-08-20 22:13:28 -0400">
  <message><span class="member">vdwal</span> joined the chat room.</message>
  <who hostmask="n=vanderwa@dsl092-170-254.wdc2.dsl.speakeasy.net">vdwal</who>
 </event>
 <envelope>
  <sender hostmask="i=urgy@c-67-188-71-51.hsd1.ca.comcast.net">urgen</sender>
  <message id="H7DJHOYEXB" received="2005-08-20 22:13:36 -0400">hi</message>
 </envelope>
 <envelope>
  <sender hostmask="n=vanderwa@dsl092-170-254.wdc2.dsl.speakeasy.net">vdwal</sender>
  <message id="XVQ44ZYEXB" received="2005-08-20 22:13:47 -0400">where did everybody go?</message>
  <message id="GD3YCAZEXB" received="2005-08-20 22:13:58 -0400">hi</message>
  <message id="D0TAANZEXB" received="2005-08-20 22:14:11 -0400">i lost my nickname and my legs</message>
  <message id="H5CJHSZEXB" received="2005-08-20 22:14:16 -0400">stuck again</message>
 </envelope>
</log>
*/

@interface JVChatTranscriptMetadataExtractor : NSObject {
	BOOL inEnvelope;
	BOOL inMessage;
	NSString *lastElement;
	NSDate *dateStarted;
	NSString *lastEventDate;
	NSString *source;
	NSMutableString *content;
	NSMutableSet *participants;
}
- (id) initWithCapacity:(unsigned) capacity;
- (NSDictionary *) metadataAttributes;
@end

@implementation JVChatTranscriptMetadataExtractor
- (id) initWithCapacity:(unsigned) capacity {
	if( ( self = [super init] ) ) {
		content = [[NSMutableString alloc] initWithCapacity:capacity];
		participants = [[NSMutableSet alloc] initWithCapacity:400];
	}

	return self;
}

- (void) dealloc {
	[lastElement release];
	[content release];
	[participants release];
	[dateStarted release];
	[lastEventDate release];
	[source release];

	lastElement = nil;
	content = nil;
	participants = nil;
	dateStarted = nil;
	lastEventDate = nil;
	source = nil;

	[super dealloc];
}

- (NSDictionary *) metadataAttributes {
	NSMutableDictionary *ret = [NSMutableDictionary dictionary];
	[ret setObject:content forKey:(NSString *) kMDItemTextContent];

	if( dateStarted ) [ret setObject:dateStarted forKey:(NSString *) kMDItemContentCreationDate];
	if( [lastEventDate length] ) {
		NSDate *lastDate = [NSDate dateWithString:lastEventDate];
		if( lastDate ) {
			[ret setObject:lastDate forKey:(NSString *) kMDItemContentModificationDate];
			[ret setObject:lastDate forKey:(NSString *) kMDItemLastUsedDate];

			if( dateStarted ) {
				// Set Duration
				NSTimeInterval logDuration = [lastDate timeIntervalSinceDate:dateStarted];
				[ret setObject:[NSNumber numberWithInt:logDuration] forKey:(NSString *) kMDItemDurationSeconds];

				// Set Coverage
				NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
				[formatter setFormatterBehavior:NSDateFormatterBehavior10_4];
				[formatter setDateStyle:NSDateFormatterShortStyle];
				[formatter setTimeStyle:NSDateFormatterShortStyle];

				NSString *coverageWording = [NSString stringWithFormat:@"%@ - %@", [formatter stringFromDate:dateStarted], [formatter stringFromDate:lastDate]];
				[ret setObject:coverageWording forKey:(NSString *) kMDItemCoverage];
				[formatter release];
			}			
		}
	}

	if( [participants count] ) [ret setObject:[participants allObjects] forKey:(NSString *) kMDItemContributors];
	if( [source length] ) [ret setObject:source forKey:(NSString *) kMDItemWhereFroms];

	[ret setObject:[NSArray arrayWithObject:@"transcript"] forKey:(NSString *) kMDItemKind];
	[ret setObject:[NSArray arrayWithObject:@"Colloquy"] forKey:(NSString *) kMDItemCreator];

	return ret;
}

- (void) parser:(NSXMLParser *) parser didStartElement:(NSString *) elementName namespaceURI:(NSString *) namespaceURI qualifiedName:(NSString *) qName attributes:(NSDictionary *) attributes {
	[lastElement release];
	lastElement = [elementName retain];

	if( [elementName isEqualToString:@"envelope"] ) inEnvelope = YES;
	else if( [elementName isEqualToString:@"message"] ) {
		inMessage = YES;
		NSString *date = [attributes objectForKey:@"received"];
		if( date ) {
			[lastEventDate release];
			lastEventDate = [date retain];
			if( ! dateStarted ) dateStarted = [[NSDate alloc] initWithString:date];
		}
	} else if( [elementName isEqualToString:@"event"] ) {
		NSString *date = [attributes objectForKey:@"occurred"];
		if( date ) {
			[lastEventDate release];
			lastEventDate = [date retain];
			if( ! dateStarted ) dateStarted = [[NSDate alloc] initWithString:date];
		}
	} else if( [elementName isEqualToString:@"log"] ) {
		NSString *date = [attributes objectForKey:@"began"];
		if( date && ! dateStarted ) dateStarted = [[NSDate alloc] initWithString:date];
	}
}

- (void) parser:(NSXMLParser *) parser didEndElement:(NSString *) elementName namespaceURI:(NSString *) namespaceURI qualifiedName:(NSString *) qName {
	if( inEnvelope && [elementName isEqualToString:@"envelope"] ) inEnvelope = NO;
	else if( inEnvelope && inMessage && [elementName isEqualToString:@"message"] ) {
		inMessage = NO;
		[content appendString:@" "]; // append a space after messages
	} else if( inEnvelope && inMessage ) {
		[content appendString:@" "]; // append a space after formatting elements since we are still in the message
	}

	[lastElement release];
	lastElement = nil;
}

- (void) parser:(NSXMLParser *) parser foundCharacters:(NSString *) string {
	if( inEnvelope && inMessage ) {
		NSString *newString = [string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if( [newString length] ) [content appendString:newString];
	} else if( inEnvelope && [lastElement isEqualToString:@"sender"] ) {
		[participants addObject:string];
	}
}
@end

Boolean GetMetadataForFile( void *thisInterface, CFMutableDictionaryRef attributes, CFStringRef contentTypeUTI, CFStringRef pathToFile ) {
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	NSFileManager *fm = [NSFileManager defaultManager];

	if( ! [fm fileExistsAtPath:(NSString *) pathToFile] ) goto end;
	if( ! [fm isReadableFileAtPath:(NSString *) pathToFile] ) goto end;

	NSURL *file = [NSURL fileURLWithPath:(NSString *) pathToFile];
	NSXMLParser *parser = [[NSXMLParser alloc] initWithContentsOfURL:file];

	unsigned long long fileSize = [[fm fileAttributesAtPath:(NSString *) pathToFile traverseLink:YES] fileSize];
	unsigned capacity = ( fileSize ? fileSize / 3 : 5000 ); // the message content takes up about a third of the XML file's size

	JVChatTranscriptMetadataExtractor *extractor = [[JVChatTranscriptMetadataExtractor alloc] initWithCapacity:capacity];

	[parser setDelegate:extractor];
	[parser parse];

	[(NSMutableDictionary *) attributes addEntriesFromDictionary:[extractor metadataAttributes]];

	[parser release];
	[extractor release];

end:
	[pool release];
    return TRUE;
}