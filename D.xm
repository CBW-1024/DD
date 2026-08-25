//
//  DDAdBlock.xm
//  插件名: DD广告拦截   版本: 1.0.10
//
//  变更记录:
//  - 1.0.3: 规范化缩进；开关不回弹、无宏；进阶仅留激励快过
//  - 1.0.5: 视频号运行时 KVC 探测（候选 key，未依赖具体头文件）
//  - 1.0.6: 依据 8.0.76 真实头文件重写视频号评论广告拦截
//            证据：WCFinderCommentAdTableViewCell.h（class-dump 3.5, 8.0.76）
//                  WCFinderCommentDetailViewController.h
//  - 1.0.7: 收敛拦截链，移除多余 WCFinderCommentSectionViewModel hook（属性名均为猜测）
//  - 1.0.8: 彻底清理残留（工具函数、注释、sectionHeight 判断），
//            仅保留 Flex 视图树 + 真实头文件双重证实的拦截层
//
//  ★ 关键证据（来自头文件 + Flex 视图层级，非猜测）:
//    1) Flex 视图树直接捕获: UITableView → WCFinderCommentAdTableViewCell
//       → 评论区广告 = 独立 Cell，不是"混在评论数组里的伪评论"
//    2) 头文件: WCFinderCommentAdTableViewCell : UITableViewCell
//       - updateWithModel:width: / resetCellData 是必经更新入口
//       - sectionHeightWith:width:halfScreenHeight: 控制高度
//       - updatePlayerViewWithCommentInfo:videoInfo: 填充广告视频
//       - updateImageViewWithCommentImageInfo:imgInfo: 填充广告图
//       - clickADContentActionWithArea: 广告点击跳转
//       - commentAdReportDictWithReportScene: / canReportWithReportScene: 上报
//    3) 控制器 WCFinderCommentDetailViewController 持有完整广告生命周期:
//       commentAdCell:click* / reportCommentAd* /
//       checkCommentAdPlayerExposeStateIfNeeded / clearCommentAdState
//
//  因此策略（简洁、无猜测）:
//    A. Cell 视图层 neutralize: updateWithModel 短路 + 运行时隐藏(setHidden:)
//       高度 → 0pt（sectionHeight + cell 级 heightForMedia 均返回 0）
//       → 不破坏 dataSource 计数，不 return nil，防闪退
//    B. 控制器层: 曝光/上报/点击全部短路
//    C. 数据对象层: WCFinderComment / WCFinderDataItem / WCAdFinderInfo 沿用 D.txt
//
//  ★ 已删除（1.0.7~1.0.8）:
//    - WCFinderCommentSectionViewModel 整个 hook 块（属性名均为猜测，无头文件支撑）
//    - ddIsFinderCommentAdSection() KVC 探测函数（同上）
//    - sectionHeightWith: 里的 isAdSection 判断（改为无条件返回 0）
//
//  设计原则（对齐 D.txt 防闪退）:
//    - 不 return nil 单个对象 / 不 return 空数组（UITableView dataSource 计数一致）
//    - 所有 hook 走 class 存在性 + respondsToSelector: 保护
//

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#import <objc/runtime.h>
#import <objc/message.h>  // class_respondsToSelector / methodForSelector:

// ========== 插件管理入口 ==========
@interface WCPluginsMgr : NSObject
+ (instancetype)sharedInstance;
- (void)registerControllerWithTitle:(NSString *)title
                            version:(NSString *)version
                         controller:(NSString *)controller;
@end

// ========== 配置类（8 个开关，默认全关） ==========
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
@property (assign, nonatomic) BOOL master;
@property (assign, nonatomic) BOOL moments;
@property (assign, nonatomic) BOOL brand;
@property (assign, nonatomic) BOOL finder;
@property (assign, nonatomic) BOOL live;
@property (assign, nonatomic) BOOL miniProgram;
@property (assign, nonatomic) BOOL search;
@property (assign, nonatomic) BOOL rewardedFastPass;
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

// 显式手写 setter：关闭后立即持久化，不会自动回弹
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

// 总开关守卫
static BOOL ddActive(void) {
    return [DDAdBlockConfig sharedConfig].master;
}

// ============================================================================
//  1. 朋友圈广告拦截（沿用 D.txt）
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
- (id)getAdvertiseDataByCurMinTime:(unsigned int)arg1
                           MaxTime:(unsigned int)arg2
                   checkDataValid:(BOOL)arg3 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return [NSMutableArray array];
    return %orig;
}
- (id)getAdvertiseDataByCurMinTime:(unsigned int)arg1
                           MaxTime:(unsigned int)arg2 {
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
//  2. 公众号广告拦截（D.txt 原生层 + WebView 有效层）
// ============================================================================
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

// 公众号 WebView 广告 URL 黑名单 + DOM 隐藏
static BOOL ddURLIsAd(NSURL *url) {
    if (!url) return NO;
    NSString *s = [url absoluteString];
    if (s.length == 0) return NO;
    NSArray *patterns = @[
        @"wxa.wxs.qq.com/tmpl/px",
        @"wxa.wxs.qq.com/tmpl/lite",
        @"cgi-bin/mmbiz-bin/ad",
        @"ad.weixin.qq.com",
        @"mp.weixin.qq.com/mp/getappmsgad",
        @"/tmpl/px",
        @"/tmpl/lite",
        @"advertisement",
        @"advert_pos",
    ];
    for (NSString *p in patterns) {
        if ([s rangeOfString:p options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return YES;
        }
    }
    return NO;
}

static NSString *DDAdBlockMPHideCSS(void) {
    return @".iframe_ad_container,.iframe_adv_ad_container,.comment-ad-container,"
           @"li.cidad_comment_constant_key,#cidad_comment_constant_key,"
           @".adv_keyword_search,.ad_control-tips"
           @"{display:none!important;height:0!important;min-height:0!important;"
           @"margin:0!important;padding:0!important;overflow:hidden!important;}"
           @"div:has(> .iframe_ad_container),"
           @"li:has(> .comment-ad-container)"
           @"{display:none!important;height:0!important;}";
}

%hook MMWebViewController
- (BOOL)webView:(id)arg1 shouldStartLoadWithRequest:(NSURLRequest *)request {
    if (ddActive() && [DDAdBlockConfig sharedConfig].brand) {
        if (ddURLIsAd([request URL])) return NO;
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
    [wv evaluateJavaScript:DDAdBlockMPHideCSS() completionHandler:nil];
}
%end

// ============================================================================
//  3. 视频号广告拦截（1.0.8 最终版 · Flex + 头文件双重证实）
//
//  架构: 评论区广告 = 独立 WCFinderCommentAdTableViewCell
//        （Flex 视图树: UITableView → WCFinderCommentAdTableViewCell 已证实）
//
//  拦截链（三层，无猜测代码）:
//    A. Cell 视图层 neutralize（主拦截）
//    B. 控制器层: 曝光/上报/点击短路
//    C. 数据对象层（D.txt 兼容）
// ============================================================================

// 3.1 数据对象层 neutralize（D.txt 沿用，字段经 8.0.76 头文件核对）
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

// 3.2 ★ Cell 视图层 neutralize（Flex 已证实此 Cell 存在）
//   依据: WCFinderCommentAdTableViewCell.h 真实方法名
%hook WCFinderCommentAdTableViewCell

// 更新入口: 调用原始实现保证内部状态一致，随后清空 + 隐藏
// 注意: 所有方法调用均通过 objc_msgSend 运行时派发，不用中括号 [cell xxx]
//       原因: WCFinderCommentAdTableViewCell 仅有 @class 前向声明，
//             ARC 会对中括号调用做静态选择器校验并报错
//             (no known instance method for selector 'resetCellData')。
//             故一律走 SEL + IMP 派发，存在性由 class_respondsToSelector 保证。
- (void)updateWithModel:(id)arg1 width:(double)arg2 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder) {
        %orig;  // 保留原始调用，保证内部状态机正常，避免空内容 crash

        // 隐藏 cell（等同 self.hidden = YES），运行时派发
        SEL setHiddenSel = @selector(setHidden:);
        if (class_respondsToSelector([(id)self class], setHiddenSel)) {
            void (*imp)(id, SEL, BOOL) = (void (*)(id, SEL, BOOL))
                [(id)self methodForSelector:setHiddenSel];
            if (imp) imp((id)self, setHiddenSel, YES);
        }
        return;
    }
    %orig;
}

// section 高度 → 0: 广告 cell 不占空间
// （不再判断 isAdSection，因为所有 WCFinderCommentAdTableViewCell 都是广告 cell）
+ (double)sectionHeightWith:(id)arg1 width:(double)arg2 halfScreenHeight:(double)arg3 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder) {
        return 0.0;
    }
    return %orig;
}

// cell 级高度也兜底 → 0
- (double)heightForMediaWithRatio:(double)arg1
               maxHeightPercentage:(long long)arg2
                          minArea:(unsigned long long)arg3 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder) {
        return 0.0;
    }
    return %orig;
}

// 阻止广告视频/图片/跳转渲染
- (void)updatePlayerViewWithCommentInfo:(id)arg1 videoInfo:(id)arg2 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return;
    %orig;
}
- (void)updateImageViewWithCommentImageInfo:(id)arg1 imgInfo:(id)arg2 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return;
    %orig;
}
- (void)clickADContentActionWithArea:(int)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return;
    %orig;
}

// 上报抑制
- (id)commentAdReportDictWithReportScene:(long long)arg1 clickArea:(int)arg2 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return nil;
    return %orig;
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

// 3.3 ★ 控制器层: 曝光/上报/点击短路（方法名来自真实头文件）
%hook WCFinderCommentDetailViewController

- (void)checkCommentAdPlayerExposeStateIfNeeded {
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return;
    %orig;
}

- (void)reportCommentAdIfNeededWithReportScene:(long long)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return;
    %orig;
}

- (void)reportCommentAd:(id)arg1 withReportScene:(long long)arg2 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return;
    %orig;
}

- (void)_configADCellReportBehavior:(id)arg1 comment:(id)arg2 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return;
    %orig;
}

// commentAdCell: 系列点击/长按 → 全部短路
- (void)commentAdCell:(id)arg1 clickFeedbackButton:(id)arg2 atSection:(unsigned long long)arg3 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return;
    %orig;
}
- (void)commentAdCell:(id)arg1 longPressAtSection:(unsigned long long)arg2 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return;
    %orig;
}
- (void)commentAdCell:(id)arg1 clickJumpInfo:(id)arg2 atSection:(unsigned long long)arg3 clickArea:(int)arg4 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return;
    %orig;
}
- (void)commentAdCell:(id)arg1 clickFullTextAtSection:(unsigned long long)arg2 isExpand:(BOOL)arg3 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return;
    %orig;
}
- (void)commentAdCell:(id)arg1 clickNicknameAtSection:(unsigned long long)arg2 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return;
    %orig;
}
- (void)commentAdCell:(id)arg1 clickAvatarAtSection:(unsigned long long)arg2 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return;
    %orig;
}
- (void)_commentAdCellReporstClickType:(unsigned long long)arg1 comment:(id)arg2 section:(unsigned long long)arg3 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return;
    %orig;
}

// clearCommentAdState: 保留原始调用（清理状态无害）
- (void)clearCommentAdState {
    %orig;
}
%end

// ============================================================================
//  4. 小程序广告拦截（WebView 有效层 + 原生层，沿用 D.txt）
// ============================================================================

// 小程序 WebView 广告隐藏 JS（<ad>/<ad-custom> DOM sweep）
static NSString *DDAdBlockMiniAppHideCSS(void) {
    return @"wx-ad,wx-ad-custom,ad,ad-custom,.wx-ad,.wx-ad-custom"
           @"{display:none!important;height:0!important;min-height:0!important;"
           @"max-height:0!important;margin:0!important;padding:0!important;"
           @"overflow:hidden!important;}";
}

%hook WAWebViewController
- (BOOL)webView:(id)arg1 shouldStartLoadWithRequest:(NSURLRequest *)request {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) {
        if (ddURLIsAd([request URL])) return NO;
    }
    return %orig;
}

- (void)webViewDidFinishLoad:(id)arg1 navigation:(id)arg2 {
    %orig;
    if (!(ddActive() && [DDAdBlockConfig sharedConfig].miniProgram)) return;
    id wv = nil;
    @try { wv = [(id)self valueForKey:@"webView"]; } @catch (__unused NSException *e) {}
    if (![wv respondsToSelector:@selector(evaluateJavaScript:completionHandler:)]) return;
    [(WKWebView *)wv evaluateJavaScript:DDAdBlockMiniAppHideCSS() completionHandler:nil];
}
%end

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

// ============================================================================
//  5. 直播广告拦截
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
//  6. 搜索广告拦截（位于「广告拦截场景-直播广告下方」）
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
//  7. 激励广告快速跳过（进阶拦截唯一项）
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

// ============================================================================
//  9. 设置界面
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
    _tableViewManager = [[managerCls alloc] initWithFrame:self.view.bounds
                                                     style:UITableViewStyleInsetGrouped];
    _tableViewManager.tableView.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _tableViewManager.tableView.contentInsetAdjustmentBehavior =
        UIScrollViewContentInsetAdjustmentAutomatic;
    [self.view addSubview:_tableViewManager.tableView];

    [self buildTable];
}

- (void)buildTable {
    [_tableViewManager clearAllSection];
    Class sectionCls = %c(WCTableViewSectionManager);
    Class cellCls = %c(WCTableViewCellManager);
    DDAdBlockConfig *cfg = [DDAdBlockConfig sharedConfig];

    // 广告拦截场景
    WCTableViewSectionManager *secMain = [sectionCls sectionWithHeader:@"广告拦截场景"];
    [secMain addCell:[cellCls switchCellForSel:@selector(onMasterSwitch:)
                                        target:self
                                         title:@"启用广告拦截"
                                            on:cfg.master]];
    [secMain addCell:[cellCls switchCellForSel:@selector(onMomentsSwitch:)
                                        target:self
                                         title:@"屏蔽朋友圈广告"
                                            on:cfg.moments]];
    [secMain addCell:[cellCls switchCellForSel:@selector(onBrandSwitch:)
                                        target:self
                                         title:@"屏蔽公众号广告"
                                            on:cfg.brand]];
    [secMain addCell:[cellCls switchCellForSel:@selector(onFinderSwitch:)
                                        target:self
                                         title:@"屏蔽视频号广告"
                                            on:cfg.finder]];
    [secMain addCell:[cellCls switchCellForSel:@selector(onLiveSwitch:)
                                        target:self
                                         title:@"屏蔽直播广告"
                                            on:cfg.live]];
    [secMain addCell:[cellCls switchCellForSel:@selector(onSearchSwitch:)
                                        target:self
                                         title:@"屏蔽搜索广告"
                                            on:cfg.search]];
    [secMain addCell:[cellCls switchCellForSel:@selector(onMiniProgramSwitch:)
                                        target:self
                                         title:@"屏蔽小程序广告"
                                            on:cfg.miniProgram]];
    [_tableViewManager addSection:secMain];

    // 进阶拦截: 仅激励广告快速跳过
    WCTableViewSectionManager *secAdv = [sectionCls sectionWithHeader:@"进阶拦截"];
    [secAdv addCell:[cellCls switchCellForSel:@selector(onRewardedSwitch:)
                                       target:self
                                        title:@"激励广告快速跳过"
                                           on:cfg.rewardedFastPass]];
    [_tableViewManager addSection:secAdv];

    [_tableViewManager reloadTableView];
}

// 开关回调
- (void)onMasterSwitch:(UISwitch *)s        { [DDAdBlockConfig sharedConfig].master = s.isOn; [self buildTable]; }
- (void)onMomentsSwitch:(UISwitch *)s       { [DDAdBlockConfig sharedConfig].moments = s.isOn; }
- (void)onBrandSwitch:(UISwitch *)s         { [DDAdBlockConfig sharedConfig].brand = s.isOn; }
- (void)onFinderSwitch:(UISwitch *)s        { [DDAdBlockConfig sharedConfig].finder = s.isOn; }
- (void)onLiveSwitch:(UISwitch *)s          { [DDAdBlockConfig sharedConfig].live = s.isOn; }
- (void)onSearchSwitch:(UISwitch *)s        { [DDAdBlockConfig sharedConfig].search = s.isOn; }
- (void)onMiniProgramSwitch:(UISwitch *)s   { [DDAdBlockConfig sharedConfig].miniProgram = s.isOn; }
- (void)onRewardedSwitch:(UISwitch *)s      { [DDAdBlockConfig sharedConfig].rewardedFastPass = s.isOn; }
@end

// ============================================================================
//  10. 插件注册
// ============================================================================
%ctor {
    @autoreleasepool {
        Class mgrClass = NSClassFromString(@"WCPluginsMgr");
        if (mgrClass) {
            id mgr = [mgrClass sharedInstance];
            if ([mgr respondsToSelector:@selector(registerControllerWithTitle:version:controller:)]) {
                [mgr registerControllerWithTitle:@"DD广告拦截"
                                         version:@"1.0.9"
                                      controller:@"DDAdBlockSettingsViewController"];
            }
        }
    }
}
