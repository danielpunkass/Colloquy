@interface JVNotificationController : NSObject {
	NSMutableDictionary *_bubbles;
	BOOL _growlInstalled;
}
+ (JVNotificationController *) defaultManager;
- (void) performNotification:(NSString *) identifier withContextInfo:(NSDictionary *) context;
@end

@interface NSObject (MVChatPluginNotificationSupport)
- (void) performNotification:(NSString *) identifier withContextInfo:(NSDictionary *) context andPreferences:(NSDictionary *) preferences;
@end