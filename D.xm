//
//  DDAdBlock.xm  v1.0.7
//  插件名: DD广告拦截
//  视频号段基于 8.0.56 公开头文件(WeChatHeaders 8.0.56)核对真实 selector 重写:
//    WCFinderComment          : advertisementInfo / commentAdImageUrl / promotionInfo (8.0.56 确认存在)
//    WCFinderDataItem        : adFlag (8.0.56 确认存在)
//    WCAdFinderInfo          : isValid (8.0.56 确认存在)
//    WCFinderCommentSectionViewModel : getFinderCommentWithIndex: / hasFinderCommentWithIndex:
//                                     / commentAtIndex: / numberOfComment / removeCommentAtIndex:
//    WCFinderCommentDetailViewModel  : allComments (NSMutableArray,可就地删除广告 comment)
//  已删除 8.0.56 中不存在的 selector: commentViewModels/rootComments/isAdComment/
//           WCFinderGetCommentListResponse/numberOfRowsInSection(WCFinderCommentSectionViewModel)
//
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#import <objc/runtime.h>

#pragma mark - 私有类前向声明 + 分类补充(解决编译期未声明/前向声明错误)
@class WCFinderComment, WCFinderDataItem, WCAdFinderInfo;
@class WCFinderCommentSectionViewModel, WCFinderCommentDetailViewModel;

@interface WCFinderComment ()
- (id)advertisementInfo;
- (id)commentAdImageUrl;
- (id)promotionInfo;
@end

@interface WCFinderDataItem ()
- (unsigned long long)adFlag;
@end

@interface WCAdFinderInfo ()
- (BOOL)isValid;
@end

@interface WCFinderCommentSectionViewModel ()
- (id)getFinderCommentWithIndex:(unsigned long long)index;
- (BOOL)hasFinderCommentWithIndex:(unsigned long long)index;
- (id)commentAtIndex:(unsigned long long)index;
- (unsigned long long)numberOfComment;
- (void)removeCommentAtIndex:(unsigned long long)index;
@end

@interface WCFinderCommentDetailViewModel ()
- (NSMutableArray *)allComments;
@end

#pragma mark - 配置类(8开关,默认全关,显式setter+synchronize,无宏)
static NSString * const kDDMaster=@"DDAdBlock_Master";
static NSString * const kDDMoments=@"DDAdBlock_Moments";
static NSString * const kDDBrand=@"DDAdBlock_Brand";
static NSString * const kDDFinder=@"DDAdBlock_Finder";
static NSString * const kDDLive=@"DDAdBlock_Live";
static NSString * const kDDMini=@"DDAdBlock_MiniProgram";
static NSString * const kDDSearch=@"DDAdBlock_Search";
static NSString * const kDDReward=@"DDAdBlock_RewardedAdFastPass";

@interface DDAdBlockConfig : NSObject
+ (instancetype)sharedConfig;
@property (assign,nonatomic) BOOL master,moments,brand,finder,live,miniProgram,search,rewardedFastPass;
@end

@implementation DDAdBlockConfig
+ (instancetype)sharedConfig{static DDAdBlockConfig*c;static dispatch_once_t t;dispatch_once(&t){c=[self new];};return c;}
- (instancetype)init{if(self=[super init]){NSUserDefaults*ud=[NSUserDefaults standardUserDefaults];
  if([ud objectForKey:kDDMaster]==nil)[ud setBool:NO forKey:kDDMaster];
  if([ud objectForKey:kDDMoments]==nil)[ud setBool:NO forKey:kDDMoments];
  if([ud objectForKey:kDDBrand]==nil)[ud setBool:NO forKey:kDDBrand];
  if([ud objectForKey:kDDFinder]==nil)[ud setBool:NO forKey:kDDFinder];
  if([ud objectForKey:kDDLive]==nil)[ud setBool:NO forKey:kDDLive];
  if([ud objectForKey:kDDMini]==nil)[ud setBool:NO forKey:kDDMini];
  if([ud objectForKey:kDDSearch]==nil)[ud setBool:NO forKey:kDDSearch];
  if([ud objectForKey:kDDReward]==nil)[ud setBool:NO forKey:kDDReward];[ud synchronize];
  _master=[ud boolForKey:kDDMaster];_moments=[ud boolForKey:kDDMoments];_brand=[ud boolForKey:kDDBrand];
  _finder=[ud boolForKey:kDDFinder];_live=[ud boolForKey:kDDLive];_miniProgram=[ud boolForKey:kDDMini];
  _search=[ud boolForKey:kDDSearch];_rewardedFastPass=[ud boolForKey:kDDReward];}return self;}
#define DDSET(name,key) -(void)set##name:(BOOL)v{_##name=v;[[NSUserDefaults standardUserDefaults]setBool:v forKey:key];[[NSUserDefaults standardUserDefaults]synchronize];}
DDSET(Master,kDDMaster) DDSET(Moments,kDDMoments) DDSET(Brand,kDDBrand) DDSET(Finder,kDDFinder)
DDSET(Live,kDDLive) DDSET(MiniProgram,kDDMini) DDSET(Search,kDDSearch) DDSET(RewardedFastPass,kDDReward)
@end
static BOOL ddActive(void){return [DDAdBlockConfig sharedConfig].master;}

#pragma mark - 工具函数(恢复D.txt已验证 WebView 拦截)
static NSString*DDMP(void){return @".iframe_ad_container,.comment-ad-container{display:none!important;height:0!important;min-height:0!important;margin:0!important;padding:0!important;overflow:hidden!important;}";}
static NSString*DDWA(void){return @"wx-ad,wx-ad-custom,.wx-ad,.wx-ad-custom{display:none!important;height:0!important;min-height:0!important;max-height:0!important;margin:0!important;padding:0!important;overflow:hidden!important;}";}
static NSArray*DDBlocklist(void){static NSArray*l;static dispatch_once_t o;dispatch_once(&o){l=@[@"wxa.wxs.qq.com/tmpl/px/",@"wxa.wxs.qq.com/tmpl/lite/",@"/cgi-bin/mmbiz-bin/ad",@"ad.weixin.qq.com",@"wxad",@"adunit-",@"_ad_",@"&adpos=",@"mp.weixin.qq.com/mp/getappmsgad"];};return l;}
static BOOL ddIsAd(NSString*u){if(!u||u.length==0)return NO;for(NSString*s in DDBlocklist())if([u containsString:s])return YES;return NO;}

// 判断一条 WCFinderComment 是否为广告(仅用 8.0.56 确认存在的 selector)
static BOOL ddFinderCommentIsAd(id comment){
  if(!comment) return NO;
  if([comment respondsToSelector:@selector(advertisementInfo)] && [comment advertisementInfo]) return YES;
  if([comment respondsToSelector:@selector(promotionInfo)] && [comment promotionInfo]) return YES;
  return NO;
}

#pragma mark - 1.朋友圈(D.txt已验证)
%hook WCAdvertiseDataHelper
- (void)saveAdPullCompareInfo:(id)a{ if(ddActive()&&[DDAdBlockConfig sharedConfig].moments)return;%orig;}
- (void)saveAdvertiseMsgXmlDatas{ if(ddActive()&&[DDAdBlockConfig sharedConfig].moments)return;%orig;}
- (void)addAdvertiseDataList:(id)a{ if(ddActive()&&[DDAdBlockConfig sharedConfig].moments)return;%orig;}
- (void)saveAdvertiseDatas{ if(ddActive()&&[DDAdBlockConfig sharedConfig].moments)return;%orig;}
- (void)tryLoadAdvertiseData{ if(ddActive()&&[DDAdBlockConfig sharedConfig].moments)return;%orig;}
- (BOOL)isAdPreviewExpired:(id)a{ if(ddActive()&&[DDAdBlockConfig sharedConfig].moments)return YES;return %orig;}
%end
%hook WCTimelineMgr
- (id)getAdvertiseDataByCurMinTime:(unsigned int)a MaxTime:(unsigned int)b checkDataValid:(BOOL)c{ if(ddActive()&&[DDAdBlockConfig sharedConfig].moments)return [NSMutableArray array];return %orig;}
- (id)getAdvertiseDataByCurMinTime:(unsigned int)a MaxTime:(unsigned int)b{ if(ddActive()&&[DDAdBlockConfig sharedConfig].moments)return [NSMutableArray array];return %orig;}
- (id)getTopAdvertiseDataByTopNumber:(unsigned int)a{ if(ddActive()&&[DDAdBlockConfig sharedConfig].moments)return [NSMutableArray array];return %orig;}
- (void)onAdPullWithAdDatas:(id)a{ if(ddActive()&&[DDAdBlockConfig sharedConfig].moments)return;%orig;}
- (void)tryToProcessWithNewAdList:(id)a{ if(ddActive()&&[DDAdBlockConfig sharedConfig].moments)return;%orig;}
%end

#pragma mark - 2.公众号(D.txt已验证)
%hook BrandTLExptConfig
- (BOOL)isExptNotShowAd{ if(ddActive()&&[DDAdBlockConfig sharedConfig].brand)return YES;return %orig;}
%end
%hook BrandTLCanvasCardMgr
- (BOOL)isAdCardOpen{ if(ddActive()&&[DDAdBlockConfig sharedConfig].brand)return NO;return %orig;}
- (BOOL)isAdRequestOpen{ if(ddActive()&&[DDAdBlockConfig sharedConfig].brand)return NO;return %orig;}
- (void)handleBizAdNotifyNewXml:(id)a{ if(ddActive()&&[DDAdBlockConfig sharedConfig].brand)return;%orig;}
%end
%hook BrandAdDataParser
+ (id)adDataItemForContent:(id)a{ if(ddActive()&&[DDAdBlockConfig sharedConfig].brand)return nil;return %orig;}
+ (id)adDataItemForMsgWrap:(id)a{ if(ddActive()&&[DDAdBlockConfig sharedConfig].brand)return nil;return %orig;}
+ (id)adInfoDicForContent:(id)a{ if(ddActive()&&[DDAdBlockConfig sharedConfig].brand)return nil;return %orig;}
+ (id)adInfoDicForMsgWrap:(id)a{ if(ddActive()&&[DDAdBlockConfig sharedConfig].brand)return nil;return %orig;}
%end
%hook MMWebViewController
- (BOOL)webView:(id)w shouldStartLoadWithRequest:(id)req navigationType:(long long)t isMainFrame:(BOOL)mf navigationAction:(id)na{
  if(ddActive()&&[DDAdBlockConfig sharedConfig].brand&&!mf){NSString*u=[[(NSURLRequest*)req URL]absoluteString];if(ddIsAd(u))return NO;}
  return %orig;}
- (void)webViewDidFinishLoad:(id)w navigation:(id)n{
  %orig;if(!(ddActive()&&[DDAdBlockConfig sharedConfig].brand))return;
  WKWebView*wv=nil;@try{wv=[(id)self valueForKey:@"webView"];}@catch(NSException*e){}if(![wv isKindOfClass:[WKWebView class]])return;
  NSString*js=[NSString stringWithFormat:@"(function(){try{var s=document.createElement('style');s.textContent='%@';(document.head||document.documentElement).appendChild(s);}catch(e){}})();",DDMP()];
  [wv evaluateJavaScript:js completionHandler:nil];}
%end

#pragma mark - 3.视频号广告拦截(8.0.56 verified selectors)
// 3.1 单条 Comment 数据层兜底(字段 neutralize,不删对象,防闪退)
%hook WCFinderComment
- (id)advertisementInfo{ if(ddActive()&&[DDAdBlockConfig sharedConfig].finder)return nil;return %orig;}
- (id)commentAdImageUrl{ if(ddActive()&&[DDAdBlockConfig sharedConfig].finder)return nil;return %orig;}
- (id)promotionInfo{ if(ddActive()&&[DDAdBlockConfig sharedConfig].finder)return nil;return %orig;}
%end

%hook WCFinderDataItem
- (unsigned long long)adFlag{ if(ddActive()&&[DDAdBlockConfig sharedConfig].finder)return 0;return %orig;}
%end

%hook WCAdFinderInfo
- (BOOL)isValid{ if(ddActive()&&[DDAdBlockConfig sharedConfig].finder)return NO;return %orig;}
%end

// 3.2 Section VM 层:广告 comment 在索引访问/存在性/计数三处同步过滤,避免越界闪退
%hook WCFinderCommentSectionViewModel
- (id)getFinderCommentWithIndex:(unsigned long long)index{
  id c=%orig; if(ddActive()&&[DDAdBlockConfig sharedConfig].finder && ddFinderCommentIsAd(c)) return nil;
  return c;
}
- (BOOL)hasFinderCommentWithIndex:(unsigned long long)index{
  BOOL has=%orig; if(!has) return NO;
  if(ddActive()&&[DDAdBlockConfig sharedConfig].finder){
    id c=[self getFinderCommentWithIndex:index]; if(ddFinderCommentIsAd(c)) return NO;
  } return has;
}
- (id)commentAtIndex:(unsigned long long)index{
  id c=%orig; if(ddActive()&&[DDAdBlockConfig sharedConfig].finder && ddFinderCommentIsAd(c)) return nil;
  return c;
}
- (unsigned long long)numberOfComment{
  unsigned long long n=%orig;
  if(ddActive()&&[DDAdBlockConfig sharedConfig].finder && n>0){
    unsigned long long ad=0; unsigned long long i=0;
    for(;i<n;i++){ id c=[self getFinderCommentWithIndex:i]; if(ddFinderCommentIsAd(c)) ad++; }
    if(ad>0 && n>ad) n-=ad; // 扣减广告 comment 数,防止 cellForRow 越界
  } return n;
}
%end

// 3.3 Detail VM 层:allComments 为 NSMutableArray,就地删除广告 comment,外部计数自动同步
%hook WCFinderCommentDetailViewModel
- (NSMutableArray *)allComments{
  NSMutableArray *arr=%orig;
  if(ddActive()&&[DDAdBlockConfig sharedConfig].finder && [arr isKindOfClass:[NSMutableArray class]] && arr.count>0){
    NSIndexSet *ads=[arr indexesOfObjectsPassingTest:^BOOL(id c,NSUInteger idx,BOOL*stop){
      return ddFinderCommentIsAd(c);
    }];
    if(ads.count>0) [arr removeObjectsAtIndexes:ads];
  } return arr;
}
%end

#pragma mark - 4.小程序(D.txt已验证)
%hook WAAppTaskSplashADConfig
- (void)handleShowSplashAdCalled:(BOOL)a{ if(ddActive()&&[DDAdBlockConfig sharedConfig].miniProgram)return;%orig;}
%end
%hook WAJSEventHandler_showSplashAd
- (void)handleJSEvent:(id)a{ if(ddActive()&&[DDAdBlockConfig sharedConfig].miniProgram)return;%orig;}
%end
%hook WAJSEventHandler_showSplashAdMenu
- (void)handleJSEvent:(id)a{ if(ddActive()&&[DDAdBlockConfig sharedConfig].miniProgram)return;%orig;}
%end
%hook WAJSEventHandler_adOperateWXData
- (void)handleJSEvent:(id)a{ if(ddActive()&&[DDAdBlockConfig sharedConfig].miniProgram)return;%orig;}
%end
%hook MagicAdCommonService
- (id)getAdInfoWithPosId:(id)a{ if(ddActive()&&[DDAdBlockConfig sharedConfig].miniProgram)return nil;return %orig;}
- (id)internalGetAdInfoFromCacheWithPosId:(id)a{ if(ddActive()&&[DDAdBlockConfig sharedConfig].miniProgram)return nil;return %orig;}
- (void)getAdInfoAsyncWithPosId:(id)a completion:(id)b{ if(ddActive()&&[DDAdBlockConfig sharedConfig].miniProgram)return;%orig;}
- (void)getAdInfoAsyncWithPosId:(id)a timeoutMs:(long long)b completion:(id)c{ if(ddActive()&&[DDAdBlockConfig sharedConfig].miniProgram)return;%orig;}
- (void)triggerUpdateAdWithPosId:(id)a pullType:(unsigned char)b{ if(ddActive()&&[DDAdBlockConfig sharedConfig].miniProgram)return;%orig;}
- (void)updateAdInfoByCGIInstantlyWithPosId:(id)a pullType:(unsigned char)b isDelayPull:(BOOL)c{ if(ddActive()&&[DDAdBlockConfig sharedConfig].miniProgram)return;%orig;}
%end
%hook MagicAdCGIMgr
+ (void)getAdsCGIWithPosIds:(id)a successBlock:(id)b failBlock:(id)c{ if(ddActive()&&[DDAdBlockConfig sharedConfig].miniProgram)return;%orig;}
%end
%hook MagicAdPushMgrService
- (void)handleAdMsg:(id)a{ if(ddActive()&&[DDAdBlockConfig sharedConfig].miniProgram)return;%orig;}
%end
%hook WCAdvertisePushService
- (void)handlePushMsg:(id)a{ if(ddActive()&&[DDAdBlockConfig sharedConfig].miniProgram)return;%orig;}
%end
%hook WAWebViewController
- (BOOL)webView:(id)w shouldStartLoadWithRequest:(id)req navigationType:(long long)t isMainFrame:(BOOL)mf navigationAction:(id)na{
  if(ddActive()&&[DDAdBlockConfig sharedConfig].miniProgram&&!mf){NSString*u=[[(NSURLRequest*)req URL]absoluteString];if(ddIsAd(u))return NO;}
  return %orig;}
- (void)webViewDidFinishLoad:(id)w navigation:(id)n{
  %orig;if(!(ddActive()&&[DDAdBlockConfig sharedConfig].miniProgram))return;
  id wv=nil;@try{wv=[(id)self valueForKey:@"webView"];}@catch(NSException*e){}if(![wv respondsToSelector:@selector(evaluateJavaScript:completionHandler:)])return;
  NSString*js=[NSString stringWithFormat:@"(function(){try{var s=document.createElement('style');s.textContent='%@';(document.head||document.documentElement).appendChild(s);}catch(e){}})();",DDWA()];
  [wv evaluateJavaScript:js completionHandler:nil];}
%end

#pragma mark - 5.直播(D.txt已验证)
%hook WCFinderAdCountdownBannerView
- (void)setupSubviews{ if(ddActive()&&[DDAdBlockConfig sharedConfig].live)return;%orig;}
- (void)startCountdown{ if(ddActive()&&[DDAdBlockConfig sharedConfig].live)return;%orig;}
- (void)updateUIWithTime:(long long)a{ if(ddActive()&&[DDAdBlockConfig sharedConfig].live)return;%orig;}
- (BOOL)adHasPlayOver{ if(ddActive()&&[DDAdBlockConfig sharedConfig].live)return YES;return %orig;}
%end
%hook WCFinderLiveHomePageViewController
- (void)onAdSectionView:(id)a selectElementVM:(id)b{ if(ddActive()&&[DDAdBlockConfig sharedConfig].live)return;%orig;}
%end

#pragma mark - 6.搜索
%hook WCAdSearchH5Info
- (BOOL)isValid{ if(ddActive()&&[DDAdBlockConfig sharedConfig].search)return NO;return %orig;}
+ (id)fromXML:(struct XmlReaderNode_t *)a{ if(ddActive()&&[DDAdBlockConfig sharedConfig].search)return nil;return %orig;}
%end

#pragma mark - 7.激励广告快速跳过
%hook WCFinderRewardAdViewController
- (void)viewDidAppear:(BOOL)a{ if(ddActive()&&[DDAdBlockConfig sharedConfig].rewardedFastPass){[(id)self dismissViewControllerAnimated:YES completion:nil];return;}%orig;}
%end

#pragma mark - 8.上报抑制
%hook WCAdvertiseStatMgr
- (id)getAdvertiseInfoForItem:(id)a{ if(ddActive())return nil;return %orig;}
- (void)logHeadImageH5:(id)a{ if(ddActive())return;%orig;}
- (void)logADBrandProfile:(id)a{ if(ddActive())return;%orig;}
- (void)logADFloatView:(id)a{ if(ddActive())return;%orig;}
- (void)logADPoiH5:(id)a{ if(ddActive())return;%orig;}
- (void)logADH5:(id)a withUserInfo:(id)b reportType:(unsigned long long)c{ if(ddActive())return;%orig;}
- (void)logADCommentLog:(id)a{ if(ddActive())return;%orig;}
- (void)logADBodyLog:(id)a{ if(ddActive())return;%orig;}
- (void)reportAllFeedsADLog{ if(ddActive())return;%orig;}
%end

#pragma mark - 设置页
@interface WCTableViewManager:NSObject
- (id)initWithFrame:(CGRect)f style:(NSInteger)s;@property(nonatomic,readonly)UITableView*tableView;
- (void)clearAllSection;-(void)addSection:(id)s;-(void)reloadTableView;@end
@interface WCTableViewSectionManager:NSObject
+ (id)sectionWithHeader:(NSString*)h;-(void)addCell:(id)c;@end
@interface WCTableViewCellManager:NSObject
+ (id)switchCellForSel:(SEL)s target:(id)t title:(id)ti on:(BOOL)o;@end
@interface DDAdBlockSettingsViewController:UIViewController
@property(nonatomic,strong)WCTableViewManager*tableViewManager;@end
@implementation DDAdBlockSettingsViewController
- (void)viewDidLoad{ [super viewDidLoad];self.title=@"DD广告拦截";self.view.backgroundColor=[UIColor systemBackgroundColor];
  Class mc=%c(WCTableViewManager);_tableViewManager=[[mc alloc]initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
  _tableViewManager.tableView.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
  _tableViewManager.tableView.contentInsetAdjustmentBehavior=UIScrollViewContentInsetAdjustmentAutomatic;
  [self.view addSubview:_tableViewManager.tableView];[self buildTable];}
- (void)buildTable{[_tableViewManager clearAllSection];Class sc=%c(WCTableViewSectionManager),cc=%c(WCTableViewCellManager);
  DDAdBlockConfig*cfg=[DDAdBlockConfig sharedConfig];
  WCTableViewSectionManager*sm=[sc sectionWithHeader:@"广告拦截场景"];
  [sm addCell:[cc switchCellForSel:@selector(onMaster:) target:self title:@"启用广告拦截" on:cfg.master]];
  [sm addCell:[cc switchCellForSel:@selector(onMoments:) target:self title:@"屏蔽朋友圈广告" on:cfg.moments]];
  [sm addCell:[cc switchCellForSel:@selector(onBrand:) target:self title:@"屏蔽公众号广告" on:cfg.brand]];
  [sm addCell:[cc switchCellForSel:@selector(onFinder:) target:self title:@"屏蔽视频号广告" on:cfg.finder]];
  [sm addCell:[cc switchCellForSel:@selector(onLive:) target:self title:@"屏蔽直播广告" on:cfg.live]];
  [sm addCell:[cc switchCellForSel:@selector(onSearch:) target:self title:@"屏蔽搜索广告" on:cfg.search]];
  [sm addCell:[cc switchCellForSel:@selector(onMini:) target:self title:@"屏蔽小程序广告" on:cfg.miniProgram]];
  [_tableViewManager addSection:sm];
  WCTableViewSectionManager*am=[sc sectionWithHeader:@"进阶拦截"];
  [am addCell:[cc switchCellForSel:@selector(onReward:) target:self title:@"激励广告快速跳过" on:cfg.rewardedFastPass]];
  [_tableViewManager addSection:am];[_tableViewManager reloadTableView];}
- (void)onMaster:(UISwitch*)s{[DDAdBlockConfig sharedConfig].master=s.isOn;[self buildTable];}
- (void)onMoments:(UISwitch*)s{[DDAdBlockConfig sharedConfig].moments=s.isOn;}
- (void)onBrand:(UISwitch*)s{[DDAdBlockConfig sharedConfig].brand=s.isOn;}
- (void)onFinder:(UISwitch*)s{[DDAdBlockConfig sharedConfig].finder=s.isOn;}
- (void)onLive:(UISwitch*)s{[DDAdBlockConfig sharedConfig].live=s.isOn;}
- (void)onSearch:(UISwitch*)s{[DDAdBlockConfig sharedConfig].search=s.isOn;}
- (void)onMini:(UISwitch*)s{[DDAdBlockConfig sharedConfig].miniProgram=s.isOn;}
- (void)onReward:(UISwitch*)s{[DDAdBlockConfig sharedConfig].rewardedFastPass=s.isOn;}
@end

%ctor{@autoreleasepool{Class m=NSClassFromString(@"WCPluginsMgr");if(m){id i=[m sharedInstance];
  if([i respondsToSelector:@selector(registerControllerWithTitle:version:controller:)])
    [i registerControllerWithTitle:@"DD广告拦截" version:@"1.0.7" controller:@"DDAdBlockSettingsViewController"];}}}
