// DDAdBlock.xm v1.0.9-DStyle - 完全对齐D.txt，无任何声明
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// 开关直接读NSUserDefaults，和D.txt一样不搞Config类
static NSString * const kDDMaster  = @"DD_master";
static NSString * const kDDMoments = @"DD_moments";
static NSString * const kDDBrand   = @"DD_brand";
static NSString * const kDDFinder  = @"DD_finder";
static NSString * const kDDLive    = @"DD_live";
static NSString * const kDDMini    = @"DD_mini";
static NSString * const kDDSearch  = @"DD_search";
static NSString * const kDDReward  = @"DD_reward";

static BOOL ddActive(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kDDMaster];
}
static BOOL ddBool(NSString *key) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:key];
}

// MARK: - 视频号：完全D.txt风格，只重写返回id的方法，无任何声明
%hook WCFinderComment
- (id)advertisementInfo {
    if (ddActive() && ddBool(kDDFinder)) return nil;
    return %orig;
}
- (id)promotionInfo {
    if (ddActive() && ddBool(kDDFinder)) return nil;
    return %orig;
}
- (id)commentAdImageUrl {
    if (ddActive() && ddBool(kDDFinder)) return nil;
    return %orig;
}
%end

// MARK: - 以下全是D.txt原封不动的逻辑，未做任何修改
%hook WCAdvertiseDataHelper
- (void)saveAdPullCompareInfo:(id)arg1 {
    if (ddActive() && ddBool(kDDMoments)) return;
    %orig;
}
- (void)saveAdvertiseMsgXmlDatas {
    if (ddActive() && ddBool(kDDMoments)) return;
    %orig;
}
- (void)addAdvertiseDataList:(id)arg1 {
    if (ddActive() && ddBool(kDDMoments)) return;
    %orig;
}
- (void)saveAdvertiseDatas {
    if (ddActive() && ddBool(kDDMoments)) return;
    %orig;
}
- (void)tryLoadAdvertiseData {
    if (ddActive() && ddBool(kDDMoments)) return;
    %orig;
}
- (BOOL)isAdPreviewExpired:(id)arg1 {
    if (ddActive() && ddBool(kDDMoments)) return YES;
    return %orig;
}
%end

%hook WCTimelineMgr
- (id)getAdvertiseDataByCurMinTime:(unsigned int)arg1 MaxTime:(unsigned int)arg2 checkDataValid:(BOOL)arg3 {
    if (ddActive() && ddBool(kDDMoments)) return [NSMutableArray array];
    return %orig;
}
- (id)getAdvertiseDataByCurMinTime:(unsigned int)arg1 MaxTime:(unsigned int)arg2 {
    if (ddActive() && ddBool(kDDMoments)) return [NSMutableArray array];
    return %orig;
}
- (id)getTopAdvertiseDataByTopNumber:(unsigned int)arg1 {
    if (ddActive() && ddBool(kDDMoments)) return [NSMutableArray array];
    return %orig;
}
- (void)onAdPullWithAdDatas:(id)arg1 {
    if (ddActive() && ddBool(kDDMoments)) return;
    %orig;
}
- (void)tryToProcessWithNewAdList:(id)arg1 {
    if (ddActive() && ddBool(kDDMoments)) return;
    %orig;
}
%end

%hook BrandTLExptConfig
- (BOOL)isExptNotShowAd {
    if (ddActive() && ddBool(kDDBrand)) return YES;
    return %orig;
}
%end

%hook BrandTLCanvasCardMgr
- (BOOL)isAdCardOpen {
    if (ddActive() && ddBool(kDDBrand)) return NO;
    return %orig;
}
- (BOOL)isAdRequestOpen {
    if (ddActive() && ddBool(kDDBrand)) return NO;
    return %orig;
}
- (void)handleBizAdNotifyNewXml:(id)arg1 {
    if (ddActive() && ddBool(kDDBrand)) return;
    %orig;
}
%end

%hook BrandAdDataParser
+ (id)adDataItemForContent:(id)arg1 {
    if (ddActive() && ddBool(kDDBrand)) return nil;
    return %orig;
}
+ (id)adDataItemForMsgWrap:(id)arg1 {
    if (ddActive() && ddBool(kDDBrand)) return nil;
    return %orig;
}
+ (id)adInfoDicForContent:(id)arg1 {
    if (ddActive() && ddBool(kDDBrand)) return nil;
    return %orig;
}
+ (id)adInfoDicForMsgWrap:(id)arg1 {
    if (ddActive() && ddBool(kDDBrand)) return nil;
    return %orig;
}
%end

%hook WAAppTaskSplashADConfig
- (void)handleShowSplashAdCalled:(BOOL)arg1 {
    if (ddActive() && ddBool(kDDMini)) return;
    %orig;
}
%end

%hook WAJSEventHandler_showSplashAd
- (void)handleJSEvent:(id)arg1 {
    if (ddActive() && ddBool(kDDMini)) return;
    %orig;
}
%end

%hook WAJSEventHandler_showSplashAdMenu
- (void)handleJSEvent:(id)arg1 {
    if (ddActive() && ddBool(kDDMini)) return;
    %orig;
}
%end

%hook WAJSEventHandler_adOperateWXData
- (void)handleJSEvent:(id)arg1 {
    if (ddActive() && ddBool(kDDMini)) return;
    %orig;
}
%end

%hook MagicAdCommonService
- (id)getAdInfoWithPosId:(id)arg1 {
    if (ddActive() && ddBool(kDDMini)) return nil;
    return %orig;
}
- (id)internalGetAdInfoFromCacheWithPosId:(id)arg1 {
    if (ddActive() && ddBool(kDDMini)) return nil;
    return %orig;
}
- (void)getAdInfoAsyncWithPosId:(id)arg1 completion:(id)arg2 {
    if (ddActive() && ddBool(kDDMini)) return;
    %orig;
}
- (void)getAdInfoAsyncWithPosId:(id)arg1 timeoutMs:(long long)arg2 completion:(id)arg3 {
    if (ddActive() && ddBool(kDDMini)) return;
    %orig;
}
- (void)triggerUpdateAdWithPosId:(id)arg1 pullType:(unsigned char)arg2 {
    if (ddActive() && ddBool(kDDMini)) return;
    %orig;
}
- (void)updateAdInfoByCGIInstantlyWithPosId:(id)arg1 pullType:(unsigned char)arg2 isDelayPull:(BOOL)arg3 {
    if (ddActive() && ddBool(kDDMini)) return;
    %orig;
}
%end

%hook MagicAdCGIMgr
+ (void)getAdsCGIWithPosIds:(id)arg1 successBlock:(id)arg2 failBlock:(id)arg3 {
    if (ddActive() && ddBool(kDDMini)) return;
    %orig;
}
%end

%hook MagicAdPushMgrService
- (void)handleAdMsg:(id)arg1 {
    if (ddActive() && ddBool(kDDMini)) return;
    %orig;
}
%end

%hook WCAdvertisePushService
- (void)handlePushMsg:(id)arg1 {
    if (ddActive() && ddBool(kDDMini)) return;
    %orig;
}
%end

%hook WCFinderAdCountdownBannerView
- (void)setupSubviews {
    if (ddActive() && ddBool(kDDLive)) return;
    %orig;
}
- (void)startCountdown {
    if (ddActive() && ddBool(kDDLive)) return;
    %orig;
}
- (void)updateUIWithTime:(long long)arg1 {
    if (ddActive() && ddBool(kDDLive)) return;
    %orig;
}
- (BOOL)adHasPlayOver {
    if (ddActive() && ddBool(kDDLive)) return YES;
    return %orig;
}
%end

%hook WCAdSearchH5Info
- (BOOL)isValid {
    if (ddActive() && ddBool(kDDSearch)) return NO;
    return %orig;
}
+ (id)fromXML:(struct XmlReaderNode_t *)arg1 {
    if (ddActive() && ddBool(kDDSearch)) return nil;
    return %orig;
}
%end

%hook WCFinderRewardAdViewController
- (void)viewDidAppear:(BOOL)animated {
    if (ddActive() && ddBool(kDDReward)) {
        [self dismissViewControllerAnimated:YES completion:nil];
        return;
    }
    %orig;
}
%end

%hook WCAdvertiseStatMgr
- (id)getAdvertiseInfoForItem:(id)arg1 {
    if (ddActive()) return nil;
    return %orig;
}
- (void)logHeadImageH5:(id)arg1 { if (ddActive()) return; %orig; }
- (void)logADBrandProfile:(id)arg1 { if (ddActive()) return; %orig; }
- (void)logADFloatView:(id)arg1 { if (ddActive()) return; %orig; }
- (void)logADPoiH5:(id)arg1 { if (ddActive()) return; %orig; }
- (void)logADH5:(id)arg1 withUserInfo:(id)arg2 reportType:(unsigned long long)arg3 {
    if (ddActive()) return; %orig;
}
- (void)logADCommentLog:(id)arg1 { if (ddActive()) return; %orig; }
- (void)logADBodyLog:(id)arg1 { if (ddActive()) return; %orig; }
- (void)reportAllFeedsADLog { if (ddActive()) return; %orig; }
%end
