typedef struct {
	BOOL x86;
	BOOL x86_64;
	BOOL ppc32;
	BOOL ppc64;
	BOOL armv6;
	BOOL armv7;
	NSInteger unknown; // 68k, MIPS, etc
} MVArchitectures;

@interface NSFileManager (Additions)
- (MVArchitectures) architecturesForBinaryAtPath:(NSString *) path;

- (BOOL) canExecutePluginAtPath:(NSString *) pluginPath;
@end

NSString *NSStringFromMVArchitectures(MVArchitectures architectures);
