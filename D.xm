//
//  DDAdBlock.xm
//  DD广告拦截 v1.0.0
//
//  说明:
//  - 不使用宏, 所有方法显式书写
//  - 不写 @class 前向声明, 也不 #import 微信私有头文件
//    (Logos 的 %hook 运行时按类名查找, 方法体内只用 %orig 与系统 API)
//  - 开关默认全关, 关闭立即 synchronize 持久化 (不会自动回弹)
//  - 组织方式: 按开关顺序分模块, 每个模块的辅助代码就近放在本模块内部
//    (如 WebView 黑名单/注入 JS/CSS 分别内聚在公众号模块和小程序模块里)
//

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#import <objc/runtime.h>

// ============================================================================
//  配置类 (开关: master / moments / brand / finder / live / search /
//         miniProgram / rewardedFastPass)
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
//  全局守卫 (被所有模块共用, 放此处作为基础设施)
// ============================================================================

static BOOL ddActive(void) {
    return [DDAdBlockConfig sharedConfig].master;
}

static BOOL ddFinderOn(void) {
    return ddActive() && [DDAdBlockConfig sharedConfig].finder;
}

// 安全的 setHidden: (规避前向声明, 供视频号 Cell 使用)
static void ddViewSetHidden(id view, BOOL hidden) {
    if (!view) return;
    SEL sel = @selector(setHidden:);
    if (class_respondsToSelector([(id)view class], sel)) {
        void (*imp)(id, SEL, BOOL) = (void (*)(id, SEL, BOOL))[(id)view methodForSelector:sel];
        if (imp) imp((id)view, sel, hidden);
    }
}

// ============================================================================
//  1. 朋友圈广告 (moments)
// ============================================================================

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

// ============================================================================
//  2. 公众号广告 (brand)
//     (a) 原生数据层  (b) WebView URL 黑名单 + JS 注入 + DOM sweep
//     ↓ WebView 相关辅助代码就近放在本模块内部
// ============================================================================

// ----- 2a. 原生数据层 -----
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

// ----- 2b/2c 辅助: 广告 URL 黑名单 (公众号专属) -----
static NSString * const DDAdBlockMPURLBlocklist[] = {
    @"wxs.qq.com/tmpl/px",
    @"wxs.qq.com/tmpl/lite",
    @"wxs.qq.com/tmpl",
    @"mmbiz-bin/ad",
    @"ad.weixin.qq.com",
    @"cgi-bin/mmbiz-bin/ad",
    @"getappmsgad",
    @"magicad",
    @"magic-ad",
    @"posId=",
    nil
};

// 判定 URL 是否为广告 (公众号 WebView 使用)
static BOOL ddMPURLIsAd(NSURL *url) {
    if (!url) return NO;
    NSString *absolute = url.absoluteString;
    if (!absolute) return NO;
    for (NSInteger i = 0; DDAdBlockMPURLBlocklist[i] != nil; i++) {
        if ([absolute rangeOfString:DDAdBlockMPURLBlocklist[i] options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return YES;
        }
    }
    return NO;
}

// document-start 注入的通用 JS: 注入 CSS + 周期性 DOM sweep (公众号使用)
static NSString * const DDAdBlockMPInjectJS =
@"(function(){"
@"var s=document.createElement('style');"
@"s.textContent='[class*=ad],[id*=ad],[class*=Ad],"
@"[class*=advert],iframe[src*=ad],.ad-container,.ad_box,"
@".ad-card,.ad_banner,.ad_feed,.ad-mask,.ad-cover,.ad-slot{"
@"display:none!important;width:0!important;height:0!important;"
@"overflow:hidden!important;opacity:0!important;}';"
@"document.head.appendChild(s);"
@"function sweep(){"
@"var all=document.querySelectorAll("
@"'[class*=ad],[id*=ad],[class*=Ad],[class*=advert]');"
@"for(var i=0;i<all.length;i++){"
@"var r=all[i].getBoundingClientRect();"
@"if(r.width>0&&r.height>0){all[i].style.cssText+='display:none!important;';}}"
@"}"
@"setInterval(sweep,1500);sweep();"
@"})();";

// 公众号文章页专用隐藏 CSS (iframe 广告 / 评论区广告 / 关键词广告)
static NSString * const DDAdBlockMPHideCSS =
@".iframe_ad_container,.iframe_adv_ad_container,.comment-ad-container,"
@"li.cidad_comment_constant_key,#cidad_comment_constant_key,"
@"adv_keyword_search,.ad_control-tips{display:none!important;"
@"height:0!important;min-height:0!important;margin:0!important;"
@"padding:0!important;overflow:hidden!important;}"
@"div:has(> .iframe_ad_container),"
@"li:has(> .comment-ad-container){display:none!important;height:0!important;}";

// ----- 2b. WebView URL 黑名单: 在请求阶段直接拦截广告 URL -----
%hook MMWebViewController
- (void)webView:(id)webView decidePolicyForNavigationAction:(id)action
        decisionHandler:(void (^)(NSInteger))decisionHandler {
    if (ddActive() && [DDAdBlockConfig sharedConfig].brand) {
        NSURL *url = nil;
        @try { url = [(id)action valueForKey:@"URL"]; } @catch (__unused NSException *e) {}
        if (url && ddMPURLIsAd(url)) {
            if (decisionHandler) decisionHandler(2); // WKNavigationActionPolicyCancel
            return;
        }
    }
    %orig;
}
%end

// ----- 2c. 加载完成注入 JS + 补充公众号专用 CSS -----
%hook MMWebViewController
- (void)webView:(id)webView didFinishNavigation:(id)navigation {
    %orig;
    if (!(ddActive() && [DDAdBlockConfig sharedConfig].brand)) return;
    WKWebView *wv = nil;
    @try { wv = [(id)self valueForKey:@"webView"]; } @catch (__unused NSException *e) {}
    if (![wv isKindOfClass:[WKWebView class]]) return;
    [wv evaluateJavaScript:DDAdBlockMPInjectJS completionHandler:nil];
    [wv evaluateJavaScript:DDAdBlockMPHideCSS completionHandler:nil];
}
%end

// ============================================================================
//  3. 视频号广告 (finder)
//     3.1 评论区广告  3.2 视频流广告 (刷到的广告视频, 仅第一层)
// ============================================================================

// ----- 3.1 评论区广告 -----
%hook WCFinderComment
- (id)advertisementInfo {
    if (ddFinderOn()) return nil;
    return %orig;
}
- (id)commentAdImageUrl {
    if (ddFinderOn()) return nil;
    return %orig;
}
- (id)promotionInfo {
    if (ddFinderOn()) return nil;
    return %orig;
}
%end

%hook WCFinderDataItem
- (unsigned long long)adFlag {
    if (ddFinderOn()) return 0;
    return %orig;
}
%end

%hook WCAdFinderInfo
- (BOOL)isValid {
    if (ddFinderOn()) return NO;
    return %orig;
}
%end

%hook WCFinderCommentAdTableViewCell
- (void)updateWithModel:(id)arg1 width:(double)arg2 {
    if (ddFinderOn()) {
        %orig;
        ddViewSetHidden((id)self, YES);
        return;
    }
    %orig;
}
- (double)sectionHeightWith:(id)arg1 width:(double)arg2 halfScreenHeight:(double)arg3 {
    if (ddFinderOn()) return 0.0;
    return %orig;
}
- (double)heightForMediaWithRatio:(double)arg1 maxHeightPercentage:(double)arg2 minArea:(double)arg3 {
    if (ddFinderOn()) return 0.0;
    return %orig;
}
- (void)updatePlayerViewWithCommentInfo:(id)arg1 videoInfo:(id)arg2 {
    if (ddFinderOn()) return;
    %orig;
}
- (void)updateImageViewWithCommentImageInfo:(id)arg1 imgInfo:(id)arg2 {
    if (ddFinderOn()) return;
    %orig;
}
- (void)clickADContentActionWithArea:(NSInteger)arg1 {
    if (ddFinderOn()) return;
    %orig;
}
- (id)commentAdReportDictWithReportScene:(NSInteger)arg1 {
    if (ddFinderOn()) return nil;
    return %orig;
}
- (BOOL)canReportWithReportScene:(NSInteger)arg1 {
    if (ddFinderOn()) return NO;
    return %orig;
}
%end

%hook WCFinderCommentDetailViewController
- (void)checkCommentAdPlayerExposeStateIfNeeded {
    if (ddFinderOn()) return;
    %orig;
}
- (void)reportCommentAd:(id)arg1 withReportScene:(NSInteger)arg2 {
    if (ddFinderOn()) return;
    %orig;
}
- (void)reportCommentAdIfNeededWithReportScene:(NSInteger)arg2 {
    if (ddFinderOn()) return;
    %orig;
}
- (void)_configADCellReportBehavior:(id)arg1 comment:(id)arg2 {
    if (ddFinderOn()) return;
    %orig;
}
- (void)commentAdCell:(id)arg1 clickFeedbackButton:(id)arg2 atSection:(NSInteger)arg3 {
    if (ddFinderOn()) return;
    %orig;
}
- (void)commentAdCell:(id)arg1 longPressAtSection:(NSInteger)arg3 {
    if (ddFinderOn()) return;
    %orig;
}
%end

// ----- 3.2 视频流广告 (刷到的广告视频, 仅第一层) -----
// 依据 WCFinderDataItem 真实头文件: 广告判定接口为
// isHardAdFeed / isHardAdLiveFeed / isFromAdsStream / adFlag 等.
// 让微信自身认为 "该 item 不是广告", 列表插入/角标/素材请求/上报全部失效,
// 不碰 Cell, 不碰播放器.
%hook WCFinderDataItem
- (BOOL)isHardAdFeed {
    if (ddFinderOn()) return NO;
    return %orig;
}
- (BOOL)isHardAdLiveFeed {
    if (ddFinderOn()) return NO;
    return %orig;
}
- (BOOL)isFromAdsStream {
    if (ddFinderOn()) return NO;
    return %orig;
}
- (void)setIsFromAdsStream:(BOOL)arg1 {
    if (ddFinderOn()) {
        %orig(NO);
        return;
    }
    %orig;
}
- (id)jumpInfoContainer {
    if (ddFinderOn()) return nil;
    return %orig;
}
- (id)postJumpInfoContainer {
    if (ddFinderOn()) return nil;
    return %orig;
}
- (id)adLiveCoverUrl {
    if (ddFinderOn()) return nil;
    return %orig;
}
- (id)adsParams {
    if (ddFinderOn()) return nil;
    return %orig;
}
%end

// ============================================================================
//  4. 直播广告 (live)
// ============================================================================

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

// ============================================================================
//  5. 搜索广告 (search)
// ============================================================================

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

// ============================================================================
//  6. 小程序广告 (miniProgram)
//     (a) 原生数据层 / CGI / 推送  (b) WebView URL 黑名单 + JS 注入 + DOM sweep
//     ↓ WebView 相关辅助代码就近放在本模块内部 (与公众号模块各自独立)
// ============================================================================

// ----- 6a. 原生数据层 / CGI / 推送 -----
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

// ----- 6b/6c 辅助: 广告 URL 黑名单 (小程序专属) -----
static NSString * const DDAdBlockMiniAppURLBlocklist[] = {
    @"wxs.qq.com/tmpl/px",
    @"wxs.qq.com/tmpl/lite",
    @"wxs.qq.com/tmpl",
    @"mmbiz-bin/ad",
    @"ad.weixin.qq.com",
    @"cgi-bin/mmbiz-bin/ad",
    @"getappmsgad",
    @"magicad",
    @"magic-ad",
    @"posId=",
    nil
};

// 判定 URL 是否为广告 (小程序 WebView 使用)
static BOOL ddMiniAppURLIsAd(NSURL *url) {
    if (!url) return NO;
    NSString *absolute = url.absoluteString;
    if (!absolute) return NO;
    for (NSInteger i = 0; DDAdBlockMiniAppURLBlocklist[i] != nil; i++) {
        if ([absolute rangeOfString:DDAdBlockMiniAppURLBlocklist[i] options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return YES;
        }
    }
    return NO;
}

// document-start 注入的通用 JS: 注入 CSS + 周期性 DOM sweep (小程序使用)
static NSString * const DDAdBlockMiniAppInjectJS =
@"(function(){"
@"var s=document.createElement('style');"
@"s.textContent='[class*=ad],[id*=ad],[class*=Ad],"
@"[class*=advert],iframe[src*=ad],.ad-container,.ad_box,"
@".ad-card,.ad_banner,.ad_feed,.ad-mask,.ad-cover,.ad-slot{"
@"display:none!important;width:0!important;height:0!important;"
@"overflow:hidden!important;opacity:0!important;}';"
@"document.head.appendChild(s);"
@"function sweep(){"
@"var all=document.querySelectorAll("
@"'[class*=ad],[id*=ad],[class*=Ad],[class*=advert]');"
@"for(var i=0;i<all.length;i++){"
@"var r=all[i].getBoundingClientRect();"
@"if(r.width>0&&r.height>0){all[i].style.cssText+='display:none!important;';}}"
@"}"
@"setInterval(sweep,1500);sweep();"
@"})();";

// 小程序专用隐藏 CSS (<wx-ad> / <wx-ad-custom> 原生组件)
static NSString * const DDAdBlockMiniAppHideCSS =
@"wx-ad,wx-ad-custom,ad,ad-custom,"
@".wx-ad,.wx-ad-custom{display:none!important;height:0!important;"
@"min-height:0!important;max-height:0!important;margin:0!important;"
@"padding:0!important;overflow:hidden!important;}";

// ----- 6b. WebView URL 黑名单: 在请求阶段直接拦截广告 URL -----
%hook WAWebViewController
- (void)webView:(id)webView decidePolicyForNavigationAction:(id)action
        decisionHandler:(void (^)(NSInteger))decisionHandler {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) {
        NSURL *url = nil;
        @try { url = [(id)action valueForKey:@"URL"]; } @catch (__unused NSException *e) {}
        if (url && ddMiniAppURLIsAd(url)) {
            if (decisionHandler) decisionHandler(2); // WKNavigationActionPolicyCancel
            return;
        }
    }
    %orig;
}
%end

// ----- 6c. 加载完成注入 JS + 补充 <wx-ad> 原生组件 CSS -----
%hook WAWebViewController
- (void)webView:(id)webView didFinishNavigation:(id)navigation {
    %orig;
    if (!(ddActive() && [DDAdBlockConfig sharedConfig].miniProgram)) return;
    id wv = nil;
    @try { wv = [(id)self valueForKey:@"webView"]; } @catch (__unused NSException *e) {}
    if (![wv respondsToSelector:@selector(evaluateJavaScript:completionHandler:)]) return;
    [wv evaluateJavaScript:DDAdBlockMiniAppInjectJS completionHandler:nil];
    [wv evaluateJavaScript:DDAdBlockMiniAppHideCSS completionHandler:nil];
}
%end

// ============================================================================
//  7. 激励广告快速跳过 (rewardedFastPass, 进阶拦截唯一项)
// ============================================================================

%hook WCFinderRewardAdViewController
- (void)viewDidAppear:(BOOL)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].rewardedFastPass) {
        [(id)self dismissViewControllerAnimated:YES completion:nil];
        return;
    }
    %orig;
}
%end

// ============================================================================
//  8. 广告上报抑制 (全局, 独立于分区开关)
// ============================================================================

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

// ============================================================================
//  9. 设置界面 (优化版)
// ============================================================================

@interface DDAdBlockSettingsViewController : UIViewController
@property (nonatomic, strong) id tableViewManager;
@end

@implementation DDAdBlockSettingsViewController

- (instancetype)init {
    self = [super init];
    if (self) {
        // 延迟初始化 tableViewManager，避免在 init 时依赖 view 尺寸
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"DD广告拦截";
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    [self setupTableViewManager];
    [self buildSections];
}

- (void)setupTableViewManager {
    if (_tableViewManager) return;
    Class mgrCls = NSClassFromString(@"WCTableViewManager");
    if (!mgrCls) {
        // 若类不存在，给个占位提示
        UILabel *label = [[UILabel alloc] initWithFrame:self.view.bounds];
        label.text = @"无法加载设置界面（依赖类不存在）";
        label.textAlignment = NSTextAlignmentCenter;
        label.textColor = [UIColor secondaryLabelColor];
        [self.view addSubview:label];
        return;
    }
    _tableViewManager = [[mgrCls alloc] initWithFrame:self.view.bounds
                                                style:UITableViewStyleInsetGrouped];
    UITableView *tableView = [self.tableViewManager getTableView];
    tableView.frame = self.view.bounds;
    tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentAutomatic;
    [self.view addSubview:tableView];
}

- (void)buildSections {
    if (!_tableViewManager) return;
    Class sectionCls = NSClassFromString(@"WCTableViewSectionManager");
    Class cellCls = NSClassFromString(@"WCTableViewCellManager");
    if (!sectionCls || !cellCls) return;

    DDAdBlockConfig *cfg = [DDAdBlockConfig sharedConfig];

    // 清空旧数据
    [_tableViewManager clearAllSection];

    // ---- 主 Section ----
    id secMain = [sectionCls defaultSection];
    secMain.headerTitle = @"广告屏蔽开关";
    [secMain addCell:[self switchCellWithTitle:@"启用广告拦截"
                                            on:cfg.master
                                        action:@selector(onMasterSwitch:)]];
    [secMain addCell:[self switchCellWithTitle:@"屏蔽朋友圈广告"
                                            on:cfg.moments
                                        action:@selector(onMomentsSwitch:)]];
    [secMain addCell:[self switchCellWithTitle:@"屏蔽公众号广告"
                                            on:cfg.brand
                                        action:@selector(onBrandSwitch:)]];
    [secMain addCell:[self switchCellWithTitle:@"屏蔽视频号广告"
                                            on:cfg.finder
                                        action:@selector(onFinderSwitch:)]];
    [secMain addCell:[self switchCellWithTitle:@"屏蔽直播广告"
                                            on:cfg.live
                                        action:@selector(onLiveSwitch:)]];
    [secMain addCell:[self switchCellWithTitle:@"屏蔽搜索广告"
                                            on:cfg.search
                                        action:@selector(onSearchSwitch:)]];
    [secMain addCell:[self switchCellWithTitle:@"屏蔽小程序广告"
                                            on:cfg.miniProgram
                                        action:@selector(onMiniProgramSwitch:)]];
    [_tableViewManager addSection:secMain];

    // ---- 进阶拦截 Section ----
    id secAdv = [sectionCls defaultSection];
    secAdv.headerTitle = @"进阶拦截";
    secAdv.footerTitle = @"开启后，激励广告将自动快速跳过（无需等待）";
    [secAdv addCell:[self switchCellWithTitle:@"激励广告快速跳过"
                                           on:cfg.rewardedFastPass
                                       action:@selector(onRewardedSwitch:)]];
    [_tableViewManager addSection:secAdv];

    [_tableViewManager reloadTableView];
}

// 辅助方法：创建开关 Cell
- (id)switchCellWithTitle:(NSString *)title on:(BOOL)on action:(SEL)action {
    Class cellCls = NSClassFromString(@"WCTableViewCellManager");
    if (!cellCls) return nil;
    return [cellCls switchCellForSel:action
                              target:self
                               title:title
                                  on:on];
}

// 开关回调（仅保存配置，不重建表）
- (void)onMasterSwitch:(UISwitch *)s {
    [DDAdBlockConfig sharedConfig].master = s.isOn;
}
- (void)onMomentsSwitch:(UISwitch *)s {
    [DDAdBlockConfig sharedConfig].moments = s.isOn;
}
- (void)onBrandSwitch:(UISwitch *)s {
    [DDAdBlockConfig sharedConfig].brand = s.isOn;
}
- (void)onFinderSwitch:(UISwitch *)s {
    [DDAdBlockConfig sharedConfig].finder = s.isOn;
}
- (void)onLiveSwitch:(UISwitch *)s {
    [DDAdBlockConfig sharedConfig].live = s.isOn;
}
- (void)onSearchSwitch:(UISwitch *)s {
    [DDAdBlockConfig sharedConfig].search = s.isOn;
}
- (void)onMiniProgramSwitch:(UISwitch *)s {
    [DDAdBlockConfig sharedConfig].miniProgram = s.isOn;
}
- (void)onRewardedSwitch:(UISwitch *)s {
    [DDAdBlockConfig sharedConfig].rewardedFastPass = s.isOn;
}

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