#import "SigningContext.h"
#import <Security/Security.h>
#ifndef TAP_TESTING
#include <dlfcn.h>
#endif

static NSDictionary *signingContext;
static NSString *const OriginalID=@"com.zhiliaoapp.musically";

NSDictionary *TAPResolveSigningContext(NSDictionary *info,NSDictionary *entitlements) {
    if(![info isKindOfClass:NSDictionary.class])return nil;
    NSString *identifier=info[@"CFBundleIdentifier"];
    if(![identifier isKindOfClass:NSString.class])return nil;
    if([info[@"TTDistribution"] isEqual:@"altstore-classic"]) {
        if(![info[@"ALTBundleIdentifier"] isEqual:OriginalID] || ![entitlements isKindOfClass:NSDictionary.class])return nil;
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
