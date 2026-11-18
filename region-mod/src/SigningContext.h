#import <Foundation/Foundation.h>

NSDictionary *TAPResolveSigningContext(NSDictionary *info, NSDictionary *entitlements);
BOOL TAPInitializeSigningContext(NSBundle *bundle);
BOOL TAPIsLiveContainerGuestInfo(NSDictionary *guest, NSDictionary *host);
BOOL TAPIsLiveContainerGuest(NSBundle *bundle);
NSString *TAPSignedBundleIdentifier(void);
NSString *TAPSigningKeychainPrefix(void);
