#import "BundleIdentity.h"
#import "CompatibilityDiagnostics.h"
#import "SigningContext.h"
#import <objc/runtime.h>
#import <objc/message.h>
#include <stdatomic.h>

#ifndef TT_COMPAT_RELEASE
static atomic_uint observations;
#endif
static BOOL installedIdentity;

static BOOL Signature(Method method, unsigned count) {
    if (!method || method_getNumberOfArguments(method)!=count) return NO;
    char *type=method_copyReturnType(method);
    BOOL valid=type && strcmp(type,"@")==0;free(type);
    if (count==3) {
        type=method_copyArgumentType(method,2);valid=valid && type && strcmp(type,"@")==0;free(type);
    }
    return valid;
}

static void Observed(NSString *getter) {
#ifndef TT_COMPAT_RELEASE
    if (atomic_fetch_add(&observations,1)<30)
        TAPEmit(@{@"event":@"bundle_identity_read",@"getter":getter,@"reported_original":@YES});
#endif
}

BOOL TAPInstallBundleIdentity(Class cls,id target,NSString *expected,NSString *replacement) {
    if (installedIdentity || !target || !expected.length || !replacement.length || ![target isKindOfClass:cls]) return NO;
    SEL identifier=@selector(bundleIdentifier),dictionary=@selector(infoDictionary),key=@selector(objectForInfoDictionaryKey:);
    Method mi=class_getInstanceMethod(cls,identifier),md=class_getInstanceMethod(cls,dictionary),mk=class_getInstanceMethod(cls,key);
    if (!Signature(mi,2) || !Signature(md,2) || !Signature(mk,3)) return NO;
    IMP oi=method_getImplementation(mi),od=method_getImplementation(md),ok=method_getImplementation(mk);
    id current=((id(*)(id,SEL))oi)(target,identifier);
    if (![current isKindOfClass:NSString.class] || ![current isEqual:expected]) return NO;
    IMP ri=imp_implementationWithBlock(^id(id self) {
        id result=((id(*)(id,SEL))oi)(self,identifier);
        if (self==target && [result isEqual:expected]) {Observed(@"bundleIdentifier");return replacement;}
        return result;
    });
    IMP rd=imp_implementationWithBlock(^id(id self) {
        id result=((id(*)(id,SEL))od)(self,dictionary);
        if (self!=target || ![result isKindOfClass:NSDictionary.class] || ![result[@"CFBundleIdentifier"] isEqual:expected]) return result;
        NSMutableDictionary *copy=[result mutableCopy];copy[@"CFBundleIdentifier"]=replacement;
        Observed(@"infoDictionary");return [copy copy];
    });
    IMP rk=imp_implementationWithBlock(^id(id self,id name) {
        id result=((id(*)(id,SEL,id))ok)(self,key,name);
        if (self==target && [name isEqual:@"CFBundleIdentifier"] && [result isEqual:expected]) {
            Observed(@"objectForInfoDictionaryKey");return replacement;
        }
        return result;
    });
    if (!class_addMethod(cls,identifier,ri,method_getTypeEncoding(mi))) class_replaceMethod(cls,identifier,ri,method_getTypeEncoding(mi));
    if (!class_addMethod(cls,dictionary,rd,method_getTypeEncoding(md))) class_replaceMethod(cls,dictionary,rd,method_getTypeEncoding(md));
    if (!class_addMethod(cls,key,rk,method_getTypeEncoding(mk))) class_replaceMethod(cls,key,rk,method_getTypeEncoding(mk));
    installedIdentity=YES;return YES;
}

void TAPStartBundleIdentity(void) {
    NSBundle *bundle=NSBundle.mainBundle;
    if (![[bundle objectForInfoDictionaryKey:@"TTBundleIdentityBuild"] isEqual:@"0.1.0"]) return;
    NSString *expected=TAPSignedBundleIdentifier();
    if (!expected.length) return;
    BOOL result=TAPInstallBundleIdentity(NSBundle.class,bundle,expected,@"com.zhiliaoapp.musically");
    (void)result;
    TAPEmit(@{@"event":@"bundle_identity_installed",@"success":@(result)});
}
