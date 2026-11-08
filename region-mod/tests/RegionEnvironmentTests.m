#import "RegionEnvironment.h"
#import "RegionSources.h"
#import "RegionCompatibility.h"
#import <objc/runtime.h>
#include <assert.h>
@interface EnvironmentParent:NSObject
@property(nonatomic,strong) id payload;
@property(nonatomic) NSUInteger reads;
@property(nonatomic) NSInteger seenService;
@property(nonatomic) BOOL throws;
- (id)locale;
- (id)zone;
- (id)carrier:(NSInteger)type;
- (id)service:(NSInteger)service property:(NSInteger)type;
- (id)objectArgument:(id)value;
- (BOOL)scalar;
- (id)commonParams;
@end
@implementation EnvironmentParent
- (id)locale {self.reads++;if(self.throws)@throw [NSException exceptionWithName:@"test" reason:nil userInfo:nil];return self.payload;}
- (id)zone {return [self locale];}
- (id)carrier:(NSInteger)type {return [self locale];}
- (id)service:(NSInteger)service property:(NSInteger)type {self.seenService=service;return [self locale];}
- (id)objectArgument:(id)value{return value;}
- (BOOL)scalar{return YES;}
- (id)commonParams {
    if(self.throws)@throw [NSException exceptionWithName:@"test" reason:nil userInfo:nil];
    return @{@"zone_observed":NSTimeZone.systemTimeZone.name,@"country_observed":[NSLocale.currentLocale objectForKey:NSLocaleCountryCode]?:@""};
}
@end
@interface EnvironmentChild:EnvironmentParent @end
@implementation EnvironmentChild @end
int main(void){@autoreleasepool {
    TRCTestEnabled(YES);
    assert(TRETestGetter(EnvironmentChild.class,@selector(locale),NO,NO));
    assert(TRETestGetter(EnvironmentChild.class,@selector(locale),NO,NO));
    assert(!TRETestGetter(EnvironmentChild.class,@selector(scalar),NO,NO));
    assert(!TRETestGetter(EnvironmentChild.class,@selector(objectArgument:),NO,NO));
    EnvironmentChild *child=[EnvironmentChild new];EnvironmentParent *parent=[EnvironmentParent new];
    NSLocale *original=[[NSLocale alloc] initWithLocaleIdentifier:@"zh_Hans_CN"];
    child.payload=original;parent.payload=original;
    NSLocale *result=child.locale;
    assert([result isKindOfClass:NSLocale.class]);
    assert([[result objectForKey:NSLocaleCountryCode] isEqual:@"CA"]);
    assert([[result objectForKey:NSLocaleLanguageCode] isEqual:@"zh"]);
    assert([[result objectForKey:NSLocaleScriptCode] isEqual:@"Hans"]);
    assert(parent.locale==original && child.reads==1);
    child.payload=[[NSLocale alloc] initWithLocaleIdentifier:@"zh_TW"];
    assert([[[child locale] objectForKey:NSLocaleScriptCode] isEqual:@"Hant"]);
    child.payload=[[NSLocale alloc] initWithLocaleIdentifier:@"sr_Latn_RS"];
    assert([[[child locale] objectForKey:NSLocaleScriptCode] isEqual:@"Latn"]);
    child.payload=@"ru_RU";assert([child.locale isEqual:@"ru_CA"]);
    child.payload=@"ru_CA";assert(child.locale==child.payload);
    child.payload=@42;assert(child.locale==child.payload);
    child.payload=nil;assert(child.locale==nil);
    child.throws=YES;BOOL threw=NO;@try{[child locale];}@catch(NSException *e){threw=YES;}assert(threw);child.throws=NO;
    assert(TRETestCarrier(EnvironmentChild.class,@selector(carrier:),NO));
    assert(TRETestCarrier(EnvironmentChild.class,@selector(service:property:),YES));
    assert(!TRETestCarrier(EnvironmentChild.class,@selector(objectArgument:),NO));
    child.payload=nil;
    NSArray *expected=@[@"Rogers",@"ca",@"302",@"720"];
    for(NSInteger i=1;i<=4;i++)assert([[child carrier:i] isEqual:expected[i-1]]);
    assert([child carrier:99]==nil);
    child.payload=@42;assert([child carrier:2]==child.payload);
    child.payload=@"";assert([[child service:17 property:2] isEqual:@"ca"] && child.seenService==17);
    parent.payload=@"original";assert([[parent carrier:2] isEqual:@"original"]);
    TRCTestEnabled(NO);assert([child carrier:2]==child.payload && child.locale==child.payload);
    TRCTestEnabled(YES);
    NSString *originalZone=NSTimeZone.systemTimeZone.name;
    NSString *originalLocale=NSLocale.currentLocale.localeIdentifier;
    TREInstall();
    assert([NSTimeZone.systemTimeZone.name isEqual:originalZone]);
    assert([NSLocale.currentLocale.localeIdentifier isEqual:originalLocale]);
    assert(TRSTestInstall(EnvironmentChild.class,@selector(commonParams),NO));
    NSDictionary *common=child.commonParams;
    assert([common[@"zone_observed"] isEqual:@"America/Toronto"]);
    assert([common[@"country_observed"] isEqual:@"CA"]);
    assert(TRETestDepth()==0 && [NSTimeZone.systemTimeZone.name isEqual:originalZone]);
    child.throws=YES;threw=NO;@try{[child commonParams];}@catch(NSException *e){threw=YES;}
    assert(threw && TRETestDepth()==0);child.throws=NO;
    TREBeginScope();TREBeginScope();TREEndScope();
    assert(TRETestDepth()==1 && [NSTimeZone.defaultTimeZone.name isEqual:@"America/Toronto"]);
    dispatch_semaphore_t done=dispatch_semaphore_create(0);
    [NSThread detachNewThreadWithBlock:^{@autoreleasepool {
        assert(TRETestDepth()==0 && [NSTimeZone.systemTimeZone.name isEqual:originalZone]);
        dispatch_semaphore_signal(done);
    }}];
    assert(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);
    TREEndScope();assert(TRETestDepth()==0);
    TRCTestEnabled(NO);TREBeginScope();
    assert([NSLocale.currentLocale.localeIdentifier isEqual:originalLocale]);
    assert([NSTimeZone.systemTimeZone.name isEqual:originalZone]);TREEndScope();
    NSString *json=[[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:TRESnapshot() options:0 error:nil] encoding:NSUTF8StringEncoding];
    assert(json && ![json containsString:@"original"]);
    puts("Environment: typed locale/language/script, carrier enums/ABI, OFF, inheritance, thread-local scope and exception unwind passed");
}return 0;}
