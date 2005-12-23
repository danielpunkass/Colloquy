#import "NSPreferences.h"

@class JVFontPreviewField;
@class JVStyle;
@class JVStyleView;

@interface JVAppearancePreferences : NSPreferencesModule {
	IBOutlet JVStyleView *preview;
	IBOutlet NSPopUpButton *styles;
	IBOutlet NSPopUpButton *emoticons;
	IBOutlet JVFontPreviewField *standardFont;
	IBOutlet NSTextField *minimumFontSize;
	IBOutlet NSStepper *minimumFontSizeStepper;
	IBOutlet NSTextField *baseFontSize;
	IBOutlet NSStepper *baseFontSizeStepper;
	IBOutlet NSDrawer *optionsDrawer;
	IBOutlet NSTableView *optionsTable;
	IBOutlet NSPanel *newVariantPanel;
	IBOutlet NSTextField *newVariantName;
	BOOL _variantLocked;
	BOOL _alertDisplayed;
	JVStyle *_style;
	NSMutableArray *_styleOptions;
	NSString *_userStyle;
}
- (void) selectStyleWithIdentifier:(NSString *) identifier;
- (void) selectEmoticonsWithIdentifier:(NSString *) identifier;

- (void) setStyle:(JVStyle *) style;

- (void) changePreferences;

- (IBAction) changeBaseFontSize:(id) sender;
- (IBAction) changeMinimumFontSize:(id) sender;

- (IBAction) changeDefaultChatStyle:(id) sender;
- (IBAction) changeDefaultEmoticons:(id) sender;

- (IBAction) showOptions:(id) sender;

- (void) updateChatStylesMenu;
- (void) updateEmoticonsMenu;
- (void) updateVariant;

- (void) parseStyleOptions;
- (NSString *) valueOfProperty:(NSString *) property forSelector:(NSString *) selector inStyle:(NSString *) style;
- (void) setStyleProperty:(NSString *) property forSelector:(NSString *) selector toValue:(NSString *) value;
- (void) setUserStyle:(NSString *) style;
- (void) saveStyleOptions;

- (void) showNewVariantSheet;
- (IBAction) closeNewVariantSheet:(id) sender;
- (IBAction) createNewVariant:(id) sender;
@end
