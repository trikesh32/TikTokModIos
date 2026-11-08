#import <UIKit/UIKit.h>
#import "RegionCompatibility.h"
#import "RegionProfile.h"
#import "RegionMenu.h"
#ifdef TT_REGION_AGGRESSIVE
#import "RegionPNS.h"
#endif
#ifdef TT_REGION_DIAGNOSTICS
#import "RegionObservation.h"
#endif

static BOOL Pending(void) {
    return TRCSavedEnabled()!=TRCEnabled() || ![TRFSavedCountry() isEqual:TRFCountry()];
}
static NSString *SettingName(BOOL enabled,NSString *country) {
    return enabled?TRFProfile(country)[@"name"]:@"Выключено";
}
static UITableViewCell *Cell(UITableView *table,NSString *title,NSString *detail) {
    UITableViewCell *cell=[table dequeueReusableCellWithIdentifier:@"setting"];
    if(!cell)cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"setting"];
    cell.textLabel.text=title;cell.detailTextLabel.text=detail;
    cell.textLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    cell.detailTextLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    cell.textLabel.adjustsFontForContentSizeCategory=YES;cell.detailTextLabel.adjustsFontForContentSizeCategory=YES;
    cell.textLabel.numberOfLines=0;cell.detailTextLabel.numberOfLines=0;
    cell.accessoryView=nil;cell.accessoryType=UITableViewCellAccessoryNone;
    cell.selectionStyle=UITableViewCellSelectionStyleDefault;
    return cell;
}
@interface TRCRegionPicker : UITableViewController @end
@implementation TRCRegionPicker
- (void)viewDidLoad {[super viewDidLoad];self.title=@"Регион";self.tableView.rowHeight=UITableViewAutomaticDimension;self.tableView.estimatedRowHeight=54;}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {return TRFProfiles().count;}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)index {
    NSDictionary *p=TRFProfiles()[index.row];UITableViewCell *cell=Cell(table,p[@"name"],p[@"country"]);
    cell.accessoryType=[p[@"country"] isEqual:TRFSavedCountry()]?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryNone;
    cell.accessibilityIdentifier=[@"mod.region." stringByAppendingString:p[@"country"]];return cell;
}
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section {
    return @"Выбранный регион применится после полного перезапуска TikTok. Доступность контента может различаться между регионами.";
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)index {
    if(TRFSaveCountry(TRFProfiles()[index.row][@"country"]))[self.navigationController popViewControllerAnimated:YES];
}
@end

@interface TRCDiagnosticsController : UITableViewController @end
@implementation TRCDiagnosticsController
- (void)viewDidLoad {[super viewDidLoad];self.title=@"Диагностика";self.tableView.rowHeight=UITableViewAutomaticDimension;self.tableView.estimatedRowHeight=54;}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table {return 2;}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {return section==0?3:1;}
- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section {return section==0?@"Начать замер":nil;}
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section {
    return section==0?@"Выбери действие, закрой настройки и воспроизведи проблему. Затем вернись сюда и скопируй диагностику.":@"Диагностика копируется в буфер обмена только по нажатию. Мод не отправляет её автоматически.";
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)index {
    NSString *title=index.section==0?@[@"Видео из чата",@"Лайки",@"Лента"][index.row]:@"Скопировать диагностику";
    return Cell(table,title,nil);
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)index {
    [table deselectRowAtIndexPath:index animated:YES];
    if(index.section==0) {
#ifdef TT_REGION_DIAGNOSTICS
        TRDBeginWindow(@[@"chat",@"likes",@"feed"][index.row]);
#ifdef TT_REGION_AGGRESSIVE
        TRPBeginWindow();
#endif
#endif
        [self.navigationController dismissViewControllerAnimated:YES completion:nil];
    } else {
        NSError *error=nil;NSData *data=[NSJSONSerialization dataWithJSONObject:TRCDiagnostics() options:NSJSONWritingPrettyPrinted error:&error];
        NSString *text=data?[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]:nil;
        if(text)UIPasteboard.generalPasteboard.string=text;
        UIAlertController *alert=[UIAlertController alertControllerWithTitle:text?@"Скопировано":@"Не удалось скопировать" message:text?@"Диагностика в буфере обмена. Теперь её можно вставить в сообщение.":@"Попробуй ещё раз." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Понятно" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}
@end

@interface TRCModSettingsController : UITableViewController @end
@implementation TRCModSettingsController
- (void)viewDidLoad {
    [super viewDidLoad];self.title=@"Настройки мода";
    self.tableView.rowHeight=UITableViewAutomaticDimension;self.tableView.estimatedRowHeight=54;
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close)];
}
- (void)viewWillAppear:(BOOL)animated {[super viewWillAppear:animated];[self.tableView reloadData];}
- (void)close {[self.navigationController dismissViewControllerAnimated:YES completion:nil];}
- (void)toggle:(UISwitch *)sender {TRCSaveEnabled(sender.on);[self.tableView reloadData];}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table {return 3;}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {return section==0?2:1;}
- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section {return section==0?@"Регион":section==1?@"Поддержка":nil;}
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section {
    if(section!=0)return nil;
    NSString *state=[NSString stringWithFormat:@"Сейчас: %@.",SettingName(TRCEnabled(),TRFCountry())];
    if(Pending())state=[state stringByAppendingFormat:@" После перезапуска: %@.",SettingName(TRCSavedEnabled(),TRFSavedCountry())];
    return [state stringByAppendingString:@"\n\nПосле изменения настроек полностью закрой TikTok через переключатель приложений и открой снова. Язык приложения остаётся прежним. IP-адрес не меняется."];
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)index {
    UITableViewCell *cell;
    if(index.section==0 && index.row==0) {
        cell=Cell(table,@"Изменять регион",nil);UISwitch *toggle=[UISwitch new];toggle.on=TRCSavedEnabled();
        toggle.accessibilityLabel=@"Изменять регион";toggle.accessibilityIdentifier=@"mod.enabled";
        [toggle addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView=toggle;cell.selectionStyle=UITableViewCellSelectionStyleNone;
    } else if(index.section==0) {
        cell=Cell(table,@"Страна",TRFProfile(TRFSavedCountry())[@"name"]);cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
        cell.accessibilityIdentifier=@"mod.country";
    } else if(index.section==1) {
        cell=Cell(table,@"Диагностика",nil);cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    } else {
        cell=Cell(table,@"Версия мода",TRC_VERSION);cell.selectionStyle=UITableViewCellSelectionStyleNone;
    }
    return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)index {
    [table deselectRowAtIndexPath:index animated:YES];
    if(index.section==0 && index.row==1)[self.navigationController pushViewController:[[TRCRegionPicker alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];
    else if(index.section==1)[self.navigationController pushViewController:[[TRCDiagnosticsController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];
}
@end

// Entry point lives in TikTok's own settings list. No window overlay is created.
static UIViewController *SettingsPresenter(void) {
    for(UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if(![scene isKindOfClass:UIWindowScene.class] || scene.activationState!=UISceneActivationStateForegroundActive)continue;
        for(UIWindow *window in ((UIWindowScene *)scene).windows) {
            if(!window.isKeyWindow || window.windowLevel!=UIWindowLevelNormal)continue;
            UIViewController *controller=window.rootViewController;
            while(controller.presentedViewController)controller=controller.presentedViewController;
            return controller;
        }
    }
    return nil;
}
static void ShowModSettings(void) {
    UIViewController *presenter=SettingsPresenter();
    if(!presenter || presenter.isBeingDismissed || presenter.isBeingPresented || [presenter isKindOfClass:UIAlertController.class])return;
    if([presenter isKindOfClass:UINavigationController.class] && [((UINavigationController *)presenter).viewControllers.firstObject isKindOfClass:TRCModSettingsController.class])return;
    UINavigationController *nav=[[UINavigationController alloc] initWithRootViewController:[[TRCModSettingsController alloc] initWithStyle:UITableViewStyleInsetGrouped]];
    nav.modalPresentationStyle=UIModalPresentationFormSheet;
    [presenter presentViewController:nav animated:YES completion:nil];TRCUIAttached();
}
static void InstallSettingsEntry(void) {
    TRMInstall(^{ShowModSettings();},[UIImage systemImageNamed:@"gearshape"]);
}
void TRCStartSettings(void) {
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *notification){InstallSettingsEntry();TRCInstallHooks();}];
    dispatch_async(dispatch_get_main_queue(),^{InstallSettingsEntry();});
    // Classes loaded later are retried; repeated installation is a no-op.
    for(NSNumber *delay in @[@0.2,@0.5,@1,@2,@4,@8])dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(delay.doubleValue*NSEC_PER_SEC)),dispatch_get_main_queue(),^{InstallSettingsEntry();});
}
