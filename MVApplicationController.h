#import <Foundation/NSObject.h>

@interface MVApplicationController : NSObject {
	BOOL _terminating;
}
- (IBAction) checkForUpdate:(id) sender;
- (IBAction) connectToSupportRoom:(id) sender;
- (IBAction) emailDeveloper:(id) sender;
- (IBAction) productWebsite:(id) sender;

- (IBAction) showPreferences:(id) sender;
- (IBAction) showTransferManager:(id) sender;
- (IBAction) showConnectionManager:(id) sender;
- (IBAction) showBuddyList:(id) sender;

- (BOOL) isTerminating;
@end
