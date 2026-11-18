#import "SigningContext.h"
#import <Security/Security.h>
#import <objc/runtime.h>
#include <string.h>
#ifndef TAP_TESTING
#include <dlfcn.h>
#endif

static NSDictionary *signingContext;
static NSString *const OriginalID=@"com.zhiliaoapp.musically";

BOOL TAPIsLiveContainerGuestInfo(NSDictionary *guest,NSDictionary *host) {
    if(![guest isKindOfClass:NSDictionary.class] || ![host isKindOfClass:NSDictionary.class])return NO;
    if(![guest[@"CFBundleIdentifier"] isEqual:OriginalID])return NO;
    NSString *identifier=host[@"CFBundleIdentifier"];
    if(![identifier isKindOfClass:NSString.class])return NO;
    return [identifier isEqual:@"com.kdt.livecontainer"] || [identifier hasPrefix:@"com.kdt.livecontainer."];
}

BOOL TAPIsLiveContainerGuest(NSBundle *bundle) {
    // LiveContainer exposes its actual host bundle through this class method.
    // Read it before installing any identity/Keychain compatibility hooks.
    SEL selector=NSSelectorFromString(@"lcMainBundle");
    Method method=class_getClassMethod(NSUserDefaults.class,selector);
    if(!method || method_getNumberOfArguments(method)!=2)return NO;
    char *type=method_copyReturnType(method);
    BOOL valid=type && !strcmp(type,"@");free(type);if(!valid)return NO;
    id host=((id(*)(id,SEL))method_getImplementation(method))(NSUserDefaults.class,selector);
    if(![host isKindOfClass:NSBundle.class] || host==bundle ||
       [[host bundlePath] isEqual:bundle.bundlePath])return NO;
    return TAPIsLiveContainerGuestInfo(bundle.infoDictionary,[host infoDictionary]);
}

NSDictionary *TAPResolveSigningContext(NSDictionary *info,NSDictionary *entitlements) {
    if(![info isKindOfClass:NSDictionary.class])return nil;
    NSString *identifier=info[@"CFBundleIdentifier"];
    if(![identifier isKindOfClass:NSString.class])return nil;
    if([info[@"TTDistribution"] isEqual:@"altstore-classic"]) {
        // SideStore omits ALTBundleIdentifier. Signed identity and exact grants below
        // are authoritative; reject a conflicting hint, but do not require it.
        id hint=info[@"ALTBundleIdentifier"];
        if((hint && ![hint isEqual:OriginalID]) || ![entitlements isKindOfClass:NSDictionary.class])return nil;
        NSString *team=entitlements[@"com.apple.developer.team-identifier"];
        NSString *application=entitlements[@"application-identifier"];
        NSArray *groups=entitlements[@"keychain-access-groups"];
        if(![team isKindOfClass:NSString.class] || team.length!=10 ||
           [team rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"] invertedSet]].location!=NSNotFound ||
           ![application isKindOfClass:NSString.class] || ![groups isKindOfClass:NSArray.class])return nil;
        // AltStore supports both its older prefix and current suffix App ID format.
        if(![identifier isEqual:[OriginalID stringByAppendingFormat:@".%@",team]] &&
           ![identifier isEqual:[NSString stringWithFormat:@"com.%@.%@",team,OriginalID]])return nil;
        if(![application isEqual:[NSString stringWithFormat:@"%@.%@",team,identifier]])return nil;
        NSString *prefix=[NSString stringWithFormat:@"%@.%@.altstore",team,OriginalID];
        if(![groups containsObject:prefix])return nil;
        for(NSString *label in @[@"main",@"test",@"shared",@"dev",@"chainlogin",@"chainassociate"])
            if(![groups containsObject:[prefix stringByAppendingFormat:@".compat.%@",label]])return nil;
        return @{@"bundle":identifier,@"keychain":prefix};
    }
    // Keep the existing local signer path and its isolated namespaces unchanged.
    NSString *expected=info[@"TTSignedBundleIdentifier"],*prefix=info[@"TTKeychainCompatPrefix"];
    if(![expected isKindOfClass:NSString.class] || ![expected isEqual:identifier] ||
       ![expected hasPrefix:[OriginalID stringByAppendingString:@"."]] ||
       ![prefix isKindOfClass:NSString.class] || ![prefix hasSuffix:[@"." stringByAppendingString:identifier]])return nil;
    return @{@"bundle":identifier,@"keychain":prefix};
}

BOOL TAPInitializeSigningContext(NSBundle *bundle) {
    if(signingContext)return YES;
    NSDictionary *info=bundle.infoDictionary;
    NSMutableDictionary *entitlements=[NSMutableDictionary dictionary];
#ifndef TAP_TESTING
    if([info[@"TTDistribution"] isEqual:@"altstore-classic"]) {
        // Read only this process's effective signed entitlements, not a copied
        // provisioning profile or a publisher's embedded identity.
        CFTypeRef (*create)(CFAllocatorRef)=dlsym(RTLD_DEFAULT,"SecTaskCreateFromSelf");
        CFTypeRef (*copyValue)(CFTypeRef,CFStringRef,CFErrorRef *)=dlsym(RTLD_DEFAULT,"SecTaskCopyValueForEntitlement");
        if(!create || !copyValue)return NO;
        CFTypeRef task=create(kCFAllocatorDefault);if(!task)return NO;
        for(NSString *key in @[@"application-identifier",@"com.apple.developer.team-identifier",@"keychain-access-groups"]) {
            CFTypeRef value=copyValue(task,(__bridge CFStringRef)key,NULL);
            if(value)entitlements[key]=CFBridgingRelease(value);
        }
        CFRelease(task);
    }
#endif
    signingContext=[TAPResolveSigningContext(info,entitlements) copy];
    return signingContext!=nil;
}
NSString *TAPSignedBundleIdentifier(void){return signingContext[@"bundle"];}
NSString *TAPSigningKeychainPrefix(void){return signingContext[@"keychain"];}
