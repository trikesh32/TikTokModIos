#import <Foundation/Foundation.h>
void TRQInstall(void);
NSDictionary *TRQSnapshot(void);
// Returns nil for a request outside the approved experiment scope.
NSDictionary *TRQPrepare(id url,id headers,id params,id method,id common);
#ifdef TAP_TESTING
BOOL TRQTestInstall(Class cls);
BOOL TRQTestInstallAppend(Class cls);
#endif
