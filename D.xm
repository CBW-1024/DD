//
//  DDAdBlock.xm
//  插件名: DD广告拦截   版本: 1.0.3
//  说明: 参考 D.txt 重建为独立单文件 tweak。D.txt 经实机验证"公众号广告拦截完美、小程序
//        中间无广告"，其有效性来源于三层：① 原生广告数据/解析层（WCAdvertiseDataHelper、
//        BrandTL*、BrandAdDataParser、WCFinderComment/WCAdFinderInfo 等）；② WebView
//        URL 黑名单 + document-start 注入 JS + DOM sweep（公众号 MMWebViewController、
//        小程序 WAWebViewController）；③ 广告上报/推送抑制。本版完整保留这三层，不删除
//        D.txt 任何已验证有效的 Hook；视频号评论区严格沿用 D.txt 写法（仅 neutralize
//        广告字段，不 return nil、不新增未验证类名），避免引入猜测类导致广告回退。
//  分组: 广告拦截场景 = 朋友圈/公众号/视频号/直播/搜索(直播下)/小程序
//        进阶拦截 = 激励广告快速跳过（仅此项；无青少年弹窗、无网络层开关、无实验开关）
//  开关: 9 个，默认全关；显式 setter + synchronize，关闭立即持久化、不自动回弹；不使用宏。
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

// ========== 配置类（9 个开关，默认全关） ==========
static NSString * const kDDAdBlockMasterKey           = @"DDAdBlock_Master";
static NSString * const kDDAdBlockMomentsKey          = @"DDAdBlock_Moments";
static NSString * const kDDAdBlockBrandKey            = @"DDAdBlock_Brand";
static NSString * const kDDAdBlockFinderKey           = @"DDAdBlock_Finder";
static NSString * const kDDAdBlockLiveKey             = @"DDAdBlock_Live";
static NSString * const kDDAdBlockMiniProgramKey      = @"DDAdBlock_MiniProgram";
static NSString * const kDDAdBlockSearchKey           = @"DDAdBlock_Search";
static NSString * const kDDAdBlockRewardedFastPassKey = @"DDAdBlock_RewardedAdFastPass";

@interface DDAdBlockConfig : NSObject
+ (instancetype)sharedConfig;
@property (assign, nonatomic) BOOL master;            // 总开关
@property (assign, nonatomic) BOOL moments;           // 朋友圈广告
@property (assign, nonatomic) BOOL brand;             // 公众号广告
@property (assign, nonatomic) BOOL finder;            // 视频号广告
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
        // 首次安装写入默认值（全关），随后 synchronize 再读取，杜绝竞态
        if ([ud objectForKey:kDDAdBlockMasterKey] == nil)           [ud setBool:NO forKey:kDDAdBlockMasterKey];
        if ([ud objectForKey:kDDAdBlockMomentsKey] == nil)          [ud setBool:NO forKey:kDDAdBlockMomentsKey];
        if ([ud objectForKey:kDDAdBlockBrandKey] == nil)            [ud setBool:NO forKey:kDDAdBlockBrandKey];
        if ([ud objectForKey:kDDAdBlockFinderKey] == nil)           [ud setBool:NO forKey:kDDAdBlockFinderKey];
        if ([ud objectForKey:kDDAdBlockLiveKey] == nil)             [ud setBool:NO forKey:kDDAdBlockLiveKey];
        if ([ud objectForKey:kDDAdBlockMiniProgramKey] == nil)      [ud setBool:NO forKey:kDDAdBlockMiniProgramKey];
        if ([ud objectForKey:kDDAdBlockSearchKey] == nil)           [ud setBool:NO forKey:kDDAdBlockSearchKey];
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
// 显式 setter + synchronize：关闭立即落盘，不自动回弹；ivar 与自动合成名一致（全小写）
- (void)setMaster:(BOOL)value { _master = value; NSUserDefaults *ud = [NSUserDefaults standardUserDefaults]; [ud setBool:value forKey:kDDAdBlockMasterKey]; [ud synchronize]; }
- (void)setMoments:(BOOL)value { _moments = value; NSUserDefaults *ud = [NSUserDefaults standardUserDefaults]; [ud setBool:value forKey:kDDAdBlockMomentsKey]; [ud synchronize]; }
- (void)setBrand:(BOOL)value { _brand = value; NSUserDefaults *ud = [NSUserDefaults standardUserDefaults]; [ud setBool:value forKey:kDDAdBlockBrandKey]; [ud synchronize]; }
- (void)setFinder:(BOOL)value { _finder = value; NSUserDefaults *ud = [NSUserDefaults standardUserDefaults]; [ud setBool:value forKey:kDDAdBlockFinderKey]; [ud synchronize]; }
- (void)setLive:(BOOL)value { _live = value; NSUserDefaults *ud = [NSUserDefaults standardUserDefaults]; [ud setBool:value forKey:kDDAdBlockLiveKey]; [ud synchronize]; }
- (void)setMiniProgram:(BOOL)value { _miniProgram = value; NSUserDefaults *ud = [NSUserDefaults standardUserDefaults]; [ud setBool:value forKey:kDDAdBlockMiniProgramKey]; [ud synchronize]; }
- (void)setSearch:(BOOL)value { _search = value; NSUserDefaults *ud = [NSUserDefaults standardUserDefaults]; [ud setBool:value forKey:kDDAdBlockSearchKey]; [ud synchronize]; }
- (void)setRewardedFastPass:(BOOL)value { _rewardedFastPass = value; NSUserDefaults *ud = [NSUserDefaults standardUserDefaults]; [ud setBool:value forKey:kDDAdBlockRewardedFastPassKey]; [ud synchronize]; }
@end

// 总开关守卫
static BOOL ddActive(void) { return [DDAdBlockConfig sharedConfig].master; }

// ============================================================================
// 所有 Hook 均经「总开关 + 分区开关」双重门控；类不存在时 Logos 自动跳过
// ============================================================================

// ---------- 1. 朋友圈广告拦截 ----------
%hook WCAdvertiseDataHelper
- (void)saveAdPullCompareInfo:(id)arg1 { if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return; %orig; }
- (void)saveAdvertiseMsgXmlDatas { if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return; %orig; }
- (void)addAdvertiseDataList:(id)arg1 { if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return; %orig; }
- (void)saveAdvertiseDatas { if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return; %orig; }
- (void)tryLoadAdvertiseData { if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return; %orig; }
- (BOOL)isAdPreviewExpired:(id)arg1 { if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return YES; return %orig; }
%end

%hook WCTimelineMgr
- (id)getAdvertiseDataByCurMinTime:(unsigned int)arg1 MaxTime:(unsigned int)arg2 checkDataValid:(BOOL)arg3 { if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return [NSMutableArray array]; return %orig; }
- (id)getAdvertiseDataByCurMinTime:(unsigned int)arg1 MaxTime:(unsigned int)arg2 { if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return [NSMutableArray array]; return %orig; }
- (id)getTopAdvertiseDataByTopNumber:(unsigned int)arg1 { if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return [NSMutableArray array]; return %orig; }
- (void)onAdPullWithAdDatas:(id)arg1 { if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return; %orig; }
- (void)tryToProcessWithNewAdList:(id)arg1 { if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return; %orig; }
%end

// ---------- 2. 公众号广告拦截 ----------
%hook BrandTLExptConfig
- (BOOL)isExptNotShowAd { if (ddActive() && [DDAdBlockConfig sharedConfig].brand) return YES; return %orig; }
%end

%hook BrandTLCanvasCardMgr
- (BOOL)isAdCardOpen { if (ddActive() && [DDAdBlockConfig sharedConfig].brand) return NO; return %orig; }
- (BOOL)isAdRequestOpen { if (ddActive() && [DDAdBlockConfig sharedConfig].brand) return NO; return %orig; }
- (void)handleBizAdNotifyNewXml:(id)arg1 { if (ddActive() && [DDAdBlockConfig sharedConfig].brand) return; %orig; }
%end

%hook BrandAdDataParser
+ (id)adDataItemForContent:(id)arg1 { if (ddActive() && [DDAdBlockConfig sharedConfig].brand) return nil; return %orig; }
+ (id)adDataItemForMsgWrap:(id)arg1 { if (ddActive() && [DDAdBlockConfig sharedConfig].brand) return nil; return %orig; }
+ (id)adInfoDicForContent:(id)arg1 { if (ddActive() && [DDAdBlockConfig sharedConfig].brand) return nil; return %orig; }
+ (id)adInfoDicForMsgWrap:(id)arg1 { if (ddActive() && [DDAdBlockConfig sharedConfig].brand) return nil; return %orig; }
%end

// 公众号/小程序 WebView 广告：URL 黑名单 + document-start 注入 JS + DOM sweep
// 2.a CSS 隐藏规则（选择器来自实机 DOM 探针）
static NSString *DDAdBlockMPHideCSS(void) {
    return @".iframe_ad_container,.iframe_adv_ad_container,.comment-ad-container,li.cidad_comment_constant_key,#cidad_comment_constant_key,.adv_keyword_search,.ad_control-tips{display:none!important;height:0!important;min-height:0!important;margin:0!important;padding:0!important;overflow:hidden!important;}";
}
static NSString *DDAdBlockMPHideParentCSS(void) {
    return @"div:has(> .iframe_ad_container),li:has(> .comment-ad-container){display:none!important;height:0!important;}";
}
static NSString *DDAdBlockInjectJS(void) {
    return [NSString stringWithFormat:@"(function(){try{if(!document.getElementById('__dd_adblock')){var s=document.createElement('style');s.id='__dd_adblock';s.textContent='%@'+'%@';(document.head||document.documentElement).appendChild(s);}var sweep=function(){try{Array.prototype.forEach.call(document.querySelectorAll('.iframe_ad_container,.comment-ad-container'),function(e){var p=e.parentElement,n=0;while(p&&n<3){if(p.tagName==='LI'||(p.className&&/comment-ad|discuss_media/.test(p.className))){p.style.setProperty('display','none','important');break;}p=p.parentElement;n++;}});}catch(e){}};sweep();if(!window.__dd_ob&&window.MutationObserver){var t=null;window.__dd_ob=new MutationObserver(function(){if(t)return;t=setTimeout(function(){t=null;sweep();},300);});window.__dd_ob.observe(document.documentElement,{childList:true,subtree:true});}}catch(e){}})();", DDAdBlockMPHideCSS(), DDAdBlockMPHideParentCSS()];
}

// 2.b URL 黑名单（覆盖公众号文章内广告 iframe / 素材 / 小程序广告素材 / 联盟广告）
static NSArray<NSString *> *DDAdBlockURLBlocklist(void) {
    static NSArray *list;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        list = @[
            @"wxa.wxs.qq.com/tmpl/px/",   // 公众号/文章内广告 iframe
            @"wxa.wxs.qq.com/tmpl/lite/",
            @"support.weixin.qq.com/cgi-bin/mmsupport-bin/",
            @"wxapp.tc.qq.com/ad/",        // 小程序广告素材
            @"cpro.baidu.com",             // 搜索/信息流联盟广告
            @"pos.baidu.com",
            @"go.mobile.qq.com/ad",
            @"/cgi-bin/mmbiz-bin/ad",
            @"ad.weixin.qq.com",
            @"wxad",
            @"adunit-",                    // 小程序 adUnitId
            @"_ad_",
            @"&adpos=",
        ];
    });
    return list;
}
static BOOL ddURLIsAd(NSString *url) {
    if (url.length == 0) return NO;
    for (NSString *sub in DDAdBlockURLBlocklist()) { if ([url containsString:sub]) return YES; }
    return NO;
}

%hook MMWebViewController
- (id)webViewUserScriptsForConfiguration {
    id scripts = %orig;
    DDAdBlockConfig *cfg = [DDAdBlockConfig sharedConfig];
    if (!(ddActive() && cfg.brand)) return scripts;
    NSMutableArray *arr = [scripts isKindOfClass:[NSArray class]] ? [(NSArray *)scripts mutableCopy] : [NSMutableArray array];
    WKUserScript *us = [[WKUserScript alloc] initWithSource:DDAdBlockInjectJS() injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO];
    [arr addObject:us];
    return arr;
}
- (BOOL)webView:(id)arg1 shouldStartLoadWithRequest:(id)arg2 navigationType:(long long)arg3 isMainFrame:(BOOL)arg4 navigationAction:(id)arg5 {
    DDAdBlockConfig *cfg = [DDAdBlockConfig sharedConfig];
    if (ddActive() && cfg.brand && !arg4) {
        NSString *u = [[(NSURLRequest *)arg2 URL] absoluteString];
        if ([u containsString:@"wxa.wxs.qq.com"] && [u containsString:@"/tmpl/px/"]) return NO;
        if (ddURLIsAd(u)) return NO;
    }
    return %orig;
}
- (void)webViewDidFinishLoad:(id)arg1 navigation:(id)arg2 {
    %orig;
    DDAdBlockConfig *cfg = [DDAdBlockConfig sharedConfig];
    if (!(ddActive() && cfg.brand)) return;
    WKWebView *wv = nil;
    @try { wv = [(id)self valueForKey:@"webView"]; } @catch (__unused NSException *e) {}
    if (![wv isKindOfClass:[WKWebView class]]) return;
    [wv evaluateJavaScript:DDAdBlockInjectJS() completionHandler:nil];
}
%end

// ---------- 3. 视频号广告拦截（严格沿用 D.txt 写法：仅 neutralize 广告字段，不 return nil） ----------
%hook WCFinderComment
- (id)advertisementInfo { if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return nil; return %orig; }
- (id)commentAdImageUrl { if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return nil; return %orig; }
- (id)promotionInfo { if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return nil; return %orig; }
%end

%hook WCFinderDataItem
- (unsigned long long)adFlag { if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return 0; return %orig; }
%end

%hook WCAdFinderInfo
- (BOOL)isValid { if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return NO; return %orig; }
%end

// ---------- 4. 小程序广告拦截（沿用 D.txt：开屏/JS桥/posId/CGI/推送 + WebView URL 黑名单/DOM sweep） ----------
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

// 小程序 <ad>/<ad-custom> DOM 隐藏 + WebView URL 拦截（D.txt 有效层，完整保留）
static NSString *DDAdBlockMiniAppHideCSS(void) {
    return @"wx-ad,wx-ad-custom,ad,ad-custom,.wx-ad,.wx-ad-custom{display:none!important;height:0!important;min-height:0!important;max-height:0!important;margin:0!important;padding:0!important;overflow:hidden!important;}";
}
static NSString *DDAdBlockMiniAppInjectJS(void) {
    return [NSString stringWithFormat:@"(function(){try{if(!document.getElementById('__dd_adblock_wa')){var s=document.createElement('style');s.id='__dd_adblock_wa';s.textContent='%@';(document.head||document.documentElement).appendChild(s);}var sweep=function(){try{Array.prototype.forEach.call(document.querySelectorAll('wx-ad,wx-ad-custom,.wx-ad,.wx-ad-custom'),function(e){e.style.setProperty('display','none','important');e.style.setProperty('height','0','important');e.style.setProperty('max-height','0','important');});}catch(e){}};sweep();if(!window.__dd_ob_wa&&window.MutationObserver){var t=null;window.__dd_ob_wa=new MutationObserver(function(){if(t)return;t=setTimeout(function(){t=null;sweep();},300);});window.__dd_ob_wa.observe(document.documentElement,{childList:true,subtree:true});}}catch(e){}})();", DDAdBlockMiniAppHideCSS()];
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

// ---------- 5. 直播广告拦截 ----------
%hook WCFinderAdCountdownBannerView
- (void)setupSubviews { if (ddActive() && [DDAdBlockConfig sharedConfig].live) return; %orig; }
- (void)startCountdown { if (ddActive() && [DDAdBlockConfig sharedConfig].live) return; %orig; }
- (void)updateUIWithTime:(long long)arg1 { if (ddActive() && [DDAdBlockConfig sharedConfig].live) return; %orig; }
- (BOOL)adHasPlayOver { if (ddActive() && [DDAdBlockConfig sharedConfig].live) return YES; return %orig; }
%end
%hook WCFinderLiveHomePageViewController
- (void)onAdSectionView:(id)arg1 selectElementVM:(id)arg2 { if (ddActive() && [DDAdBlockConfig sharedConfig].live) return; %orig; }
%end

// ---------- 6. 搜索广告拦截（在广告拦截场景-直播下方） ----------
%hook WCAdSearchH5Info
- (BOOL)isValid { if (ddActive() && [DDAdBlockConfig sharedConfig].search) return NO; return %orig; }
+ (id)fromXML:(struct XmlReaderNode_t *)arg1 { if (ddActive() && [DDAdBlockConfig sharedConfig].search) return nil; return %orig; }
%end

// ---------- 7. 激励广告快速跳过（进阶拦截唯一项） ----------
%hook WCFinderRewardAdViewController
- (void)viewDidAppear:(BOOL)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].rewardedFastPass) {
        [(id)self dismissViewControllerAnimated:YES completion:nil];
        return;
    }
    %orig;
}
%end

// ---------- 8. 广告曝光上报抑制 ----------
%hook WCAdvertiseStatMgr
- (id)getAdvertiseInfoForItem:(id)arg1 { if (ddActive()) return nil; return %orig; }
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

    // 广告拦截场景：总开关 + 各场景；搜索放在直播下方
    WCTableViewSectionManager *secMain = [sectionCls sectionWithHeader:@"广告拦截场景"];
    [secMain addCell:[cellCls switchCellForSel:@selector(onMasterSwitch:) target:self title:@"启用广告拦截" on:cfg.master]];
    [secMain addCell:[cellCls switchCellForSel:@selector(onMomentsSwitch:) target:self title:@"屏蔽朋友圈广告" on:cfg.moments]];
    [secMain addCell:[cellCls switchCellForSel:@selector(onBrandSwitch:) target:self title:@"屏蔽公众号广告" on:cfg.brand]];
    [secMain addCell:[cellCls switchCellForSel:@selector(onFinderSwitch:) target:self title:@"屏蔽视频号广告" on:cfg.finder]];
    [secMain addCell:[cellCls switchCellForSel:@selector(onLiveSwitch:) target:self title:@"屏蔽直播广告" on:cfg.live]];
    [secMain addCell:[cellCls switchCellForSel:@selector(onSearchSwitch:) target:self title:@"屏蔽搜索广告" on:cfg.search]];
    [secMain addCell:[cellCls switchCellForSel:@selector(onMiniProgramSwitch:) target:self title:@"屏蔽小程序广告" on:cfg.miniProgram]];
    [_tableViewManager addSection:secMain];

    // 进阶拦截：仅激励广告快速跳过
    WCTableViewSectionManager *secAdv = [sectionCls sectionWithHeader:@"进阶拦截"];
    [secAdv addCell:[cellCls switchCellForSel:@selector(onRewardedSwitch:) target:self title:@"激励广告快速跳过" on:cfg.rewardedFastPass]];
    [_tableViewManager addSection:secAdv];

    [_tableViewManager reloadTableView];
}
- (void)onMasterSwitch:(UISwitch *)s        { [DDAdBlockConfig sharedConfig].master = s.isOn; [self buildTable]; }
- (void)onMomentsSwitch:(UISwitch *)s       { [DDAdBlockConfig sharedConfig].moments = s.isOn; }
- (void)onBrandSwitch:(UISwitch *)s         { [DDAdBlockConfig sharedConfig].brand = s.isOn; }
- (void)onFinderSwitch:(UISwitch *)s        { [DDAdBlockConfig sharedConfig].finder = s.isOn; }
- (void)onLiveSwitch:(UISwitch *)s          { [DDAdBlockConfig sharedConfig].live = s.isOn; }
- (void)onSearchSwitch:(UISwitch *)s        { [DDAdBlockConfig sharedConfig].search = s.isOn; }
- (void)onMiniProgramSwitch:(UISwitch *)s   { [DDAdBlockConfig sharedConfig].miniProgram = s.isOn; }
- (void)onRewardedSwitch:(UISwitch *)s      { [DDAdBlockConfig sharedConfig].rewardedFastPass = s.isOn; }
@end

// ========== 插件注册 ==========
%ctor {
    @autoreleasepool {
        Class mgrClass = NSClassFromString(@"WCPluginsMgr");
        if (mgrClass) {
            id mgr = [mgrClass sharedInstance];
            if ([mgr respondsToSelector:@selector(registerControllerWithTitle:version:controller:)]) {
                [mgr registerControllerWithTitle:@"DD广告拦截" version:@"1.0.3" controller:@"DDAdBlockSettingsViewController"];
            }
        }
    }
}
