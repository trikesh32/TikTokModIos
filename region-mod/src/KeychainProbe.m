// Observe metadata and OSStatus only. No account/service/tag/key/token values.
#import "KeychainProbe.h"
#import "CompatibilityDiagnostics.h"
#import "SigningContext.h"
#include <stdatomic.h>
#include <errno.h>
#ifndef TAP_TESTING
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include "fishhook.h"
#endif

static OSStatus (*OriginalCopy)(CFDictionaryRef, CFTypeRef *);
#ifndef TAP_TESTING
static OSStatus (*OriginalAdd)(CFDictionaryRef, CFTypeRef *);
static OSStatus (*OriginalUpdate)(CFDictionaryRef, CFDictionaryRef);
static OSStatus (*OriginalDelete)(CFDictionaryRef);
#endif
#ifndef TT_COMPAT_RELEASE
static atomic_uint recorded;
#endif
static NSString *compatPrefix;

static NSDictionary *VendorGroups(void) {
    return @{@"MJ797D8U6F.com.zhiliaoapp.musically.test":@"test",
             @"MJ797D8U6F.com.zhiliaoapp.musically":@"main",
             @"MJ797D8U6F.com.zhiliaoapp.shared":@"shared",
             @"MJ797D8U6F.com.zhiliaoapp.musically.dev":@"dev",
             @"MJ797D8U6F.com.chainlogin":@"chainlogin",
             @"MJ797D8U6F.com.chainassociate":@"chainassociate"};
}

NSDictionary *TAPKeychainRewrite(NSDictionary *query, NSString *prefix) {
    if (![query isKindOfClass:NSDictionary.class] || !prefix.length) return query;
    id group=query[(__bridge id)kSecAttrAccessGroup];
    if (![group isKindOfClass:NSString.class]) return query;
    NSString *label=VendorGroups()[group];
    if (!label) return query;
    NSMutableDictionary *copy=[query mutableCopy];
    copy[(__bridge id)kSecAttrAccessGroup]=[prefix stringByAppendingFormat:@".compat.%@",label];
    return copy;
}

#ifndef TT_COMPAT_RELEASE
NSDictionary *TAPKeychainMetadata(CFDictionaryRef query) {
    if (!query || CFGetTypeID(query)!=CFDictionaryGetTypeID()) return @{};
    NSDictionary *q=(__bridge NSDictionary *)query;
    id group=q[(__bridge id)kSecAttrAccessGroup];
    NSString *scope=@"default";
    if (group) scope=[group isKindOfClass:NSString.class] && [group hasPrefix:@"MJ797D8U6F."] ? @"vendor" : @"other";
    id kind=q[(__bridge id)kSecClass];NSString *label=@"other";
    for (NSArray *pair in @[@[(__bridge id)kSecClassGenericPassword,@"generic_password"],
                            @[(__bridge id)kSecClassInternetPassword,@"internet_password"],
                            @[(__bridge id)kSecClassKey,@"key"],
                            @[(__bridge id)kSecClassCertificate,@"certificate"],
                            @[(__bridge id)kSecClassIdentity,@"identity"]]) {
        if ([pair[0] isEqual:kind]) label=pair[1];
    }
    NSString *groupLabel=[group isKindOfClass:NSString.class] ? VendorGroups()[group] : nil;
    return @{@"item_class":label,@"access_group_scope":scope,@"explicit_access_group":@(group!=nil),
             @"vendor_group_label":groupLabel ?: @"none",@"compat_remapped":@(compatPrefix.length>0 && groupLabel!=nil)};
}

static void Observe(NSString *operation,CFDictionaryRef query,OSStatus status) {
    int savedErrno=errno;
    @try {
        if (atomic_fetch_add(&recorded,1)<1000) {
            NSMutableDictionary *event=[TAPKeychainMetadata(query) mutableCopy];
            event[@"event"]=@"keychain_result";event[@"operation"]=operation;event[@"status"]=@(status);
            TAPEmit(event);
        }
    } @catch (__unused NSException *exception) {}
    errno=savedErrno;
}
#else
#define Observe(...) ((void)0)
#endif

static OSStatus Copy(CFDictionaryRef query,CFTypeRef *result) {
    NSDictionary *mapped=TAPKeychainRewrite((__bridge NSDictionary *)query,compatPrefix);
    OSStatus status=OriginalCopy((__bridge CFDictionaryRef)mapped,result);Observe(@"copy",query,status);return status;
}
#ifdef TAP_TESTING
OSStatus TAPTestCopy(TAPCopyFunction original,CFDictionaryRef query,CFTypeRef *result) {
    OriginalCopy=original;return Copy(query,result);
}
void TAPInstallKeychainObservers(void) {}
#else
static OSStatus Add(CFDictionaryRef query,CFTypeRef *result) {
    NSDictionary *mapped=TAPKeychainRewrite((__bridge NSDictionary *)query,compatPrefix);
    OSStatus status=OriginalAdd((__bridge CFDictionaryRef)mapped,result);Observe(@"add",query,status);return status;
}
static OSStatus Update(CFDictionaryRef query,CFDictionaryRef attributes) {
    NSDictionary *mapped=TAPKeychainRewrite((__bridge NSDictionary *)query,compatPrefix);
    NSDictionary *mappedAttributes=TAPKeychainRewrite((__bridge NSDictionary *)attributes,compatPrefix);
    OSStatus status=OriginalUpdate((__bridge CFDictionaryRef)mapped,(__bridge CFDictionaryRef)mappedAttributes);
    Observe(@"update",query,status);return status;
}
static OSStatus Delete(CFDictionaryRef query) {
    NSDictionary *mapped=TAPKeychainRewrite((__bridge NSDictionary *)query,compatPrefix);
    OSStatus status=OriginalDelete((__bridge CFDictionaryRef)mapped);Observe(@"delete",query,status);return status;
}
static void OnImage(const struct mach_header *header,intptr_t slide) {
    @autoreleasepool {
        Dl_info info;
        if (!dladdr(header,&info) || !info.dli_fname) return;
        NSString *path=@(info.dli_fname);
        NSString *prefix=[NSBundle.mainBundle.bundlePath stringByAppendingString:@"/"];
        if (![path hasPrefix:prefix]) return;
#ifdef TT_COMPAT_RELEASE
        if ([path.lastPathComponent isEqual:@"TikTokCompatibility.dylib"]) return;
#else
        if ([path.lastPathComponent isEqual:@"TikTokAuthProbe.dylib"]) return;
#endif
        struct rebinding bindings[]={
            {"SecItemCopyMatching",(void *)Copy,NULL},{"SecItemAdd",(void *)Add,NULL},
            {"SecItemUpdate",(void *)Update,NULL},{"SecItemDelete",(void *)Delete,NULL}};
        int result=rebind_symbols_image((void *)header,slide,bindings,4);
        (void)result;
        // A successful API call does not prove that any imported pointer changed.
        TAPEmit(@{@"event":@"keychain_binding_attempt",@"result":@(result)});
    }
}
void TAPInstallKeychainObservers(void) {
    NSString *prefix=TAPSigningKeychainPrefix();
    if ([[NSBundle.mainBundle objectForInfoDictionaryKey:@"TTKeychainCompatBuild"] isEqual:@"0.1.0"] &&
        prefix.length) {
        compatPrefix=[prefix copy];
        TAPEmit(@{@"event":@"keychain_compat_enabled",@"version":@"0.1.0"});
    }
    OriginalCopy=dlsym(RTLD_DEFAULT,"SecItemCopyMatching");OriginalAdd=dlsym(RTLD_DEFAULT,"SecItemAdd");
    OriginalUpdate=dlsym(RTLD_DEFAULT,"SecItemUpdate");OriginalDelete=dlsym(RTLD_DEFAULT,"SecItemDelete");
    if (!OriginalCopy || !OriginalAdd || !OriginalUpdate || !OriginalDelete) {
        TAPEmit(@{@"event":@"keychain_symbols_unavailable"});return;
    }
    _dyld_register_func_for_add_image(OnImage);
}
#endif
