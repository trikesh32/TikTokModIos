#import "RegionProfile.h"
#import "RegionSources.h"
#import "RegionSignals.h"
#import "RegionEnvironment.h"
#import "RegionCompatibility.h"
#import <objc/runtime.h>
#include <stdatomic.h>
#include <string.h>

static NSDictionary *Fields(BOOL settings) {
    static NSDictionary *common,*config;static dispatch_once_t once;
    dispatch_once(&once,^{
        NSMutableDictionary *allCommon=[NSMutableDictionary new],*allConfig=[NSMutableDictionary new];
        for(NSDictionary *profile in TRFProfiles()) {
            NSString *country=profile[@"country"],*operator=[profile[@"mcc"] stringByAppendingString:profile[@"mnc"]];
            allConfig[country]=@{@"current_region":country,@"region_of_residence":country};
            allCommon[country]=@{@"region":country,@"current_region":country,@"sys_region":country,
                @"system_region":country,@"residence":country,@"region_of_residence":country,
                @"account_region":country,@"user_region":country,@"op_region":country,
                @"carrier_region":country,@"sim_region":country,@"store_region":country,
                @"mcc_mnc":operator,@"mccmnc":operator,@"x-tt-store-region":country,@"store-region":country};
        }
        common=[allCommon copy];config=[allConfig copy];
    });return (settings?config:common)[TRFCountry()];
}

id TRSNormalize(id value,BOOL settings) {
    if(!TRCEnabled() || ![value isKindOfClass:NSDictionary.class])return value;
    if(!settings)value=TRGNormalizeDictionary(value);
    NSDictionary *fields=Fields(settings);NSMutableDictionary *copy=nil;
    for(NSString *key in fields) {
        id old=value[key];
        // Settings keys have known fallbacks and must be present. Common params
        // only replace existing keys: do not add another source of duplicates.
        if((old || settings) && ![old isEqual:fields[key]]) {
            if(!copy)copy=[value mutableCopy];copy[key]=fields[key];
        }
    }
    if(!copy)return value;
    // Preserve mutability when the getter's original dictionary was mutable.
    return [value isKindOfClass:NSMutableDictionary.class]?copy:[copy copy];
}
@interface TRSSource : NSObject {
@public atomic_uint_fast64_t reads;atomic_uint_fast64_t replacements;
}
@property(nonatomic,copy) NSString *status;
@end
@implementation TRSSource
- (instancetype)init {if((self=[super init])){atomic_init(&reads,0);atomic_init(&replacements,0);}return self;}
@end
static NSMutableDictionary *Sources(void) {static NSMutableDictionary *s;static dispatch_once_t once;dispatch_once(&once,^{s=[NSMutableDictionary new];});return s;}
static BOOL InstallDictionary(Class cls,SEL selector,BOOL settings) {
    if(!cls)return NO;
    NSString *key=[NSString stringWithFormat:@"%c[%s %s]",class_isMetaClass(cls)?'+':'-',class_getName(cls),sel_getName(selector)];
    @synchronized(Sources()) {
        TRSSource *source=Sources()[key];if([source.status isEqual:@"installed"])return YES;
        if(!source){source=[TRSSource new];Sources()[key]=source;}
        Method method=class_getInstanceMethod(cls,selector);char *type=method?method_copyReturnType(method):NULL;
        BOOL valid=method && method_getNumberOfArguments(method)==2 && type && strcmp(type,"@")==0;
        free(type);if(!valid){source.status=method?@"unsupported_abi":@"missing";return NO;}
        IMP original=method_getImplementation(method);
        IMP wrapper=imp_implementationWithBlock(^id(id object){
            id value;
            if(!settings)TREBeginScope();
            @try {value=((id(*)(id,SEL))original)(object,selector);}
            @finally {if(!settings)TREEndScope();}
            atomic_fetch_add_explicit(&source->reads,1,memory_order_relaxed);
            @try {
                id result=TRSNormalize(value,settings);
                if(result!=value)atomic_fetch_add_explicit(&source->replacements,1,memory_order_relaxed);
                return result;
            } @catch(__unused NSException *e) {return value;}
        });
        if(!class_addMethod(cls,selector,wrapper,method_getTypeEncoding(method)))method_setImplementation(class_getInstanceMethod(cls,selector),wrapper);
        source.status=@"installed";return YES;
    }
}
static void Strings(NSString *name,BOOL classMethod,NSArray *methods) {
    Class cls=NSClassFromString(name);if(classMethod)cls=object_getClass(cls);
    for(NSString *method in methods)TRCInstallGetter(cls,NSSelectorFromString(method),TRFCountry());
}
void TRSInstall(void) {
    TREInstall();
    TRGInstall();
    Strings(@"TIKTOKRegionManager",YES,@[@"storeRegion"]);
    Strings(@"TTKStoreRegionModel",NO,@[@"storeRegion"]);
    Strings(@"TTKStoreRegionService",NO,@[@"storeRegion",@"getStoreRegion"]);
    Strings(@"TTInstallIDManager",NO,@[@"currentAppRegion"]);
    Strings(@"TTNetworkManagerChromium",NO,@[@"userRegion"]);
    Strings(@"AWEUserModel",NO,@[@"passport_region",@"accountRegion"]);
    InstallDictionary(object_getClass(NSClassFromString(@"AWEAppSettings")),NSSelectorFromString(@"awemeSettings"),YES);
    for(NSString *name in @[@"AWENetworkCommonParamNonSensitive",@"AWENetworkCommonParamUtilites"])
        for(NSString *method in @[@"commonParams",@"buildCommonParams",@"buildCommonParamsOptimizedV1",@"buildCommonParamsOptimizedV2",@"buildConsistentCommonParams",@"buildDynamicCommonParams",@"dynamicCommonParamsOfNonChildMode"])
            InstallDictionary(NSClassFromString(name),NSSelectorFromString(method),NO);
    InstallDictionary(object_getClass(NSClassFromString(@"AWENetworkCommonParamNonSensitive")),NSSelectorFromString(@"commonParamsNonSensitive"),NO);
    InstallDictionary(object_getClass(NSClassFromString(@"AWENetworkCommonParamUtilites")),NSSelectorFromString(@"commonParameters"),NO);
    InstallDictionary(NSClassFromString(@"AWENetworkConfigImpl"),NSSelectorFromString(@"commonParams"),NO);
    InstallDictionary(NSClassFromString(@"AWENetworkConfigImpl"),NSSelectorFromString(@"commonParamsNonSensitive"),NO);
    InstallDictionary(NSClassFromString(@"_TtC12PNSRegionSDK20PNSRegionServiceImpl"),NSSelectorFromString(@"getTTNetHeaders"),NO);
}
NSDictionary *TRSSnapshot(void) {
    NSMutableArray *rows=[NSMutableArray new];
    @synchronized(Sources()) {
        for(NSString *key in [[Sources() allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
            TRSSource *source=Sources()[key];[rows addObject:@{@"method":key,@"status":source.status,
                @"reads":@(atomic_load_explicit(&source->reads,memory_order_relaxed)),
                @"replacements":@(atomic_load_explicit(&source->replacements,memory_order_relaxed))}];
        }
    }
    return @{@"mode":@"aggressive_sources",@"country":TRFCountry(),@"sources":rows,@"signals":TRGSnapshot(),@"environment":TRESnapshot(),@"persistent_region_writes":@NO};
}
#ifdef TAP_TESTING
BOOL TRSTestInstall(Class cls,SEL selector,BOOL settings) {return InstallDictionary(cls,selector,settings);}
#endif
