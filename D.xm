//
//  DD广告拦截 v1.2.9 — 微信广告拦截插件（单文件 Logos/Theos tweak）
//  10 个开关，默认全部关闭；每个 Hook 经总开关 + 分区开关双重门控。
//  v1.2.8 纯编译修复（CI 报错 “receiver type '_TtC6WeChat20/23MagicPlayableService' is a forward declaration”）：
//    两处 [self notifyMiniProgramPlayableStatusWithIsEnd:YES] 改为 objc_msgSend 强转调用，
//    绕开 Swift 前向声明类无法在编译期识别该方法的问题。逻辑与 v1.2.7 完全一致。
//  v1.2.9 移除「关闭青少年模式弹窗」功能（WCR: disableTeenagerPopupEnabled）：删除对应开关、
//    WCFinderTimelineTabViewController 的 3 个 hook 方法及设置项，不再拦截青少年模式弹窗。
//  v1.2.7 修对齐（再反汇编 WCR + 微信 7.6）：
//    1) 试玩广告（PlayableAd / “试玩 19 秒获得奖励”）秒过：
//       _TtC6WeChat20MagicPlayableService + _TtC6WeChat23MagicNewPlayableService
//       - startWithConfig: 后立即 notifyMiniProgramPlayableStatusWithIsEnd:YES
//       - notifyMiniProgramPlayableStatusWithIsEnd: 兜底强制 YES
//       对齐 WCR：__cstring 'MagicPlayableService.startWithConfig' / 'MagicNewPlayableService.startWithConfig'
//         + selrefs 'notifyMiniProgramPlayableStatusWithIsEnd:' / 'isPlayable'
//    2) 试玩广告生命周期 JS 桥（7 个 Swift 事件桥）全部短路：
//       _TtC6WeChat46/49 WAJSEventHandler_update/remove/insertMiniProgramPlayableView(New)
//       _TtC6WeChat46 MPEventHandler_notifyMiniProgramPlayableStatus
//       _TtC6WeChat49 MBEventHandler_notifyMiniProgramPlayableStatusNew
//    3) 激励视频秒过修复：
//       - 移除 WCFinderRewardAdViewController.viewDidLoad 空实现（破坏 adHasPlayOver 传递链）
//       - 改 hook startAdCountdownTimer 直接 return 掐断视频倒计时
//       - WAJSEventHandler_adOperateWXData.handleJSEvent: 在 rewardedFastPass 开启时放行
//         （fastpass 标志必须透传，否则小程序不发奖）
//       - rewardedFastPass 默认值改 YES（开箱即用秒过）
//    4) 视频号广告 banner 视图（WCFinderAdBannerView）init 返回 nil，不再渲染“广告”横条。
//    v1.2.6 修微信 7.6 兼容性：internalGetAdInfoFromCacheWithPosId → getCachedAdInfoForPosId（MagicAdCommonService 已改名）。
//  开关命名对齐 WCR（WCRefine）的 enhancedAdBlock*Enabled 模块：moments/brand/finder/live/
//  miniProgram/network/search/rewardedAdFastPass/expt。
//  全部 Hook 落点经 WCR 反汇编精确核对（__cstring 说明字符串 + __objc_selrefs 双重证据）：
//   v1.2.0 修正：小程序广告走“开屏 JS 事件 + 广告推送消息”双入口（WCR 机制）；
//     激励广告走 adHasPlayOver + viewDidLoad；公众号/WebView 广告补 MBEventHandler_* JS 桥。
//   v1.2.1 补强：小程序横幅/插屏按实测补 MagicAdCommonService 数据拉取层 +
//     Swift 展示服务（MagicAdMiniProgramService）+ 网络层兜底。
//   v1.2.2 补强：小程序再加 MagicAdCGIMgr.getAdsCGIWithPosIds:（最底层 CGI 发起）
//     + WASplashADWindow.showRootViewControllerAnimated:（开屏展示兜底）。
//   v1.2.3 补强（反汇编复核）：恢复 WCR 精确落点但此前遗漏的开屏类——
//     WAExptProxy.shouldShowSplashAD -> NO（'WAExptProxy shouldShowSplashAD -> NO'）、
//     WAAppTaskSplashADConfig.splashADEnableNumber/canShowSplashADWindow/splashADHasContent/
//     canHotStartShowSplashAD（'splashADEnableNumber -> NO' + selrefs）、
//     WAAppTask.isSplashADFinished -> YES（'isSplashADFinished -> YES'）+ splashAD_didFinished；
//     朋友圈补 WCAdDB（建表）+ WCAdvertiseInfo（广告信息解析）+ WCAdvertiseDataHelper
//     addAdvertiseData:needUpdateCreateTime:；公众号补 _TtC6WeChat19MagicAdBrandService
//     notifyAdServerInfoEventWithFeedsType:adInfo:（品牌广告信息流）。
//   v1.2.4 补强（反汇编复核）：公众号再补 WCR 精确落点——
//     WebviewJSEventHandler_adDataReport（'...adDataReport blocked'）广告上报 JS 桥、
//     BrandTLFlutterViewController.enableAd/setEnableAd:（'enableAd -> NO'/'setEnableAd -> force NO'）
//     公众号 Flutter 页广告开关。至此 WCR 全部广告 hook 落点均已覆盖。
//   v1.2.5 补强（反汇编复核）：补上此前遗漏的 WCR 精确落点——
//     BrandTLExptConfig.exptShowOption / setExptShowOption:（'exptShowOption %u -> %u (clear ad bit)' /
//     'setExptShowOption %u -> %u'）。该属性为广告实验开关的底层位掩码，WCR 读写时清除“广告位”。
//     同步补 BSTLExptConfig（同样声明 exptShowOption 属性）。至此与 WCR 反汇编落点完全对齐。
//   v1.2.6 适配（基于微信 7.6 头文件复核）：MagicAdCommonService 的缓存广告方法在微信 7.6 已
//     由 internalGetAdInfoFromCacheWithPosId: 改名为 getCachedAdInfoForPosId:，同步改名以继续
//     拦截小程序横幅/插屏广告的缓存数据入口。其余 43 个 hook 类、全部 WCR 文档化落点在 7.6 头文件
//     中均仍存在（setEnableAd:/setExptShowOption: 为 @property 合成 setter，属正常）。
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
        if ([ud objectForKey:kDDAdBlockRewardedFastPassKey] == nil) [ud setBool:YES forKey:kDDAdBlockRewardedFastPassKey];
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
// 对齐 WCR 引用 addAdvertiseData:needUpdateCreateTime:（朋友圈广告数据入池入口，空实现丢弃）
- (void)addAdvertiseData:(id)arg1 needUpdateCreateTime:(BOOL)arg2 {
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

// 对齐 WCR（__objc_selrefs 精确引用）：朋友圈广告数据库建表入口。
// 拦截 createPullRecordTable/createTables/initDB → 广告数据无处落库，广告不持久化、不展示。
%hook WCAdDB
- (void)createPullRecordTable {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return;
    %orig;
}
- (void)createTables {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return;
    %orig;
}
- (void)initDB {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return;
    %orig;
}
%end

// 对齐 WCR（__objc_selrefs 精确引用）：广告动态信息解析入口。
// 返回 nil → 广告动态信息解析失败，广告内容不构造、不展示。
%hook WCAdvertiseInfo
+ (id)dictionaryFromADDynamicInfo:(id)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return nil;
    return %orig;
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
// 对齐 WCR（__cstring 'BrandTLExptConfig exptShowOption %u -> %u (clear ad bit)' /
//   'BrandTLExptConfig setExptShowOption %u -> %u'）：实验开关式广告抑制的底层位掩码。
// exptShowOption 为 unsigned int 位掩码，WCR 在读写时清除“广告位”（clear ad bit）。
// 与上方 4 个 isExptNotShow* 返回 YES 形成双重保险：即便广告判定走 exptShowOption 直读路径，
// 清位后同样判定“不展示广告”。清最低位（ad 位，对应 isExptNotShowAd）；其余 3 位已由上方
// isExptNotShow* 强制 YES 覆盖，清错位也只会冗余抑制、不会误伤正常功能。
- (unsigned int)exptShowOption {
    unsigned int v = %orig;
    if (ddActive() && [DDAdBlockConfig sharedConfig].expt) return v & ~1U;
    return v;
}
- (void)setExptShowOption:(unsigned int)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].expt) { %orig(arg1 & ~1U); return; }
    %orig;
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
// 对齐 WCR：BSTLExptConfig 同样声明 exptShowOption 位掩码属性，与 BrandTLExptConfig 同机制
// （WCR 'BrandTLExptConfig exptShowOption ... (clear ad bit)' 同款清位逻辑）。清最低 ad 位。
- (unsigned int)exptShowOption {
    unsigned int v = %orig;
    if (ddActive() && [DDAdBlockConfig sharedConfig].expt) return v & ~1U;
    return v;
}
- (void)setExptShowOption:(unsigned int)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].expt) { %orig(arg1 & ~1U); return; }
    %orig;
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

// ========== 2.x 公众号/WebView 广告的 JS 桥事件拦截（精确对齐 WCR）[WCR: enhancedAdBlockBrandEnabled] ==========
// WCR 通过 __objc_selrefs 精确引用了这些 WebView JS 桥处理器（MBEventHandler_*/WebviewJSEventHandler），
// 在 JS 桥层丢弃广告请求/数据注入：
//   MBEventHandler_getAdPushMsg.invoke:           获取广告推送消息
//   MBEventHandler_getOldAdInfo.invoke:           获取旧广告信息
//   MBEventHandler_setAdRequestInfo.invoke:       设置广告请求信息
//   MBEventHandler_setAdCardRequestInfo.invoke:   设置广告卡片请求信息
//   MBEventHandler_setFeedsAdRequestInfo.invoke:  设置信息流广告请求信息
//   WebviewJSEventHandler_getAdIdInfo.checkUrlValid:  广告ID获取的URL校验
// 拦截这些 → 公众号文章/WebView 内广告的 JS 桥拿不到广告数据，广告不再注入。
%hook MBEventHandler_getAdPushMsg
- (void)invoke:(id)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].brand) return;
    %orig;
}
%end

%hook MBEventHandler_getOldAdInfo
- (void)invoke:(id)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].brand) return;
    %orig;
}
%end

%hook MBEventHandler_setAdRequestInfo
- (void)invoke:(id)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].brand) return;
    %orig;
}
%end

%hook MBEventHandler_setAdCardRequestInfo
- (void)invoke:(id)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].brand) return;
    %orig;
}
%end

%hook MBEventHandler_setFeedsAdRequestInfo
- (void)invoke:(id)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].brand) return;
    %orig;
}
%end

%hook WebviewJSEventHandler_getAdIdInfo
- (BOOL)checkUrlValid {
    if (ddActive() && [DDAdBlockConfig sharedConfig].brand) return NO;
    return %orig;
}
%end

// WCR 精确落点（__cstring 'WebviewJSEventHandler_adDataReport blocked'）：
// 公众号广告数据上报 JS 桥，空实现 → 广告上报被阻断，广告不统计不落地。
%hook WebviewJSEventHandler_adDataReport
- (void)handleJSEvent:(id)arg1 HandlerFacade:(id)arg2 ExtraData:(id)arg3 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].brand) return;
    %orig;
}
%end

// WCR 精确落点（__cstring 'BrandTLFlutterViewController enableAd -> NO' / 'setEnableAd:%d -> force NO'）：
// 公众号 Flutter 页面广告开关，强制关闭 → 公众号 Flutter 内广告不展示。
%hook BrandTLFlutterViewController
- (BOOL)enableAd {
    if (ddActive() && [DDAdBlockConfig sharedConfig].brand) return NO;
    return %orig;
}
- (void)setEnableAd:(BOOL)arg1 {
    // WCR 'setEnableAd:%d -> force NO'：无论传入什么都强制 NO，且不调用原实现（避免递归）。
    if (ddActive() && [DDAdBlockConfig sharedConfig].brand) return;
    %orig;
}
%end

// 对齐 WCR（__objc_selrefs 精确引用 notifyAdServerInfoEventWithFeedsType:adInfo:）：
// 公众号品牌广告信息流通知，空实现 → 品牌广告信息不上报、不进入展示流程。
%hook _TtC6WeChat19MagicAdBrandService
- (void)notifyAdServerInfoEventWithFeedsType:(long long)arg1 adInfo:(id)arg2 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].brand) return;
    %orig;
}
%end

// ========== 2.x 公众号 WebView 广告（DOM 层兜底） ==========
// 公众号文章内广告为 WebView 动态插入的 iframe，从 DOM + CSS 两层隐藏（作为 JS 桥拦截的兜底）。
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

// 视频号广告 banner 视图：截断“广告”标识+跳转链接的渲染。WCR 在 WCFinderAdBannerView 上 hook，
// 头像边或卡片顶部带“广告”标识的横条全部不渲染。
%hook WCFinderAdBannerView
- (id)initWithFrame:(struct CGRect)arg1 jumpInfo:(id)arg2 enableClick:(BOOL)arg3 disableIconColor:(id)arg4 disableTextColor:(id)arg5 iconSize:(struct CGSize)arg6 textFont:(id)arg7 delegate:(id)arg8 textNormalColor:(id)arg9 adLabelColor:(id)arg10 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return nil;
    return %orig;
}
%end

// ========== 4. 小程序广告（多入口全覆盖）[WCR: enhancedAdBlockMiniProgramEnabled] ==========
// 微信小程序广告（开屏 + 横幅/插屏 + 广告推送消息）在原生层拦截，不注入 WebView
// （注入会误伤正常请求、产生“网络连接失败”，且 display:none 不停音频/卡顿）。
//
// 【覆盖机制】小程序广告分四类入口，逐一堵死：
//   1) 开屏广告（精确对齐 WCR，__cstring 说明字符串 + __objc_selrefs 双重确认）：
//      - WAExptProxy.shouldShowSplashAD -> NO            （'WAExptProxy shouldShowSplashAD -> NO'）
//      - WAAppTaskSplashADConfig.splashADEnableNumber -> 0
//        canShowSplashADWindow / splashADHasContent / canHotStartShowSplashAD -> NO
//        handleShowSplashAdCalled: 空实现                 （'splashADEnableNumber -> NO' + selrefs）
//      - WAAppTask.isSplashADFinished -> YES              （'WAAppTask isSplashADFinished -> YES'）
//        splashAD_didFinished 空实现                      （selrefs）
//      - WASplashADWindow.showRootViewControllerAnimated:completion: 跳过
//        （'WASplashADWindow skip showRootViewController'）+ initWithFrame: nil 双保险
//      - WAJSEventHandler_showSplashAd / _showSplashAdMenu  short-circuit
//        （'showSplashAd short-circuit' / 'showSplashAdMenu short-circuit'）
//      - WAJSEventHandler_adOperateWXData（handleJSEvent/endCancel/endOKWithData:/onResponseData:）
//   2) 横幅/插屏广告“数据拉取层”（实测确认的真实数据入口）：
//      - MagicAdCGIMgr.getAdsCGIWithPosIds: → 不发 CGI
//      - MagicAdCommonService.getAdInfoWithPosId: → nil / getAdInfoAsyncWithPosId: → 拦截
//   3) 插屏/横幅“展示服务层”（Swift，按实测补强）：
//      - _TtC9WeAppCore25MagicAdMiniProgramService.handleJsEvent:/
//        prepareWithAppId:/sendEventToMBBizWithBizName:event:data:
//   4) 广告“推送消息层”（对齐 WCR）：
//      - MagicAdPushMgrService.handleAdMsg: / WCAdvertisePushService.handlePushMsg:
// 另有网络层兜底（见下方 NSURLSession：miniProgram 开关开启时拦截广告 CGI）。
//
%hook WAAppTaskSplashADConfig
// WCR 精确落点（__objc_selrefs + __cstring 双重确认）：
//   'WAAppTaskSplashADConfig splashADEnableNumber -> NO' 说明字符串
//   selrefs 引用 splashADEnableNumber / canShowSplashADWindow / splashADHasContent /
//   canHotStartShowSplashAD / splashAD_didFinished / handleShowSplashAdCalled:
// 全部归为开屏广告“是否允许展示”的判断，统一返回禁用值 → 开屏广告从源头不出现。
- (NSNumber *)splashADEnableNumber {
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
- (void)handleShowSplashAdCalled:(BOOL)arg1 {
    // WCR：开屏广告被调用展示的入口。空实现 → 从最上游禁止开屏广告逻辑执行。
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return;
    %orig;
}
%end

// WCR 精确落点（__cstring 说明字符串 'WAExptProxy shouldShowSplashAD -> NO'）：
// 开屏广告“是否展示”的总开关，返回 NO → 从最上游禁止任何开屏广告出现。
%hook WAExptProxy
+ (BOOL)shouldShowSplashAD {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return NO;
    return %orig;
}
%end

// WCR 精确落点（__cstring 说明字符串 'WAAppTask isSplashADFinished -> YES'）：
// 开屏广告“是否已完成”判断，返回 YES → 微信认为开屏流程已结束，不再拉起。
%hook WAAppTask
- (BOOL)isSplashADFinished {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return YES;
    return %orig;
}
- (void)splashAD_didFinished {
    // WCR 引用 splashAD_didFinished（开屏广告完成通知）：空实现 → 不再推进开屏后续流程。
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return;
    %orig;
}
%end

// 开屏广告 JS 事件处理器：小程序内 wx.showSplashAd 调用被丢弃，广告不会拉起。
%hook WAJSEventHandler_showSplashAd
- (void)handleJSEvent:(id)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return;
    %orig;
}
%end

// 开屏广告“菜单”JS 事件处理器：菜单触发同样丢弃。
%hook WAJSEventHandler_showSplashAdMenu
- (void)handleJSEvent:(id)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return;
    %orig;
}
%end

// 广告操作数据 JS 事件处理器：adOperateWXData 的请求/响应数据清空（对齐 WCR 4 个落点）。
// 【特别说明】handleJSEvent: 是小程序向微信注入“激励已看完”等业务回调的唯一入口。
// 当 rewardedFastPass 开启时，必须放行该事件（携带 fastpass=1 让小程序立刻发奖），
// 否则激励秒过会因回调被掐断而失败（表现为“点完不结算”）。
%hook WAJSEventHandler_adOperateWXData
- (void)handleJSEvent:(id)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) {
        // 放行激励秒过的回调通道（不再拦截）
        if ([DDAdBlockConfig sharedConfig].rewardedFastPass) {
            %orig;
            return;
        }
        return;
    }
    %orig;
}
- (void)endCancel {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return;
    %orig;
}
- (void)endOKWithData:(id)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return;
    %orig;
}
- (void)onResponseData:(id)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return;
    %orig;
}
%end

// 试玩广告（PlayableAd / “试玩 19 秒获得奖励”）秒过（精确对齐 WCR：
// __cstring 描述串 'MagicPlayableService.startWithConfig' / 'MagicNewPlayableService.startWithConfig'
// + __objc_selrefs 'notifyMiniProgramPlayableStatusWithIsEnd:' / 'isPlayable'）。
// 启动后立即 notifyMiniProgramPlayableStatusWithIsEnd:YES，让小程序运行时认为试玩已结束并立刻发奖，
// 不再等待 19 秒试玩。notifyMiniProgramPlayableStatusWithIsEnd: 兜底强制 YES，应对 startWithConfig 漏触发场景。
%hook _TtC6WeChat20MagicPlayableService
- (void)startWithConfig:(id)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) {
        %orig(arg1);
        // 前向声明的 Swift 类无法在编译期识别该方法，用 objc_msgSend 强转调用绕过
        SEL _ddPlayableSel = NSSelectorFromString(@"notifyMiniProgramPlayableStatusWithIsEnd:");
        if (_ddPlayableSel) ((void (*)(id, SEL, BOOL))objc_msgSend)((id)self, _ddPlayableSel, YES);
        return;
    }
    %orig;
}
- (void)notifyMiniProgramPlayableStatusWithIsEnd:(BOOL)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) {
        %orig(YES);
        return;
    }
    %orig;
}
%end

%hook _TtC6WeChat23MagicNewPlayableService
- (void)startWithConfig:(id)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) {
        %orig(arg1);
        // 前向声明的 Swift 类无法在编译期识别该方法，用 objc_msgSend 强转调用绕过
        SEL _ddPlayableSel = NSSelectorFromString(@"notifyMiniProgramPlayableStatusWithIsEnd:");
        if (_ddPlayableSel) ((void (*)(id, SEL, BOOL))objc_msgSend)((id)self, _ddPlayableSel, YES);
        return;
    }
    %orig;
}
- (void)notifyMiniProgramPlayableStatusWithIsEnd:(BOOL)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) {
        %orig(YES);
        return;
    }
    %orig;
}
%end

// 试玩广告生命周期 JS 桥：插入/更新/移除试玩视图的事件全部清空
// （selrefs 中 WCR 对应的 _TtC6WeChat* 系列 Swift 事件桥）。即使 PlayableService hook 未触发，
// JS 层也不会再创建试玩视图渲染。
%hook _TtC6WeChat46WAJSEventHandler_updateMiniProgramPlayableView
- (void)handleJSEvent:(id)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return;
    %orig;
}
%end

%hook _TtC6WeChat49WAJSEventHandler_updateMiniProgramPlayableViewNew
- (void)handleJSEvent:(id)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return;
    %orig;
}
%end

%hook _TtC6WeChat46WAJSEventHandler_removeMiniProgramPlayableView
- (void)handleJSEvent:(id)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return;
    %orig;
}
%end

%hook _TtC6WeChat49WAJSEventHandler_removeMiniProgramPlayableViewNew
- (void)handleJSEvent:(id)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return;
    %orig;
}
%end

%hook _TtC6WeChat49WAJSEventHandler_insertMiniProgramPlayableViewNew
- (void)handleJSEvent:(id)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return;
    %orig;
}
%end

%hook _TtC6WeChat46MPEventHandler_notifyMiniProgramPlayableStatus
- (void)invoke:(id)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return;
    %orig;
}
%end

%hook _TtC6WeChat49MBEventHandler_notifyMiniProgramPlayableStatusNew
- (void)invoke:(id)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return;
    %orig;
}
%end

// 开屏广告窗口：双保险拦截。
//   1) initWithFrame: 返回 nil → 窗口不创建（WCR 对齐点）
//   2) showRootViewControllerAnimated:completion: 空实现 → 即使窗口已创建也不展示开屏广告根VC
%hook WASplashADWindow
- (id)initWithFrame:(struct CGRect)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return nil;
    return %orig;
}
- (void)showRootViewControllerAnimated:(BOOL)arg1 completion:(id)arg2 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) {
        // 跳过开屏广告展示，直接执行完成回调：无广告界面、无声音、不卡顿
        if (arg2) { @try { ((void (^)(id))arg2)(nil); } @catch (__unused NSException *e) {} }
        return;
    }
    %orig;
}
%end

// 广告推送消息：小程序/朋友圈广告通过推送消息下发。丢弃 → 广告不落地。
%hook MagicAdPushMgrService
- (void)handleAdMsg:(id)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return;
    %orig;
}
%end

// 广告推送服务（通用广告推送）：丢弃推送，阻断广告消息入池。
%hook WCAdvertisePushService
- (void)handlePushMsg:(id)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return;
    %orig;
}
%end

// 小程序广告 CGI 发起者（按 posId 拉取广告数据的最底层入口）。
// 拦截 getAdsCGIWithPosIds: → 小程序广告子系统发不出拉取请求，横幅/插屏/开屏都拿不到数据。
// 注：此方法为纯 CGI 请求发起，直接 return 只导致“无广告数据”，不会触发 failBlock 报错，
// 也不会产生“网络连接失败”。
%hook MagicAdCGIMgr
+ (void)getAdsCGIWithPosIds:(id)arg1 successBlock:(id)arg2 failBlock:(id)arg3 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return;
    %orig;
}
%end

// 通用广告服务（小程序横幅/插屏广告的真实数据入口）。
// 实测确认：小程序内横幅/插屏广告通过 MagicAdCommonService 按 posId 拉取广告数据。
// 拦截策略（实测有效、且不误伤）：
//   1) 同步数据入口 getAdInfoWithPosId: / getCachedAdInfoForPosId: 返回 nil
//      —— 调用方拿到 nil 即视为“无广告”，绝对安全，不会超时/报错。
//      注：微信 7.6 起原 internalGetAdInfoFromCacheWithPosId: 已改名为 getCachedAdInfoForPosId:。
//   2) 异步拉取入口 getAdInfoAsyncWithPosId:completion: 直接 return（不再下发广告数据）。
// 配合 JS 事件层拦截（开屏）与网络层兜底（广告 CGI），完整覆盖小程序开屏/横幅/插屏广告。
%hook MagicAdCommonService
- (id)getAdInfoWithPosId:(id)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return nil;
    return %orig;
}
- (id)getCachedAdInfoForPosId:(id)arg1 {
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
%end

// 小程序插屏/横幅广告核心服务（Swift：_TtC9WeAppCore25MagicAdMiniProgramService）。
// 持有 systemCoverView / contentView / 广告容器，小程序内插屏(banner/插屏/激励插屏)广告
// 都经由它：JS 指令 -> handleJsEvent: -> 准备 -> sendEventToMBBiz -> 渲染展示。
// 拦截其指令/准备/渲染发送入口 → 小程序内非开屏广告不再拉起。
// 注：WCR 未覆盖此类（仅覆盖开屏 JS 事件 + 推送），此为按实测补强，更彻底拦净小程序广告。
%hook _TtC9WeAppCore25MagicAdMiniProgramService
- (void)handleJsEvent:(id)arg1 extraInfo:(id)arg2 callback:(id)arg3 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return;
    %orig;
}
- (void)prepareWithAppId:(id)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return;
    %orig;
}
- (void)sendEventToMBBizWithBizName:(id)arg1 event:(id)arg2 data:(id)arg3 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return;
    %orig;
}
%end

// 网络层广告拦截：dataTask 层命中广告正则的请求被替换为本地空 data: 请求。
// 关键边界：
//  1) 不在 HttpClientAppleImpl 的 willPerformHTTPRedirection 里取消重定向——那会误伤正常
//     重定向链（含激励广告 SDK 的跳转），导致“网络未连接”。只保留 dataTask 层拦截。
//  2) 激励广告（rewardedFastPass 开启）时跳过拦截：激励由 adHasPlayOver 秒过处理，
//     网络层再拦会让激励视频加载失败并弹“网络未连接”。
//  3) 正则只匹配微信专属广告 CGI token（getadvert/ad_posid/advertisement_ 等），且不包含
//     reward/rewardad/reward-video，避免误伤激励广告自身的视频/数据请求。
//  4) 开关：network（网络层广告拦截）或 miniProgram（小程序广告）任一开启即生效——
//     小程序广告数据经 CGI（含 ad_posid）拉取，网络层兜底可拦住未走 MagicAdCommonService 的请求。
static NSString * const kDDAdBlockAdURLPattern =
    @"advert_group|getadvert|getAdPreloadData|ad_posid|_ads_|/ads_|advertisement_";

static BOOL DDAdBlockURLIsAdRequest(NSURL *url) {
    if (url == nil) return NO;
    NSString *s = [url absoluteString];
    if (s.length == 0) return NO;
    // 激励广告请求（URL 含 reward/reward-video 等）由 adHasPlayOver 单独处理，网络层不拦，
    // 否则视频加载失败会弹“网络未连接”。
    if ([s rangeOfString:@"reward" options:NSCaseInsensitiveSearch].location != NSNotFound) return NO;
    return [s rangeOfString:kDDAdBlockAdURLPattern
                     options:NSRegularExpressionSearch].location != NSNotFound;
}

%hook NSURLSession
// 对齐落点：微信所有 CGI / HTTP 请求最终经 NSURLSession 的公开 dataTask 方法发出。
// 命中广告 URL 正则的请求替换为本地空 data: 请求——不联网、返回空数据。
- (id)dataTaskWithRequest:(NSURLRequest *)arg1 completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))arg2 {
    DDAdBlockConfig *cfg = [DDAdBlockConfig sharedConfig];
    if (ddActive() && (cfg.network || cfg.miniProgram)
        && !cfg.rewardedFastPass
        && DDAdBlockURLIsAdRequest([arg1 URL])) {
        NSURLRequest *dr = [NSURLRequest requestWithURL:[NSURL URLWithString:@"data:text/plain;charset=utf-8,"]];
        return %orig(dr, arg2);
    }
    return %orig;
}
- (id)dataTaskWithURL:(NSURL *)arg1 completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))arg2 {
    DDAdBlockConfig *cfg = [DDAdBlockConfig sharedConfig];
    if (ddActive() && (cfg.network || cfg.miniProgram)
        && !cfg.rewardedFastPass
        && DDAdBlockURLIsAdRequest(arg1)) {
        // 本方法第一个参数是 NSURL *，需替换为空 data: URL（非 NSURLRequest *）
        NSURL *du = [NSURL URLWithString:@"data:text/plain;charset=utf-8,"];
        return %orig(du, arg2);
    }
    return %orig;
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

// ========== 7. 激励广告快速过（精确对齐 WCR：adHasPlayOver + viewDidLoad）[WCR: enhancedAdBlockRewardedAdFastPassEnabled] ==========
%hook WCFinderRewardAdViewController
// 让系统认为激励视频已播放完毕，跳过倒计时/等待并触发奖励结算（WCR 同款核心：selrefs 中唯一 adHasPlayOver）
- (BOOL)adHasPlayOver {
    if (ddActive() && [DDAdBlockConfig sharedConfig].rewardedFastPass) return YES;
    return %orig;
}
// 不再空实现 viewDidLoad（VC 由导航 push 而非 present，空 viewDidLoad 会破坏 adHasPlayOver 传递链），
// 改为精准掐断倒计时定时器：视频还未拉起就被立即停掉，配合 adHasPlayOver→YES 形成“无界面、无声音、秒过”。
- (void)startAdCountdownTimer {
    if (ddActive() && [DDAdBlockConfig sharedConfig].rewardedFastPass) return;
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

@end

// ========== 插件注册 ==========
%ctor {
    @autoreleasepool {
        Class mgrClass = NSClassFromString(@"WCPluginsMgr");
        if (mgrClass) {
            id mgr = [mgrClass sharedInstance];
            if ([mgr respondsToSelector:@selector(registerControllerWithTitle:version:controller:)]) {
                [mgr registerControllerWithTitle:@"DD广告拦截"
                                         version:@"1.2.9"
                                      controller:@"DDAdBlockSettingsViewController"];
            }
        }
    }
}
