#import "NSPreferences.h"

@interface JVInterfacePreferences : NSPreferencesModule
#if MAC_OS_X_VERSION_MIN_REQUIRED > MAC_OS_X_VERSION_10_5
<NSTableViewDataSource, NSTableViewDelegate>
#endif
{
	IBOutlet NSTableView *windowSetsTable;
	IBOutlet NSTableView *rulesTable;
	IBOutlet NSButton *deleteWindowButton;
	IBOutlet NSButton *editWindowButton;
	IBOutlet NSButton *deleteRuleButton;
	IBOutlet NSButton *editRuleButton;
	IBOutlet NSPopUpButton *drawerSide;
	IBOutlet NSPopUpButton *interfaceStyle;

	IBOutlet NSPanel *windowEditPanel;
	IBOutlet NSTextField *windowTitle;
	IBOutlet NSButton *rememberPanels;
	IBOutlet NSButton *windowEditSaveButton;

	IBOutlet NSWindow *ruleEditPanel;
	IBOutlet NSTableView *ruleEditTable;
	IBOutlet NSPopUpButton *ruleOperation;
	IBOutlet NSButton *ignoreCase;

	NSMutableArray *_windowSets;
	NSMutableArray *_editingRuleCriterion;
	NSUInteger _selectedWindowSet;
	NSUInteger _selectedRuleSet;
	NSUInteger _origRuleEditHeight;
	BOOL _makingNewWindowSet;
	BOOL _makingNewRuleSet;
}
- (NSMutableArray *) selectedRules;
- (NSMutableArray *) editingCriterion;

- (IBAction) addWindowSet:(id) sender;
- (IBAction) editWindowSet:(id) sender;
- (IBAction) saveWindowSet:(id) sender;
- (IBAction) cancelWindowSet:(id) sender;

- (IBAction) addRuleCriterionRow:(id) sender;
- (IBAction) removeRuleCriterionRow:(id) sender;

- (IBAction) addRuleSet:(id) sender;
- (IBAction) editRuleSet:(id) sender;
- (IBAction) saveRuleSet:(id) sender;
- (IBAction) cancelRuleSet:(id) sender;

- (IBAction) changeSortByStatus:(id) sender;
- (IBAction) changeShowFullRoomName:(id) sender;

- (void) clear:(id) sender;
@end
