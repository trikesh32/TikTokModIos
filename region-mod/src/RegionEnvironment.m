#import "RegionProfile.h"
#import "RegionEnvironment.h"
#import "RegionCompatibility.h"
#import <objc/runtime.h>
#include <stdatomic.h>
#include <string.h>

// Scope follows synchronous common-parameter production, not a thread forever.
// Never enter this scope around an OAuth callback or device-identity producer.
static _Thread_local NSUInteger scopeDepth;
static _Thread_local BOOL replacing;
void TREBeginScope(void){scopeDepth++;}
void TREEndScope(void){if(scopeDepth)scopeDepth--;}

@interface TREHook : NSObject {
@public atomic_uint_fast64_t calls,eligible,changes;
}
@property(nonatomic,copy) NSString *status;
@property(nonatomic,copy) NSString *effective;
@end
@implementation TREHook
- (instancetype)init {if((self=[super init])){atomic_init(&calls,0);atomic_init(&eligible,0);atomic_init(&changes,0);}return self;}
@end
static NSMutableDictionary *Hooks(void) {
    static NSMutableDictionary *d;static dispatch_once_t once;
    dispatch_once(&once,^{d=[NSMutableDictionary new];});return d;
}
static NSString *HookKey(Class cls,SEL selector) {
    return [NSString stringWithFormat:@"%c[%s %s]",class_isMetaClass(cls)?'+':'-',class_getName(cls),sel_getName(selector)];
}
static BOOL ObjectReturn(Method m,unsigned int arguments) {
    if(!m || method_getNumberOfArguments(m)!=arguments)return NO;
    char *t=method_copyReturnType(m);BOOL ok=t && strcmp(t,"@")==0;free(t);return ok;
}
static BOOL IntegerArgument(Method m,unsigned int argument) {
    char *t=method_copyArgumentType(m,argument);BOOL ok=t && strcmp(t,@encode(NSInteger))==0;free(t);return ok;
}
static TREHook *Row(NSString *key) {
    TREHook *r=Hooks()[key];if(!r){r=[TREHook new];Hooks()[key]=r;}return r;
}
static void Note(TREHook *row,id old,id value,NSString *effective) {
    if(old!=value && ![old isEqual:value])atomic_fetch_add_explicit(&row->changes,1,memory_order_relaxed);
    @synchronized(Hooks()){row.effective=effective;}
}
static NSString *LocaleIdentifier(id original) {
    if([original isKindOfClass:NSLocale.class])return [original localeIdentifier];
    if([original isKindOfClass:NSString.class])return original;
    return nil;
}
static id ProfileLocale(id original) {
    NSString *identifier=LocaleIdentifier(original);
    if(identifier.length<2 || identifier.length>64)return original;
    NSMutableDictionary *parts=[[NSLocale componentsFromLocaleIdentifier:identifier] mutableCopy];
    NSString *language=parts[NSLocaleLanguageCode];
    if(language.length<2 || language.length>3)return original;
    for(NSUInteger i=0;i<language.length;i++) {
        unichar c=[language characterAtIndex:i];
        if(!((c>='a'&&c<='z')||(c>='A'&&c<='Z')))return original;
    }
    if([parts[NSLocaleCountryCode] isEqual:TRFCountry()])return original;
    if(!parts[NSLocaleScriptCode]) {
        // Foundation canonicalizes zh_Hans_CN to zh_CN. Recover the language
        // script before replacing the country (otherwise zh_TW can change script).
        NSString *canonical=[NSLocale canonicalLanguageIdentifierFromString:identifier];
        NSString *script=[NSLocale componentsFromLocaleIdentifier:canonical][NSLocaleScriptCode];
        if(!script && [language isEqual:@"zh"] && [@[@"HK",@"MO"] containsObject:parts[NSLocaleCountryCode]])script=@"Hant";
        if(script)parts[NSLocaleScriptCode]=script;
    }
    parts[NSLocaleCountryCode]=TRFCountry();
    NSString *out=[NSLocale localeIdentifierFromComponents:parts];
    return [original isKindOfClass:NSLocale.class]?[[NSLocale alloc] initWithLocaleIdentifier:out]:out;
}
static BOOL Getter(Class cls,SEL selector,BOOL zone,BOOL scoped) {
    if(!cls)return NO;
    @synchronized(Hooks()) {
        TREHook *r=Row(HookKey(cls,selector));if([r.status isEqual:@"installed"])return YES;
        Method m=class_getInstanceMethod(cls,selector);
        if(!ObjectReturn(m,2)){r.status=m?@"unsupported_abi":@"missing";return NO;}
        IMP original=method_getImplementation(m);
        IMP wrapper=imp_implementationWithBlock(^id(id object){
            id value=((id(*)(id,SEL))original)(object,selector);
            atomic_fetch_add_explicit(&r->calls,1,memory_order_relaxed);
            if(!TRCEnabled() || replacing || (scoped && !scopeDepth))return value;
            atomic_fetch_add_explicit(&r->eligible,1,memory_order_relaxed);
            replacing=YES;
            @try {
                id result=value;NSString *effective=@"unsupported_type";
                if(zone && [value isKindOfClass:NSTimeZone.class]) {
                    NSTimeZone *target=[NSTimeZone timeZoneWithName:TRFCurrent()[@"timezone"]];
                    if(target)result=target;
                    effective=[result name];
                } else if(!zone) {
                    result=ProfileLocale(value);
                    // Only report the effective country, never arbitrary locale extensions.
                    NSString *identifier=LocaleIdentifier(result);
                    NSString *country=identifier?[NSLocale componentsFromLocaleIdentifier:identifier][NSLocaleCountryCode]:nil;
                    effective=[country isEqual:TRFCountry()]?TRFCountry():@"not_replaced";
                }
                Note(r,value,result,effective);return result;
            }@catch(__unused NSException *e){return value;}
            @finally{replacing=NO;}
        });
        if(!class_addMethod(cls,selector,wrapper,method_getTypeEncoding(m)))method_setImplementation(class_getInstanceMethod(cls,selector),wrapper);
        r.status=@"installed";return YES;
    }
}
static NSString *CarrierValue(NSInteger type) {
    // Verified in 47.6.0: TTReachability helper at 0x21DBEB34, selector table
    // 0x2D349E70: carrierName, isoCountryCode, mobileCountryCode, mobileNetworkCode.
    switch(type){case 1:return TRFCurrent()[@"carrier"];case 2:return TRFCountry().lowercaseString;case 3:return TRFCurrent()[@"mcc"];case 4:return TRFCurrent()[@"mnc"];default:return nil;}
}
static id CarrierResult(TREHook *r,NSInteger type,id value) {
    atomic_fetch_add_explicit(&r->calls,1,memory_order_relaxed);
    if(!TRCEnabled())return value;
    NSString *replacement=CarrierValue(type);
    if(!replacement || (value && ![value isKindOfClass:NSString.class]))return value;
    atomic_fetch_add_explicit(&r->eligible,1,memory_order_relaxed);
    Note(r,value,replacement,[TRFCountry() stringByAppendingString:@"_carrier_profile"]);return replacement;
}
static BOOL Carrier(Class cls,SEL selector,BOOL serviceArgument) {
    if(!cls)return NO;
    @synchronized(Hooks()) {
        TREHook *r=Row(HookKey(cls,selector));if([r.status isEqual:@"installed"])return YES;
        Method m=class_getInstanceMethod(cls,selector);
        BOOL valid=ObjectReturn(m,serviceArgument?4:3) && IntegerArgument(m,2) && (!serviceArgument || IntegerArgument(m,3));
        if(!valid){r.status=m?@"unsupported_abi":@"missing";return NO;}
        IMP original=method_getImplementation(m),wrapper;
        if(serviceArgument)wrapper=imp_implementationWithBlock(^id(id object,NSInteger service,NSInteger type){
            id value=((id(*)(id,SEL,NSInteger,NSInteger))original)(object,selector,service,type);
            return CarrierResult(r,type,value);
        });
        else wrapper=imp_implementationWithBlock(^id(id object,NSInteger type){
            id value=((id(*)(id,SEL,NSInteger))original)(object,selector,type);
            return CarrierResult(r,type,value);
        });
        if(!class_addMethod(cls,selector,wrapper,method_getTypeEncoding(m)))method_setImplementation(class_getInstanceMethod(cls,selector),wrapper);
        r.status=@"installed";return YES;
    }
}
void TREInstall(void) {
    Class locale=object_getClass(NSLocale.class),zone=object_getClass(NSTimeZone.class);
    for(NSString *s in @[@"currentLocale",@"autoupdatingCurrentLocale",@"systemLocale"])Getter(locale,NSSelectorFromString(s),NO,YES);
    for(NSString *s in @[@"localTimeZone",@"systemTimeZone",@"defaultTimeZone",@"autoupdatingLocalTimeZone"])Getter(zone,NSSelectorFromString(s),YES,YES);
    Getter(NSClassFromString(@"AWELanguageManager"),NSSelectorFromString(@"currentLocale"),NO,NO);
    Carrier(NSClassFromString(@"TTReachabilityCarrierInfo"),NSSelectorFromString(@"getCarrierInfoWithType:"),NO);
    Class reach=object_getClass(NSClassFromString(@"TTReachability"));
    Carrier(reach,NSSelectorFromString(@"currentCarrierInfoForDataServiceWithPropertyType:"),NO);
    Carrier(reach,NSSelectorFromString(@"currentCarrierInfoForService:withPropertyType:"),YES);
}
NSDictionary *TRESnapshot(void) {
    NSMutableArray *rows=[NSMutableArray new];
    @synchronized(Hooks()) {
        for(NSString *key in [[Hooks() allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
            TREHook *r=Hooks()[key];
            [rows addObject:@{@"method":key,@"status":r.status?:@"not_attempted",
                @"calls":@(atomic_load_explicit(&r->calls,memory_order_relaxed)),
                @"eligible_calls":@(atomic_load_explicit(&r->eligible,memory_order_relaxed)),
                @"replacements":@(atomic_load_explicit(&r->changes,memory_order_relaxed)),
                @"effective":r.effective?:@"unobserved"}];
        }
    }
    return @{@"scope":@"synchronous_network_common_parameters",@"hooks":rows,
        @"timezone_target":TRFCurrent()[@"timezone"],@"language_preserved":@YES,
        @"device_identity_hash_hooked":@NO,@"clock_changed":@NO};
}
#ifdef TAP_TESTING
BOOL TRETestGetter(Class cls,SEL selector,BOOL zone,BOOL scoped){return Getter(cls,selector,zone,scoped);}
BOOL TRETestCarrier(Class cls,SEL selector,BOOL serviceArgument){return Carrier(cls,selector,serviceArgument);}
NSUInteger TRETestDepth(void){return scopeDepth;}
#endif
