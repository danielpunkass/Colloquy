#import "NSObjectAdditions.h"

#import <objc/message.h>

#if ENABLE(SECRETS)
#define SAFE_PERFORM_BASE(function, cast, arguments, defaultValue) \
	SEL selector = NSSelectorFromString(selectorString); \
	if (LIKELY([self respondsToSelector:selector]))\
		return (cast function)arguments; \
	NSAssert2(NO, @"%@ does not respond to %@.", NSStringFromClass([self class]), selectorString); \
	return defaultValue 
#else
#define SAFE_PERFORM_BASE(function, cast, arguments, defaultValue) \
	return defaultValue
#endif

#define SAFE_PERFORM(cast, arguments, defaultValue) \
	SAFE_PERFORM_BASE(objc_msgSend, cast, arguments, defaultValue)

#define SAFE_PERFORM_RETURNING_STRUCT(cast, arguments, defaultValue) \
	SAFE_PERFORM_BASE(objc_msgSend_stret, cast, arguments, defaultValue)

@implementation NSObject (NSObjectAdditions)
+ (id) performPrivateSelector:(NSString *) selectorString {
	SAFE_PERFORM((id (*)(id, SEL)), (self, selector), nil);
}

- (id) performPrivateSelector:(NSString *) selectorString {
	SAFE_PERFORM((id (*)(id, SEL)), (self, selector), nil);
}

- (id) performPrivateSelector:(NSString *) selectorString withObject:(id) object {
	SAFE_PERFORM((id (*)(id, SEL, id)), (self, selector, object), nil);
}

- (id) performPrivateSelector:(NSString *) selectorString withBoolean:(BOOL) boolean {
	SAFE_PERFORM((id (*)(id, SEL, BOOL)), (self, selector, boolean), nil);
}

- (id) performPrivateSelector:(NSString *) selectorString withUnsignedInteger:(NSUInteger) integer {
	SAFE_PERFORM((id (*)(id, SEL, NSUInteger)), (self, selector, integer), nil);
}

- (id) performPrivateSelector:(NSString *) selectorString withRange:(NSRange) range {
	SAFE_PERFORM((id (*)(id, SEL, NSRange)), (self, selector, range), nil);
}

- (CGPoint) performPrivateSelectorReturningPoint:(NSString *) selectorString {
	SAFE_PERFORM_RETURNING_STRUCT((CGPoint (*)(id, SEL)), (self, selector), CGPointZero);
}

- (BOOL) performPrivateSelectorReturningBoolean:(NSString *) selectorString {
	SAFE_PERFORM((BOOL (*)(id, SEL)), (self, selector), NO);
}
@end
