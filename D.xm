//
//  DDAdBlock.xm
//  DD广告拦截 v1.0.0（最终版，仅更新公众号/小程序 WebView 拦截）
//
//  特点：
//  - 每个广告模块完全自包含（开关判断 + 辅助函数）
//  - 配置单例全局共享
//  - 不依赖私有头文件，仅运行时查找类
//  - 公众号/小程序采用去广告.xm 的最新 WebView 拦截方案（URL黑名单 + 注入JS + DOM sweep）
//

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#import <objc/runtime.h>

// ============================================================================
//  声明微信私有类（供设置界面及插件注册使用）
// ============================================================================

@interface WCTableViewManager : NSObject
- (UITableView *)getTableView;
- (void)clearAllSection;
- (void)addSection:(id)section;
- (void)reloadTableView;
- (instancetype)initWithFrame:(CGRect)frame style:(UITableViewStyle)style;
@end

@interface WCTableViewSectionManager : NSObject
+ (instancetype)defaultSection;
- (void)addCell:(id)cell;
@property (nonatomic, copy) NSString *headerTitle;
@property (nonatomic, copy) NSString *footerTitle;
@end

@interface WCTableViewCellManager : NSObject
+ (id)switchCellForSel:(SEL)sel target:(id)target title:(id)title on:(BOOL)on;
@end

@interface WCPluginsMgr : NSObject
+ (instancetype)sharedInstance;
- (void)registerControllerWithTitle:(NSString *)title version:(NSString *)version controller:(NSString *)controllerName;
@end

// ============================================================================
//  全局配置类（开关持久化）
// ============================================================================

static NSString * const kMaster           = @"DDAdBlock_Master";
static NSString * const kMoments          = @"DDAdBlock_Moments";
static NSString * const kBrand            = @"DDAdBlock_Brand";
static NSString * const kFinder           = @"DDAdBlock_Finder";
static NSString * const kLive             = @"DDAdBlock_Live";
static NSString * const kMiniProgram      = @"DDAdBlock_MiniProgram";
static NSString * const kSearch           = @"DDAdBlock_Search";
static NSString * const kRewardedFastPass = @"DDAdBlock_RewardedFastPass";

@interface DDAdBlockConfig : NSObject
+ (instancetype)sharedConfig;
@property (assign, nonatomic) BOOL master;
@property (assign, nonatomic) BOOL moments;
@property (assign, nonatomic) BOOL brand;
@property (assign, nonatomic) BOOL finder;
@property (assign, nonatomic) BOOL live;
@property (assign, nonatomic) BOOL miniProgram;
@property (assign, nonatomic) BOOL search;
@property (assign, nonatomic) BOOL rewardedFastPass;
@end

@implementation DDAdBlockConfig {
    BOOL _master;
    BOOL _moments;
    BOOL _brand;
    BOOL _finder;
    BOOL _live;
    BOOL _miniProgram;
    BOOL _search;
    BOOL _rewardedFastPass;
}

+ (instancetype)sharedConfig {
    static DDAdBlockConfig *config = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        config = [[DDAdBlockConfig alloc] init];
    });
    return config;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        if ([ud objectForKey:kMaster] == nil)           [ud setBool:NO forKey:kMaster];
        if ([ud objectForKey:kMoments] == nil)          [ud setBool:NO forKey:kMoments];
        if ([ud objectForKey:kBrand] == nil)            [ud setBool:NO forKey:kBrand];
        if ([ud objectForKey:kFinder] == nil)           [ud setBool:NO forKey:kFinder];
        if ([ud objectForKey:kLive] == nil)             [ud setBool:NO forKey:kLive];
        if ([ud objectForKey:kMiniProgram] == nil)      [ud setBool:NO forKey:kMiniProgram];
        if ([ud objectForKey:kSearch] == nil)           [ud setBool:NO forKey:kSearch];
        if ([ud objectForKey:kRewardedFastPass] == nil) [ud setBool:NO forKey:kRewardedFastPass];
        [ud synchronize];

        _master           = [ud boolForKey:kMaster];
        _moments          = [ud boolForKey:kMoments];
        _brand            = [ud boolForKey:kBrand];
        _finder           = [ud boolForKey:kFinder];
        _live             = [ud boolForKey:kLive];
        _miniProgram      = [ud boolForKey:kMiniProgram];
        _search           = [ud boolForKey:kSearch];
        _rewardedFastPass = [ud boolForKey:kRewardedFastPass];
    }
    return self;
}

- (void)setMaster:(BOOL)value {
    _master = value;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setBool:value forKey:kMaster];
    [ud synchronize];
}
- (void)setMoments:(BOOL)value {
    _moments = value;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setBool:value forKey:kMoments];
    [ud synchronize];
}
- (void)setBrand:(BOOL)value {
    _brand = value;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setBool:value forKey:kBrand];
    [ud synchronize];
}
- (void)setFinder:(BOOL)value {
    _finder = value;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setBool:value forKey:kFinder];
    [ud synchronize];
}
- (void)setLive:(BOOL)value {
    _live = value;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setBool:value forKey:kLive];
    [ud synchronize];
}
- (void)setMiniProgram:(BOOL)value {
    _miniProgram = value;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setBool:value forKey:kMiniProgram];
    [ud synchronize];
}
- (void)setSearch:(BOOL)value {
    _search = value;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setBool:value forKey:kSearch];
    [ud synchronize];
}
- (void)setRewardedFastPass:(BOOL)value {
    _rewardedFastPass = value;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setBool:value forKey:kRewardedFastPass];
    [ud synchronize];
}

@end

// ============================================================================
//  1. 朋友圈广告模块
// ============================================================================

static inline BOOL momentsEnabled(void) {
    return [DDAdBlockConfig sharedConfig].master && [DDAdBlockConfig sharedConfig].moments;
}

%hook WCAdvertiseDataHelper
- (void)saveAdPullCompareInfo:(id)arg1 {
    if (momentsEnabled()) return;
    %orig;
}
- (void)saveAdvertiseMsgXmlDatas {
    if (momentsEnabled()) return;
    %orig;
}
- (void)addAdvertiseDataList:(id)arg1 {
    if (momentsEnabled()) return;
    %orig;
}
- (void)saveAdvertiseDatas {
    if (momentsEnabled()) return;
    %orig;
}
- (void)tryLoadAdvertiseData {
    if (momentsEnabled()) return;
    %orig;
}
- (BOOL)isAdPreviewExpired:(id)arg1 {
    if (momentsEnabled()) return YES;
    return %orig;
}
%end

%hook WCTimelineMgr
- (id)getAdvertiseDataByCurMinTime:(unsigned int)arg1 MaxTime:(unsigned int)arg2 checkDataValid:(BOOL)arg3 {
    if (momentsEnabled()) return [NSMutableArray array];
    return %orig;
}
- (id)getAdvertiseDataByCurMinTime:(unsigned int)arg1 MaxTime:(unsigned int)arg2 {
    if (momentsEnabled()) return [NSMutableArray array];
    return %orig;
}
- (id)getTopAdvertiseDataByTopNumber:(unsigned int)arg1 {
    if (momentsEnabled()) return [NSMutableArray array];
    return %orig;
}
- (void)onAdPullWithAdDatas:(id)arg1 {
    if (momentsEnabled()) return;
    %orig;
}
- (void)tryToProcessWithNewAdList:(id)arg1 {
    if (momentsEnabled()) return;
    %orig;
}
%end

// ============================================================================
//  2. 公众号广告模块（新方案：注入 WKUserScript + URL 拦截 + DOM 清理）
// ============================================================================

static inline BOOL brandEnabled(void) {
    return [DDAdBlockConfig sharedConfig].master && [DDAdBlockConfig sharedConfig].brand;
}

// 公众号专用 CSS（隐藏 iframe/评论区广告等）
static NSString *DDAdBlockMPHideCSS(void) {
    return @".iframe_ad_container,.iframe_adv_ad_container,.comment-ad-container,"
           @"li.cidad_comment_constant_key,#cidad_comment_constant_key,"
           @".adv_keyword_search,.ad_control-tips"
           @"{display:none!important;height:0!important;min-height:0!important;"
           @"margin:0!important;padding:0!important;overflow:hidden!important;}";
}

static NSString *DDAdBlockMPHideParentCSS(void) {
    return @"div:has(> .iframe_ad_container),li:has(> .comment-ad-container)"
           @"{display:none!important;height:0!important;}";
}

// 注入 JS（包含 CSS + 周期性 DOM 扫描 + MutationObserver）
static NSString *DDAdBlockInjectJS(void) {
    return [NSString stringWithFormat:
        @"(function(){try{"
        @"if(!document.getElementById('__dd_adblock')){"
        @"var s=document.createElement('style');s.id='__dd_adblock';"
        @"s.textContent='%@'+'%@';"
        @"(document.head||document.documentElement).appendChild(s);}"
        @"var sweep=function(){try{Array.prototype.forEach.call("
        @"document.querySelectorAll('.iframe_ad_container,.comment-ad-container'),"
        @"function(e){var p=e.parentElement,n=0;"
        @"while(p&&n<3){if(p.tagName==='LI'||(p.className&&/comment-ad|discuss_media/.test(p.className))){"
        @"p.style.setProperty('display','none','important');break;}p=p.parentElement;n++;}});}catch(e){}};"
        @"sweep();"
        @"if(!window.__dd_ob&&window.MutationObserver){"
        @"var t=null;window.__dd_ob=new MutationObserver(function(){"
        @"if(t)return;t=setTimeout(function(){t=null;sweep();},300);});"
        @"window.__dd_ob.observe(document.documentElement,{childList:true,subtree:true});}"
        @"}catch(e){}})();",
        DDAdBlockMPHideCSS(), DDAdBlockMPHideParentCSS()];
}

// URL 黑名单（覆盖公众号/小程序广告素材、联盟广告等）
static NSArray<NSString *> *DDAdBlockURLBlocklist(void) {
    static NSArray *list;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        list = @[
            @"wxa.wxs.qq.com/tmpl/px/",
            @"wxa.wxs.qq.com/tmpl/lite/",
            @"support.weixin.qq.com/cgi-bin/mmsupport-bin/",
            @"wxapp.tc.qq.com/ad/",
            @"cpro.baidu.com",
            @"pos.baidu.com",
            @"go.mobile.qq.com/ad",
            @"/cgi-bin/mmbiz-bin/ad",
            @"ad.weixin.qq.com",
            @"wxad",
            @"adunit-",
            @"_ad_",
            @"&adpos=",
        ];
    });
    return list;
}

static BOOL ddURLIsAd(NSString *url) {
    if (url.length == 0) return NO;
    for (NSString *sub in DDAdBlockURLBlocklist()) {
        if ([url containsString:sub]) return YES;
    }
    return NO;
}

// 原生数据层拦截（保留原实现）
%hook BrandTLExptConfig
- (BOOL)isExptNotShowAd {
    if (brandEnabled()) return YES;
    return %orig;
}
%end

%hook BrandTLCanvasCardMgr
- (BOOL)isAdCardOpen {
    if (brandEnabled()) return NO;
    return %orig;
}
- (BOOL)isAdRequestOpen {
    if (brandEnabled()) return NO;
    return %orig;
}
- (void)handleBizAdNotifyNewXml:(id)arg1 {
    if (brandEnabled()) return;
    %orig;
}
%end

%hook BrandAdDataParser
+ (id)adDataItemForContent:(id)arg1 {
    if (brandEnabled()) return nil;
    return %orig;
}
+ (id)adDataItemForMsgWrap:(id)arg1 {
    if (brandEnabled()) return nil;
    return %orig;
}
+ (id)adInfoDicForContent:(id)arg1 {
    if (brandEnabled()) return nil;
    return %orig;
}
+ (id)adInfoDicForMsgWrap:(id)arg1 {
    if (brandEnabled()) return nil;
    return %orig;
}
%end

// MMWebViewController WebView 拦截
%hook MMWebViewController
- (id)webViewUserScriptsForConfiguration {
    id scripts = %orig;
    if (!brandEnabled()) return scripts;
    NSMutableArray *arr = [scripts isKindOfClass:[NSArray class]]
        ? [(NSArray *)scripts mutableCopy]
        : [NSMutableArray array];
    WKUserScript *us = [[WKUserScript alloc] initWithSource:DDAdBlockInjectJS()
                                              injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                           forMainFrameOnly:NO];
    [arr addObject:us];
    return arr;
}

- (BOOL)webView:(id)arg1 shouldStartLoadWithRequest:(id)arg2 navigationType:(long long)arg3 isMainFrame:(BOOL)arg4 navigationAction:(id)arg5 {
    if (brandEnabled() && !arg4) {
        NSString *u = [[(NSURLRequest *)arg2 URL] absoluteString];
        if ([u containsString:@"wxa.wxs.qq.com"] && [u containsString:@"/tmpl/px/"]) {
            return NO;
        }
        if (ddURLIsAd(u)) {
            return NO;
        }
    }
    return %orig;
}

- (void)webViewDidFinishLoad:(id)arg1 navigation:(id)arg2 {
    %orig;
    if (!brandEnabled()) return;
    WKWebView *wv = nil;
    @try {
        wv = [(id)self valueForKey:@"webView"];
    } @catch (__unused NSException *e) {}
    if (![wv isKindOfClass:[WKWebView class]]) return;
    [wv evaluateJavaScript:DDAdBlockInjectJS() completionHandler:nil];
}
%end

// ============================================================================
//  3. 视频号广告模块（含辅助工具 ddViewSetHidden）
// ============================================================================

static inline BOOL finderEnabled(void) {
    return [DDAdBlockConfig sharedConfig].master && [DDAdBlockConfig sharedConfig].finder;
}

// 辅助：安全设置 hidden（仅此模块使用）
static void ddViewSetHidden(id view, BOOL hidden) {
    if (!view) return;
    SEL sel = @selector(setHidden:);
    if (class_respondsToSelector([(id)view class], sel)) {
        void (*imp)(id, SEL, BOOL) = (void (*)(id, SEL, BOOL))[(id)view methodForSelector:sel];
        if (imp) imp((id)view, sel, hidden);
    }
}

// 评论区广告
%hook WCFinderComment
- (id)advertisementInfo {
    if (finderEnabled()) return nil;
    return %orig;
}
- (id)commentAdImageUrl {
    if (finderEnabled()) return nil;
    return %orig;
}
- (id)promotionInfo {
    if (finderEnabled()) return nil;
    return %orig;
}
%end

%hook WCFinderDataItem
- (unsigned long long)adFlag {
    if (finderEnabled()) return 0;
    return %orig;
}
%end

%hook WCAdFinderInfo
- (BOOL)isValid {
    if (finderEnabled()) return NO;
    return %orig;
}
%end

%hook WCFinderCommentAdTableViewCell
- (void)updateWithModel:(id)arg1 width:(double)arg2 {
    if (finderEnabled()) {
        %orig;
        ddViewSetHidden((id)self, YES);
        return;
    }
    %orig;
}
- (double)sectionHeightWith:(id)arg1 width:(double)arg2 halfScreenHeight:(double)arg3 {
    if (finderEnabled()) return 0.0;
    return %orig;
}
- (double)heightForMediaWithRatio:(double)arg1 maxHeightPercentage:(double)arg2 minArea:(double)arg3 {
    if (finderEnabled()) return 0.0;
    return %orig;
}
- (void)updatePlayerViewWithCommentInfo:(id)arg1 videoInfo:(id)arg2 {
    if (finderEnabled()) return;
    %orig;
}
- (void)updateImageViewWithCommentImageInfo:(id)arg1 imgInfo:(id)arg2 {
    if (finderEnabled()) return;
    %orig;
}
- (void)clickADContentActionWithArea:(NSInteger)arg1 {
    if (finderEnabled()) return;
    %orig;
}
- (id)commentAdReportDictWithReportScene:(NSInteger)arg1 {
    if (finderEnabled()) return nil;
    return %orig;
}
- (BOOL)canReportWithReportScene:(NSInteger)arg1 {
    if (finderEnabled()) return NO;
    return %orig;
}
%end

%hook WCFinderCommentDetailViewController
- (void)checkCommentAdPlayerExposeStateIfNeeded {
    if (finderEnabled()) return;
    %orig;
}
- (void)reportCommentAd:(id)arg1 withReportScene:(NSInteger)arg2 {
    if (finderEnabled()) return;
    %orig;
}
- (void)reportCommentAdIfNeededWithReportScene:(NSInteger)arg2 {
    if (finderEnabled()) return;
    %orig;
}
- (void)_configADCellReportBehavior:(id)arg1 comment:(id)arg2 {
    if (finderEnabled()) return;
    %orig;
}
- (void)commentAdCell:(id)arg1 clickFeedbackButton:(id)arg2 atSection:(NSInteger)arg3 {
    if (finderEnabled()) return;
    %orig;
}
- (void)commentAdCell:(id)arg1 longPressAtSection:(NSInteger)arg3 {
    if (finderEnabled()) return;
    %orig;
}
%end

// 视频流广告（刷到的广告视频）
%hook WCFinderDataItem
- (BOOL)isHardAdFeed {
    if (finderEnabled()) return NO;
    return %orig;
}
- (BOOL)isHardAdLiveFeed {
    if (finderEnabled()) return NO;
    return %orig;
}
- (BOOL)isFromAdsStream {
    if (finderEnabled()) return NO;
    return %orig;
}
- (void)setIsFromAdsStream:(BOOL)arg1 {
    if (finderEnabled()) {
        %orig(NO);
        return;
    }
    %orig;
}
- (id)jumpInfoContainer {
    if (finderEnabled()) return nil;
    return %orig;
}
- (id)postJumpInfoContainer {
    if (finderEnabled()) return nil;
    return %orig;
}
- (id)adLiveCoverUrl {
    if (finderEnabled()) return nil;
    return %orig;
}
- (id)adsParams {
    if (finderEnabled()) return nil;
    return %orig;
}
%end

// ============================================================================
//  4. 直播广告模块
// ============================================================================

static inline BOOL liveEnabled(void) {
    return [DDAdBlockConfig sharedConfig].master && [DDAdBlockConfig sharedConfig].live;
}

%hook WCFinderAdCountdownBannerView
- (void)setupSubviews {
    if (liveEnabled()) return;
    %orig;
}
- (void)startCountdown {
    if (liveEnabled()) return;
    %orig;
}
- (void)updateUIWithTime:(long long)arg1 {
    if (liveEnabled()) return;
    %orig;
}
- (BOOL)adHasPlayOver {
    if (liveEnabled()) return YES;
    return %orig;
}
%end

%hook WCFinderLiveHomePageViewController
- (void)onAdSectionView:(id)arg1 selectElementVM:(id)arg2 {
    if (liveEnabled()) return;
    %orig;
}
%end

// ============================================================================
//  5. 搜索广告模块
// ============================================================================

static inline BOOL searchEnabled(void) {
    return [DDAdBlockConfig sharedConfig].master && [DDAdBlockConfig sharedConfig].search;
}

%hook WCAdSearchH5Info
- (BOOL)isValid {
    if (searchEnabled()) return NO;
    return %orig;
}
+ (id)fromXML:(struct XmlReaderNode_t *)arg1 {
    if (searchEnabled()) return nil;
    return %orig;
}
%end

// ============================================================================
//  6. 小程序广告模块（新方案：原生层拦截 + WebView URL 黑名单 + DOM 隐藏）
// ============================================================================

static inline BOOL miniProgramEnabled(void) {
    return [DDAdBlockConfig sharedConfig].master && [DDAdBlockConfig sharedConfig].miniProgram;
}

// 小程序专用 CSS（隐藏 <wx-ad> 等原生组件）
static NSString *DDAdBlockMiniAppHideCSS(void) {
    return @"wx-ad,wx-ad-custom,ad,ad-custom,.wx-ad,.wx-ad-custom"
           @"{display:none!important;height:0!important;min-height:0!important;"
           @"max-height:0!important;margin:0!important;padding:0!important;"
           @"overflow:hidden!important;}";
}

// 小程序注入 JS（含 CSS + DOM 扫描 + MutationObserver）
static NSString *DDAdBlockMiniAppInjectJS(void) {
    return [NSString stringWithFormat:
        @"(function(){try{"
        @"if(!document.getElementById('__dd_adblock_wa')){"
        @"var s=document.createElement('style');s.id='__dd_adblock_wa';"
        @"s.textContent='%@';"
        @"(document.head||document.documentElement).appendChild(s);}"
        @"var sweep=function(){try{Array.prototype.forEach.call("
        @"document.querySelectorAll('wx-ad,wx-ad-custom,.wx-ad,.wx-ad-custom'),"
        @"function(e){e.style.setProperty('display','none','important');"
        @"e.style.setProperty('height','0','important');"
        @"e.style.setProperty('max-height','0','important');});}catch(e){}};"
        @"sweep();"
        @"if(!window.__dd_ob_wa&&window.MutationObserver){"
        @"var t=null;window.__dd_ob_wa=new MutationObserver(function(){"
        @"if(t)return;t=setTimeout(function(){t=null;sweep();},300);});"
        @"window.__dd_ob_wa.observe(document.documentElement,{childList:true,subtree:true});}"
        @"}catch(e){}})();",
        DDAdBlockMiniAppHideCSS()];
}

// 原生层拦截（保留原实现）
%hook WAAppTaskSplashADConfig
- (void)handleShowSplashAdCalled:(BOOL)arg1 {
    if (miniProgramEnabled()) return;
    %orig;
}
%end

%hook WAJSEventHandler_showSplashAd
- (void)handleJSEvent:(id)arg1 {
    if (miniProgramEnabled()) return;
    %orig;
}
%end

%hook WAJSEventHandler_showSplashAdMenu
- (void)handleJSEvent:(id)arg1 {
    if (miniProgramEnabled()) return;
    %orig;
}
%end

%hook WAJSEventHandler_adOperateWXData
- (void)handleJSEvent:(id)arg1 {
    if (miniProgramEnabled()) return;
    %orig;
}
%end

%hook MagicAdCommonService
- (id)getAdInfoWithPosId:(id)arg1 {
    if (miniProgramEnabled()) return nil;
    return %orig;
}
- (id)internalGetAdInfoFromCacheWithPosId:(id)arg1 {
    if (miniProgramEnabled()) return nil;
    return %orig;
}
- (void)getAdInfoAsyncWithPosId:(id)arg1 completion:(id)arg2 {
    if (miniProgramEnabled()) return;
    %orig;
}
- (void)getAdInfoAsyncWithPosId:(id)arg1 timeoutMs:(long long)arg2 completion:(id)arg3 {
    if (miniProgramEnabled()) return;
    %orig;
}
- (void)triggerUpdateAdWithPosId:(id)arg1 pullType:(unsigned char)arg2 {
    if (miniProgramEnabled()) return;
    %orig;
}
- (void)updateAdInfoByCGIInstantlyWithPosId:(id)arg1 pullType:(unsigned char)arg2 isDelayPull:(BOOL)arg3 {
    if (miniProgramEnabled()) return;
    %orig;
}
%end

%hook MagicAdCGIMgr
+ (void)getAdsCGIWithPosIds:(id)arg1 successBlock:(id)arg2 failBlock:(id)arg3 {
    if (miniProgramEnabled()) return;
    %orig;
}
%end

%hook MagicAdPushMgrService
- (void)handleAdMsg:(id)arg1 {
    if (miniProgramEnabled()) return;
    %orig;
}
%end

%hook WCAdvertisePushService
- (void)handlePushMsg:(id)arg1 {
    if (miniProgramEnabled()) return;
    %orig;
}
%end

// WAWebViewController WebView 拦截
%hook WAWebViewController
- (void)webViewDidFinishLoad:(id)arg1 navigation:(id)arg2 {
    %orig;
    if (!miniProgramEnabled()) return;
    id wv = nil;
    @try {
        wv = [(id)self valueForKey:@"webView"];
    } @catch (__unused NSException *e) {}
    if (![wv respondsToSelector:@selector(evaluateJavaScript:completionHandler:)]) return;
    [wv evaluateJavaScript:DDAdBlockMiniAppInjectJS() completionHandler:nil];
}

- (BOOL)webView:(id)arg1 shouldStartLoadWithRequest:(id)arg2 navigationType:(long long)arg3 isMainFrame:(BOOL)arg4 navigationAction:(id)arg5 {
    if (miniProgramEnabled() && !arg4) {
        NSString *u = [[(NSURLRequest *)arg2 URL] absoluteString];
        if (ddURLIsAd(u)) {
            return NO;
        }
    }
    return %orig;
}
%end

// ============================================================================
//  7. 激励广告快速跳过模块
// ============================================================================

static inline BOOL rewardedEnabled(void) {
    return [DDAdBlockConfig sharedConfig].master && [DDAdBlockConfig sharedConfig].rewardedFastPass;
}

%hook WCFinderRewardAdViewController
- (void)viewDidAppear:(BOOL)arg1 {
    if (rewardedEnabled()) {
        [(id)self dismissViewControllerAnimated:YES completion:nil];
        return;
    }
    %orig;
}
%end

// ============================================================================
//  8. 广告上报抑制（全局，不受子开关影响，仅依赖 master）
// ============================================================================

static inline BOOL reportEnabled(void) {
    return [DDAdBlockConfig sharedConfig].master;
}

%hook WCAdvertiseStatMgr
- (id)getAdvertiseInfoForItem:(id)arg1 {
    if (reportEnabled()) return nil;
    return %orig;
}
- (void)logHeadImageH5:(id)arg1 {
    if (reportEnabled()) return;
    %orig;
}
- (void)logADBrandProfile:(id)arg1 {
    if (reportEnabled()) return;
    %orig;
}
- (void)logADFloatView:(id)arg1 {
    if (reportEnabled()) return;
    %orig;
}
- (void)logADPoiH5:(id)arg1 {
    if (reportEnabled()) return;
    %orig;
}
- (void)logADH5:(id)arg1 withUserInfo:(id)arg2 reportType:(unsigned long long)arg3 {
    if (reportEnabled()) return;
    %orig;
}
- (void)logADCommentLog:(id)arg1 {
    if (reportEnabled()) return;
    %orig;
}
- (void)logADBodyLog:(id)arg1 {
    if (reportEnabled()) return;
    %orig;
}
- (void)reportAllFeedsADLog {
    if (reportEnabled()) return;
    %orig;
}
%end

// ============================================================================
//  9. 设置界面
// ============================================================================

@interface DDAdBlockSettingsViewController : UIViewController
@property (nonatomic, strong) WCTableViewManager *tableViewManager;
@end

@implementation DDAdBlockSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"DD广告拦截";
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    Class mgrCls = NSClassFromString(@"WCTableViewManager");
    _tableViewManager = [[mgrCls alloc] initWithFrame:self.view.bounds
                                                style:UITableViewStyleInsetGrouped];
    UITableView *tableView = [_tableViewManager getTableView];
    tableView.frame = self.view.bounds;
    tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentAutomatic;
    [self.view addSubview:tableView];

    [self buildSections];
}

- (void)buildSections {
    Class sectionCls = NSClassFromString(@"WCTableViewSectionManager");
    DDAdBlockConfig *cfg = [DDAdBlockConfig sharedConfig];

    [_tableViewManager clearAllSection];

    WCTableViewSectionManager *secMain = [sectionCls defaultSection];
    secMain.headerTitle = @"广告屏蔽开关";
    [secMain addCell:[self switchCellWithTitle:@"启用广告拦截" on:cfg.master action:@selector(onMasterSwitch:)]];
    [secMain addCell:[self switchCellWithTitle:@"屏蔽朋友圈广告" on:cfg.moments action:@selector(onMomentsSwitch:)]];
    [secMain addCell:[self switchCellWithTitle:@"屏蔽公众号广告" on:cfg.brand action:@selector(onBrandSwitch:)]];
    [secMain addCell:[self switchCellWithTitle:@"屏蔽视频号广告" on:cfg.finder action:@selector(onFinderSwitch:)]];
    [secMain addCell:[self switchCellWithTitle:@"屏蔽直播广告" on:cfg.live action:@selector(onLiveSwitch:)]];
    [secMain addCell:[self switchCellWithTitle:@"屏蔽搜索广告" on:cfg.search action:@selector(onSearchSwitch:)]];
    [secMain addCell:[self switchCellWithTitle:@"屏蔽小程序广告" on:cfg.miniProgram action:@selector(onMiniProgramSwitch:)]];
    [_tableViewManager addSection:secMain];

    WCTableViewSectionManager *secAdv = [sectionCls defaultSection];
    secAdv.headerTitle = @"进阶拦截";
    secAdv.footerTitle = @"开启后，激励广告将自动快速跳过（无需等待）";
    [secAdv addCell:[self switchCellWithTitle:@"激励广告快速跳过" on:cfg.rewardedFastPass action:@selector(onRewardedSwitch:)]];
    [_tableViewManager addSection:secAdv];

    [_tableViewManager reloadTableView];
}

- (id)switchCellWithTitle:(NSString *)title on:(BOOL)on action:(SEL)action {
    Class cellCls = NSClassFromString(@"WCTableViewCellManager");
    return [cellCls switchCellForSel:action target:self title:title on:on];
}

- (void)onMasterSwitch:(UISwitch *)s       { [DDAdBlockConfig sharedConfig].master = s.isOn; }
- (void)onMomentsSwitch:(UISwitch *)s      { [DDAdBlockConfig sharedConfig].moments = s.isOn; }
- (void)onBrandSwitch:(UISwitch *)s        { [DDAdBlockConfig sharedConfig].brand = s.isOn; }
- (void)onFinderSwitch:(UISwitch *)s       { [DDAdBlockConfig sharedConfig].finder = s.isOn; }
- (void)onLiveSwitch:(UISwitch *)s         { [DDAdBlockConfig sharedConfig].live = s.isOn; }
- (void)onSearchSwitch:(UISwitch *)s       { [DDAdBlockConfig sharedConfig].search = s.isOn; }
- (void)onMiniProgramSwitch:(UISwitch *)s  { [DDAdBlockConfig sharedConfig].miniProgram = s.isOn; }
- (void)onRewardedSwitch:(UISwitch *)s     { [DDAdBlockConfig sharedConfig].rewardedFastPass = s.isOn; }

@end

// ============================================================================
//  插件注册
// ============================================================================

%ctor {
    @autoreleasepool {
        Class mgrClass = NSClassFromString(@"WCPluginsMgr");
        if (mgrClass) {
            id mgr = [mgrClass sharedInstance];
            if ([mgr respondsToSelector:@selector(registerControllerWithTitle:version:controller:)]) {
                [mgr registerControllerWithTitle:@"DD广告拦截"
                                         version:@"1.0.0"
                                      controller:@"DDAdBlockSettingsViewController"];
            }
        }
    }
}