#import <Foundation/Foundation.h>
void TREInstall(void);
void TREBeginScope(void);
void TREEndScope(void);
NSDictionary *TRESnapshot(void);
#ifdef TAP_TESTING
BOOL TRETestGetter(Class cls,SEL selector,BOOL zone,BOOL scoped);
BOOL TRETestCarrier(Class cls,SEL selector,BOOL serviceArgument);
NSUInteger TRETestDepth(void);
#endif
