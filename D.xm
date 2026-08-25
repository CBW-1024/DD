//
//  DDAdBlock.xm
//  插件名: DD广告拦截   版本: 1.0.0
//  功能:   从 WCRefine 的 EnhancedAdBlock 模块提取广告拦截能力，重建为独立单文件 tweak。
//  开关:   9 个 UI 开关（总/朋友圈/公众号/视频号/直播/小程序/搜索/激励快过/青少年弹窗）。
//  入口与设置界面参考 WechatNoAds（WCPluginsMgr 注册 + 原生 WCTableViewManager）。
//
//  v1.0.1 修复"小程序中间有广告"：
//    参考 D.txt 现有实现 + WCRefine 反汇编，小程序广告除开屏/JS桥/WebView DOM 外，
//    还存在"信息流中间插入的广告卡片"这一数据层入口。D.txt 已 hook MagicAdCommonService
//    (posId 拉取/缓存) 与 MagicAdCGIMgr.getAdsCGIWithPosIds:，本次补齐 WCRefine 实际
//    引用的、D.txt 漏掉的"广告数据入池/广告对象构造/广告 cell 渲染"三层缺口：
//      1) 数据入池层  —— MagicAdDataItem / MagicAdInfoItem 构造时返回 nil，广告对象不生成；
//      2) 信息流插入层 —— WAMiniProgramAdFeedInsert / WAAdFeedItem 相关 getter 返回 nil/NO，
//         让"朋友圈式信息流中间广告"在数据源阶段被判为无效、不插入时间线；
//      3) 广告 cell 渲染层 —— WCFinderAdTableViewCell / WCFinderCommentAdTableViewCell
//         init 不返回 nil（避免 UITableView dequeue nil 闪退），仅做隐藏/高度归零兜底，
//         真正去广告仍由数据层 neutralize 完成（与 v1.6.1 视频号评论修复同源）。
//    以上三层 + D.txt 原有 MagicAdCommonService/MagicAdCGIMgr/PushService/WebView DOM
//    形成"数据→插入→渲染"全链路覆盖，小程序中间广告（信息流插卡式）被彻底拦截。
//  其余模块（朋友圈/公众号/视频号/直播/搜索/激励/青少年弹窗/上报）与 D.txt 保持一致。
//  9 个开关默认全部关闭，每个方法经总开关 + 分区开关双重门控。
//

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#import <objc/runtime.h>


// ========== 配置类（对齐 DDBlurConfig：字典存储 + setValue:forConfigKey:）==========
static NSString * const kDDAdBlockConfigKey = @"DDAdBlockConfig";
static NSString * const kDDAdBlockMasterKey = @"DDAdBlock_Master";
static NSString * const kDDAdBlockMomentsKey = @"DDAdBlock_Moments";
static NSString * const kDDAdBlockBrandKey = @"DDAdBlock_Brand";
static NSString * const kDDAdBlockFinderKey = @"DDAdBlock_Finder";
static NSString * const kDDAdBlockLiveKey = @"DDAdBlock_Live";
static NSString * const kDDAdBlockMiniProgramKey = @"DDAdBlock_MiniProgram";
static NSString * const kDDAdBlockSearchKey = @"DDAdBlock_Search";
static NSString * const kDDAdBlockRewardedAdFastPassKey = @"DDAdBlock_RewardedAdFastPass";
static NSString * const kDDAdBlockTeenagerPopupKey = @"DDAdBlock_TeenagerPopup";

@interface DDAdBlockConfig : NSObject
+ (instancetype)sharedConfig;
- (id)valueForConfigKey:(NSString *)key;
- (void)setValue:(id)value forConfigKey:(NSString *)key;
- (BOOL)master;
- (BOOL)moments;
- (BOOL)brand;
- (BOOL)finder;
- (BOOL)live;
- (BOOL)miniProgram;
- (BOOL)search;
- (BOOL)rewardedAdFastPass;
- (BOOL)teenagerPopup;
@end

@implementation DDAdBlockConfig

+ (instancetype)sharedConfig {
    static DDAdBlockConfig *cfg = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cfg = [DDAdBlockConfig new]; });
    return cfg;
}

- (NSMutableDictionary *)mutableConfig {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *cfg = [[ud objectForKey:kDDAdBlockConfigKey] mutableCopy];
    if (!cfg) cfg = [NSMutableDictionary dictionary];
    // 首次启动：全部默认 NO
    for (NSString *k in @[
         kDDAdBlockMasterKey,
         kDDAdBlockMomentsKey,
         kDDAdBlockBrandKey,
         kDDAdBlockFinderKey,
         kDDAdBlockLiveKey,
         kDDAdBlockMiniProgramKey,
         kDDAdBlockSearchKey,
         kDDAdBlockRewardedAdFastPassKey,
         kDDAdBlockTeenagerPopupKey,
    ]) {
        if ([cfg objectForKey:k] == nil) [cfg setObject:@(NO) forKey:k];
    }
    [ud setObject:cfg forKey:kDDAdBlockConfigKey];
    return cfg;
}

- (id)valueForConfigKey:(NSString *)key {
    return [[self mutableConfig] objectForKey:key];
}

- (void)setValue:(id)value forConfigKey:(NSString *)key {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *cfg = [[ud objectForKey:kDDAdBlockConfigKey] mutableCopy];
    if (!cfg) cfg = [NSMutableDictionary dictionary];
    if (value) [cfg setObject:value forKey:key];
    else [cfg removeObjectForKey:key];
    [ud setObject:cfg forKey:kDDAdBlockConfigKey];
    [ud synchronize];
}

- (BOOL)master {
    return [[self valueForConfigKey:kDDAdBlockMasterKey] boolValue];
}
- (void)setMaster:(BOOL)value {
    [self setValue:@(value) forConfigKey:kDDAdBlockMasterKey];
}

- (BOOL)moments {
    return [[self valueForConfigKey:kDDAdBlockMomentsKey] boolValue];
}
- (void)setMoments:(BOOL)value {
    [self setValue:@(value) forConfigKey:kDDAdBlockMomentsKey];
}

- (BOOL)brand {
    return [[self valueForConfigKey:kDDAdBlockBrandKey] boolValue];
}
- (void)setBrand:(BOOL)value {
    [self setValue:@(value) forConfigKey:kDDAdBlockBrandKey];
}

- (BOOL)finder {
    return [[self valueForConfigKey:kDDAdBlockFinderKey] boolValue];
}
- (void)setFinder:(BOOL)value {
    [self setValue:@(value) forConfigKey:kDDAdBlockFinderKey];
}

- (BOOL)live {
    return [[self valueForConfigKey:kDDAdBlockLiveKey] boolValue];
}
- (void)setLive:(BOOL)value {
    [self setValue:@(value) forConfigKey:kDDAdBlockLiveKey];
}

- (BOOL)miniProgram {
    return [[self valueForConfigKey:kDDAdBlockMiniProgramKey] boolValue];
}
- (void)setMiniProgram:(BOOL)value {
    [self setValue:@(value) forConfigKey:kDDAdBlockMiniProgramKey];
}

- (BOOL)search {
    return [[self valueForConfigKey:kDDAdBlockSearchKey] boolValue];
}
- (void)setSearch:(BOOL)value {
    [self setValue:@(value) forConfigKey:kDDAdBlockSearchKey];
}

- (BOOL)rewardedAdFastPass {
    return [[self valueForConfigKey:kDDAdBlockRewardedAdFastPassKey] boolValue];
}
- (void)setRewardedAdFastPass:(BOOL)value {
    [self setValue:@(value) forConfigKey:kDDAdBlockRewardedAdFastPassKey];
}

- (BOOL)teenagerPopup {
    return [[self valueForConfigKey:kDDAdBlockTeenagerPopupKey] boolValue];
}
- (void)setTeenagerPopup:(BOOL)value {
    [self setValue:@(value) forConfigKey:kDDAdBlockTeenagerPopupKey];
}

@end


static BOOL ddActive(void) { return [DDAdBlockConfig sharedConfig].master; }

// ============================================================================
//  以下 Hook 均经 WCRefine.dylib 字符串集与微信头文件交叉核对：只 Hook WCR 实际
//  引用的"去广告"方法（数据层/解析层/展示层/推送层/上报层/弹窗），不引入猜测类。
//  每个方法经总开关 + 分区开关双重门控；分区开关默认全关。
// ============================================================================

// ---------- 1. 朋友圈广告 ---------- 参考 D.txt，保持不变 ----------
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

// ---------- 2. 公众号广告 ---------- 参考 D.txt，保持不变 ----------
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

// 公众号/小程序 WebView 广告（CSS 隐藏 + URL 黑名单）
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

%hook MMWebViewController
- (id)webViewUserScriptsForConfiguration {
    id scripts = %orig;
    DDAdBlockConfig *cfg = [DDAdBlockConfig sharedConfig];
    if (!(ddActive() && cfg.brand)) return scripts;
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
    if (ddActive() && [DDAdBlockConfig sharedConfig].brand && !arg4) {
        NSString *u = [[(NSURLRequest *)arg2 URL] absoluteString];
        if ([u containsString:@"wxa.wxs.qq.com"] && [u containsString:@"/tmpl/px/"]) return NO;
        if (ddURLIsAd(u)) return NO;
    }
    return %orig;
}
- (void)webViewDidFinishLoad:(id)arg1 navigation:(id)arg2 {
    %orig;
    if (!(ddActive() && [DDAdBlockConfig sharedConfig].brand)) return;
    WKWebView *wv = nil;
    @try { wv = [(id)self valueForKey:@"webView"]; } @catch (__unused NSException *e) {}
    if (![wv isKindOfClass:[WKWebView class]]) return;
    [wv evaluateJavaScript:DDAdBlockInjectJS() completionHandler:nil];
}
%end

// ---------- 3. 视频号广告 ---------- 参考 D.txt + v1.6.1 评论闪退修复 ----------
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

// ---------- 4. 小程序广告（v1.0.1 重点修复"小程序中间有广告"） ----------
// 4.0 开屏广告拦截（D.txt 原有，保持不变）
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

// 4.1 MagicAd 广告位数据层（D.txt 原有，保持不变）
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

// 4.2 【v1.0.1 新增】小程序广告数据对象层 —— 广告对象构造即返回 nil/NO
// 对齐 WCRefine：MagicAdDataItem / MagicAdInfoItem 是广告数据落库/序列化的核心对象，
// 其 getter（adId/adType/adContent/isAd）被置空后，下游"信息流中间广告卡片"因拿不到
// 有效广告对象而不被插入。这是修复"小程序中间有广告"的关键数据层缺口。
%hook MagicAdDataItem
- (id)adId {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return nil;
    return %orig;
}
- (id)adContent {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return nil;
    return %orig;
}
- (long long)adType {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return 0;
    return %orig;
}
- (BOOL)isAd {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return NO;
    return %orig;
}
%end

%hook MagicAdInfoItem
- (id)adId {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return nil;
    return %orig;
}
- (id)adTitle {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return nil;
    return %orig;
}
- (id)adDesc {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return nil;
    return %orig;
}
- (id)adImgUrl {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return nil;
    return %orig;
}
- (BOOL)isValid {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return NO;
    return %orig;
}
%end

// 4.3 【v1.0.1 新增】小程序信息流广告插入层 —— 让"中间插入的广告"被判无效
// WAMiniProgramAdFeedInsert 是小程序首页/信息流"按位置插入广告卡片"的调度器，
// shouldInsertAdAtIndex:/adFeedItemForIndex: 返回 NO/nil 时，广告卡片不会被插入时间线。
%hook WAMiniProgramAdFeedInsert
- (BOOL)shouldInsertAdAtIndex:(unsigned long long)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return NO;
    return %orig;
}
- (id)adFeedItemForIndex:(unsigned long long)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return nil;
    return %orig;
}
- (void)insertAdFeedItems {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return;
    %orig;
}
%end

// WAAdFeedItem 是单条广告 feed 数据对象，isValid/isAd 返回 NO/nil 使其被过滤。
%hook WAAdFeedItem
- (BOOL)isValid {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return NO;
    return %orig;
}
- (BOOL)isAd {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return NO;
    return %orig;
}
- (id)adInfo {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return nil;
    return %orig;
}
%end

// 4.4 【v1.0.1 新增】广告 cell 渲染层兜底（不返回 nil，避免 UITableView 闪退）
// 对齐 v1.6.1 视频号评论修复同源原则：init 永不返回 nil，仅做隐藏/高度归零，
// 真正去广告由 4.2/4.3 数据层 neutralize 完成。若数据层已生效，这些 cell 根本不会被路由到。
%hook WCFinderAdTableViewCell
- (id)initWithStyle:(long long)arg1 reuseIdentifier:(id)arg2 {
    id cell = %orig;
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram && [cell isKindOfClass:[UIView class]]) {
        [(UIView *)cell setHidden:YES];
    }
    return cell;
}
- (void)layoutSubviews {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) {
        %orig;
        if ([(id)self isKindOfClass:[UIView class]]) [(UIView *)self setHidden:YES];
        return;
    }
    %orig;
}
%end

%hook WCFinderCommentAdTableViewCell
- (id)initWithStyle:(long long)arg1 reuseIdentifier:(id)arg2 {
    id cell = %orig;
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram && [cell isKindOfClass:[UIView class]]) {
        [(UIView *)cell setHidden:YES];
    }
    return cell;
}
- (void)layoutSubviews {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) {
        %orig;
        if ([(id)self isKindOfClass:[UIView class]]) [(UIView *)self setHidden:YES];
        return;
    }
    %orig;
}
%end

// 4.5 小程序 WebView 广告组件隐藏（D.txt 原有，保持不变）
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

// ---------- 5. 直播广告 ---------- 参考 D.txt，保持不变 ----------
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

// ---------- 6. 搜索广告 ---------- 参考 D.txt，保持不变 ----------
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

// ---------- 7. 激励广告快速过 ---------- 参考 D.txt，保持不变 ----------
%hook WCFinderRewardAdViewController
- (void)viewDidAppear:(BOOL)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].rewardedFastPass) {
        [(id)self dismissViewControllerAnimated:YES completion:nil];
        return;
    }
    %orig;
}
%end

// ---------- 8. 青少年模式弹窗 ---------- 参考 D.txt，保持不变 ----------
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

// ---------- 9. 广告曝光上报抑制 ---------- 参考 D.txt，保持不变 ----------
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

// ========== 设置界面（对齐 DD后台高斯模糊）==========

#pragma mark - 微信私有接口声明（运行时 objc_getClass 获取，编译期无需 @class）

@interface WCPluginsMgr : NSObject
+ (instancetype)sharedInstance;
- (void)registerControllerWithTitle:(NSString *)title version:(NSString *)version controller:(NSString *)controller;
@end

@interface WCTableViewManager : NSObject
- (instancetype)initWithFrame:(struct CGRect)arg1 style:(long long)arg2;
- (void)clearAllSection;
- (id)getTableView;          // ← 参考代码：方法，非属性
- (void)addSection:(id)arg1;
- (void)reloadTableView;
@end

@interface WCTableViewSectionManager : NSObject
+ (id)defaultSection;
+ (id)sectionInfoHeader:(NSString *)header;
- (void)addCell:(id)arg1;
@end

@interface WCTableViewCellManager : NSObject
+ (id)switchCellForSel:(SEL)arg1 target:(id)arg2 title:(id)arg3 on:(BOOL)arg4;
@end

#pragma mark - 设置界面

@interface DDAdBlockSettingsViewController : UIViewController
@property (nonatomic, strong) WCTableViewManager *tableViewManager;
@end

@implementation DDAdBlockSettingsViewController

- (void)ensureTableViewManager {
    if (_tableViewManager) return;
    Class managerCls = objc_getClass("WCTableViewManager");
    if (!managerCls) return;
    _tableViewManager = [[managerCls alloc] initWithFrame:[UIScreen mainScreen].bounds
                                                   style:UITableViewStyleInsetGrouped];
}

- (instancetype)init {
    if (self = [super init]) {
        [self ensureTableViewManager];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"DD广告拦截";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    [self ensureTableViewManager];
    if (!_tableViewManager) return;
    [self buildTable];
    // ✅ 参考代码：getTableView 方法，非 .tableView 属性
    UITableView *tableView = [_tableViewManager getTableView];
    tableView.frame = self.view.bounds;
    tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentAutomatic;
    [self.view addSubview:tableView];
}

- (void)buildTable {
    Class cellCls    = objc_getClass("WCTableViewCellManager");
    Class sectionCls = objc_getClass("WCTableViewSectionManager");
    if (!cellCls || !sectionCls || !_tableViewManager) return;

    [_tableViewManager clearAllSection];   // ✅ 参考代码：clearAllSection
    DDAdBlockConfig *cfg = DDAdBlockConfig.sharedConfig;

    // ✅ 参考代码：sectionInfoHeader:（不用不存在的 sectionWithHeader:）
    id secMain = [sectionCls sectionInfoHeader:@"广告拦截开关"];
    [secMain addCell:[cellCls switchCellForSel:@selector(onMasterSwitch:)       target:self title:@"启用广告拦截"        on:cfg.master]];
    [secMain addCell:[cellCls switchCellForSel:@selector(onMomentsSwitch:)      target:self title:@"屏蔽朋友圈广告"      on:cfg.moments]];
    [secMain addCell:[cellCls switchCellForSel:@selector(onBrandSwitch:)        target:self title:@"屏蔽公众号广告"      on:cfg.brand]];
    [secMain addCell:[cellCls switchCellForSel:@selector(onFinderSwitch:)       target:self title:@"屏蔽视频号广告"      on:cfg.finder]];
    [secMain addCell:[cellCls switchCellForSel:@selector(onLiveSwitch:)         target:self title:@"屏蔽直播广告"        on:cfg.live]];
    [secMain addCell:[cellCls switchCellForSel:@selector(onMiniProgramSwitch:)  target:self title:@"屏蔽小程序广告"      on:cfg.miniProgram]];
    [_tableViewManager addSection:secMain];

    id secAdv = [sectionCls sectionInfoHeader:@"进阶拦截"];
    [secAdv addCell:[cellCls switchCellForSel:@selector(onSearchSwitch:)     target:self title:@"屏蔽搜索广告"        on:cfg.search]];
    [secAdv addCell:[cellCls switchCellForSel:@selector(onRewardedSwitch:)   target:self title:@"激励广告快速跳过"    on:cfg.rewardedFastPass]];
    [secAdv addCell:[cellCls switchCellForSel:@selector(onTeenagerSwitch:)  target:self title:@"关闭青少年模式弹窗"  on:cfg.teenagerPopup]];
    [_tableViewManager addSection:secAdv];

    [_tableViewManager reloadTableView];
}

- (void)onMasterSwitch:(UISwitch *)s        { DDAdBlockConfig.sharedConfig.master = s.isOn;        [self buildTable]; }
- (void)onMomentsSwitch:(UISwitch *)s       { DDAdBlockConfig.sharedConfig.moments = s.isOn;       [self buildTable]; }
- (void)onBrandSwitch:(UISwitch *)s         { DDAdBlockConfig.sharedConfig.brand = s.isOn;         [self buildTable]; }
- (void)onFinderSwitch:(UISwitch *)s        { DDAdBlockConfig.sharedConfig.finder = s.isOn;        [self buildTable]; }
- (void)onLiveSwitch:(UISwitch *)s          { DDAdBlockConfig.sharedConfig.live = s.isOn;          [self buildTable]; }
- (void)onMiniProgramSwitch:(UISwitch *)s   { DDAdBlockConfig.sharedConfig.miniProgram = s.isOn;   [self buildTable]; }
- (void)onSearchSwitch:(UISwitch *)s        { DDAdBlockConfig.sharedConfig.search = s.isOn;        [self buildTable]; }
- (void)onRewardedSwitch:(UISwitch *)s      { DDAdBlockConfig.sharedConfig.rewardedFastPass = s.isOn; [self buildTable]; }
- (void)onTeenagerSwitch:(UISwitch *)s      { DDAdBlockConfig.sharedConfig.teenagerPopup = s.isOn; [self buildTable]; }
@end

// ========== 插件注册（对齐 DD后台高斯模糊 %ctor）==========
%ctor {
    @autoreleasepool {
        Class mgrClass = objc_getClass("WCPluginsMgr");
        if (mgrClass && [mgrClass respondsToSelector:@selector(sharedInstance)]) {
            id mgr = [mgrClass sharedInstance];
            if ([mgr respondsToSelector:@selector(registerControllerWithTitle:version:controller:)]) {
                [mgr registerControllerWithTitle:@"DD广告拦截"
                                         version:@"1.0.0"
                                      controller:@"DDAdBlockSettingsViewController"];
            }
        }
    }
}
