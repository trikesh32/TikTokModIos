#import "RegionMenu.h"
#import <objc/runtime.h>
#include <string.h>

// Independently implemented against 47.6.0 Objective-C metadata. The existing
// BHTikTok reference identified this extension point; validate every ABI here.
@protocol TRMItem <NSObject>
- (instancetype)initWithIdentifier:(id)identifier;
- (id)identifier;
- (void)setTitle:(id)title;
- (void)setDetail:(id)detail;
- (void)setIconImage:(id)icon;
- (void)setType:(NSInteger)type;
@end
@protocol TRMPlugin <NSObject>
- (instancetype)initWithPluginContext:(id)context;
- (id)itemModel;
- (void)setItemModel:(id)item;
@end
@protocol TRMSection <NSObject>
- (id)sectionIdentifier;
- (id)context;
- (id)modelsArray;
- (void)insertModel:(id)model atIndex:(NSInteger)index animated:(BOOL)animated;
@end
static NSString *const ItemID=@"trikesh.region_mod.settings";
static char InsertingKey,EntryKey;
static NSMutableDictionary *State(void) {
    static NSMutableDictionary *state;static dispatch_once_t once;
    dispatch_once(&once,^{state=[@{@"status":@"not_attempted",@"insertions":@0,@"selections":@0} mutableCopy];});return state;
}
static void Status(NSString *status){@synchronized(State()){State()[@"status"]=status;}}
static void Count(NSString *key){@synchronized(State()){State()[key]=@([State()[key] unsignedLongLongValue]+1);}}
static BOOL Signature(Class cls,NSString *name,const char *ret,NSArray<NSString *> *args) {
    Method m=class_getInstanceMethod(cls,NSSelectorFromString(name));
    if(!m || method_getNumberOfArguments(m)!=args.count+2)return NO;
    char *type=method_copyReturnType(m);BOOL valid=type && strcmp(type,ret)==0;free(type);
    for(NSUInteger i=0;valid && i<args.count;i++){
        type=method_copyArgumentType(m,(unsigned int)i+2);valid=type && strcmp(type,args[i].UTF8String)==0;free(type);
    }return valid;
}
static BOOL IsOurItem(id item,Class itemClass) {
    if(![item isKindOfClass:itemClass])return NO;
    id identifier=[(id<TRMItem>)item identifier];return [identifier isKindOfClass:NSString.class] && [identifier isEqual:ItemID];
}
static id Entry(id<TRMSection> section,Class pluginClass,Class itemClass,id icon) {
    id context=[section context];if(!context)return nil;
    id cached=objc_getAssociatedObject(section,&EntryKey);if(cached)return cached;
    // ARC sees the init method family and retains the correct ownership contract.
    id<TRMItem> item=[(id<TRMItem>)[itemClass alloc] initWithIdentifier:ItemID];
    id<TRMPlugin> plugin=[(id<TRMPlugin>)[pluginClass alloc] initWithPluginContext:context];
    if(!item || !plugin)return nil;
    [item setTitle:@"Настройки мода"];[item setDetail:@"Регион и параметры мода"];
    [item setType:99];if(icon)[item setIconImage:icon];[plugin setItemModel:item];
    objc_setAssociatedObject(section,&EntryKey,plugin,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return plugin;
}
static BOOL Account(id<TRMSection> section) {
    id identifier=[section sectionIdentifier];
    return [identifier isKindOfClass:NSString.class] && [identifier isEqual:@"account"];
}
static id Preserve(id<TRMSection> section,id models,Class pluginClass,Class itemClass,id icon) {
    @try {
        // Nil/unknown input retains its original clearing/error semantics.
        if(!NSThread.isMainThread || ![models isKindOfClass:NSArray.class] || [models count]>512 || !Account(section))return models;
        id entry=nil;NSUInteger count=0;
        for(id model in models)if([model isKindOfClass:pluginClass] && IsOurItem([(id<TRMPlugin>)model itemModel],itemClass)){if(!entry)entry=model;count++;}
        if(count==1 && [models firstObject]==entry)return models;
        if(!entry)entry=Entry(section,pluginClass,itemClass,icon);
        if(!entry)return models;
        NSMutableArray *out=[NSMutableArray arrayWithObject:entry];
        for(id model in models)
            if(!([model isKindOfClass:pluginClass] && IsOurItem([(id<TRMPlugin>)model itemModel],itemClass)))[out addObject:model];
        Count(@"preserved_updates");
        return [models isKindOfClass:NSMutableArray.class]?out:[out copy];
    }@catch(__unused NSException *e){Count(@"update_errors");return models;}
}
static void Insert(id<TRMSection> section,Class pluginClass,Class itemClass,id icon) {
    if(objc_getAssociatedObject(section,&InsertingKey))return;
    @try {
        if(!Account(section))return;
        id models=[section modelsArray];
        if(models && (![models isKindOfClass:NSArray.class] || [models count]>512))return;
        for(id model in models)
            if([model isKindOfClass:pluginClass] && IsOurItem([(id<TRMPlugin>)model itemModel],itemClass))return;
        objc_setAssociatedObject(section,&InsertingKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        id plugin=Entry(section,pluginClass,itemClass,icon);if(!plugin)return;
        [section insertModel:plugin atIndex:0 animated:NO];Count(@"insertions");
    }@catch(__unused NSException *e){Count(@"insertion_errors");}
    @finally{objc_setAssociatedObject(section,&InsertingKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
}
static BOOL Install(Class section,Class plugin,Class item,void (^openSettings)(void),id icon) {
    if(!section || !plugin || !item || !openSettings){Status(@"classes_unavailable");return NO;}
    @synchronized(State()) {
        // Each installation tuple is immutable; retries must not chain hooks.
        static NSMutableSet *installed; if(!installed)installed=[NSMutableSet new];
        NSString *key=[NSString stringWithFormat:@"%s/%s/%s",class_getName(section),class_getName(plugin),class_getName(item)];
        if([installed containsObject:key])return YES;
        BOOL valid=Signature(section,@"viewDidLoad","v",@[]) && Signature(section,@"viewWillAppear","v",@[]) &&
            Signature(section,@"sectionIdentifier","@",@[]) && Signature(section,@"context","@",@[]) &&
            Signature(section,@"modelsArray","@",@[]) && Signature(section,@"insertModel:atIndex:animated:","v",@[@"@",@"q",@"B"]) &&
            Signature(plugin,@"initWithPluginContext:","@",@[@"@"]) && Signature(plugin,@"itemModel","@",@[]) &&
            Signature(plugin,@"setItemModel:","v",@[@"@"]) && Signature(plugin,@"didSelectItemAtIndex:","v",@[@"q"]) &&
            Signature(item,@"initWithIdentifier:","@",@[@"@"]) && Signature(item,@"identifier","@",@[]) &&
            Signature(item,@"setTitle:","v",@[@"@"]) && Signature(item,@"setDetail:","v",@[@"@"]) &&
            Signature(item,@"setIconImage:","v",@[@"@"]) && Signature(item,@"setType:","v",@[@"q"]);
        valid=valid && Signature(section,@"replaceByModels:","v",@[@"@"]) &&
            Signature(section,@"setModelsArray:","v",@[@"@"]) &&
            Signature(section,@"replaceByModels:animated:sync:completion:","v",@[@"@",@"B",@"B",@"@?"]) &&
            Signature(section,@"updateByModels:animated:sync:","v",@[@"@",@"B",@"B"]);
        if(!valid){Status(@"unsupported_abi");return NO;}
        SEL select=NSSelectorFromString(@"didSelectItemAtIndex:");Method selection=class_getInstanceMethod(plugin,select);IMP original=method_getImplementation(selection);
        IMP handler=imp_implementationWithBlock(^(id object,NSInteger index){
            BOOL ours=NO;@try{ours=IsOurItem([(id<TRMPlugin>)object itemModel],item);}@catch(__unused NSException *e){}
            if(ours){Count(@"selections");if(NSThread.isMainThread)openSettings();else dispatch_async(dispatch_get_main_queue(),openSettings);return;}
            ((void(*)(id,SEL,NSInteger))original)(object,select,index);
        });
        if(!class_addMethod(plugin,select,handler,method_getTypeEncoding(selection)))method_setImplementation(class_getInstanceMethod(plugin,select),handler);
        // Decorate replacement inputs BEFORE the native diff/update starts.
        // Reloading after the diff or modifying a getter would desynchronise the
        // collection's item counts. Override only this settings subclass.
        for(NSString *name in @[@"replaceByModels:",@"setModelsArray:",@"replaceByModels:animated:sync:completion:",@"updateByModels:animated:sync:"]) {
            SEL selector=NSSelectorFromString(name);Method method=class_getInstanceMethod(section,selector);IMP before=method_getImplementation(method),hook;
            if([name isEqual:@"replaceByModels:animated:sync:completion:"])
                hook=imp_implementationWithBlock(^(id object,id models,BOOL animated,BOOL sync,id completion){
                    id updated=Preserve(object,models,plugin,item,icon);
                    ((void(*)(id,SEL,id,BOOL,BOOL,id))before)(object,selector,updated,animated,sync,completion);
                });
            else if([name isEqual:@"updateByModels:animated:sync:"])
                hook=imp_implementationWithBlock(^(id object,id models,BOOL animated,BOOL sync){
                    id updated=Preserve(object,models,plugin,item,icon);
                    ((void(*)(id,SEL,id,BOOL,BOOL))before)(object,selector,updated,animated,sync);
                });
            else hook=imp_implementationWithBlock(^(id object,id models){
                id updated=Preserve(object,models,plugin,item,icon);
                ((void(*)(id,SEL,id))before)(object,selector,updated);
            });
            if(!class_addMethod(section,selector,hook,method_getTypeEncoding(method)))method_setImplementation(class_getInstanceMethod(section,selector),hook);
        }
        for(NSString *name in @[@"viewDidLoad",@"viewWillAppear"]) {
            SEL selector=NSSelectorFromString(name);Method method=class_getInstanceMethod(section,selector);IMP before=method_getImplementation(method);
            IMP hook=imp_implementationWithBlock(^(id object){
                ((void(*)(id,SEL))before)(object,selector);
                // Section lifecycle is UI work. Never mutate a list on a worker.
                if(NSThread.isMainThread)Insert(object,plugin,item,icon);
            });
            if(!class_addMethod(section,selector,hook,method_getTypeEncoding(method)))method_setImplementation(class_getInstanceMethod(section,selector),hook);
        }
        [installed addObject:key];Status(@"installed");return YES;
    }
}
void TRMInstall(void (^openSettings)(void),id icon) {
    Install(NSClassFromString(@"AWESettingsNormalSectionViewModel"),NSClassFromString(@"TTKSettingsBaseCellPlugin"),NSClassFromString(@"AWESettingItemModel"),openSettings,icon);
}
NSDictionary *TRMSnapshot(void){@synchronized(State()){return [State() copy];}}
#ifdef TAP_TESTING
BOOL TRMTestInstall(Class section,Class plugin,Class item,void (^openSettings)(void),id icon){return Install(section,plugin,item,openSettings,icon);}
#endif
