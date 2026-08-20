//
//  WCRBundleIDCallerCheck.xm —— 对齐 WeChatLoginFix.dylib 的 Bundle ID 伪装（带调试日志）
//  ---------------------------------------------------------------------------
//  逆向还原自用户提供的 WeChatLoginFix.dylib（arm64 + arm64e，Theos/Logos 编译）。
//
//  【dylib 完整逻辑还原】
//    MSHookMessageEx(NSBundle, @selector(bundleIdentifier), hook=0x4048, &orig=0xc068)
//    hook 逻辑（0x4048）：
//      1. origVal = orig(self, sel)                     // 真实 bundleId
//      2. stack = [NSThread callStackReturnAddresses]   // 调用栈返回地址
//      3. if stack.count < 3 → return origVal           // 栈太浅，不伪装
//      4. frameAddr = [[stack objectAtIndexedSubscript:2] unsignedLongValue]
//      5. if !dladdr(frameAddr, &info) → return origVal // 无法解析镜像，不伪装
//      6. frameName = [NSString stringWithUTF8String:info.dli_fname]
//      7. mainPath = [[NSBundle mainBundle] bundlePath]
//      8. if [frameName hasPrefix:mainPath]             // 调用者来自主程序
//           && ![origVal isEqualToString:@"com.tencent.xin"]
//             return @"com.tencent.xin"                 // 伪装为官方
//         else return origVal
//
//  【调试日志】
//    每次 hook 触发，追加写沙盒日志：
//      NSHomeDirectory()/Documents/bundleid_fix.log
//    记录 self、原包名、栈深度、frameName、mainPath、hasPrefix、是否伪装、返回结果。
//    用 lldb/ifunbox/Files 查看该文件即可定位微信走的判定分支。
//
//  【关键差异（为什么这个能过而简单的全量/self==mainBundle 不行）】
//    它按「调用栈来源」过滤：只有主程序（微信主二进制，bundlePath 前缀）内部
//    调用 bundleIdentifier 时才伪装。微信的登录资格校验正是在主程序代码里读
//    bundleId，因此被精确命中；而系统框架/其它场景读取不受影响，规避副作用。
//
//  依赖：Theos + CydiaSubstrate
//  Makefile：
//    WCRBundleIDCallerCheck_FILES = WCRBundleIDCallerCheck.xm
//    WCRBundleIDCallerCheck_FRAMEWORKS = Foundation UIKit
//  ---------------------------------------------------------------------------

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <stdarg.h>

// 伪装目标值（对齐 dylib __cfstring：官方正式包）
static NSString *const kOfficialBundleID = @"com.tencent.xin";


// ===========================================================================
//  沙盒调试日志
//  -------------------------------------------------------------------------
//  说明：
//    - 只对微信进程写日志（bundleId 为 com.tencent.xin / com.tencent.qy.xin 等）。
//    - 文件：<沙盒>/Documents/bundleid_fix.log
//    - 追加写，带时间戳。多线程调用加互斥，避免日志交错。
// ===========================================================================
static NSFileHandle *gLogFH = nil;

// 是否已初始化日志文件句柄
static BOOL gLogInited = NO;

static void WCRLogInit(void) {
    if (gLogInited) return;
    @autoreleasepool {
        NSString *dir = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:NULL];
        NSString *path = [dir stringByAppendingPathComponent:@"bundleid_fix.log"];
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
        }
        gLogFH = [NSFileHandle fileHandleForWritingAtPath:path];
        [gLogFH seekToEndOfFile];
    }
    gLogInited = YES;
}

static void WCRLog(NSString *fmt, ...) {
    @autoreleasepool {
        WCRLogInit();
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


%hook NSBundle

- (NSString *)bundleIdentifier {
    // 1. 先取原始真实包名
    NSString *origVal = %orig;

    // 2. 取调用栈返回地址
    NSArray *stack = [NSThread callStackReturnAddresses];
    NSUInteger depth = stack.count;
    NSString *ret;

    // 3. 栈过浅则不伪装（对齐 dylib: count < 3 → 返回原值）
    if (depth < 3) {
        ret = origVal;
        WCRLog(@"[bundleIdentifier] self=%p orig=%@ | depth=%lu<3 → 不伪装, ret=%@",
               self, origVal, (unsigned long)depth, ret);
        return ret;
    }

    // 4. 取第 3 帧地址（index 2），转为指针
    unsigned long long frameAddr =
        [[stack objectAtIndexedSubscript:2] unsignedLongValue];

    // 5. 用 dladdr 解析该地址所在镜像
    Dl_info info;
    memset(&info, 0, sizeof(info));
    if (dladdr((const void *)frameAddr, &info) == 0) {
        ret = origVal;
        WCRLog(@"[bundleIdentifier] self=%p orig=%@ | depth=%lu frameAddr=0x%llx | dladdr失败 → 不伪装, ret=%@",
               self, origVal, (unsigned long)depth, frameAddr, ret);
        return ret;
    }

    // 6. 镜像文件名/路径
    NSString *frameName = [NSString stringWithUTF8String:info.dli_fname ?: ""];

    // 7. 主程序 bundle 路径
    NSString *mainPath = [[NSBundle mainBundle] bundlePath];
    BOOL fromMain = (mainPath != nil && [frameName hasPrefix:mainPath]);
    BOOL isOfficial = [origVal isEqualToString:kOfficialBundleID];

    // 8. 仅当调用者来自主程序 且 原包名非官方时，伪装为官方
    if (fromMain && !isOfficial) {
        ret = kOfficialBundleID;
        WCRLog(@"[bundleIdentifier] self=%p orig=%@ | depth=%lu frame=%@ | frame(0x%llx)来自主程序[%@], hasPrefix=YES, 原非官方 → 伪装, ret=%@",
               self, origVal, (unsigned long)depth, frameName, frameAddr,
               mainPath, ret);
        return ret;
    }

    ret = origVal;
    WCRLog(@"[bundleIdentifier] self=%p orig=%@ | depth=%lu frame=%@ | fromMain=%d isOfficial=%d → 不伪装, ret=%@",
           self, origVal, (unsigned long)depth, frameName,
           fromMain, isOfficial, ret);
    return ret;
}

%end


%ctor {
    @autoreleasepool {
        // 初始化日志（只对微信进程记录）
        WCRLogInit();
        WCRLog(@"==== WCRBundleIDCallerCheck 注入完成, 目标包名=%@ ====",
               kOfficialBundleID);

        %init;
    }
}
