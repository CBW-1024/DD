//
//  WCRBundleIDAlignMainBundle.xm —— 完全对齐 WCR 的伪装方法（self==mainBundle）
//  ---------------------------------------------------------------------------
//  严格复刻 WCRefine.dylib @0x1391bac 的 bundleIdentifier hook 逻辑：
//    仅当 receiver == [NSBundle mainBundle] 时返回官方包名 com.tencent.xin，
//    其余所有 NSBundle 实例（含微信/系统创建的其它 bundle）走 orig 返回真实值。
//
//  【WCR 反汇编依据（0x1391bac）】
//    1391bc0  adrp x8,#0x1f0a000 ; ldrb w8,[x8,#0xa18]  读人脸管线 flag
//    1391be8  ldur x8,[x29,#-0x10]                      self
//    1391bf0-  ldr x0,[mainBundle] + ldr x1,[@selector(mainBundle)]
//    1391c34  subs x8,x8,x9 ; b.ne →orig                若 self != mainBundle → 走 orig
//    1391c84- 命中时 adrp x0,0x1ca5000; add x0,#0xf78  返回 CFString "com.tencent.xin"
//    1391ce4  blr orig(0x1f0a000+0x910)                 未命中 → 真实 bundleId
//
//  【用途】验证"self==mainBundle 过滤"对无线数据授权弹窗的影响：
//    - 登录资格：微信读 [NSBundle mainBundle].bundleIdentifier → 伪装 → 去资格
//    - 无线数据检测：若其用非 mainBundle 实例 → 返回真实 qy.xin → 弹窗恢复
//
//  【调试日志】本版本日志默认开启（-DWCR_ENABLE_LOG=1），写入沙盒 Documents：
//    <沙盒>/Documents/bundleid_main.log
//    同时输出到 NSLog（Console.app 可看）。每条记录 self 指针、是否 mainBundle、
//    实例 bundlePath、调用栈来源镜像。用于定位无线数据检测到底用哪个 NSBundle 实例。
//  ---------------------------------------------------------------------------

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <stdarg.h>

// 伪装目标值（对齐 WCR CFString@0x1ca5000+0xf78：官方正式包）
static NSString *const kOfficialBundleID = @"com.tencent.xin";


// ===========================================================================
//  调试日志（本版本默认开启）
// ===========================================================================
#ifdef WCR_ENABLE_LOG

static NSFileHandle *gLogFH = nil;
static BOOL gLogInited = NO;

static void WCRLogInit(void) {
    if (gLogInited) return;
    @autoreleasepool {
        // 日志写沙盒 Documents（用户指定），同时 NSLog 兜底
        NSString *dir = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:NULL];
        NSString *path = [dir stringByAppendingPathComponent:@"bundleid_main.log"];
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
        }
        gLogFH = [NSFileHandle fileHandleForWritingAtPath:path];
        [gLogFH seekToEndOfFile];
        NSLog(@"[WCRBundleIDAlignMainBundle] 日志文件: %@ (handle=%@)", path, gLogFH);
    }
    gLogInited = YES;
}

static void WCRLog(NSString *fmt, ...) {
    @autoreleasepool {
        WCRLogInit();
        // 同时输出到系统日志（Console.app / idevice 日志可看）
        va_list args2;
        va_start(args2, fmt);
        NSString *nslogMsg = [[NSString alloc] initWithFormat:fmt arguments:args2];
        va_end(args2);
        NSLog(@"[WCRBundleIDAlignMainBundle] %@", nslogMsg);

        if (gLogFH == nil) return;
        va_list args;
        va_start(args, fmt);
        NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
        va_end(args);
        NSDateFormatter *df = [[NSDateFormatter alloc] init];
        [df setDateFormat:@"yyyy-MM-dd HH:mm:ss.SSS"];
        NSString *line = [NSString stringWithFormat:@"[%@] %@\n",
                          [df stringFromDate:[NSDate date]], msg];
        NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
        @synchronized (gLogFH) {
            [gLogFH writeData:data];
            [gLogFH synchronizeFile];
        }
    }
}

// 解析调用者镜像，判断 bundleIdentifier 是被谁调用的
static NSString *WCRCallerImage(void) {
    NSArray *stack = [NSThread callStackReturnAddresses];
    if (stack.count < 3) return @"(栈太浅)";
    unsigned long long frameAddr =
        [[stack objectAtIndexedSubscript:2] unsignedLongValue];
    Dl_info info;
    memset(&info, 0, sizeof(info));
    if (dladdr((const void *)frameAddr, &info) == 0) {
        return @"(dladdr失败)";
    }
    return [NSString stringWithUTF8String:info.dli_fname ?: "?"];
}

#else
#define WCRLogInit() do {} while (0)
#define WCRLog(...)  do {} while (0)
#define WCRCallerImage() @""
#endif


// ===========================================================================
//  对齐 WCR：self==mainBundle 过滤（带日志）
// ===========================================================================
%hook NSBundle

- (NSString *)bundleIdentifier {
    NSBundle *mainBundle = [NSBundle mainBundle];

    // 分支一：self == [NSBundle mainBundle] → 伪装为官方包
    if (self == mainBundle) {
        WCRLog(@"[bundleIdentifier] self=%p == mainBundle(%p) → 伪装, ret=%@",
               self, mainBundle, kOfficialBundleID);
        return kOfficialBundleID;
    }

    // 分支二：其它 NSBundle 实例 → 走 orig 返回真实值
    NSString *origVal = %orig;
    WCRLog(@"[bundleIdentifier] self=%p != mainBundle(%p) | self.bundlePath=%@ | caller=%@ | → 不伪装, ret=%@",
           self, mainBundle,
           self.bundlePath ?: @"(nil)",
           WCRCallerImage(),
           origVal);
    return origVal;
}

%end


%ctor {
    @autoreleasepool {
        WCRLogInit();
        WCRLog(@"==== WCRBundleIDAlignMainBundle 注入完成, 目标包名=%@, 日志已开启 ====",
               kOfficialBundleID);
        %init;
    }
}
