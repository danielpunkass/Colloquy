#import <AppKit/NSNibDeclarations.h>
#import "NSPreferences.h"

@interface JVFileTransferPreferences : NSPreferencesModule {
	IBOutlet NSPopUpButton *autoAccept;
	IBOutlet NSPopUpButton *saveDownloads;
	IBOutlet NSPopUpButton *removeTransfers;
	IBOutlet NSButton *openSafe;
	IBOutlet NSTextField *minRate;
	IBOutlet NSTextField *maxRate;
}
- (IBAction) changePortRange:(id) sender;
- (IBAction) changeAutoAccept:(id) sender;
- (IBAction) changeSaveDownloads:(id) sender;
- (IBAction) changeRemoveTransfers:(id) sender;
- (IBAction) toggleOpenSafeFiles:(id) sender;
@end
