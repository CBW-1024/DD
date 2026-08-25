//
//  DDAdBlock.xm
//  插件名: DD广告拦截   版本: 1.0.6
//
//  变更记录:
//  - 1.0.3: 规范化缩进；开关不回弹、无宏；进阶仅留激励快过
//  - 1.0.5: 视频号运行时 KVC 探测（候选 key，未依赖具体头文件）
//  - 1.0.6: 依据 8.0.76 真实头文件重写视频号评论广告拦截 ★ 本节
//            证据：WCFinderCommentAdTableViewCell.h（class-dump 3.5, 8.0.76）
//                  WCFinderCommentDetailViewController.h
//
//  ★ 关键证据（来自头文件，非猜测）:
//    1) 评论区广告有专属 Cell: WCFinderCommentAdTableViewCell : UITableViewCell
//       - 持有 WCFinderCommentSectionViewModel *_commentVM
//       - updateWithModel:width: / resetCellData / cellForRowAtIndexPath 是必经点
//     - 控制器里有完整广告生命周期: commentAdCell:click* / reportCommentAd* /
//         checkCommentAdPlayerExposeStateIfNeeded / clearCommentAdState
//    2) 控制器把广告当 Section 管理（clickFeedbackButton:atSection: 等），
//       说明「评论区广告 ≈ 独立 section」，不是混在评论数组里的伪评论
//    3) WCFinderCommentSectionViewModel 才是广告数据的承载者（cell.commentVM）
//
//  因此 1.0.6 策略调整为:
//    A. 让广告 Cell 渲染为空 (updateWithModel:width: 短路 + resetCellData 清空)
//       并隐藏高度 (sectionHeightWith:width:halfScreenHeight: -> 0)
//       → 不需要从数组移除，从「视图层 neutralize」更稳、不破坏 dataSource 计数
//    B. 保留 1.0.5 的「数组过滤」作为第二道防线（KVC 探测，可选）
//    C. 数据层 WCFinderComment / WCFinderDataItem 沿用 D.txt（字段按头文件核对）
//
//  设计原则（对齐 D.txt 防闪退）:
//    - 不 return nil 单个对象 / 不 return 空数组（UITableView dataSource 计数一致）
//    - 只把「广告 cell 的高度置 0 + 内容清空」，视觉消失但 indexPath 不变
//    - 所有 hook 用 class 存在性 + respondsToSelector 双重保护
//
//  其余模块（公众号/小程序 WebView、朋友圈/直播/搜索、激励快过、上报抑制、设置页）
//  与 1.0.3 保持一致，未做功能性改动。
//
//  ⚠️ 合规提示: 本插件为未授权微信注入 tweak，仅用于个人逆向学习，请勿分发。
//

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#import <objc/runtime.h>

// ================== 插件管理入口（兼容不同工程） ==================
@interface WCPluginsMgr : NSObject
+ (instancetype)sharedInstance;
- (void)registerControllerWithTitle:(NSString *)title version:(NSString *)version controller:(NSString *)controller;
@end

// ================== 配置开关（显式 setter + synchronize，默认全关） ==================
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

@implementation DDAdBlockConfig {
    BOOL _master, _moments, _brand, _finder, _live, _miniProgram, _search, _rewardedFastPass;
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
    if (!self) return nil;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    // 首次安装写入默认值（全部关闭）
    if ([ud objectForKey:kDDAdBlockMasterKey] == nil)           [ud setBool:NO forKey:kDDAdBlockMasterKey];
    if ([ud objectForKey:kDDAdBlockMomentsKey] == nil)          [ud setBool:NO forKey:kDDAdBlockMomentsKey];
    if ([ud objectForKey:kDDAdBlockBrandKey] == nil)            [ud setBool:NO forKey:kDDAdBlockBrandKey];
    if ([ud objectForKey:kDDAdBlockFinderKey] == nil)           [ud setBool:NO forKey:kDDAdBlockFinderKey];
    if ([ud objectForKey:kDDAdBlockLiveKey] == nil)             [ud setBool:NO forKey:kDDAdBlockLiveKey];
    if ([ud objectForKey:kDDAdBlockMiniProgramKey] == nil)      [ud setBool:NO forKey:kDDAdBlockMiniProgramKey];
    if ([ud objectForKey:kDDAdBlockSearchKey] == nil)           [ud setBool:NO forKey:kDDAdBlockSearchKey];
    if ([ud objectForKey:kDDAdBlockRewardedFastPassKey] == nil) [ud setBool:NO forKey:kDDAdBlockRewardedFastPassKey];
    [ud synchronize];
    // 从持久化读取到 ivar
    _master           = [ud boolForKey:kDDAdBlockMasterKey];
    _moments          = [ud boolForKey:kDDAdBlockMomentsKey];
    _brand            = [ud boolForKey:kDDAdBlockBrandKey];
    _finder           = [ud boolForKey:kDDAdBlockFinderKey];
    _live             = [ud boolForKey:kDDAdBlockLiveKey];
    _miniProgram      = [ud boolForKey:kDDAdBlockMiniProgramKey];
    _search           = [ud boolForKey:kDDAdBlockSearchKey];
    _rewardedFastPass = [ud boolForKey:kDDAdBlockRewardedFastPassKey];
    return self;
}

// 显式 setter: 关闭后立即持久化，不会自动回弹（修复历史问题）
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

// ================== 通用工具 ==================

// 判断某 section view model 是否为「评论区广告 section」
// 依据: WCFinderCommentSectionViewModel 持有广告数据; 广告 section 通常可由
// commentVM.adComment / isAdSection / advertisementInfo 等标记区分。
// 采用 KVC 探测，不依赖头文件里是否暴露了具体属性名。
static BOOL ddIsFinderCommentAdSection(id sectionVM) {
    if (!sectionVM) return NO;
    // 特征1: 类名为 WCFinderCommentSectionViewModel 且带广告标记
    NSString *cls = NSStringFromClass([sectionVM class]);
    if (![cls isEqualToString:@"WCFinderCommentSectionViewModel"]) return NO;

    NSArray *adKeys = @[
        @"isAdSection",        // 最可能的广告 section 标记
        @"adComment",          // 广告 comment 对象
        @"advertisementInfo",
        @"promotionInfo",
        @"isAd",
        @"adFlag",
        @"commentAdImageUrl",
        @"adInfo",
    ];
    for (NSString *key in adKeys) {
        SEL sel = NSSelectorFromString(key);
        if (![sectionVM respondsToSelector:sel]) continue;
        id val = [sectionVM valueForKey:key];
        if (!val || [val isKindOfClass:[NSNull class]]) continue;
        if ([val isKindOfClass:[NSNumber class]] && [val integerValue] == 0) continue;
        return YES;
    }
    return NO;
}

// 判断一个 Cell 是否为评论区广告 Cell（依据真实头文件类名）
static BOOL ddIsFinderCommentAdCell(Class cellClass) {
    if (!cellClass) return NO;
    NSString *cls = NSStringFromClass(cellClass);
    return [cls isEqualToString:@"WCFinderCommentAdTableViewCell"];
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
//  2. 公众号广告拦截（原生层 + WebView 层，沿用 D.txt 已验证有效链路）
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

// 公众号文章 WebView 广告隐藏 CSS（沿用 D.txt）
static NSString *DDAdBlockMPHideCSS(void) {
    return @".iframe_ad_container,.iframe_adv_ad_container,.comment-ad-container,"
           @"li.cidad_comment_constant_key,#cidad_comment_constant_key,"
           @".adv_keyword_search,.ad_control-tips{display:none!important;"
           @"height:0!important;min-height:0!important;margin:0!important;"
           @"padding:0!important;overflow:hidden!important;}"
           @"div:has(> .iframe_ad_container),"
           @"li:has(> .comment-ad-container){display:none!important;height:0!important;}";
}

%hook MMWebViewController
- (void)webViewDidFinishLoad:(id)arg1 navigation:(id)arg2 {
    %orig;
    if (!(ddActive() && [DDAdBlockConfig sharedConfig].brand)) return;
    id wv = nil;
    @try { wv = [(id)self valueForKey:@"webView"]; } @catch (__unused NSException *e) {}
    if (![wv isKindOfClass:[WKWebView class]]) return;
    [(WKWebView *)wv evaluateJavaScript:DDAdBlockMPHideCSS() completionHandler:nil];
}
%end

// ============================================================================
//  3. 视频号广告拦截（1.0.6 基于 8.0.76 真实头文件重写 ★）
//
//  证据链:
//    WCFinderCommentDetailViewController 持有 WCFinderCommentDetailViewModel
//    评论列表以 Section 组织，广告有专属 WCFinderCommentAdTableViewCell
//    Cell 通过 updateWithModel:width: 拿到 WCFinderCommentSectionViewModel(commentVM)
//
//  策略: 「视图层 neutralize」为主（高度=0 + 内容清空），不破坏 dataSource 计数
//        → 根治"评论页闪退"且彻底隐藏广告 cell
// ============================================================================

// 3.1 数据层 neutralize（沿用 D.txt，字段经 8.0.76 核对存在性）
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

// 3.2 ★ 评论区广告 Cell 视图层 neutralize（1.0.6 核心）
//   依据: WCFinderCommentAdTableViewCell
//          - updateWithModel:width:       (必经更新入口)
//          - resetCellData                 (清空内容)
//          - sectionHeightWith:width:halfScreenHeight: (控制 section 高度)
%hook WCFinderCommentAdTableViewCell

// 更新入口短路: 直接清空，不绘制广告内容
- (void)updateWithModel:(id)arg1 width:(double)arg2 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder) {
        // 调用原始实现以保证内部状态一致（避免空内容 crash），但随后清空
        %orig;
        if ([self respondsToSelector:@selector(resetCellData)]) {
            [self resetCellData];
        }
        self.hidden = YES;
        return;
    }
    %orig;
}

// section 高度置 0 → 广告 cell 不占空间（关键: 不 return nil，只缩到 0pt）
+ (double)sectionHeightWith:(id)arg1 width:(double)arg2 halfScreenHeight:(double)arg3 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder) {
        if (ddIsFinderCommentAdSection(arg1)) {
            return 0.0;
        }
    }
    return %orig;
}

// 实例高度也兜底置 0（部分列表用 cell 级 heightForRow）
- (double)heightForMediaWithRatio:(double)arg1 maxHeightPercentage:(long long)arg2 minArea:(unsigned long long)arg3 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder) {
        return 0.0;
    }
    return %orig;
}

// 卡片容器一律清空，防止残留
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

// 上报抑制（依据控制器 reportCommentAd* 同名链路）
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

// 3.3 ★ 控制器层: 阻止广告 section 的曝光/上报/播放（依据真实方法名）
%hook WCFinderCommentDetailViewController

// 曝光检查: 直接返回，不触发广告曝光上报
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

// 广告 cell 配置/点击全部短路
- (void)_configADCellReportBehavior:(id)arg1 comment:(id)arg2 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return;
    %orig;
}

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
- (void)clearCommentAdState {
    // 正常流程，不拦截（清理状态是无害的），保留 %orig 保证内部一致性
    %orig;
}
%end

// 3.4 Section ViewModel 层（承载广告数据 commentVM）
//   WCFinderCommentSectionViewModel 若存在广告标记属性，在此 neutralize
%hook WCFinderCommentSectionViewModel
- (id)adComment {
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return nil;
    return %orig;
}
- (id)advertisementInfo {
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return nil;
    return %orig;
}
- (BOOL)isAdSection {
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return NO;
    return %orig;
}
// 若列表通过 commentList 组装，过滤广告 comment（沿用 1.0.5 第二道防线）
- (NSArray *)commentList {
    if (!ddActive() || ![DDAdBlockConfig sharedConfig].finder) return %orig;
    NSArray *orig = %orig;
    if (![orig isKindOfClass:[NSArray class]] || orig.count == 0) return orig;
    NSMutableArray *filtered = [NSMutableArray arrayWithCapacity:orig.count];
    for (id c in orig) {
        if (ddIsFinderCommentAdSection(c)) continue;  // 跳过广告 section/comment
        [filtered addObject:c];
    }
    return filtered;
}
%end

// ============================================================================
//  4. 小程序广告拦截（WebView 有效层 + 原生层，沿用 D.txt）
// ============================================================================

// 小程序 WebView 广告隐藏 JS（沿用 D.txt <ad>/<ad-custom> DOM sweep）
static NSString *DDAdBlockMiniAppHideCSS(void) {
    return @"wx-ad,wx-ad-custom,ad,ad-custom,.wx-ad,.wx-ad-custom"
           @"{display:none!important;height:0!important;min-height:0!important;"
           @"max-height:0!important;margin:0!important;padding:0!important;"
           @"overflow:hidden!important;}";
}

%hook WAWebViewController
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
                                         version:@"1.0.6"
                                      controller:@"DDAdBlockSettingsViewController"];
            }
        }
    }
}
