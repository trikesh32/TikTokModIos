#import <Foundation/Foundation.h>
void TRSInstall(void);
NSDictionary *TRSSnapshot(void);
id TRSNormalize(id value,BOOL settings);
#ifdef TAP_TESTING
BOOL TRSTestInstall(Class cls,SEL selector,BOOL settings);
#endif
