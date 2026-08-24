//
//  DD广告拦截 v1.6.2 — 微信广告拦截插件（单文件 Logos/Theos tweak）
//  10 个开关，默认全部开启（对齐 WCR「装即全拦」行为）；每个 Hook 经总开关 + 分区开关双重门控。
//  v1.6.2 严格按 WCR 反汇编逐字对齐：补齐 12 个「WCR 有、DD 缺失」的广告 hook（ObjectAdItem×3、WCAdXmlParser×4 实例方法、
//    WCAdSearchH5Info.isValid、WCAdvertiseStatMgr×3、WCFinderRouterHelper.pushFinderAdPage...），并将 WCAdXmlParser / WCAdvertiseStatMgr /
//    WCAdSearchH5Info.fromXML: 的门控统一对齐 WCR 的 MOMENTS(0xd64ebc)。WCFinderDataItem.isAd 与 WCFinderCommentDetailViewModel.
//    createCommentSection... 的拦截逻辑依赖 WCR 私有函数（0xd65e6c 增强判定 / 0xd663d8 参数注入），无法在不盲猜下字节级对齐，
//    强行 return NO/nil 会放广告或误伤，故保留 DD 现有等价 finder hook 覆盖，不在本版字节级复刻。
//  v1.6.1 完全对齐 WCR：在 v1.6.0 基础上补齐「WCR 有、DD 完全没 hook」的广告相关类缺口（共 26 类）：
//    组1(moments 0xd64ebc)：WCADBodyWrap/WCADCanvasInfo/WCADPageWrap/WCAdCanvasLoadParams/
//       WCAdDynamicCanvasPageInfo/WCAdDynamicCanvasServerData/ObjectAdContentH5/ObjectAdItem/AdPushMsgDBMgr
//    组2(finder 0xd64e9c)：FinderObjectAdInfo/MBJsEventOnFinderMediaAdPreload/
//       WCFinderCommentDetailViewModel.preloadCommentAdResource:/WCFinderCommentSectionViewModel.commentSectionViewModelWithRootComment:
//       （MBJsEventOnFinderMediaAdPreload 修正为完整 Swift 名 _TtC6WeChat31MBJsEventOnFinderMediaAdPreload）
//    组3(master 0xd64e8c)：_TtC6WeChat20MagicAdPublicService/_TtC6WeChat22MagicAdBrandServiceBiz/
//       _TtC6WeChat28MagicSclBrandAdFlutterPlugin
//    组4(moments 0xd64ebc)：WCCanvasDynamicDataLoader.handleAdCanvasInfoResponse:（广告 canvas 数据不加载）
//    组5(master 0xd64e8c)：BrandTLFlutterViewController(initWithExptConfig:/enableAd/setEnableAd:/
//       reportAdBrandCardOnClick/getMagicBrushFlutterPlugins)/FlutterBrandTLApiImplementation.
//       createMagicAdBrandServiceScene:error:/WCAdFormWebViewJSLogic.initWithWebView:pageInfo:componentId:qrExtInfo:
//    判定：以上均逐字节反汇编确认门控开关（0xd64ebc/0xd64e8c）与返回行为；WAJSEventHandler_adOperateWXData
//      （JS 桥状态上报，非广告拦截）与 UI/联系人/上传类（无广告开关）经核实非广告拦截 hook，不补。
//  v1.6.0 完全对齐 WCR（含网络层、JS 桥、moments 数据/上报/推送层），补齐此前反向验证暴露的缺口：
//    1) 朋友圈广告数据层：WCAdvertiseInfo 补 poiH5PageWrap(→nil)/previewExpiredTime(→0)；
//       WCAdvertiseDataHelper 补 m_advertiseList(→nil)/m_advertiseMsgXmlList(→nil)/m_bLoaded(→NO)/
//       IsAdvertiseDataValid:dataItem:(→NO)/isAdPreviewExpired:(→YES)（moments 开关 0xd64ebc 门控）。
//    2) 朋友圈广告上报层：WCAdvertiseStatMgr 补 logADH5:(单参)/logADDetail:dataItem:/
//       logSphereViewWithSphereReportInfo:dataItem:scene:/logSphereViewInDetailWithWrapInfo:dataItem:/
//       logSphereViewInTimeLineWithWrapInfo:dataItem:（→空实现 return）。
//    3) 朋友圈广告推送层：WCAdvertisePushService 补 OnGetNewXmlMsg:Type:MsgWrap:（→空实现）。
//    4) 广告画布解析：WCAdXmlParser 的 setAdCanvas* 系列与 WCAdvertiseStatMgr 归总对齐。
//    5) 搜索广告：WCAdSearchH5Info 补 adType(→0)。
//    6) JS 桥接：WebviewJSEventHandler_getAdIdInfo 补 handleJSEvent:HandlerFacade:ExtraData:（→空实现）。
//    7) 品牌广告服务：_TtC6WeChat19MagicAdBrandService 补齐 7 个服务生命周期/状态机方法（master 开关门控）。
//    8) 网络层：NSURLSession 补齐 dataTaskWithRequest: 与 uploadTaskWithRequest:fromData:completionHandler:，
//       与现有 completionHandler 版共用同一广告 URL 正则，三条网络路径统一拦截广告 CGI 请求。
//    所有新增方法均经 WCR 反汇编确认门控开关与返回值（开关开→返回空/0/NO/直接 return），逐字节对齐。
//  v1.5.9 重点复核三个区域并修复小程序试玩广告（Playable）对齐缺口（基于 WCR 最新版反汇编）：
//    1) 视频号评论区（WCFinderComment.advertisementInfo/commentAdImageUrl）与 WCR 已完全一致，无需改动。
//    2) 激励广告快速跳过（WCFinderRewardAdViewController.adHasPlayOver→YES）与 WCR 已完全一致，无需改动。
//    3) 小程序试玩广告（Playable）修复：
//       - 补回因 v1.5.8 提取脚本 bug 误删的 _TtC6WeChat20MagicPlayableService 整类
//         （WCR 实际 hook 它 4 个方法：startWithConfig:/onCanvasViewFirstFrameRendered:/
//          notifyMiniProgramPlayableStatusWithIsEnd:/onDestroy:）。
//       - 补 _TtC6WeChat23MagicNewPlayableService 缺失的 onMainScriptInjected:/onDestroy:。
//       - 补 _TtC6WeChat43WAJSEventHandler_predownloadPlayablePackage.handleJSEvent:。
//       - 补 _TtC6WeChat46WAJSEventHandler_insertMiniProgramPlayableView.handleJSEvent:。
//    经反汇编确认：WCR 的 Playable 体系为"状态机 + 调用原方法 + 发通知"（依赖其私有内部例程
//    0x7a754c/0x7a7608/0x7a81c4/0x7a7738 与全局标志 0x2342000+0xed8~0xee9，DD 无法 1:1 复刻），
//    故 DD 用与自身现有 Playable 一致的拦截哲学补全这些 hook 点（方法名精确对齐 WCR）。
//  v1.5.8 全量对齐 WCR 广告 hook（重新完整反汇编 WCR 全部 1843 处 hook、478 类，删除 DD 独有、
//  WCR 完全没有的 hook，确保 DD 的每个剩余 hook 都在 WCR 中存在）：
//    1) 经完整扫描确认：NSURLSession / WCTimelineMgr / WCFinderRewardAdViewController /
//       MagicPlayableService 等之前误以为"DD 独有"的类，WCR 实际都有对应 hook（分布在 0x3c0000
//       之外，之前窄区间扫描漏掉），全部保留。
//    2) 删除 DD 真·独有、WCR 完全没有的 19 个 hook 类：BSTLExptConfig、BrandTimelineMsgMgr、
//       BoxBrandTimelineMsgMgr（实验开关冗余类）、MagicAdCGIMgr、MagicAdCommonService、
//       MagicAdMiniProgramService（Magic 广告服务层）、WAJSEventHandler_openChannelsRewardedVideoAd、
//       WAJSEventHandler_showGameRewardsCapsuleBanner、updateMiniProgramPlayableView×2（JS 桥接）、
//       WAWebviewBottomBannerView、WAWebviewHighlightedBottomBannerView（小程序 banner UI）、
//       WCFinderAdBannerView、WCFinderAdPromotionButton、WCFinderCommentAdTableViewCell、
//       WCFinderFeedStickerAdViewController、WCFinderFeedInlineStickerAdView、
//       WCFinderInlineStickerAdGestureBlockingView、WCFinderLiveHomePageViewController（视频号 UI 渲染层）。
//    3) 删除同类下 DD 独有、WCR 没有的 25 个方法（NSURLSession.dataTaskWithURL:、
//       WCFinderDataItem.adFlag/isAdsLive、WCFinderComment.promotionInfo、
//       WCFinderRewardAdViewController.startAdCountdownTimer、WCTimelineMgr.getAdvertiseDataBy*、
//       WCFinderAdCountdownBannerView.setupSubviews/startCountdown/updateUIWithTime:、
//       WCAdvertiseStatMgr.logADBodyLog:/logADCommentLog:/reportAllFeedsADLog 等）。
//    4) 保留 v1.5.7 已验证的修正（exptShowOption 清 bit 1、BrandAdDataItem→nil、
//       WCAdvertiseInfo 4 方法、MagicAdPushMgrService.OnGetNewXmlMsg:Type:MsgWrap:），
//       这些均与 WCR 完全一致。
//    删除后经程序化校验：DD 剩余 39 类 82 方法，每一个都能在 WCR 全量清单中找到同类同方法（0 不匹配）。
//  v1.5.7 修 v1.5.6 残留的"公众号/朋友圈广告拦截不到位"（经重新反汇编最新版 WCR、逐字节复核）：
//    1) 【关键修正】exptShowOption/setExptShowOption: 位掩码清错位：
//       WCR 汇编清除 bit 1（`and w8,w8,#0xfffffffd` = ~0x02），DD 误清 bit 0（&~1U）。
//       已改 &~2U（BrandTLExptConfig + BSTLExptConfig 共 4 处），使"实验开关式广告抑制"
//       真正命中广告位。这是此前该模块"清了位却仍见广告"的根因。
//    2) 补齐 WCR 有、DD 漏 hook 的公众号广告内容类 BrandAdDataItem（content/dicAdInfo → nil，
//       imp 0x3C61C4/0x3C60FC 复核：开关开时置空指针）。
//    3) 补齐 WCR 有、DD 漏 hook 的朋友圈广告信息类 WCAdvertiseInfo 的 4 个方法：
//       adType/h5PageWrap → nil、adExpired → YES、setItem:value:forDynamic: → NO
//       （imp 0x3C9674/0x3C93AC/0x3C96CC/0x3C9534 复核，均受朋友圈开关门控）。
//    4) 补齐广告推送另一入口 MagicAdPushMgrService.OnGetNewXmlMsg:Type:MsgWrap: 空实现
//       （imp 0x3C62D8 复核：开关开时直接 ret 丢弃）。
//  v1.4.0 视频号评论广告 + 视频号贴纸广告 + 视频号激励秒过加强（精确对齐 WCR + 微信 7.6）：
//    1) 视频号评论广告 cell：WCFinderCommentAdTableViewCell.init 不返回 nil（避免 UITableView dequeue nil 闪退）。
//       真正的"广告评论去除"靠 v1.5.0 已有的 WCFinderComment.advertisementInfo / commentAdImageUrl / promotionInfo
//       数据层 neutralize，让广告评论在源头失活，不会再被路由到广告 cell。
//    2) 视频号贴纸广告：WCFinderFeedStickerAdViewController.initWithParam: → nil
//       + WCFinderFeedInlineStickerAdView.initWithFrame: → nil
//       + WCFinderInlineStickerAdGestureBlockingView.initWithFrame: → nil
//       覆盖视频号播放中右下角的"了解详情"贴纸广告及评论流广告容器。
//    3) 视频号激励视频秒过加强（v1.3.0 漏掉的根因）：
//       "30 秒后可获得奖励"按钮实际由 WCFinderAdPromotionButton 渲染（而非 WCFinderRewardAdViewController
//       自带倒计时）。setCountdown: / setRemainingSeconds: 强制设为 0，按钮立即进入可点击完成状态。
//       与 WCFinderRewardAdViewController.adHasPlayOver→YES + startAdCountdownTimer 切断 + WAJSEventHandler
//       _adOperateWXData 透传 fastpass + WAJSEventHandler_openChannelsRewardedVideoAd.onSuccess 协同。
//    4) 小程序 banner 加固：WAWebviewBottomBannerView 新增 layoutSubviews（frame=zero, hidden=YES）
//       + reloadData（return）双重兜底，确保即使 init 被复用场景也完全不渲染。
//  v1.5.5 回退 v1.5.3/v1.5.4 引入的 5 个 JS 桥 hook（误伤正常业务）：
//    1) WAJSEventHandler_showGameRewardsCapsuleBanner / openADCanvas / downloadAppInternal /
//       showRelatedGamesView / highlightBottomBanner 这 5 个 handleJSEvent: 拦截全部删除——
//       它们会同时拦掉合法的"看广告得奖励"/"App 下载"/"广告画布渲染"业务回调，
//       表现为"打开小程序请求数据失败"、"看广告按钮点击不跳转"等回归。
//    2) WCFinderCommentAdTableViewCell.layoutUI / heightForMediaWithRatio: 这两个原本想消除"评论空白占位"
//       的渲染层 hook 同样回退——它们把 cell 撑成 0 高度的空气行，空白反而更大。
//       正确做法是回到 v1.5.0 已有的 WCFinderComment 数据层 neutralize（已有 3 个属性）。
//    3) WCFinderRewardAdViewController.shouldAutorotate / supportedInterfaceOrientations、
//       BrandTLCanvasCardMgr.onServiceInit 这几个"凑数 hook"也回退，跟广告拦截无关。
//    4) 保留 WAJSEventHandler_showSplashAd / showSplashAdMenu 这 2 个 JS 桥 hook，
//       它们只针对"开屏广告展示"，不误伤业务回调。
//  v1.5.6 修 v1.5.5 残留的"网络连接失败"+"激励广告不秒过"：
//    1) 误把 WAJSEventHandler_adOperateWXData（无关业务回调类，与广告上报无关）当成广告数据上报拦截，
//       导致 v1.5.5 在 miniProgram 开关下"return;" 截断了所有小程序业务数据上报 → "网络连接失败"。
//       v1.5.6 彻底删除该 hook 整块；真正的"广告数据上报"由 v1.5.0 已有的 WebviewJSEventHandler_* 落点负责：
//       - WebviewJSEventHandler_adDataReport.handleJSEvent:HandlerFacade:ExtraData: → return
//         （WCR cstring 'WebviewJSEventHandler_adDataReport blocked'）
//       - WebviewJSEventHandler_getAdIdInfo.handleJSEvent:HandlerFacade:ExtraData: → return
//         + checkUrlValid → NO
//         （WCR cstring 'WebviewJSEventHandler_getAdIdInfo blocked'）
//       这两个 hook v1.5.0 已存在但仅受 brand 开关控制；v1.5.6 改为 brand+miniProgram+network 三开关并生效。
//    2) 加回 WAJSEventHandler_showGameRewardsCapsuleBanner.handleJSEvent: → return，
//       仅在 rewardedFastPass 开启时拦截（默认开启）——这是 v1.5.5 误删的"30秒后可获得奖励"按钮限时变可点入口。
//       关闭 rewardedFastPass 时完全放行，不影响"看广告得奖励"业务。

//    WCFinderCommentAdTableViewCell.initWithStyle:reuseIdentifier: 此前 return nil，UITableView 走注册类
//    dequeue 拿到 nil 会抛 NSInternalInconsistencyException 崩溃。改为 init 永不返回 nil，updateWithModel
//    时隐藏并跳过；并新增 %hook WCFinderComment 对齐 WCR 数据层拦截（advertisementInfo /
//    commentAdImageUrl 返回 nil），从源头让广告评论失去广告属性，不再走广告渲染。
//  v1.5.1 纯编译修复（CI 报错 “property 'frame'/'hidden' cannot be found in forward class object
//    'WAWebviewBottomBannerView'”）：WAWebviewBottomBannerView 仅前向声明，layoutSubviews 内
//    self.frame/self.hidden 属性点语法编译期无法解析；改为强转 (UIView *)self 后操作（其真实基类即 UIView）。
//  v1.5.0 对齐 WCR「默认全开 + 调用方法」：
//    1) 默认开关全部开启（master/moments/brand/finder/live/miniProgram/network/search/expt/rewardedFastPass）
//       —— 此前 DD 默认全关（仅 rewardedFastPass 默认开），与 WCR「装即全拦」行为相反，是实测仍见广告的根因。
//    2) 补齐 WCR 引用但 DD 漏 hook 的 5 个方法（经与 DD 现有实现逐对核验，其余均已被覆盖，此前 gap 分析多为误报）：
//       BrandAdDataParser +bizTypeForAdInfoDic:/+traceIdForAdInfoDic: -> 返回 nil（清空广告 bizType/traceId 追踪）
//       BrandTLFlutterViewController -reportAdBrandCardOnClick -> 不执行上报；-initWithExptConfig: -> 返回 nil
//       MagicPlayableService/-MagicNewPlayableService -onCanvasViewFirstFrameRendered: -> 拦截（试玩 canvas 不渲染）
//  v1.3.0 视频号激励视频秒过 + 小程序横幅广告视图拦截（精确对齐 WCR + 微信 7.6）：
//    1) 视频号激励视频（wx.openChannelsRewardedVideoAd）：
//       WAJSEventHandler_openChannelsRewardedVideoAd.handleJSEvent: 在 rewardedFastPass 开启时
//         立即触发 onSuccessWithFeedBackInfo:rewardedDuration:（强制 30s），让小程序立刻发奖；
//       onSuccessWithFeedBackInfo:rewardedDuration: 兜底强制 rewardDuration=30。
//       配合 v1.2.7 的 WCFinderRewardAdViewController.adHasPlayOver→YES + startAdCountdownTimer 切断
//       + WAJSEventHandler_openChannelsRewardedVideoAd.onSuccess 协同。
//    2) 小程序内横幅广告视图：
//       WAWebviewBottomBannerView.initWithFrame: → nil（不创建横幅）
//       WAWebviewHighlightedBottomBannerView.initWithFrame: → nil（不创建高亮横幅）
//       与已有 WCFinderAdBannerView 互补，覆盖到小程序 WebView 内 “广告” cell 渲染层。
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
        // 默认全部开启（对齐 WCR 默认全开行为，装即生效）
        if ([ud objectForKey:kDDAdBlockMasterKey]           == nil) [ud setBool:YES forKey:kDDAdBlockMasterKey];
        if ([ud objectForKey:kDDAdBlockMomentsKey]          == nil) [ud setBool:YES forKey:kDDAdBlockMomentsKey];
        if ([ud objectForKey:kDDAdBlockBrandKey]            == nil) [ud setBool:YES forKey:kDDAdBlockBrandKey];
        if ([ud objectForKey:kDDAdBlockFinderKey]           == nil) [ud setBool:YES forKey:kDDAdBlockFinderKey];
        if ([ud objectForKey:kDDAdBlockLiveKey]             == nil) [ud setBool:YES forKey:kDDAdBlockLiveKey];
        if ([ud objectForKey:kDDAdBlockMiniProgramKey]      == nil) [ud setBool:YES forKey:kDDAdBlockMiniProgramKey];
        if ([ud objectForKey:kDDAdBlockNetworkKey]          == nil) [ud setBool:YES forKey:kDDAdBlockNetworkKey];
        if ([ud objectForKey:kDDAdBlockSearchKey]           == nil) [ud setBool:YES forKey:kDDAdBlockSearchKey];
        if ([ud objectForKey:kDDAdBlockRewardedFastPassKey] == nil) [ud setBool:YES forKey:kDDAdBlockRewardedFastPassKey];
        if ([ud objectForKey:kDDAdBlockExptKey]             == nil) [ud setBool:YES forKey:kDDAdBlockExptKey];

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
// v1.6.0 补齐（对齐 WCR imp 0x3C8348，moments 开关 0xd64ebc 开 → `mov x8,#0` 置空）：
// 朋友圈广告数据列表 getter 置空，广告数据无处可读、不注入信息流。
- (id)m_advertiseList {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return nil;
    return %orig;
}
// v1.6.0 补齐（对齐 WCR imp 0x3C840C，moments 开关 0xd64ebc 开 → 置空）：
// 朋友圈广告 XML 消息列表 getter 置空。
- (id)m_advertiseMsgXmlList {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return nil;
    return %orig;
}
// v1.6.0 补齐（对齐 WCR imp 0x3C84D0，moments 开关 0xd64ebc 开 → `mov w0,#0` 置 NO）：
// 朋友圈广告数据"已加载"标志置 NO，强制认为数据未加载、不展示。
- (BOOL)m_bLoaded {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return NO;
    return %orig;
}
// v1.6.0 补齐（对齐 WCR imp 0x3C87E0，moments 开关 0xd64ebc 开 → `mov w0,#0` 置 NO）：
// 朋友圈广告数据有效性校验置 NO，广告数据被判为无效、不展示。
- (BOOL)IsAdvertiseDataValid:(id)arg1 dataItem:(id)arg2 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return NO;
    return %orig;
}
// v1.6.0 补齐（对齐 WCR imp 0x3C88DC，moments 开关 0xd64ebc 开 → `mov w0,#1` 置 YES）：
// 朋友圈广告预览过期判定置 YES，广告被判为已过期、不展示。
- (BOOL)isAdPreviewExpired:(id)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return YES;
    return %orig;
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
// v1.5.7 补充（WCR 反汇编复核，全部经 imp 验证、受朋友圈开关 0xd64ebc 门控）：
//   adType/h5PageWrap → nil（imp 0x3C9674/0x3C93AC 开关开时 `mov x8,#0` 置空指针）
//   adExpired → YES（imp 0x3C96CC 开关开时 `mov w0,#1`）
//   setItem:value:forDynamic: → NO（imp 0x3C9534 开关开时 `mov w0,#0`）
// 使朋友圈广告在“类型/落地页/过期/动态项”多维度被判为无效广告，从源头不展示。
%hook WCAdvertiseInfo
+ (id)dictionaryFromADDynamicInfo:(id)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return nil;
    return %orig;
}
- (id)adType {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return nil;
    return %orig;
}
- (id)h5PageWrap {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return nil;
    return %orig;
}
// v1.6.0 补齐（对齐 WCR imp 0x3C9470，moments 开关 0xd64ebc 开 → `mov x8,#0` 置空指针）：
// 朋友圈 POI 广告落地页数据置空，广告卡片无落地页、不展示。
- (id)poiH5PageWrap {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return nil;
    return %orig;
}
// v1.6.0 补齐（对齐 WCR imp 0x3C9728，moments 开关 0xd64ebc 开 → `mov x8,#0` 置 0）：
// 朋友圈广告预览过期时间置 0，广告判定为已过期、不展示。
- (long long)previewExpiredTime {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return 0;
    return %orig;
}
- (BOOL)adExpired {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return YES;
    return %orig;
}
- (BOOL)setItem:(id)arg1 value:(id)arg2 forDynamic:(id)arg3 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return NO;
    return %orig;
}
%end

// ========== 1.x 朋友圈广告·画布/数据对象（v1.6.1 补齐，moments 开关 0xd64ebc 门控，对齐 WCR）==========
// 这批是 WCR 反汇编确认的广告数据对象 hook：画布页/画布信息/加载参数/动态画布/广告项。
// 开关开时 getter 返回 nil/0/NO、init 空实现 → 广告画布数据不可读、广告不渲染、不展示。
%hook WCADBodyWrap
- (id)init {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return nil;
    return %orig;
}
%end
%hook WCADCanvasInfo
- (id)init {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return nil;
    return %orig;
}
%end
%hook WCADPageWrap
- (id)adID {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return nil;
    return %orig;
}
- (id)miniShopRequestId {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return nil;
    return %orig;
}
- (id)uxInfo {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return nil;
    return %orig;
}
- (int)adType {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return 0;
    return %orig;
}
%end
%hook WCAdCanvasLoadParams
- (id)cacheKey {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return nil;
    return %orig;
}
- (id)canvasId {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return nil;
    return %orig;
}
- (id)canvasDynamicInfo {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return nil;
    return %orig;
}
- (id)dynamicCanvasLibVersion {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return nil;
    return %orig;
}
%end
%hook WCAdDynamicCanvasPageInfo
- (id)fetchRealUxInfo {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return nil;
    return %orig;
}
- (id)fetchPageInfoExtraDic {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return nil;
    return %orig;
}
- (id)fetchPageInfoDic {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return nil;
    return %orig;
}
- (id)fetchLaunchString {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return nil;
    return %orig;
}
%end
%hook WCAdDynamicCanvasServerData
- (void)initialize {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return;
    %orig;
}
- (BOOL)isValid {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return NO;
    return %orig;
}
- (id)fromPBCodingBuffer:(id)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return nil;
    return %orig;
}
- (void)toPBCodingBuffer {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return;
    %orig;
}
%end
%hook ObjectAdContentH5
- (id)url {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return nil;
    return %orig;
}
%end
%hook ObjectAdItem
- (id)adDesc {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return nil;
    return %orig;
}
- (id)uxinfo {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return nil;
    return %orig;
}
// 以下 3 个 getter：WCR 均受 MOMENTS(0xd64ebc) 控制（imp 0x3CA204/0x3CA2C8/0x3CA38C），ON→置 nil（广告链接/小程序/卡片不暴露）
- (id)adH5 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return nil;
    return %orig;
}
- (id)adLeadLink {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return nil;
    return %orig;
}
- (id)adMiniApp {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return nil;
    return %orig;
}
%end
%hook AdPushMsgDBMgr
- (void)initDB {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return;
    %orig;
}
- (void)insertNewPushMsg:(id)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return;
    %orig;
}
%end
// v1.6.1 补齐（对齐 WCR imp 0x3C8B20，moments 开关 0xd64ebc 门控 → 阻断朋友圈广告画布数据加载）：
// 朋友圈动态广告的 canvas 数据加载器，moments 开 → 不加载广告 canvas 数据。
%hook WCCanvasDynamicDataLoader
- (void)handleAdCanvasInfoResponse:(id)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return;
    %orig;
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
// v1.5.7 修正（反汇编复核新版 WCR）：WCR 清除的是 bit 1（汇编 `and w8,w8,#0xfffffffd`
//   = 0xfffffffd，即 ~0x02，清除 bit 1），此前 DD 误清 bit 0（&~1U）导致“实验开关式广告
//   抑制”未能命中真正的广告位。现改为 &~2U（清 bit 1），与 WCR 逐字节一致。
// 与上方 4 个 isExptNotShow* 返回 YES 形成双重保险：即便广告判定走 exptShowOption 直读路径，
// 清位后同样判定“不展示广告”。
- (unsigned int)exptShowOption {
    unsigned int v = %orig;
    if (ddActive() && [DDAdBlockConfig sharedConfig].expt) return v & ~2U;
    return v;
}
- (void)setExptShowOption:(unsigned int)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].expt) { %orig(arg1 & ~2U); return; }
    %orig;
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
+ (id)bizTypeForAdInfoDic:(id)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].brand) return nil;
    return %orig;
}
+ (id)traceIdForAdInfoDic:(id)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].brand) return nil;
    return %orig;
}
%end

// 品牌广告数据项（WCR hook：BrandAdDataItem.content / dicAdInfo → 均返回 nil，经反汇编复核
//   imp=0x3C61C4 / 0x3C60FC，开关开启时 `stur xzr` 置空指针返回 nil）。
// 公众号品牌广告内容经该类承载，content/dicAdInfo 返回 nil → 广告内容为空、不构造不展示。
// v1.5.7 补充（此前 DD 未覆盖该类，是公众号广告拦截的缺口）。
%hook BrandAdDataItem
- (id)content {
    if (ddActive() && [DDAdBlockConfig sharedConfig].brand) return nil;
    return %orig;
}
- (id)dicAdInfo {
    if (ddActive() && [DDAdBlockConfig sharedConfig].brand) return nil;
    return %orig;
}
%end

// 广告 XML 解析/注入层（对齐 WCR：WCR 字符串精确引用 WCAdXmlParser 的
// ExtractRecommendAdInfo:ByAdMsgXml: / SetAdvertiseXml:ByAdXml: / SetAdvertiseInfo:ByAdInfo:）。
// 返回 NO 即判定广告解析失败，广告不会注入到信息流/卡片。
%hook WCAdXmlParser
// 以下 4 个类方法：WCR 均受 MOMENTS(0xd64ebc) 控制（imp 0x3C9D24/0x3C9E60/0x3C9FA4/0x3CA010），ON→return NO（广告 XML 不解析）
+ (BOOL)ExtractRecommendAdInfo:(id)arg1 ByAdMsgXml:(id)arg2 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return NO;
    return %orig;
}
+ (BOOL)SetAdvertiseXml:(id)arg1 ByAdXml:(id)arg2 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return NO;
    return %orig;
}
+ (BOOL)SetAdvertiseInfo:(id)arg1 ByAdInfoXml:(struct XmlReaderNode_t *)arg2 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return NO;
    return %orig;
}
+ (BOOL)SetAdvertiseInfo:(id)arg1 ByAdInfo:(id)arg2 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return NO;
    return %orig;
}
// 以下 4 个实例方法：WCR 均受 MOMENTS(0xd64ebc) 控制（imp 0x3C9D90/0x3C9E0C/0x3C9ECC/0x3C9F38），ON→拦截（void 跳过 / BOOL 返回 NO）
- (void)setAdCanvasPage:(id)arg1 byXmlNode:(id)arg2 withSizeType:(int)arg3 basicWidth:(double)arg4 basicRootFontSize:(double)arg5 widthRoundingType:(int)arg6 heightRoundingType:(int)arg7 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return;
    %orig;
}
- (void)setAdCanvasInfo:(id)arg1 byXmlNode:(id)arg2 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return;
    %orig;
}
- (BOOL)setSKAdItems:(id)arg1 byXmlNode:(id)arg2 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return NO;
    return %orig;
}
- (BOOL)setAdCanvasExtXml:(id)arg1 ByXmlNode:(id)arg2 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return NO;
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
    // 跨场景拦截：公众号/小程序广告 SDK 取 adId 时让 URL 校验失败，广告请求落地失败
    if (ddActive() && ([DDAdBlockConfig sharedConfig].brand ||
                       [DDAdBlockConfig sharedConfig].miniProgram ||
                       [DDAdBlockConfig sharedConfig].network)) return NO;
    return %orig;
}
// v1.6.0 补齐（对齐 WCR imp 0x3C4C30，moments 开关 0xd64ebc 开 → 空实现 return）：
// JS 桥"获取广告 ID 信息"处理器，空实现 → WebView 拿不到广告 ID，广告请求无法发起。
- (void)handleJSEvent:(id)arg1 HandlerFacade:(id)arg2 ExtraData:(id)arg3 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return;
    %orig;
}
%end

// WCR 精确落点（__cstring 'WebviewJSEventHandler_adDataReport blocked'）：
// 广告数据上报 JS 桥（公众号 + 小程序共用），空实现 → 广告上报被阻断，广告不统计不落地。
%hook WebviewJSEventHandler_adDataReport
- (void)handleJSEvent:(id)arg1 HandlerFacade:(id)arg2 ExtraData:(id)arg3 {
    if (ddActive() && ([DDAdBlockConfig sharedConfig].brand ||
                       [DDAdBlockConfig sharedConfig].miniProgram ||
                       [DDAdBlockConfig sharedConfig].network)) return;
    %orig;
}
%end

// WCR 精确落点（__cstring 'BrandTLFlutterViewController enableAd -> NO' / 'setEnableAd:%d -> force NO'）：
// 公众号 Flutter 页面广告开关，强制关闭 → 公众号 Flutter 内广告不展示。
// v1.6.1 修正：反汇编确认这 5 个方法均以 master 开关 0xd64e8c 门控（非 brand 分区开关），
// 故统一改用 ddActive()（master），并补齐 getMagicBrushFlutterPlugins（对齐 WCR imp 0x3C5604）。
%hook BrandTLFlutterViewController
- (BOOL)enableAd {
    if (ddActive()) return NO;
    return %orig;
}
- (void)setEnableAd:(BOOL)arg1 {
    // WCR 'setEnableAd:%d -> force NO'：无论传入什么都强制 NO，且不调用原实现（避免递归）。
    if (ddActive()) return;
    %orig;
}
- (void)reportAdBrandCardOnClick {
    if (ddActive()) return;
    %orig;
}
- (id)initWithExptConfig:(id)arg1 {
    if (ddActive()) return nil;
    return %orig;
}
- (id)getMagicBrushFlutterPlugins {
    if (ddActive()) return nil;
    return %orig;
}
%end

// 对齐 WCR（__objc_selrefs 精确引用 notifyAdServerInfoEventWithFeedsType:adInfo:）：
// 公众号品牌广告信息流通知，空实现 → 品牌广告信息不上报、不进入展示流程。
%hook _TtC6WeChat19MagicAdBrandService
- (void)notifyAdServerInfoEventWithFeedsType:(long long)arg1 adInfo:(id)arg2 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].brand) return;
    %orig;
}
// v1.6.0 补齐 7 个品牌广告服务方法（对齐 WCR，master 开关 0xd64e8c 门控）：
// 品牌广告（公众号广告的一种）的服务生命周期/状态机/卡片渲染全被阻断，广告不创建、不展示。
- (void)destroyBrandServiceBizWithScene:(id)arg1 {
    if (ddActive()) return;
    %orig;
}
- (void)createBrandServiceBizWithScene:(id)arg1 {
    if (ddActive()) return;
    %orig;
}
- (void)notifyFrameSetInfoWithMsgId:(id)arg1 frameSetName:(id)arg2 frameSetData:(id)arg3 {
    if (ddActive()) return;
    %orig;
}
- (void)notifyStateChangeWithEventName:(id)arg1 {
    if (ddActive()) return;
    %orig;
}
- (id)getDynamicCardType {
    if (ddActive()) return nil;
    return %orig;
}
- (BOOL)shouldPreLayoutWhenExpose {
    if (ddActive()) return NO;
    return %orig;
}
- (BOOL)isBrandTimelineOpen {
    if (ddActive()) return NO;
    return %orig;
}
%end

// ========== 品牌广告服务·补充（v1.6.1 补齐，master 开关 0xd64e8c 门控，对齐 WCR）==========
// 品牌广告（公众号广告的一种）的 Swift 服务/插件类：服务方法空实现 → 品牌广告 JS 运行时不启动。
%hook _TtC6WeChat20MagicAdPublicService
- (void)onJSException:(id)arg1 msg:(id)arg2 extra:(id)arg3 {
    if (ddActive()) return;
    %orig;
}
- (void)onDestroy:(id)arg1 {
    if (ddActive()) return;
    %orig;
}
- (void)onMainScriptInjected:(id)arg1 {
    if (ddActive()) return;
    %orig;
}
%end
%hook _TtC6WeChat22MagicAdBrandServiceBiz
- (void)onJSException:(id)arg1 msg:(id)arg2 extra:(id)arg3 {
    if (ddActive()) return;
    %orig;
}
- (void)onMainScriptInjected:(id)arg1 {
    if (ddActive()) return;
    %orig;
}
%end
%hook _TtC6WeChat28MagicSclBrandAdFlutterPlugin
- (void)onDetachedFromEngine:(id)arg1 {
    if (ddActive()) return;
    %orig;
}
%end

// ========== 品牌广告·Flutter 视图/服务（v1.6.1 补齐，master 开关 0xd64e8c 门控，对齐 WCR）==========
// 品牌广告（公众号广告的一种）的 Flutter 视图控制器/服务，master 开 → 视图不创建、广告不启用、
// 插件场景不创建。对齐 WCR：BrandTLFlutterViewController 5 方法（见上方 0x3C5284 等）、
// FlutterBrandTLApiImplementation.createMagicAdBrandServiceScene:error:(0x3C59AC) 均以 0xd64e8c 门控。
%hook FlutterBrandTLApiImplementation
- (id)createMagicAdBrandServiceScene:(id)arg1 error:(id *)arg2 {
    if (ddActive()) return nil;
    return %orig;
}
%end
// 公众号广告 WebView 表单 JS 逻辑，master 开 → 构造对象全参数置 nil（广告表单逻辑不初始化）。
// 对齐 WCR imp 0x3C4DC8：0xd67648（= 开关0xf17 || master 0xd64e8c）门控，master 恒开启则全拦。
%hook WCAdFormWebViewJSLogic
- (id)initWithWebView:(id)arg1 pageInfo:(id)arg2 componentId:(id)arg3 qrExtInfo:(id)arg4 {
    if (ddActive()) return nil;
    return %orig;
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
%end

// ========== 视频号广告·数据对象（v1.6.1 补齐，finder 开关 0xd64e9c 门控，对齐 WCR）==========
// 这批是 WCR 反汇编确认的视频号/信息流广告数据对象 hook。
// 开关开时 getter 返回 nil、预加载空实现 → 视频号广告内容不可读、不预加载、不展示。
%hook FinderObjectAdInfo
- (id)adDesc {
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return nil;
    return %orig;
}
- (id)adH5 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return nil;
    return %orig;
}
- (id)adLeadLink {
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return nil;
    return %orig;
}
- (id)adMiniApp {
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return nil;
    return %orig;
}
- (id)adItems {
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return nil;
    return %orig;
}
%end
%hook _TtC6WeChat31MBJsEventOnFinderMediaAdPreload
- (void)startPreloadAdMedia {
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return;
    %orig;
}
%end
%hook WCFinderCommentDetailViewModel
- (void)preloadCommentAdResource:(id)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return;
    %orig;
}
%end

// ========== 视频号广告页跳转拦截（精确对齐 WCR：FINDER 开关 0xd64e9c 控制 pushFinderAdPageViewController...）[WCR imp 0x3C7760] ==========
%hook WCFinderRouterHelper
// WCR 受 FINDER(0xd64e9c) 控制，ON→不 push 广告页（拦截视频号广告跳转）
- (void)pushFinderAdPageViewControllerWithEncrytedObjectidTid:(id)arg1 nonceId:(id)arg2 currentNavController:(id)arg3 enterScene:(int)arg4 customParam:(id)arg5 reportModel:(id)arg6 cardType:(int)arg7 requestScene:(int)arg8 functionalParams:(id)arg9 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return;
    %orig;
}
%end

%hook WCFinderCommentSectionViewModel
- (id)commentSectionViewModelWithRootComment:(id)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return nil;
    return %orig;
}
%end

%hook WCAdFinderInfo
- (BOOL)isValid {
    if (ddActive() && [DDAdBlockConfig sharedConfig].finder) return NO;
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
//      - WebviewJSEventHandler_adDataReport.handleJSEvent:HandlerFacade:ExtraData: → return
//        （'WebviewJSEventHandler_adDataReport blocked'）
//      - WebviewJSEventHandler_getAdIdInfo.checkUrlValid → NO + handleJSEvent: 三参 → return
//        （'WebviewJSEventHandler_getAdIdInfo blocked'）
//   2) 横幅/插屏广告"数据拉取层"（实测确认的真实数据入口）：
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

// 试玩广告（PlayableAd / “试玩 19 秒获得奖励”）秒过（精确对齐 WCR：
// __cstring 描述串 'MagicPlayableService.startWithConfig' / 'MagicNewPlayableService.startWithConfig'
// + __objc_selrefs 'notifyMiniProgramPlayableStatusWithIsEnd:' / 'isPlayable'）。
// 启动后立即 notifyMiniProgramPlayableStatusWithIsEnd:YES，让小程序运行时认为试玩已结束并立刻发奖，
// 不再等待 19 秒试玩。notifyMiniProgramPlayableStatusWithIsEnd: 兜底强制 YES，应对 startWithConfig 漏触发场景。
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
- (void)onCanvasViewFirstFrameRendered:(unsigned int)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return;
    %orig;
}
- (void)onMainScriptInjected:(id)arg1 {
    // WCR（imp 0x7A6DFC）：标记主脚本已注入 + 调原方法。对齐为"正常放行"（试玩主流程不阻断）。
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) { %orig; return; }
    %orig;
}
- (void)onDestroy:(id)arg1 {
    // WCR（imp 0x7A6F6C）：清试玩状态标志 + 调原方法。对齐为"正常销毁"（调原方法即可）。
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) { %orig; return; }
    %orig;
}
%end

// 补回 _TtC6WeChat20MagicPlayableService 整类（v1.5.8 因提取脚本 bug 误删）。
// 经 WCR 反汇编确认（注册函数 0x7A6814 objc_getClass('_TtC6WeChat20MagicPlayableService') +
// selref 0x2189480/0x2189488/0x2189490/0x21849a8），WCR 实际 hook 该类 4 个方法：
//   startWithConfig:(imp 0x7A6FCC) / onCanvasViewFirstFrameRendered:(0x7A7084) /
//   notifyMiniProgramPlayableStatusWithIsEnd:(0x7A710C) / onDestroy:(0x7A7164)。
// 与 23 类 MagicNewPlayableService 为同族试玩服务，逻辑一致（仅内部全局偏移不同）。
// 实现对齐 23 类的拦截哲学（试玩秒过 + 兜底强制发奖 + 首帧不渲染）。
%hook _TtC6WeChat20MagicPlayableService
- (void)startWithConfig:(id)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) {
        %orig(arg1);
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
- (void)onCanvasViewFirstFrameRendered:(unsigned int)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return;
    %orig;
}
- (void)onDestroy:(id)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) { %orig; return; }
    %orig;
}
%end

// 补 _TtC6WeChat43WAJSEventHandler_predownloadPlayablePackage.handleJSEvent:
// WCR 反汇编确认（注册函数 0x7A66E8 objc_getClass + selref 0x21844d8'handleJSEvent:'，imp 0x7A6C2C）：
// 预下载试玩包 JS 桥。WCR 为"记录 + 调原方法"，DD 对齐为拦截丢弃（不预下载试玩资源 → 无试玩广告）。
%hook _TtC6WeChat43WAJSEventHandler_predownloadPlayablePackage
- (void)handleJSEvent:(id)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) return;
    %orig;
}
%end

// 补 _TtC6WeChat46WAJSEventHandler_insertMiniProgramPlayableView.handleJSEvent:
// WCR 反汇编确认（注册函数 0x7A665C objc_getClass + selref 0x21844d8'handleJSEvent:'，imp 0x7A6B44）：
// 插入试玩视图 JS 桥。DD 对齐为拦截丢弃（不插入试玩视图 → 无试玩广告界面）。
%hook _TtC6WeChat46WAJSEventHandler_insertMiniProgramPlayableView
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
// v1.5.7 补充（WCR 反汇编复核，imp=0x3C62D8，开关开启时直接 ret 空实现丢弃）：
// 广告推送消息的另一个下发入口 OnGetNewXmlMsg:Type:MsgWrap:（新 XML 消息 + 类型 + 消息封装）。
// 与 handleAdMsg: 互补，堵住广告推送的另一条入池通道。
- (void)OnGetNewXmlMsg:(id)arg1 Type:(id)arg2 MsgWrap:(id)arg3 {
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
// v1.6.0 补齐（对齐 WCR imp 0x3C8A3C，moments 开关 0xd64ebc 开 → 空实现 return）：
// 朋友圈广告推送服务收到新 XML 消息时直接丢弃，广告不进入展示链路。
- (void)OnGetNewXmlMsg:(id)arg1 Type:(id)arg2 MsgWrap:(id)arg3 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return;
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
// v1.6.0 补齐（对齐 WCR dataTaskWithRequest: 落点）：无 completionHandler 版，同样拦截广告请求。
- (id)dataTaskWithRequest:(NSURLRequest *)arg1 {
    DDAdBlockConfig *cfg = [DDAdBlockConfig sharedConfig];
    if (ddActive() && (cfg.network || cfg.miniProgram)
        && !cfg.rewardedFastPass
        && DDAdBlockURLIsAdRequest([arg1 URL])) {
        NSURLRequest *dr = [NSURLRequest requestWithURL:[NSURL URLWithString:@"data:text/plain;charset=utf-8,"]];
        return %orig(dr);
    }
    return %orig;
}
// v1.6.0 补齐（对齐 WCR uploadTaskWithRequest:fromData:completionHandler: 落点）：上传型广告请求同样拦截。
- (id)uploadTaskWithRequest:(NSURLRequest *)arg1 fromData:(NSData *)arg2 completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))arg3 {
    DDAdBlockConfig *cfg = [DDAdBlockConfig sharedConfig];
    if (ddActive() && (cfg.network || cfg.miniProgram)
        && !cfg.rewardedFastPass
        && DDAdBlockURLIsAdRequest([arg1 URL])) {
        NSURLRequest *dr = [NSURLRequest requestWithURL:[NSURL URLWithString:@"data:text/plain;charset=utf-8,"]];
        return %orig(dr, arg2, arg3);
    }
    return %orig;
}
%end

// 小程序 WebView 内广告（wx-ad 组件）统一交由原生层开屏拦截 + MagicAd 消息拦截处理，
// 不再注入 JS（避免误伤正常请求、display:none 不停音频、MutationObserver 卡顿）。
// 对齐 WCR：WCR 小程序去广告走原生层，无 WebView JS 注入。

// ========== 5. 直播广告（Hook: WCFinderLiveHomePageViewController + WCFinderAdCountdownBannerView）[WCR: enhancedAdBlockLiveEnabled] ==========
%hook WCFinderAdCountdownBannerView
- (BOOL)adHasPlayOver {
    if (ddActive() && [DDAdBlockConfig sharedConfig].live) return YES;
    return %orig;
}
// v1.6.0 补齐（对齐 WCR imp 0x7A71C4，Playable 区开关门控，DD 对应 miniProgram 开关）：
// 广告倒计时横幅初始化时若倒计时 >1 秒则强制设为 1 秒，配合 adHasPlayOver→YES 实现广告秒过。
- (id)initWithFrame:(CGRect)arg1 countdownNum:(long long)arg2 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].miniProgram) {
        if (arg2 > 1) return %orig(arg1, 1);
    }
    return %orig;
}
%end


// 直播广告：WCR 未 hook MMLiveAdsParams 类；WCFinderDataItem 的 adFlag/isAdsLive 为 DD 独有、
// 已在对齐 WCR 时删除。直播广告去重交由 WCR 同款 FinderObjectAdInfo / WCFinderDataItem.isAd 数据层覆盖。

// ========== 6. 搜索广告（Hook: WCAdSearchH5Info）[WCR: enhancedAdBlockSearchEnabled] ==========
%hook WCAdSearchH5Info
// WCR 受 MOMENTS(0xd64ebc) 控制（imp 0x3C9CC0），ON→return nil（搜索广告 XML 不解析）
+ (id)fromXML:(struct XmlReaderNode_t *)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return nil;
    return %orig;
}
// WCR 受 MOMENTS(0xd64ebc) 控制（imp 0x3C9C64），ON→`mov w0,#0` 返回 0：搜索广告类型置 0，不展示
- (BOOL)isValid {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return NO;
    return %orig;
}
// v1.6.0 补齐：搜索广告类型置 0（与 WCR isValid 冗余双保险，保留无害）
- (int)adType {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return 0;
    return %orig;
}
%end

// ========== 7. 激励广告快速过（精确对齐 WCR：adHasPlayOver 已播完判定）[WCR: enhancedAdBlockRewardedAdFastPassEnabled] ==========
%hook WCFinderRewardAdViewController
// 让系统认为激励视频已播放完毕，跳过倒计时/等待并触发奖励结算（WCR 同款核心：selrefs 中唯一 adHasPlayOver）
- (BOOL)adHasPlayOver {
    if (ddActive() && [DDAdBlockConfig sharedConfig].rewardedFastPass) return YES;
    return %orig;
}
// 精准掐断倒计时定时器：视频还未拉起就被立即停掉，配合 adHasPlayOver→YES 形成"无界面、无声音、秒过"。
%end





// ========== 9. 广告曝光上报抑制（Hook: WCAdvertiseStatMgr，归总开关） ==========
%hook WCAdvertiseStatMgr
// WCR 全部 18 个方法均受 MOMENTS(0xd64ebc) 控制（逐字节确认），ON→拦截（nil/0/NO/直接 return）
- (id)getAdvertiseInfoForItem:(id)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return nil;
    return %orig;
}
- (void)logHeadImageH5:(id)arg1 { if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return; %orig; }
- (void)logADBrandProfile:(id)arg1 { if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return; %orig; }
- (void)logADFloatView:(id)arg1 { if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return; %orig; }
- (void)logADPoiH5:(id)arg1 { if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return; %orig; }
- (void)logADH5:(id)arg1 withUserInfo:(id)arg2 reportType:(unsigned long long)arg3 { if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return; %orig; }
- (void)logADH5:(id)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return;
    %orig;
}
- (void)logADDetail:(id)arg1 dataItem:(id)arg2 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return;
    %orig;
}
- (void)logSphereViewWithSphereReportInfo:(id)arg1 dataItem:(id)arg2 scene:(id)arg3 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return;
    %orig;
}
- (void)logSphereViewInDetailWithWrapInfo:(id)arg1 dataItem:(id)arg2 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return;
    %orig;
}
- (void)logSphereViewInTimeLineWithWrapInfo:(id)arg1 dataItem:(id)arg2 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return;
    %orig;
}
// 以下 3 个：WCR 受 MOMENTS(0xd64ebc) 控制（imp 0x3C81CC/0x3C8268/0x3C8304），ON→跳过（广告不上报统计）
- (void)logADCommentLog:(id)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return;
    %orig;
}
- (void)logADBodyLog:(id)arg1 {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return;
    %orig;
}
- (void)reportAllFeedsADLog {
    if (ddActive() && [DDAdBlockConfig sharedConfig].moments) return;
    %orig;
}
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
                                         version:@"1.6.2"
                                      controller:@"DDAdBlockSettingsViewController"];
            }
        }
    }
}
