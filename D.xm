//
//  DDAdBlock.xm
//  DD广告拦截 v1.0.0 — 微信全场景广告拦截插件（Theos/Logos tweak）
//
//  功能：默认全开，覆盖朋友圈/公众号/视频号/直播/小程序/搜索/网络层/激励广告/实验开关广告抑制。
//  核心修复（相对早期版本）：视频号评论区 hook 不返回 nil，保证 UITableView 数据源完整，
//  广告拦截下沉到 WCFinderComment 数据层（advertisementInfo/commentAdImageUrl → nil）。
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

// ========== 配置开关 Key（DDAdBlock 前缀，默认全开） ==========
static NSString * const kDDAdBlockMasterKey            = @"DDAdBlock_MasterEnabled";
static NSString * const kDDAdBlockMomentsKey           = @"DDAdBlock_MomentsEnabled";
static NSString * const kDDAdBlockBrandKey             = @"DDAdBlock_BrandEnabled";
static NSString * const kDDAdBlockFinderKey            = @"DDAdBlock_FinderEnabled";
static NSString * const kDDAdBlockLiveKey              = @"DDAdBlock_LiveEnabled";
static NSString * const kDDAdBlockMiniProgramKey       = @"DDAdBlock_MiniProgramEnabled";
static NSString * const kDDAdBlockNetworkKey           = @"DDAdBlock_NetworkEnabled";
static NSString * const kDDAdBlockSearchKey            = @"DDAdBlock_SearchEnabled";
static NSString * const kDDAdBlockRewardedFastPassKey  = @"DDAdBlock_RewardedFastPassEnabled";
static NSString * const kDDAdBlockExptKey              = @"DDAdBlock_ExptEnabled";

// ========== 配置类 ==========
@interface DDAdBlockConfig : NSObject
+ (instancetype)sharedConfig;
@property (assign, nonatomic) BOOL master;
@property (assign, nonatomic) BOOL moments;
@property (assign, nonatomic) BOOL brand;
@property (assign, nonatomic) BOOL finder;
@property (assign, nonatomic) BOOL live;
@property (assign, nonatomic) BOOL miniProgram;
@property (assign, nonatomic) BOOL network;
@property (assign, nonatomic) BOOL search;
@property (assign, nonatomic) BOOL rewardedFastPass;
@property (assign, nonatomic) BOOL expt;
@end

// setter 宏：name_lc 为属性名（全小写），与编译器自动合成的 _name_lc ivar 一致。
#define DDADBLOCK_SETTER(name_lc, key) \
    -(void)set##name_lc:(BOOL)v { \
        _##name_lc = v; \
        [[NSUserDefaults standardUserDefaults] setBool:v forKey:key]; \
    }

@implementation DDAdBlockConfig
+ (instancetype)sharedConfig {
    static DDAdBlockConfig *c = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ c = [DDAdBlockConfig new]; });
    return c;
}
- (instancetype)init {
    if (self = [super init]) {
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        if ([ud objectForKey:kDDAdBlockMasterKey] == nil) [ud setBool:YES forKey:kDDAdBlockMasterKey];
        if ([ud objectForKey:kDDAdBlockMomentsKey] == nil) [ud setBool:YES forKey:kDDAdBlockMomentsKey];
        if ([ud objectForKey:kDDAdBlockBrandKey] == nil) [ud setBool:YES forKey:kDDAdBlockBrandKey];
        if ([ud objectForKey:kDDAdBlockFinderKey] == nil) [ud setBool:YES forKey:kDDAdBlockFinderKey];
        if ([ud objectForKey:kDDAdBlockLiveKey] == nil) [ud setBool:YES forKey:kDDAdBlockLiveKey];
        if ([ud objectForKey:kDDAdBlockMiniProgramKey] == nil) [ud setBool:YES forKey:kDDAdBlockMiniProgramKey];
        if ([ud objectForKey:kDDAdBlockNetworkKey] == nil) [ud setBool:YES forKey:kDDAdBlockNetworkKey];
        if ([ud objectForKey:kDDAdBlockSearchKey] == nil) [ud setBool:YES forKey:kDDAdBlockSearchKey];
        if ([ud objectForKey:kDDAdBlockRewardedFastPassKey] == nil) [ud setBool:YES forKey:kDDAdBlockRewardedFastPassKey];
        if ([ud objectForKey:kDDAdBlockExptKey] == nil) [ud setBool:YES forKey:kDDAdBlockExptKey];

        _master = [ud boolForKey:kDDAdBlockMasterKey];
        _moments = [ud boolForKey:kDDAdBlockMomentsKey];
        _brand = [ud boolForKey:kDDAdBlockBrandKey];
        _finder = [ud boolForKey:kDDAdBlockFinderKey];
        _live = [ud boolForKey:kDDAdBlockLiveKey];
        _miniProgram = [ud boolForKey:kDDAdBlockMiniProgramKey];
        _network = [ud boolForKey:kDDAdBlockNetworkKey];
        _search = [ud boolForKey:kDDAdBlockSearchKey];
        _rewardedFastPass = [ud boolForKey:kDDAdBlockRewardedFastPassKey];
        _expt = [ud boolForKey:kDDAdBlockExptKey];
    }
    return self;
}

DDADBLOCK_SETTER(master,            kDDAdBlockMasterKey)
DDADBLOCK_SETTER(moments,           kDDAdBlockMomentsKey)
DDADBLOCK_SETTER(brand,             kDDAdBlockBrandKey)
DDADBLOCK_SETTER(finder,            kDDAdBlockFinderKey)
DDADBLOCK_SETTER(live,              kDDAdBlockLiveKey)
DDADBLOCK_SETTER(miniProgram,       kDDAdBlockMiniProgramKey)
DDADBLOCK_SETTER(network,           kDDAdBlockNetworkKey)
DDADBLOCK_SETTER(search,            kDDAdBlockSearchKey)
DDADBLOCK_SETTER(rewardedFastPass,  kDDAdBlockRewardedFastPassKey)
DDADBLOCK_SETTER(expt,              kDDAdBlockExptKey)
@end

// 总开关守卫
static BOOL DDAdBlockActive(void) { return [DDAdBlockConfig sharedConfig].master; }

// ========== 1. 朋友圈广告拦截 ==========
%hook WCAdvertiseDataHelper
- (void)saveAdPullCompareInfo:(id)arg1 { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].moments) return; %orig; }
- (void)saveAdvertiseMsgXmlDatas { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].moments) return; %orig; }
- (void)addAdvertiseDataList:(id)arg1 { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].moments) return; %orig; }
- (void)addAdvertiseData:(id)arg1 needUpdateCreateTime:(BOOL)arg2 { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].moments) return; %orig; }
- (void)saveAdvertiseDatas { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].moments) return; %orig; }
- (void)tryLoadAdvertiseData { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].moments) return; %orig; }
- (id)m_advertiseList { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].moments) return nil; return %orig; }
- (id)m_advertiseMsgXmlList { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].moments) return nil; return %orig; }
- (BOOL)m_bLoaded { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].moments) return NO; return %orig; }
- (BOOL)IsAdvertiseDataValid:(id)arg1 dataItem:(id)arg2 { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].moments) return NO; return %orig; }
- (BOOL)isAdPreviewExpired:(id)arg1 { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].moments) return YES; return %orig; }
%end

%hook WCAdDB
- (void)createPullRecordTable { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].moments) return; %orig; }
- (void)createTables { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].moments) return; %orig; }
- (void)initDB { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].moments) return; %orig; }
%end

%hook WCAdvertiseInfo
+ (id)dictionaryFromADDynamicInfo:(id)arg1 { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].moments) return nil; return %orig; }
- (id)adType { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].moments) return nil; return %orig; }
- (id)h5PageWrap { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].moments) return nil; return %orig; }
- (id)poiH5PageWrap { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].moments) return nil; return %orig; }
- (long long)previewExpiredTime { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].moments) return 0; return %orig; }
- (BOOL)adExpired { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].moments) return YES; return %orig; }
- (BOOL)setItem:(id)arg1 value:(id)arg2 forDynamic:(id)arg3 { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].moments) return NO; return %orig; }
%end

// ========== 2. 公众号广告拦截 ==========
%hook BrandTLExptConfig
- (BOOL)isExptNotShowAd { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].expt) return YES; return %orig; }
- (BOOL)isExptNotShowFinderLiveBar { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].expt) return YES; return %orig; }
- (BOOL)isExptNotShowRecCard { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].expt) return YES; return %orig; }
- (BOOL)isExptNotShowRecoFlow { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].expt) return YES; return %orig; }
- (unsigned int)exptShowOption { unsigned int v = %orig; if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].expt) return v & ~2U; return v; }
- (void)setExptShowOption:(unsigned int)arg1 { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].expt) { %orig(arg1 & ~2U); return; } %orig; }
%end

%hook BrandTLCanvasCardMgr
- (BOOL)isAdCardOpen { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].brand) return NO; return %orig; }
- (BOOL)isAdRequestOpen { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].brand) return NO; return %orig; }
- (void)handleBizAdNotifyNewXml:(id)arg1 { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].brand) return; %orig; }
%end

%hook BrandAdDataParser
+ (id)adDataItemForContent:(id)arg1 { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].brand) return nil; return %orig; }
+ (id)adDataItemForMsgWrap:(id)arg1 { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].brand) return nil; return %orig; }
+ (id)adInfoDicForContent:(id)arg1 { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].brand) return nil; return %orig; }
+ (id)adInfoDicForMsgWrap:(id)arg1 { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].brand) return nil; return %orig; }
+ (id)bizTypeForAdInfoDic:(id)arg1 { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].brand) return nil; return %orig; }
+ (id)traceIdForAdInfoDic:(id)arg1 { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].brand) return nil; return %orig; }
%end

%hook BrandAdDataItem
- (id)content { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].brand) return nil; return %orig; }
- (id)dicAdInfo { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].brand) return nil; return %orig; }
%end

%hook WCAdXmlParser
+ (BOOL)ExtractRecommendAdInfo:(id)arg1 ByAdMsgXml:(id)arg2 { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].brand) return NO; return %orig; }
+ (BOOL)SetAdvertiseXml:(id)arg1 ByAdXml:(id)arg2 { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].brand) return NO; return %orig; }
+ (BOOL)SetAdvertiseInfo:(id)arg1 ByAdInfoXml:(struct XmlReaderNode_t *)arg2 { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].brand) return NO; return %orig; }
+ (BOOL)SetAdvertiseInfo:(id)arg1 ByAdInfo:(id)arg2 { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].brand) return NO; return %orig; }
%end

// 公众号广告 JS 桥拦截
%hook MBEventHandler_getAdPushMsg
- (void)invoke:(id)arg1 { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].brand) return; %orig; }
%end
%hook MBEventHandler_getOldAdInfo
- (void)invoke:(id)arg1 { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].brand) return; %orig; }
%end
%hook MBEventHandler_setAdRequestInfo
- (void)invoke:(id)arg1 { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].brand) return; %orig; }
%end
%hook MBEventHandler_setAdCardRequestInfo
- (void)invoke:(id)arg1 { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].brand) return; %orig; }
%end
%hook MBEventHandler_setFeedsAdRequestInfo
- (void)invoke:(id)arg1 { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].brand) return; %orig; }
%end

%hook WebviewJSEventHandler_getAdIdInfo
- (BOOL)checkUrlValid {
    DDAdBlockConfig *cfg = [DDAdBlockConfig sharedConfig];
    if (DDAdBlockActive() && (cfg.brand || cfg.miniProgram || cfg.network)) return NO;
    return %orig;
}
- (void)handleJSEvent:(id)arg1 HandlerFacade:(id)arg2 ExtraData:(id)arg3 {
    if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].moments) return; %orig;
}
%end

%hook WebviewJSEventHandler_adDataReport
- (void)handleJSEvent:(id)arg1 HandlerFacade:(id)arg2 ExtraData:(id)arg3 {
    DDAdBlockConfig *cfg = [DDAdBlockConfig sharedConfig];
    if (DDAdBlockActive() && (cfg.brand || cfg.miniProgram || cfg.network)) return;
    %orig;
}
%end

// 公众号 Flutter 页广告拦截
%hook BrandTLFlutterViewController
- (BOOL)enableAd { if (DDAdBlockActive()) return NO; return %orig; }
- (void)setEnableAd:(BOOL)arg1 { if (DDAdBlockActive()) return; %orig; }
- (void)reportAdBrandCardOnClick { if (DDAdBlockActive()) return; %orig; }
- (id)initWithExptConfig:(id)arg1 { if (DDAdBlockActive()) return nil; return %orig; }
- (id)getMagicBrushFlutterPlugins { if (DDAdBlockActive()) return nil; return %orig; }
%end

// 品牌广告服务拦截
%hook _TtC6WeChat19MagicAdBrandService
- (void)notifyAdServerInfoEventWithFeedsType:(long long)arg1 adInfo:(id)arg2 { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].brand) return; %orig; }
- (void)destroyBrandServiceBizWithScene:(id)arg1 { if (DDAdBlockActive()) return; %orig; }
- (void)createBrandServiceBizWithScene:(id)arg1 { if (DDAdBlockActive()) return; %orig; }
- (void)notifyFrameSetInfoWithMsgId:(id)arg1 frameSetName:(id)arg2 frameSetData:(id)arg3 { if (DDAdBlockActive()) return; %orig; }
- (void)notifyStateChangeWithEventName:(id)arg1 { if (DDAdBlockActive()) return; %orig; }
- (id)getDynamicCardType { if (DDAdBlockActive()) return nil; return %orig; }
- (BOOL)shouldPreLayoutWhenExpose { if (DDAdBlockActive()) return NO; return %orig; }
- (BOOL)isBrandTimelineOpen { if (DDAdBlockActive()) return NO; return %orig; }
%end

// 公众号文章广告 DOM/CSS 兜底隐藏
static NSString *DDAdBlockArticleAdCSS(void) {
    return @".iframe_ad_container,.iframe_adv_ad_container,.comment-ad-container,"
            "li.cidad_comment_constant_key,#cidad_comment_constant_key,"
            ".adv_keyword_search,.ad_control-tips"
            "{display:none!important;height:0!important;min-height:0!important;"
            "margin:0!important;padding:0!important;overflow:hidden!important;}"
            "div:has(> .iframe_ad_container),li:has(> .comment-ad-container)"
            "{display:none!important;height:0!important;}";
}

%hook MMWebViewController
- (void)webViewDidFinishLoad:(id)arg1 navigation:(id)arg2 {
    %orig;
    DDAdBlockConfig *cfg = [DDAdBlockConfig sharedConfig];
    if (!(DDAdBlockActive() && (cfg.brand || cfg.network))) return;
    WKWebView *wv = nil;
    @try { wv = [(id)self valueForKey:@"webView"]; } @catch (__unused NSException *e) {}
    if (![wv isKindOfClass:[WKWebView class]]) return;
    [wv evaluateJavaScript:DDAdBlockArticleAdCSS() completionHandler:nil];
}
%end

// ========== 3. 视频号广告拦截（核心修复：评论区不返回 nil） ==========
%hook WCFinderComment
- (id)advertisementInfo { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].finder) return nil; return %orig; }
- (id)commentAdImageUrl { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].finder) return nil; return %orig; }
%end

%hook FinderObjectAdInfo
- (id)adDesc { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].finder) return nil; return %orig; }
- (id)adH5 { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].finder) return nil; return %orig; }
- (id)adLeadLink { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].finder) return nil; return %orig; }
- (id)adMiniApp { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].finder) return nil; return %orig; }
- (id)adItems { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].finder) return nil; return %orig; }
%end

%hook _TtC6WeChat31MBJsEventOnFinderMediaAdPreload
- (void)startPreloadAdMedia { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].finder) return; %orig; }
%end

%hook WCFinderCommentDetailViewModel
- (void)preloadCommentAdResource:(id)arg1 {
    // 保留原实现副作用，避免下游状态未初始化
    if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].finder) { %orig; return; }
    %orig;
}
%end

%hook WCFinderCommentSectionViewModel
- (id)commentSectionViewModelWithRootComment:(id)arg1 {
    // 核心修复：不返回 nil，保证 UITableView 数据源完整，根治评论页闪退
    if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].finder) return %orig;
    return %orig;
}
%end

%hook WCAdFinderInfo
- (BOOL)isValid { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].finder) return NO; return %orig; }
%end

// ========== 4. 小程序广告拦截 ==========
%hook WAAppTaskSplashADConfig
- (NSNumber *)splashADEnableNumber { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].miniProgram) return @(0); return %orig; }
- (BOOL)canShowSplashADWindow { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].miniProgram) return NO; return %orig; }
- (BOOL)splashADHasContent { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].miniProgram) return NO; return %orig; }
- (BOOL)canHotStartShowSplashAD { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].miniProgram) return NO; return %orig; }
- (void)handleShowSplashAdCalled:(BOOL)arg1 { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].miniProgram) return; %orig; }
%end

%hook WAExptProxy
+ (BOOL)shouldShowSplashAD { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].miniProgram) return NO; return %orig; }
%end

%hook WAAppTask
- (BOOL)isSplashADFinished { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].miniProgram) return YES; return %orig; }
%end

%hook WAJSEventHandler_showSplashAd
- (void)handleJSEvent:(id)arg1 { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].miniProgram) return; %orig; }
%end

%hook WAJSEventHandler_showSplashAdMenu
- (void)handleJSEvent:(id)arg1 { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].miniProgram) return; %orig; }
%end

// 试玩广告秒过
%hook _TtC6WeChat23MagicNewPlayableService
- (void)startWithConfig:(id)arg1 {
    if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].miniProgram) {
        %orig(arg1);
        SEL sel = NSSelectorFromString(@"notifyMiniProgramPlayableStatusWithIsEnd:");
        if (sel) ((void (*)(id, SEL, BOOL))objc_msgSend)((id)self, sel, YES);
        return;
    }
    %orig;
}
- (void)notifyMiniProgramPlayableStatusWithIsEnd:(BOOL)arg1 {
    if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].miniProgram) { %orig(YES); return; }
    %orig;
}
- (void)onCanvasViewFirstFrameRendered:(unsigned int)arg1 { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].miniProgram) return; %orig; }
- (void)onMainScriptInjected:(id)arg1 { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].miniProgram) { %orig; return; } %orig; }
- (void)onDestroy:(id)arg1 { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].miniProgram) { %orig; return; } %orig; }
%end

%hook _TtC6WeChat20MagicPlayableService
- (void)startWithConfig:(id)arg1 {
    if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].miniProgram) {
        %orig(arg1);
        SEL sel = NSSelectorFromString(@"notifyMiniProgramPlayableStatusWithIsEnd:");
        if (sel) ((void (*)(id, SEL, BOOL))objc_msgSend)((id)self, sel, YES);
        return;
    }
    %orig;
}
- (void)notifyMiniProgramPlayableStatusWithIsEnd:(BOOL)arg1 {
    if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].miniProgram) { %orig(YES); return; }
    %orig;
}
- (void)onCanvasViewFirstFrameRendered:(unsigned int)arg1 { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].miniProgram) return; %orig; }
- (void)onDestroy:(id)arg1 { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].miniProgram) { %orig; return; } %orig; }
%end

// 试玩广告 JS 桥拦截
%hook _TtC6WeChat43WAJSEventHandler_predownloadPlayablePackage
- (void)handleJSEvent:(id)arg1 { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].miniProgram) return; %orig; }
%end
%hook _TtC6WeChat46WAJSEventHandler_insertMiniProgramPlayableView
- (void)handleJSEvent:(id)arg1 { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].miniProgram) return; %orig; }
%end
%hook _TtC6WeChat46WAJSEventHandler_removeMiniProgramPlayableView
- (void)handleJSEvent:(id)arg1 { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].miniProgram) return; %orig; }
%end
%hook _TtC6WeChat49WAJSEventHandler_removeMiniProgramPlayableViewNew
- (void)handleJSEvent:(id)arg1 { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].miniProgram) return; %orig; }
%end
%hook _TtC6WeChat49WAJSEventHandler_insertMiniProgramPlayableViewNew
- (void)handleJSEvent:(id)arg1 { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].miniProgram) return; %orig; }
%end
%hook _TtC6WeChat46MPEventHandler_notifyMiniProgramPlayableStatus
- (void)invoke:(id)arg1 { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].miniProgram) return; %orig; }
%end
%hook _TtC6WeChat49MBEventHandler_notifyMiniProgramPlayableStatusNew
- (void)invoke:(id)arg1 { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].miniProgram) return; %orig; }
%end

// 开屏广告窗口拦截
%hook WASplashADWindow
- (void)showRootViewControllerAnimated:(BOOL)arg1 completion:(id)arg2 {
    if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].miniProgram) {
        if (arg2) { @try { ((void (^)(id))arg2)(nil); } @catch (__unused NSException *e) {} }
        return;
    }
    %orig;
}
%end

// 广告推送拦截
%hook MagicAdPushMgrService
- (void)handleAdMsg:(id)arg1 { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].miniProgram) return; %orig; }
- (void)OnGetNewXmlMsg:(id)arg1 Type:(id)arg2 MsgWrap:(id)arg3 { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].miniProgram) return; %orig; }
%end

%hook WCAdvertisePushService
- (void)handlePushMsg:(id)arg1 { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].miniProgram) return; %orig; }
- (void)OnGetNewXmlMsg:(id)arg1 Type:(id)arg2 MsgWrap:(id)arg3 { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].moments) return; %orig; }
%end

// ========== 5. 网络层广告拦截 ==========
static NSString * const kDDAdBlockAdURLPattern = @"advert_group|getadvert|getAdPreloadData|ad_posid|_ads_|/ads_|advertisement_";
static BOOL DDAdBlockURLIsAdRequest(NSURL *url) {
    if (!url) return NO;
    NSString *s = [url absoluteString];
    if (s.length == 0) return NO;
    // 跳过激励广告请求，避免误伤正常业务
    if ([s rangeOfString:@"reward" options:NSCaseInsensitiveSearch].location != NSNotFound) return NO;
    return [s rangeOfString:kDDAdBlockAdURLPattern options:NSRegularExpressionSearch].location != NSNotFound;
}

%hook NSURLSession
- (id)dataTaskWithRequest:(NSURLRequest *)arg1 completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))arg2 {
    DDAdBlockConfig *cfg = [DDAdBlockConfig sharedConfig];
    if (DDAdBlockActive() && (cfg.network || cfg.miniProgram) && !cfg.rewardedFastPass && DDAdBlockURLIsAdRequest([arg1 URL])) {
        NSURLRequest *dr = [NSURLRequest requestWithURL:[NSURL URLWithString:@"data:text/plain;charset=utf-8,"]];
        return %orig(dr, arg2);
    }
    return %orig;
}
- (id)dataTaskWithRequest:(NSURLRequest *)arg1 {
    DDAdBlockConfig *cfg = [DDAdBlockConfig sharedConfig];
    if (DDAdBlockActive() && (cfg.network || cfg.miniProgram) && !cfg.rewardedFastPass && DDAdBlockURLIsAdRequest([arg1 URL])) {
        NSURLRequest *dr = [NSURLRequest requestWithURL:[NSURL URLWithString:@"data:text/plain;charset=utf-8,"]];
        return %orig(dr);
    }
    return %orig;
}
- (id)uploadTaskWithRequest:(NSURLRequest *)arg1 fromData:(NSData *)arg2 completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))arg3 {
    DDAdBlockConfig *cfg = [DDAdBlockConfig sharedConfig];
    if (DDAdBlockActive() && (cfg.network || cfg.miniProgram) && !cfg.rewardedFastPass && DDAdBlockURLIsAdRequest([arg1 URL])) {
        NSURLRequest *dr = [NSURLRequest requestWithURL:[NSURL URLWithString:@"data:text/plain;charset=utf-8,"]];
        return %orig(dr, arg2, arg3);
    }
    return %orig;
}
%end

// ========== 6. 直播广告拦截 ==========
%hook WCFinderAdCountdownBannerView
- (BOOL)adHasPlayOver { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].live) return YES; return %orig; }
- (id)initWithFrame:(CGRect)arg1 countdownNum:(long long)arg2 {
    if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].miniProgram && arg2 > 1) return %orig(arg1, 1);
    return %orig;
}
%end

// ========== 7. 搜索广告拦截 ==========
%hook WCAdSearchH5Info
+ (id)fromXML:(struct XmlReaderNode_t *)arg1 { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].search) return nil; return %orig; }
- (int)adType { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].moments) return 0; return %orig; }
%end

// ========== 8. 激励广告快速跳过 ==========
%hook WCFinderRewardAdViewController
- (BOOL)adHasPlayOver { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].rewardedFastPass) return YES; return %orig; }
%end

// ========== 9. 广告上报拦截 ==========
%hook WCAdvertiseStatMgr
- (id)getAdvertiseInfoForItem:(id)arg1 { if (DDAdBlockActive()) return nil; return %orig; }
- (void)logHeadImageH5:(id)arg1 { if (DDAdBlockActive()) return; %orig; }
- (void)logADBrandProfile:(id)arg1 { if (DDAdBlockActive()) return; %orig; }
- (void)logADFloatView:(id)arg1 { if (DDAdBlockActive()) return; %orig; }
- (void)logADPoiH5:(id)arg1 { if (DDAdBlockActive()) return; %orig; }
- (void)logADH5:(id)arg1 withUserInfo:(id)arg2 reportType:(unsigned long long)arg3 { if (DDAdBlockActive()) return; %orig; }
- (void)logADH5:(id)arg1 { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].moments) return; %orig; }
- (void)logADDetail:(id)arg1 dataItem:(id)arg2 { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].moments) return; %orig; }
- (void)logSphereViewWithSphereReportInfo:(id)arg1 dataItem:(id)arg2 scene:(id)arg3 { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].moments) return; %orig; }
- (void)logSphereViewInDetailWithWrapInfo:(id)arg1 dataItem:(id)arg2 { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].moments) return; %orig; }
- (void)logSphereViewInTimeLineWithWrapInfo:(id)arg1 dataItem:(id)arg2 { if (DDAdBlockActive() && [DDAdBlockConfig sharedConfig].moments) return; %orig; }
%end

// ========== 设置界面 ==========
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

    WCTableViewSectionManager *secMaster = [sectionCls sectionWithHeader:@"DD广告拦截 v1.0.0"];
    [secMaster addCell:[cellCls switchCellForSel:@selector(onMasterSwitch:) target:self title:@"启用广告拦截" on:cfg.master]];
    [_tableViewManager addSection:secMaster];

    if (cfg.master) {
        WCTableViewSectionManager *secMain = [sectionCls sectionWithHeader:@"广告拦截场景"];
        [secMain addCell:[cellCls switchCellForSel:@selector(onMomentsSwitch:) target:self title:@"屏蔽朋友圈广告" on:cfg.moments]];
        [secMain addCell:[cellCls switchCellForSel:@selector(onBrandSwitch:) target:self title:@"屏蔽公众号广告" on:cfg.brand]];
        [secMain addCell:[cellCls switchCellForSel:@selector(onFinderSwitch:) target:self title:@"屏蔽视频号广告" on:cfg.finder]];
        [secMain addCell:[cellCls switchCellForSel:@selector(onLiveSwitch:) target:self title:@"屏蔽直播广告" on:cfg.live]];
        [secMain addCell:[cellCls switchCellForSel:@selector(onMiniProgramSwitch:) target:self title:@"屏蔽小程序广告" on:cfg.miniProgram]];
        [_tableViewManager addSection:secMain];

        WCTableViewSectionManager *secAdv = [sectionCls sectionWithHeader:@"进阶拦截"];
        [secAdv addCell:[cellCls switchCellForSel:@selector(onNetworkSwitch:) target:self title:@"网络层广告拦截" on:cfg.network]];
        [secAdv addCell:[cellCls switchCellForSel:@selector(onSearchSwitch:) target:self title:@"屏蔽搜索广告" on:cfg.search]];
        [secAdv addCell:[cellCls switchCellForSel:@selector(onRewardedSwitch:) target:self title:@"激励广告快速跳过" on:cfg.rewardedFastPass]];
        [secAdv addCell:[cellCls switchCellForSel:@selector(onExptSwitch:) target:self title:@"实验开关广告抑制" on:cfg.expt]];
        [_tableViewManager addSection:secAdv];
    }
    [_tableViewManager reloadTableView];
}

- (void)onMasterSwitch:(UISwitch *)s { [DDAdBlockConfig sharedConfig].master = s.isOn; [self buildTable]; }
- (void)onMomentsSwitch:(UISwitch *)s { [DDAdBlockConfig sharedConfig].moments = s.isOn; }
- (void)onBrandSwitch:(UISwitch *)s { [DDAdBlockConfig sharedConfig].brand = s.isOn; }
- (void)onFinderSwitch:(UISwitch *)s { [DDAdBlockConfig sharedConfig].finder = s.isOn; }
- (void)onLiveSwitch:(UISwitch *)s { [DDAdBlockConfig sharedConfig].live = s.isOn; }
- (void)onMiniProgramSwitch:(UISwitch *)s { [DDAdBlockConfig sharedConfig].miniProgram = s.isOn; }
- (void)onNetworkSwitch:(UISwitch *)s { [DDAdBlockConfig sharedConfig].network = s.isOn; }
- (void)onSearchSwitch:(UISwitch *)s { [DDAdBlockConfig sharedConfig].search = s.isOn; }
- (void)onRewardedSwitch:(UISwitch *)s { [DDAdBlockConfig sharedConfig].rewardedFastPass = s.isOn; }
- (void)onExptSwitch:(UISwitch *)s { [DDAdBlockConfig sharedConfig].expt = s.isOn; }
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

