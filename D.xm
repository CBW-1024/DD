#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>

// 微信官方 Bundle ID（用于伪装）
static NSString *const kOfficialBundleID = @"com.tencent.xin";


#pragma mark - NSBundle Hook：篡改 bundleIdentifier

%hook NSBundle

/**
 * 篡改主程序的 bundleIdentifier，仅在主程序自身代码读取时伪装成微信官方包名，
 * 以绕过某些基于 bundle ID 的检测（如越狱检测、环境校验）。
 * 对系统框架、第三方动态库等外部调用保持原样，避免副作用。
 */
- (NSString *)bundleIdentifier {
    // 先获取原始 bundleIdentifier（系统真实值）
    NSString *origVal = %orig;

    // ① 非主 Bundle（如系统库、插件等）直接放行，只干预主程序自身。
    if (self != [NSBundle mainBundle]) {
        return origVal;
    }

    // ② 如果原始值已经是目标官方包名，直接返回，避免后续栈回溯开销。
    if ([origVal isEqualToString:kOfficialBundleID]) {
        return origVal;
    }

    // ③ 获取当前调用栈地址，用于判断调用者是否来自主程序内部。
    NSArray *stack = [NSThread callStackReturnAddresses];
    NSUInteger depth = stack.count;
    // 栈深度不足 3 则无法获取有效调用帧，直接放行。
    if (depth < 3) {
        return origVal;
    }

    // 取第 3 帧（索引 2）的地址，通常是调用本方法的直接调用者。
    unsigned long long frameAddr =
        [[stack objectAtIndexedSubscript:2] unsignedLongValue];

    // ④ 通过 dladdr 获取该地址对应的符号信息，包括所属镜像路径。
    Dl_info info;
    memset(&info, 0, sizeof(info));
    if (dladdr((const void *)(uintptr_t)frameAddr, &info) == 0) {
        // 若解析失败，无法判断调用来源，安全起见放行。
        return origVal;
    }

    // ⑤ 获取调用者所在二进制文件的路径。
    NSString *frameName = [NSString stringWithUTF8String:info.dli_fname ?: ""];
    // 主程序 Bundle 路径（如 /var/containers/Bundle/Application/xxx/WeChat.app）
    NSString *mainPath = [[NSBundle mainBundle] bundlePath];

    // 判断调用者是否位于主程序包内（包括主可执行文件及内嵌 Framework）。
    BOOL fromMain = (mainPath.length > 0 && [frameName hasPrefix:mainPath]);

    // ⑥ 只有主程序自身的代码调用时才返回伪装包名，其他所有外部调用保留真实值。
    return fromMain ? kOfficialBundleID : origVal;
}

%end


#pragma mark - FaceRecogFlashHandler Hook：确保人脸流水线正常初始化

%hook FaceRecogFlashHandler

/**
 * 钩住人脸识别处理器的初始化方法，仅透传调用原实现。
 * 目的是让该方法被正常执行，防止某些检测机制因方法未被调用而判定环境异常。
 * （例如部分越狱检测会 hook 该方法返回空，导致人脸识别功能失效，此处确保其正常运行）
 */
- (void)initPipeline {
    %orig;  // 直接调用原始方法，不做任何修改
}

%end


#pragma mark - 构造函数：初始化所有 Hook

%ctor {
    @autoreleasepool {
        // %init 会展开所有 %hook 并注册到 Objective-C 运行时
        %init;
    }
}