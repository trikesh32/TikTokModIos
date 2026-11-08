#import "RegionObservation.h"
#include <assert.h>

@interface ObservationFixture : NSObject
@property(nonatomic,strong) id payload;
@property(nonatomic) NSUInteger reads;
- (id)result;
- (void)resume;
- (BOOL)scalar;
- (id)argument:(id)value;
- (id (^)(void))callback;
- (id)throwing;
- (NSNumber *)statusCode;
- (NSUInteger)filteredReason;
- (NSUInteger)invalidItemCount;
- (BOOL)isHidingInvalidItem;
- (id)hasMore;
@end
@implementation ObservationFixture
- (id)result {self.reads++;return self.payload;}
- (void)resume {self.reads++;}
- (BOOL)scalar {return YES;}
- (id)argument:(id)value {return value;}
- (id (^)(void))callback {return ^id{return nil;};}
- (NSNumber *)statusCode {return @42;}
- (NSUInteger)filteredReason {return 17;}
- (NSUInteger)invalidItemCount {return 3;}
- (BOOL)isHidingInvalidItem {return YES;}
- (id)hasMore {return @"SECRET_SENTINEL";}
- (id)throwing {@throw [NSException exceptionWithName:@"fixture" reason:nil userInfo:nil];}
@end
@interface ObservationChild : ObservationFixture @end
@implementation ObservationChild @end


@interface AWEAwemeStatus : NSObject
@property(nonatomic) NSInteger status;
@property(nonatomic) BOOL isFiltered;
- (id)itemID;
- (id)statusText;
@end
@implementation AWEAwemeStatus
- (id)itemID {@throw [NSException exceptionWithName:@"must_not_read_id" reason:nil userInfo:nil];}
- (id)statusText {@throw [NSException exceptionWithName:@"must_not_read_text" reason:nil userInfo:nil];}
@end

int main(void) { @autoreleasepool {
    NSString *secret=@"SECRET_SENTINEL";
    NSDictionary *raw=@{@"X-TT-Store-Region":@"ru",@"mcc_mnc":@"302720",@"Cookie":secret,
        @"token":secret,@"device_id":secret,@"region":secret,@"user_region":@42};
    NSDictionary *safe=TRDRegionFields(raw);
    assert(safe.count==4 && [safe[@"x-tt-store-region"] isEqual:@"RU"]);
    assert([safe[@"mcc_mnc"] isEqual:@"302720"] && [safe[@"region"] isEqual:@"invalid_or_empty"]);
    assert(TRDRegionFields(@[secret]).count==0);
    NSDictionary *request=TRDRequestFields(@"https://api.tiktokv.com/aweme/v1/feed/?region=CA&carrier_region=ca&token=SECRET_SENTINEL&device_id=12345",raw);
    assert([request[@"category"] isEqual:@"feed"] && [request[@"query"] count]==2);
    assert(TRDRequestFields(@"https://api.tiktokv.com.evil.example/aweme/v1/feed/?region=CA",raw).count==0);
    assert(TRDRequestFields(@"https://tiktokv.com@evil.example/?region=CA",raw).count==0);
    assert(TRDRequestFields(@"file://api.tiktokv.com/a",raw).count==0);
    assert(TRDRequestFields(@"https://example.com/a",raw).count==0);
    assert([TRDRequestFields(@"https://api.tiktokv.us/aweme/v1/aweme/post/?region=CA&region=RU",nil)[@"query"][@"region"] isEqual:@"conflicting_values"]);
    assert([TRDRequestFields(@"https://api.tiktokv.com/aweme/v1/search/item/?region=CA",nil)[@"category"] isEqual:@"search"]);
    assert(TRDRequestFields(@"https://api.tiktokv.com/aweme/v1/feed/",nil).count==3);
    for(NSArray *item in @[@[@"/aweme/v1/aweme/favorite/",@"likes"],@[@"/aweme/v1/multi/aweme/detail/",@"detail_multi"],@[@"/tiktok/v1/videos/detail/",@"detail_multi"],@[@"/tiktok/v1/videos/detail",@"detail_multi"],@[@"/aweme/v1/aweme/detail/",@"detail"],@[@"/aweme/detail_list/",@"detail"],@[@"/tiktok/v1/im/test/",@"im"]]) {
        NSString *url=[@"https://api.tiktokv.com" stringByAppendingString:item[0]];
        assert([TRDRequestFields(url,nil)[@"category"] isEqual:item[1]]);
    }
    ObservationChild *child=[ObservationChild new]; ObservationFixture *parent=[ObservationFixture new];
    child.payload=raw;parent.payload=raw;
    assert(TRDTestObserve(ObservationChild.class,@selector(result),YES));
    assert(TRDTestObserve(ObservationChild.class,@selector(result),YES));
    assert(TRDTestObserve(ObservationChild.class,@selector(resume),NO));
    assert(!TRDTestObserve(ObservationChild.class,@selector(scalar),YES));
    assert(!TRDTestObserve(ObservationChild.class,@selector(argument:),YES));
    assert(!TRDTestObserve(ObservationChild.class,@selector(callback),YES));
    assert(!TRDTestObserve(ObservationChild.class,NSSelectorFromString(@"missing"),YES));
    assert(child.result==raw && child.reads==1);
    assert(parent.result==raw && parent.reads==1);
    child.payload=nil;assert(child.result==nil && child.reads==2);
    [child resume];assert(child.reads==3);
    assert(TRDTestObserve(ObservationChild.class,@selector(throwing),YES));
    BOOL threw=NO;@try {[child throwing];} @catch(NSException *e) {threw=[e.name isEqual:@"fixture"];}
    assert(threw);
    for(NSUInteger i=0;i<1100;i++) {
        child.payload=@{@"region":[NSString stringWithFormat:@"%c%c",(int)('A'+(i/26)%26),(int)('A'+i%26)]};
        assert(child.result==child.payload);
    }
    NSDictionary *snapshot=TRDSnapshot();
    assert([snapshot[@"observations"] count]==64 && [snapshot[@"overflow"] unsignedIntegerValue]>0);
    NSDictionary *model=TRDModelFields(child,@"likes",@"awemes",@[secret,secret]);
    assert([model[@"item_count"] integerValue]==2 && [model[@"statusCode"] integerValue]==42);
    assert([model[@"invalidItemCount"] integerValue]==3 && [model[@"isHidingInvalidItem"] boolValue]);
    assert(!model[@"hasMore"]); // Object-returning getter is read as an object; non-numbers are rejected.
    assert([TRDModelFields(child,@"detail",@"awemeDetail",nil)[@"filteredReason"] integerValue]==17);
    assert(![TRDModelFields(child,@"detail",@"awemeDetail",nil)[@"present"] boolValue]);
    AWEAwemeStatus *s1=[AWEAwemeStatus new];s1.status=7;s1.isFiltered=YES;
    AWEAwemeStatus *s2=[AWEAwemeStatus new];s2.status=0;s2.isFiltered=NO;
    NSDictionary *statuses=TRDModelFields(child,@"detail_multi",@"awemeStatus",@[s1,s1,s2,secret]);
    assert([statuses[@"item_statuses"] count]==2);
    assert([statuses[@"item_statuses"][0][@"count"] integerValue]==2);
    assert([statuses[@"unrecognized_status_items"] integerValue]==1);
    NSMutableArray *many=[NSMutableArray new];for(int i=0;i<200;i++)[many addObject:s1];
    assert([TRDModelFields(child,@"detail_multi",@"awemeStatus",many)[@"sampled_status_items"] integerValue]==128);
    assert([TRDModelFields(child,@"detail_multi",@"awemeStatus",many)[@"status_items_truncated"] boolValue]);
    NSDictionary *extra=TRDRegionFields(@{@"timezone_name":@"America/Toronto",@"timezone_offset":@"-18000",@"locale":@"ru_CA",@"store-region-src":@"local"});
    assert([extra[@"timezone_name"] isEqual:@"America/Toronto"] && [extra[@"timezone_offset"] isEqual:@"-18000"]);
    assert([TRDRegionFields(@{@"timezone_name":secret,@"store-region-src":secret,@"locale":secret})[@"locale"] isEqual:@"invalid_or_empty"]);
    TRDBeginWindow(secret);assert([TRDSnapshot()[@"observations"] count]==64);
    TRDBeginWindow(@"chat");assert([TRDSnapshot()[@"observations"] count]==0);
    child.payload=@{@"region":@"CA"};assert(child.result==child.payload);
    snapshot=TRDSnapshot();assert([snapshot[@"observations"] count]==1);
    assert([snapshot[@"window"][@"phase"] isEqual:@"chat"]);
    TRDBeginWindow(@"likes");assert([TRDSnapshot()[@"observations"] count]==0);
    NSData *data=[NSJSONSerialization dataWithJSONObject:@[snapshot,request,safe,model,statuses,extra] options:0 error:nil];
    NSString *json=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    assert(![json containsString:secret] && ![json containsString:@"device_id"] && ![json containsString:@"api.tiktok"]);
    assert(![json containsString:@"Cookie"] && ![json containsString:@"token"]);
    puts("Region observations: original result/void/nil/exception preserved, ABI/inheritance, URL scope, redaction and bounded aggregation passed");
}return 0;}
