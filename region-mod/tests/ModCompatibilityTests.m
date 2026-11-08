#import "ModCompatibility.h"
#import <objc/runtime.h>
#include <assert.h>

@interface CompatFixture : NSObject
- (bool)flag;
- (signed char)legacyFlag;
- (bool)flagWithArgument:(bool)arg;
- (NSInteger)wrongReturn;
- (id)source;
- (id)pathForResource:(id)name ofType:(id)type;
- (id)URLForResource:(id)name withExtension:(id)type;
@end
static NSUInteger resourceCalls;
static id lastName,lastType;
@implementation CompatFixture
- (bool)flag {return false;}
- (signed char)legacyFlag {return 1;}
- (bool)flagWithArgument:(bool)arg {return arg;}
- (NSInteger)wrongReturn {return 5;}
- (id)source {return @"original";}
- (id)pathForResource:(id)name ofType:(id)type {resourceCalls++;lastName=name;lastType=type;return @"sentinel";}
- (id)URLForResource:(id)name withExtension:(id)type {resourceCalls++;lastName=name;lastType=type;return @"url-sentinel";}
@end
@interface CompatChild : CompatFixture @end
@implementation CompatChild @end

void TAPRunCompatibilityTests(void) {
    CompatFixture *parent=[CompatFixture new];CompatChild *target=[CompatChild new],*other=[CompatChild new];
    assert(!TAPCompatBool(CompatChild.class,@"wrongReturn",YES,NO));
    assert(!TAPCompatBool(CompatChild.class,@"flagWithArgument:",YES,NO));
    assert(!TAPCompatBool(Nil,@"flag",YES,NO));
    assert(TAPCompatBool(CompatChild.class,@"flag",YES,NO));
    IMP first=class_getMethodImplementation(CompatChild.class,@selector(flag));
    assert(!TAPCompatBool(CompatChild.class,@"flag",NO,NO));
    assert(first==class_getMethodImplementation(CompatChild.class,@selector(flag)));
    assert(target.flag && !parent.flag);
    assert(TAPCompatBool(CompatChild.class,@"legacyFlag",NO,NO));
    assert(!target.legacyFlag && parent.legacyFlag);
    assert(TAPCompatBool(CompatChild.class,@"flagWithArgument:",NO,YES));
    assert(![target flagWithArgument:true] && ![target flagWithArgument:false]);
    assert([parent flagWithArgument:true]);
    assert(!TAPCompatString(CompatChild.class,@"wrongReturn",@"AppStore"));
    assert(TAPCompatString(CompatChild.class,@"source",@"AppStore"));
    assert([target.source isEqual:@"AppStore"] && [parent.source isEqual:@"original"]);
    assert(!TAPCompatResource(CompatChild.class,nil,@"pathForResource:ofType:"));
    assert(TAPCompatResource(CompatChild.class,target,@"pathForResource:ofType:"));
    assert(TAPCompatResource(CompatChild.class,target,@"URLForResource:withExtension:"));
    assert([target pathForResource:@"embedded" ofType:@"mobileprovision"]==nil);
    assert([target URLForResource:@"embedded" withExtension:@"mobileprovision"]==nil);
    assert(resourceCalls==0);
    assert([[other pathForResource:@"embedded" ofType:@"mobileprovision"] isEqual:@"sentinel"]);
    assert([[parent pathForResource:@"embedded" ofType:@"mobileprovision"] isEqual:@"sentinel"]);
    NSString *name=@"unrelated",*type=@"mobileprovision";
    assert([[target pathForResource:name ofType:type] isEqual:@"sentinel"]);
    assert(lastName==name && lastType==type);
    assert([[target pathForResource:@"embedded" ofType:@"plist"] isEqual:@"sentinel"]);
    assert([[target pathForResource:nil ofType:nil] isEqual:@"sentinel"]);
    assert([[other URLForResource:@"embedded" withExtension:@"mobileprovision"] isEqual:@"url-sentinel"]);
    assert(resourceCalls==6);
    puts("ModCompatibility: ABI rejection, inherited-method isolation, resource scoping and repeat-install checks passed");
}
