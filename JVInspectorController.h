#import <AppKit/NSWindowController.h>
#import <AppKit/NSNibDeclarations.h>
#import <Foundation/NSGeometry.h>

@class NSView;
@protocol JVInspection;

@protocol JVInspector <NSObject>
- (NSView *) view;
- (NSSize) minSize;
- (NSString *) title;
- (NSString *) type;
@end

@interface NSObject (JVInspectorOptional)
- (void) willLoad;
- (void) didLoad;

- (BOOL) shouldUnload;
- (void) didUnload;
@end

@protocol JVInspection <NSObject>
- (id <JVInspector>) inspector;
@end

@protocol JVInspectionDelegator <NSObject>
- (id <JVInspection>) objectToInspect;
- (IBAction) getInfo:(id) sender;
@end

@interface JVInspectorController : NSWindowController {
	BOOL _locked;
	id <JVInspection> _object;
	id <JVInspector> _inspector;
}
+ (JVInspectorController *) sharedInspector;
+ (JVInspectorController *) inspectorOfObject:(id <JVInspection>) object;

- (id) initWithObject:(id <JVInspection>) object lockedOn:(BOOL) locked;

- (IBAction) show:(id) sender;

- (void) inspectObject:(id <JVInspection>) object;
@end
