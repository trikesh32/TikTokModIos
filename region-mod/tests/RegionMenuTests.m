#import "RegionMenu.h"
#include <assert.h>
@interface MenuItem:NSObject
@property(nonatomic,copy) NSString *identifier,*title,*detail;
@property(nonatomic,strong) id iconImage;
@property(nonatomic) NSInteger type;
- (instancetype)initWithIdentifier:(id)identifier;
@end
@implementation MenuItem
- (instancetype)initWithIdentifier:(id)identifier{if((self=[super init]))self.identifier=identifier;return self;}
@end
@interface MenuPluginParent:NSObject
@property(nonatomic,strong) id itemModel,context;
@property(nonatomic) NSInteger selected;
- (instancetype)initWithPluginContext:(id)context;
- (void)didSelectItemAtIndex:(NSInteger)index;
@end
@implementation MenuPluginParent
- (instancetype)initWithPluginContext:(id)context{if((self=[super init]))self.context=context;return self;}
- (void)didSelectItemAtIndex:(NSInteger)index{self.selected=index;}
@end
@interface MenuPlugin:MenuPluginParent @end
@implementation MenuPlugin @end
@interface MenuSectionParent:NSObject
@property(nonatomic,copy) NSString *sectionIdentifier;
@property(nonatomic,strong) id context;
@property(nonatomic,strong) NSMutableArray *modelsArray;
@property(nonatomic) NSUInteger loads,appearances,inserts;
@property(nonatomic) BOOL reenter,throws;
@property(nonatomic,strong) id lastReplacement;
@property(nonatomic,copy) void(^completion)(void);
@property(nonatomic) BOOL animated,sync;
- (void)viewDidLoad;
- (void)viewWillAppear;
- (void)insertModel:(id)model atIndex:(NSInteger)index animated:(BOOL)animated;
- (void)replaceByModels:(id)models;
- (void)replaceByModels:(id)models animated:(BOOL)animated sync:(BOOL)sync completion:(void(^)(void))completion;
- (void)updateByModels:(id)models animated:(BOOL)animated sync:(BOOL)sync;
@end
@implementation MenuSectionParent
- (instancetype)init{if((self=[super init])){self.context=[NSObject new];self.modelsArray=[NSMutableArray new];self.sectionIdentifier=@"account";}return self;}
- (void)viewDidLoad{self.loads++;if(self.throws)@throw [NSException exceptionWithName:@"fixture" reason:nil userInfo:nil];}
- (void)viewWillAppear{self.appearances++;}
- (void)replaceByModels:(id)models {[self replaceByModels:models animated:NO sync:NO completion:nil];}
- (void)replaceByModels:(id)models animated:(BOOL)animated sync:(BOOL)sync completion:(void(^)(void))completion {
    self.lastReplacement=models;self.animated=animated;self.sync=sync;self.completion=completion;
    self.modelsArray=[models mutableCopy];
}
- (void)updateByModels:(id)models animated:(BOOL)animated sync:(BOOL)sync {
    [self replaceByModels:models animated:animated sync:sync completion:nil];
}
- (void)insertModel:(id)model atIndex:(NSInteger)index animated:(BOOL)animated {
    assert(index==0 && !animated);self.inserts++;
    if(self.reenter)[self viewWillAppear];
    [self.modelsArray insertObject:model atIndex:index];
}
@end
@interface MenuSection:MenuSectionParent @end
@implementation MenuSection @end
@interface WrongSection:NSObject
- (id)viewDidLoad;
@end
@implementation WrongSection
- (id)viewDidLoad{return nil;}
@end
int main(void){@autoreleasepool {
    __block NSUInteger opened=0;id icon=[NSObject new];
    assert(!TRMTestInstall(WrongSection.class,MenuPlugin.class,MenuItem.class,^{opened++;},icon));
    assert(TRMTestInstall(MenuSection.class,MenuPlugin.class,MenuItem.class,^{opened++;},icon));
    assert(TRMTestInstall(MenuSection.class,MenuPlugin.class,MenuItem.class,^{opened+=100;},icon));
    MenuSection *section=[MenuSection new];MenuSectionParent *parent=[MenuSectionParent new];
    MenuPlugin *ordinary=[[MenuPlugin alloc] initWithPluginContext:section.context];
    ordinary.itemModel=[[MenuItem alloc] initWithIdentifier:@"privacy"];
    [section.modelsArray addObject:ordinary];
    section.reenter=YES;[section viewDidLoad];
    assert(section.loads==1 && section.inserts==1 && section.modelsArray.count==2);
    assert(section.modelsArray[1]==ordinary);
    MenuPlugin *ours=section.modelsArray.firstObject;MenuItem *item=ours.itemModel;
    assert([item.title isEqual:@"Настройки мода"] && item.iconImage==icon && item.type==99);
    assert(ours.context==section.context);
    [section viewDidLoad];[section viewWillAppear];assert(section.inserts==1);
    // Regression: native settings reload after opening, without a second
    // lifecycle callback. The item must be part of the next diff's input.
    NSArray *native=@[ordinary];__block BOOL reloaded=NO;
    dispatch_async(dispatch_get_main_queue(),^{[section replaceByModels:native];reloaded=YES;});
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:2];
    while(!reloaded && deadline.timeIntervalSinceNow>0)[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    assert(reloaded && section.lastReplacement!=native && section.modelsArray.count==2);
    assert(section.modelsArray.firstObject==ours && native.count==1);
    assert(section.lastReplacement[0]==ours && section.lastReplacement[1]==ordinary);
    __block BOOL completed=NO;void(^completion)(void)=^{completed=YES;};
    [section replaceByModels:native animated:YES sync:YES completion:completion];
    assert(section.animated && section.sync && section.completion==completion && !completed);
    section.completion();assert(completed);
    [section updateByModels:native animated:NO sync:YES];assert(!section.animated && section.sync && section.modelsArray.firstObject==ours);
    section.modelsArray=[native mutableCopy];assert(section.modelsArray.count==2 && section.modelsArray.firstObject==ours);
    [section replaceByModels:@[ordinary,ours,ours]];assert(section.modelsArray.count==2 && section.modelsArray.firstObject==ours);
    [section replaceByModels:nil];assert(section.modelsArray==nil);
    [section replaceByModels:@[]];assert(section.modelsArray.count==1 && section.modelsArray.firstObject==ours);
    [ours didSelectItemAtIndex:0];assert(opened==1 && ours.selected==0);
    [ordinary didSelectItemAtIndex:7];assert(ordinary.selected==7 && opened==1);
    MenuPluginParent *unhooked=[[MenuPluginParent alloc] initWithPluginContext:parent.context];unhooked.itemModel=item;
    [unhooked didSelectItemAtIndex:8];assert(unhooked.selected==8 && opened==1);
    [parent viewDidLoad];assert(parent.loads==1 && parent.modelsArray.count==0);
    [parent replaceByModels:native];assert(parent.modelsArray.count==1 && parent.modelsArray.firstObject==ordinary);
    section.sectionIdentifier=@"privacy";[section.modelsArray removeAllObjects];[section viewWillAppear];assert(section.modelsArray.count==0);
    section.sectionIdentifier=@"account";section.context=nil;[section viewWillAppear];assert(section.modelsArray.count==0);
    section.context=[NSObject new];[section viewWillAppear];assert(section.modelsArray.count==1 && section.inserts==2);
    // Stable plugin identity is retained only by its section, not globally.
    __weak id weakSection,weakPlugin;
    @autoreleasepool {
        MenuSection *temporary=[MenuSection new];[temporary replaceByModels:@[]];
        weakSection=temporary;weakPlugin=temporary.modelsArray.firstObject;
    }
    assert(weakSection==nil && weakPlugin==nil);
    [section.modelsArray removeAllObjects];
    section.throws=YES;BOOL threw=NO;@try{[section viewDidLoad];}@catch(__unused NSException *e){threw=YES;}assert(threw && section.modelsArray.count==0);
    assert([TRMSnapshot()[@"status"] isEqual:@"installed"]);
    assert([TRMSnapshot()[@"selections"] intValue]==1);
    puts("Native menu: delayed replacement regression, diff input, stable identity, duplicates, callback/flags, inheritance, passthrough and ARC lifetime passed");
}}
