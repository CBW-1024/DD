/*
 * FXAdBlock v1.0.0 — 微信全场景广告拦截插件（Theos Logos Tweak）
 * 默认全开，支持开关分场景控制。
 * 核心修复：视频号评论区 Hook 不返回 nil，保证 UITableView 数据源完整，
 *          广告拦截下沉到数据层（WCFinderComment.advertisementInfo 等返回 nil）。
 */

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#import <dispatch/dispatch.h>
#import <objc/runtime.h>

// ================= 插件管理入口 =================
@interface WCPluginsMgr : NSObject
+ (instancetype)sharedInstance;
- (void)registerControllerWithTitle:(NSString *)title version:(NSString *)version controller:(NSString *)controller;
@end

// ================= 配置开关（默认全开） =================
static NSString * const kFXMasterKey            = @"FXAdBlock_MasterEnabled";
static NSString * const kFXMomentsKey           = @"FXAdBlock_MomentsEnabled";
static NSString * const kFXBrandKey             = @"FXAdBlock_BrandEnabled";
static NSString * const kFXFinderKey            = @"FXAdBlock_FinderEnabled";
static NSString * const kFXLiveKey              = @"FXAdBlock_LiveEnabled";
static NSString * const kFXMiniProgramKey       = @"FXAdBlock_MiniProgramEnabled";
static NSString * const kFXNetworkKey           = @"FXAdBlock_NetworkEnabled";
static NSString * const kFXSearchKey            = @"FXAdBlock_SearchEnabled";
static NSString * const kFXRewardedFastPassKey  = @"FXAdBlock_RewardedFastPassEnabled";
static NSString * const kFXExptKey              = @"FXAdBlock_ExptEnabled";

@interface FXAdBlockConfig : NSObject
+ (instancetype)sharedConfig;
@property (assign, nonatomic) BOOL master, moments, brand, finder, live, miniProgram, network, search, rewardedFastPass, expt;
@end

@implementation FXAdBlockConfig
+ (instancetype)sharedConfig {
    static FXAdBlockConfig *c = nil;
    static dispatch_once_t t; dispatch_once(&t, ^{ c = [self new]; });
    return c;
}
- (instancetype)init {
    if ((self = [super init])) {
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        if ([ud objectForKey:kFXMasterKey] == nil)            [ud setBool:YES forKey:kFXMasterKey];
        if ([ud objectForKey:kFXMomentsKey] == nil)           [ud setBool:YES forKey:kFXMomentsKey];
        if ([ud objectForKey:kFXBrandKey] == nil)             [ud setBool:YES forKey:kFXBrandKey];
        if ([ud objectForKey:kFXFinderKey] == nil)            [ud setBool:YES forKey:kFXFinderKey];
        if ([ud objectForKey:kFXLiveKey] == nil)              [ud setBool:YES forKey:kFXLiveKey];
        if ([ud objectForKey:kFXMiniProgramKey] == nil)       [ud setBool:YES forKey:kFXMiniProgramKey];
        if ([ud objectForKey:kFXNetworkKey] == nil)           [ud setBool:YES forKey:kFXNetworkKey];
        if ([ud objectForKey:kFXSearchKey] == nil)            [ud setBool:YES forKey:kFXSearchKey];
        if ([ud objectForKey:kFXRewardedFastPassKey] == nil)  [ud setBool:YES forKey:kFXRewardedFastPassKey];
        if ([ud objectForKey:kFXExptKey] == nil)              [ud setBool:YES forKey:kFXExptKey];
        _master = [ud boolForKey:kFXMasterKey];
        _moments = [ud boolForKey:kFXMomentsKey];
        _brand = [ud boolForKey:kFXBrandKey];
        _finder = [ud boolForKey:kFXFinderKey];
        _live = [ud boolForKey:kFXLiveKey];
        _miniProgram = [ud boolForKey:kFXMiniProgramKey];
        _network = [ud boolForKey:kFXNetworkKey];
        _search = [ud boolForKey:kFXSearchKey];
        _rewardedFastPass = [ud boolForKey:kFXRewardedFastPassKey];
        _expt = [ud boolForKey:kFXExptKey];
    }
    return self;
}
#define FX_SETTER(name, key) -(void)set##name:(BOOL)v { _##name = v; [[NSUserDefaults standardUserDefaults] setBool:v forKey:key]; }
FX_SETTER(Master, kFXMasterKey)
FX_SETTER(Moments, kFXMomentsKey)
FX_SETTER(Brand, kFXBrandKey)
FX_SETTER(Finder, kFXFinderKey)
FX_SETTER(Live, kFXLiveKey)
FX_SETTER(MiniProgram, kFXMiniProgramKey)
FX_SETTER(Network, kFXNetworkKey)
FX_SETTER(Search, kFXSearchKey)
FX_SETTER(RewardedFastPass, kFXRewardedFastPassKey)
FX_SETTER(Expt, kFXExptKey)
#undef FX_SETTER
@end

static BOOL fxActive(void) { return [FXAdBlockConfig sharedConfig].master; }
static FXAdBlockConfig *fxCfg(void) { return [FXAdBlockConfig sharedConfig]; }

// ================= 1. 朋友圈广告 =================
%hook WCAdvertiseDataHelper
- (void)saveAdPullCompareInfo:(id)a { if (fxActive() && fxCfg().moments) return; %orig; }
- (void)saveAdvertiseMsgXmlDatas { if (fxActive() && fxCfg().moments) return; %orig; }
- (void)addAdvertiseDataList:(id)a { if (fxActive() && fxCfg().moments) return; %orig; }
- (void)addAdvertiseData:(id)a needUpdateCreateTime:(BOOL)b { if (fxActive() && fxCfg().moments) return; %orig; }
- (void)saveAdvertiseDatas { if (fxActive() && fxCfg().moments) return; %orig; }
- (void)tryLoadAdvertiseData { if (fxActive() && fxCfg().moments) return; %orig; }
- (id)m_advertiseList { if (fxActive() && fxCfg().moments) return nil; return %orig; }
- (id)m_advertiseMsgXmlList { if (fxActive() && fxCfg().moments) return nil; return %orig; }
- (BOOL)m_bLoaded { if (fxActive() && fxCfg().moments) return NO; return %orig; }
- (BOOL)IsAdvertiseDataValid:(id)a dataItem:(id)b { if (fxActive() && fxCfg().moments) return NO; return %orig; }
- (BOOL)isAdPreviewExpired:(id)a { if (fxActive() && fxCfg().moments) return YES; return %orig; }
%end

%hook WCAdDB
- (void)createPullRecordTable { if (fxActive() && fxCfg().moments) return; %orig; }
- (void)createTables { if (fxActive() && fxCfg().moments) return; %orig; }
- (void)initDB { if (fxActive() && fxCfg().moments) return; %orig; }
%end

%hook WCAdvertiseInfo
+ (id)dictionaryFromADDynamicInfo:(id)a { if (fxActive() && fxCfg().moments) return nil; return %orig; }
- (id)adType { if (fxActive() && fxCfg().moments) return nil; return %orig; }
- (id)h5PageWrap { if (fxActive() && fxCfg().moments) return nil; return %orig; }
- (id)poiH5PageWrap { if (fxActive() && fxCfg().moments) return nil; return %orig; }
- (long long)previewExpiredTime { if (fxActive() && fxCfg().moments) return 0; return %orig; }
- (BOOL)adExpired { if (fxActive() && fxCfg().moments) return YES; return %orig; }
- (BOOL)setItem:(id)a value:(id)b forDynamic:(id)c { if (fxActive() && fxCfg().moments) return NO; return %orig; }
%end

%hook WCADBodyWrap
- (id)init { if (fxActive() && fxCfg().moments) return nil; return %orig; }
%end
%hook WCADCanvasInfo
- (id)init { if (fxActive() && fxCfg().moments) return nil; return %orig; }
%end
%hook WCADPageWrap
- (id)adID { if (fxActive() && fxCfg().moments) return nil; return %orig; }
- (id)miniShopRequestId { if (fxActive() && fxCfg().moments) return nil; return %orig; }
- (id)uxInfo { if (fxActive() && fxCfg().moments) return nil; return %orig; }
- (int)adType { if (fxActive() && fxCfg().moments) return 0; return %orig; }
%end
%hook WCAdCanvasLoadParams
- (id)cacheKey { if (fxActive() && fxCfg().moments) return nil; return %orig; }
- (id)canvasId { if (fxActive() && fxCfg().moments) return nil; return %orig; }
- (id)canvasDynamicInfo { if (fxActive() && fxCfg().moments) return nil; return %orig; }
- (id)dynamicCanvasLibVersion { if (fxActive() && fxCfg().moments) return nil; return %orig; }
%end
%hook WCAdDynamicCanvasPageInfo
- (id)fetchRealUxInfo { if (fxActive() && fxCfg().moments) return nil; return %orig; }
- (id)fetchPageInfoExtraDic { if (fxActive() && fxCfg().moments) return nil; return %orig; }
- (id)fetchPageInfoDic { if (fxActive() && fxCfg().moments) return nil; return %orig; }
- (id)fetchLaunchString { if (fxActive() && fxCfg().moments) return nil; return %orig; }
%end
%hook WCAdDynamicCanvasServerData
- (void)initialize { if (fxActive() && fxCfg().moments) return; %orig; }
- (BOOL)isValid { if (fxActive() && fxCfg().moments) return NO; return %orig; }
- (id)fromPBCodingBuffer:(id)a { if (fxActive() && fxCfg().moments) return nil; return %orig; }
- (void)toPBCodingBuffer { if (fxActive() && fxCfg().moments) return; %orig; }
%end
%hook ObjectAdContentH5
- (id)url { if (fxActive() && fxCfg().moments) return nil; return %orig; }
%end
%hook ObjectAdItem
- (id)adDesc { if (fxActive() && fxCfg().moments) return nil; return %orig; }
- (id)uxinfo { if (fxActive() && fxCfg().moments) return nil; return %orig; }
%end
%hook AdPushMsgDBMgr
- (void)initDB { if (fxActive() && fxCfg().moments) return; %orig; }
- (void)insertNewPushMsg:(id)a { if (fxActive() && fxCfg().moments) return; %orig; }
%end
%hook WCCanvasDynamicDataLoader
- (void)handleAdCanvasInfoResponse:(id)a { if (fxActive() && fxCfg().moments) return; %orig; }
%end

// ================= 2. 公众号广告 =================
%hook BrandTLExptConfig
- (BOOL)isExptNotShowAd { if (fxActive() && fxCfg().expt) return YES; return %orig; }
- (BOOL)isExptNotShowFinderLiveBar { if (fxActive() && fxCfg().expt) return YES; return %orig; }
- (BOOL)isExptNotShowRecCard { if (fxActive() && fxCfg().expt) return YES; return %orig; }
- (BOOL)isExptNotShowRecoFlow { if (fxActive() && fxCfg().expt) return YES; return %orig; }
- (unsigned int)exptShowOption { unsigned int v = %orig; if (fxActive() && fxCfg().expt) return v & ~2U; return v; }
- (void)setExptShowOption:(unsigned int)v { if (fxActive() && fxCfg().expt) { %orig(v & ~2U); return; } %orig; }
%end

%hook BrandTLCanvasCardMgr
- (BOOL)isAdCardOpen { if (fxActive() && fxCfg().brand) return NO; return %orig; }
- (BOOL)isAdRequestOpen { if (fxActive() && fxCfg().brand) return NO; return %orig; }
- (void)handleBizAdNotifyNewXml:(id)a { if (fxActive() && fxCfg().brand) return; %orig; }
%end

%hook BrandAdDataParser
+ (id)adDataItemForContent:(id)a { if (fxActive() && fxCfg().brand) return nil; return %orig; }
+ (id)adDataItemForMsgWrap:(id)a { if (fxActive() && fxCfg().brand) return nil; return %orig; }
+ (id)adInfoDicForContent:(id)a { if (fxActive() && fxCfg().brand) return nil; return %orig; }
+ (id)adInfoDicForMsgWrap:(id)a { if (fxActive() && fxCfg().brand) return nil; return %orig; }
+ (id)bizTypeForAdInfoDic:(id)a { if (fxActive() && fxCfg().brand) return nil; return %orig; }
+ (id)traceIdForAdInfoDic:(id)a { if (fxActive() && fxCfg().brand) return nil; return %orig; }
%end

%hook BrandAdDataItem
- (id)content { if (fxActive() && fxCfg().brand) return nil; return %orig; }
- (id)dicAdInfo { if (fxActive() && fxCfg().brand) return nil; return %orig; }
%end

%hook WCAdXmlParser
+ (BOOL)ExtractRecommendAdInfo:(id)a ByAdMsgXml:(id)b { if (fxActive() && fxCfg().brand) return NO; return %orig; }
+ (BOOL)SetAdvertiseXml:(id)a ByAdXml:(id)b { if (fxActive() && fxCfg().brand) return NO; return %orig; }
+ (BOOL)SetAdvertiseInfo:(id)a ByAdInfoXml:(struct XmlReaderNode_t *)b { if (fxActive() && fxCfg().brand) return NO; return %orig; }
+ (BOOL)SetAdvertiseInfo:(id)a ByAdInfo:(id)b { if (fxActive() && fxCfg().brand) return NO; return %orig; }
%end

%hook MBEventHandler_getAdPushMsg
- (void)invoke:(id)a { if (fxActive() && fxCfg().brand) return; %orig; }
%end
%hook MBEventHandler_getOldAdInfo
- (void)invoke:(id)a { if (fxActive() && fxCfg().brand) return; %orig; }
%end
%hook MBEventHandler_setAdRequestInfo
- (void)invoke:(id)a { if (fxActive() && fxCfg().brand) return; %orig; }
%end
%hook MBEventHandler_setAdCardRequestInfo
- (void)invoke:(id)a { if (fxActive() && fxCfg().brand) return; %orig; }
%end
%hook MBEventHandler_setFeedsAdRequestInfo
- (void)invoke:(id)a { if (fxActive() && fxCfg().brand) return; %orig; }
%end

%hook WebviewJSEventHandler_getAdIdInfo
- (BOOL)checkUrlValid {
    FXAdBlockConfig *c = fxCfg();
    if (fxActive() && (c.brand || c.miniProgram || c.network)) return NO;
    return %orig;
}
- (void)handleJSEvent:(id)a HandlerFacade:(id)b ExtraData:(id)c {
    if (fxActive() && fxCfg().moments) return; %orig;
}
%end

%hook WebviewJSEventHandler_adDataReport
- (void)handleJSEvent:(id)a HandlerFacade:(id)b ExtraData:(id)c {
    FXAdBlockConfig *cf = fxCfg();
    if (fxActive() && (cf.brand || cf.miniProgram || cf.network)) return;
    %orig;
}
%end

%hook BrandTLFlutterViewController
- (BOOL)enableAd { if (fxActive()) return NO; return %orig; }
- (void)setEnableAd:(BOOL)v { if (fxActive()) return; %orig; }
- (void)reportAdBrandCardOnClick { if (fxActive()) return; %orig; }
- (id)initWithExptConfig:(id)a { if (fxActive()) return nil; return %orig; }
- (id)getMagicBrushFlutterPlugins { if (fxActive()) return nil; return %orig; }
%end

%hook _TtC6WeChat19MagicAdBrandService
- (void)notifyAdServerInfoEventWithFeedsType:(long long)a adInfo:(id)b { if (fxActive() && fxCfg().brand) return; %orig; }
- (void)destroyBrandServiceBizWithScene:(id)a { if (fxActive()) return; %orig; }
- (void)createBrandServiceBizWithScene:(id)a { if (fxActive()) return; %orig; }
- (void)notifyFrameSetInfoWithMsgId:(id)a frameSetName:(id)b frameSetData:(id)c { if (fxActive()) return; %orig; }
- (void)notifyStateChangeWithEventName:(id)a { if (fxActive()) return; %orig; }
- (id)getDynamicCardType { if (fxActive()) return nil; return %orig; }
- (BOOL)shouldPreLayoutWhenExpose { if (fxActive()) return NO; return %orig; }
- (BOOL)isBrandTimelineOpen { if (fxActive()) return NO; return %orig; }
%end

%hook _TtC6WeChat20MagicAdPublicService
- (void)onJSException:(id)a msg:(id)b extra:(id)c { if (fxActive()) return; %orig; }
- (void)onDestroy:(id)a { if (fxActive()) return; %orig; }
- (void)onMainScriptInjected:(id)a { if (fxActive()) return; %orig; }
%end
%hook _TtC6WeChat22MagicAdBrandServiceBiz
- (void)onJSException:(id)a msg:(id)b extra:(id)c { if (fxActive()) return; %orig; }
- (void)onMainScriptInjected:(id)a { if (fxActive()) return; %orig; }
%end
%hook _TtC6WeChat28MagicSclBrandAdFlutterPlugin
- (void)onDetachedFromEngine:(id)a { if (fxActive()) return; %orig; }
%end

%hook FlutterBrandTLApiImplementation
- (id)createMagicAdBrandServiceScene:(id)a error:(id *)b { if (fxActive()) return nil; return %orig; }
%end
%hook WCAdFormWebViewJSLogic
- (id)initWithWebView:(id)a pageInfo:(id)b componentId:(id)c qrExtInfo:(id)d { if (fxActive()) return nil; return %orig; }
%end

// 公众号文章广告 DOM/CSS 兜底隐藏
static NSString *FXAdBlockMPHideCSS(void) {
    return @".iframe_ad_container,.iframe_adv_ad_container,.comment-ad-container,"
            "li.cidad_comment_constant_key,#cidad_comment_constant_key,"
            ".adv_keyword_search,.ad_control-tips"
            "{display:none!important;height:0!important;min-height:0!important;"
            "margin:0!important;padding:0!important;overflow:hidden!important;}"
            "div:has(> .iframe_ad_container),li:has(> .comment-ad-container)"
            "{display:none!important;height:0!important;}";
}

%hook MMWebViewController
- (void)webViewDidFinishLoad:(id)a navigation:(id)b {
    %orig;
    FXAdBlockConfig *c = fxCfg();
    if (!(fxActive() && (c.brand || c.network))) return;
    WKWebView *wv = nil;
    @try { wv = [(id)self valueForKey:@"webView"]; } @catch (__unused NSException *e) {}
    if (![wv isKindOfClass:[WKWebView class]]) return;
    [wv evaluateJavaScript:FXAdBlockMPHideCSS() completionHandler:nil];
}
%end

// ================= 3. 视频号广告（核心修复：评论区不返回 nil） =================
%hook WCFinderComment
- (id)advertisementInfo { if (fxActive() && fxCfg().finder) return nil; return %orig; }
- (id)commentAdImageUrl { if (fxActive() && fxCfg().finder) return nil; return %orig; }
%end

%hook FinderObjectAdInfo
- (id)adDesc { if (fxActive() && fxCfg().finder) return nil; return %orig; }
- (id)adH5 { if (fxActive() && fxCfg().finder) return nil; return %orig; }
- (id)adLeadLink { if (fxActive() && fxCfg().finder) return nil; return %orig; }
- (id)adMiniApp { if (fxActive() && fxCfg().finder) return nil; return %orig; }
- (id)adItems { if (fxActive() && fxCfg().finder) return nil; return %orig; }
%end

%hook _TtC6WeChat31MBJsEventOnFinderMediaAdPreload
- (void)startPreloadAdMedia { if (fxActive() && fxCfg().finder) return; %orig; }
%end

%hook WCFinderCommentDetailViewModel
// 修复：保留原实现副作用，避免下游状态未初始化导致异常
- (void)preloadCommentAdResource:(id)a {
    if (fxActive() && fxCfg().finder) { %orig; return; }
    %orig;
}
%end

%hook WCFinderCommentSectionViewModel
// 核心修复：不返回 nil，保证 UITableView 数据源完整，根治"打开视频号评论闪退"
- (id)commentSectionViewModelWithRootComment:(id)a {
    if (fxActive() && fxCfg().finder) return %orig;
    return %orig;
}
%end

%hook WCAdFinderInfo
- (BOOL)isValid { if (fxActive() && fxCfg().finder) return NO; return %orig; }
%end

// ================= 4. 小程序广告 =================
%hook WAAppTaskSplashADConfig
- (NSNumber *)splashADEnableNumber { if (fxActive() && fxCfg().miniProgram) return @(0); return %orig; }
- (BOOL)canShowSplashADWindow { if (fxActive() && fxCfg().miniProgram) return NO; return %orig; }
- (BOOL)splashADHasContent { if (fxActive() && fxCfg().miniProgram) return NO; return %orig; }
- (BOOL)canHotStartShowSplashAD { if (fxActive() && fxCfg().miniProgram) return NO; return %orig; }
- (void)handleShowSplashAdCalled:(BOOL)a { if (fxActive() && fxCfg().miniProgram) return; %orig; }
%end

%hook WAExptProxy
+ (BOOL)shouldShowSplashAD { if (fxActive() && fxCfg().miniProgram) return NO; return %orig; }
%end

%hook WAAppTask
- (BOOL)isSplashADFinished { if (fxActive() && fxCfg().miniProgram) return YES; return %orig; }
%end

%hook WAJSEventHandler_showSplashAd
- (void)handleJSEvent:(id)a { if (fxActive() && fxCfg().miniProgram) return; %orig; }
%end
%hook WAJSEventHandler_showSplashAdMenu
- (void)handleJSEvent:(id)a { if (fxActive() && fxCfg().miniProgram) return; %orig; }
%end

// 试玩广告（Playable）秒过
%hook _TtC6WeChat23MagicNewPlayableService
- (void)startWithConfig:(id)a {
    if (fxActive() && fxCfg().miniProgram) {
        %orig(a);
        SEL s = NSSelectorFromString(@"notifyMiniProgramPlayableStatusWithIsEnd:");
        if (s) ((void (*)(id, SEL, BOOL))objc_msgSend)((id)self, s, YES);
        return;
    }
    %orig;
}
- (void)notifyMiniProgramPlayableStatusWithIsEnd:(BOOL)a {
    if (fxActive() && fxCfg().miniProgram) { %orig(YES); return; } %orig;
}
- (void)onCanvasViewFirstFrameRendered:(unsigned int)a { if (fxActive() && fxCfg().miniProgram) return; %orig; }
- (void)onMainScriptInjected:(id)a { if (fxActive() && fxCfg().miniProgram) { %orig; return; } %orig; }
- (void)onDestroy:(id)a { if (fxActive() && fxCfg().miniProgram) { %orig; return; } %orig; }
%end

%hook _TtC6WeChat20MagicPlayableService
- (void)startWithConfig:(id)a {
    if (fxActive() && fxCfg().miniProgram) {
        %orig(a);
        SEL s = NSSelectorFromString(@"notifyMiniProgramPlayableStatusWithIsEnd:");
        if (s) ((void (*)(id, SEL, BOOL))objc_msgSend)((id)self, s, YES);
        return;
    }
    %orig;
}
- (void)notifyMiniProgramPlayableStatusWithIsEnd:(BOOL)a {
    if (fxActive() && fxCfg().miniProgram) { %orig(YES); return; } %orig;
}
- (void)onCanvasViewFirstFrameRendered:(unsigned int)a { if (fxActive() && fxCfg().miniProgram) return; %orig; }
- (void)onDestroy:(id)a { if (fxActive() && fxCfg().miniProgram) { %orig; return; } %orig; }
%end

%hook _TtC6WeChat43WAJSEventHandler_predownloadPlayablePackage
- (void)handleJSEvent:(id)a { if (fxActive() && fxCfg().miniProgram) return; %orig; }
%end
%hook _TtC6WeChat46WAJSEventHandler_insertMiniProgramPlayableView
- (void)handleJSEvent:(id)a { if (fxActive() && fxCfg().miniProgram) return; %orig; }
%end
%hook _TtC6WeChat46WAJSEventHandler_removeMiniProgramPlayableView
- (void)handleJSEvent:(id)a { if (fxActive() && fxCfg().miniProgram) return; %orig; }
%end
%hook _TtC6WeChat49WAJSEventHandler_removeMiniProgramPlayableViewNew
- (void)handleJSEvent:(id)a { if (fxActive() && fxCfg().miniProgram) return; %orig; }
%end
%hook _TtC6WeChat49WAJSEventHandler_insertMiniProgramPlayableViewNew
- (void)handleJSEvent:(id)a { if (fxActive() && fxCfg().miniProgram) return; %orig; }
%end
%hook _TtC6WeChat46MPEventHandler_notifyMiniProgramPlayableStatus
- (void)invoke:(id)a { if (fxActive() && fxCfg().miniProgram) return; %orig; }
%end
%hook _TtC6WeChat49MBEventHandler_notifyMiniProgramPlayableStatusNew
- (void)invoke:(id)a { if (fxActive() && fxCfg().miniProgram) return; %orig; }
%end

%hook WASplashADWindow
- (void)showRootViewControllerAnimated:(BOOL)a completion:(id)b {
    if (fxActive() && fxCfg().miniProgram) {
        if (b) { @try { ((void (^)(id))b)(nil); } @catch (__unused NSException *e) {} }
        return;
    }
    %orig;
}
%end

%hook MagicAdPushMgrService
- (void)handleAdMsg:(id)a { if (fxActive() && fxCfg().miniProgram) return; %orig; }
- (void)OnGetNewXmlMsg:(id)a Type:(id)b MsgWrap:(id)c { if (fxActive() && fxCfg().miniProgram) return; %orig; }
%end

%hook WCAdvertisePushService
- (void)handlePushMsg:(id)a { if (fxActive() && fxCfg().miniProgram) return; %orig; }
- (void)OnGetNewXmlMsg:(id)a Type:(id)b MsgWrap:(id)c { if (fxActive() && fxCfg().moments) return; %orig; }
%end

// ================= 5. 网络层广告拦截 =================
static NSString * const kFXAdURLPattern = @"advert_group|getadvert|getAdPreloadData|ad_posid|_ads_|/ads_|advertisement_";
static BOOL FXURLIsAd(NSURL *url) {
    if (!url) return NO;
    NSString *s = [url absoluteString];
    if (s.length == 0) return NO;
    if ([s rangeOfString:@"reward" options:NSCaseInsensitiveSearch].location != NSNotFound) return NO;
    return [s rangeOfString:kFXAdURLPattern options:NSRegularExpressionSearch].location != NSNotFound;
}

%hook NSURLSession
- (id)dataTaskWithRequest:(NSURLRequest *)a completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))b {
    FXAdBlockConfig *c = fxCfg();
    if (fxActive() && (c.network || c.miniProgram) && !c.rewardedFastPass && FXURLIsAd([a URL])) {
        NSURLRequest *dr = [NSURLRequest requestWithURL:[NSURL URLWithString:@"data:text/plain;charset=utf-8,"]];
        return %orig(dr, b);
    }
    return %orig;
}
- (id)dataTaskWithRequest:(NSURLRequest *)a {
    FXAdBlockConfig *c = fxCfg();
    if (fxActive() && (c.network || c.miniProgram) && !c.rewardedFastPass && FXURLIsAd([a URL])) {
        NSURLRequest *dr = [NSURLRequest requestWithURL:[NSURL URLWithString:@"data:text/plain;charset=utf-8,"]];
        return %orig(dr);
    }
    return %orig;
}
- (id)uploadTaskWithRequest:(NSURLRequest *)a fromData:(NSData *)b completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))c {
    FXAdBlockConfig *cf = fxCfg();
    if (fxActive() && (cf.network || cf.miniProgram) && !cf.rewardedFastPass && FXURLIsAd([a URL])) {
        NSURLRequest *dr = [NSURLRequest requestWithURL:[NSURL URLWithString:@"data:text/plain;charset=utf-8,"]];
        return %orig(dr, b, c);
    }
    return %orig;
}
%end

// ================= 6. 直播广告 =================
%hook WCFinderAdCountdownBannerView
- (BOOL)adHasPlayOver { if (fxActive() && fxCfg().live) return YES; return %orig; }
- (id)initWithFrame:(CGRect)a countdownNum:(long long)b {
    if (fxActive() && fxCfg().miniProgram && b > 1) return %orig(a, 1);
    return %orig;
}
%end

// ================= 7. 搜索广告 =================
%hook WCAdSearchH5Info
+ (id)fromXML:(struct XmlReaderNode_t *)a { if (fxActive() && fxCfg().search) return nil; return %orig; }
- (int)adType { if (fxActive() && fxCfg().moments) return 0; return %orig; }
%end

// ================= 8. 激励广告快速跳过 =================
%hook WCFinderRewardAdViewController
- (BOOL)adHasPlayOver { if (fxActive() && fxCfg().rewardedFastPass) return YES; return %orig; }
%end

// ================= 9. 广告上报抑制 =================
%hook WCAdvertiseStatMgr
- (id)getAdvertiseInfoForItem:(id)a { if (fxActive()) return nil; return %orig; }
- (void)logHeadImageH5:(id)a { if (fxActive()) return; %orig; }
- (void)logADBrandProfile:(id)a { if (fxActive()) return; %orig; }
- (void)logADFloatView:(id)a { if (fxActive()) return; %orig; }
- (void)logADPoiH5:(id)a { if (fxActive()) return; %orig; }
- (void)logADH5:(id)a withUserInfo:(id)b reportType:(unsigned long long)c { if (fxActive()) return; %orig; }
- (void)logADH5:(id)a { if (fxActive() && fxCfg().moments) return; %orig; }
- (void)logADDetail:(id)a dataItem:(id)b { if (fxActive() && fxCfg().moments) return; %orig; }
- (void)logSphereViewWithSphereReportInfo:(id)a dataItem:(id)b scene:(id)c { if (fxActive() && fxCfg().moments) return; %orig; }
- (void)logSphereViewInDetailWithWrapInfo:(id)a dataItem:(id)b { if (fxActive() && fxCfg().moments) return; %orig; }
- (void)logSphereViewInTimeLineWithWrapInfo:(id)a dataItem:(id)b { if (fxActive() && fxCfg().moments) return; %orig; }
%end

// ================= 设置界面 =================
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

@interface FXAdBlockSettingsViewController : UIViewController
@property (nonatomic, strong) WCTableViewManager *tableViewManager;
@end

@implementation FXAdBlockSettingsViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"FX广告拦截";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    Class mc = %c(WCTableViewManager);
    _tableViewManager = [[mc alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    _tableViewManager.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _tableViewManager.tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentAutomatic;
    [self.view addSubview:_tableViewManager.tableView];
    [self buildTable];
}
- (void)buildTable {
    [_tableViewManager clearAllSection];
    Class sc = %c(WCTableViewSectionManager), cc = %c(WCTableViewCellManager);
    FXAdBlockConfig *c = fxCfg();
    WCTableViewSectionManager *sm = [sc sectionWithHeader:@"FX广告拦截 v1.0.0"];
    [sm addCell:[cc switchCellForSel:@selector(onMaster:) target:self title:@"启用广告拦截" on:c.master]];
    [_tableViewManager addSection:sm];
    if (c.master) {
        WCTableViewSectionManager *s1 = [sc sectionWithHeader:@"广告拦截场景"];
        [s1 addCell:[cc switchCellForSel:@selector(onMoments:) target:self title:@"屏蔽朋友圈广告" on:c.moments]];
        [s1 addCell:[cc switchCellForSel:@selector(onBrand:) target:self title:@"屏蔽公众号广告" on:c.brand]];
        [s1 addCell:[cc switchCellForSel:@selector(onFinder:) target:self title:@"屏蔽视频号广告" on:c.finder]];
        [s1 addCell:[cc switchCellForSel:@selector(onLive:) target:self title:@"屏蔽直播广告" on:c.live]];
        [s1 addCell:[cc switchCellForSel:@selector(onMini:) target:self title:@"屏蔽小程序广告" on:c.miniProgram]];
        [_tableViewManager addSection:s1];
        WCTableViewSectionManager *s2 = [sc sectionWithHeader:@"进阶拦截"];
        [s2 addCell:[cc switchCellForSel:@selector(onNetwork:) target:self title:@"网络层广告拦截" on:c.network]];
        [s2 addCell:[cc switchCellForSel:@selector(onSearch:) target:self title:@"屏蔽搜索广告" on:c.search]];
        [s2 addCell:[cc switchCellForSel:@selector(onRewarded:) target:self title:@"激励广告快速跳过" on:c.rewardedFastPass]];
        [s2 addCell:[cc switchCellForSel:@selector(onExpt:) target:self title:@"实验开关广告抑制" on:c.expt]];
        [_tableViewManager addSection:s2];
    }
    [_tableViewManager reloadTableView];
}
- (void)onMaster:(UISwitch *)s { fxCfg().master = s.isOn; [self buildTable]; }
- (void)onMoments:(UISwitch *)s { fxCfg().moments = s.isOn; }
- (void)onBrand:(UISwitch *)s { fxCfg().brand = s.isOn; }
- (void)onFinder:(UISwitch *)s { fxCfg().finder = s.isOn; }
- (void)onLive:(UISwitch *)s { fxCfg().live = s.isOn; }
- (void)onMini:(UISwitch *)s { fxCfg().miniProgram = s.isOn; }
- (void)onNetwork:(UISwitch *)s { fxCfg().network = s.isOn; }
- (void)onSearch:(UISwitch *)s { fxCfg().search = s.isOn; }
- (void)onRewarded:(UISwitch *)s { fxCfg().rewardedFastPass = s.isOn; }
- (void)onExpt:(UISwitch *)s { fxCfg().expt = s.isOn; }
@end

// ================= 插件注册 =================
%ctor {
    @autoreleasepool {
        Class mc = NSClassFromString(@"WCPluginsMgr");
        if (mc) {
            id mgr = [mc sharedInstance];
            if ([mgr respondsToSelector:@selector(registerControllerWithTitle:version:controller:)]) {
                [mgr registerControllerWithTitle:@"FX广告拦截" version:@"1.0.0" controller:@"FXAdBlockSettingsViewController"];
            }
        }
    }
}

