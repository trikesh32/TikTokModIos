#import "RegionCompatibility.h"
#import <objc/runtime.h>
#include <assert.h>

@interface RegionParent : NSObject
@property(nonatomic) NSUInteger reads;
- (NSString *)country;
- (NSString *)absent;
- (BOOL)scalar;
- (id (^)(void))callback;
- (NSString *)argument:(id)value;
+ (NSString *)country;
@end
@implementation RegionParent
- (NSString *)country { self.reads++; return @"original"; }
- (NSString *)absent { self.reads++; return nil; }
- (BOOL)scalar { return YES; }
- (id (^)(void))callback { return ^id{ return @"callback"; }; }
- (NSString *)argument:(id)value { return value; }
+ (NSString *)country { return @"class-original"; }
@end
@interface RegionChild : RegionParent @end
@implementation RegionChild @end

int main(void) { @autoreleasepool {
    TRCTestEnabled(NO);
    RegionParent *parent=[RegionParent new]; RegionChild *child=[RegionChild new];
    assert(TRCInstallGetter(RegionChild.class,@selector(country),@"CA"));
    assert(TRCInstallGetter(RegionChild.class,@selector(absent),@"CA"));
    assert(TRCInstallGetter(object_getClass(RegionChild.class),@selector(country),@"CA"));
    assert(!TRCInstallGetter(RegionChild.class,@selector(scalar),@"CA"));
    assert(!TRCInstallGetter(RegionChild.class,@selector(callback),@"CA"));
    assert(!TRCInstallGetter(RegionChild.class,@selector(argument:),@"CA"));
    assert(!TRCInstallGetter(RegionChild.class,NSSelectorFromString(@"missing"),@"CA"));
    assert([child.country isEqual:@"original"] && child.reads==1);
    assert(child.absent==nil && child.reads==2);
    assert([RegionChild.country isEqual:@"class-original"]);
    TRCTestEnabled(YES);
    assert([child.country isEqual:@"CA"] && child.reads==2);
    assert([child.absent isEqual:@"CA"] && child.reads==2);
    assert([RegionChild.country isEqual:@"CA"]);
    assert([parent.country isEqual:@"original"] && parent.reads==1);
    assert([RegionParent.country isEqual:@"class-original"]);
    assert(TRCInstallGetter(RegionChild.class,@selector(country),@"different"));
    assert([child.country isEqual:@"CA"]); // Idempotent, no chain of hooks.
    TRCTestEnabled(NO);
    assert([child.country isEqual:@"original"] && child.reads==3);
    NSDictionary *diagnostics=TRCDiagnostics(); BOOL found=NO;
    for (NSDictionary *entry in diagnostics[@"hooks"]) {
        if ([entry[@"method"] isEqual:@"-[RegionChild country]"]) {
            assert([entry[@"reads"] unsignedIntegerValue]==4);
            assert([entry[@"replacements"] unsignedIntegerValue]==2);
            found=YES;
        }
    }
    assert(found);
    assert([NSJSONSerialization isValidJSONObject:diagnostics]);
    assert([diagnostics[@"region_after_restart"] isKindOfClass:NSString.class]);
    assert([diagnostics[@"restart_required"] isKindOfClass:NSNumber.class]);
    puts("Region getters: OFF passthrough, nil, inherited/class methods, ABI rejection, repeat installation and counters passed");
}return 0;}
