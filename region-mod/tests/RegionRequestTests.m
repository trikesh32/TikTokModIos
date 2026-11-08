#import "RegionRequest.h"
#import "RegionCompatibility.h"
#include <assert.h>
#import <objc/runtime.h>

@interface AppendFixture : NSObject
+ (id)URLString:(id)url appendCommonParams:(id)params;
@end
@implementation AppendFixture
+ (id)URLString:(id)url appendCommonParams:(id)params {
    return [url stringByAppendingString:@"&current_region=RU&current_region=RU&sys_region=RU&opaque2=raw%2F+Keep"];
}
@end

@interface RequestFixture : NSObject
@property(nonatomic,strong) id seenURL,seenHeaders,seenParams,seenCommon,seenMethod;
@property(nonatomic,copy) void(^savedBlock)(id);
@property(nonatomic) BOOL bypass,shouldThrow;
@property(nonatomic) NSUInteger calls;
@property(nonatomic,strong) NSString *mergedURL,*otherThreadURL;
@property(nonatomic) BOOL threadCheck;
- (id)URLRequestWithURL:(id)url headerField:(id)headers params:(id)params method:(id)method constructingBodyBlock:(void(^)(id))block commonParams:(id)common bypassXWwwFormUrlencoded:(BOOL)bypass;
@end
@implementation RequestFixture
- (id)URLRequestWithURL:(id)url headerField:(id)headers params:(id)params method:(id)method constructingBodyBlock:(void(^)(id))block commonParams:(id)common bypassXWwwFormUrlencoded:(BOOL)bypass {
    self.calls++;self.seenURL=url;self.seenHeaders=headers;self.seenParams=params;self.seenMethod=method;self.seenCommon=common;self.savedBlock=block;self.bypass=bypass;
    if(self.shouldThrow)@throw [NSException exceptionWithName:@"original" reason:nil userInfo:nil];
    self.mergedURL=[AppendFixture URLString:url appendCommonParams:common];
    if(self.threadCheck) {
        dispatch_semaphore_t done=dispatch_semaphore_create(0);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT,0),^{self.otherThreadURL=[AppendFixture URLString:url appendCommonParams:common];dispatch_semaphore_signal(done);});
        assert(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);
    }
    return self;
}
@end
@interface RequestChild : RequestFixture @end
@implementation RequestChild @end
@interface WrongRequest : NSObject
- (id)URLRequestWithURL:(id)u headerField:(id)h params:(id)p method:(id)m constructingBodyBlock:(id)b commonParams:(id)c bypassXWwwFormUrlencoded:(NSInteger)v;
@end
@implementation WrongRequest
- (id)URLRequestWithURL:(id)u headerField:(id)h params:(id)p method:(id)m constructingBodyBlock:(id)b commonParams:(id)c bypassXWwwFormUrlencoded:(NSInteger)v {return nil;}
@end
int main(void) { @autoreleasepool {
    TRCTestEnabled(YES);
    NSString *url=@"https://api.tiktokv.com/aweme/v1/feed/?opaque=a%2fb+Z&%63urrent_region=RU&current_region=RU&empty=&flag";
    NSDictionary *headers=@{@"Cookie":@"unchanged"},*params=@{@"cursor":@123,@"current_region":@"RU"};
    NSDictionary *common=@{@"sys_region":@"RU",@"account_region":@"RU",@"token":@"untouched",@"nested":@{@"region":@"RU"}};
    NSDictionary *r=TRQPrepare(url,headers,params,@"GET",common);
    assert([r[@"url"] isEqual:@"https://api.tiktokv.com/aweme/v1/feed/?opaque=a%2fb+Z&%63urrent_region=CA&current_region=CA&empty=&flag"]);
    assert([r[@"common"][@"sys_region"] isEqual:@"CA"] && [r[@"common"][@"mcc_mnc"] isEqual:@"302720"]);
    assert([r[@"params"][@"current_region"] isEqual:@"CA"] && r[@"params"][@"cursor"]==params[@"cursor"]);
    assert(r[@"common"][@"token"]==common[@"token"] && r[@"common"][@"nested"]==common[@"nested"]);
    assert([common[@"sys_region"] isEqual:@"RU"] && [params[@"current_region"] isEqual:@"RU"]);
    assert(TRQPrepare(url,@{@"X-Gorgon":@"signed"},params,@"GET",common)==nil);
    assert(TRQPrepare([url stringByAppendingString:@"&%73ignature=exists"],nil,nil,@"GET",nil)==nil);
    assert(TRQPrepare(url,nil,@{@"_signature":@"exists"},@"GET",nil)==nil);
    for(NSString *rejected in @[@"https://api.tiktokv.com/passport/feed/",@"https://api.tiktokv.com/aweme/v1/login/",@"https://evil.tiktokv.com.evil/aweme/v1/feed/",@"http://api.tiktokv.com/aweme/v1/feed/",@"https://user@api.tiktokv.com/aweme/v1/feed/",@"https://api.tiktokv.com/aweme/v1/search/../passport/",@"https://api.tiktokv.com/aweme/v1/search/%2e%2e/passport/",@"https://api.tiktokv.com/aweme/v1/aweme/delete/"])
        assert(TRQPrepare(rejected,nil,nil,@"GET",nil)==nil);
    assert(TRQPrepare(url,nil,nil,@"POST",nil)==nil);
    assert(TRQPrepare(url,nil,@"not a dictionary",@"GET",nil)==nil);
    for(NSString *path in @[@"/aweme/v1/feed/",@"/aweme/v2/aweme/post/",@"/aweme/v1/user/profile/",@"/aweme/v1/general/search/single/",@"/aweme/v1/aweme/detail/"]) {
        NSDictionary *prepared=TRQPrepare([NSURL URLWithString:[@"https://api.tiktokv.com" stringByAppendingString:path]],nil,nil,@"GET",nil);
        assert(prepared && [prepared[@"url"] isKindOfClass:NSURL.class]);
        assert(prepared[@"common"]==NSNull.null && [prepared[@"params"][@"current_region"] isEqual:@"CA"]);
    }
    assert(TRQTestInstall(RequestChild.class) && TRQTestInstall(RequestChild.class));
    assert(TRQTestInstallAppend(object_getClass(AppendFixture.class)));
    assert(!TRQTestInstall(WrongRequest.class));
    RequestChild *child=[RequestChild new];RequestFixture *parent=[RequestFixture new];child.threadCheck=YES;
    __block NSUInteger completions=0;void(^block)(id)=^(id value){assert(value==child);completions++;};
    id result=[child URLRequestWithURL:url headerField:headers params:params method:@"GET" constructingBodyBlock:block commonParams:common bypassXWwwFormUrlencoded:YES];
    assert(result==child && child.calls==1 && child.bypass);
    assert(child.seenHeaders==headers && [child.seenCommon[@"current_region"] isEqual:@"CA"]);
    NSArray *items=[NSURLComponents componentsWithString:child.mergedURL].queryItems;
    NSUInteger countryCount=0,systemCount=0;
    for(NSURLQueryItem *item in items) {
        if([item.name isEqual:@"current_region"]){countryCount++;assert([item.value isEqual:@"CA"]);}
        if([item.name isEqual:@"sys_region"]){systemCount++;assert([item.value isEqual:@"CA"]);}
    }
    assert(countryCount==1 && systemCount==1);
    assert([child.mergedURL containsString:@"opaque2=raw%2F+Keep"] && [child.mergedURL containsString:@"opaque=a%2fb+Z"]);
    assert([child.otherThreadURL containsString:@"current_region=RU"]);
    child.savedBlock(child);assert(completions==1);
    [parent URLRequestWithURL:url headerField:headers params:params method:@"GET" constructingBodyBlock:nil commonParams:common bypassXWwwFormUrlencoded:NO];
    assert(parent.seenCommon==common && parent.seenParams==params);
    assert([parent.mergedURL containsString:@"current_region=RU"]); // No serializer context on parent.
    [child URLRequestWithURL:url headerField:@{@"X-Gorgon":@"signed"} params:params method:@"GET" constructingBodyBlock:nil commonParams:common bypassXWwwFormUrlencoded:NO];
    assert([child.mergedURL containsString:@"current_region=RU"]); // Signed requests do not activate context.
    TRCTestEnabled(NO);
    assert(TRQPrepare(url,headers,params,@"GET",common)==nil);
    [child URLRequestWithURL:url headerField:headers params:params method:@"GET" constructingBodyBlock:nil commonParams:common bypassXWwwFormUrlencoded:NO];
    assert(child.seenURL==url && child.seenParams==params && child.seenCommon==common && child.seenHeaders==headers && !child.bypass && child.calls==3);
    assert([child.mergedURL containsString:@"current_region=RU"]);
    child.shouldThrow=YES;BOOL threw=NO;
    @try {[child URLRequestWithURL:url headerField:nil params:nil method:@"GET" constructingBodyBlock:nil commonParams:nil bypassXWwwFormUrlencoded:NO];}
    @catch(NSException *e){threw=[e.name isEqual:@"original"];}
    assert(threw && child.calls==4);
    TRCTestEnabled(YES);child.shouldThrow=YES;
    @try {[child URLRequestWithURL:url headerField:nil params:nil method:@"GET" constructingBodyBlock:nil commonParams:nil bypassXWwwFormUrlencoded:NO];}
    @catch(NSException *e) {assert([e.name isEqual:@"original"]);}
    assert([[AppendFixture URLString:url appendCommonParams:nil] containsString:@"current_region=RU"]); // Finally restored context after throw.
    assert([NSJSONSerialization isValidJSONObject:TRQSnapshot()]);
    BOOL reasonsFound=NO;
    for(NSDictionary *row in TRQSnapshot()[@"hooks"])if([row[@"class"] isEqual:@"RequestChild"]) {
        assert([row[@"reasons"][@"feed:applied"] unsignedIntegerValue]==2);
        assert([row[@"reasons"][@"feed:signature_or_dictionary_limit"] unsignedIntegerValue]==1);
        assert([row[@"reasons"][@"feed:disabled"] unsignedIntegerValue]==2);
        reasonsFound=YES;
    }
    assert(reasonsFound);
    puts("Request region: late RU merge deduplicated, thread/exception scope restored, signature/OFF guards, raw URL and dictionary isolation, ABI and callback passthrough passed");
}return 0;}
