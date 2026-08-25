#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

// ===== 微信私有API声明（100%对齐你提供的class-dump头文件）=====
@interface WCTableViewManager : NSObject
- (instancetype)initWithFrame:(struct CGRect)arg1 style:(long long)arg2;
- (void)clearAllSection;
- (id)getTableView;
- (void)addSection:(id)arg1;
- (void)reloadTableView;
@end

@interface WCTableViewSectionManager : NSObject
+ (id)sectionInfoHeader:(id)arg1;
+ (id)defaultSection;
- (void)addCell:(id)arg1;
@end

@interface WCTableViewCellManager : NSObject
+ (id)switchCellForSel:(SEL)arg1 target:(id)arg2 title:(id)arg3 on:(_Bool)arg4;
@end

@interface WCPluginsMgr : NSObject
+ (instancetype)sharedInstance;
- (void)registerControllerWithTitle:(NSString *)title
                           version:(NSString *)version
                        controller:(NSString *)controller;
@end

// ===== 配置存储（无冗余逻辑，仅存开关状态）=====
static NSString * const kDDAdBlockConfigKey = @"DDAdBlockConfig";

@interface DDAdBlockConfig : NSObject
+ (instancetype)shared;
@property (nonatomic, assign) BOOL master;          // 总开关
@property (nonatomic, assign) BOOL moments;         // 朋友圈广告
@property (nonatomic, assign) BOOL brand;           // 公众号广告
@property (nonatomic, assign) BOOL finder;          // 视频号广告
@property (nonatomic, assign) BOOL live;            // 直播广告
@property (nonatomic, assign) BOOL search;          // 搜索广告
@property (nonatomic, assign) BOOL miniProgram;     // 小程序广告
@property (nonatomic, assign) BOOL rewardedFastPass;// 激励广告快过
@end

@implementation DDAdBlockConfig
+ (instancetype)shared {
    static DDAdBlockConfig *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [DDAdBlockConfig new]; });
    return instance;
}
- (NSDictionary *)currentConfig {
    return [[NSUserDefaults standardUserDefaults] dictionaryForKey:kDDAdBlockConfigKey] ?: @{};
}
- (void)setBoolValue:(BOOL)value forKey:(NSString *)key {
    NSMutableDictionary *config = [[self currentConfig] mutableCopy];
    config[key] = @(value);
    [[NSUserDefaults standardUserDefaults] setObject:config forKey:kDDAdBlockConfigKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}
// 自动生成getter/setter
#define DD_CONFIG_GET(key) return [[self currentConfig][key] boolValue];
#define DD_CONFIG_SET(key) [self setBoolValue:value forKey:key];
- (BOOL)master { DD_CONFIG_GET(@"master") } - (void)setMaster:(BOOL)value { DD_CONFIG_SET(@"master") }
- (BOOL)moments { DD_CONFIG_GET(@"moments") } - (void)setMoments:(BOOL)value { DD_CONFIG_SET(@"moments") }
- (BOOL)brand { DD_CONFIG_GET(@"brand") } - (void)setBrand:(BOOL)value { DD_CONFIG_SET(@"brand") }
- (BOOL)finder { DD_CONFIG_GET(@"finder") } - (void)setFinder:(BOOL)value { DD_CONFIG_SET(@"finder") }
- (BOOL)live { DD_CONFIG_GET(@"live") } - (void)setLive:(BOOL)value { DD_CONFIG_SET(@"live") }
- (BOOL)search { DD_CONFIG_GET(@"search") } - (void)setSearch:(BOOL)value { DD_CONFIG_SET(@"search") }
- (BOOL)miniProgram { DD_CONFIG_GET(@"miniProgram") } - (void)setMiniProgram:(BOOL)value { DD_CONFIG_SET(@"miniProgram") }
- (BOOL)rewardedFastPass { DD_CONFIG_GET(@"rewardedFastPass") } - (void)setRewardedFastPass:(BOOL)value { DD_CONFIG_SET(@"rewardedFastPass") }
@end

// ===== 微信原生设置界面（100%用你提供的私有类实现）=====
@interface DDAdBlockSettingsViewController : UIViewController
@property (nonatomic, strong) id tableViewManager;
@end

@implementation DDAdBlockSettingsViewController
- (void)ensureTableViewManager {
    if (_tableViewManager) return;
    Class mgrClass = objc_getClass("WCTableViewManager");
    if (!mgrClass) return;
    _tableViewManager = [[mgrClass alloc] initWithFrame:UIScreen.mainScreen.bounds
                                                 style:UITableViewStyleInsetGrouped];
}
- (instancetype)init {
    if (self = [super init]) [self ensureTableViewManager];
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"DD广告拦截";
    [self ensureTableViewManager];
    if (!_tableViewManager) return;
    [self buildTableView];
    UITableView *tableView = [_tableViewManager getTableView];
    tableView.frame = self.view.bounds;
    tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentAutomatic;
    [self.view addSubview:tableView];
}
- (void)buildTableView {
    id cellManager = objc_getClass("WCTableViewCellManager");
    id sectionManager = objc_getClass("WCTableViewSectionManager");
    if (!cellManager || !sectionManager || !_tableViewManager) return;

    DDAdBlockConfig *config = DDAdBlockConfig.shared;
    [_tableViewManager clearAllSection];

    // 分组1：广告拦截场景（搜索广告已归位）
    id mainSection = [sectionManager sectionInfoHeader:@"广告拦截场景"];
    [mainSection addCell:[cellManager switchCellForSel:@selector(onMasterSwitch:)
                                                target:self
                                                 title:@"启用广告拦截"
                                                    on:config.master]];
    [mainSection addCell:[cellManager switchCellForSel:@selector(onMomentsSwitch:)
                                                target:self
                                                 title:@"屏蔽朋友圈广告"
                                                    on:config.moments]];
    [mainSection addCell:[cellManager switchCellForSel:@selector(onBrandSwitch:)
                                                target:self
                                                 title:@"屏蔽公众号广告"
                                                    on:config.brand]];
    [mainSection addCell:[cellManager switchCellForSel:@selector(onFinderSwitch:)
                                                target:self
                                                 title:@"屏蔽视频号广告"
                                                    on:config.finder]];
    [mainSection addCell:[cellManager switchCellForSel:@selector(onLiveSwitch:)
                                                target:self
                                                 title:@"屏蔽直播广告"
                                                    on:config.live]];
    [mainSection addCell:[cellManager switchCellForSel:@selector(onSearchSwitch:)
                                                target:self
                                                 title:@"屏蔽搜索广告"
                                                    on:config.search]];
    [mainSection addCell:[cellManager switchCellForSel:@selector(onMiniProgramSwitch:)
                                                target:self
                                                 title:@"屏蔽小程序广告"
                                                    on:config.miniProgram]];
    [_tableViewManager addSection:mainSection];

    // 分组2：进阶拦截（仅保留激励快过）
    id advancedSection = [sectionManager sectionInfoHeader:@"进阶拦截"];
    [advancedSection addCell:[cellManager switchCellForSel:@selector(onRewardedFastPassSwitch:)
                                                    target:self
                                                     title:@"激励广告快速跳过"
                                                        on:config.rewardedFastPass]];
    [_tableViewManager addSection:advancedSection];

    [_tableViewManager reloadTableView];
}
// 开关回调
- (void)onMasterSwitch:(UISwitch *)sender {
    DDAdBlockConfig.shared.master = sender.isOn;
    [self buildTableView];
}
- (void)onMomentsSwitch:(UISwitch *)sender {
    DDAdBlockConfig.shared.moments = sender.isOn;
    [self buildTableView];
}
- (void)onBrandSwitch:(UISwitch *)sender {
    DDAdBlockConfig.shared.brand = sender.isOn;
    [self buildTableView];
}
- (void)onFinderSwitch:(UISwitch *)sender {
    DDAdBlockConfig.shared.finder = sender.isOn;
    [self buildTableView];
}
- (void)onLiveSwitch:(UISwitch *)sender {
    DDAdBlockConfig.shared.live = sender.isOn;
    [self buildTableView];
}
- (void)onSearchSwitch:(UISwitch *)sender {
    DDAdBlockConfig.shared.search = sender.isOn;
    [self buildTableView];
}
- (void)onMiniProgramSwitch:(UISwitch *)sender {
    DDAdBlockConfig.shared.miniProgram = sender.isOn;
    [self buildTableView];
}
- (void)onRewardedFastPassSwitch:(UISwitch *)sender {
    DDAdBlockConfig.shared.rewardedFastPass = sender.isOn;
    [self buildTableView];
}
@end

// ===== 30个业务Hook（覆盖微信8.0.76全广告场景，无青少年模式残留）=====
#pragma mark - 1. 朋友圈广告拦截
%hook MMTimelineAdData
- (BOOL)isValidAd {
    return !(DDAdBlockConfig.shared.master && DDAdBlockConfig.shared.moments);
}
%end

%hook MMTimelineAdTableViewCell
- (void)layoutSubviews {
    if (DDAdBlockConfig.shared.master && DDAdBlockConfig.shared.moments) return;
    %orig;
}
%end

%hook TimelineInteractionAdView
- (void)showAd {
    if (DDAdBlockConfig.shared.master && DDAdBlockConfig.shared.moments) return;
    %orig;
}
%end

#pragma mark - 2. 公众号广告拦截
%hook BrandArticleAdView
- (void)showAdWithData:(id)data {
    if (DDAdBlockConfig.shared.master && DDAdBlockConfig.shared.brand) return;
    %orig;
}
%end

%hook BrandInlineAdView
- (void)renderAd {
    if (DDAdBlockConfig.shared.master && DDAdBlockConfig.shared.brand) return;
    %orig;
}
%end

%hook BrandSessionAdCell
- (void)setAdData:(id)data {
    if (DDAdBlockConfig.shared.master && DDAdBlockConfig.shared.brand) return;
    %orig;
}
%end

%hook BrandDetailAdView
- (void)layoutSubviews {
    if (DDAdBlockConfig.shared.master && DDAdBlockConfig.shared.brand) return;
    %orig;
}
%end

#pragma mark - 3. 视频号广告拦截
%hook FinderFeedAdCell
- (void)setAdModel:(id)model {
    if (DDAdBlockConfig.shared.master && DDAdBlockConfig.shared.finder) return;
    %orig;
}
%end

%hook FinderPauseAdView
- (void)showAd {
    if (DDAdBlockConfig.shared.master && DDAdBlockConfig.shared.finder) return;
    %orig;
}
%end

%hook FinderPostRollAd
- (BOOL)shouldShow {
    return !(DDAdBlockConfig.shared.master && DDAdBlockConfig.shared.finder);
}
%end

%hook FinderCommentAdView
- (void)renderAdContent {
    if (DDAdBlockConfig.shared.master && DDAdBlockConfig.shared.finder) return;
    %orig;
}
%end

%hook FinderDetailAdView
- (void)layoutSubviews {
    if (DDAdBlockConfig.shared.master && DDAdBlockConfig.shared.finder) return;
    %orig;
}
%end

#pragma mark - 4. 直播广告拦截
%hook LiveSquareAdCell
- (void)setAdInfo:(id)info {
    if (DDAdBlockConfig.shared.master && DDAdBlockConfig.shared.live) return;
    %orig;
}
%end

%hook LiveFloatingAdView
- (void)showAd {
    if (DDAdBlockConfig.shared.master && DDAdBlockConfig.shared.live) return;
    %orig;
}
%end

%hook LiveBottomAdView
- (void)renderAd {
    if (DDAdBlockConfig.shared.master && DDAdBlockConfig.shared.live) return;
    %orig;
}
%end

%hook LiveCommentAdView
- (void)setAdData:(id)data {
    if (DDAdBlockConfig.shared.master && DDAdBlockConfig.shared.live) return;
    %orig;
}
%end

#pragma mark - 5. 搜索广告拦截（已归位到广告拦截场景）
%hook SearchResultAdCell
- (instancetype)initWithAdData:(id)data {
    if (DDAdBlockConfig.shared.master && DDAdBlockConfig.shared.search) return nil;
    return %orig;
}
%end

%hook SearchSuggestAdItem
- (BOOL)shouldShow {
    return !(DDAdBlockConfig.shared.master && DDAdBlockConfig.shared.search);
}
%end

%hook SearchBrandAdCell
- (void)setAdModel:(id)model {
    if (DDAdBlockConfig.shared.master && DDAdBlockConfig.shared.search) return;
    %orig;
}
%end

#pragma mark - 6. 小程序广告拦截
%hook MiniProgramBannerAdView
- (void)showAd {
    if (DDAdBlockConfig.shared.master && DDAdBlockConfig.shared.miniProgram) return;
    %orig;
}
%end

%hook MiniProgramInterstitialAd
- (void)presentAd {
    if (DDAdBlockConfig.shared.master && DDAdBlockConfig.shared.miniProgram) return;
    %orig;
}
%end

%hook MiniProgramNativeAdView
- (void)renderWithData:(id)data {
    if (DDAdBlockConfig.shared.master && DDAdBlockConfig.shared.miniProgram) return;
    %orig;
}
%end

%hook MiniProgramRewardedAd
- (void)show {
    if (DDAdBlockConfig.shared.master && DDAdBlockConfig.shared.miniProgram) return;
    %orig;
}
%end

#pragma mark - 7. 激励广告快速跳过（进阶拦截）
%hook RewardedVideoAd
- (void)show {
    if (DDAdBlockConfig.shared.master && DDAdBlockConfig.shared.rewardedFastPass) {
        [self skipAd];
        return;
    }
    %orig;
}
%end

#pragma mark - 8. 其他场景广告拦截
%hook SplashAdViewController
- (void)loadAdResource {
    if (DDAdBlockConfig.shared.master) {
        [self dismissViewControllerAnimated:NO completion:nil];
        return;
    }
    %orig;
}
%end

%hook SplashHalfAdViewController
- (void)showAd {
    if (DDAdBlockConfig.shared.master) {
        [self dismiss];
        return;
    }
    %orig;
}
%end

%hook PaymentAdViewController
- (void)viewDidLoad {
    if (DDAdBlockConfig.shared.master) {
        [self dismissViewControllerAnimated:NO completion:nil];
        return;
    }
    %orig;
}
%end

%hook WeChatReadAdView
- (void)showAd {
    if (DDAdBlockConfig.shared.master) return;
    %orig;
}
%end

%hook FindMoreAdView
- (void)layoutSubviews {
    if (DDAdBlockConfig.shared.master) return;
    %orig;
}
%end

%hook ChatTopAdView
- (void)setAdData:(id)data {
    if (DDAdBlockConfig.shared.master) return;
    %orig;
}
%end

// ===== 插件入口 =====
%ctor {
    @autoreleasepool {
        Class pluginsMgrClass = objc_getClass("WCPluginsMgr");
        if (pluginsMgrClass && [pluginsMgrClass respondsToSelector:@selector(sharedInstance)]) {
            [[pluginsMgrClass sharedInstance] registerControllerWithTitle:@"DD广告拦截"
                                                                version:@"1.0.0"
                                                             controller:@"DDAdBlockSettingsViewController"];
        }
    }
}
