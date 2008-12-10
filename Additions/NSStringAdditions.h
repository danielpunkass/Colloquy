BOOL isValidUTF8( const char *s, unsigned len );

@interface NSString (NSStringAdditions)
+ (NSString *) locallyUniqueString;

+ (unsigned long) scriptTypedEncodingFromStringEncoding:(NSStringEncoding) encoding;
+ (NSStringEncoding) stringEncodingFromScriptTypedEncoding:(unsigned long) encoding;

- (id) initWithChatData:(NSData *) data encoding:(NSStringEncoding) encoding;

- (BOOL) isCaseInsensitiveEqualToString:(NSString *) string;
- (BOOL) hasCaseInsensitivePrefix:(NSString *) prefix;
- (BOOL) hasCaseInsensitiveSuffix:(NSString *) suffix;
- (BOOL) hasCaseInsensitiveSubstring:(NSString *) substring;

- (NSString *) stringByEncodingXMLSpecialCharactersAsEntities;
- (NSString *) stringByDecodingXMLSpecialCharacterEntities;

- (NSString *) stringByEscapingCharactersInSet:(NSCharacterSet *) set;

- (NSString *) stringByEncodingIllegalURLCharacters;
- (NSString *) stringByDecodingIllegalURLCharacters;

- (NSString *) stringByStrippingIllegalXMLCharacters;
- (NSString *) stringByStrippingXMLTags;

- (NSString *) stringWithDomainNameSegmentOfAddress;

- (BOOL) containsEmojiCharacters;
- (BOOL) containsEmojiCharactersInRange:(NSRange) range;
- (NSRange) rangeOfEmojiCharactersInRange:(NSRange) range;

- (BOOL) containsTypicalEmoticonCharacters;

- (NSString *) stringBySubstitutingEmojiForEmoticons;
- (NSString *) stringBySubstitutingEmoticonsForEmoji;
@end

@interface NSMutableString (NSMutableStringAdditions)
- (void) encodeXMLSpecialCharactersAsEntities;
- (void) decodeXMLSpecialCharacterEntities;

- (void) escapeCharactersInSet:(NSCharacterSet *) set;

- (void) encodeIllegalURLCharacters;
- (void) decodeIllegalURLCharacters;

- (void) stripIllegalXMLCharacters;
- (void) stripXMLTags;

- (void) substituteEmoticonsForEmoji;
- (void) substituteEmoticonsForEmojiInRange:(NSRangePointer) range;

- (void) substituteEmojiForEmoticons;
- (void) substituteEmojiForEmoticonsInRange:(NSRangePointer) range;
- (void) substituteEmojiForEmoticonsInRange:(NSRangePointer) range encodeXMLSpecialCharactersAsEntities:(BOOL) encode;
@end
