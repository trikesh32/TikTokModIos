#import <Foundation/Foundation.h>
#import "RegionCompatibility.h"
#include <assert.h>
void TAPStartCompatibility(NSBundle *bundle);
static BOOL guest,valid;
static NSUInteger signingCalls,keychainCalls,identityCalls,compatCalls,regionCalls,menuCalls;
static NSString *environment,*signing;
BOOL TAPIsLiveContainerGuest(NSBundle *bundle){(void)bundle;return guest;}
BOOL TAPInitializeSigningContext(NSBundle *bundle){(void)bundle;signingCalls++;return valid;}
void TAPInstallKeychainObservers(void){keychainCalls++;}
void TAPStartBundleIdentity(void){identityCalls++;}
void TAPInstallModCompatibility(void){compatCalls++;}
void TRCSetRuntimeEnvironment(NSString *s){environment=s;}
void TRCSetSigningCompatibility(NSString *s){signing=s;}
void TRCStart(void){regionCalls++;}
void TRCStartSettings(void){menuCalls++;}
void TRCInstallHooks(void){}
@interface Fixture:NSObject
@property(nonatomic,copy) NSDictionary *info;
@end
@implementation Fixture
- (id)objectForInfoDictionaryKey:(NSString *)key{return self.info[key];}
@end
static void Reset(void){signingCalls=keychainCalls=identityCalls=compatCalls=regionCalls=menuCalls=0;environment=nil;signing=nil;}
int main(void){@autoreleasepool {
    Fixture *f=[Fixture new];
    f.info=@{@"TTCompatibilityBuild":TRC_VERSION,@"TTModCompatibilityProfile":@"full",@"TTCarrierRegionProfile":@"CA"};
    valid=YES;guest=NO;TAPStartCompatibility((NSBundle *)f);
    assert(signingCalls==1 && keychainCalls==1 && identityCalls==1 && compatCalls==1);
    assert(regionCalls==1 && menuCalls==1 && [signing isEqual:@"validated"]);
    Reset();valid=NO;TAPStartCompatibility((NSBundle *)f);
    assert(signingCalls==1 && keychainCalls==0 && identityCalls==0 && compatCalls==0);
    assert(regionCalls==1 && menuCalls==1 && [signing isEqual:@"unavailable"]);
    Reset();guest=YES;TAPStartCompatibility((NSBundle *)f);
    assert(signingCalls==0 && keychainCalls==0 && identityCalls==0 && compatCalls==0);
    assert(regionCalls==1 && menuCalls==1 && [environment isEqual:@"livecontainer"] && [signing isEqual:@"container_managed"]);
    Reset();f.info=@{@"TTCompatibilityBuild":@"wrong",@"TTModCompatibilityProfile":@"full",@"TTCarrierRegionProfile":@"CA"};
    TAPStartCompatibility((NSBundle *)f);assert(signingCalls==0 && regionCalls==0 && menuCalls==0);
    puts("Bootstrap: signed standalone, unavailable signing, container ownership and build guard passed");
}return 0;}
