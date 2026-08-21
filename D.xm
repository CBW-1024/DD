//
//  DDAdBlock.xm
//  DD广告拦截 v1.0.0 — 微信广告拦截插件（单文件 Logos/Theos tweak）
//  10 个开关，默认全部关闭；每个 Hook 经总开关 + 分区开关双重门控。
//

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#import <objc/runtime.h>

// ========== 插件管理入口 ==========
@interface WCPluginsMgr : NSObject
+ (instancetype)sharedInstance;
- (void)registerControllerWithTitle:(NSString *)title version:(NSString *)version controller:(NSString *)controller;
@end

// ========== 配置（10 个开关，默认全关） ==========
static NSString * const kDDAdBlockMasterKey            = @"DDAdBlock_Master";
static NSString * const kDDAdBlockMomentsKey           = @"DDAdBlock_Moments";
static NSString * const kDDAdBlockBrandKey             = @"DDAdBlock_Brand";
static NSString * const kDDAdBlockFinderKey            = @"DDAdBlock_Finder";
static NSString * const kDDAdBlockLiveKey              = @"DDAdBlock_Live";
static NSString * const kDDAdBlockMiniProgramKey       = @"DDAdBlock_MiniProgram";
static NSString * const kDDAdBlockNetworkKey           = @"DDAdBlock_Network";
static NSString * const kDDAdBlockSearchKey            = @"DDAdBlock_Search";
static NSString * const kDDAdBlockRewardedFastPassKey  = @"DDAdBlock_RewardedAdFastPass";
static NSString * const kDDAdBlockTeenagerPopupKey     = @"DDAdBlock_TeenagerPopup";

@interface DDAdBlockConfig : NSObject
+ (instancetype)sharedConfig;
@property (assign, nonatomic) BOOL master;            // 总开关
@property (assign, nonatomic) BOOL moments;           // 朋友圈
@property (assign, nonatomic) BOOL brand;             // 公众号
@property (assign, nonatomic) BOOL finder;            // 视频号
@property (assign, nonatomic) BOOL live;              // 直播
@property (assign, nonatomic) BOOL miniProgram;       // 小程序
@property (assign, nonatomic) BOOL network;           // 网络层
@property (assign, nonatomic) BOOL search;            // 搜索
@property (assign, nonatomic) BOOL rewardedFastPass;  // 激励广告快速过
@property (assign, nonatomic) BOOL teenagerPopup;     // 青少年弹窗
@end

@implementation DDAdBlockConfig
+ (instancetype)sharedConfig {
    static DDAdBlockConfig *config = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ config = [DDAdBlockConfig new]; });
    return config;
}
- (instancetype)init {
    if (self = [super init]) {
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        // 默认全部关闭，需在设置内手动开启
        if ([ud objectForKey:kDDAdBlockMasterKey]           == nil) [ud setBool:NO forKey:kDDAdBlockMasterKey];
        if ([ud objectForKey:kDDAdBlockMomentsKey]          == nil) [ud setBool:NO forKey:kDDAdBlockMomentsKey];
        if ([ud objectForKey:kDDAdBlockBrandKey]            == nil) [ud setBool:NO forKey:kDDAdBlockBrandKey];
        if ([ud objectForKey:kDDAdBlockFinderKey]           == nil) [ud setBool:NO forKey:kDDAdBlockFinderKey];
        if ([ud objectForKey:kDDAdBlockLiveKey]             == nil) [ud setBool:NO forKey:kDDAdBlockLiveKey];
        if ([ud objectForKey:kDDAdBlockMiniProgramKey]      == nil) [ud setBool:NO forKey:kDDAdBlockMiniProgramKey];
        if ([ud objectForKey:kDDAdBlockNetworkKey]          == nil) [ud setBool:NO forKey:kDDAdBlockNetworkKey];
        if ([ud objectForKey:kDDAdBlockSearchKey]           == nil) [ud setBool:NO forKey:kDDAdBlockSearchKey];
        if ([ud objectForKey:kDDAdBlockRewardedFastPassKey] == nil) [ud setBool:NO forKey:kDDAdBlockRewardedFastPassKey];
        if ([ud objectForKey:kDDAdBlockTeenagerPopupKey]    == nil) [ud setBool:NO forKey:kDDAdBlockTeenagerPopupKey];

        _master           = [ud boolForKey:kDDAdBlockMasterKey];
        _moments          = [ud boolForKey:kDDAdBlockMomentsKey];
        _brand            = [ud boolForKey:kDDAdBlockBrandKey];
        _finder           = [ud boolForKey:kDDAdBlockFinderKey];
        _live             = [ud boolForKey:kDDAdBlockLiveKey];
        _miniProgram      = [ud boolForKey:kDDAdBlockMiniProgramKey];
        _network          = [ud boolForKey:kDDAdBlockNetworkKey];
        _search           = [ud boolForKey:kDDAdBlockSearchKey];
        _rewardedFastPass = [ud boolForKey:kDDAdBlockRewardedFastPassKey];
        _teenagerPopup    = [ud boolForKey:kDDAdBlockTeenagerPopupKey];
    }
    return self;
}
- (void)setMaster:(BOOL)value {
    _master = value;
    [[NSUserDefaults standardUserDefaults] setBool:value forKey:kDDAdBlockMasterKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}
- (void)setMoments:(BOOL)value {
    _moments = value;
    [[NSUserDefaults standardUserDefaults] setBool:value forKey:kDDAdBlockMomentsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}
- (void)setBrand:(BOOL)value {
    _brand = value;
    [[NSUserDefaults standardUserDefaults] setBool:value forKey:kDDAdBlockBrandKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}
- (void)setFinder:(BOOL)value {
    _finder = value;
    [[NSUserDefaults standardUserDefaults] setBool:value forKey:kDDAdBlockFinderKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}
- (void)setLive:(BOOL)value {
    _live = value;
    [[NSUserDefaults standardUserDefaults] setBool:value forKey:kDDAdBlockLiveKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}
- (void)setMiniProgram:(BOOL)value {
    _miniProgram = value;
    [[NSUserDefaults standardUserDefaults] setBool:value forKey:kDDAdBlockMiniProgramKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}
- (void)setNetwork:(BOOL)value {
    _network = value;
    [[NSUserDefaults standardUserDefaults] setBool:value forKey:kDDAdBlockNetworkKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}
- (void)setSearch:(BOOL)value {
    _search = value;
    [[NSUserDefaults standardUserDefaults] setBool:value forKey:kDDAdBlockSearchKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}
- (void)setRewardedFastPass:(BOOL)value {
    _rewardedFastPass = value;
    [[NSUserDefaults standardUserDefaults] setBool:value forKey:kDDAdBlockRewardedFastPassKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}
- (void)setTeenagerPopup:(BOOL)value {
    _teenagerPopup = value;
    [[NSUserDefaults standardUserDefaults] setBool:value forKey:kDDAdBlockTeenagerPopupKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}
@end

// 总开关守卫：所有 Hook 先经过它
static BOOL ddActive(void) { return [DDAdBlockConfig sharedConfig].master; }

// ========== 1. 朋友圈广告（Hook: WCAdvertiseDataHelper + WCTimelineMgr） ==========
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

// ========== 2. 公众号广告（Hook: BrandTL* + BrandAdDataParser） ==========
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

// 广告内容解析层：返回 nil 即不生成广告
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

// ========== 2.x 公众号/小程序 WebView 广告 ==========
// 公众号文章内广告为 WebView 动态插入的 iframe，从网络 + DOM 两层拦截。
static NSString *DDAdBlockMPHideCSS(void) {
    return @".iframe_ad_container,.iframe_adv_ad_container,"
            ".comment-ad-container,"
            "li.cidad_comment_constant_key,#cidad_comment_constant_key,"
            ".adv_keyword_search,.ad_control-tips"
            "{display:none!important;height:0!important;min-height:0!important;"
            "margin:0!important;padding:0!important;overflow:hidden!important;}";
}
static NSString *DDAdBlockMPHideParentCSS(void) {
    return @"div:has(> .iframe_ad_container),li:has(> .comment-ad-container)"
            "{display:none!important;height:0!important;}";
}
static NSString *DDAdBlockInjectJS(void) {
    return [NSString stringWithFormat:
        @"(function(){try{"
         "if(!document.getElementById('__dd_adblock')){"
         "var s=document.createElement('style');s.id='__dd_adblock';"
         "s.textContent='%@'+'%@';"
         "(document.head||document.documentElement).appendChild(s);}"
         "var sweep=function(){try{Array.prototype.forEach.call("
         "document.querySelectorAll('.iframe_ad_container,.comment-ad-container'),"
         "function(e){var p=e.parentElement,n=0;"
         "while(p&&n<3){if(p.tagName==='LI'||(p.className&&/comment-ad|discuss_media/.test(p.className))){"
         "p.style.setProperty('display','none','important');break;}p=p.parentElement;n++;}});}catch(e){}};"
         "sweep();"
         "if(!window.__dd_ob&&window.MutationObserver){"
         "var t=null;window.__dd_ob=new MutationObserver(function(){"
         "if(t)return;t=setTimeout(function(){t=null;sweep();},300);});"
         "window.__dd_ob.observe(document.documentElement,{childList:true,subtree:true});}"
         "}catch(e){}})();",
        DDAdBlockMPHideCSS(), DDAdBlockMPHideParentCSS()];
}

// 广告 URL 黑名单：命中即拒
static NSArray<NSString *> *DDAdBlockURLBlocklist(void) {
    static NSArray *list;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        list = @[
            @"wxa.wxs.qq.com/tmpl/px/",            // 公众号/文章内广告 iframe
            @"wxa.wxs.qq.com/tmpl/lite/",
            @"support.weixin.qq.com/cgi-bin/mmsupport-bin/", // 部分广告上报/素材
            @"wxapp.tc.qq.com/ad/",               // 小程序广告素材
            @"cpro.baidu.com",                    // 搜索/信息流联盟广告
            @"pos.baidu.com",
            @"go.mobile.qq.com/ad",
            @"/cgi-bin/mmbiz-bin/ad",
            @"ad.weixin.qq.com",
            @"wxad",
            @"adunit-",                            // 小程序 adUnitId
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

%hook MMWebViewController
- (id)webViewUserScriptsForConfiguration {
    id scripts = %orig;
    DDAdBlockConfig *cfg = [DDAdBlockConfig sharedConfig];
    if (!(ddActive() && (cfg.brand || cfg.network))) return scripts;
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
    DDAdBlockConfig *cfg = [DDAdBlockConfig sharedConfig];
    if (ddActive() && (cfg.brand || cfg.network) && !arg4) {
        NSString *u = [[(NSURLRequest *)arg2 URL] absoluteString];
        if ([u containsString:@"wxa.wxs.qq.com"] && [u containsString:@"/tmpl/px/"]) return NO;
        if (ddActive() && cfg.network && ddURLIsAd(u)) return NO;
    }
    return %orig;
}
- (void)webViewDidFinishLoad:(id)arg1 navigation:(id)arg2 {
    %orig;
    DDAdBlockConfig *cfg = [DDAdBlockConfig sharedConfig];
    if (!(ddActive() && (cfg.brand || cfg.network))) return;
    WKWebView *wv = nil;
    @try { wv = [(id)self valueForKey:@"webView"]; } @catch (__unused NSException *e) {}
    if (![wv isKindOfClass:[WKWebView class]]) return;
    [wv evaluateJavaScript:DDAdBlockInjectJS() completionHandler:nil];
}
%end

// ========== 3. 视频号广告（Hook: WCFinderComment + WCFinderDataItem + WCAdFinderInfo） ==========
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

// ========== 4. 小程序广告（Hook: WAAppTask* + MagicAd* + PushService） ==========
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

// MagicAd 自有广告位（按 posId 拉取，覆盖小程序位、支付完成页等）
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

// 广告推送处理入口：直接丢弃广告消息
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

// 小程序广告 DOM 组件（wx-ad / wx-ad-custom，样式隐藏）
static NSString *DDAdBlockMiniAppHideCSS(void) {
    return @"wx-ad,wx-ad-custom,ad,ad-custom,"
            ".wx-ad,.wx-ad-custom"
            "{display:none!important;height:0!important;min-height:0!important;"
            "max-height:0!important;margin:0!important;padding:0!important;"
            "overflow:hidden!important;}";
}
static NSString *DDAdBlockMiniAppInjectJS(void) {
    return [NSString stringWithFormat:
        @"(function(){try{"
         "if(!document.getElementById('__dd_adblock_wa')){"
         "var s=document.createElement('style');s.id='__dd_adblock_wa';"
         "s.textContent='%@';"
         "(document.head||document.documentElement).appendChild(s);}"
         "var sweep=function(){try{Array.prototype.forEach.call("
         "document.querySelectorAll('wx-ad,wx-ad-custom,.wx-ad,.wx-ad-custom'),"
         "function(e){e.style.setProperty('display','none','important');"
         "e.style.setProperty('height','0','important');"
         "e.style.setProperty('max-height','0','important');});}catch(e){}};"
         "sweep();"
         "if(!window.__dd_ob_wa&&window.MutationObserver){"
         "var t=null;window.__dd_ob_wa=new MutationObserver(function(){"
         "if(t)return;t=setTimeout(function(){t=null;sweep();},300);});"
         "window.__dd_ob_wa.observe(document.documentElement,{childList:true,subtree:true});}"
         "}catch(e){}})();",
        DDAdBlockMiniAppHideCSS()];
}
%hook WAWebViewController
- (void)webViewDidFinishLoad:(id)arg1 navigation:(id)arg2 {
    %orig;
    if (!(ddActive() && [DDAdBlockConfig sharedConfig].miniProgram)) return;
    id wv = nil;
    @try { wv = [(id)self valueForKey:@"webView"]; } @catch (__unused NSException *e) {}
    if (![wv respondsToSelector:@selector(evaluateJavaScript:completionHandler:)]) return;
    [wv evaluateJavaScript:DDAdBlockMiniAppInjectJS() completionHandler:nil];
}
- (BOOL)webView:(id)arg1 shouldStartLoadWithRequest:(id)arg2 navigationType:(long long)arg3 isMainFrame:(BOOL)arg4 navigationAction:(id)arg5 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram && !arg4) {
        NSString *u = [[(NSURLRequest *)arg2 URL] absoluteString];
        if (ddURLIsAd(u)) return NO;
    }
    return %orig;
}
%end

// ========== 5. 直播广告（Hook: WCFinderLiveHomePageViewController + WCFinderAdCountdownBannerView） ==========
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

// ========== 6. 搜索广告（Hook: WCAdSearchH5Info） ==========
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

// ========== 7. 激励广告快速过（Hook: WCFinderRewardAdViewController） ==========
%hook WCFinderRewardAdViewController
- (void)viewDidAppear:(BOOL)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].rewardedFastPass) {
        // self 为前向声明类，强转为 id 以避免前向声明报错
        [(id)self dismissViewControllerAnimated:YES completion:nil];
        return;
    }
    %orig;
}
%end

// ========== 8. 青少年模式弹窗（Hook: WCFinderTimelineTabViewController） ==========
%hook WCFinderTimelineTabViewController
- (void)showTeenagerBlockAlertView {
    if (ddActive() && [DDAdBlockConfig sharedConfig].teenagerPopup) return;
    %orig;
}
- (void)showTeenagerNavView {
    if (ddActive() && [DDAdBlockConfig sharedConfig].teenagerPopup) return;
    %orig;
}
- (void)onShowTeenagerRestWithScene:(unsigned long long)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].teenagerPopup) return;
    %orig;
}
%end

// ========== 9. 广告曝光上报抑制（Hook: WCAdvertiseStatMgr，归总开关） ==========
%hook WCAdvertiseStatMgr
- (id)getAdvertiseInfoForItem:(id)arg1 {
    if (ddActive()) return nil;
    return %orig;
}
- (void)logHeadImageH5:(id)arg1 { if (ddActive()) return; %orig; }
- (void)logADBrandProfile:(id)arg1 { if (ddActive()) return; %orig; }
- (void)logADFloatView:(id)arg1 { if (ddActive()) return; %orig; }
- (void)logADPoiH5:(id)arg1 { if (ddActive()) return; %orig; }
- (void)logADH5:(id)arg1 withUserInfo:(id)arg2 reportType:(unsigned long long)arg3 { if (ddActive()) return; %orig; }
- (void)logADCommentLog:(id)arg1 { if (ddActive()) return; %orig; }
- (void)logADBodyLog:(id)arg1 { if (ddActive()) return; %orig; }
- (void)reportAllFeedsADLog { if (ddActive()) return; %orig; }
%end

// ========== 设置界面 ==========
@interface WCTableViewManager : NSObject
- (id)initWithFrame:(CGRect)frame style:(NSInteger)style;
@property (nonatomic, readonly) UITableView *tableView;
@property (nonatomic, weak) id delegate;
- (void)clearAllSection;
- (void)addSection:(id)arg1;
- (void)reloadTableView;
@end

@interface WCTableViewSectionManager : NSObject
+ (id)sectionWithHeader:(NSString *)header;
- (void)addCell:(id)arg1;
@end

@interface WCTableViewCellManager : NSObject
+ (id)switchCellForSel:(SEL)sel target:(id)target title:(id)title on:(BOOL)on;
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
    _tableViewManager = [[managerCls alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    _tableViewManager.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _tableViewManager.tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentAutomatic;
    [self.view addSubview:_tableViewManager.tableView];

    [self buildTable];
}

- (void)buildTable {
    [_tableViewManager clearAllSection];

    Class sectionCls = %c(WCTableViewSectionManager);
    Class cellCls = %c(WCTableViewCellManager);

    WCTableViewSectionManager *secMain = [sectionCls sectionWithHeader:@"广告拦截开关"];
    DDAdBlockConfig *cfg = [DDAdBlockConfig sharedConfig];

    [secMain addCell:[cellCls switchCellForSel:@selector(onMasterSwitch:)        target:self title:@"启用广告拦截"       on:cfg.master]];
    [secMain addCell:[cellCls switchCellForSel:@selector(onMomentsSwitch:)      target:self title:@"屏蔽朋友圈广告"     on:cfg.moments]];
    [secMain addCell:[cellCls switchCellForSel:@selector(onBrandSwitch:)        target:self title:@"屏蔽公众号广告"     on:cfg.brand]];
    [secMain addCell:[cellCls switchCellForSel:@selector(onFinderSwitch:)       target:self title:@"屏蔽视频号广告"     on:cfg.finder]];
    [secMain addCell:[cellCls switchCellForSel:@selector(onLiveSwitch:)         target:self title:@"屏蔽直播广告"       on:cfg.live]];
    [secMain addCell:[cellCls switchCellForSel:@selector(onMiniProgramSwitch:)   target:self title:@"屏蔽小程序广告"     on:cfg.miniProgram]];

    [_tableViewManager addSection:secMain];

    WCTableViewSectionManager *secAdv = [sectionCls sectionWithHeader:@"进阶拦截"];
    [secAdv addCell:[cellCls switchCellForSel:@selector(onNetworkSwitch:)       target:self title:@"网络层广告拦截"     on:cfg.network]];
    [secAdv addCell:[cellCls switchCellForSel:@selector(onSearchSwitch:)        target:self title:@"屏蔽搜索广告"       on:cfg.search]];
    [secAdv addCell:[cellCls switchCellForSel:@selector(onRewardedSwitch:)      target:self title:@"激励广告快速跳过"   on:cfg.rewardedFastPass]];
    [secAdv addCell:[cellCls switchCellForSel:@selector(onTeenagerSwitch:)      target:self title:@"关闭青少年模式弹窗" on:cfg.teenagerPopup]];

    [_tableViewManager addSection:secAdv];
    [_tableViewManager reloadTableView];
}

- (void)onMasterSwitch:(UISwitch *)s        { [DDAdBlockConfig sharedConfig].master = s.isOn; }
- (void)onMomentsSwitch:(UISwitch *)s       { [DDAdBlockConfig sharedConfig].moments = s.isOn; }
- (void)onBrandSwitch:(UISwitch *)s         { [DDAdBlockConfig sharedConfig].brand = s.isOn; }
- (void)onFinderSwitch:(UISwitch *)s        { [DDAdBlockConfig sharedConfig].finder = s.isOn; }
- (void)onLiveSwitch:(UISwitch *)s          { [DDAdBlockConfig sharedConfig].live = s.isOn; }
- (void)onMiniProgramSwitch:(UISwitch *)s   { [DDAdBlockConfig sharedConfig].miniProgram = s.isOn; }
- (void)onNetworkSwitch:(UISwitch *)s       { [DDAdBlockConfig sharedConfig].network = s.isOn; }
- (void)onSearchSwitch:(UISwitch *)s        { [DDAdBlockConfig sharedConfig].search = s.isOn; }
- (void)onRewardedSwitch:(UISwitch *)s      { [DDAdBlockConfig sharedConfig].rewardedFastPass = s.isOn; }
- (void)onTeenagerSwitch:(UISwitch *)s      { [DDAdBlockConfig sharedConfig].teenagerPopup = s.isOn; }

@end

// ========== 插件注册 ==========
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
