#import <Foundation/NSObject.h>
#import <Foundation/NSKeyValueCoding.h>

@interface MVApplicationController : NSObject {}
- (IBAction) checkForUpdate:(id) sender;
- (IBAction) connectToSupportRoom:(id) sender;
- (IBAction) emailDeveloper:(id) sender;
- (IBAction) productWebsite:(id) sender;

- (IBAction) showPreferences:(id) sender;
- (IBAction) showTransferManager:(id) sender;
- (IBAction) showConnectionManager:(id) sender;
- (IBAction) showBuddyList:(id) sender;

+ (BOOL) isTerminating;
@end
