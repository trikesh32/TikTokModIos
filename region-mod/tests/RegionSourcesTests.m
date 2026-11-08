#import "RegionSources.h"
#import "RegionSignals.h"
#import "RegionCompatibility.h"
#include <assert.h>
@interface SourceParent : NSObject
@property(nonatomic,strong) id payload;
@property(nonatomic) NSUInteger reads;
- (id)commonParams;
- (id)awemeSettings;
- (BOOL)scalar;
- (id)argument:(id)value;
- (id)getFeatureWithName:(id)name parameters:(id)parameters;
@property(nonatomic,strong) id seenParameters;
@end
@implementation SourceParent
- (id)commonParams {self.reads++;return self.payload;}
- (id)awemeSettings {self.reads++;return self.payload;}
- (BOOL)scalar {return YES;}
- (id)argument:(id)value {return value;}
- (id)getFeatureWithName:(id)name parameters:(id)parameters {
    self.reads++;self.seenParameters=parameters;
    if([name isEqual:@"throw"])@throw [NSException exceptionWithName:@"fixture" reason:nil userInfo:nil];
    return self.payload;
}
@end
@interface SourceChild : SourceParent @end
@implementation SourceChild @end
int main(void) {@autoreleasepool {
    NSDictionary *original=@{@"current_region":@"FR",@"sys_region":@"RU",@"account_region":@"RU",
        @"carrier_region":@"",@"mcc_mnc":@"",@"token":@"unchanged",
        @"birthday":@"unchanged",@"nested":@{@"region":@"RU"},@"age_gate":@YES};
    TRCTestEnabled(YES);id normalized=TRSNormalize(original,NO);
    assert(normalized!=original && [normalized[@"current_region"] isEqual:@"CA"]);
    assert([normalized[@"mcc_mnc"] isEqual:@"302720"] && [normalized[@"carrier_region"] isEqual:@"CA"]);
    for(NSString *key in @[@"token",@"birthday",@"nested",@"age_gate"])assert(normalized[key]==original[key]);
    assert([original[@"current_region"] isEqual:@"FR"] && [original[@"mcc_mnc"] isEqual:@""]);
    assert([normalized count]==original.count && TRSNormalize(normalized,NO)==normalized);
    NSDictionary *empty=@{};assert(TRSNormalize(empty,NO)==empty);
    NSDictionary *settings=TRSNormalize(empty,YES);assert(settings.count==2 && [settings[@"region_of_residence"] isEqual:@"CA"]);
    assert(TRSNormalize(nil,YES)==nil && [TRSNormalize(@"not a dictionary",NO) isEqual:@"not a dictionary"]);
    NSMutableDictionary *mutable=[original mutableCopy];id mutableResult=TRSNormalize(mutable,NO);
    assert([mutableResult isKindOfClass:NSMutableDictionary.class]);mutableResult[@"token"]=@"copy-only";
    assert([mutable[@"token"] isEqual:@"unchanged"]);
    assert(TRSTestInstall(SourceChild.class,@selector(commonParams),NO));
    assert(TRSTestInstall(SourceChild.class,@selector(commonParams),NO));
    assert(TRSTestInstall(SourceChild.class,@selector(awemeSettings),YES));
    assert(!TRSTestInstall(SourceChild.class,@selector(scalar),NO));
    assert(!TRSTestInstall(SourceChild.class,@selector(argument:),NO));
    SourceChild *child=[SourceChild new];SourceParent *parent=[SourceParent new];child.payload=original;parent.payload=original;
    id result=child.commonParams;assert([result[@"account_region"] isEqual:@"CA"] && child.reads==1);
    assert(parent.commonParams==original && parent.reads==1);
    assert([child.awemeSettings[@"region_of_residence"] isEqual:@"CA"]);
    TRCTestEnabled(NO);assert(child.commonParams==original && child.reads==3);
    assert(TRSNormalize(original,YES)==original);
    child.payload=nil;assert(child.commonParams==nil && child.reads==4);
    TRCTestEnabled(YES);
    assert([TRGFeatureValue(@"f_global_sys_region",@"RU") isEqual:@"CA"]);
    assert([TRGFeatureValue(@"f_global_timezone_name",@"Europe/Moscow") isEqual:@"America/Toronto"]);
    assert([TRGFeatureValue(@"f_global_locale",@"ru_RU") isEqual:@"ru_CA"]);
    assert([TRGFeatureValue(@"f_global_locale",@"zh_Hans_CN") isEqual:@"zh_Hans_CA"]);
    NSString *badLocale=@"ru_SECRET_SENTINEL";assert(TRGFeatureValue(@"f_global_locale",badLocale)==badLocale);
    assert([TRGFeatureValue(@"f_global_carrier_region_v2",@"250") isEqual:@"302"]);
    assert([TRGFeatureValue(@"f_global_carrier_region_v2",@"RU") isEqual:@"CA"]);
    assert([TRGFeatureValue(@"f_global_timezone",@10800) isEqual:@10800]);
    NSNumber *boolean=@YES;assert(TRGFeatureValue(@"f_global_timezone_offset",boolean)==boolean);
    id secret=@{@"token":@"SECRET_SENTINEL"};assert(TRGFeatureValue(@"unknown",secret)==secret);
    assert(TRGFeatureValue(@"f_global_sys_region",secret)==secret);
    assert(TRGFeatureValue(@"f_global_sys_region",nil)==nil);
    assert([TRGFeatureValue(@"f_global_timezone_offset",@"10800") isKindOfClass:NSString.class]);
    assert([TRGFeatureValue(@"f_global_timezone_offset",@10800) isKindOfClass:NSNumber.class]);
    NSDate *winter=[NSDate dateWithTimeIntervalSince1970:1768435200]; // 2026-01-15
    NSDate *summer=[NSDate dateWithTimeIntervalSince1970:1784073600]; // 2026-07-15
    assert([TRGTimeValues(winter)[@"timezone_offset"] integerValue]==-18000);
    assert([TRGTimeValues(summer)[@"timezone_offset"] integerValue]==-14400);
    NSDictionary *timeInput=@{@"timezone_name":@"Europe/Moscow",@"timezone_offset":@10800,@"locale":@"ru_RU",@"nested":secret};
    id timeResult=TRSNormalize(timeInput,NO);
    assert([timeResult[@"timezone_name"] isEqual:@"America/Toronto"] && timeResult[@"nested"]==secret);
    assert([timeInput[@"locale"] isEqual:@"ru_RU"]);
    assert(TRSNormalize(timeResult,NO)==timeResult);
    assert(!TRGTestInstall(SourceChild.class,@selector(argument:)));
    assert(TRGTestInstall(SourceChild.class,@selector(getFeatureWithName:parameters:)));
    assert(TRGTestInstall(SourceChild.class,@selector(getFeatureWithName:parameters:)));
    child.payload=@"RU";parent.payload=@"RU";
    assert([[child getFeatureWithName:@"f_global_sys_region" parameters:secret] isEqual:@"CA"]);
    assert(child.seenParameters==secret);
    assert([[parent getFeatureWithName:@"f_global_sys_region" parameters:secret] isEqual:@"RU"]);
    child.payload=@"SECRET_SENTINEL";
    assert([child getFeatureWithName:@"f_global_sys_region" parameters:secret]==child.payload);
    BOOL threw=NO;@try{[child getFeatureWithName:@"throw" parameters:nil];}@catch(NSException *e){threw=[e.name isEqual:@"fixture"];}
    assert(threw);
    NSString *json=[[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:TRGSnapshot() options:0 error:nil] encoding:NSUTF8StringEncoding];
    assert(![json containsString:@"SECRET_SENTINEL"] && ![json containsString:@"token"]);
    TRCTestEnabled(NO);child.payload=@"RU";
    assert([child getFeatureWithName:@"f_global_sys_region" parameters:nil]==child.payload);
    assert(TRSNormalize(timeInput,NO)==timeInput);
    assert([NSJSONSerialization isValidJSONObject:TRSSnapshot()]);
    puts("Aggressive sources: OFF/identity/nil, source and nested data isolation, immutable/mutable contracts, ABI rejection and inheritance passed");
}return 0;}
