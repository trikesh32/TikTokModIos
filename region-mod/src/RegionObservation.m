#import "RegionObservation.h"
#ifdef TT_REGION_AGGRESSIVE
#import "RegionPNS.h"
#endif
#import <objc/runtime.h>
#include <stdatomic.h>
#include <string.h>

// Only fixed field names and bounded country/operator values survive extraction.
// Never retain URLs, requests, headers, cookies, bodies or account identifiers.
static NSDictionary *FieldKinds(void) {
    static NSDictionary *fields; static dispatch_once_t once;
    dispatch_once(&once,^{fields=@{
        @"region":@"country",@"current_region":@"country",@"carrier_region":@"country",
        @"carrier_region_v2":@"country",@"sys_region":@"country",@"system_region":@"country",
        @"store_region":@"country",@"reg_store_region":@"country",@"account_region":@"country",
        @"residence":@"country",@"sim_region":@"country",@"op_region":@"country",
        @"x-tt-store-region":@"country",@"store-region":@"country",@"user_region":@"country",
        @"x-tt-app-cdn-region":@"country",@"network_sim_region":@"country",
        @"mcc_mnc":@"operator",@"mccmnc":@"operator",
        @"timezone_name":@"zone",@"timezone_offset":@"offset",@"locale":@"locale",
        @"store-region-src":@"source",@"x-tt-store-region-src":@"source"};});
    return fields;
}
static NSString *Country(id value) {
    if (![value isKindOfClass:NSString.class] || [value length]!=2) return nil;
    NSString *upper=[value uppercaseString]; if (upper.length!=2) return nil;
    for (NSUInteger i=0;i<2;i++) { unichar c=[upper characterAtIndex:i]; if (c<'A'||c>'Z') return nil; }
    return [upper copy];
}
NSDictionary *TRDRegionFields(id dictionary) {
    if (![dictionary isKindOfClass:NSDictionary.class]) return @{};
    NSMutableDictionary *fields=[NSMutableDictionary new];
    // Bounded scan; do not stringify unknown object types or arbitrary values.
    NSUInteger count=0;
    for (id key in dictionary) {
        if (++count>512) break;
        if (![key isKindOfClass:NSString.class] || [key length]>40) continue;
        NSString *name=[key lowercaseString],*kind=FieldKinds()[name];
        if (!kind) continue;
        id raw=dictionary[key]; NSString *value=nil;
        if ([kind isEqual:@"country"]) value=Country(raw);
        else if([kind isEqual:@"zone"] && [raw isKindOfClass:NSString.class] && [NSTimeZone.knownTimeZoneNames containsObject:raw])value=[raw copy];
        else if([kind isEqual:@"source"] && [@[@"local",@"server",@"cache",@"account"] containsObject:raw?:@""])value=raw;
        else if([kind isEqual:@"offset"] && [raw isKindOfClass:NSString.class] && [raw length]<=7) {
            NSScanner *scanner=[NSScanner scannerWithString:raw];scanner.charactersToBeSkipped=nil;long long offset=0;
            if([scanner scanLongLong:&offset] && scanner.isAtEnd && offset>=-86400 && offset<=86400)value=[@(offset) stringValue];
        }
        else if([kind isEqual:@"locale"] && [raw isKindOfClass:NSString.class] && [raw length]<=32) {
            NSRegularExpression *regex=[NSRegularExpression regularExpressionWithPattern:@"^[A-Za-z]{2,3}([_-][A-Za-z]{2,4}){0,2}$" options:0 error:nil];
            if([regex firstMatchInString:raw options:0 range:NSMakeRange(0,[raw length])])value=[raw copy];
        }
        else if ([kind isEqual:@"operator"] && [raw isKindOfClass:NSString.class] && ([raw length]==5||[raw length]==6)) {
            BOOL digits=YES;
            for (NSUInteger i=0;i<[raw length];i++) { unichar c=[raw characterAtIndex:i]; if(c<'0'||c>'9') digits=NO; }
            if(digits) value=[raw copy];
        }
        fields[name]=value?:@"invalid_or_empty";
    }
    return fields;
}
NSDictionary *TRDRequestFields(id url,id headers) {
    NSURL *parsed=nil;
    if ([url isKindOfClass:NSURL.class]) parsed=url;
    else if ([url isKindOfClass:NSString.class] && [url length]<65536) parsed=[NSURL URLWithString:url];
    if (!parsed || parsed.absoluteString.length>65536 ||
        ![@[@"http",@"https"] containsObject:parsed.scheme.lowercaseString]) return @{};
    NSString *host=parsed.host.lowercaseString; BOOL allowed=NO;
    for (NSString *suffix in @[@"tiktokv.com",@"tiktok.com",@"tiktokv.us",@"musical.ly"])
        if ([host isEqual:suffix] || [host hasSuffix:[@"." stringByAppendingString:suffix]]) allowed=YES;
    if (!allowed) return @{};
    // NSURL.path may remove the trailing slash from an endpoint.
    NSString *path=[parsed.path.lowercaseString stringByAppendingString:@"/"],*category=@"other";
    if ([path containsString:@"/feed/"]) category=@"feed";
    else if ([path containsString:@"/aweme/post/"] || [path containsString:@"/user/profile/"]) category=@"profile";
    else if ([path containsString:@"/search/"]) category=@"search";
    else if ([path containsString:@"/aweme/favorite/"]) category=@"likes";
    // AWEAwemeManager uses videos/detail for withStatus:YES, including IM fetches.
    else if ([path containsString:@"/multi/aweme/detail/"] || [path containsString:@"/tiktok/v1/videos/detail/"]) category=@"detail_multi";
    else if ([path containsString:@"/aweme/detail/"] || [path containsString:@"/aweme/detail_list/"] || [path containsString:@"/aweme/detaillist/"]) category=@"detail";
    else if ([path containsString:@"/im/"]) category=@"im";
    else if ([path hasSuffix:@"/location/region/"]) category=@"pns_region";
    else if ([path hasSuffix:@"/tiktok/pns/privacy_headers/"]) category=@"pns_privacy_headers";
    NSMutableDictionary *query=[NSMutableDictionary new];
    NSURLComponents *components=[NSURLComponents componentsWithURL:parsed resolvingAgainstBaseURL:NO];
    NSUInteger count=0;
    for (NSURLQueryItem *item in components.queryItems) {
        if (++count>512) break;
        if (item.name.length>40) continue;
        NSString *name=item.name.lowercaseString;
        if (FieldKinds()[name]) {
            // Extract immediately, do not keep arbitrary raw query values.
            NSDictionary *safe=TRDRegionFields(@{name:item.value?:@""});
            NSString *value=safe[name];
            if (query[name] && ![query[name] isEqual:value]) query[name]=@"conflicting_values";
            else query[name]=value;
        }
    }
    return @{@"category":category,@"query":query,@"headers":TRDRegionFields(headers)};
}
@interface TRDHook : NSObject {
@public atomic_uint_fast64_t calls;
@public NSUInteger samples; // Protected by Events() lock.
}
@property(nonatomic,copy) NSString *status;
@end
@implementation TRDHook
- (instancetype)init { if((self=[super init])) atomic_init(&calls,0); return self; }
@end
static NSMutableDictionary *Hooks(void) {
    static NSMutableDictionary *hooks; static dispatch_once_t once;
    dispatch_once(&once,^{hooks=[NSMutableDictionary new];}); return hooks;
}
static NSMutableArray *Events(void) {
    static NSMutableArray *events; static dispatch_once_t once;
    dispatch_once(&once,^{events=[NSMutableArray new];}); return events;
}
static NSUInteger dropped,windowNumber;
static NSString *windowPhase=@"startup";
static NSTimeInterval windowStart;
static void Record(NSString *source,NSDictionary *fields) {
    NSDictionary *event=@{@"source":source,@"fields":fields};
    NSMutableArray *events=Events();
    @synchronized(events) {
        for (NSMutableDictionary *entry in events) {
            if ([entry[@"event"] isEqual:event]) {entry[@"count"]=@([entry[@"count"] unsignedIntegerValue]+1);return;}
        }
        if(events.count>=64) {dropped++;return;}
        [events addObject:[@{@"event":event,@"count":@1} mutableCopy]];
    }
}
static BOOL Type(Method method,const char *type) {
    if(!method || method_getNumberOfArguments(method)!=2) return NO;
    char *ret=method_copyReturnType(method); BOOL valid=ret && strcmp(ret,type)==0;free(ret);return valid;
}
static id Get(id object,NSString *name) {
    if (!object) return nil;
    SEL selector=NSSelectorFromString(name);Method method=class_getInstanceMethod(object_getClass(object),selector);
    if(!Type(method,"@")) return nil;
    return ((id(*)(id,SEL))method_getImplementation(method))(object,selector);
}
// Invoke only exact scalar ABIs; never reinterpret an object or a block as an integer.
static NSNumber *Number(id object,NSString *name) {
    if(!object)return nil;
    SEL selector=NSSelectorFromString(name);
    Method method=class_getInstanceMethod(object_getClass(object),selector);
    if(!method || method_getNumberOfArguments(method)!=2)return nil;
    char *type=method_copyReturnType(method);if(!type)return nil;
    IMP imp=method_getImplementation(method);NSNumber *value=nil;
#define READ_NUMBER(encoding,ctype) if(strcmp(type,encoding)==0)value=@(((ctype(*)(id,SEL))imp)(object,selector))
    if(strcmp(type,"@")==0) {
        id result=((id(*)(id,SEL))imp)(object,selector);
        if([result isKindOfClass:NSNumber.class])value=result;
    }
    else READ_NUMBER("q",long long);
    else READ_NUMBER("Q",unsigned long long);
    else READ_NUMBER("i",int);
    else READ_NUMBER("I",unsigned int);
    else READ_NUMBER("B",BOOL);
    else READ_NUMBER("c",signed char);
    else READ_NUMBER("C",unsigned char);
#undef READ_NUMBER
    free(type);
    return value && value.doubleValue>=-1000000 && value.doubleValue<=1000000?value:nil;
}
NSDictionary *TRDModelFields(id object,NSString *family,NSString *field,id result) {
    NSMutableDictionary *fields=[@{@"family":family,@"field":field,@"present":@(result!=nil)} mutableCopy];
    if([result isKindOfClass:NSArray.class])fields[@"item_count"]=@(MIN([result count],1000000UL));
    // statusCode is NSNumber in AWEBaseApiModel; filteredReason is NSUInteger.
    // Both are runtime ABI checked, and no status text is retained.
    for(NSString *key in @[@"statusCode",@"invalidItemCount",@"isHidingInvalidItem",@"hasMore",@"filteredReason"]) {
        NSNumber *value=Number(object,key);if(value)fields[key]=value;
    }
    if([family isEqual:@"detail_multi"] && [field isEqual:@"awemeStatus"] && [result isKindOfClass:NSArray.class]) {
        NSMutableArray *histogram=[NSMutableArray new];NSUInteger sampled=0,unrecognized=0;
        Class statusClass=NSClassFromString(@"AWEAwemeStatus");
        for(id entry in result) {
            if(sampled>=128)break;sampled++;
            if(!statusClass || ![entry isKindOfClass:statusClass]){unrecognized++;continue;}
            NSNumber *status=Number(entry,@"status"),*filtered=Number(entry,@"isFiltered");
            if(!status || !filtered){unrecognized++;continue;}
            NSMutableDictionary *row=nil;
            for(NSMutableDictionary *candidate in histogram)
                if([candidate[@"status"] isEqual:status] && [candidate[@"isFiltered"] isEqual:filtered]){row=candidate;break;}
            if(!row){row=[@{@"status":status,@"isFiltered":filtered,@"count":@0} mutableCopy];[histogram addObject:row];}
            row[@"count"]=@([row[@"count"] unsignedIntegerValue]+1);
        }
        fields[@"item_statuses"]=histogram;fields[@"sampled_status_items"]=@(sampled);
        fields[@"unrecognized_status_items"]=@(unrecognized);fields[@"status_items_truncated"]=@([result count]>sampled);
    }
    return fields;
}
void TRDBeginWindow(NSString *phase) {
    if(![@[@"chat",@"likes",@"feed"] containsObject:phase])return;
    @synchronized(Hooks()) { @synchronized(Events()) {
        [Events() removeAllObjects];dropped=0;windowNumber++;windowPhase=[phase copy];
        windowStart=NSProcessInfo.processInfo.systemUptime;
        for(TRDHook *hook in Hooks().allValues)hook->samples=0;
    }}
}
static _Thread_local BOOL observing;
static BOOL Observe(Class cls,SEL selector,BOOL returnsObject,void(^observe)(id,id)) {
    if (!cls) return NO;
    NSString *key=[NSString stringWithFormat:@"%c[%s %s]",class_isMetaClass(cls)?'+':'-',class_getName(cls),sel_getName(selector)];
    NSMutableDictionary *hooks=Hooks();
    @synchronized(hooks) {
        TRDHook *hook=hooks[key];if([hook.status isEqual:@"installed"]) return YES;
        if(!hook) {hook=[TRDHook new];hooks[key]=hook;}
        Method method=class_getInstanceMethod(cls,selector);
        if (!Type(method,returnsObject?"@":"v")) {hook.status=method?@"unsupported_abi":@"missing";return NO;}
        IMP original=method_getImplementation(method);
        void(^inspect)(id,id)=^(id object,id result) {
            if(observing) return;
            atomic_fetch_add_explicit(&hook->calls,1,memory_order_relaxed);
            @synchronized(Events()) {
                if(hook->samples>=1000)return;
                hook->samples++;
                observing=YES;
                @try {observe(object,result);} @catch(__unused NSException *e) {}
                @finally {observing=NO;}
            }
        };
        IMP wrapper;
        if(returnsObject) wrapper=imp_implementationWithBlock(^id(id object) {
            id result=((id(*)(id,SEL))original)(object,selector);
            inspect(object,result);return result;
        });
        else wrapper=imp_implementationWithBlock(^(id object) {
            inspect(object,nil);((void(*)(id,SEL))original)(object,selector);
        });
        if(!class_addMethod(cls,selector,wrapper,method_getTypeEncoding(method)))
            method_setImplementation(class_getInstanceMethod(cls,selector),wrapper);
        hook.status=@"installed";return YES;
    }
}
static void CountryGetter(NSString *className,NSString *methodName,BOOL classMethod) {
    Class cls=NSClassFromString(className);if(classMethod) cls=object_getClass(cls);
    NSString *source=[className stringByAppendingFormat:@".%@",methodName];
    Observe(cls,NSSelectorFromString(methodName),YES,^(__unused id object,id result){
        NSMutableDictionary *fields=[@{@"country":Country(result)?:@"invalid_or_empty"} mutableCopy];
        if([className isEqual:@"TTKStoreRegionModel"]) {
            NSNumber *kind=Number(object,@"source");if(kind)fields[@"source_code"]=kind;
        }
        Record(source,fields);
    });
}
void TRDInstall(void) {
    CountryGetter(@"TIKTOKRegionManager",@"storeRegion",YES);
    CountryGetter(@"TTKStoreRegionService",@"storeRegion",NO);
    CountryGetter(@"TTKStoreRegionService",@"getStoreRegion",NO);
    CountryGetter(@"TTKStoreRegionModel",@"storeRegion",NO);
    CountryGetter(@"TTInstallIDManager",@"currentAppRegion",NO);
    Observe(NSClassFromString(@"_TtC12PNSRegionSDK20PNSRegionServiceImpl"),NSSelectorFromString(@"getTTNetHeaders"),YES,^(__unused id object,id result){
        Record(@"pns_region_headers",TRDRegionFields(result));
    });
    Observe(NSClassFromString(@"TTHttpTaskChromium"),NSSelectorFromString(@"resume"),NO,^(id object,__unused id result){
        id request=Get(object,@"request");
        NSDictionary *fields=TRDRequestFields(Get(request,@"URL"),Get(request,@"allHTTPHeaderFields"));
        if(fields.count) {
            NSMutableDictionary *details=[fields mutableCopy];id method=Get(request,@"HTTPMethod");
            details[@"method"]=[@[@"GET",@"POST",@"HEAD",@"PUT",@"DELETE",@"PATCH"] containsObject:method?:@""]?method:@"unknown";
#ifdef TT_REGION_AGGRESSIVE
            details[@"pns_headers"]=TRPRequestHeaders(Get(request,@"allHTTPHeaderFields"));
#endif
            Record(@"request_before_resume",details);
        }
    });
    for(NSString *name in @[@"TTHttpResponse",@"TTHttpResponseChromium"]) {
        Class cls=NSClassFromString(name); SEL selector=NSSelectorFromString(@"allHeaderFields");
        // An inherited getter is already covered by the parent observer.
        if (cls && class_getInstanceMethod(cls,selector)==class_getInstanceMethod(class_getSuperclass(cls),selector)) continue;
        Observe(cls,selector,YES,^(__unused id object,id result){
            NSDictionary *fields=TRDRequestFields(Get(object,@"URL"),result);
            // Response URL query isn't a server statement about region.
            if(fields.count) {
                NSMutableDictionary *details=[@{@"category":fields[@"category"],@"headers":fields[@"headers"]} mutableCopy];
                NSNumber *status=Number(object,@"statusCode");if(status)details[@"http_status"]=status;
                Record(@"response_headers_read",details);
            }
        });
    }
    // Observe model reads, not deserializers or async callbacks. Counts describe
    // getter observations (possibly cached), not unique network responses.
    for(NSArray *spec in @[
        @[@"AWEUserLikesResponseModel",@"likes",@"awemes"],
        @[@"AWEAwemeDetailResponse",@"detail",@"awemeDetail"],
        @[@"AWEAwemeMultiResponseModel",@"detail_multi",@"awemeList"],
        @[@"AWEAwemeMultiResponseModel",@"detail_multi",@"awemeStatus"]]) {
        NSString *family=spec[1],*field=spec[2];
        Observe(NSClassFromString(spec[0]),NSSelectorFromString(field),YES,^(id object,id result){
            Record(@"content_model_read",TRDModelFields(object,family,field,result));
        });
    }
}
NSDictionary *TRDSnapshot(void) {
    NSMutableArray *hooks=[NSMutableArray new],*events=[NSMutableArray new];NSUInteger overflow;
    @synchronized(Hooks()) {
        for(NSString *key in [[Hooks() allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
            TRDHook *hook=Hooks()[key];
            @synchronized(Events()) {
                [hooks addObject:@{@"method":key,@"status":hook.status,
                    @"calls":@(atomic_load_explicit(&hook->calls,memory_order_relaxed)),
                    @"samples_in_window":@(hook->samples),@"sample_limit_reached":@(hook->samples>=1000)}];
            }
        }
    }
    NSDictionary *window;
    @synchronized(Events()) {
        for(NSDictionary *event in Events()) [events addObject:[event copy]];overflow=dropped;
        window=@{@"number":@(windowNumber),@"phase":windowPhase,
            @"elapsed_ms":windowStart?@((NSProcessInfo.processInfo.systemUptime-windowStart)*1000):@0};
    }
    return @{@"observers":hooks,@"observations":events,@"overflow":@(overflow),@"sample_limit_per_hook":@1000,
        @"window":window,@"counts_are_getter_observations":@YES};
}
#ifdef TAP_TESTING
BOOL TRDTestObserve(Class cls,SEL selector,BOOL returnsObject) {
    return Observe(cls,selector,returnsObject,^(__unused id object,id result){Record(@"fixture",TRDRegionFields(result));});
}
#endif
