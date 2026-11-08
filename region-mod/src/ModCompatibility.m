// Optional, process-local compatibility profile. No signature/receipt fabrication.
#import "ModCompatibility.h"
#import "CompatibilityDiagnostics.h"
#import <objc/runtime.h>
#include <stdatomic.h>

static NSMutableSet *compatInstalled;
#ifndef TT_COMPAT_RELEASE
static NSMutableDictionary *compatStatus;
static atomic_uint compatReads;
#endif

static BOOL IsType(Method m, int index, const char *expected) {
    char *type=index<0 ? method_copyReturnType(m) : method_copyArgumentType(m,(unsigned)index);
    BOOL ok=type && strcmp(type,expected)==0;free(type);return ok;
}
static NSString *HookKey(Class cls,NSString *name) {
    return [NSString stringWithFormat:@"%@[%@ %@]",class_isMetaClass(cls)?@"+":@"-",NSStringFromClass(cls),name];
}
static Method Candidate(Class cls,NSString *name,unsigned count) {
    if (!cls) return NULL;
    if (!compatInstalled) compatInstalled=[NSMutableSet set];
    if ([compatInstalled containsObject:HookKey(cls,name)]) return NULL;
    Method m=class_getInstanceMethod(cls,NSSelectorFromString(name));
    return m && method_getNumberOfArguments(m)==count ? m : NULL;
}
static void Observe(NSString *key) {
#ifndef TT_COMPAT_RELEASE
    if (atomic_fetch_add(&compatReads,1)<200)
        TAPEmit(@{@"event":@"compat_read",@"source":key});
#endif
}
static BOOL Replace(Class cls,NSString *name,Method m,IMP hook) {
    SEL sel=NSSelectorFromString(name);
    if (!class_addMethod(cls,sel,hook,method_getTypeEncoding(m)))
        class_replaceMethod(cls,sel,hook,method_getTypeEncoding(m));
    NSString *key=HookKey(cls,name);[compatInstalled addObject:key];
    TAPEmit(@{@"event":@"compat_installed",@"source":key});return YES;
}
static void ReportAvailability(Class cls,NSString *className,NSString *name) {
#ifndef TT_COMPAT_RELEASE
    if (!compatStatus) compatStatus=[NSMutableDictionary dictionary];
    NSString *source=[NSString stringWithFormat:@"%@: %@",className,name];
    NSString *status=!cls ? @"class_missing" :
        [compatInstalled containsObject:HookKey(cls,name)] ? @"enabled" : @"method_missing_or_abi_mismatch";
    if (![compatStatus[source] isEqual:status]) {
        compatStatus[source]=status;
        TAPEmit(@{@"event":@"compat_status",@"source":source,@"status":status});
    }
#endif
}
BOOL TAPCompatBool(Class cls,NSString *name,BOOL value,BOOL booleanArgument) {
    Method m=Candidate(cls,name,booleanArgument?3:2);
    if (!m) return NO;
    // arm64 BOOL is B; older libraries may use signed char. Match each ABI exactly.
    BOOL b=IsType(m,-1,"B"),c=IsType(m,-1,"c");
    if ((!b && !c) || (booleanArgument && !IsType(m,2,b?"B":"c"))) return NO;
    NSString *key=HookKey(cls,name);IMP hook;
    if (booleanArgument) {
        if (b) hook=imp_implementationWithBlock(^bool(id self,bool argument){Observe(key);return (bool)value;});
        else hook=imp_implementationWithBlock(^signed char(id self,signed char argument){Observe(key);return (signed char)value;});
    } else {
        if (b) hook=imp_implementationWithBlock(^bool(id self){Observe(key);return (bool)value;});
        else hook=imp_implementationWithBlock(^signed char(id self){Observe(key);return (signed char)value;});
    }
    return Replace(cls,name,m,hook);
}
BOOL TAPCompatString(Class cls,NSString *name,NSString *value) {
    Method m=Candidate(cls,name,2);
    if (!m || !IsType(m,-1,"@") || ![value isKindOfClass:NSString.class]) return NO;
    NSString *key=HookKey(cls,name);NSString *copy=[value copy];
    return Replace(cls,name,m,imp_implementationWithBlock(^id(id self){Observe(key);return copy;}));
}
BOOL TAPCompatResource(Class cls,id target,NSString *name) {
    if (!target || ![target isKindOfClass:cls]) return NO;
    Method m=Candidate(cls,name,4);
    if (!m || !IsType(m,-1,"@") || !IsType(m,2,"@") || !IsType(m,3,"@")) return NO;
    IMP original=method_getImplementation(m);SEL sel=NSSelectorFromString(name);NSString *key=HookKey(cls,name);
    IMP hook=imp_implementationWithBlock(^id(id self,id resource,id extension){
        if (self==target && [resource isKindOfClass:NSString.class] && [extension isKindOfClass:NSString.class] &&
            [resource isEqual:@"embedded"] && [extension isEqual:@"mobileprovision"]) {
            Observe(key);return nil;
        }
        return ((id(*)(id,SEL,id,id))original)(self,sel,resource,extension);
    });
    return Replace(cls,name,m,hook);
}

void TAPInstallModCompatibility(void) {
    NSBundle *bundle=NSBundle.mainBundle;
    NSString *profile=[bundle objectForInfoDictionaryKey:@"TTModCompatibilityProfile"];
    if (![@[@"store",@"full"] containsObject:profile]) return;
    NSArray *specs=@[
        @[@"AWEAPMManager",@"signInfo",@"string"],
        @[@"GULAppEnvironmentUtil",@"isFromAppStore",@"true"],
        @[@"GULAppEnvironmentUtil",@"isAppStoreReceiptSandbox",@"false"]
    ];
    NSMutableArray *all=[specs mutableCopy];
    if ([profile isEqual:@"full"]) {
        for (NSString *name in @[@"BDADeviceHelper",@"TTInstallUtil",@"IESLiveDeviceInfo",@"BDInstallNetworkUtility",@"TTAdSplashDeviceHelper"])
            [all addObject:@[name,@"isJailBroken",@"false"]];
        [all addObject:@[@"UIDevice",@"btd_isJailBroken",@"false"]];
        [all addObject:@[@"FBSDKAppEventsUtility",@"isDebugBuild",@"false"]];
        [all addObject:@[@"AppsFlyerUtils",@"isJailbrokenWithSkipAdvancedJailbreakValidation:",@"argument"]];
    }
    for (NSArray *spec in all) {
        Class cls=object_getClass(NSClassFromString(spec[0]));
        if ([spec[2] isEqual:@"string"]) TAPCompatString(cls,spec[1],@"AppStore");
        else TAPCompatBool(cls,spec[1],[spec[2] isEqual:@"true"],[spec[2] isEqual:@"argument"]);
        ReportAvailability(cls,spec[0],spec[1]);
    }
    TAPCompatResource(NSBundle.class,bundle,@"pathForResource:ofType:");
    TAPCompatResource(NSBundle.class,bundle,@"URLForResource:withExtension:");
    ReportAvailability(NSBundle.class,@"NSBundle",@"pathForResource:ofType:");
    ReportAvailability(NSBundle.class,@"NSBundle",@"URLForResource:withExtension:");
    // No changes to isAppExtension, the receipt bytes, security collectors, IAP,
    // App Attest, system trust, or files on disk. Signing must remain valid.
}
