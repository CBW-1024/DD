//
//  DDAdBlock.xm  v1.0.7 (8.0.56 头文件适配版，合规缩进)
//  说明：%开头的Logos指令必须顶格，OC代码正常缩进，避免预处理报错
//

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#import <objc/runtime.h>

#pragma mark - 私有类分类声明（仅声明8.0.56头文件确认存在的selector，解决编译报错）
@class WCFinderComment, WCFinderCommentSectionViewModel, WCFinderCommentDetailViewModel;
@class WCFinderDataItem, WCAdFinderInfo;

@interface WCFinderComment ()
- (id)advertisementInfo;
- (id)commentAdImageUrl;
- (id)promotionInfo;
@end

@interface WCFinderCommentSectionViewModel ()
- (id)getFinderCommentWithIndex:(unsigned long long)arg1;
- (BOOL)hasFinderCommentWithIndex:(unsigned long long)arg1;
- (id)commentAtIndex:(unsigned long long)arg1;
- (unsigned long long)numberOfComment;
@end

@interface WCFinderCommentDetailViewModel ()
- (NSMutableArray *)allComments;
@end

@interface WCFinderDataItem ()
- (unsigned long long)adFlag;
@end

@interface WCAdFinderInfo ()
- (BOOL)isValid;
@end

#pragma mark - 配置类（8个开关，默认全关，持久化）
static NSString * const kDDMaster = @"DDAdBlock_Master";
static NSString * const kDDMoments = @"DDAdBlock_Moments";
static NSString * const kDDBrand = @"DDAdBlock_Brand";
static NSString * const kDDFinder = @"DDAdBlock_Finder";
static NSString * const kDDLive = @"DDAdBlock_Live";
static NSString * const kDDMini = @"DDAdBlock_MiniProgram";
static NSString * const kDDSearch = @"DDAdBlock_Search";
static NSString * const kDDReward = @"DDAdBlock_RewardedAdFastPass";

@interface DDAdBlockConfig : NSObject
+ (instancetype)sharedConfig;
@property (assign, nonatomic) BOOL master, moments, brand, finder, live, miniProgram, search, rewardedFastPass;
@end

@implementation DDAdBlockConfig
+ (instancetype)sharedConfig {
    static DDAdBlockConfig *config = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        config = [[DDAdBlockConfig alloc] init];
    });
    return config;
}

- (instancetype)init {
    if (self = [super init]) {
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        if ([ud objectForKey:kDDMaster] == nil) [ud setBool:NO forKey:kDDMaster];
        if ([ud objectForKey:kDDMoments] == nil) [ud setBool:NO forKey:kDDMoments];
        if ([ud objectForKey:kDDBrand] == nil) [ud setBool:NO forKey:kDDBrand];
        if ([ud objectForKey:kDDFinder] == nil) [ud setBool:NO forKey:kDDFinder];
        if ([ud objectForKey:kDDLive] == nil) [ud setBool:NO forKey:kDDLive];
        if ([ud objectForKey:kDDMini] == nil) [ud setBool:NO forKey:kDDMini];
        if ([ud objectForKey:kDDSearch] == nil) [ud setBool:NO forKey:kDDSearch];
        if ([ud objectForKey:kDDReward] == nil) [ud setBool:NO forKey:kDDReward];
        [ud synchronize];
        
        _master = [ud boolForKey:kDDMaster];
        _moments = [ud boolForKey:kDDMoments];
        _brand = [ud boolForKey:kDDBrand];
        _finder = [ud boolForKey:kDDFinder];
        _live = [ud boolForKey:kDDLive];
        _miniProgram = [ud boolForKey:kDDMini];
        _search = [ud boolForKey:kDDSearch];
        _rewardedFastPass = [ud boolForKey:kDDReward];
    }
    return self;
}

#define DD_SETTER(name, key) \
- (void)set##name:(BOOL)value { \
    _##name = value; \
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults]; \
    [ud setBool:value forKey:key]; \
    [ud synchronize]; \
}

DD_SETTER(Master, kDDMaster)
DD_SETTER(Moments, kDDMoments)
DD_SETTER(Brand, kDDBrand)
DD_SETTER(Finder, kDDFinder)
DD_SETTER(Live, kDDLive)
DD_SETTER(MiniProgram, kDDMini)
DD_SETTER(Search, kDDSearch)
DD_SETTER(RewardedFastPass, kDDReward)
@end

static BOOL ddActive(void) {
    return [DDAdBlockConfig sharedConfig].master;
}

#pragma mark - 通用工具（恢复D.txt已验证的WebView拦截逻辑）
static NSString *DDMPHideCSS(void) {
    return @".iframe_ad_container,.comment-ad-container{display:none!important;height:0!important;min-height:0!important;margin:0!important;padding:0!important;overflow:hidden!important;}";
}

static NSString *DDMiniAppHideCSS(void) {
    return @"wx-ad,wx-ad-custom,.wx-ad,.wx-ad-custom{display:none!important;height:0!important;min-height:0!important;max-height:0!important;margin:0!important;padding:0!important;overflow:hidden!important;}";
}

static NSArray<NSString *> *DDBlocklist(void) {
    static NSArray *list;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        list = @[
            @"wxa.wxs.qq.com/tmpl/px/",
            @"wxa.wxs.qq.com/tmpl/lite/",
            @"/cgi-bin/mmbiz-bin/ad",
            @"ad.weixin.qq.com",
            @"wxad",
            @"adunit-",
            @"_ad_",
            @"&adpos=",
            @"mp.weixin.qq.com/mp/getappmsgad"
        ];
    });
    return list;
}

static BOOL ddURLIsAd(NSString *url) {
    if (url.length == 0) return NO;
    for (NSString *sub in DDBlocklist()) {
        if ([url containsString:sub]) return YES;
    }
    return NO;
}

#pragma mark - 1. 朋友圈广告拦截（D.txt已验证，8.0.56兼容）
%hook WCAdvertiseDataHelper
- (void)saveAdPullCompareInfo:(id)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return;
    %orig;
}

- (void)saveAdvertiseMsgXmlDatas {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return;
    %orig;
}

- (void)addAdvertiseDataList:(id)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return;
    %orig;
}

- (void)saveAdvertiseDatas {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return;
    %orig;
}

- (void)tryLoadAdvertiseData {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return;
    %orig;
}

- (BOOL)isAdPreviewExpired:(id)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return YES;
    return %orig;
}
%end

%hook WCTimelineMgr
- (id)getAdvertiseDataByCurMinTime:(unsigned int)arg1 MaxTime:(unsigned int)arg2 checkDataValid:(BOOL)arg3 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return [NSMutableArray array];
    return %orig;
}

- (id)getAdvertiseDataByCurMinTime:(unsigned int)arg1 MaxTime:(unsigned int)arg2 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return [NSMutableArray array];
    return %orig;
}

- (id)getTopAdvertiseDataByTopNumber:(unsigned int)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return [NSMutableArray array];
    return %orig;
}

- (void)onAdPullWithAdDatas:(id)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return;
    %orig;
}

- (void)tryToProcessWithNewAdList:(id)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return;
    %orig;
}
%end

#pragma mark - 2. 公众号广告拦截（D.txt已验证，8.0.56兼容）
%hook BrandTLExptConfig
- (BOOL)isExptNotShowAd {
    if (ddActive() && [DDAdBlockConfig sharedConfig].brand) return YES;
    return %orig;
}
%end

%hook BrandTLCanvasCardMgr
- (BOOL)isAdCardOpen {
    if (ddActive() && [DDAdBlockConfig sharedConfig].brand) return NO;
    return %orig;
}

- (BOOL)isAdRequestOpen {
    if (ddActive() && [DDAdBlockConfig sharedConfig].brand) return NO;
    return %orig;
}

- (void)handleBizAdNotifyNewXml:(id)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].brand) return;
    %orig;
}
%end

%hook BrandAdDataParser
+ (id)adDataItemForContent:(id)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].brand) return nil;
    return %orig;
}

+ (id)adDataItemForMsgWrap:(id)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].brand) return nil;
    return %orig;
}

+ (id)adInfoDicForContent:(id)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].brand) return nil;
    return %orig;
}

+ (id)adInfoDicForMsgWrap:(id)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].brand) return nil;
    return %orig;
}
%end

%hook MMWebViewController
- (BOOL)webView:(id)arg1 shouldStartLoadWithRequest:(id)arg2 navigationType:(long long)arg3 isMainFrame:(BOOL)arg4 navigationAction:(id)arg5 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].brand && !arg4) {
        NSString *url = [[(NSURLRequest *)arg2 URL] absoluteString];
        if (ddURLIsAd(url)) return NO;
    }
    return %orig;
}

- (void)webViewDidFinishLoad:(id)arg1 navigation:(id)arg2 {
    %orig;
    if (!(ddActive() && [DDAdBlockConfig sharedConfig].brand)) return;
    
    WKWebView *webView = nil;
    @try {
        webView = [(id)self valueForKey:@"webView"];
    } @catch (NSException *e) {}
    if (![webView isKindOfClass:[WKWebView class]]) return;
    
    NSString *js = [NSString stringWithFormat:@"(function(){try{var s=document.createElement('style');s.textContent='%@';(document.head||document.documentElement).appendChild(s);}catch(e){}})();", DDMPHideCSS()];
    [webView evaluateJavaScript:js completionHandler:nil];
}
%end

#pragma mark - 3. 视频号广告拦截（8.0.56头文件适配，防闪退）
// 3.1 广告评论判断（仅用8.0.56确认存在的selector）
static BOOL ddFinderCommentIsAd(id comment) {
    if (!comment || ![comment isKindOfClass:NSClassFromString(@"WCFinderComment")]) return NO;
    
    if ([comment respondsToSelector:@selector(advertisementInfo)] && [comment advertisementInfo]) {
        return YES;
    }
    if ([comment respondsToSelector:@selector(promotionInfo)] && [comment promotionInfo]) {
        return YES;
    }
    if ([comment respondsToSelector:@selector(commentAdImageUrl)] && [comment commentAdImageUrl]) {
        return YES;
    }
    return NO;
}

// 3.2 数据层兜底（8.0.56确认存在）
%hook WCFinderComment
- (id)advertisementInfo {
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return nil;
    return %orig;
}

- (id)commentAdImageUrl {
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return nil;
    return %orig;
}

- (id)promotionInfo {
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return nil;
    return %orig;
}
%end

%hook WCFinderDataItem
- (unsigned long long)adFlag {
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return 0;
    return %orig;
}
%end

%hook WCAdFinderInfo
- (BOOL)isValid {
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return NO;
    return %orig;
}
%end

// 3.3 评论列表Section层（8.0.56接口适配，防闪退）
%hook WCFinderCommentSectionViewModel
// 索引访问：广告返回nil，避免cellForRow越界
- (id)getFinderCommentWithIndex:(unsigned long long)index {
    id comment = %orig;
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder && ddFinderCommentIsAd(comment)) {
        return nil;
    }
    return comment;
}

- (id)commentAtIndex:(unsigned long long)index {
    id comment = %orig;
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder && ddFinderCommentIsAd(comment)) {
        return nil;
    }
    return comment;
}

// 存在性判断：广告返回NO
- (BOOL)hasFinderCommentWithIndex:(unsigned long long)index {
    id comment = %orig;
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder && ddFinderCommentIsAd(comment)) {
        return NO;
    }
    return %orig;
}

// 计数同步：扣减广告数量，避免列表行数不匹配
- (unsigned long long)numberOfComment {
    unsigned long long origCount = %orig;
    if (!(ddActive() && [DDAdBlockConfig sharedConfig].finder)) return origCount;
    
    unsigned long long adCount = 0;
    for (unsigned long long i = 0; i < origCount; i++) {
        id comment = %orig;
        if (ddFinderCommentIsAd(comment)) {
            adCount++;
        }
    }
    return origCount - adCount;
}
%end

// 3.4 评论详情页（8.0.56的allComments是NSMutableArray，就地删除广告）
%hook WCFinderCommentDetailViewModel
- (NSMutableArray *)allComments {
    NSMutableArray *orig = %orig;
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder && [orig isKindOfClass:[NSMutableArray class]]) {
        NSMutableIndexSet *adIndexes = [NSMutableIndexSet indexSet];
        [orig enumerateObjectsUsingBlock:^(id comment, NSUInteger idx, BOOL *stop) {
            if (ddFinderCommentIsAd(comment)) {
                [adIndexes addIndex:idx];
            }
        }];
        [orig removeObjectsAtIndexes:adIndexes];
    }
    return orig;
}
%end

#pragma mark - 4. 小程序广告拦截（D.txt已验证，8.0.56兼容）
%hook WAAppTaskSplashADConfig
- (void)handleShowSplashAdCalled:(BOOL)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return;
    %orig;
}
%end

%hook WAJSEventHandler_showSplashAd
- (void)handleJSEvent:(id)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return;
    %orig;
}
%end

%hook WAJSEventHandler_showSplashAdMenu
- (void)handleJSEvent:(id)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return;
    %orig;
}
%end

%hook WAJSEventHandler_adOperateWXData
- (void)handleJSEvent:(id)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return;
    %orig;
}
%end

%hook MagicAdCommonService
- (id)getAdInfoWithPosId:(id)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return nil;
    return %orig;
}

- (id)internalGetAdInfoFromCacheWithPosId:(id)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return nil;
    return %orig;
}

- (void)getAdInfoAsyncWithPosId:(id)arg1 completion:(id)arg2 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return;
    %orig;
}

- (void)getAdInfoAsyncWithPosId:(id)arg1 timeoutMs:(long long)arg2 completion:(id)arg3 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return;
    %orig;
}

- (void)triggerUpdateAdWithPosId:(id)arg1 pullType:(unsigned char)arg2 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return;
    %orig;
}

- (void)updateAdInfoByCGIInstantlyWithPosId:(id)arg1 pullType:(unsigned char)arg2 isDelayPull:(BOOL)arg3 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return;
    %orig;
}
%end

%hook MagicAdCGIMgr
+ (void)getAdsCGIWithPosIds:(id)arg1 successBlock:(id)arg2 failBlock:(id)arg3 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return;
    %orig;
}
%end

%hook MagicAdPushMgrService
- (void)handleAdMsg:(id)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return;
    %orig;
}
%end

%hook WCAdvertisePushService
- (void)handlePushMsg:(id)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return;
    %orig;
}
%end

%hook WAWebViewController
- (BOOL)webView:(id)arg1 shouldStartLoadWithRequest:(id)arg2 navigationType:(long long)arg3 isMainFrame:(BOOL)arg4 navigationAction:(id)arg5 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram && !arg4) {
        NSString *url = [[(NSURLRequest *)arg2 URL] absoluteString];
        if (ddURLIsAd(url)) return NO;
    }
    return %orig;
}

- (void)webViewDidFinishLoad:(id)arg1 navigation:(id)arg2 {
    %orig;
    if (!(ddActive() && [DDAdBlockConfig sharedConfig].miniProgram)) return;
    
    id webView = nil;
    @try {
        webView = [(id)self valueForKey:@"webView"];
    } @catch (NSException *e) {}
    if (![webView respondsToSelector:@selector(evaluateJavaScript:completionHandler:)]) return;
    
    NSString *js = [NSString stringWithFormat:@"(function(){try{var s=document.createElement('style');s.textContent='%@';(document.head||document.documentElement).appendChild(s);}catch(e){}})();", DDMiniAppHideCSS()];
    [webView evaluateJavaScript:js completionHandler:nil];
}
%end

#pragma mark - 5. 直播广告拦截（D.txt已验证，8.0.56兼容）
%hook WCFinderAdCountdownBannerView
- (void)setupSubviews {
    if (ddActive() && [DDAdBlockConfig sharedConfig].live) return;
    %orig;
}

- (void)startCountdown {
    if (ddActive() && [DDAdBlockConfig sharedConfig].live) return;
    %orig;
}

- (void)updateUIWithTime:(long long)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].live) return;
    %orig;
}

- (BOOL)adHasPlayOver {
    if (ddActive() && [DDAdBlockConfig sharedConfig].live) return YES;
    return %orig;
}
%end

%hook WCFinderLiveHomePageViewController
- (void)onAdSectionView:(id)arg1 selectElementVM:(id)arg2 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].live) return;
    %orig;
}
%end

#pragma mark - 6. 搜索广告拦截
%hook WCAdSearchH5Info
- (BOOL)isValid {
    if (ddActive() && [DDAdBlockConfig sharedConfig].search) return NO;
    return %orig;
}

+ (id)fromXML:(struct XmlReaderNode_t *)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].search) return nil;
    return %orig;
}
%end

#pragma mark - 7. 激励广告快速跳过
%hook WCFinderRewardAdViewController
- (void)viewDidAppear:(BOOL)animated {
    if (ddActive() && [DDAdBlockConfig sharedConfig].rewardedFastPass) {
        [self dismissViewControllerAnimated:YES completion:nil];
        return;
    }
    %orig;
}
%end

#pragma mark - 8. 广告上报抑制
%hook WCAdvertiseStatMgr
- (id)getAdvertiseInfoForItem:(id)arg1 {
    if (ddActive()) return nil;
    return %orig;
}

- (void)logHeadImageH5:(id)arg1 {
    if (ddActive()) return;
    %orig;
}

- (void)logADBrandProfile:(id)arg1 {
    if (ddActive()) return;
    %orig;
}

- (void)logADFloatView:(id)arg1 {
    if (ddActive()) return;
    %orig;
}

- (void)logADPoiH5:(id)arg1 {
    if (ddActive()) return;
    %orig;
}

- (void)logADH5:(id)arg1 withUserInfo:(id)arg2 reportType:(unsigned long long)arg3 {
    if (ddActive()) return;
    %orig;
}

- (void)logADCommentLog:(id)arg1 {
    if (ddActive()) return;
    %orig;
}

- (void)logADBodyLog:(id)arg1 {
    if (ddActive()) return;
    %orig;
}

- (void)reportAllFeedsADLog {
    if (ddActive()) return;
    %orig;
}
%end

#pragma mark - 设置界面
@interface WCTableViewManager : NSObject
- (id)initWithFrame:(CGRect)frame style:(NSInteger)style;
@property (nonatomic, readonly) UITableView *tableView;
- (void)clearAllSection;
- (void)addSection:(id)section;
- (void)reloadTableView;
@end

@interface WCTableViewSectionManager : NSObject
+ (id)sectionWithHeader:(NSString *)header;
- (void)addCell:(id)cell;
@end

@interface WCTableViewCellManager : NSObject
+ (id)switchCellForSel:(SEL)selector target:(id)target title:(id)title on:(BOOL)on;
@end

@interface DDAdBlockSettingsViewController : UIViewController
@property (nonatomic, strong) WCTableViewManager *tableViewManager;
@end

@implementation DDAdBlockSettingsViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"DD广告拦截";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
    Class managerCls = %c(WCTableViewManager);
    self.tableViewManager = [[managerCls alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableViewManager.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableViewManager.tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentAutomatic;
    [self.view addSubview:self.tableViewManager.tableView];
    
    [self buildTable];
}

- (void)buildTable {
    [self.tableViewManager clearAllSection];
    Class sectionCls = %c(WCTableViewSectionManager);
    Class cellCls = %c(WCTableViewCellManager);
    DDAdBlockConfig *cfg = [DDAdBlockConfig sharedConfig];
    
    WCTableViewSectionManager *mainSection = [sectionCls sectionWithHeader:@"广告拦截场景"];
    [mainSection addCell:[cellCls switchCellForSel:@selector(onMasterSwitch:) target:self title:@"启用广告拦截" on:cfg.master]];
    [mainSection addCell:[cellCls switchCellForSel:@selector(onMomentsSwitch:) target:self title:@"屏蔽朋友圈广告" on:cfg.moments]];
    [mainSection addCell:[cellCls switchCellForSel:@selector(onBrandSwitch:) target:self title:@"屏蔽公众号广告" on:cfg.brand]];
    [mainSection addCell:[cellCls switchCellForSel:@selector(onFinderSwitch:) target:self title:@"屏蔽视频号广告" on:cfg.finder]];
    [mainSection addCell:[cellCls switchCellForSel:@selector(onLiveSwitch:) target:self title:@"屏蔽直播广告" on:cfg.live]];
    [mainSection addCell:[cellCls switchCellForSel:@selector(onSearchSwitch:) target:self title:@"屏蔽搜索广告" on:cfg.search]];
    [mainSection addCell:[cellCls switchCellForSel:@selector(onMiniProgramSwitch:) target:self title:@"屏蔽小程序广告" on:cfg.miniProgram]];
    [self.tableViewManager addSection:mainSection];
    
    WCTableViewSectionManager *advSection = [sectionCls sectionWithHeader:@"进阶拦截"];
    [advSection addCell:[cellCls switchCellForSel:@selector(onRewardedSwitch:) target:self title:@"激励广告快速跳过" on:cfg.rewardedFastPass]];
    [self.tableViewManager addSection:advSection];
    
    [self.tableViewManager reloadTableView];
}

- (void)onMasterSwitch:(UISwitch *)sender {
    [DDAdBlockConfig sharedConfig].master = sender.isOn;
    [self buildTable];
}

- (void)onMomentsSwitch:(UISwitch *)sender {
    [DDAdBlockConfig sharedConfig].moments = sender.isOn;
}

- (void)onBrandSwitch:(UISwitch *)sender {
    [DDAdBlockConfig sharedConfig].brand = sender.isOn;
}

- (void)onFinderSwitch:(UISwitch *)sender {
    [DDAdBlockConfig sharedConfig].finder = sender.isOn;
}

- (void)onLiveSwitch:(UISwitch *)sender {
    [DDAdBlockConfig sharedConfig].live = sender.isOn;
}

- (void)onSearchSwitch:(UISwitch *)sender {
    [DDAdBlockConfig sharedConfig].search = sender.isOn;
}

- (void)onMiniProgramSwitch:(UISwitch *)sender {
    [DDAdBlockConfig sharedConfig].miniProgram = sender.isOn;
}

- (void)onRewardedSwitch:(UISwitch *)sender {
    [DDAdBlockConfig sharedConfig].rewardedFastPass = sender.isOn;
}
@end

#pragma mark - 插件注册
%ctor {
    @autoreleasepool {
        Class mgrClass = NSClassFromString(@"WCPluginsMgr");
        if (mgrClass) {
            id mgr = [mgrClass sharedInstance];
            if ([mgr respondsToSelector:@selector(registerControllerWithTitle:version:controller:)]) {
                [mgr registerControllerWithTitle:@"DD广告拦截"
                                       version:@"1.0.7"
                                    controller:@"DDAdBlockSettingsViewController"];
            }
        }
    }
}
