#import "SigningContext.h"
#include <assert.h>
int main(void){@autoreleasepool {
    NSString *team=@"TESTTEAM01",*original=@"com.zhiliaoapp.musically";
    NSString *prefix=[NSString stringWithFormat:@"%@.%@.altstore",team,original];
    NSMutableArray *groups=[NSMutableArray arrayWithObject:prefix];
    for(NSString *s in @[@"main",@"test",@"shared",@"dev",@"chainlogin",@"chainassociate"])
        [groups addObject:[prefix stringByAppendingFormat:@".compat.%@",s]];
    for(NSString *identifier in @[[original stringByAppendingFormat:@".%@",team],[NSString stringWithFormat:@"com.%@.%@",team,original]]) {
        NSDictionary *info=@{@"TTDistribution":@"altstore-classic",@"ALTBundleIdentifier":original,@"CFBundleIdentifier":identifier};
        NSDictionary *ent=@{@"application-identifier":[NSString stringWithFormat:@"%@.%@",team,identifier],@"com.apple.developer.team-identifier":team,@"keychain-access-groups":groups};
        NSDictionary *context=TAPResolveSigningContext(info,ent);
        assert([context[@"bundle"] isEqual:identifier] && [context[@"keychain"] isEqual:prefix]);
        NSMutableDictionary *bad=[ent mutableCopy];bad[@"application-identifier"]=@"OTHER.app";assert(!TAPResolveSigningContext(info,bad));
        bad=[ent mutableCopy];bad[@"keychain-access-groups"]=@[prefix];assert(!TAPResolveSigningContext(info,bad));
        bad=[ent mutableCopy];bad[@"com.apple.developer.team-identifier"]=@42;assert(!TAPResolveSigningContext(info,bad));
        bad=[info mutableCopy];[bad removeObjectForKey:@"ALTBundleIdentifier"];assert(!TAPResolveSigningContext(bad,ent));
        bad=[info mutableCopy];bad[@"CFBundleIdentifier"]=original;assert(!TAPResolveSigningContext(bad,ent));
        assert(!TAPResolveSigningContext(info,@{}));
    }
    NSDictionary *local=@{@"CFBundleIdentifier":@"com.zhiliaoapp.musically.TEST",@"TTSignedBundleIdentifier":@"com.zhiliaoapp.musically.TEST",@"TTKeychainCompatPrefix":@"TEST.com.zhiliaoapp.musically.TEST"};
    assert([TAPResolveSigningContext(local,@{})[@"keychain"] isEqual:local[@"TTKeychainCompatPrefix"]]);
    assert(!TAPResolveSigningContext(@{},@{}));
    puts("Signing context: Classic old/new IDs, exact grants, foreign identity rejection and local signer passed");
}return 0;}
