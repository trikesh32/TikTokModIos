#import <Foundation/Foundation.h>
#import "BundleIdentity.h"
#import "KeychainProbe.h"
#include <assert.h>
#include <errno.h>

void TAPRunCompatibilityTests(void);
@interface ReleaseBundleFixture : NSObject
@property(nonatomic,copy) NSDictionary *metadata;
- (NSString *)bundleIdentifier;
- (NSDictionary *)infoDictionary;
- (id)objectForInfoDictionaryKey:(id)key;
@end
@implementation ReleaseBundleFixture
- (NSString *)bundleIdentifier {return self.metadata[@"CFBundleIdentifier"];}
- (NSDictionary *)infoDictionary {return self.metadata;}
- (id)objectForInfoDictionaryKey:(id)key {return self.metadata[key];}
@end
static CFDictionaryRef expectedQuery;
static CFTypeRef *expectedResult;
static OSStatus Original(CFDictionaryRef query,CFTypeRef *result) {
    assert(query==expectedQuery && result==expectedResult);
    errno=EAGAIN;return errSecItemNotFound;
}
int main(void) { @autoreleasepool {
    TAPRunCompatibilityTests();
    ReleaseBundleFixture *target=[ReleaseBundleFixture new],*other=[ReleaseBundleFixture new];
    NSDictionary *metadata=@{@"CFBundleIdentifier":@"com.zhiliaoapp.musically.TEST",@"other":@"untouched"};
    target.metadata=metadata;other.metadata=metadata;
    assert(TAPInstallBundleIdentity(ReleaseBundleFixture.class,target,metadata[@"CFBundleIdentifier"],@"com.zhiliaoapp.musically"));
    assert([target.bundleIdentifier isEqual:@"com.zhiliaoapp.musically"]);
    assert([target.infoDictionary[@"CFBundleIdentifier"] isEqual:@"com.zhiliaoapp.musically"]);
    assert([[target objectForInfoDictionaryKey:@"CFBundleIdentifier"] isEqual:@"com.zhiliaoapp.musically"]);
    assert([[target objectForInfoDictionaryKey:@"other"] isEqual:@"untouched"]);
    assert(other.infoDictionary==metadata && target.metadata==metadata);
    NSDictionary *query=@{(__bridge id)kSecAttrAccessGroup:@"MJ797D8U6F.com.chainlogin",(__bridge id)kSecAttrAccount:@"fixture"};
    NSDictionary *mapped=TAPKeychainRewrite(query,@"TEST.com.zhiliaoapp.musically.TEST");
    assert([mapped[(__bridge id)kSecAttrAccessGroup] isEqual:@"TEST.com.zhiliaoapp.musically.TEST.compat.chainlogin"]);
    assert(mapped[(__bridge id)kSecAttrAccount]==query[(__bridge id)kSecAttrAccount]);
    assert(TAPKeychainRewrite(mapped,@"TEST.com.zhiliaoapp.musically.TEST")==mapped);
    expectedQuery=(__bridge CFDictionaryRef)query;CFTypeRef result=NULL;expectedResult=&result;
    assert(TAPTestCopy(Original,expectedQuery,&result)==errSecItemNotFound);
    assert(errno==EAGAIN && result==NULL);
    puts("0.3.0 release configuration: compatibility, Keychain and Bundle ID tests passed");
}return 0;}
