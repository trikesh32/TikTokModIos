#import <Foundation/Foundation.h>
#ifdef TT_REGION_AGGRESSIVE
#define TRC_VERSION @"1.1.3"
#elif defined(TT_REGION_REQUESTS)
#define TRC_VERSION @"0.3.4"
#elif defined(TT_REGION_DIAGNOSTICS)
#define TRC_VERSION @"0.3.2"
#else
#define TRC_VERSION @"0.3.1"
#endif

BOOL TRCInstallGetter(Class cls, SEL selector, NSString *value);
void TRCStart(void);
void TRCSetSigningCompatibility(NSString *state);
void TRCSetRuntimeEnvironment(NSString *environment);
void TRCInstallHooks(void);
BOOL TRCEnabled(void);
BOOL TRCSavedEnabled(void);
void TRCSaveEnabled(BOOL enabled);
NSDictionary *TRCDiagnostics(void);
void TRCStartSettings(void);
void TRCUIAttached(void);
#ifdef TAP_TESTING
void TRCTestEnabled(BOOL enabled);
#endif
