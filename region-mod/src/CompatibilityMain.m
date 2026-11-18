#import <Foundation/Foundation.h>
#import "KeychainProbe.h"
#import "BundleIdentity.h"
#import "ModCompatibility.h"
#import "SigningContext.h"
#ifdef TT_REGION_COMPAT
#import "RegionCompatibility.h"
#define TT_RELEASE_VERSION TRC_VERSION
#else
#define TT_RELEASE_VERSION @"0.3.0"
#endif

// 0.3.0 keeps the complete successful 0.2.6 compatibility configuration.
// No AuthProbe/App Attest/OAuth observers or diagnostic log writer are linked.
void TAPStartCompatibility(NSBundle *bundle) {
    @autoreleasepool {
        if (![[bundle objectForInfoDictionaryKey:@"TTCompatibilityBuild"] isEqual:TT_RELEASE_VERSION] ||
            ![[bundle objectForInfoDictionaryKey:@"TTModCompatibilityProfile"] isEqual:@"full"]) return;
        BOOL container=TAPIsLiveContainerGuest(bundle);
        BOOL signingReady=!container && TAPInitializeSigningContext(bundle);
        if(signingReady) {
            // Standalone signing checks remain strict. The container owns its
            // guest identity and Keychain routing; do not install competing hooks.
            TAPInstallKeychainObservers();
            TAPStartBundleIdentity();
            TAPInstallModCompatibility();
        }
#ifdef TT_REGION_COMPAT
        TRCSetRuntimeEnvironment(container?@"livecontainer":@"standalone");
        TRCSetSigningCompatibility(container?@"container_managed":signingReady?@"validated":@"unavailable");
        if ([[bundle objectForInfoDictionaryKey:@"TTCarrierRegionProfile"] isEqual:@"CA"]) {
            TRCStart();
            TRCStartSettings();
        }
#endif
        // Match 0.2.6 for classes registered later during startup.
        for (int delay=0;delay<5;delay++)
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,delay*NSEC_PER_SEC),dispatch_get_main_queue(),^{
                if(signingReady)TAPInstallModCompatibility();
#ifdef TT_REGION_COMPAT
                if ([[bundle objectForInfoDictionaryKey:@"TTCarrierRegionProfile"] isEqual:@"CA"]) TRCInstallHooks();
#endif
            });
    }
}

#ifndef TAP_TESTING
__attribute__((constructor)) static void StartCompatibility(void) {
    TAPStartCompatibility(NSBundle.mainBundle);
}
#endif
