#import "RegionProfile.h"
#import "RegionPNS.h"
#import "RegionCompatibility.h"
#import "RegionEnvironment.h"
#import "RegionObservation.h"
#import <objc/runtime.h>
#include <string.h>

// Observe only bounded, allowlisted region values. Opaque header VALUES, account
// identifiers, URLs, bodies and callbacks are never retained by diagnostics.
static NSMutableDictionary *Rows(void) {
    static NSMutableDictionary *d;static dispatch_once_t once;
    dispatch_once(&once,^{d=[NSMutableDictionary new];});return d;
}
static NSMutableSet *HeaderKeys(void) {
    static NSMutableSet *s;static dispatch_once_t once;
    dispatch_once(&once,^{s=[NSMutableSet new];});return s;
}
static NSUInteger generation;
static BOOL ObjectDictionary(id value){return [value isKindOfClass:NSDictionary.class];}
static NSSet *CountryKeys(void) {
    static NSSet *keys;static dispatch_once_t once;
    dispatch_once(&once,^{keys=[NSSet setWithArray:@[@"region",@"current_region",@"system_region",@"sys_region",
        @"carrier_region",@"network_sim_region",@"sim_region",@"store_region",@"account_region",@"residence",@"op_region",@"mcc_mnc"]];});return keys;
}

static BOOL CountryText(id value) {
    if(![value isKindOfClass:NSString.class] || [value length]!=2)return NO;
    for(NSUInteger i=0;i<2;i++){unichar c=[value characterAtIndex:i];if(!((c>='a'&&c<='z')||(c>='A'&&c<='Z')))return NO;}return YES;
}
static id FieldValue(NSString *key,id value) {
    NSString *country=[CountryKeys() containsObject:key]?([key isEqual:@"mcc_mnc"]?TRFOperator():TRFCountry()):nil;
    if(country && [value isKindOfClass:NSString.class]) {
        if(![key isEqual:@"mcc_mnc"])return CountryText(value)?country:value;
        if([value length]!=5 && [value length]!=6)return value;
        for(NSUInteger i=0;i<[value length];i++){unichar c=[value characterAtIndex:i];if(c<'0'||c>'9')return value;}return country;
    }
    if([key isEqual:@"locale"] && [value isKindOfClass:NSString.class] && [value length]<=32) {
        NSRegularExpression *re=[NSRegularExpression regularExpressionWithPattern:@"^[A-Za-z]{2,3}([_-][A-Za-z]{2,4}){0,2}$" options:0 error:nil];
        if(![re firstMatchInString:value options:0 range:NSMakeRange(0,[value length])])return value;
        NSMutableDictionary *parts=[[NSLocale componentsFromLocaleIdentifier:value] mutableCopy];
        parts[NSLocaleCountryCode]=TRFCountry();return [NSLocale localeIdentifierFromComponents:parts];
    }
    // Ambiguous timezone numbers/units and unknown representations pass through.
    if([@[@"timezone",@"timezone_name"] containsObject:key] && [value isKindOfClass:NSString.class] && [NSTimeZone.knownTimeZoneNames containsObject:value])return TRFCurrent()[@"timezone"];
    return value;
}
static NSArray *Containers(void){return @[@"data",@"params",@"region_info",@"device_info",@"sim_info"];}
static id Normalize(id value,NSUInteger depth,NSUInteger *budget) {
    if(depth>3 || !*budget)return value;
    if([value isKindOfClass:NSArray.class]) {
        if([value count]>32)return value;
        NSMutableArray *copy=nil;NSUInteger i=0;
        for(id item in value){id result=Normalize(item,depth+1,budget);if(result!=item){if(!copy)copy=[value mutableCopy];copy[i]=result;}i++;}
        return copy?([value isKindOfClass:NSMutableArray.class]?copy:[copy copy]):value;
    }
    if(!ObjectDictionary(value) || [value count]>128)return value;
    NSMutableDictionary *copy=nil;
    for(id key in value) {
        if(!*budget)break;(*budget)--;
        if(![key isKindOfClass:NSString.class])continue;
        id old=value[key],result=FieldValue(key,old);
        if([Containers() containsObject:key])result=Normalize(old,depth+1,budget);
        if(result!=old && ![old isEqual:result]){if(!copy)copy=[value mutableCopy];copy[key]=result;}
    }
    return copy?([value isKindOfClass:NSMutableDictionary.class]?copy:[copy copy]):value;
}
id TRPNormalizeFields(id fields) {
    if(!TRCEnabled())return fields;
    NSUInteger budget=512;return Normalize(fields,0,&budget);
}
BOOL TRPAllowedPath(id path) {
    if(![path isKindOfClass:NSString.class] || [path length]>2048)return NO;
    NSURLComponents *url=[NSURLComponents componentsWithString:path];if(!url)return NO;
    if(url.host || url.scheme) {
        if(![url.scheme.lowercaseString isEqual:@"https"])return NO;
        NSString *h=url.host.lowercaseString;BOOL allowed=NO;
        for(NSString *s in @[@"tiktokv.com",@"tiktok.com",@"tiktokv.us",@"musical.ly"])
            if([h isEqual:s] || [h hasSuffix:[@"." stringByAppendingString:s]])allowed=YES;
        if(!allowed)return NO;
    }
    NSString *p=url.path;if([p hasSuffix:@"/"])p=[p substringToIndex:p.length-1];
    return [@[@"/location/region",@"/tiktok/location/region",@"/tiktok/pns/privacy_headers"] containsObject:p];
}
static NSDictionary *SafeFields(id value,NSUInteger depth) {
    if(!ObjectDictionary(value) || depth>3)return @{};
    NSMutableDictionary *out=[TRDRegionFields(value) mutableCopy];
    for(NSString *key in @[@"network_sim_region"])if(value[key])out[key]=CountryText(value[key])?[value[key] uppercaseString]:@"unrecognized";
    id zone=value[@"timezone"];
    if([zone isKindOfClass:NSString.class] && [NSTimeZone.knownTimeZoneNames containsObject:zone])out[@"timezone"]=zone;
    for(NSString *key in Containers()) {
        id child=value[key];
        if(ObjectDictionary(child))out[key]=SafeFields(child,depth+1);
        else if([child isKindOfClass:NSArray.class]) {
            NSMutableArray *items=[NSMutableArray new];NSUInteger count=0;
            for(id item in child){if(count++>=8)break;[items addObject:SafeFields(item,depth+1)];}out[key]=items;
        }
    }
    return out;
}
NSDictionary *TRPHeaderSummary(id headers) {
    if(!ObjectDictionary(headers))return @{@"dictionary":@NO,@"entries":@0};
    NSDictionary *known=TRDRegionFields(headers);
    return @{@"dictionary":@YES,@"entries":@(MIN([headers count],10000UL)),@"known_fields":known,
        @"unexported_entries":@(MIN([headers count]-known.count,10000UL))};
}
static void RememberKeys(id headers) {
    if(!ObjectDictionary(headers))return;
    NSUInteger n=0;
    @synchronized(Rows()) {
        for(id key in headers) {
            if(n++>=128 || HeaderKeys().count>=128)break;
            if([key isKindOfClass:NSString.class] && [key length]<=128)[HeaderKeys() addObject:[key lowercaseString]];
        }
    }
}
NSDictionary *TRPRequestHeaders(id headers) {
    NSUInteger matched=0,scanned=0,total=0;
    @synchronized(Rows()) {
        total=HeaderKeys().count;
        if(ObjectDictionary(headers))for(id key in headers) {
            if(scanned++>=512)break;
            if([key isKindOfClass:NSString.class] && [HeaderKeys() containsObject:[key lowercaseString]])matched++;
        }
    }
    return @{@"observed_pns_key_count":@(total),@"matching_key_count":@(matched),@"headers":TRPHeaderSummary(headers)};
}
static NSMutableDictionary *Row(NSString *key) {
    NSMutableDictionary *r=Rows()[key];
    if(!r){r=[@{@"status":@"not_attempted",@"calls":@0,@"applied":@0} mutableCopy];Rows()[key]=r;}return r;
}
static void Note(NSMutableDictionary *row,NSDictionary *event,BOOL applied) {
    @synchronized(Rows()) {
        row[@"calls"]=@([row[@"calls"] unsignedLongLongValue]+1);
        if(applied){
            row[@"applied"]=@([row[@"applied"] unsignedLongLongValue]+1);
            row[@"last_rewrite"]=event;row[@"last_rewrite_window"]=@(generation);
        }
        row[@"last"]=event;row[@"window"]=@(generation);
    }
}
static BOOL HasType(Method m,BOOL ret,unsigned int arg,const char *expected) {
    char *type=ret?method_copyReturnType(m):method_copyArgumentType(m,arg);
    BOOL valid=type && strcmp(type,expected)==0;free(type);return valid;
}
// Shapes: provider v(@,@,@,@?), builder @(q), header getter @()/@(@), response v(@).
static BOOL Install(Class cls,SEL sel,NSString *shape) {
    if(!cls)return NO;
    NSString *key=[NSString stringWithFormat:@"%s.%s",class_getName(cls),sel_getName(sel)];
    @synchronized(Rows()) {
        NSMutableDictionary *row=Row(key);if([row[@"status"] isEqual:@"installed"])return YES;
        Method m=class_getInstanceMethod(cls,sel);BOOL provider=[shape isEqual:@"provider"],builder=[shape isEqual:@"builder"],response=[shape isEqual:@"response"],arg=[shape isEqual:@"headers_arg"];
        unsigned int count=provider?6:((builder||response||arg)?3:2);
        BOOL valid=m && method_getNumberOfArguments(m)==count && HasType(m,YES,0,(provider||response)?"v":"@");
        if(valid && provider)valid=HasType(m,NO,2,"@")&&HasType(m,NO,3,"@")&&HasType(m,NO,4,"@")&&HasType(m,NO,5,"@?");
        if(valid && builder)valid=HasType(m,NO,2,@encode(NSInteger));
        if(valid && (response||arg))valid=HasType(m,NO,2,"@");
        if(!valid){row[@"status"]=m?@"unsupported_abi":@"missing";return NO;}
        IMP original=method_getImplementation(m),wrapper;
        if(provider)wrapper=imp_implementationWithBlock(^(id object,id path,id query,id params,id completion){
            BOOL allowed=TRPAllowedPath(path);id q=query,p=params;
            @try {
                if(allowed){q=TRPNormalizeFields(query);p=TRPNormalizeFields(params);}
                Note(row,@{@"path_allowed":@(allowed),@"query_before":allowed?SafeFields(query,0):@{},
                    @"body_before":allowed?SafeFields(params,0):@{},@"query_after":allowed?SafeFields(q,0):@{},
                    @"body_after":allowed?SafeFields(p,0):@{},@"body_dictionary":@(ObjectDictionary(params))},q!=query||p!=params);
            }@catch(__unused NSException *e){q=query;p=params;}
            // Original completion object and callback lifetime are untouched.
            ((void(*)(id,SEL,id,id,id,id))original)(object,sel,path,q,p,completion);
        });
        else if(builder)wrapper=imp_implementationWithBlock(^id(id object,NSInteger scene){
            id value;TREBeginScope();
            @try{value=((id(*)(id,SEL,NSInteger))original)(object,sel,scene);}@finally{TREEndScope();}
            @try{Note(row,@{@"fields":SafeFields(value,0),@"dictionary":@(ObjectDictionary(value))},NO);}@catch(__unused NSException *e){}
            // Driver may build auxiliary compliance modules rather than the final body.
            // Mutations are confined to the verified network-provider boundary.
            return value;
        });
        else if(response)wrapper=imp_implementationWithBlock(^(id object,id value){
            @try{
                id data=ObjectDictionary(value)?value[@"data"]:nil;
                id headers=ObjectDictionary(data)?data[@"region_header"]:nil;
                if(!headers && ObjectDictionary(value))headers=value[@"region_header"];
                RememberKeys(headers);Note(row,@{@"region_headers":TRPHeaderSummary(headers)},NO);
            }@catch(__unused NSException *e){}
            ((void(*)(id,SEL,id))original)(object,sel,value);
        });
        else {
            void(^inspect)(id)=^(id value){@try{RememberKeys(value);Note(row,TRPHeaderSummary(value),NO);}@catch(__unused NSException *e){}};
            if(arg)wrapper=imp_implementationWithBlock(^id(id object,id keys){id result=((id(*)(id,SEL,id))original)(object,sel,keys);inspect(result);return result;});
            else wrapper=imp_implementationWithBlock(^id(id object){id result=((id(*)(id,SEL))original)(object,sel);inspect(result);return result;});
        }
        if(!class_addMethod(cls,sel,wrapper,method_getTypeEncoding(m)))method_setImplementation(class_getInstanceMethod(cls,sel),wrapper);
        row[@"status"]=@"installed";return YES;
    }
}
void TRPInstall(void) {
    for(NSString *name in @[@"postWithPath:query:params:completion:",@"getWithPath:query:params:completion:"])
        Install(NSClassFromString(@"TikTokRegionNetworkProvider"),NSSelectorFromString(name),@"provider");
    Class driver=NSClassFromString(@"_TtC12PNSRegionSDK25PNSRegionComplianceDriver");
    Install(driver,NSSelectorFromString(@"buildRequestFieldsWithScene:"),@"builder");
    Install(driver,NSSelectorFromString(@"handleResponseWithResponse:"),@"response");
    Install(NSClassFromString(@"_TtC12PNSRegionSDK20PNSRegionServiceImpl"),NSSelectorFromString(@"getTTNetHeaders"),@"headers");
    Install(NSClassFromString(@"_TtC12PNSRegionSDK25PNSPrivacyDataServiceImpl"),NSSelectorFromString(@"getHeadersWithKeys:"),@"headers_arg");
}
void TRPBeginWindow(void){@synchronized(Rows()){generation++;}}
NSDictionary *TRPSnapshot(void) {
    NSMutableArray *out=[NSMutableArray new];
    @synchronized(Rows()) {
        for(NSString *key in [[Rows() allKeys] sortedArrayUsingSelector:@selector(compare:)]){
            NSMutableDictionary *r=[Rows()[key] mutableCopy];r[@"method"]=key;[out addObject:r];
        }
        return @{@"hooks":out,@"window":@(generation),@"observed_header_key_count":@(HeaderKeys().count),
            @"server_header_values_modified":@NO,@"forced_refresh":@NO,@"counts_are_method_calls":@YES};
    }
}
#ifdef TAP_TESTING
BOOL TRPTestProvider(Class cls,SEL sel){return Install(cls,sel,@"provider");}
BOOL TRPTestBuilder(Class cls,SEL sel){return Install(cls,sel,@"builder");}
BOOL TRPTestHeaders(Class cls,SEL sel,BOOL arg){return Install(cls,sel,arg?@"headers_arg":@"headers");}
BOOL TRPTestResponse(Class cls,SEL sel){return Install(cls,sel,@"response");}
#endif
