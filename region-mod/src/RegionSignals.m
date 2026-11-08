#import "RegionProfile.h"
#import "RegionSignals.h"
#import "RegionCompatibility.h"
#import "RegionEnvironment.h"
#import <objc/runtime.h>
#include <stdatomic.h>
#include <string.h>

static NSDictionary *TimeValues(NSDate *date) {
    NSTimeZone *zone=[NSTimeZone timeZoneWithName:TRFCurrent()[@"timezone"]];
    NSInteger seconds=[zone secondsFromGMTForDate:date];
    return @{@"timezone_name":TRFCurrent()[@"timezone"],@"timezone_offset":@(seconds),@"timezone":@(seconds/3600)};
}
static NSDictionary *FeatureKeys(void) {
    static NSDictionary *map;static dispatch_once_t once;
    dispatch_once(&once,^{
        NSMutableDictionary *m=[NSMutableDictionary new];
        for(NSString *key in @[@"region",@"sys_region",@"current_region",@"residence",@"op_region",@"account_region",@"carrier_region",@"carrier_region_v2",@"mcc_mnc",@"timezone_name",@"timezone_offset",@"timezone",@"locale"])
            m[[@"f_global_" stringByAppendingString:key]]=key;
        map=[m copy];
    });return map;
}
static BOOL Digits(NSString *value,NSUInteger min,NSUInteger max) {
    if(value.length<min || value.length>max)return NO;
    for(NSUInteger i=0;i<value.length;i++){unichar c=[value characterAtIndex:i];if(c<'0'||c>'9')return NO;}
    return YES;
}
static BOOL Country(NSString *value) {
    if(value.length!=2)return NO;
    for(NSUInteger i=0;i<2;i++){unichar c=[value characterAtIndex:i];if(!((c>='A'&&c<='Z')||(c>='a'&&c<='z')))return NO;}
    return YES;
}
static BOOL NumericText(NSString *value) {
    if([value hasPrefix:@"-"]||[value hasPrefix:@"+"])value=[value substringFromIndex:1];
    return Digits(value,1,6);
}
static BOOL LocaleText(NSString *value) {
    if(value.length<2 || value.length>32)return NO;
    static NSRegularExpression *pattern;static dispatch_once_t once;
    dispatch_once(&once,^{pattern=[NSRegularExpression regularExpressionWithPattern:@"^[A-Za-z]{2,3}([_-][A-Za-z]{2,4}){0,2}$" options:0 error:nil];});
    if(![pattern firstMatchInString:value options:0 range:NSMakeRange(0,value.length)])return NO;
    NSString *language=[NSLocale componentsFromLocaleIdentifier:value][NSLocaleLanguageCode];
    return language.length>=2 && language.length<=3;
}
static id Replace(NSString *key,id value) {
    if(!TRCEnabled() || !value)return value;
    // The unqualified f_global_timezone has no verified iOS unit yet.
    if([key isEqual:@"timezone"])return value;
    if([key hasPrefix:@"timezone"] && [@[@"timezone_name",@"timezone_offset",@"timezone"] containsObject:key]) {
        id replacement=TimeValues(NSDate.date)[key];
        if([key isEqual:@"timezone_name"])
            return [value isKindOfClass:NSString.class]?replacement:value;
        if([value isKindOfClass:NSString.class] && NumericText(value))return [replacement stringValue];
        if([value isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)value)!=CFBooleanGetTypeID())return replacement;
        return value;
    }
    if(![value isKindOfClass:NSString.class])return value;
    if([key isEqual:@"locale"]) {
        if(!LocaleText(value))return value;
        NSMutableDictionary *parts=[[NSLocale componentsFromLocaleIdentifier:value] mutableCopy];
        parts[NSLocaleCountryCode]=TRFCountry();
        return [NSLocale localeIdentifierFromComponents:parts];
    }
    if([key isEqual:@"carrier_region_v2"]) {
        // Android implementations disagree; preserve the observed representation.
        if(Digits(value,3,3))return TRFCurrent()[@"mcc"];
        if(Country(value))return TRFCountry();
        return value;
    }
    if([key isEqual:@"mcc_mnc"])return Digits(value,5,6)?TRFOperator():value;
    return Country(value)?TRFCountry():value;
}
id TRGFeatureValue(id name,id value) {
    if(![name isKindOfClass:NSString.class])return value;
    NSString *key=FeatureKeys()[name];return key?Replace(key,value):value;
}
static NSString *SafeValue(NSString *key,id value) {
    if(!value)return @"nil";
    if([value isKindOfClass:NSString.class]) {
        BOOL valid=NO;
        if([key isEqual:@"timezone_name"])valid=[NSTimeZone.knownTimeZoneNames containsObject:value];
        else if([key isEqual:@"locale"])valid=LocaleText(value);
        else if([key isEqual:@"timezone_offset"]||[key isEqual:@"timezone"])valid=NumericText(value);
        else if([key isEqual:@"mcc_mnc"])valid=Digits(value,5,6);
        else if([key isEqual:@"carrier_region_v2"])valid=Country(value)||Digits(value,3,3);
        else valid=Country(value);
        return valid?value:@"unrecognized_string";
    }
    if([value isKindOfClass:NSNumber.class] && [key hasPrefix:@"timezone"] &&
       [value doubleValue]>=-86400 && [value doubleValue]<=86400)return [value stringValue];
    return @"unsupported_type";
}
static NSMutableDictionary *Rows(void) {static NSMutableDictionary *rows;static dispatch_once_t once;dispatch_once(&once,^{rows=[NSMutableDictionary new];});return rows;}
static void Note(NSString *source,NSString *key,id old,id result) {
    NSString *name=[source stringByAppendingFormat:@":%@",key];
    @synchronized(Rows()) {
        NSMutableDictionary *row=Rows()[name];
        if(!row){row=[@{@"source":source,@"field":key,@"reads":@0,@"replacements":@0} mutableCopy];Rows()[name]=row;}
        row[@"reads"]=@([row[@"reads"] unsignedLongLongValue]+1);
        if(![old isEqual:result] && old!=result)row[@"replacements"]=@([row[@"replacements"] unsignedLongLongValue]+1);
        row[@"last_original"]=SafeValue(key,old);row[@"last_effective"]=SafeValue(key,result);
    }
}
id TRGNormalizeDictionary(id value) {
    if(![value isKindOfClass:NSDictionary.class])return value;
    NSMutableDictionary *copy=nil;
    // Names and seconds only; ambiguous `timezone` remains observation-only.
    for(NSString *key in @[@"timezone_name",@"timezone_offset",@"locale",@"carrier_region_v2"]) {
        id old=value[key];if(!old)continue;
        id result=Replace(key,old);Note(@"common_params",key,old,result);
        if(![old isEqual:result]){if(!copy)copy=[value mutableCopy];copy[key]=result;}
    }
    return copy?([value isKindOfClass:NSMutableDictionary.class]?copy:[copy copy]):value;
}
static NSString *installStatus=@"not_attempted";
static IMP installedIMP;
static Class installedClass;
static SEL installedSelector;
static atomic_uint_fast64_t featureCalls,matchedFeatureCalls;
static BOOL Install(Class cls,SEL selector) {
    if(!cls){installStatus=@"class_missing";return NO;}
    @synchronized(Rows()) {
        if(installedIMP && installedClass==cls && installedSelector==selector)return YES;
        Method method=class_getInstanceMethod(cls,selector);BOOL valid=method && method_getNumberOfArguments(method)==4;
        char *ret=method?method_copyReturnType(method):NULL;
        valid=valid && ret && strcmp(ret,"@")==0;free(ret);
        for(unsigned int i=2;valid && i<4;i++){char *arg=method_copyArgumentType(method,i);valid=arg&&strcmp(arg,"@")==0;free(arg);}
        if(!valid){installStatus=method?@"unsupported_abi":@"method_missing";return NO;}
        IMP original=method_getImplementation(method);
        IMP wrapper=imp_implementationWithBlock(^id(id object,id name,id parameters){
            atomic_fetch_add_explicit(&featureCalls,1,memory_order_relaxed);
            NSString *key=[name isKindOfClass:NSString.class]?FeatureKeys()[name]:nil;
            id value;
            if(key)TREBeginScope();
            @try {value=((id(*)(id,SEL,id,id))original)(object,selector,name,parameters);}
            @finally {if(key)TREEndScope();}
            @try {
                if(!key)return value;
                atomic_fetch_add_explicit(&matchedFeatureCalls,1,memory_order_relaxed);
                id result=Replace(key,value);Note(@"feature_producer",key,value,result);return result;
            }@catch(__unused NSException *e){return value;}
        });
        if(!class_addMethod(cls,selector,wrapper,method_getTypeEncoding(method)))method_setImplementation(class_getInstanceMethod(cls,selector),wrapper);
        installedIMP=wrapper;installedClass=cls;installedSelector=selector;installStatus=@"installed";return YES;
    }
}
void TRGInstall(void) {Install(NSClassFromString(@"TikTokCommonParamsFeatureProducer"),NSSelectorFromString(@"getFeatureWithName:parameters:"));}
NSDictionary *TRGSnapshot(void) {
    NSMutableArray *rows=[NSMutableArray new];
    @synchronized(Rows()) {
        for(NSString *key in [[Rows() allKeys] sortedArrayUsingSelector:@selector(compare:)])[rows addObject:[Rows()[key] copy]];
        return @{@"status":installStatus,@"target_time":TimeValues(NSDate.date),@"fields":rows,
            @"producer_calls":@(atomic_load_explicit(&featureCalls,memory_order_relaxed)),
            @"matched_feature_calls":@(atomic_load_explicit(&matchedFeatureCalls,memory_order_relaxed)),
            @"foundation_getters_scoped":@YES,@"unknown_features_passthrough":@YES};
    }
}
#ifdef TAP_TESTING
BOOL TRGTestInstall(Class cls,SEL selector){return Install(cls,selector);}
NSDictionary *TRGTimeValues(NSDate *date){return TimeValues(date);}
#endif
