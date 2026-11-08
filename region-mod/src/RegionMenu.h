#import <Foundation/Foundation.h>
void TRMInstall(void (^openSettings)(void),id icon);
NSDictionary *TRMSnapshot(void);
#ifdef TAP_TESTING
BOOL TRMTestInstall(Class section,Class plugin,Class item,void (^openSettings)(void),id icon);
#endif
