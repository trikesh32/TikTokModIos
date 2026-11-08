#import <Foundation/Foundation.h>
#import <Security/Security.h>

NSDictionary *TAPKeychainMetadata(CFDictionaryRef query);
NSDictionary *TAPKeychainRewrite(NSDictionary *query, NSString *prefix);
void TAPInstallKeychainObservers(void);
#ifdef TAP_TESTING
typedef OSStatus (*TAPCopyFunction)(CFDictionaryRef, CFTypeRef *);
OSStatus TAPTestCopy(TAPCopyFunction original, CFDictionaryRef query, CFTypeRef *result);
#endif
