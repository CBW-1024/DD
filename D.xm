//
//  DDAdBlock.xm
//  DD广告拦截 v1.0.0（带日志调试版，修复 iOS 13+ 弃用 API）
//
//  新增功能：
//  - 日志记录所有拦截动作（原生层、WebView URL、DOM 清理、Cell 隐藏）
//  - 设置界面增加“导出日志”和“清空日志”按钮
//  - 日志存储在 Documents/DDAdBlock.log，可分享或复制
//

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#import <objc/runtime.h>

// ============================================================================
//  日志管理器（线程安全，写入文件）
// ============================================================================

@interface DDAdBlockLogger : NSObject
+ (instancetype)sharedLogger;
- (void)log:(NSString *)message;
- (NSString *)logFilePath;
- (NSString *)allLogs;
- (void)clearLogs;
@end

@implementation DDAdBlockLogger {
    dispatch_queue_t _logQueue;
    NSFileHandle *_fileHandle;
    NSString *_filePath;
}

+ (instancetype)sharedLogger {
    static DDAdBlockLogger *logger = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        logger = [[DDAdBlockLogger alloc] init];
    });
    return logger;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _logQueue = dispatch_queue_create("com.dd.adblock.log", DISPATCH_QUEUE_SERIAL);
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *documents = [paths firstObject];
        _filePath = [documents stringByAppendingPathComponent:@"DDAdBlock.log"];
        // 如果文件不存在，创建空文件
        if (![[NSFileManager defaultManager] fileExistsAtPath:_filePath]) {
            [[NSData data] writeToFile:_filePath atomically:YES];
        }
        _fileHandle = [NSFileHandle fileHandleForWritingAtPath:_filePath];
        if (_fileHandle) {
            [_fileHandle seekToEndOfFile];
        } else {
            // 降级：直接写入
            [_filePath writeToFile:_filePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }
    }
    return self;
}

- (void)log:(NSString *)message {
    dispatch_async(_logQueue, ^{
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
        NSString *timestamp = [formatter stringFromDate:[NSDate date]];
        NSString *line = [NSString stringWithFormat:@"[%@] %@\n", timestamp, message];
        NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
        if (self->_fileHandle) {
            @try {
                [self->_fileHandle writeData:data];
            } @catch (NSException *e) {
                // 重新打开文件
                self->_fileHandle = [NSFileHandle fileHandleForWritingAtPath:self->_filePath];
                [self->_fileHandle seekToEndOfFile];
                [self->_fileHandle writeData:data];
            }
        } else {
            // 降级写入
            NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:self->_filePath];
            [fh seekToEndOfFile];
            [fh writeData:data];
            [fh closeFile];
        }
    });
}

- (NSString *)logFilePath {
    return _filePath;
}

- (NSString *)allLogs {
    __block NSString *content = nil;
    dispatch_sync(_logQueue, ^{
        content = [NSString stringWithContentsOfFile:self->_filePath encoding:NSUTF8StringEncoding error:nil];
    });
    return content ?: @"";
}

- (void)clearLogs {
    dispatch_async(_logQueue, ^{
        [[NSData data] writeToFile:self->_filePath atomically:YES];
        if (self->_fileHandle) {
            [self->_fileHandle closeFile];
            self->_fileHandle = [NSFileHandle fileHandleForWritingAtPath:self->_filePath];
            [self->_fileHandle seekToEndOfFile];
        }
    });
}

@end

// 便捷宏
#define DDLog(fmt, ...) [[DDAdBlockLogger sharedLogger] log:[NSString stringWithFormat:fmt, ##__VA_ARGS__]]

// ============================================================================
//  声明微信私有类（供设置界面及插件注册使用）
// ============================================================================

@interface WCTableViewManager : NSObject
- (UITableView *)getTableView;
- (void)clearAllSection;
- (void)addSection:(id)section;
- (void)reloadTableView;
- (instancetype)initWithFrame:(CGRect)frame style:(UITableViewStyle)style;
@end

@interface WCTableViewSectionManager : NSObject
+ (instancetype)defaultSection;
- (void)addCell:(id)cell;
@property (nonatomic, copy) NSString *headerTitle;
@property (nonatomic, copy) NSString *footerTitle;
@end

@interface WCTableViewCellManager : NSObject
+ (id)switchCellForSel:(SEL)sel target:(id)target title:(id)title on:(BOOL)on;
+ (id)normalCellForSel:(SEL)sel target:(id)target title:(id)title;
@end

@interface WCPluginsMgr : NSObject
+ (instancetype)sharedInstance;
- (void)registerControllerWithTitle:(NSString *)title version:(NSString *)version controller:(NSString *)controllerName;
@end

// ============================================================================
//  全局配置类（开关持久化）
// ============================================================================

static NSString * const kMaster           = @"DDAdBlock_Master";
static NSString * const kMoments          = @"DDAdBlock_Moments";
static NSString * const kBrand            = @"DDAdBlock_Brand";
static NSString * const kFinder           = @"DDAdBlock_Finder";
static NSString * const kLive             = @"DDAdBlock_Live";
static NSString * const kMiniProgram      = @"DDAdBlock_MiniProgram";
static NSString * const kSearch           = @"DDAdBlock_Search";
static NSString * const kRewardedFastPass = @"DDAdBlock_RewardedFastPass";

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
    BOOL _master;
    BOOL _moments;
    BOOL _brand;
    BOOL _finder;
    BOOL _live;
    BOOL _miniProgram;
    BOOL _search;
    BOOL _rewardedFastPass;
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
    if (self) {
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        if ([ud objectForKey:kMaster] == nil)           [ud setBool:NO forKey:kMaster];
        if ([ud objectForKey:kMoments] == nil)          [ud setBool:NO forKey:kMoments];
        if ([ud objectForKey:kBrand] == nil)            [ud setBool:NO forKey:kBrand];
        if ([ud objectForKey:kFinder] == nil)           [ud setBool:NO forKey:kFinder];
        if ([ud objectForKey:kLive] == nil)             [ud setBool:NO forKey:kLive];
        if ([ud objectForKey:kMiniProgram] == nil)      [ud setBool:NO forKey:kMiniProgram];
        if ([ud objectForKey:kSearch] == nil)           [ud setBool:NO forKey:kSearch];
        if ([ud objectForKey:kRewardedFastPass] == nil) [ud setBool:NO forKey:kRewardedFastPass];
        [ud synchronize];

        _master           = [ud boolForKey:kMaster];
        _moments          = [ud boolForKey:kMoments];
        _brand            = [ud boolForKey:kBrand];
        _finder           = [ud boolForKey:kFinder];
        _live             = [ud boolForKey:kLive];
        _miniProgram      = [ud boolForKey:kMiniProgram];
        _search           = [ud boolForKey:kSearch];
        _rewardedFastPass = [ud boolForKey:kRewardedFastPass];
    }
    return self;
}

- (void)setMaster:(BOOL)value {
    _master = value;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setBool:value forKey:kMaster];
    [ud synchronize];
}
- (void)setMoments:(BOOL)value {
    _moments = value;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setBool:value forKey:kMoments];
    [ud synchronize];
}
- (void)setBrand:(BOOL)value {
    _brand = value;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setBool:value forKey:kBrand];
    [ud synchronize];
}
- (void)setFinder:(BOOL)value {
    _finder = value;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setBool:value forKey:kFinder];
    [ud synchronize];
}
- (void)setLive:(BOOL)value {
    _live = value;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setBool:value forKey:kLive];
    [ud synchronize];
}
- (void)setMiniProgram:(BOOL)value {
    _miniProgram = value;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setBool:value forKey:kMiniProgram];
    [ud synchronize];
}
- (void)setSearch:(BOOL)value {
    _search = value;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setBool:value forKey:kSearch];
    [ud synchronize];
}
- (void)setRewardedFastPass:(BOOL)value {
    _rewardedFastPass = value;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setBool:value forKey:kRewardedFastPass];
    [ud synchronize];
}

@end

// ============================================================================
//  1. 朋友圈广告模块（带日志）
// ============================================================================

static inline BOOL momentsEnabled(void) {
    return [DDAdBlockConfig sharedConfig].master && [DDAdBlockConfig sharedConfig].moments;
}

%hook WCAdvertiseDataHelper
- (void)saveAdPullCompareInfo:(id)arg1 {
    if (momentsEnabled()) {
        DDLog(@"朋友圈广告拦截: saveAdPullCompareInfo 被阻止");
        return;
    }
    %orig;
}
- (void)saveAdvertiseMsgXmlDatas {
    if (momentsEnabled()) {
        DDLog(@"朋友圈广告拦截: saveAdvertiseMsgXmlDatas 被阻止");
        return;
    }
    %orig;
}
- (void)addAdvertiseDataList:(id)arg1 {
    if (momentsEnabled()) {
        DDLog(@"朋友圈广告拦截: addAdvertiseDataList 被阻止");
        return;
    }
    %orig;
}
- (void)saveAdvertiseDatas {
    if (momentsEnabled()) {
        DDLog(@"朋友圈广告拦截: saveAdvertiseDatas 被阻止");
        return;
    }
    %orig;
}
- (void)tryLoadAdvertiseData {
    if (momentsEnabled()) {
        DDLog(@"朋友圈广告拦截: tryLoadAdvertiseData 被阻止");
        return;
    }
    %orig;
}
- (BOOL)isAdPreviewExpired:(id)arg1 {
    if (momentsEnabled()) {
        DDLog(@"朋友圈广告拦截: isAdPreviewExpired 返回 YES (视为过期)");
        return YES;
    }
    return %orig;
}
%end

%hook WCTimelineMgr
- (id)getAdvertiseDataByCurMinTime:(unsigned int)arg1 MaxTime:(unsigned int)arg2 checkDataValid:(BOOL)arg3 {
    if (momentsEnabled()) {
        DDLog(@"朋友圈广告拦截: getAdvertiseData... 返回空数组");
        return [NSMutableArray array];
    }
    return %orig;
}
- (id)getAdvertiseDataByCurMinTime:(unsigned int)arg1 MaxTime:(unsigned int)arg2 {
    if (momentsEnabled()) {
        DDLog(@"朋友圈广告拦截: getAdvertiseData 返回空数组");
        return [NSMutableArray array];
    }
    return %orig;
}
- (id)getTopAdvertiseDataByTopNumber:(unsigned int)arg1 {
    if (momentsEnabled()) {
        DDLog(@"朋友圈广告拦截: getTopAdvertiseDataByTopNumber 返回空数组");
        return [NSMutableArray array];
    }
    return %orig;
}
- (void)onAdPullWithAdDatas:(id)arg1 {
    if (momentsEnabled()) {
        DDLog(@"朋友圈广告拦截: onAdPullWithAdDatas 被阻止");
        return;
    }
    %orig;
}
- (void)tryToProcessWithNewAdList:(id)arg1 {
    if (momentsEnabled()) {
        DDLog(@"朋友圈广告拦截: tryToProcessWithNewAdList 被阻止");
        return;
    }
    %orig;
}
%end

// ============================================================================
//  2. 公众号广告模块（带日志）
// ============================================================================

static inline BOOL brandEnabled(void) {
    return [DDAdBlockConfig sharedConfig].master && [DDAdBlockConfig sharedConfig].brand;
}

// 公众号 CSS/JS（同前，不加日志，但注入时会记录）
static NSString *DDAdBlockMPHideCSS(void) {
    return @".iframe_ad_container,.iframe_adv_ad_container,.comment-ad-container,"
           @"li.cidad_comment_constant_key,#cidad_comment_constant_key,"
           @".adv_keyword_search,.ad_control-tips"
           @"{display:none!important;height:0!important;min-height:0!important;"
           @"margin:0!important;padding:0!important;overflow:hidden!important;}";
}

static NSString *DDAdBlockMPHideParentCSS(void) {
    return @"div:has(> .iframe_ad_container),li:has(> .comment-ad-container)"
           @"{display:none!important;height:0!important;}";
}

static NSString *DDAdBlockInjectJS(void) {
    return [NSString stringWithFormat:
        @"(function(){"
        @"if(window.__dd_injected)return;"
        @"window.__dd_injected=true;"
        @"if(window.__dd_ob){window.__dd_ob.disconnect();delete window.__dd_ob;}"
        @"if(window.__dd_timer){clearTimeout(window.__dd_timer);delete window.__dd_timer;}"
        @"try{"
        @"var s=document.createElement('style');s.id='__dd_adblock';"
        @"s.textContent='%@'+'%@';"
        @"(document.head||document.documentElement).appendChild(s);"
        @"var sweep=function(){try{Array.prototype.forEach.call("
        @"document.querySelectorAll('.iframe_ad_container,.comment-ad-container'),"
        @"function(e){var p=e.parentElement,n=0;"
        @"while(p&&n<3){if(p.tagName==='LI'||(p.className&&/comment-ad|discuss_media/.test(p.className))){"
        @"p.style.setProperty('display','none','important');break;}p=p.parentElement;n++;}});}catch(e){}};"
        @"sweep();"
        @"if(window.MutationObserver){"
        @"var timer=null;"
        @"window.__dd_ob=new MutationObserver(function(){"
        @"if(timer)return;timer=setTimeout(function(){timer=null;sweep();},300);});"
        @"window.__dd_ob.observe(document.documentElement,{childList:true,subtree:true});"
        @"window.__dd_timer=timer;"
        @"}"
        @"}catch(e){}})();",
        DDAdBlockMPHideCSS(), DDAdBlockMPHideParentCSS()];
}

// URL 黑名单
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
        if ([url containsString:sub]) {
            DDLog(@"URL黑名单匹配: %@ 包含 %@", url, sub);
            return YES;
        }
    }
    return NO;
}

// 原生层
%hook BrandTLExptConfig
- (BOOL)isExptNotShowAd {
    if (brandEnabled()) {
        DDLog(@"公众号广告拦截: BrandTLExptConfig isExptNotShowAd 返回 YES");
        return YES;
    }
    return %orig;
}
%end

%hook BrandTLCanvasCardMgr
- (BOOL)isAdCardOpen {
    if (brandEnabled()) {
        DDLog(@"公众号广告拦截: BrandTLCanvasCardMgr isAdCardOpen 返回 NO");
        return NO;
    }
    return %orig;
}
- (BOOL)isAdRequestOpen {
    if (brandEnabled()) {
        DDLog(@"公众号广告拦截: BrandTLCanvasCardMgr isAdRequestOpen 返回 NO");
        return NO;
    }
    return %orig;
}
- (void)handleBizAdNotifyNewXml:(id)arg1 {
    if (brandEnabled()) {
        DDLog(@"公众号广告拦截: handleBizAdNotifyNewXml 被阻止");
        return;
    }
    %orig;
}
%end

%hook BrandAdDataParser
+ (id)adDataItemForContent:(id)arg1 {
    if (brandEnabled()) {
        DDLog(@"公众号广告拦截: BrandAdDataParser adDataItemForContent 返回 nil");
        return nil;
    }
    return %orig;
}
+ (id)adDataItemForMsgWrap:(id)arg1 {
    if (brandEnabled()) {
        DDLog(@"公众号广告拦截: BrandAdDataParser adDataItemForMsgWrap 返回 nil");
        return nil;
    }
    return %orig;
}
+ (id)adInfoDicForContent:(id)arg1 {
    if (brandEnabled()) {
        DDLog(@"公众号广告拦截: BrandAdDataParser adInfoDicForContent 返回 nil");
        return nil;
    }
    return %orig;
}
+ (id)adInfoDicForMsgWrap:(id)arg1 {
    if (brandEnabled()) {
        DDLog(@"公众号广告拦截: BrandAdDataParser adInfoDicForMsgWrap 返回 nil");
        return nil;
    }
    return %orig;
}
%end

%hook MMWebViewController
- (id)webViewUserScriptsForConfiguration {
    id scripts = %orig;
    if (!brandEnabled()) return scripts;
    DDLog(@"公众号广告: 注入 WKUserScript (DocumentStart)");
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
    if (brandEnabled() && !arg4) {
        NSString *u = [[(NSURLRequest *)arg2 URL] absoluteString];
        if ([u containsString:@"wxa.wxs.qq.com"] && [u containsString:@"/tmpl/px/"]) {
            DDLog(@"公众号广告: 拦截 iframe 广告 URL: %@", u);
            return NO;
        }
        if (ddURLIsAd(u)) {
            DDLog(@"公众号广告: 拦截广告 URL: %@", u);
            return NO;
        }
    }
    return %orig;
}
%end

// ============================================================================
//  3. 视频号广告模块（带日志）
// ============================================================================

static inline BOOL finderEnabled(void) {
    return [DDAdBlockConfig sharedConfig].master && [DDAdBlockConfig sharedConfig].finder;
}

static void ddViewSetHidden(id view, BOOL hidden) {
    if (!view) return;
    SEL sel = @selector(setHidden:);
    if (class_respondsToSelector([(id)view class], sel)) {
        void (*imp)(id, SEL, BOOL) = (void (*)(id, SEL, BOOL))[(id)view methodForSelector:sel];
        if (imp) imp((id)view, sel, hidden);
    }
}

%hook WCFinderComment
- (id)advertisementInfo {
    if (finderEnabled()) {
        DDLog(@"视频号广告: WCFinderComment advertisementInfo 返回 nil");
        return nil;
    }
    return %orig;
}
- (id)commentAdImageUrl {
    if (finderEnabled()) {
        DDLog(@"视频号广告: WCFinderComment commentAdImageUrl 返回 nil");
        return nil;
    }
    return %orig;
}
- (id)promotionInfo {
    if (finderEnabled()) {
        DDLog(@"视频号广告: WCFinderComment promotionInfo 返回 nil");
        return nil;
    }
    return %orig;
}
%end

%hook WCFinderDataItem
- (unsigned long long)adFlag {
    if (finderEnabled()) {
        DDLog(@"视频号广告: WCFinderDataItem adFlag 返回 0");
        return 0;
    }
    return %orig;
}
%end

%hook WCAdFinderInfo
- (BOOL)isValid {
    if (finderEnabled()) {
        DDLog(@"视频号广告: WCAdFinderInfo isValid 返回 NO");
        return NO;
    }
    return %orig;
}
%end

%hook WCFinderCommentAdTableViewCell
- (void)updateWithModel:(id)arg1 width:(double)arg2 {
    if (finderEnabled()) {
        DDLog(@"视频号广告: 隐藏评论区广告 Cell");
        %orig;
        ddViewSetHidden((id)self, YES);
        return;
    }
    %orig;
}
- (double)sectionHeightWith:(id)arg1 width:(double)arg2 halfScreenHeight:(double)arg3 {
    if (finderEnabled()) {
        DDLog(@"视频号广告: 评论区广告高度设为 0");
        return 0.0;
    }
    return %orig;
}
- (double)heightForMediaWithRatio:(double)arg1 maxHeightPercentage:(double)arg2 minArea:(double)arg3 {
    if (finderEnabled()) {
        DDLog(@"视频号广告: 评论区广告媒体高度设为 0");
        return 0.0;
    }
    return %orig;
}
- (void)updatePlayerViewWithCommentInfo:(id)arg1 videoInfo:(id)arg2 {
    if (finderEnabled()) {
        DDLog(@"视频号广告: 阻止评论区广告播放器更新");
        return;
    }
    %orig;
}
- (void)updateImageViewWithCommentImageInfo:(id)arg1 imgInfo:(id)arg2 {
    if (finderEnabled()) {
        DDLog(@"视频号广告: 阻止评论区广告图片更新");
        return;
    }
    %orig;
}
- (void)clickADContentActionWithArea:(NSInteger)arg1 {
    if (finderEnabled()) {
        DDLog(@"视频号广告: 阻止评论区广告点击");
        return;
    }
    %orig;
}
- (id)commentAdReportDictWithReportScene:(NSInteger)arg1 {
    if (finderEnabled()) {
        DDLog(@"视频号广告: 评论区广告上报返回 nil");
        return nil;
    }
    return %orig;
}
- (BOOL)canReportWithReportScene:(NSInteger)arg1 {
    if (finderEnabled()) {
        DDLog(@"视频号广告: 评论区广告上报返回 NO");
        return NO;
    }
    return %orig;
}
%end

%hook WCFinderCommentDetailViewController
- (void)checkCommentAdPlayerExposeStateIfNeeded {
    if (finderEnabled()) {
        DDLog(@"视频号广告: 阻止评论区广告曝光检查");
        return;
    }
    %orig;
}
- (void)reportCommentAd:(id)arg1 withReportScene:(NSInteger)arg2 {
    if (finderEnabled()) {
        DDLog(@"视频号广告: 阻止评论区广告上报");
        return;
    }
    %orig;
}
- (void)reportCommentAdIfNeededWithReportScene:(NSInteger)arg2 {
    if (finderEnabled()) {
        DDLog(@"视频号广告: 阻止评论区广告上报");
        return;
    }
    %orig;
}
- (void)_configADCellReportBehavior:(id)arg1 comment:(id)arg2 {
    if (finderEnabled()) {
        DDLog(@"视频号广告: 阻止配置广告上报行为");
        return;
    }
    %orig;
}
- (void)commentAdCell:(id)arg1 clickFeedbackButton:(id)arg2 atSection:(NSInteger)arg3 {
    if (finderEnabled()) {
        DDLog(@"视频号广告: 阻止评论区广告反馈按钮点击");
        return;
    }
    %orig;
}
- (void)commentAdCell:(id)arg1 longPressAtSection:(NSInteger)arg3 {
    if (finderEnabled()) {
        DDLog(@"视频号广告: 阻止评论区广告长按");
        return;
    }
    %orig;
}
%end

// 视频流广告
%hook WCFinderDataItem
- (BOOL)isHardAdFeed {
    if (finderEnabled()) {
        DDLog(@"视频号广告: isHardAdFeed 返回 NO");
        return NO;
    }
    return %orig;
}
- (BOOL)isHardAdLiveFeed {
    if (finderEnabled()) {
        DDLog(@"视频号广告: isHardAdLiveFeed 返回 NO");
        return NO;
    }
    return %orig;
}
- (BOOL)isFromAdsStream {
    if (finderEnabled()) {
        DDLog(@"视频号广告: isFromAdsStream 返回 NO");
        return NO;
    }
    return %orig;
}
- (void)setIsFromAdsStream:(BOOL)arg1 {
    if (finderEnabled()) {
        DDLog(@"视频号广告: setIsFromAdsStream 强制设为 NO");
        %orig(NO);
        return;
    }
    %orig;
}
- (id)jumpInfoContainer {
    if (finderEnabled()) {
        DDLog(@"视频号广告: jumpInfoContainer 返回 nil");
        return nil;
    }
    return %orig;
}
- (id)postJumpInfoContainer {
    if (finderEnabled()) {
        DDLog(@"视频号广告: postJumpInfoContainer 返回 nil");
        return nil;
    }
    return %orig;
}
- (id)adLiveCoverUrl {
    if (finderEnabled()) {
        DDLog(@"视频号广告: adLiveCoverUrl 返回 nil");
        return nil;
    }
    return %orig;
}
- (id)adsParams {
    if (finderEnabled()) {
        DDLog(@"视频号广告: adsParams 返回 nil");
        return nil;
    }
    return %orig;
}
%end

// ============================================================================
//  4. 直播广告模块（带日志）
// ============================================================================

static inline BOOL liveEnabled(void) {
    return [DDAdBlockConfig sharedConfig].master && [DDAdBlockConfig sharedConfig].live;
}

%hook WCFinderAdCountdownBannerView
- (void)setupSubviews {
    if (liveEnabled()) {
        DDLog(@"直播广告: setupSubviews 被阻止");
        return;
    }
    %orig;
}
- (void)startCountdown {
    if (liveEnabled()) {
        DDLog(@"直播广告: startCountdown 被阻止");
        return;
    }
    %orig;
}
- (void)updateUIWithTime:(long long)arg1 {
    if (liveEnabled()) {
        DDLog(@"直播广告: updateUIWithTime 被阻止");
        return;
    }
    %orig;
}
- (BOOL)adHasPlayOver {
    if (liveEnabled()) {
        DDLog(@"直播广告: adHasPlayOver 返回 YES");
        return YES;
    }
    return %orig;
}
%end

%hook WCFinderLiveHomePageViewController
- (void)onAdSectionView:(id)arg1 selectElementVM:(id)arg2 {
    if (liveEnabled()) {
        DDLog(@"直播广告: onAdSectionView 被阻止");
        return;
    }
    %orig;
}
%end

// ============================================================================
//  5. 搜索广告模块（带日志）
// ============================================================================

static inline BOOL searchEnabled(void) {
    return [DDAdBlockConfig sharedConfig].master && [DDAdBlockConfig sharedConfig].search;
}

%hook WCAdSearchH5Info
- (BOOL)isValid {
    if (searchEnabled()) {
        DDLog(@"搜索广告: WCAdSearchH5Info isValid 返回 NO");
        return NO;
    }
    return %orig;
}
+ (id)fromXML:(struct XmlReaderNode_t *)arg1 {
    if (searchEnabled()) {
        DDLog(@"搜索广告: WCAdSearchH5Info fromXML 返回 nil");
        return nil;
    }
    return %orig;
}
%end

// ============================================================================
//  6. 小程序广告模块（带日志）
// ============================================================================

static inline BOOL miniProgramEnabled(void) {
    return [DDAdBlockConfig sharedConfig].master && [DDAdBlockConfig sharedConfig].miniProgram;
}

static NSString *DDAdBlockMiniAppHideCSS(void) {
    return @"wx-ad,wx-ad-custom,ad,ad-custom,.wx-ad,.wx-ad-custom"
           @"{display:none!important;height:0!important;min-height:0!important;"
           @"max-height:0!important;margin:0!important;padding:0!important;"
           @"overflow:hidden!important;}";
}

static NSString *DDAdBlockMiniAppInjectJS(void) {
    return [NSString stringWithFormat:
        @"(function(){"
        @"if(window.__dd_injected_wa)return;"
        @"window.__dd_injected_wa=true;"
        @"if(window.__dd_ob_wa){window.__dd_ob_wa.disconnect();delete window.__dd_ob_wa;}"
        @"if(window.__dd_timer_wa){clearTimeout(window.__dd_timer_wa);delete window.__dd_timer_wa;}"
        @"try{"
        @"var s=document.createElement('style');s.id='__dd_adblock_wa';"
        @"s.textContent='%@';"
        @"(document.head||document.documentElement).appendChild(s);"
        @"var sweep=function(){try{Array.prototype.forEach.call("
        @"document.querySelectorAll('wx-ad,wx-ad-custom,.wx-ad,.wx-ad-custom'),"
        @"function(e){e.style.setProperty('display','none','important');"
        @"e.style.setProperty('height','0','important');"
        @"e.style.setProperty('max-height','0','important');});}catch(e){}};"
        @"sweep();"
        @"if(window.MutationObserver){"
        @"var timer=null;"
        @"window.__dd_ob_wa=new MutationObserver(function(){"
        @"if(timer)return;timer=setTimeout(function(){timer=null;sweep();},300);});"
        @"window.__dd_ob_wa.observe(document.documentElement,{childList:true,subtree:true});"
        @"window.__dd_timer_wa=timer;"
        @"}"
        @"}catch(e){}})();",
        DDAdBlockMiniAppHideCSS()];
}

%hook WAAppTaskSplashADConfig
- (void)handleShowSplashAdCalled:(BOOL)arg1 {
    if (miniProgramEnabled()) {
        DDLog(@"小程序广告: handleShowSplashAdCalled 被阻止");
        return;
    }
    %orig;
}
%end

%hook WAJSEventHandler_showSplashAd
- (void)handleJSEvent:(id)arg1 {
    if (miniProgramEnabled()) {
        DDLog(@"小程序广告: WAJSEventHandler_showSplashAd 被阻止");
        return;
    }
    %orig;
}
%end

%hook WAJSEventHandler_showSplashAdMenu
- (void)handleJSEvent:(id)arg1 {
    if (miniProgramEnabled()) {
        DDLog(@"小程序广告: WAJSEventHandler_showSplashAdMenu 被阻止");
        return;
    }
    %orig;
}
%end

%hook WAJSEventHandler_adOperateWXData
- (void)handleJSEvent:(id)arg1 {
    if (miniProgramEnabled()) {
        DDLog(@"小程序广告: WAJSEventHandler_adOperateWXData 被阻止");
        return;
    }
    %orig;
}
%end

%hook MagicAdCommonService
- (id)getAdInfoWithPosId:(id)arg1 {
    if (miniProgramEnabled()) {
        DDLog(@"小程序广告: MagicAdCommonService getAdInfoWithPosId 返回 nil");
        return nil;
    }
    return %orig;
}
- (id)internalGetAdInfoFromCacheWithPosId:(id)arg1 {
    if (miniProgramEnabled()) {
        DDLog(@"小程序广告: MagicAdCommonService internalGetAdInfoFromCacheWithPosId 返回 nil");
        return nil;
    }
    return %orig;
}
- (void)getAdInfoAsyncWithPosId:(id)arg1 completion:(id)arg2 {
    if (miniProgramEnabled()) {
        DDLog(@"小程序广告: MagicAdCommonService getAdInfoAsync 被阻止");
        return;
    }
    %orig;
}
- (void)getAdInfoAsyncWithPosId:(id)arg1 timeoutMs:(long long)arg2 completion:(id)arg3 {
    if (miniProgramEnabled()) {
        DDLog(@"小程序广告: MagicAdCommonService getAdInfoAsync(timeout) 被阻止");
        return;
    }
    %orig;
}
- (void)triggerUpdateAdWithPosId:(id)arg1 pullType:(unsigned char)arg2 {
    if (miniProgramEnabled()) {
        DDLog(@"小程序广告: MagicAdCommonService triggerUpdateAd 被阻止");
        return;
    }
    %orig;
}
- (void)updateAdInfoByCGIInstantlyWithPosId:(id)arg1 pullType:(unsigned char)arg2 isDelayPull:(BOOL)arg3 {
    if (miniProgramEnabled()) {
        DDLog(@"小程序广告: MagicAdCommonService updateAdInfoByCGI 被阻止");
        return;
    }
    %orig;
}
%end

%hook MagicAdCGIMgr
+ (void)getAdsCGIWithPosIds:(id)arg1 successBlock:(id)arg2 failBlock:(id)arg3 {
    if (miniProgramEnabled()) {
        DDLog(@"小程序广告: MagicAdCGIMgr getAdsCGI 被阻止");
        return;
    }
    %orig;
}
%end

%hook MagicAdPushMgrService
- (void)handleAdMsg:(id)arg1 {
    if (miniProgramEnabled()) {
        DDLog(@"小程序广告: MagicAdPushMgrService handleAdMsg 被阻止");
        return;
    }
    %orig;
}
%end

%hook WCAdvertisePushService
- (void)handlePushMsg:(id)arg1 {
    if (miniProgramEnabled()) {
        DDLog(@"小程序广告: WCAdvertisePushService handlePushMsg 被阻止");
        return;
    }
    %orig;
}
%end

%hook WAWebViewController
- (void)webViewDidFinishLoad:(id)arg1 navigation:(id)arg2 {
    %orig;
    if (!miniProgramEnabled()) return;
    DDLog(@"小程序广告: 在 webViewDidFinishLoad 注入 JS");
    id wv = nil;
    @try {
        wv = [(id)self valueForKey:@"webView"];
    } @catch (__unused NSException *e) {}
    if (![wv respondsToSelector:@selector(evaluateJavaScript:completionHandler:)]) return;
    [wv evaluateJavaScript:DDAdBlockMiniAppInjectJS() completionHandler:nil];
}

- (BOOL)webView:(id)arg1 shouldStartLoadWithRequest:(id)arg2 navigationType:(long long)arg3 isMainFrame:(BOOL)arg4 navigationAction:(id)arg5 {
    if (miniProgramEnabled() && !arg4) {
        NSString *u = [[(NSURLRequest *)arg2 URL] absoluteString];
        if (ddURLIsAd(u)) {
            DDLog(@"小程序广告: 拦截广告 URL: %@", u);
            return NO;
        }
    }
    return %orig;
}
%end

// ============================================================================
//  7. 激励广告快速跳过模块（带日志）
// ============================================================================

static inline BOOL rewardedEnabled(void) {
    return [DDAdBlockConfig sharedConfig].master && [DDAdBlockConfig sharedConfig].rewardedFastPass;
}

%hook WCFinderRewardAdViewController
- (void)viewDidAppear:(BOOL)arg1 {
    if (rewardedEnabled()) {
        DDLog(@"激励广告: 快速跳过 (dismiss)");
        [(id)self dismissViewControllerAnimated:YES completion:nil];
        return;
    }
    %orig;
}
%end

// ============================================================================
//  8. 广告上报抑制（带日志）
// ============================================================================

static inline BOOL reportEnabled(void) {
    return [DDAdBlockConfig sharedConfig].master;
}

%hook WCAdvertiseStatMgr
- (id)getAdvertiseInfoForItem:(id)arg1 {
    if (reportEnabled()) {
        DDLog(@"上报抑制: getAdvertiseInfoForItem 返回 nil");
        return nil;
    }
    return %orig;
}
- (void)logHeadImageH5:(id)arg1 {
    if (reportEnabled()) {
        DDLog(@"上报抑制: logHeadImageH5 被阻止");
        return;
    }
    %orig;
}
- (void)logADBrandProfile:(id)arg1 {
    if (reportEnabled()) {
        DDLog(@"上报抑制: logADBrandProfile 被阻止");
        return;
    }
    %orig;
}
- (void)logADFloatView:(id)arg1 {
    if (reportEnabled()) {
        DDLog(@"上报抑制: logADFloatView 被阻止");
        return;
    }
    %orig;
}
- (void)logADPoiH5:(id)arg1 {
    if (reportEnabled()) {
        DDLog(@"上报抑制: logADPoiH5 被阻止");
        return;
    }
    %orig;
}
- (void)logADH5:(id)arg1 withUserInfo:(id)arg2 reportType:(unsigned long long)arg3 {
    if (reportEnabled()) {
        DDLog(@"上报抑制: logADH5 被阻止");
        return;
    }
    %orig;
}
- (void)logADCommentLog:(id)arg1 {
    if (reportEnabled()) {
        DDLog(@"上报抑制: logADCommentLog 被阻止");
        return;
    }
    %orig;
}
- (void)logADBodyLog:(id)arg1 {
    if (reportEnabled()) {
        DDLog(@"上报抑制: logADBodyLog 被阻止");
        return;
    }
    %orig;
}
- (void)reportAllFeedsADLog {
    if (reportEnabled()) {
        DDLog(@"上报抑制: reportAllFeedsADLog 被阻止");
        return;
    }
    %orig;
}
%end

// ============================================================================
//  9. 设置界面（新增日志分组）
// ============================================================================

@interface DDAdBlockSettingsViewController : UIViewController
@property (nonatomic, strong) WCTableViewManager *tableViewManager;
@end

@implementation DDAdBlockSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"DD广告拦截";
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    Class mgrCls = NSClassFromString(@"WCTableViewManager");
    _tableViewManager = [[mgrCls alloc] initWithFrame:self.view.bounds
                                                style:UITableViewStyleInsetGrouped];
    UITableView *tableView = [_tableViewManager getTableView];
    tableView.frame = self.view.bounds;
    tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentAutomatic;
    [self.view addSubview:tableView];

    [self buildSections];
}

- (void)buildSections {
    Class sectionCls = NSClassFromString(@"WCTableViewSectionManager");
    Class cellCls = NSClassFromString(@"WCTableViewCellManager");
    DDAdBlockConfig *cfg = [DDAdBlockConfig sharedConfig];

    [_tableViewManager clearAllSection];

    // 广告拦截场景
    WCTableViewSectionManager *secMain = [sectionCls defaultSection];
    secMain.headerTitle = @"广告屏蔽开关";
    [secMain addCell:[self switchCellWithTitle:@"启用广告拦截" on:cfg.master action:@selector(onMasterSwitch:)]];
    [secMain addCell:[self switchCellWithTitle:@"屏蔽朋友圈广告" on:cfg.moments action:@selector(onMomentsSwitch:)]];
    [secMain addCell:[self switchCellWithTitle:@"屏蔽公众号广告" on:cfg.brand action:@selector(onBrandSwitch:)]];
    [secMain addCell:[self switchCellWithTitle:@"屏蔽视频号广告" on:cfg.finder action:@selector(onFinderSwitch:)]];
    [secMain addCell:[self switchCellWithTitle:@"屏蔽直播广告" on:cfg.live action:@selector(onLiveSwitch:)]];
    [secMain addCell:[self switchCellWithTitle:@"屏蔽搜索广告" on:cfg.search action:@selector(onSearchSwitch:)]];
    [secMain addCell:[self switchCellWithTitle:@"屏蔽小程序广告" on:cfg.miniProgram action:@selector(onMiniProgramSwitch:)]];
    [_tableViewManager addSection:secMain];

    // 进阶拦截
    WCTableViewSectionManager *secAdv = [sectionCls defaultSection];
    secAdv.headerTitle = @"进阶拦截";
    secAdv.footerTitle = @"开启后，激励广告将自动快速跳过（无需等待）";
    [secAdv addCell:[self switchCellWithTitle:@"激励广告快速跳过" on:cfg.rewardedFastPass action:@selector(onRewardedSwitch:)]];
    [_tableViewManager addSection:secAdv];

    // 日志管理
    WCTableViewSectionManager *secLog = [sectionCls defaultSection];
    secLog.headerTitle = @"日志管理";
    [secLog addCell:[cellCls normalCellForSel:@selector(exportLog) target:self title:@"导出日志"]];
    [secLog addCell:[cellCls normalCellForSel:@selector(clearLog) target:self title:@"清空日志"]];
    [_tableViewManager addSection:secLog];

    [_tableViewManager reloadTableView];
}

- (id)switchCellWithTitle:(NSString *)title on:(BOOL)on action:(SEL)action {
    Class cellCls = NSClassFromString(@"WCTableViewCellManager");
    return [cellCls switchCellForSel:action target:self title:title on:on];
}

#pragma mark - 开关回调
- (void)onMasterSwitch:(UISwitch *)s       { [DDAdBlockConfig sharedConfig].master = s.isOn; }
- (void)onMomentsSwitch:(UISwitch *)s      { [DDAdBlockConfig sharedConfig].moments = s.isOn; }
- (void)onBrandSwitch:(UISwitch *)s        { [DDAdBlockConfig sharedConfig].brand = s.isOn; }
- (void)onFinderSwitch:(UISwitch *)s       { [DDAdBlockConfig sharedConfig].finder = s.isOn; }
- (void)onLiveSwitch:(UISwitch *)s         { [DDAdBlockConfig sharedConfig].live = s.isOn; }
- (void)onSearchSwitch:(UISwitch *)s       { [DDAdBlockConfig sharedConfig].search = s.isOn; }
- (void)onMiniProgramSwitch:(UISwitch *)s  { [DDAdBlockConfig sharedConfig].miniProgram = s.isOn; }
- (void)onRewardedSwitch:(UISwitch *)s     { [DDAdBlockConfig sharedConfig].rewardedFastPass = s.isOn; }

#pragma mark - 日志操作
- (void)exportLog {
    NSString *logContent = [[DDAdBlockLogger sharedLogger] allLogs];
    if (logContent.length == 0) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"提示"
                                                                       message:@"日志为空"
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    // 保存到临时文件
    NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"DDAdBlock.log"];
    [logContent writeToFile:tempPath atomically:YES encoding:NSUTF8StringEncoding error:nil];

    // 分享
    NSURL *fileURL = [NSURL fileURLWithPath:tempPath];
    UIActivityViewController *activityVC = [[UIActivityViewController alloc] initWithActivityItems:@[fileURL] applicationActivities:nil];
    // 使用现代 API 检测 iPad
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        activityVC.popoverPresentationController.sourceView = self.view;
        activityVC.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 0, 0);
    }
    [self presentViewController:activityVC animated:YES completion:nil];
}

- (void)clearLog {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"确认清空"
                                                                   message:@"确定要清空所有日志吗？"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"清空" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        [[DDAdBlockLogger sharedLogger] clearLogs];
        // 提示
        UIAlertController *done = [UIAlertController alertControllerWithTitle:@"已完成"
                                                                      message:@"日志已清空"
                                                               preferredStyle:UIAlertControllerStyleAlert];
        [done addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:done animated:YES completion:nil];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

// ============================================================================
//  插件注册
// ============================================================================

%ctor {
    @autoreleasepool {
        DDLog(@"========== DD广告拦截 插件加载 ==========");
        Class mgrClass = NSClassFromString(@"WCPluginsMgr");
        if (mgrClass) {
            id mgr = [mgrClass sharedInstance];
            if ([mgr respondsToSelector:@selector(registerControllerWithTitle:version:controller:)]) {
                [mgr registerControllerWithTitle:@"DD广告拦截"
                                         version:@"1.0.0"
                                      controller:@"DDAdBlockSettingsViewController"];
                DDLog(@"插件注册成功");
            }
        }
    }
}