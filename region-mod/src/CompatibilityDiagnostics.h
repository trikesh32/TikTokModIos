// Diagnostic calls are removed at preprocessing time from the release module.
#ifdef TT_COMPAT_RELEASE
#define TAPEmit(...) ((void)0)
#else
#import "AuthProbe.h"
#endif
