#import <Foundation/Foundation.h>

NSDictionary *TAPResolveSigningContext(NSDictionary *info, NSDictionary *entitlements);
BOOL TAPInitializeSigningContext(NSBundle *bundle);
NSString *TAPSignedBundleIdentifier(void);
NSString *TAPSigningKeychainPrefix(void);
