#import <libxml/xinclude.h>
#import "JVChattranscript.h"

NSComparisonResult sortBundlesByName( id style1, id style2, void *context );

@interface JVChatTranscript (JVChatTranscriptPrivate)
+ (const char **) _xsltParamArrayWithDictionary:(NSDictionary *) dictionary;
+ (void) _freeXsltParamArray:(const char **) params;
+ (void) _scanForChatStyles;
+ (void) _scanForEmoticons;

#pragma mark -

- (void) _switchingStyleEnded:(in NSString *) html;
- (oneway void) _switchStyle:(id) sender;
- (void) _changeChatStyleMenuSelection;
- (void) _updateChatStylesMenu;
- (NSString *) _applyStyleOnXMLDocument:(xmlDocPtr) doc;
- (NSString *) _chatStyleBaseURL;
- (NSString *) _chatStyleCSSFileURL;
- (NSString *) _chatStyleVariantCSSFileURL;
- (const char *) _chatStyleXSLFilePath;
- (NSString *) _chatStyleHeaderFileContents;
- (NSMenu *) _emoticonsMenu;
- (void) _changeChatEmoticonsMenuSelection;
- (void) _updateChatEmoticonsMenu;
- (NSString *) _chatEmoticonsMappingFilePath;
- (NSString *) _chatEmoticonsCSSFileURL;
- (NSString *) _fullDisplayHTMLWithBody:(NSString *) html;
- (BOOL) _usingSpecificStyle;
- (BOOL) _usingSpecificEmoticons;
@end
