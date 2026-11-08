#import "RegionPNS.h"
#import "RegionCompatibility.h"
#import "RegionEnvironment.h"
#include <assert.h>
@interface PNSParent:NSObject
@property(nonatomic,strong) id path,query,params,payload,received;
@property(nonatomic,copy) void(^completion)(id);
@property(nonatomic) NSUInteger count;
@property(nonatomic) NSInteger scene;
@property(nonatomic) BOOL throws;
- (void)post:(id)path query:(id)query params:(id)params completion:(void(^)(id))completion;
- (id)build:(NSInteger)scene;
- (id)headers;
- (id)headers:(id)keys;
- (void)response:(id)value;
- (id)wrong:(id)arg;
@end
@implementation PNSParent
- (void)post:(id)path query:(id)query params:(id)params completion:(void(^)(id))completion {
    self.count++;self.path=path;self.query=query;self.params=params;self.completion=completion;
}
- (id)build:(NSInteger)scene {self.scene=scene;assert(TRETestDepth()>0);if(self.throws)@throw [NSException exceptionWithName:@"fixture" reason:nil userInfo:nil];return self.payload;}
- (id)headers{return self.payload;}
- (id)headers:(id)keys {self.received=keys;return self.payload;}
- (void)response:(id)value{self.count++;self.received=value;}
- (id)wrong:(id)arg{return arg;}
@end
@interface PNSChild:PNSParent @end
@implementation PNSChild @end
int main(void){@autoreleasepool {
    TRCTestEnabled(YES);
    NSDictionary *input=@{@"carrier_region":@"RU",@"locale":@"ru_RU",@"timezone":@"Europe/Moscow",
        @"mcc_mnc":@"25001",@"device_id":@"private-device",@"timezone_offset":@10800,
        @"data":@{@"system_region":@"RU",@"account_token":@"private-token"},
        @"opaque":@{@"system_region":@"RU"}};
    id output=TRPNormalizeFields(input);
    assert([output[@"carrier_region"] isEqual:@"CA"] && [output[@"locale"] isEqual:@"ru_CA"]);
    assert([output[@"timezone"] isEqual:@"America/Toronto"] && [output[@"mcc_mnc"] isEqual:@"302720"]);
    assert([output[@"data"][@"system_region"] isEqual:@"CA"]);
    assert(output[@"data"][@"account_token"]==input[@"data"][@"account_token"]);
    assert(output[@"opaque"]==input[@"opaque"] && output[@"device_id"]==input[@"device_id"]);
    assert([input[@"carrier_region"] isEqual:@"RU"] && output[@"timezone_offset"]==input[@"timezone_offset"]);
    assert(TRPNormalizeFields(output)==output);
    NSMutableDictionary *mutable=[input mutableCopy];assert([TRPNormalizeFields(mutable) isKindOfClass:NSMutableDictionary.class]);
    NSDictionary *unknown=@{@"timezone":@3,@"system_region":@42,@"carrier_region":@"n/a",@"locale":@"private-token-value!",@"mcc_mnc":@"secret"};
    assert(TRPNormalizeFields(unknown)==unknown && TRPNormalizeFields(nil)==nil);
    TRCTestEnabled(NO);assert(TRPNormalizeFields(input)==input);TRCTestEnabled(YES);
    assert(TRPAllowedPath(@"/location/region/") && TRPAllowedPath(@"https://api-va.tiktokv.com/tiktok/pns/privacy_headers"));
    for(id path in @[@"https://evil.invalid/location/region/",@"https://tiktokv.com.evil.invalid/location/region",@"//api.tiktokv.com/location/region",@"/passport/region/change/submit/post/",@"/location/region/extra",@42])assert(!TRPAllowedPath(path));
    assert(TRPTestProvider(PNSChild.class,@selector(post:query:params:completion:)));
    assert(TRPTestProvider(PNSChild.class,@selector(post:query:params:completion:)));
    assert(!TRPTestProvider(PNSChild.class,@selector(wrong:)));
    PNSChild *child=[PNSChild new];PNSParent *parent=[PNSParent new];
    __block id delivered=nil;void(^callback)(id)=^(id value){delivered=value;};
    [child post:@"/location/region/" query:input params:input completion:callback];
    assert(child.count==1 && child.completion==callback && [child.params[@"carrier_region"] isEqual:@"CA"]);
    child.completion(@"later");assert([delivered isEqual:@"later"]);
    [parent post:@"/location/region/" query:input params:input completion:callback];assert(parent.params==input);
    [child post:@"/passport/app/login/" query:input params:input completion:nil];assert(child.params==input && child.completion==nil);
    TRCTestEnabled(NO);[child post:@"/location/region/" query:input params:input completion:nil];assert(child.params==input);TRCTestEnabled(YES);
    assert(TRPTestBuilder(PNSChild.class,@selector(build:)));
    assert(!TRPTestBuilder(PNSChild.class,@selector(wrong:)));
    child.payload=input;assert([child build:7]==input && child.scene==7 && TRETestDepth()==0);
    child.throws=YES;BOOL threw=NO;@try{[child build:8];}@catch(__unused NSException *e){threw=YES;}assert(threw && TRETestDepth()==0);child.throws=NO;
    assert(TRPTestHeaders(PNSChild.class,@selector(headers),NO));
    assert(TRPTestHeaders(PNSChild.class,@selector(headers:),YES));
    child.payload=@{@"x-opaque-region-context":@"SECRET_HEADER_VALUE",@"x-tt-store-region":@"CA"};
    assert(child.headers==child.payload);
    NSArray *keys=@[@"x-opaque-region-context"];assert([child headers:keys]==child.payload && child.received==keys);
    NSDictionary *summary=TRPHeaderSummary(child.payload);assert([summary[@"entries"] intValue]==2 && [summary[@"unexported_entries"] intValue]==1);
    assert([TRPRequestHeaders(@{@"X-OPAQUE-REGION-CONTEXT":@"any"})[@"matching_key_count"] intValue]==1);
    assert(TRPTestResponse(PNSChild.class,@selector(response:)));
    id response=@{@"data":@{@"region_header":child.payload},@"uid":@"SECRET_UID"};
    [child response:response];assert(child.received==response);
    NSData *json=[NSJSONSerialization dataWithJSONObject:TRPSnapshot() options:0 error:nil];assert(json);
    NSString *text=[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
    for(NSString *secret in @[@"SECRET",@"private-device",@"private-token",@"x-opaque-region-context"])
        assert(![text containsString:secret]);
    TRPBeginWindow();assert([TRPSnapshot()[@"window"] intValue]==1);
    puts("PNS tests passed: ABI, inherited methods, OFF, scope unwind, callback identity, path isolation, privacy");
}}
