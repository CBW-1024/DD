//
//  WCRBundleIDCallerCheck.xm —— 对齐 WeChatLoginFix.dylib 的 Bundle ID 伪装
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

// 伪装目标值（对齐 dylib __cfstring：官方正式包）
static NSString *const kOfficialBundleID = @"com.tencent.xin";


%hook NSBundle

- (NSString *)bundleIdentifier {
    // 1. 先取原始真实包名
    NSString *origVal = %orig;

    // 2. 取调用栈返回地址
    NSArray *stack = [NSThread callStackReturnAddresses];

    // 3. 栈过浅则不伪装（对齐 dylib: count < 3 → 返回原值）
    if (stack.count < 3) {
        return origVal;
    }

    // 4. 取第 3 帧地址（index 2），转为指针
    unsigned long long frameAddr =
        [[stack objectAtIndexedSubscript:2] unsignedLongValue];

    // 5. 用 dladdr 解析该地址所在镜像
    Dl_info info;
    if (dladdr((const void *)frameAddr, &info) == 0) {
        return origVal;
    }

    // 6. 镜像文件名/路径
    NSString *frameName =
        [NSString stringWithUTF8String:info.dli_fname ?: ""];

    // 7. 主程序 bundle 路径
    NSString *mainPath = [[NSBundle mainBundle] bundlePath];

    // 8. 仅当调用者来自主程序 且 原包名非官方时，伪装为官方
    if (mainPath != nil && [frameName hasPrefix:mainPath]
        && ![origVal isEqualToString:kOfficialBundleID]) {
        return kOfficialBundleID;
    }

    return origVal;
}

%end


%ctor {
    @autoreleasepool {
        %init;
    }
}
