#import "RegionProfile.h"
static NSString *const CountryKey=@"TRCarrierRegion.country.v1";
NSArray<NSDictionary<NSString *,NSString *> *> *TRFProfiles(void) {
    static NSArray *profiles;static dispatch_once_t once;
    dispatch_once(&once,^{profiles=@[
        @{@"country":@"CA",@"name":@"Канада",@"mcc":@"302",@"mnc":@"720",@"carrier":@"Rogers",@"timezone":@"America/Toronto"},
        @{@"country":@"FR",@"name":@"Франция",@"mcc":@"208",@"mnc":@"01",@"carrier":@"Orange",@"timezone":@"Europe/Paris"},
        @{@"country":@"DE",@"name":@"Германия",@"mcc":@"262",@"mnc":@"01",@"carrier":@"Telekom",@"timezone":@"Europe/Berlin"},
        @{@"country":@"GB",@"name":@"Великобритания",@"mcc":@"234",@"mnc":@"15",@"carrier":@"Vodafone",@"timezone":@"Europe/London"},
        @{@"country":@"US",@"name":@"США",@"mcc":@"310",@"mnc":@"260",@"carrier":@"T-Mobile",@"timezone":@"America/New_York"},
        @{@"country":@"KZ",@"name":@"Казахстан",@"mcc":@"401",@"mnc":@"01",@"carrier":@"Beeline",@"timezone":@"Asia/Almaty"}
    ];});return profiles;
}
NSDictionary<NSString *,NSString *> *TRFProfile(NSString *code) {
    if(![code isKindOfClass:NSString.class])return nil;
    for(NSDictionary *p in TRFProfiles())if([p[@"country"] isEqual:code.uppercaseString])return p;
    return nil;
}
NSString *TRFReadSavedCountry(NSUserDefaults *store,NSString *fallback) {
    id saved=[store objectForKey:CountryKey];
    return (TRFProfile(saved)?:TRFProfile(fallback)?:TRFProfiles().firstObject)[@"country"];
}
BOOL TRFWriteCountry(NSUserDefaults *store,NSString *code) {
    NSDictionary *profile=TRFProfile(code);if(!profile)return NO;
    [store setObject:profile[@"country"] forKey:CountryKey];return YES;
}
NSString *TRFSavedCountry(void) {
    return TRFReadSavedCountry(NSUserDefaults.standardUserDefaults,[NSBundle.mainBundle objectForInfoDictionaryKey:@"TTCarrierRegionProfile"]);
}
BOOL TRFSaveCountry(NSString *code){return TRFWriteCountry(NSUserDefaults.standardUserDefaults,code);}
#ifdef TAP_TESTING
static NSDictionary *testProfile;
void TRFTestCountry(NSString *code){testProfile=TRFProfile(code);}
#endif
NSDictionary<NSString *,NSString *> *TRFCurrent(void) {
#ifdef TAP_TESTING
    if(testProfile)return testProfile;
#endif
    // Freeze the entire profile together for this process. Saving preferences
    // cannot mix old captured getters with a new PNS/locale/operator profile.
    static NSDictionary *profile;static dispatch_once_t once;
    dispatch_once(&once,^{profile=TRFProfile(TRFSavedCountry());});return profile;
}
NSString *TRFCountry(void){return TRFCurrent()[@"country"];}
NSString *TRFOperator(void){return [TRFCurrent()[@"mcc"] stringByAppendingString:TRFCurrent()[@"mnc"]];}
