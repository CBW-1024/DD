//
//  DDAdBlock.xm
//  插件名: DD广告拦截   版本: 1.1.6
//
//  —— 对齐 D.txt 已验证有效的全部拦截层 ——
//  · 朋友圈 / 公众号 / 视频号 / 直播 / 小程序 / 搜索  (开关分组见底部设置页)
//  · 小程序 <ad>/<ad-custom> DOM 注入 + URL 黑名单
//  · 公众号文章 WebView URL 黑名单 + document-start 注入 JS
//  · 视频号评论区广告 (WCFinderCommentAdTableViewCell, Flex 实证)
//  · 视频号视频流广告 (WCFinderDataItem 第一层: isHardAdFeed / isHardAdLiveFeed / isFromAdsStream / adFlag, 头文件实证)
//       —— 实证来源: WCFinderDataItem.h / WCFinderComment.h / WCAdFinderInfo.h (你提供的 class-dump)
//
//  —— 开关：显式 setter + synchronize (默认全关, 关闭立即持久化, 不使用宏) ——
//  —— 合规：仅供个人逆向学习, 请勿分发 ——
//

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

// 说明: 不 #import 微信私有头文件, 也不写 @class 前向声明.
// Logos 的 %hook ClassName 是运行时按类名查找, 编译期无需类定义;
// 前提是每个 %hook 方法体内只用 %orig 与 UIKit/Foundation 等系统 API,
// 不主动调用 [self 微信私有方法] —— 否则需在该类 %hook 内改用 IMP 派发.
// 视频号相关类的拦截方法 (isHardAdFeed 等) 均已按此约定编写.

// ============================================================================
//  插件管理入口
// ============================================================================
@interface WCPluginsMgr : NSObject
+ (instancetype)sharedInstance;
- (void)registerControllerWithTitle:(NSString *)title version:(NSString *)version controller:(NSString *)controller;
@end

// ============================================================================
//  配置类 (8 个开关, 默认全关)
// ============================================================================
static NSString * const kDDAdBlockMasterKey           = @"DDAdBlock_Master";
static NSString * const kDDAdBlockMomentsKey          = @"DDAdBlock_Moments";
static NSString * const kDDAdBlockBrandKey            = @"DDAdBlock_Brand";
static NSString * const kDDAdBlockFinderKey           = @"DDAdBlock_Finder";
static NSString * const kDDAdBlockLiveKey             = @"DDAdBlock_Live";
static NSString * const kDDAdBlockMiniProgramKey      = @"DDAdBlock_MiniProgram";
static NSString * const kDDAdBlockSearchKey           = @"DDAdBlock_Search";
static NSString * const kDDAdBlockRewardedFastPassKey = @"DDAdBlock_RewardedFastPass";

@interface DDAdBlockConfig : NSObject
+ (instancetype)sharedConfig;
@property (assign, nonatomic) BOOL master;            // 总开关
@property (assign, nonatomic) BOOL moments;           // 朋友圈广告
@property (assign, nonatomic) BOOL brand;             // 公众号广告
@property (assign, nonatomic) BOOL finder;            // 视频号广告 (含视频流 + 评论区)
@property (assign, nonatomic) BOOL live;              // 直播广告
@property (assign, nonatomic) BOOL miniProgram;       // 小程序广告
@property (assign, nonatomic) BOOL search;            // 搜索广告
@property (assign, nonatomic) BOOL rewardedFastPass;  // 激励广告快速跳过
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
        if ([ud objectForKey:kDDAdBlockMasterKey]           == nil) [ud setBool:NO forKey:kDDAdBlockMasterKey];
        if ([ud objectForKey:kDDAdBlockMomentsKey]          == nil) [ud setBool:NO forKey:kDDAdBlockMomentsKey];
        if ([ud objectForKey:kDDAdBlockBrandKey]            == nil) [ud setBool:NO forKey:kDDAdBlockBrandKey];
        if ([ud objectForKey:kDDAdBlockFinderKey]           == nil) [ud setBool:NO forKey:kDDAdBlockFinderKey];
        if ([ud objectForKey:kDDAdBlockLiveKey]             == nil) [ud setBool:NO forKey:kDDAdBlockLiveKey];
        if ([ud objectForKey:kDDAdBlockMiniProgramKey]      == nil) [ud setBool:NO forKey:kDDAdBlockMiniProgramKey];
        if ([ud objectForKey:kDDAdBlockSearchKey]           == nil) [ud setBool:NO forKey:kDDAdBlockSearchKey];
        if ([ud objectForKey:kDDAdBlockRewardedFastPassKey] == nil) [ud setBool:NO forKey:kDDAdBlockRewardedFastPassKey];
        [ud synchronize];

        _master           = [ud boolForKey:kDDAdBlockMasterKey];
        _moments          = [ud boolForKey:kDDAdBlockMomentsKey];
        _brand            = [ud boolForKey:kDDAdBlockBrandKey];
        _finder           = [ud boolForKey:kDDAdBlockFinderKey];
        _live             = [ud boolForKey:kDDAdBlockLiveKey];
        _miniProgram      = [ud boolForKey:kDDAdBlockMiniProgramKey];
        _search           = [ud boolForKey:kDDAdBlockSearchKey];
        _rewardedFastPass = [ud boolForKey:kDDAdBlockRewardedFastPassKey];
    }
    return self;
}

- (void)setMaster:(BOOL)value {
    _master = value;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setBool:value forKey:kDDAdBlockMasterKey];
    [ud synchronize];
}
- (void)setMoments:(BOOL)value {
    _moments = value;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setBool:value forKey:kDDAdBlockMomentsKey];
    [ud synchronize];
}
- (void)setBrand:(BOOL)value {
    _brand = value;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setBool:value forKey:kDDAdBlockBrandKey];
    [ud synchronize];
}
- (void)setFinder:(BOOL)value {
    _finder = value;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setBool:value forKey:kDDAdBlockFinderKey];
    [ud synchronize];
}
- (void)setLive:(BOOL)value {
    _live = value;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setBool:value forKey:kDDAdBlockLiveKey];
    [ud synchronize];
}
- (void)setMiniProgram:(BOOL)value {
    _miniProgram = value;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setBool:value forKey:kDDAdBlockMiniProgramKey];
    [ud synchronize];
}
- (void)setSearch:(BOOL)value {
    _search = value;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setBool:value forKey:kDDAdBlockSearchKey];
    [ud synchronize];
}
- (void)setRewardedFastPass:(BOOL)value {
    _rewardedFastPass = value;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setBool:value forKey:kDDAdBlockRewardedFastPassKey];
    [ud synchronize];
}
@end

static BOOL ddActive(void) { return [DDAdBlockConfig sharedConfig].master; }

// ============================================================================
//  工具函数
// ============================================================================

// 用 IMP 函数指针调用 setHidden:，规避前向声明的 ARC 选择器校验
static void ddViewSetHidden(id obj, BOOL hidden) {
    if (!obj) return;
    SEL sel = @selector(setHidden:);
    if (!class_respondsToSelector([obj class], sel)) return;
    void (*imp)(id, SEL, BOOL) = (void (*)(id, SEL, BOOL))[obj methodForSelector:sel];
    if (imp) imp(obj, sel, hidden);
}

// ============================================================================
//  1. 朋友圈广告
// ============================================================================
%hook WCAdvertiseDataHelper
- (void)saveAdPullCompareInfo:(id)arg1                     { if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return; %orig; }
- (void)saveAdvertiseMsgXmlDatas                          { if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return; %orig; }
- (void)addAdvertiseDataList:(id)arg1                     { if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return; %orig; }
- (void)saveAdvertiseDatas                                { if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return; %orig; }
- (void)tryLoadAdvertiseData                              { if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return; %orig; }
- (BOOL)isAdPreviewExpired:(id)arg1                       { if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return YES; return %orig; }
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
- (void)onAdPullWithAdDatas:(id)arg1                      { if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return; %orig; }
- (void)tryToProcessWithNewAdList:(id)arg1               { if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return; %orig; }
%end

// ============================================================================
//  2. 公众号广告
// ============================================================================
%hook BrandTLExptConfig
- (BOOL)isExptNotShowAd {
    if (ddActive() && [DDAdBlockConfig sharedConfig].brand) return YES;
    return %orig;
}
%end

%hook BrandTLCanvasCardMgr
- (BOOL)isAdCardOpen    { if (ddActive() && [DDAdBlockConfig sharedConfig].brand) return NO; return %orig; }
- (BOOL)isAdRequestOpen { if (ddActive() && [DDAdBlockConfig sharedConfig].brand) return NO; return %orig; }
- (void)handleBizAdNotifyNewXml:(id)arg1 { if (ddActive() && [DDAdBlockConfig sharedConfig].brand) return; %orig; }
%end

%hook BrandAdDataParser
+ (id)adDataItemForContent:(id)arg1    { if (ddActive() && [DDAdBlockConfig sharedConfig].brand) return nil; return %orig; }
+ (id)adDataItemForMsgWrap:(id)arg1    { if (ddActive() && [DDAdBlockConfig sharedConfig].brand) return nil; return %orig; }
+ (id)adInfoDicForContent:(id)arg1     { if (ddActive() && [DDAdBlockConfig sharedConfig].brand) return nil; return %orig; }
+ (id)adInfoDicForMsgWrap:(id)arg1     { if (ddActive() && [DDAdBlockConfig sharedConfig].brand) return nil; return %orig; }
%end

// 公众号文章 WebView: URL 黑名单 + document-start 注入 JS + DOM sweep
static NSString * const DDAdBlockURLBlocklist[] = {
    @"ad.weixin.qq.com",
    @"wxa.wxs.qq.com/tmpl/px",
    @"wxa.wxs.qq.com/cgi-bin/mmbiz-bin/ad",
    @"mp.weixin.qq.com/mp/getappmsgad",
    @"/cgi-bin/mmbiz-bin/ad",
    @"magicad",
    nil
};

static BOOL ddURLIsAd(NSURL *url) {
    if (!url) return NO;
    NSString *abs = [url absoluteString];
    if (!abs) return NO;
    for (int i = 0; DDAdBlockURLBlocklist[i]; i++) {
        if ([abs rangeOfString:@(DDAdBlockURLBlocklist[i]) options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return YES;
        }
    }
    return NO;
}

static NSString *DDAdBlockMPInjectJS(void) {
    return @"("
        "(function(){"
        "function hide(){"
        "var s='.iframe_ad_container,.iframe_adv_ad_container,.comment-ad-container,"
        "li.cidad_comment_constant_key,#cidad_comment_constant_key,.adv_keyword_search,"
        ".ad_control-tips{display:none!important;height:0!important;min-height:0!important;"
        "margin:0!important;padding:0!important;overflow:hidden!important;}"
        "div:has(>.iframe_ad_container),li:has(>.comment-ad-container){"
        "display:none!important;height:0!important;}"
        "wx-ad,wx-ad-custom,ad,ad-custom,.wx-ad,.wx-ad-custom{"
        "display:none!important;height:0!important;min-height:0!important;max-height:0!important;"
        "margin:0!important;padding:0!important;overflow:hidden!important;}"
        "';"
        "var st=document.createElement('style');"
        "st.type='text/css';st.textContent=s;"
        "document.head&&document.head.appendChild(st);"
        "}"
        "hide();"
        "var mo=new MutationObserver(hide);"
        "mo.observe(document.body,{childList:true,subtree:true});"
        "})"
    ")();";
}

%hook MMWebViewController
- (WKUserScript *)webViewUserScriptsForConfiguration:(WKWebViewConfiguration *)configuration {
    WKUserScript *orig = %orig;
    if (ddActive() && [DDAdBlockConfig sharedConfig].brand) {
        WKUserScript *inject = [[WKUserScript alloc]
            initWithSource:DDAdBlockMPInjectJS()
            injectionTime:WKUserScriptInjectionTimeAtDocumentStart
            forMainFrameOnly:NO];
        if (orig) {
            return [[WKUserScript alloc] initWithSource:[orig.source stringByAppendingString:inject.source]
                                          injectionTime:orig.injectionTime
                                          forMainFrameOnly:orig.isForMainFrameOnly];
        }
        return inject;
    }
    return orig;
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)action
                                        decisionHandler:(void (^)(WKNavigationActionPolicy))handler {
    if (ddActive() && [DDAdBlockConfig sharedConfig].brand) {
        if (ddURLIsAd(action.request.URL)) {
            handler(WKNavigationActionPolicyCancel);
            return;
        }
    }
    %orig;
}

- (void)webViewDidFinishLoad:(id)arg1 navigation:(id)arg2 {
    %orig;
    if (!(ddActive() && [DDAdBlockConfig sharedConfig].brand)) return;
    WKWebView *wv = nil;
    @try { wv = [(id)self valueForKey:@"webView"]; } @catch (__unused NSException *e) {}
    if ([wv isKindOfClass:[WKWebView class]]) {
        [wv evaluateJavaScript:DDAdBlockMPInjectJS() completionHandler:nil];
    }
}
%end

// ============================================================================
//  3. 视频号广告
// ============================================================================

// ----- 3.1 数据对象层 (D.txt 兼容, 真实头文件确认字段) -----
// WCFinderComment.h 实锤: advertisementInfo / commentAdImageUrl / promotionInfo 均存在
%hook WCFinderComment
- (id)advertisementInfo  { if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return nil; return %orig; }
- (id)commentAdImageUrl  { if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return nil; return %orig; }
- (id)promotionInfo      { if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return nil; return %orig; }
%end

// WCAdFinderInfo: 广告标识对象, isValid 直接判 NO
%hook WCAdFinderInfo
- (BOOL)isValid { if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return NO; return %orig; }
%end

// ----- 3.2 评论区广告 (Flex 实证: WCFinderCommentAdTableViewCell) -----
%hook WCFinderCommentAdTableViewCell
- (void)updateWithModel:(id)arg1 width:(double)arg2 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder) {
        // 不调用 %orig, 广告 Cell 不渲染内容; 直接隐藏, 高度由下方方法返回 0
        ddViewSetHidden((UIView *)self, YES);
        return;
    }
    %orig;
}

+ (double)sectionHeightWith:(id)arg1 width:(double)arg2 halfScreenHeight:(double)arg3 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return 0.0;
    return %orig;
}

- (double)heightForMediaWithRatio:(double)arg1 maxHeightPercentage:(double)arg2 minArea:(double)arg3 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return 0.0;
    return %orig;
}

- (void)updatePlayerViewWithCommentInfo:(id)arg1 videoInfo:(id)arg2 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return;
    %orig;
}
- (void)updateImageViewWithCommentImageInfo:(id)arg1 imgInfo:(id)arg2 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return;
    %orig;
}
- (void)clickADContentActionWithArea:(long long)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return;
    %orig;
}

- (id)commentAdReportDictWithReportScene:(long long)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return nil;
    return %orig;
}
- (BOOL)canReportWithReportScene:(long long)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return NO;
    return %orig;
}
%end

%hook WCFinderCommentDetailViewController
- (void)checkCommentAdPlayerExposeStateIfNeeded { if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return; %orig; }
- (void)reportCommentAd:(id)arg1 withReportScene:(long long)arg2 { if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return; %orig; }
- (void)reportCommentAdIfNeededWithReportScene:(long long)arg1 { if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return; %orig; }
- (void)_configADCellReportBehavior:(id)arg1 comment:(id)arg2 { if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return; %orig; }
- (void)commentAdCell:(id)arg1 clickFeedbackButton:(id)arg2 atSection:(long long)arg3 { if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return; %orig; }
- (void)commentAdCell:(id)arg1 longPressAtSection:(long long)arg2 { if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return; %orig; }
%end

// ----- 3.3 视频流广告 (刷到的广告视频) -----
// 证据: WCFinderDataItem (class-dump 真实头文件, 你贴的 WCFinderDataItem.h)
//   官方判定方法:
//     - isHardAdFeed       ← ★ 视频流硬广 Feed (刷到的广告视频就是这个)
//     - isHardAdLiveFeed   ← 直播硬广
//     - isFromAdsStream / setIsFromAdsStream:  ← 是否来自广告流
//     - adFlag (property)   ← 广告标记位
// 思路: 第一层 —— 让微信自己认为"该 item 不是广告",
//       列表插入 / 角标 / 素材请求 / 曝光上报全部失效, 无需碰 Cell / 播放器.
%hook WCFinderDataItem
// ★ 视频流广告 (刷到的广告视频)
- (BOOL)isHardAdFeed {
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return NO;
    return %orig;
}
// 直播硬广
- (BOOL)isHardAdLiveFeed {
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return NO;
    return %orig;
}
// 是否来自广告流 (带 setter, 一并 neutralize)
- (BOOL)isFromAdsStream {
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return NO;
    return %orig;
}
- (void)setIsFromAdsStream:(BOOL)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder) { %orig(NO); return; }
    %orig;
}
// 兜底: 广告标记位清零
- (unsigned long long)adFlag {
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return 0;
    return %orig;
}
// 广告跳转信息容器置空 (点击广告区/跳转信息一并失效)
- (id)jumpInfoContainer {
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return nil;
    return %orig;
}
- (id)postJumpInfoContainer {
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return nil;
    return %orig;
}
// 直播广告封面 URL 置空
- (id)adLiveCoverUrl {
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return nil;
    return %orig;
}
// 直播广告参数置空
- (id)adsParams {
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return nil;
    return %orig;
}
%end  // 闭合 %hook WCFinderDataItem

// 辅助判定: 任意 WCFinderDataItem 是否为广告 (运行时探测, 用于列表层兜底)
// 注意: 此函数必须位于 %hook 块外部 (Logos 不允许在 %hook 内定义 C 函数)
static BOOL ddIsFinderDataItemAd(id item) {
    if (!item || ![item isKindOfClass:%c(WCFinderDataItem)]) return NO;
    // 优先官方判定方法 (来自真实头文件, 编译期即可校验)
    if ([item respondsToSelector:@selector(isHardAdFeed)] && [item isHardAdFeed]) return YES;
    if ([item respondsToSelector:@selector(isHardAdLiveFeed)] && [item isHardAdLiveFeed]) return YES;
    if ([item respondsToSelector:@selector(isFromAdsStream)] && [item isFromAdsStream]) return YES;
    // 兜底: adFlag 数值判定
    if ([item respondsToSelector:@selector(adFlag)] && [item adFlag] != 0) return YES;
    return NO;
}

// ============================================================================
//  4. 直播广告
// ============================================================================
%hook WCFinderAdCountdownBannerView
- (void)setupSubviews               { if (ddActive() && [DDAdBlockConfig sharedConfig].live) return; %orig; }
- (void)startCountdown             { if (ddActive() && [DDAdBlockConfig sharedConfig].live) return; %orig; }
- (void)updateUIWithTime:(long long)arg1 { if (ddActive() && [DDAdBlockConfig sharedConfig].live) return; %orig; }
- (BOOL)adHasPlayOver              { if (ddActive() && [DDAdBlockConfig sharedConfig].live) return YES; return %orig; }
%end

%hook WCFinderLiveHomePageViewController
- (void)onAdSectionView:(id)arg1 selectElementVM:(id)arg2 { if (ddActive() && [DDAdBlockConfig sharedConfig].live) return; %orig; }
%end

// ============================================================================
//  5. 搜索广告
// ============================================================================
%hook WCAdSearchH5Info
- (BOOL)isValid                { if (ddActive() && [DDAdBlockConfig sharedConfig].search) return NO; return %orig; }
+ (id)fromXML:(struct XmlReaderNode_t *)arg1 { if (ddActive() && [DDAdBlockConfig sharedConfig].search) return nil; return %orig; }
%end

// ============================================================================
//  6. 小程序广告
// ============================================================================

// 6.1 URL 黑名单 + DOM sweep (D.txt 核心, 防小程序中间广告)
static NSString *DDAdBlockMiniAppInjectJS(void) {
    return @"("
        "(function(){"
        "function hide(){"
        "var s='wx-ad,wx-ad-custom,ad,ad-custom,.wx-ad,.wx-ad-custom{"
        "display:none!important;height:0!important;min-height:0!important;max-height:0!important;"
        "margin:0!important;padding:0!important;overflow:hidden!important;}"
        "';"
        "var st=document.createElement('style');"
        "st.type='text/css';st.textContent=s;"
        "document.head&&document.head.appendChild(st);"
        "}"
        "hide();"
        "var mo=new MutationObserver(hide);"
        "mo.observe(document.body,{childList:true,subtree:true});"
        "})"
    ")();";
}

%hook WAWebViewController
- (WKUserScript *)webViewUserScriptsForConfiguration:(WKWebViewConfiguration *)configuration {
    WKUserScript *orig = %orig;
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) {
        WKUserScript *inject = [[WKUserScript alloc]
            initWithSource:DDAdBlockMiniAppInjectJS()
            injectionTime:WKUserScriptInjectionTimeAtDocumentStart
            forMainFrameOnly:NO];
        if (orig) {
            return [[WKUserScript alloc] initWithSource:[orig.source stringByAppendingString:inject.source]
                                          injectionTime:orig.injectionTime
                                          forMainFrameOnly:orig.isForMainFrameOnly];
        }
        return inject;
    }
    return orig;
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)action
                                        decisionHandler:(void (^)(WKNavigationActionPolicy))handler {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) {
        if (ddURLIsAd(action.request.URL)) {
            handler(WKNavigationActionPolicyCancel);
            return;
        }
    }
    %orig;
}

- (void)webViewDidFinishLoad:(id)arg1 navigation:(id)arg2 {
    %orig;
    if (!(ddActive() && [DDAdBlockConfig sharedConfig].miniProgram)) return;
    id wv = nil;
    @try { wv = [(id)self valueForKey:@"webView"]; } @catch (__unused NSException *e) {}
    if ([wv respondsToSelector:@selector(evaluateJavaScript:completionHandler:)]) {
        [wv evaluateJavaScript:DDAdBlockMiniAppInjectJS() completionHandler:nil];
    }
}
%end

// 6.2 原生广告逻辑 (D.txt)
%hook WAAppTaskSplashADConfig
- (void)handleShowSplashAdCalled:(BOOL)arg1 { if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return; %orig; }
%end

%hook WAJSEventHandler_showSplashAd
- (void)handleJSEvent:(id)arg1 { if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return; %orig; }
%end

%hook WAJSEventHandler_showSplashAdMenu
- (void)handleJSEvent:(id)arg1 { if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return; %orig; }
%end

%hook WAJSEventHandler_adOperateWXData
- (void)handleJSEvent:(id)arg1 { if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return; %orig; }
%end

%hook MagicAdCommonService
- (id)getAdInfoWithPosId:(id)arg1 { if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return nil; return %orig; }
- (id)internalGetAdInfoFromCacheWithPosId:(id)arg1 { if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return nil; return %orig; }
- (void)getAdInfoAsyncWithPosId:(id)arg1 completion:(id)arg2 { if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return; %orig; }
- (void)getAdInfoAsyncWithPosId:(id)arg1 timeoutMs:(long long)arg2 completion:(id)arg3 { if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return; %orig; }
- (void)triggerUpdateAdWithPosId:(id)arg1 pullType:(unsigned char)arg2 { if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return; %orig; }
- (void)updateAdInfoByCGIInstantlyWithPosId:(id)arg1 pullType:(unsigned char)arg2 isDelayPull:(BOOL)arg3 { if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return; %orig; }
%end

%hook MagicAdCGIMgr
+ (void)getAdsCGIWithPosIds:(id)arg1 successBlock:(id)arg2 failBlock:(id)arg3 { if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return; %orig; }
%end

%hook MagicAdPushMgrService
- (void)handleAdMsg:(id)arg1 { if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return; %orig; }
%end

%hook WCAdvertisePushService
- (void)handlePushMsg:(id)arg1 { if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return; %orig; }
%end

// ============================================================================
//  7. 激励广告快速跳过 (进阶拦截唯一项)
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
//  8. 广告上报抑制
// ============================================================================
%hook WCAdvertiseStatMgr
- (id)getAdvertiseInfoForItem:(id)arg1                  { if (ddActive()) return nil; return %orig; }
- (void)logHeadImageH5:(id)arg1                         { if (ddActive()) return; %orig; }
- (void)logADBrandProfile:(id)arg1                      { if (ddActive()) return; %orig; }
- (void)logADFloatView:(id)arg1                         { if (ddActive()) return; %orig; }
- (void)logADPoiH5:(id)arg1                             { if (ddActive()) return; %orig; }
- (void)logADH5:(id)arg1 withUserInfo:(id)arg2 reportType:(unsigned long long)arg3 { if (ddActive()) return; %orig; }
- (void)logADCommentLog:(id)arg1                        { if (ddActive()) return; %orig; }
- (void)logADBodyLog:(id)arg1                           { if (ddActive()) return; %orig; }
- (void)reportAllFeedsADLog                             { if (ddActive()) return; %orig; }
%end

// ============================================================================
//  设置界面
// ============================================================================
@interface WCTableViewManager : NSObject
- (id)initWithFrame:(CGRect)frame style:(NSInteger)style;
@property (nonatomic, readonly) UITableView *tableView;
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

    WCTableViewSectionManager *secMain = [sectionCls sectionWithHeader:@"广告拦截场景"];
    [secMain addCell:[cellCls switchCellForSel:@selector(onMasterSwitch:) target:self title:@"启用广告拦截" on:cfg.master]];
    [secMain addCell:[cellCls switchCellForSel:@selector(onMomentsSwitch:) target:self title:@"屏蔽朋友圈广告" on:cfg.moments]];
    [secMain addCell:[cellCls switchCellForSel:@selector(onBrandSwitch:) target:self title:@"屏蔽公众号广告" on:cfg.brand]];
    [secMain addCell:[cellCls switchCellForSel:@selector(onFinderSwitch:) target:self title:@"屏蔽视频号广告" on:cfg.finder]];
    [secMain addCell:[cellCls switchCellForSel:@selector(onLiveSwitch:) target:self title:@"屏蔽直播广告" on:cfg.live]];
    [secMain addCell:[cellCls switchCellForSel:@selector(onSearchSwitch:) target:self title:@"屏蔽搜索广告" on:cfg.search]];
    [secMain addCell:[cellCls switchCellForSel:@selector(onMiniProgramSwitch:) target:self title:@"屏蔽小程序广告" on:cfg.miniProgram]];
    [_tableViewManager addSection:secMain];

    WCTableViewSectionManager *secAdv = [sectionCls sectionWithHeader:@"进阶拦截"];
    [secAdv addCell:[cellCls switchCellForSel:@selector(onRewardedSwitch:) target:self title:@"激励广告快速跳过" on:cfg.rewardedFastPass]];
    [_tableViewManager addSection:secAdv];

    [_tableViewManager reloadTableView];
}

- (void)onMasterSwitch:(UISwitch *)s      { [DDAdBlockConfig sharedConfig].master = s.isOn; [self buildTable]; }
- (void)onMomentsSwitch:(UISwitch *)s     { [DDAdBlockConfig sharedConfig].moments = s.isOn; }
- (void)onBrandSwitch:(UISwitch *)s       { [DDAdBlockConfig sharedConfig].brand = s.isOn; }
- (void)onFinderSwitch:(UISwitch *)s      { [DDAdBlockConfig sharedConfig].finder = s.isOn; }
- (void)onLiveSwitch:(UISwitch *)s        { [DDAdBlockConfig sharedConfig].live = s.isOn; }
- (void)onSearchSwitch:(UISwitch *)s      { [DDAdBlockConfig sharedConfig].search = s.isOn; }
- (void)onMiniProgramSwitch:(UISwitch *)s { [DDAdBlockConfig sharedConfig].miniProgram = s.isOn; }
- (void)onRewardedSwitch:(UISwitch *)s    { [DDAdBlockConfig sharedConfig].rewardedFastPass = s.isOn; }
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
                                         version:@"1.1.3"
                                      controller:@"DDAdBlockSettingsViewController"];
            }
        }
    }
}
