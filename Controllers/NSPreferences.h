// Private classes from the AppKit framework; used by Safari and Mail.

@protocol NSPreferencesModule
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_3
- (BOOL) preferencesWindowShouldClose;
- (BOOL) moduleCanBeRemoved;
- (void) moduleWasInstalled;
- (void) moduleWillBeRemoved;
#endif
- (void) didChange;
- (void) initializeFromDefaults;
- (void) willBeDisplayed;
- (void) saveChanges;
- (BOOL) hasChangesPending;
- (NSImage *) imageForPreferenceNamed:(NSString *) name;
- (NSBox *) viewForPreferenceNamed:(NSString *) name;
@end

@interface NSPreferences : NSObject {
#if MAC_OS_X_VERSION_MAX_ALLOWED <= MAC_OS_X_VERSION_10_2
	id preferencesPanel;
	NSBox *preferenceBox;
	id moduleMatrix;
	id okButton;
	id cancelButton;
	id applyButton;
#else
	NSWindow *_preferencesPanel;
	NSBox *_preferenceBox;
	NSMatrix *_moduleMatrix;
	NSButtonCell *_okButton;
	NSButtonCell *_cancelButton;
	NSButtonCell *_applyButton;
#endif
	NSMutableArray *_preferenceTitles;
	NSMutableArray *_preferenceModules;
#if MAC_OS_X_VERSION_MAX_ALLOWED <= MAC_OS_X_VERSION_10_2
	NSMutableDictionary *_preferenceViews;
#else
	NSMutableDictionary *_masterPreferenceViews;
	NSMutableDictionary *_currentSessionPreferenceViews;
#endif
	NSBox *_originalContentView;
	BOOL _isModal;
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_3
	float _constrainedWidth;
	id _currentModule;
	void *_reserved;
#endif
}
+ (id) sharedPreferences;
+ (void) setDefaultPreferencesClass:(Class) class;
+ (Class) defaultPreferencesClass;

- (void) addPreferenceNamed:(NSString *) name owner:(id) owner;

- (NSSize) preferencesContentSize;

- (void) showPreferencesPanel;
- (void) showPreferencesPanelForOwner:(id) owner;
- (int) showModalPreferencesPanelForOwner:(id) owner;
- (int) showModalPreferencesPanel;

- (void) ok:(id) sender;
- (void) cancel:(id) sender;
- (void) apply:(id) sender;

- (NSString *) windowTitle;
- (BOOL) usesButtons;

#if MAC_OS_X_VERSION_MAX_ALLOWED <= MAC_OS_X_VERSION_10_2
- (void) selectModule:(id) sender;
#endif
@end

@interface NSPreferencesModule : NSObject <NSPreferencesModule> {
#if MAC_OS_X_VERSION_MAX_ALLOWED <= MAC_OS_X_VERSION_10_2
	IBOutlet NSBox *preferencesView;
	BOOL hasChanges;
#else
	IBOutlet NSBox *_preferencesView;
	NSSize _minSize;
	BOOL _hasChanges;
	void *_reserved;
#endif
}
+ (id) sharedInstance;
- (NSString *) preferencesNibName;
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_3
- (void) setPreferencesView:(NSView *) view;
#endif
- (NSView *) viewForPreferenceNamed:(NSString *) name;
- (NSImage *) imageForPreferenceNamed:(NSString *) name;
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_3
- (NSString *) titleForIdentifier:(NSString *) identifier;
#endif
- (BOOL) hasChangesPending;
- (void) saveChanges;
- (void) willBeDisplayed;
- (void) initializeFromDefaults;
- (void) didChange;
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_3
- (NSSize) minSize;
- (void) setMinSize:(NSSize) size;
- (BOOL) isResizable;
#endif
@end
