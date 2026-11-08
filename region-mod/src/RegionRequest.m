#import "RegionRequest.h"
#import "RegionCompatibility.h"
#import "RegionObservation.h"
#import <objc/runtime.h>
#include <stdatomic.h>
#include <string.h>

static NSDictionary *Values(void) {
    static NSDictionary *values;static dispatch_once_t once;
    dispatch_once(&once,^{values=@{@"region":@"CA",@"current_region":@"CA",@"sys_region":@"CA",
        @"residence":@"CA",@"account_region":@"CA",@"op_region":@"CA",@"carrier_region":@"CA",
        @"mcc_mnc":@"302720",@"mccmnc":@"302720",@"user_region":@"CA",@"system_region":@"CA",
        @"carrier_region_v2":@"CA",@"sim_region":@"CA",@"store_region":@"CA"};});return values;
}
static NSArray *Required(void) {return @[@"current_region",@"sys_region",@"residence",@"account_region",@"op_region",@"carrier_region",@"mcc_mnc"];}
static BOOL SignedKey(id key) {
    if(![key isKindOfClass:NSString.class])return NO;
    return [@[@"x-argus",@"x-gorgon",@"x-ladon",@"x-khronos",@"_signature",@"x-bogus",@"x-gnarly",@"signature",@"sig"] containsObject:[key lowercaseString]];
}
static BOOL SignedDictionary(id dictionary) {
    if(!dictionary)return NO;
    if(![dictionary isKindOfClass:NSDictionary.class] || [dictionary count]>1024)return YES;
    for(id key in dictionary)if(SignedKey(key))return YES;
    return NO;
}
static id RewriteDictionary(id input,BOOL addRequired) {
    NSMutableDictionary *copy=input?[input mutableCopy]:[NSMutableDictionary new];
    for(id key in input) {
        // Only literal known parameter keys, not nested dictionaries or values.
        if([key isKindOfClass:NSString.class] && Values()[key])copy[key]=Values()[key];
    }
    if(addRequired)for(NSString *key in Required())copy[key]=Values()[key];
    return [copy copy];
}
static NSDictionary *Prepare(id url,id headers,id params,id method,id common,NSString **reason) {
    *reason=@"disabled";if(!TRCEnabled())return nil;
    *reason=@"method";if(![method isKindOfClass:NSString.class] || ![method isEqual:@"GET"])return nil;
    *reason=@"dictionary_type";
    if((params && ![params isKindOfClass:NSDictionary.class]) || (common && ![common isKindOfClass:NSDictionary.class]))return nil;
    NSString *raw=[url isKindOfClass:NSString.class]?url:([url isKindOfClass:NSURL.class]?[url absoluteString]:nil);
    *reason=@"url_type_or_size";if(!raw || raw.length>65536)return nil;
    NSURL *parsed=[NSURL URLWithString:raw];
    *reason=@"transport_or_authority";if(![parsed.scheme.lowercaseString isEqual:@"https"] || parsed.user || parsed.password || parsed.fragment)return nil;
    *reason=@"host";if(TRDRequestFields(parsed,nil).count==0)return nil;
    NSString *path=parsed.path;
    NSArray *segments=[path componentsSeparatedByString:@"/"];
    *reason=@"path";if([segments containsObject:@".."] || [segments containsObject:@"."])return nil;
    static NSRegularExpression *scope;static dispatch_once_t once;
    dispatch_once(&once,^{scope=[NSRegularExpression regularExpressionWithPattern:@"^/aweme/v[0-9]+/(feed/?$|aweme/(post|detail)/?$|user/profile/?$|(?:general/)?search(?:/|$))" options:0 error:nil];});
    if(![scope firstMatchInString:path options:0 range:NSMakeRange(0,path.length)])return nil;
    *reason=@"signature_or_dictionary_limit";
    if(SignedDictionary(headers)||SignedDictionary(params)||SignedDictionary(common))return nil;
    // Retain the byte spelling/order of unrelated URL fields; never rebuild tokens.
    NSRange separator=[raw rangeOfString:@"?"];NSString *rewrittenURL=raw;
    if(separator.location!=NSNotFound) {
        NSString *query=[raw substringFromIndex:separator.location+1];NSMutableArray *parts=[NSMutableArray new];
        NSArray *items=[query componentsSeparatedByString:@"&"];*reason=@"query_limit";if(items.count>1024)return nil;
        for(NSString *item in items) {
            NSRange equals=[item rangeOfString:@"="];NSString *encodedKey=equals.location==NSNotFound?item:[item substringToIndex:equals.location];
            NSString *key=encodedKey.stringByRemovingPercentEncoding;
            *reason=@"signature_query";if(SignedKey(key))return nil;
            NSString *value=key?Values()[key]:nil;
            [parts addObject:value?[encodedKey stringByAppendingFormat:@"=%@",value]:item];
        }
        rewrittenURL=[[raw substringToIndex:separator.location+1] stringByAppendingString:[parts componentsJoinedByString:@"&"]];
    }
    id newURL=[url isKindOfClass:NSURL.class]?[NSURL URLWithString:rewrittenURL]:rewrittenURL;
    *reason=@"url_result";if(!newURL)return nil;
    id newCommon=common?RewriteDictionary(common,YES):nil;
    id newParams=(params || !common)?RewriteDictionary(params,!common):nil;
    *reason=@"applied";
    return @{@"url":newURL,@"params":newParams?:NSNull.null,@"common":newCommon?:NSNull.null};
}
NSDictionary *TRQPrepare(id url,id headers,id params,id method,id common) {
    NSString *reason;return Prepare(url,headers,params,method,common,&reason);
}
// Active only during the synchronous original serializer call; nested unrelated
// serializers clear this context. No global URL rewriting or post-sign mutation.
static _Thread_local const char *activeEndpoint;
static NSString *Endpoint(id url) {
    NSURL *u=[url isKindOfClass:NSURL.class]?url:([url isKindOfClass:NSString.class]?[NSURL URLWithString:url]:nil);
    return u?[NSString stringWithFormat:@"%@://%@:%@%@",u.scheme.lowercaseString,u.host.lowercaseString,u.port?:@443,u.path]:nil;
}
static id CanonicalURL(id value) {
    if(!activeEndpoint || ![value isKindOfClass:NSString.class])return value;
    if(![Endpoint(value) isEqual:[NSString stringWithUTF8String:activeEndpoint]])return value;
    // Reuse all scope/signature/size guards on the returned merged URL.
    NSDictionary *checked=TRQPrepare(value,nil,nil,@"GET",nil);if(!checked)return value;
    NSString *raw=checked[@"url"];NSRange separator=[raw rangeOfString:@"?"];
    NSString *base=separator.location==NSNotFound?raw:[raw substringToIndex:separator.location];
    NSString *query=separator.location==NSNotFound?nil:[raw substringFromIndex:separator.location+1];
    NSMutableArray *items=[NSMutableArray new];NSMutableSet *seen=[NSMutableSet new];
    for(NSString *item in query?[query componentsSeparatedByString:@"&"]:@[]) {
        NSRange equal=[item rangeOfString:@"="];NSString *encoded=equal.location==NSNotFound?item:[item substringToIndex:equal.location];
        NSString *key=encoded.stringByRemovingPercentEncoding;
        if(key && Values()[key]) {if([seen containsObject:key])continue;[seen addObject:key];}
        [items addObject:item];
    }
    for(NSString *key in Required())if(![seen containsObject:key])[items addObject:[key stringByAppendingFormat:@"=%@",Values()[key]]];
    return [base stringByAppendingFormat:@"?%@",[items componentsJoinedByString:@"&"]];
}
@interface TRQHook : NSObject {
@public atomic_uint_fast64_t calls;atomic_uint_fast64_t applied;
}
@property(nonatomic,copy) NSString *status;
@property(nonatomic,strong) NSMutableDictionary *reasons;
@end
@implementation TRQHook
- (instancetype)init {if((self=[super init])){atomic_init(&calls,0);atomic_init(&applied,0);_reasons=[NSMutableDictionary new];}return self;}
@end
static NSMutableDictionary *Hooks(void) {static NSMutableDictionary *hooks;static dispatch_once_t once;dispatch_once(&once,^{hooks=[NSMutableDictionary new];});return hooks;}
static void Reason(TRQHook *hook,NSString *reason,id url) {
    NSString *category=TRDRequestFields(url,nil)[@"category"]?:@"unclassified";
    NSString *key=[category stringByAppendingFormat:@":%@",reason];
    @synchronized(hook) {hook.reasons[key]=@([hook.reasons[key] unsignedLongLongValue]+1);}
}
static BOOL Matches(Method method,int index,const char *expected) {
    char *value=index<0?method_copyReturnType(method):method_copyArgumentType(method,(unsigned)index);
    BOOL ok=value&&strcmp(value,expected)==0;free(value);return ok;
}
static BOOL Install(Class cls) {
    if(!cls)return NO;
    SEL sel=NSSelectorFromString(@"URLRequestWithURL:headerField:params:method:constructingBodyBlock:commonParams:bypassXWwwFormUrlencoded:");
    NSString *name=NSStringFromClass(cls);NSMutableDictionary *hooks=Hooks();
    @synchronized(hooks) {
        TRQHook *hook=hooks[name];if([hook.status isEqual:@"installed"])return YES;
        if(!hook){hook=[TRQHook new];hooks[name]=hook;}
        Method m=class_getInstanceMethod(cls,sel);
        BOOL valid=m&&method_getNumberOfArguments(m)==9&&Matches(m,-1,"@");
        for(int i=2;valid&&i<9;i++)valid=Matches(m,i,i==6?"@?":i==8?"B":"@");
        if(!valid){hook.status=m?@"unsupported_abi":@"missing";return NO;}
        IMP original=method_getImplementation(m);
        IMP replacement=imp_implementationWithBlock(^id(id object,id url,id headers,id params,id method,id block,id common,BOOL bypass){
            atomic_fetch_add_explicit(&hook->calls,1,memory_order_relaxed);
            NSDictionary *prepared=nil;NSString *reason=@"exception";
            @try {prepared=Prepare(url,headers,params,method,common,&reason);} @catch(__unused NSException *e) {reason=@"exception";}
            @try {Reason(hook,reason,url);} @catch(__unused NSException *e) {}
            id newURL=url,newParams=params,newCommon=common;
            if(prepared) {
                newURL=prepared[@"url"];newParams=prepared[@"params"]==NSNull.null?nil:prepared[@"params"];
                newCommon=prepared[@"common"]==NSNull.null?nil:prepared[@"common"];
                atomic_fetch_add_explicit(&hook->applied,1,memory_order_relaxed);
            }
            // Block is passed through untouched; never wrap or store it.
            NSString * __attribute__((objc_precise_lifetime)) endpoint=prepared?Endpoint(newURL):nil;
            const char *previous=activeEndpoint;activeEndpoint=endpoint.UTF8String;
            @try {
                return ((id(*)(id,SEL,id,id,id,id,id,id,BOOL))original)(object,sel,newURL,headers,newParams,method,block,newCommon,bypass);
            } @finally {activeEndpoint=previous;}
        });
        if(!class_addMethod(cls,sel,replacement,method_getTypeEncoding(m)))method_setImplementation(class_getInstanceMethod(cls,sel),replacement);
        hook.status=@"installed";return YES;
    }
}
static BOOL InstallAppend(Class cls) {
    if(!cls)return NO;
    SEL sel=NSSelectorFromString(@"URLString:appendCommonParams:");NSString *name=@"TTNetworkUtil.URLString:appendCommonParams:";
    @synchronized(Hooks()) {
        TRQHook *hook=Hooks()[name];if([hook.status isEqual:@"installed"])return YES;
        if(!hook){hook=[TRQHook new];Hooks()[name]=hook;}
        Method m=class_getInstanceMethod(cls,sel);
        if(!m||method_getNumberOfArguments(m)!=4||!Matches(m,-1,"@")||!Matches(m,2,"@")||!Matches(m,3,"@")) {
            hook.status=m?@"unsupported_abi":@"missing";return NO;
        }
        IMP original=method_getImplementation(m);
        IMP wrapper=imp_implementationWithBlock(^id(id object,id url,id params){
            id result=((id(*)(id,SEL,id,id))original)(object,sel,url,params);
            atomic_fetch_add_explicit(&hook->calls,1,memory_order_relaxed);
            if(!activeEndpoint)return result;
            @try {
                // Don't erase signature parameters even if the helper drops them.
                if(!SignedDictionary(params) && TRQPrepare(url,nil,nil,@"GET",nil)) {
                    id normalized=CanonicalURL(result);
                    if(normalized!=result && ![normalized isEqual:result])atomic_fetch_add_explicit(&hook->applied,1,memory_order_relaxed);
                    return normalized;
                }
            } @catch(__unused NSException *e) {}
            return result;
        });
        if(!class_addMethod(cls,sel,wrapper,method_getTypeEncoding(m)))method_setImplementation(class_getInstanceMethod(cls,sel),wrapper);
        hook.status=@"installed";return YES;
    }
}
void TRQInstall(void) {
    InstallAppend(object_getClass(NSClassFromString(@"TTNetworkUtil")));
    Install(NSClassFromString(@"TTHTTPRequestSerializerBaseChromium"));
}
NSDictionary *TRQSnapshot(void) {
    NSMutableArray *rows=[NSMutableArray new];
    @synchronized(Hooks()) {for(NSString *name in [[Hooks() allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        TRQHook *hook=Hooks()[name];NSDictionary *reasons;@synchronized(hook){reasons=[hook.reasons copy];}
        [rows addObject:@{@"class":name,@"status":hook.status,@"reasons":reasons,
            @"calls":@(atomic_load_explicit(&hook->calls,memory_order_relaxed)),@"applied":@(atomic_load_explicit(&hook->applied,memory_order_relaxed))}];
    }}
    return @{@"stage":@"serializer_input_and_common_append",@"hooks":rows};
}
#ifdef TAP_TESTING
BOOL TRQTestInstall(Class cls) {return Install(cls);}
BOOL TRQTestInstallAppend(Class cls) {return InstallAppend(cls);}
#endif
