//
//  WCRBundleIDAlignWCP.xm —— 对齐 WCP（WCPulse）的伪装逻辑（objectForInfoDictionaryKey:）
//  ---------------------------------------------------------------------------
//  严格对齐 WCPulse.dylib 的 bundleId 伪装机制：
//    WCP hook 的是 NSBundle -objectForInfoDictionaryKey:（IMP @0x593258），
//    通过 XOR 混淆解码出 CFBundleIdentifier key 与伪装值 com.tencent.xin
//    （源缓冲 0xb61000+0x940 key / 0xb61000+0x8fa 值），对指定 key 返回伪装值。
//
//  本版本只 hook objectForInfoDictionaryKey:（对齐 WCP，不 hook bundleIdentifier），
//  当外部读取 Info.plist 的 CFBundleIdentifier 键时返回官方包名 com.tencent.xin。
//
//  用途：验证"走 objectForInfoDictionaryKey: 伪装"这条路径对登录 / 无线数据弹窗 /
//        UI 布局的影响，与 self==mainBundle / 调用栈过滤两条路径作对照。
//
//  调试日志：默认开启，写入 <沙盒>/Documents/bundleid_wcp.log，同时 NSLog。
//  ---------------------------------------------------------------------------

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <stdarg.h>

// 伪装目标值（对齐 WCP：官方正式包）
static NSString *const kOfficialBundleID = @"com.tencent.xin";


// ===========================================================================
//  调试日志（默认开启）
// ===========================================================================
#ifdef WCR_ENABLE_LOG

static NSFileHandle *gLogFH = nil;
static BOOL gLogInited = NO;

static void WCRLogInit(void) {
    if (gLogInited) return;
    @autoreleasepool {
        NSString *dir = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:NULL];
        NSString *path = [dir stringByAppendingPathComponent:@"bundleid_wcp.log"];
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
        }
        gLogFH = [NSFileHandle fileHandleForWritingAtPath:path];
        [gLogFH seekToEndOfFile];
        NSLog(@"[WCRBundleIDAlignWCP] 日志文件: %@ (handle=%@)", path, gLogFH);
    }
    gLogInited = YES;
}

static void WCRLog(NSString *fmt, ...) {
    @autoreleasepool {
        WCRLogInit();
        va_list args2;
        va_start(args2, fmt);
        NSString *nslogMsg = [[NSString alloc] initWithFormat:fmt arguments:args2];
        va_end(args2);
        NSLog(@"[WCRBundleIDAlignWCP] %@", nslogMsg);

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

#else
#define WCRLogInit() do {} while (0)
#define WCRLog(...)  do {} while (0)
#endif


// ===========================================================================
//  对齐 WCP：hook objectForInfoDictionaryKey:，对 CFBundleIdentifier 伪装
// ===========================================================================
%hook NSBundle

- (id)objectForInfoDictionaryKey:(NSString *)key {
    id origVal = %orig;
    // 对齐 WCP：当读取 Info.plist 的 CFBundleIdentifier 键时，伪装为官方包名
    if ([key isEqualToString:@"CFBundleIdentifier"]) {
        WCRLog(@"[objectForInfoDictionaryKey:] key=CFBundleIdentifier → 伪装, orig=%@ ret=%@",
               origVal, kOfficialBundleID);
        return kOfficialBundleID;
    }
    WCRLog(@"[objectForInfoDictionaryKey:] key=%@ → 不伪装, ret=%@", key, origVal);
    return origVal;
}

%end


%ctor {
    @autoreleasepool {
        WCRLogInit();
        WCRLog(@"==== WCRBundleIDAlignWCP 注入完成 (对齐 WCP objectForInfoDictionaryKey:), 目标=%@ ====",
               kOfficialBundleID);
        %init;
    }
}
