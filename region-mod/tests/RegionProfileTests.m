#import "RegionProfile.h"
#import "RegionCompatibility.h"
#import "RegionSources.h"
#import "RegionSignals.h"
#import "RegionEnvironment.h"
#import "RegionPNS.h"
#include <assert.h>
@interface ProfileFixture:NSObject
- (id)locale;
- (id)zone;
- (id)carrier:(NSInteger)type;
@end
@implementation ProfileFixture
- (id)locale{return @"ru_RU";}
- (id)zone{return [NSTimeZone timeZoneWithName:@"Europe/Moscow"];}
- (id)carrier:(NSInteger)type{return @"original";}
@end
int main(void){@autoreleasepool {
    NSString *suite=[@"tiktok-mod-profile-test." stringByAppendingString:NSUUID.UUID.UUIDString];
    NSUserDefaults *store=[[NSUserDefaults alloc] initWithSuiteName:suite];
    // Upgrade from 0.3.9, including OFF: country selection must not reset enable.
    [store setBool:NO forKey:@"TRCarrierRegion.enabled.v2"];
    assert([TRFReadSavedCountry(store,nil) isEqual:@"CA"]);
    assert(TRFWriteCountry(store,@"fr"));assert([TRFReadSavedCountry(store,@"CA") isEqual:@"FR"]);
    assert(![store boolForKey:@"TRCarrierRegion.enabled.v2"]);
    assert(!TRFWriteCountry(store,@"RU") && !TRFWriteCountry(store,(id)@42));
    assert([TRFReadSavedCountry(store,@"CA") isEqual:@"FR"]);
    NSUserDefaults *reopened=[[NSUserDefaults alloc] initWithSuiteName:suite];
    assert([TRFReadSavedCountry(reopened,@"CA") isEqual:@"FR"]);
    [store setObject:@42 forKey:@"TRCarrierRegion.country.v1"];
    assert([TRFReadSavedCountry(store,@"GB") isEqual:@"GB"]);
    assert([TRFReadSavedCountry(store,@"unknown") isEqual:@"CA"]);
    NSString *active=TRFCountry();TRFWriteCountry(store,@"DE");assert([TRFCountry() isEqual:active]);
    [store removePersistentDomainForName:suite];

    TRCTestEnabled(YES);
    assert(TRETestGetter(ProfileFixture.class,@selector(locale),NO,NO));
    assert(TRETestGetter(ProfileFixture.class,@selector(zone),YES,NO));
    assert(TRETestCarrier(ProfileFixture.class,@selector(carrier:),NO));
    ProfileFixture *fixture=[ProfileFixture new];
    NSDate *winter=[NSDate dateWithTimeIntervalSince1970:1768435200],*summer=[NSDate dateWithTimeIntervalSince1970:1784073600];
    NSDictionary *winterOffsets=@{@"CA":@-18000,@"US":@-18000,@"FR":@3600,@"DE":@3600,@"GB":@0,@"KZ":@18000};
    NSDictionary *summerOffsets=@{@"CA":@-14400,@"US":@-14400,@"FR":@7200,@"DE":@7200,@"GB":@3600,@"KZ":@18000};
    for(NSDictionary *profile in TRFProfiles()) {
        NSString *country=profile[@"country"],*operator=[profile[@"mcc"] stringByAppendingString:profile[@"mnc"]];
        TRFTestCountry(country);
        assert([TRFCountry() isEqual:country] && [TRFOperator() isEqual:operator]);
        assert([NSTimeZone timeZoneWithName:profile[@"timezone"]]);
        NSDictionary *input=@{@"region":@"RU",@"carrier_region":@"RU",@"account_region":@"RU",@"mcc_mnc":@"25001",@"locale":@"ru_RU",@"timezone_name":@"Europe/Moscow",@"unknown":@"keep"};
        for(NSDictionary *out in @[TRSNormalize(input,NO),TRPNormalizeFields(input)]) {
            for(NSString *key in @[@"region",@"carrier_region",@"account_region"])assert([out[key] isEqual:country]);
            assert([out[@"mcc_mnc"] isEqual:operator]);assert([out[@"locale"] isEqual:[@"ru_" stringByAppendingString:country]]);
            assert([out[@"timezone_name"] isEqual:profile[@"timezone"]] && out[@"unknown"]==input[@"unknown"]);
        }
        assert([TRSNormalize(@{},YES)[@"current_region"] isEqual:country]);
        assert([TRGFeatureValue(@"f_global_carrier_region_v2",@"250") isEqual:profile[@"mcc"]]);
        assert([TRGFeatureValue(@"f_global_sys_region",@"RU") isEqual:country]);
        assert([fixture.locale isEqual:[@"ru_" stringByAppendingString:country]]);
        assert([[fixture.zone name] isEqual:profile[@"timezone"]]);
        assert([[fixture carrier:1] isEqual:profile[@"carrier"]]);
        assert([[fixture carrier:2] isEqual:country.lowercaseString]);
        assert([[fixture carrier:3] isEqual:profile[@"mcc"]] && [[fixture carrier:4] isEqual:profile[@"mnc"]]);
        assert([TRGTimeValues(winter)[@"timezone_offset"] isEqual:winterOffsets[country]]);
        assert([TRGTimeValues(summer)[@"timezone_offset"] isEqual:summerOffsets[country]]);
        TRCTestEnabled(NO);assert(TRSNormalize(input,NO)==input && TRPNormalizeFields(input)==input);
        assert([fixture.locale isEqual:@"ru_RU"] && [[fixture carrier:1] isEqual:@"original"]);TRCTestEnabled(YES);
    }
    // Switching back must not retain the previous profile in common/PNS maps.
    TRFTestCountry(@"CA");assert([TRSNormalize(@{@"region":@"RU"},NO)[@"region"] isEqual:@"CA"]);
    assert([TRPNormalizeFields(@{@"mcc_mnc":@"25001"})[@"mcc_mnc"] isEqual:@"302720"]);
    puts("Profiles: six countries across PNS/common/features/environment, DST, OFF, preference upgrade/persistence and isolation passed");
}}
