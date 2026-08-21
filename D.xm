//
//  DD广告拦截 v1.1.0 — 微信广告拦截插件（单文件 Logos/Theos tweak）
//  11 个开关，默认全部关闭；每个 Hook 经总开关 + 分区开关双重门控。
//  开关命名对齐 WCR（WCRefine）的 enhancedAdBlock*Enabled 模块：moments/brand/finder/live/
//  miniProgram/network/search/rewardedAdFastPass/expt + 独立 disableTeenagerPopupEnabled。
//

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#import <dispatch/dispatch.h>
#import <objc/runtime.h>

// ========== 插件管理入口 ==========
@interface WCPluginsMgr : NSObject
+ (instancetype)sharedInstance;
- (void)registerControllerWithTitle:(NSString *)title version:(NSString *)version controller:(NSString *)controller;
@end

// ========== 配置（开关，默认全关） ==========
// NSUserDefaults 键名对齐 WCR 的 enhancedAdBlock*Enabled 模块命名（前缀 DDAdBlock_）。
// 内部属性保留简短名（moments/brand/...）便于门控处可读；每一项注释标注对应 WCR 开关。
static NSString * const kDDAdBlockMasterKey            = @"DDAdBlock_EnhancedAdBlockEnabled";            // WCR: enhancedAdBlockEnabled（总开关）
static NSString * const kDDAdBlockMomentsKey           = @"DDAdBlock_EnhancedAdBlockMomentsEnabled";     // WCR: enhancedAdBlockMomentsEnabled
static NSString * const kDDAdBlockBrandKey             = @"DDAdBlock_EnhancedAdBlockBrandEnabled";       // WCR: enhancedAdBlockBrandEnabled
static NSString * const kDDAdBlockFinderKey            = @"DDAdBlock_EnhancedAdBlockFinderEnabled";      // WCR: enhancedAdBlockFinderEnabled
static NSString * const kDDAdBlockLiveKey              = @"DDAdBlock_EnhancedAdBlockLiveEnabled";        // WCR: enhancedAdBlockLiveEnabled
static NSString * const kDDAdBlockMiniProgramKey       = @"DDAdBlock_EnhancedAdBlockMiniProgramEnabled"; // WCR: enhancedAdBlockMiniProgramEnabled
static NSString * const kDDAdBlockNetworkKey           = @"DDAdBlock_EnhancedAdBlockNetworkEnabled";     // WCR: enhancedAdBlockNetworkEnabled
static NSString * const kDDAdBlockSearchKey            = @"DDAdBlock_EnhancedAdBlockSearchEnabled";      // WCR: enhancedAdBlockSearchEnabled
static NSString * const kDDAdBlockRewardedFastPassKey  = @"DDAdBlock_EnhancedAdBlockRewardedAdFastPassEnabled"; // WCR: enhancedAdBlockRewardedAdFastPassEnabled
static NSString * const kDDAdBlockTeenagerPopupKey     = @"DDAdBlock_DisableTeenagerPopupEnabled";       // WCR: disableTeenagerPopupEnabled（青少年弹窗，独立功能）
static NSString * const kDDAdBlockExptKey              = @"DDAdBlock_EnhancedAdBlockExptEnabled";        // WCR: enhancedAdBlockExptEnabled（实验开关式广告抑制）

@interface DDAdBlockConfig : NSObject
+ (instancetype)sharedConfig;
@property (assign, nonatomic) BOOL master;            // 总开关（WCR: enhancedAdBlockEnabled）
@property (assign, nonatomic) BOOL moments;           // 朋友圈（WCR: enhancedAdBlockMomentsEnabled）
@property (assign, nonatomic) BOOL brand;             // 公众号（WCR: enhancedAdBlockBrandEnabled）
@property (assign, nonatomic) BOOL finder;            // 视频号（WCR: enhancedAdBlockFinderEnabled）
@property (assign, nonatomic) BOOL live;              // 直播（WCR: enhancedAdBlockLiveEnabled）
@property (assign, nonatomic) BOOL miniProgram;       // 小程序（WCR: enhancedAdBlockMiniProgramEnabled）
@property (assign, nonatomic) BOOL network;           // 网络层（WCR: enhancedAdBlockNetworkEnabled）
@property (assign, nonatomic) BOOL search;            // 搜索（WCR: enhancedAdBlockSearchEnabled）
@property (assign, nonatomic) BOOL rewardedFastPass;  // 激励广告快速过（WCR: enhancedAdBlockRewardedAdFastPassEnabled）
@property (assign, nonatomic) BOOL teenagerPopup;     // 青少年弹窗（WCR: disableTeenagerPopupEnabled，独立功能）
@property (assign, nonatomic) BOOL expt;              // 实验开关式广告抑制（WCR: enhancedAdBlockExptEnabled）
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
        if ([ud objectForKey:kDDAdBlockExptKey]             == nil) [ud setBool:NO forKey:kDDAdBlockExptKey];

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
        _expt             = [ud boolForKey:kDDAdBlockExptKey];
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
- (void)setExpt:(BOOL)value {
    _expt = value;
    [[NSUserDefaults standardUserDefaults] setBool:value forKey:kDDAdBlockExptKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}
@end

// 总开关守卫：所有 Hook 先经过它
static BOOL ddActive(void) { return [DDAdBlockConfig sharedConfig].master; }

// ========== 1. 朋友圈广告（Hook: WCAdvertiseDataHelper + WCTimelineMgr）[WCR: enhancedAdBlockMomentsEnabled] ==========
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
// 对齐 WCR 引用的 IsAdvertiseDataValid:dataItem:：广告数据校验入口，返回 NO 即判广告无效、
// 不进入展示流程（WCR 此选择器出现在 ad 模块 selrefs 中，是朋友圈广告注入的兜底校验）
- (BOOL)IsAdvertiseDataValid:(id)arg1 dataItem:(id)arg2 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return NO;
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

// ========== 2. 公众号广告（Hook: BrandTL* + BrandAdDataParser）[WCR: enhancedAdBlockBrandEnabled] ==========
// ========== 2.x 实验开关式广告抑制 [WCR: enhancedAdBlockExptEnabled] ==========
// WCR 用微信自身实验开关 isExptNotShow* 抑制广告展示——这是“官方开关式”拦截，不触碰广告
// 展示类本身，比 Hook 广告类更不易误伤。WCR 作为独立 expt 模块（不受 brand 模块开关控制），
// 引用全部 4 个 isExptNotShow 系列：Ad / FinderLiveBar(视频号直播) / RecCard(推荐卡片) / RecoFlow(推荐流)。
// 以下 4 个类（BrandTLExptConfig / BSTLExptConfig / BrandTimelineMsgMgr / BoxBrandTimelineMsgMgr）
// 都声明了这 4 个方法，逐一精确对齐（直接写全，不用宏展开）。
%hook BrandTLExptConfig
- (BOOL)isExptNotShowAd {
    if (ddActive() && [DDAdBlockConfig sharedConfig].expt) return YES;
    return %orig;
}
- (BOOL)isExptNotShowFinderLiveBar {
    if (ddActive() && [DDAdBlockConfig sharedConfig].expt) return YES;
    return %orig;
}
- (BOOL)isExptNotShowRecCard {
    if (ddActive() && [DDAdBlockConfig sharedConfig].expt) return YES;
    return %orig;
}
- (BOOL)isExptNotShowRecoFlow {
    if (ddActive() && [DDAdBlockConfig sharedConfig].expt) return YES;
    return %orig;
}
%end

%hook BSTLExptConfig
- (BOOL)isExptNotShowAd {
    if (ddActive() && [DDAdBlockConfig sharedConfig].expt) return YES;
    return %orig;
}
- (BOOL)isExptNotShowFinderLiveBar {
    if (ddActive() && [DDAdBlockConfig sharedConfig].expt) return YES;
    return %orig;
}
- (BOOL)isExptNotShowRecCard {
    if (ddActive() && [DDAdBlockConfig sharedConfig].expt) return YES;
    return %orig;
}
- (BOOL)isExptNotShowRecoFlow {
    if (ddActive() && [DDAdBlockConfig sharedConfig].expt) return YES;
    return %orig;
}
%end

%hook BrandTimelineMsgMgr
- (BOOL)isExptNotShowAd {
    if (ddActive() && [DDAdBlockConfig sharedConfig].expt) return YES;
    return %orig;
}
- (BOOL)isExptNotShowFinderLiveBar {
    if (ddActive() && [DDAdBlockConfig sharedConfig].expt) return YES;
    return %orig;
}
- (BOOL)isExptNotShowRecCard {
    if (ddActive() && [DDAdBlockConfig sharedConfig].expt) return YES;
    return %orig;
}
- (BOOL)isExptNotShowRecoFlow {
    if (ddActive() && [DDAdBlockConfig sharedConfig].expt) return YES;
    return %orig;
}
%end

%hook BoxBrandTimelineMsgMgr
- (BOOL)isExptNotShowAd {
    if (ddActive() && [DDAdBlockConfig sharedConfig].expt) return YES;
    return %orig;
}
- (BOOL)isExptNotShowFinderLiveBar {
    if (ddActive() && [DDAdBlockConfig sharedConfig].expt) return YES;
    return %orig;
}
- (BOOL)isExptNotShowRecCard {
    if (ddActive() && [DDAdBlockConfig sharedConfig].expt) return YES;
    return %orig;
}
- (BOOL)isExptNotShowRecoFlow {
    if (ddActive() && [DDAdBlockConfig sharedConfig].expt) return YES;
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

// 广告 XML 解析/注入层（对齐 WCR：WCR 字符串精确引用 WCAdXmlParser 的
// ExtractRecommendAdInfo:ByAdMsgXml: / SetAdvertiseXml:ByAdXml: / SetAdvertiseInfo:ByAdInfo:）。
// 返回 NO 即判定广告解析失败，广告不会注入到信息流/卡片。
%hook WCAdXmlParser
+ (BOOL)ExtractRecommendAdInfo:(id)arg1 ByAdMsgXml:(id)arg2 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].brand) return NO;
    return %orig;
}
+ (BOOL)SetAdvertiseXml:(id)arg1 ByAdXml:(id)arg2 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].brand) return NO;
    return %orig;
}
+ (BOOL)SetAdvertiseInfo:(id)arg1 ByAdInfoXml:(struct XmlReaderNode_t *)arg2 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].brand) return NO;
    return %orig;
}
+ (BOOL)SetAdvertiseInfo:(id)arg1 ByAdInfo:(id)arg2 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].brand) return NO;
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
         "window.__dd_ob.observe(document.documentElement,{childList:true,subtree:true});"
         "setTimeout(function(){try{window.__dd_ob&&window.__dd_ob.disconnect();}catch(e){}},8000);}"
         "}catch(e){}})();",
        DDAdBlockMPHideCSS(), DDAdBlockMPHideParentCSS()];
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
// 不做 URL 层黑名单拦截：WCR 对 WebView 广告仅做 DOM/CSS 注入与转发层处理，
// 不做宽泛 URL 匹配，避免误伤正常请求导致“网络连接失败”。
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

// ========== 3. 视频号广告（Hook: WCFinderComment + WCFinderDataItem + WCAdFinderInfo）[WCR: enhancedAdBlockFinderEnabled] ==========
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
- (BOOL)isAdsLive {
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return NO;
    return %orig;
}
%end

%hook WCAdFinderInfo
- (BOOL)isValid {
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return NO;
    return %orig;
}
%end

// ========== 4. 小程序广告（对齐 WCR：原生层开屏广告拦截）[WCR: enhancedAdBlockMiniProgramEnabled] ==========
// 微信小程序广告以“开屏广告”为主。WCR 在原生层强制关闭，而非注入 WebView
// （注入会误伤正常请求、产生“网络连接失败”，且 display:none 不停音频/卡顿）。
// 对齐点（来自 WCR 强制字符串 + 微信头文件）：
//   WAAppTaskSplashADConfig.splashADEnableNumber -> 0
//   WAAppTaskSplashADConfig.canShowSplashADWindow / splashADHasContent / canHotStartShowSplashAD -> NO
//   WAAppTask.isSplashADFinished -> YES
//   WASplashADWindow.showRootViewControllerAnimated:completion: 跳过展示
%hook WAAppTaskSplashADConfig
- (id)splashADEnableNumber {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return @(0);
    return %orig;
}
- (BOOL)canShowSplashADWindow {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return NO;
    return %orig;
}
- (BOOL)splashADHasContent {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return NO;
    return %orig;
}
- (BOOL)canHotStartShowSplashAD {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return NO;
    return %orig;
}
%end

%hook WAAppTask
- (BOOL)isSplashADFinished {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return YES;
    return %orig;
}
%end

%hook WASplashADWindow
- (void)showRootViewControllerAnimated:(BOOL)arg1 completion:(id)arg2 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) {
        // 跳过开屏广告展示，直接执行完成回调：无广告界面、无声音、不卡顿
        if (arg2) { @try { ((void (^)(id))arg2)(nil); } @catch (__unused NSException *e) {} }
        return;
    }
    %orig;
}
%end

// 对齐 WCR 引用的 +[WAExptProxy shouldShowSplashAD]：开屏广告是否展示的总开关。
// 返回 NO 从最上游禁止开屏广告出现（与上面 WASplashADWindow 跳过展示构成双保险）。
%hook WAExptProxy
+ (BOOL)shouldShowSplashAD {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return NO;
    return %orig;
}
%end

// 小程序/品牌广告消息入口（对齐 WCR：WCR 字符串精确引用 MagicAdPushMgrService）。
// handleAdMsg: 是推送的广告消息处理入口，拦截它即阻断广告消息进入展示流程。
// 注意：WCR 并未引用 MagicAdCommonService / MagicAdCGIMgr（那是我此前的非对齐落点），
// 小程序开屏广告的真实上游是 WAAppTaskSplashADConfig / WASplashADWindow / WAExptProxy（已对齐）。
%hook MagicAdPushMgrService
- (void)handleAdMsg:(id)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return;
    %orig;
}
- (void)OnGetNewXmlMsg:(id)arg1 Type:(id)arg2 MsgWrap:(id)arg3 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return;
    %orig;
}
%end

// ========== 4.1 网络层广告拦截（对齐 WCR：按广告 URL 正则拦截/重定向 CGI 请求）[WCR: enhancedAdBlockNetworkEnabled] ==========
// WCR 网络层（WCRefineEnhancedAdBlockNetworkEnabled）对匹配下列正则的广告 CGI 请求做
// 重定向/拦截，而非宽泛 URL 黑名单（避免误伤正常请求导致“网络连接失败”）：
//   advert_group|getadvert|getAdPreloadData|ad_posid|_ads_|/ads_|advertisement_
// 该正则取自 WCR 二进制 __cstring（cfstring: adurl_regex），是 WCR 网络层广告判定的依据。
// 对齐落点：WCR 字符串精确引用 NSURLSession 类，网络层在 NSURLSession 公开 dataTask 方法上
// 拦截（WCR 也引用 URLSession:task:willPerformHTTPRedirection: 重定向回调）。命中广告正则的
// 请求被替换为本地空 data: 请求——不真正联网、返回空数据，广告代码拿不到广告数据；与 WCR
// 日志 "url redirect=%d reason=%@ url=%@" 的“重定向/拦截”行为一致。
static NSString * const kDDAdBlockAdURLPattern =
    @"advert_group|getadvert|getAdPreloadData|ad_posid|_ads_|/ads_|advertisement_";

static BOOL DDAdBlockURLIsAdRequest(NSURL *url) {
    if (url == nil) return NO;
    NSString *s = [url absoluteString];
    if (s.length == 0) return NO;
    return [s rangeOfString:kDDAdBlockAdURLPattern
                     options:NSRegularExpressionSearch].location != NSNotFound;
}

%hook NSURLSession
// 对齐落点：微信所有 CGI / HTTP 请求最终经 NSURLSession 的公开 dataTask 方法发出
// （MMNetworkHook 在其上做监控/重定向）。Hook 公开方法可确保无论微信 swizzle 顺序如何
// 都能命中。命中广告 URL 正则的请求替换为本地空 data: 请求——不联网、返回空数据。
- (id)dataTaskWithRequest:(NSURLRequest *)arg1 completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))arg2 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].network && DDAdBlockURLIsAdRequest([arg1 URL])) {
        NSURLRequest *dr = [NSURLRequest requestWithURL:[NSURL URLWithString:@"data:text/plain;charset=utf-8,"]];
        return %orig(dr, arg2);
    }
    return %orig;
}
- (id)dataTaskWithURL:(NSURL *)arg1 completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))arg2 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].network && DDAdBlockURLIsAdRequest(arg1)) {
        // 本方法第一个参数是 NSURL *，需替换为空 data: URL（非 NSURLRequest *）
        NSURL *du = [NSURL URLWithString:@"data:text/plain;charset=utf-8,"];
        return %orig(du, arg2);
    }
    return %orig;
}
%end

// 精确对齐 WCR 网络层真实落点：WCR 在 NSURLSession 委托的 HTTP 重定向回调里拦截广告 CGI
// （二进制引用 URLSession:task:willPerformHTTPRedirection:newRequest:completionHandler:，并打
// "url redirect=%d reason=%@ url=%@" 日志）。微信全局 NSURLSession 封装为 HttpClientAppleImpl，
// 它实现了该委托方法。命中广告正则的重定向（如广告点击跳转落地页）直接取消，不跟随。
// 与上方 dataTask 替换构成纵深：dataTask 阻断广告 CGI 联网，本 Hook 兜底拦截任何漏网重定向。
%hook HttpClientAppleImpl
- (void)URLSession:(id)arg1 task:(id)arg2 willPerformHTTPRedirection:(id)arg3 newRequest:(NSURLRequest *)arg4 completionHandler:(void (^)(NSURLRequest *))arg5 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].network && DDAdBlockURLIsAdRequest([arg4 URL])) {
        if (arg5) arg5(nil);   // 取消重定向，对齐 WCR 的“拦截广告 CGI 跳转”
        return;
    }
    %orig;
}
%end

// 小程序 WebView 内广告（wx-ad 组件）统一交由原生层开屏拦截 + MagicAd 消息拦截处理，
// 不再注入 JS（避免误伤正常请求、display:none 不停音频、MutationObserver 卡顿）。
// 对齐 WCR：WCR 小程序去广告走原生层，无 WebView JS 注入。

// ========== 5. 直播广告（Hook: WCFinderLiveHomePageViewController + WCFinderAdCountdownBannerView）[WCR: enhancedAdBlockLiveEnabled] ==========
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

// 直播广告：isAdsLive（WCR 引用）已由 WCFinderDataItem 覆盖（见视频号模块）。
// WCR 未引用 MMLiveAdsParams 类，故不对其单独 Hook。

// ========== 6. 搜索广告（Hook: WCAdSearchH5Info）[WCR: enhancedAdBlockSearchEnabled] ==========
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

// ========== 7. 激励广告快速过（对齐 WCR：adHasPlayOver 跳过 + 进入即收起）[WCR: enhancedAdBlockRewardedAdFastPassEnabled] ==========
%hook WCFinderRewardAdViewController
// 让系统认为激励视频已播放完毕，跳过倒计时/等待并触发奖励结算（WCR 同款核心）
- (BOOL)adHasPlayOver {
    if (ddActive() && [DDAdBlockConfig sharedConfig].rewardedFastPass) return YES;
    return %orig;
}
// 在进入动画开始前就收起（animated:NO），视频尚未起播即关闭 → 无界面、无声音、真正“秒过”
- (void)viewWillAppear:(BOOL)arg1 {
    %orig;
    if (ddActive() && [DDAdBlockConfig sharedConfig].rewardedFastPass) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [(id)self dismissViewControllerAnimated:NO completion:nil];
        });
    }
}
// 兜底：viewWillAppear 收起失败时在 viewDidAppear 再收一次
- (void)viewDidAppear:(BOOL)arg1 {
    %orig;
    if (ddActive() && [DDAdBlockConfig sharedConfig].rewardedFastPass) {
        [(id)self dismissViewControllerAnimated:NO completion:nil];
    }
}
%end

// ========== 8. 青少年模式弹窗（Hook: WCFinderTimelineTabViewController）[WCR: disableTeenagerPopupEnabled，独立功能] ==========
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
    DDAdBlockConfig *cfg = [DDAdBlockConfig sharedConfig];

    // 总开关：最上方独立单元格
    WCTableViewSectionManager *secMaster = [sectionCls sectionWithHeader:@"DD广告拦截"];
    [secMaster addCell:[cellCls switchCellForSel:@selector(onMasterSwitch:) target:self title:@"启用广告拦截" on:cfg.master]];
    [_tableViewManager addSection:secMaster];

    // 总开关开启时展开各分区开关，关闭时收起
    if (cfg.master) {
        WCTableViewSectionManager *secMain = [sectionCls sectionWithHeader:@"广告拦截"];
        [secMain addCell:[cellCls switchCellForSel:@selector(onMomentsSwitch:)      target:self title:@"屏蔽朋友圈广告"   on:cfg.moments]];
        [secMain addCell:[cellCls switchCellForSel:@selector(onBrandSwitch:)        target:self title:@"屏蔽公众号广告"   on:cfg.brand]];
        [secMain addCell:[cellCls switchCellForSel:@selector(onFinderSwitch:)       target:self title:@"屏蔽视频号广告"   on:cfg.finder]];
        [secMain addCell:[cellCls switchCellForSel:@selector(onLiveSwitch:)          target:self title:@"屏蔽直播广告"     on:cfg.live]];
        [secMain addCell:[cellCls switchCellForSel:@selector(onMiniProgramSwitch:)   target:self title:@"屏蔽小程序广告"   on:cfg.miniProgram]];
        [_tableViewManager addSection:secMain];

        WCTableViewSectionManager *secAdv = [sectionCls sectionWithHeader:@"进阶拦截"];
        [secAdv addCell:[cellCls switchCellForSel:@selector(onNetworkSwitch:)     target:self title:@"网络层广告拦截"     on:cfg.network]];
        [secAdv addCell:[cellCls switchCellForSel:@selector(onSearchSwitch:)      target:self title:@"屏蔽搜索广告"       on:cfg.search]];
        [secAdv addCell:[cellCls switchCellForSel:@selector(onRewardedSwitch:)    target:self title:@"激励广告快速跳过"   on:cfg.rewardedFastPass]];
        [secAdv addCell:[cellCls switchCellForSel:@selector(onExptSwitch:)        target:self title:@"实验开关广告抑制"   on:cfg.expt]];
        [secAdv addCell:[cellCls switchCellForSel:@selector(onTeenagerSwitch:)    target:self title:@"关闭青少年模式弹窗" on:cfg.teenagerPopup]];
        [_tableViewManager addSection:secAdv];
    }

    [_tableViewManager reloadTableView];
}

- (void)onMasterSwitch:(UISwitch *)s        { [DDAdBlockConfig sharedConfig].master = s.isOn; [self buildTable]; }
- (void)onMomentsSwitch:(UISwitch *)s       { [DDAdBlockConfig sharedConfig].moments = s.isOn; }
- (void)onBrandSwitch:(UISwitch *)s         { [DDAdBlockConfig sharedConfig].brand = s.isOn; }
- (void)onFinderSwitch:(UISwitch *)s        { [DDAdBlockConfig sharedConfig].finder = s.isOn; }
- (void)onLiveSwitch:(UISwitch *)s          { [DDAdBlockConfig sharedConfig].live = s.isOn; }
- (void)onMiniProgramSwitch:(UISwitch *)s   { [DDAdBlockConfig sharedConfig].miniProgram = s.isOn; }
- (void)onNetworkSwitch:(UISwitch *)s       { [DDAdBlockConfig sharedConfig].network = s.isOn; }
- (void)onSearchSwitch:(UISwitch *)s        { [DDAdBlockConfig sharedConfig].search = s.isOn; }
- (void)onRewardedSwitch:(UISwitch *)s      { [DDAdBlockConfig sharedConfig].rewardedFastPass = s.isOn; }
- (void)onExptSwitch:(UISwitch *)s          { [DDAdBlockConfig sharedConfig].expt = s.isOn; }
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
                                         version:@"1.1.0"
                                      controller:@"DDAdBlockSettingsViewController"];
            }
        }
    }
}
