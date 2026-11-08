#import <Foundation/Foundation.h>
void TRPInstall(void);
NSDictionary *TRPSnapshot(void);
void TRPBeginWindow(void);
NSDictionary *TRPHeaderSummary(id headers);
NSDictionary *TRPRequestHeaders(id headers);
id TRPNormalizeFields(id fields);
BOOL TRPAllowedPath(id path);
#ifdef TAP_TESTING
BOOL TRPTestProvider(Class cls,SEL selector);
BOOL TRPTestBuilder(Class cls,SEL selector);
BOOL TRPTestHeaders(Class cls,SEL selector,BOOL argument);
BOOL TRPTestResponse(Class cls,SEL selector);
#endif
