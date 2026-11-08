#import "RegionProfile.h"
#import "RegionCompatibility.h"
#ifdef TT_REGION_AGGRESSIVE
#import "RegionSources.h"
#import "RegionPNS.h"
#import "RegionMenu.h"
#endif
#ifdef TT_REGION_REQUESTS
#import "RegionRequest.h"
#endif
#ifdef TT_REGION_DIAGNOSTICS
#import "RegionObservation.h"
#endif
#import <objc/runtime.h>
#include <stdatomic.h>
#include <string.h>

static NSString *const EnabledKey = @"TRCarrierRegion.enabled.v2";
static BOOL active;
static NSTimeInterval regionStarted,regionReady,uiAttached;
void TRCUIAttached(void) {if(!uiAttached)uiAttached=NSProcessInfo.processInfo.systemUptime;}
@interface TRCRecord : NSObject {
@public
    atomic_uint_fast64_t reads;
    atomic_uint_fast64_t replacements;
}
@property(nonatomic,copy) NSString *status;
@end
@implementation TRCRecord
- (instancetype)init { if ((self=[super init])) { atomic_init(&reads,0); atomic_init(&replacements,0); } return self; }
@end

static NSMutableDictionary<NSString *,TRCRecord *> *Records(void) {
    static NSMutableDictionary *records;
    static dispatch_once_t once;
    dispatch_once(&once,^{ records=[NSMutableDictionary new]; });
    return records;
}
BOOL TRCEnabled(void) { return active; }
#ifdef TAP_TESTING
void TRCTestEnabled(BOOL enabled) { active=enabled; }
#endif
BOOL TRCSavedEnabled(void) { return [NSUserDefaults.standardUserDefaults boolForKey:EnabledKey]; }
void TRCSaveEnabled(BOOL enabled) {
    // Startup snapshot: change all getters together after a full app restart.
    [NSUserDefaults.standardUserDefaults setBool:enabled forKey:EnabledKey];
}
BOOL TRCInstallGetter(Class cls, SEL selector, NSString *value) {
    if (!cls || !selector || !value) return NO;
    NSString *key=[NSString stringWithFormat:@"%c[%s %s]",class_isMetaClass(cls)?'+':'-',class_getName(cls),sel_getName(selector)];
    NSMutableDictionary *records=Records();
    @synchronized(records) {
        TRCRecord *record=records[key];
        if ([record.status isEqual:@"installed"]) return YES;
        if (!record) { record=[TRCRecord new]; records[key]=record; }
        Method method=class_getInstanceMethod(cls,selector);
        if (!method) { record.status=@"missing"; return NO; }
        char *returnType=method_copyReturnType(method);
        BOOL valid=method_getNumberOfArguments(method)==2 && returnType && strcmp(returnType,"@")==0;
        free(returnType);
        if (!valid) { record.status=@"unsupported_abi"; return NO; }
        IMP original=method_getImplementation(method);
        NSString *replacement=[value copy];
        IMP hook=imp_implementationWithBlock(^id(id object) {
            atomic_fetch_add_explicit(&record->reads,1,memory_order_relaxed);
            if (active) {
                atomic_fetch_add_explicit(&record->replacements,1,memory_order_relaxed);
                return replacement;
            }
            return ((id (*)(id,SEL))original)(object,selector);
        });
        // Override an inherited getter on this class, never on its parent.
        if (!class_addMethod(cls,selector,hook,method_getTypeEncoding(method)))
            method_setImplementation(class_getInstanceMethod(cls,selector),hook);
        record.status=@"installed";
        return YES;
    }
}
static void Install(NSString *name,BOOL classMethod,NSDictionary<NSString *,NSString *> *values) {
    Class cls=NSClassFromString(name);
    if (!cls) return; // Classes loaded later are retried on activation/startup.
    if (classMethod) cls=object_getClass(cls);
    for (NSString *selector in values) TRCInstallGetter(cls,NSSelectorFromString(selector),values[selector]);
}
void TRCInstallHooks(void) {
    Install(@"TTReachability",YES,@{
        @"primaryCarrierIsoCountryCode":TRFCountry().lowercaseString, @"primaryCarrierMobileCountryCode":TRFCurrent()[@"mcc"],
        @"primaryCarrierMobileNetworkCode":TRFCurrent()[@"mnc"], @"primaryCarrierCarrierName":TRFCurrent()[@"carrier"]});
    Install(@"TIKTOKRegionManager",YES,@{
        @"carrierRegion":TRFCountry(), @"mccmnc":TRFOperator(), @"region":TRFCountry(),
        @"localRegion":TRFCountry(), @"systemRegion":TRFCountry(), @"currentRegionV2":TRFCountry()});
    Install(@"CTCarrier",NO,@{
        @"isoCountryCode":TRFCountry().lowercaseString, @"mobileCountryCode":TRFCurrent()[@"mcc"],
        @"mobileNetworkCode":TRFCurrent()[@"mnc"], @"carrierName":TRFCurrent()[@"carrier"]});
#ifdef TT_REGION_AGGRESSIVE
    TRSInstall();
    TRPInstall();
#endif
#ifdef TT_REGION_DIAGNOSTICS
    TRDInstall();
#endif
#ifdef TT_REGION_REQUESTS
    TRQInstall();
#endif
}
void TRCStart(void) {
    regionStarted=NSProcessInfo.processInfo.systemUptime;
    (void)TRFCurrent();
    [NSUserDefaults.standardUserDefaults registerDefaults:@{EnabledKey:@YES}];
    active=[NSUserDefaults.standardUserDefaults boolForKey:EnabledKey];
    TRCInstallHooks();
    regionReady=NSProcessInfo.processInfo.systemUptime;
}
NSDictionary *TRCDiagnostics(void) {
    NSMutableArray *hooks=[NSMutableArray new];
    NSMutableDictionary *records=Records();
    @synchronized(records) {
        for (NSString *key in [[records allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
            TRCRecord *record=records[key];
            [hooks addObject:@{@"method":key,@"status":record.status,
                @"reads":@(atomic_load_explicit(&record->reads,memory_order_relaxed)),
                @"replacements":@(atomic_load_explicit(&record->replacements,memory_order_relaxed))}];
        }
    }
    NSMutableDictionary *result=[@{@"mod":TRC_VERSION,@"region":TRFCountry(),@"enabled":@(active),
        @"enabled_after_restart":@([NSUserDefaults.standardUserDefaults boolForKey:EnabledKey]),
        @"hooks":hooks,@"region_after_restart":TRFSavedCountry(),
        @"restart_required":@(TRCSavedEnabled()!=active || ![TRFSavedCountry() isEqual:TRFCountry()])} mutableCopy];
#ifdef TT_REGION_DIAGNOSTICS
    result[@"region_observation"]=TRDSnapshot();
#endif
#ifdef TT_REGION_REQUESTS
    result[@"request_rewrite"]=TRQSnapshot();
#endif
#ifdef TT_REGION_AGGRESSIVE
    result[@"source_profile"]=TRSSnapshot();
    result[@"pns_region"]=TRPSnapshot();
    result[@"settings_menu"]=TRMSnapshot();
    result[@"launch_timing"]=@{@"region_init_ms":@((regionReady-regionStarted)*1000),
        @"settings_opened_ms_after_region_start":uiAttached?@((uiAttached-regionStarted)*1000):NSNull.null};
#endif
    return result;
}
