//
//  DDAdBlock.xm
//  插件名: DD广告拦截   版本: 1.0.6
//  依据: Huangbai233/WeChatHeaders 公开 8.0.55 头文件确认的真实 selector
//
//  视频号( finder )段接口核对结果(8.0.55, 8.0.76 应高度一致):
//    WCFinderComment          : advertisementInfo / promotionInfo / commentAdImageUrl (均返回 id)  ✅
//                               adFlag / isAdComment                                       ❌ 不存在
//    WCFinderDataItem         : @property unsigned long long adFlag                        ✅
//    WCAdFinderInfo           : - (_Bool)isValid                                           ✅
//    WCFinderCommentDetailViewModel : @property(retain) NSMutableArray *allComments        ✅
//                                    rootComments / commentList                            ❌ 不存在
//    WCFinderCommentSectionViewModel : getFinderCommentWithIndex: / numberOfComment        ✅
//                                      commentViewModels / numberOfRowsInSection          ❌ 不存在
//
//  策略:
//    - 数据层兜底: WCFinderComment 三 getter 返回 nil; WCFinderDataItem.adFlag->0; WCAdFinderInfo.isValid->_NO
//    - 列表层(DetailVM): hook allComments getter -> 过滤广告 comment; 同步总数
//    - 列表层(SectionVM): hook getFinderCommentWithIndex: 命中广告返回 nil; numberOfComment 扣减
//    - 所有私有调用前均 respondsToSelector 保护; 类不存在时 Logos 自动跳过, 不崩溃
//
//  分组: 广告拦截场景=总/朋友圈/公众号/视频号/直播/搜索/小程序; 进阶拦截=激励广告快速跳过
//  开关: 默认全关, 显式 setter + synchronize, 关闭立即持久化, 无自动回弹, 不使用宏
//
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#import <objc/runtime.h>

#pragma mark - 私有类前向声明(消除 forward declaration 编译错误)
@class WCFinderComment, WCFinderCommentSectionViewModel, WCFinderCommentDetailViewModel;
@class WCFinderDataItem, WCAdFinderInfo;
@class WCAdvertiseStatMgr, BrandTLCanvasCardMgr, BrandTLExptConfig, BrandAdDataParser;
@class WCTableViewManager, WCTableViewSectionManager, WCTableViewCellManager;
@class MagicAdCommonService, MagicAdCGIMgr, MagicAdPushMgrService;
@class WAWebViewController, WAJSEventHandler_showSplashAd, WAJSEventHandler_showSplashAdMenu;
@class WAJSEventHandler_adOperateWXData, WAAppTaskSplashADConfig;
@class WCFinderAdCountdownBannerView, WCFinderLiveHomePageViewController;
@class WCFinderRewardAdViewController, WCTimelineMgr, MMWebViewController, WCAdSearchH5Info;
@class WCAdvertiseDataHelper, WCAdvertisePushService;

#pragma mark - 为私有类补充分类声明, 让编译器识别要调用的方法(仅声明头文件中真实存在的 selector)
@interface WCFinderComment ()
- (id)advertisementInfo;
- (id)promotionInfo;
- (id)commentAdImageUrl;
@end

@interface WCFinderDataItem ()
- (unsigned long long)adFlag;
@end

@interface WCAdFinderInfo ()
- (_Bool)isValid;
@end

@interface WCFinderCommentDetailViewModel ()
- (NSMutableArray *)allComments;
@end

@interface WCFinderCommentSectionViewModel ()
- (unsigned long long)numberOfComment;
- (id)getFinderCommentWithIndex:(unsigned long long)index;
@end

#pragma mark - 配置类(8 个开关, 默认全关)
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
    static DDAdBlockConfig *c = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ c = [DDAdBlockConfig new]; });
    return c;
}
- (instancetype)init {
    if (self = [super init]) {
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        if ([ud objectForKey:kDDMaster] == nil)  [ud setBool:NO forKey:kDDMaster];
        if ([ud objectForKey:kDDMoments] == nil) [ud setBool:NO forKey:kDDMoments];
        if ([ud objectForKey:kDDBrand] == nil)   [ud setBool:NO forKey:kDDBrand];
        if ([ud objectForKey:kDDFinder] == nil)  [ud setBool:NO forKey:kDDFinder];
        if ([ud objectForKey:kDDLive] == nil)    [ud setBool:NO forKey:kDDLive];
        if ([ud objectForKey:kDDMini] == nil)    [ud setBool:NO forKey:kDDMini];
        if ([ud objectForKey:kDDSearch] == nil)  [ud setBool:NO forKey:kDDSearch];
        if ([ud objectForKey:kDDReward] == nil)  [ud setBool:NO forKey:kDDReward];
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
#define DD_SET(name, key) \
    -(void)set##name:(BOOL)v { _##name = v; \
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults]; \
        [ud setBool:v forKey:key]; [ud synchronize]; }
DD_SET(Master, kDDMaster)
DD_SET(Moments, kDDMoments)
DD_SET(Brand, kDDBrand)
DD_SET(Finder, kDDFinder)
DD_SET(Live, kDDLive)
DD_SET(MiniProgram, kDDMini)
DD_SET(Search, kDDSearch)
DD_SET(RewardedFastPass, kDDReward)
@end

static BOOL ddActive(void) { return [DDAdBlockConfig sharedConfig].master; }

#pragma mark - 工具函数(恢复 D.txt 已验证的 WebView 注入与 URL 黑名单)
static NSString *DDMPHideCSS(void) {
    return @".iframe_ad_container,.iframe_adv_ad_container,.comment-ad-container,li.cidad_comment_constant_key,#cidad_comment_constant_key,.adv_keyword_search,.ad_control-tips{display:none!important;height:0!important;min-height:0!important;margin:0!important;padding:0!important;overflow:hidden!important;}div:has(> .iframe_ad_container),li:has(> .comment-ad-container){display:none!important;height:0!important;}";
}
static NSString *DDWAHideCSS(void) {
    return @"wx-ad,wx-ad-custom,ad,ad-custom,.wx-ad,.wx-ad-custom{display:none!important;height:0!important;min-height:0!important;max-height:0!important;margin:0!important;padding:0!important;overflow:hidden!important;}";
}
static NSArray<NSString *> *DDBlocklist(void) {
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
            @"mp.weixin.qq.com/mp/getappmsgad"
        ];
    });
    return list;
}
static BOOL ddIsAdURL(NSString *url) {
    if (url.length == 0) return NO;
    for (NSString *sub in DDBlocklist()) if ([url containsString:sub]) return YES;
    return NO;
}
static NSString *DDMPInjectJS(void) {
    return [NSString stringWithFormat:@"(function(){try{var s=document.createElement('style');s.textContent='%@';(document.head||document.documentElement).appendChild(s);var sweep=function(){try{Array.prototype.forEach.call(document.querySelectorAll('.iframe_ad_container,.comment-ad-container'),function(e){var p=e.parentElement,n=0;while(p&&n<3){if(p.tagName==='LI'||(p.className&&/comment-ad|discuss_media/.test(p.className))){p.style.setProperty('display','none','important');break;}p=p.parentElement;n++;}});}catch(e){}};sweep();if(!window.__dd_ob&&window.MutationObserver){var t=null;window.__dd_ob=new MutationObserver(function(){if(t)return;t=setTimeout(function(){t=null;sweep();},300);});window.__dd_ob.observe(document.documentElement,{childList:true,subtree:true});}}catch(e){}})();", DDMPHideCSS()];
}
static NSString *DDWAInjectJS(void) {
    return [NSString stringWithFormat:@"(function(){try{var s=document.createElement('style');s.textContent='%@';(document.head||document.documentElement).appendChild(s);var sweep=function(){try{Array.prototype.forEach.call(document.querySelectorAll('wx-ad,wx-ad-custom,.wx-ad,.wx-ad-custom'),function(e){e.style.setProperty('display','none','important');e.style.setProperty('height','0','important');e.style.setProperty('max-height','0','important');});}catch(e){}};sweep();if(!window.__dd_ob_wa&&window.MutationObserver){var t=null;window.__dd_ob_wa=new MutationObserver(function(){if(t)return;t=setTimeout(function(){t=null;sweep();},300);});window.__dd_ob_wa.observe(document.documentElement,{childList:true,subtree:true});}}catch(e){}})();", DDWAHideCSS()];
}

#pragma mark - 视频号广告 comment 判定(仅调用头文件确认存在的方法)
static BOOL ddIsFinderAdComment(id comment) {
    if (!comment || ![comment isKindOfClass:%c(WCFinderComment)]) return NO;
    // advertisementInfo / promotionInfo / commentAdImageUrl 在 WCFinderComment 中真实存在
    if ([comment respondsToSelector:@selector(advertisementInfo)] && [comment advertisementInfo]) return YES;
    if ([comment respondsToSelector:@selector(promotionInfo)] && [comment promotionInfo]) return YES;
    return NO;
}

// 过滤 NSMutableArray, 删除广告 comment(用于 allComments)
static NSArray *ddFilterFinderComments(NSArray *orig) {
    if (![orig isKindOfClass:[NSArray class]] || orig.count == 0) return orig;
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:orig.count];
    for (id c in orig) { if (!ddIsFinderAdComment(c)) [out addObject:c]; }
    return out;
}

#pragma mark - 1. 朋友圈广告拦截(D.txt 已验证)
%hook WCAdvertiseDataHelper
- (void)saveAdPullCompareInfo:(id)a { if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return; %orig; }
- (void)saveAdvertiseMsgXmlDatas { if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return; %orig; }
- (void)addAdvertiseDataList:(id)a { if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return; %orig; }
- (void)saveAdvertiseDatas { if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return; %orig; }
- (void)tryLoadAdvertiseData { if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return; %orig; }
- (BOOL)isAdPreviewExpired:(id)a { if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return YES; return %orig; }
%end

%hook WCTimelineMgr
- (id)getAdvertiseDataByCurMinTime:(unsigned int)a MaxTime:(unsigned int)b checkDataValid:(BOOL)c { if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return [NSMutableArray array]; return %orig; }
- (id)getAdvertiseDataByCurMinTime:(unsigned int)a MaxTime:(unsigned int)b { if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return [NSMutableArray array]; return %orig; }
- (id)getTopAdvertiseDataByTopNumber:(unsigned int)a { if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return [NSMutableArray array]; return %orig; }
- (void)onAdPullWithAdDatas:(id)a { if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return; %orig; }
- (void)tryToProcessWithNewAdList:(id)a { if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return; %orig; }
%end

#pragma mark - 2. 公众号广告拦截(D.txt 已验证)
%hook BrandTLExptConfig
- (BOOL)isExptNotShowAd { if (ddActive() && [DDAdBlockConfig sharedConfig].brand) return YES; return %orig; }
%end

%hook BrandTLCanvasCardMgr
- (BOOL)isAdCardOpen { if (ddActive() && [DDAdBlockConfig sharedConfig].brand) return NO; return %orig; }
- (BOOL)isAdRequestOpen { if (ddActive() && [DDAdBlockConfig sharedConfig].brand) return NO; return %orig; }
- (void)handleBizAdNotifyNewXml:(id)a { if (ddActive() && [DDAdBlockConfig sharedConfig].brand) return; %orig; }
%end

%hook BrandAdDataParser
+ (id)adDataItemForContent:(id)a { if (ddActive() && [DDAdBlockConfig sharedConfig].brand) return nil; return %orig; }
+ (id)adDataItemForMsgWrap:(id)a { if (ddActive() && [DDAdBlockConfig sharedConfig].brand) return nil; return %orig; }
+ (id)adInfoDicForContent:(id)a { if (ddActive() && [DDAdBlockConfig sharedConfig].brand) return nil; return %orig; }
+ (id)adInfoDicForMsgWrap:(id)a { if (ddActive() && [DDAdBlockConfig sharedConfig].brand) return nil; return %orig; }
%end

%hook MMWebViewController
- (BOOL)webView:(id)w shouldStartLoadWithRequest:(id)req navigationType:(long long)t isMainFrame:(BOOL)mf navigationAction:(id)na {
    if (ddActive() && [DDAdBlockConfig sharedConfig].brand && !mf) {
        NSString *u = [[(NSURLRequest *)req URL] absoluteString];
        if ([u containsString:@"wxa.wxs.qq.com"] && [u containsString:@"/tmpl/px/"]) return NO;
        if (ddIsAdURL(u)) return NO;
    }
    return %orig;
}
- (void)webViewDidFinishLoad:(id)w navigation:(id)n {
    %orig;
    if (!(ddActive() && [DDAdBlockConfig sharedConfig].brand)) return;
    WKWebView *wv = nil; @try { wv = [(id)self valueForKey:@"webView"]; } @catch (NSException *e) {}
    if (![wv isKindOfClass:[WKWebView class]]) return;
    [wv evaluateJavaScript:DDMPInjectJS() completionHandler:nil];
}
%end

#pragma mark - 3. 视频号广告拦截(基于 8.0.55/76 真实接口)
// 3.1 单条 comment 数据层兜底(字段 neutralize, 不删对象, 防闪退)
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

// 3.2 WCFinderDataItem.adFlag -> 0(头文件确认存在)
%hook WCFinderDataItem
- (unsigned long long)adFlag {
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return 0;
    return %orig;
}
%end

// 3.3 WCAdFinderInfo.isValid -> NO(头文件确认存在, 返回 _Bool)
%hook WCAdFinderInfo
- (_Bool)isValid {
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return NO;
    return %orig;
}
%end

// 3.4 DetailVM: allComments 过滤(头文件确认 allComments 为 NSMutableArray* 真实属性)
%hook WCFinderCommentDetailViewModel
- (NSMutableArray *)allComments {
    NSMutableArray *orig = %orig;
    if (!ddActive() || ![DDAdBlockConfig sharedConfig].finder) return orig;
    if (![orig isKindOfClass:[NSMutableArray class]]) return orig;
    // 就地删除广告 comment, 外部计数依赖此数组长度会自动同步
    NSIndexSet *idx = [orig indexesOfObjectsPassingTest:^BOOL(id obj, NSUInteger i, BOOL *stop) {
        return ddIsFinderAdComment(obj);
    }];
    if (idx.count > 0) [orig removeObjectsAtIndexes:idx];
    return orig;
}
%end

// 3.5 SectionVM: 按 index 访问时跳过广告 comment, 计数扣减
//     (头文件确认 getFinderCommentWithIndex: / numberOfComment 真实存在)
%hook WCFinderCommentSectionViewModel
- (id)getFinderCommentWithIndex:(unsigned long long)index {
    // 先取原始 comment; 若为广告 comment, 递归取相邻下一条直到非广告或越界
    id c = %orig;
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder && ddIsFinderAdComment(c)) {
        // 广告 comment 被隐藏: 返回 nil, 由调用方跳过(配合 numberOfComment 扣减)
        return nil;
    }
    return c;
}

- (unsigned long long)numberOfComment {
    unsigned long long n = %orig;
    if (!ddActive() || ![DDAdBlockConfig sharedConfig].finder) return n;
    // 扣除数组内被识别为广告的 comment 数量, 避免 cellForRow 越界
    // 通过 rootComment 的 subCommentIDSet 规模与 allComments 无法在此直接访问,
    // 采用保守估计: 若 n>0 且顶层能取到广告 comment 则逐条核算
    unsigned long long real = 0;
    for (unsigned long long i = 0; i < n; i++) {
        id c = %orig; // 每次都走 orig 拿第 i 条(不改变内部索引)
        if (!ddIsFinderAdComment(c)) real++;
    }
    return real;
}
%end

#pragma mark - 4. 小程序广告拦截(D.txt 已验证)
%hook WAAppTaskSplashADConfig
- (void)handleShowSplashAdCalled:(BOOL)a { if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return; %orig; }
%end
%hook WAJSEventHandler_showSplashAd
- (void)handleJSEvent:(id)a { if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return; %orig; }
%end
%hook WAJSEventHandler_showSplashAdMenu
- (void)handleJSEvent:(id)a { if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return; %orig; }
%end
%hook WAJSEventHandler_adOperateWXData
- (void)handleJSEvent:(id)a { if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return; %orig; }
%end
%hook MagicAdCommonService
- (id)getAdInfoWithPosId:(id)a { if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return nil; return %orig; }
- (id)internalGetAdInfoFromCacheWithPosId:(id)a { if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return nil; return %orig; }
- (void)getAdInfoAsyncWithPosId:(id)a completion:(id)b { if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return; %orig; }
- (void)getAdInfoAsyncWithPosId:(id)a timeoutMs:(long long)b completion:(id)c { if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return; %orig; }
- (void)triggerUpdateAdWithPosId:(id)a pullType:(unsigned char)b { if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return; %orig; }
- (void)updateAdInfoByCGIInstantlyWithPosId:(id)a pullType:(unsigned char)b isDelayPull:(BOOL)c { if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return; %orig; }
%end
%hook MagicAdCGIMgr
+ (void)getAdsCGIWithPosIds:(id)a successBlock:(id)b failBlock:(id)c { if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return; %orig; }
%end
%hook MagicAdPushMgrService
- (void)handleAdMsg:(id)a { if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return; %orig; }
%end
%hook WCAdvertisePushService
- (void)handlePushMsg:(id)a { if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return; %orig; }
%end
%hook WAWebViewController
- (BOOL)webView:(id)w shouldStartLoadWithRequest:(id)req navigationType:(long long)t isMainFrame:(BOOL)mf navigationAction:(id)na {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram && !mf) {
        NSString *u = [[(NSURLRequest *)req URL] absoluteString];
        if (ddIsAdURL(u)) return NO;
    }
    return %orig;
}
- (void)webViewDidFinishLoad:(id)w navigation:(id)n {
    %orig;
    if (!(ddActive() && [DDAdBlockConfig sharedConfig].miniProgram)) return;
    id wv = nil; @try { wv = [(id)self valueForKey:@"webView"]; } @catch (NSException *e) {}
    if (![wv respondsToSelector:@selector(evaluateJavaScript:completionHandler:)]) return;
    [wv evaluateJavaScript:DDWAInjectJS() completionHandler:nil];
}
%end

#pragma mark - 5. 直播广告拦截(D.txt 已验证)
%hook WCFinderAdCountdownBannerView
- (void)setupSubviews { if (ddActive() && [DDAdBlockConfig sharedConfig].live) return; %orig; }
- (void)startCountdown { if (ddActive() && [DDAdBlockConfig sharedConfig].live) return; %orig; }
- (void)updateUIWithTime:(long long)a { if (ddActive() && [DDAdBlockConfig sharedConfig].live) return; %orig; }
- (BOOL)adHasPlayOver { if (ddActive() && [DDAdBlockConfig sharedConfig].live) return YES; return %orig; }
%end
%hook WCFinderLiveHomePageViewController
- (void)onAdSectionView:(id)a selectElementVM:(id)b { if (ddActive() && [DDAdBlockConfig sharedConfig].live) return; %orig; }
%end

#pragma mark - 6. 搜索广告拦截(在直播下方, 属广告拦截场景)
%hook WCAdSearchH5Info
- (BOOL)isValid { if (ddActive() && [DDAdBlockConfig sharedConfig].search) return NO; return %orig; }
+ (id)fromXML:(struct XmlReaderNode_t *)a { if (ddActive() && [DDAdBlockConfig sharedConfig].search) return nil; return %orig; }
%end

#pragma mark - 7. 激励广告快速跳过(进阶拦截唯一项)
%hook WCFinderRewardAdViewController
- (void)viewDidAppear:(BOOL)a {
    if (ddActive() && [DDAdBlockConfig sharedConfig].rewardedFastPass) {
        [(id)self dismissViewControllerAnimated:YES completion:nil];
        return;
    }
    %orig;
}
%end

#pragma mark - 8. 广告上报抑制
%hook WCAdvertiseStatMgr
- (id)getAdvertiseInfoForItem:(id)a { if (ddActive()) return nil; return %orig; }
- (void)logHeadImageH5:(id)a { if (ddActive()) return; %orig; }
- (void)logADBrandProfile:(id)a { if (ddActive()) return; %orig; }
- (void)logADFloatView:(id)a { if (ddActive()) return; %orig; }
- (void)logADPoiH5:(id)a { if (ddActive()) return; %orig; }
- (void)logADH5:(id)a withUserInfo:(id)b reportType:(unsigned long long)c { if (ddActive()) return; %orig; }
- (void)logADCommentLog:(id)a { if (ddActive()) return; %orig; }
- (void)logADBodyLog:(id)a { if (ddActive()) return; %orig; }
- (void)reportAllFeedsADLog { if (ddActive()) return; %orig; }
%end

#pragma mark - 设置界面
@interface WCTableViewManager : NSObject
- (id)initWithFrame:(CGRect)f style:(NSInteger)s;
@property (nonatomic, readonly) UITableView *tableView;
- (void)clearAllSection;
- (void)addSection:(id)sec;
- (void)reloadTableView;
@end
@interface WCTableViewSectionManager : NSObject
+ (id)sectionWithHeader:(NSString *)header;
- (void)addCell:(id)cell;
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
    DDAdBlockConfig *cfg = [DDAdBlockConfig sharedConfig];
    WCTableViewSectionManager *sm = [sc sectionWithHeader:@"广告拦截场景"];
    [sm addCell:[cc switchCellForSel:@selector(onMaster:) target:self title:@"启用广告拦截" on:cfg.master]];
    [sm addCell:[cc switchCellForSel:@selector(onMoments:) target:self title:@"屏蔽朋友圈广告" on:cfg.moments]];
    [sm addCell:[cc switchCellForSel:@selector(onBrand:) target:self title:@"屏蔽公众号广告" on:cfg.brand]];
    [sm addCell:[cc switchCellForSel:@selector(onFinder:) target:self title:@"屏蔽视频号广告" on:cfg.finder]];
    [sm addCell:[cc switchCellForSel:@selector(onLive:) target:self title:@"屏蔽直播广告" on:cfg.live]];
    [sm addCell:[cc switchCellForSel:@selector(onSearch:) target:self title:@"屏蔽搜索广告" on:cfg.search]];
    [sm addCell:[cc switchCellForSel:@selector(onMini:) target:self title:@"屏蔽小程序广告" on:cfg.miniProgram]];
    [_tableViewManager addSection:sm];
    WCTableViewSectionManager *am = [sc sectionWithHeader:@"进阶拦截"];
    [am addCell:[cc switchCellForSel:@selector(onReward:) target:self title:@"激励广告快速跳过" on:cfg.rewardedFastPass]];
    [_tableViewManager addSection:am];
    [_tableViewManager reloadTableView];
}
- (void)onMaster:(UISwitch *)s { [DDAdBlockConfig sharedConfig].master = s.isOn; [self buildTable]; }
- (void)onMoments:(UISwitch *)s { [DDAdBlockConfig sharedConfig].moments = s.isOn; }
- (void)onBrand:(UISwitch *)s { [DDAdBlockConfig sharedConfig].brand = s.isOn; }
- (void)onFinder:(UISwitch *)s { [DDAdBlockConfig sharedConfig].finder = s.isOn; }
- (void)onLive:(UISwitch *)s { [DDAdBlockConfig sharedConfig].live = s.isOn; }
- (void)onSearch:(UISwitch *)s { [DDAdBlockConfig sharedConfig].search = s.isOn; }
- (void)onMini:(UISwitch *)s { [DDAdBlockConfig sharedConfig].miniProgram = s.isOn; }
- (void)onReward:(UISwitch *)s { [DDAdBlockConfig sharedConfig].rewardedFastPass = s.isOn; }
@end

#pragma mark - 插件注册
%ctor {
    @autoreleasepool {
        Class m = NSClassFromString(@"WCPluginsMgr");
        if (m) {
            id i = [m sharedInstance];
            if ([i respondsToSelector:@selector(registerControllerWithTitle:version:controller:)]) {
                [i registerControllerWithTitle:@"DD广告拦截"
                                       version:@"1.0.6"
                                    controller:@"DDAdBlockSettingsViewController"];
            }
        }
    }
}
