#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>

static NSString *const kOfficialBundleID = @"com.tencent.xin";

%hook NSBundle

- (NSString *)bundleIdentifier {
    NSString *origVal = %orig;
    NSArray *stack = [NSThread callStackReturnAddresses];
    NSUInteger depth = stack.count;

    if (depth < 3) {
        return origVal;
    }

    unsigned long long frameAddr =
        [[stack objectAtIndexedSubscript:2] unsignedLongValue];

    Dl_info info;
    memset(&info, 0, sizeof(info));
    if (dladdr((const void *)frameAddr, &info) == 0) {
        return origVal;
    }

    NSString *frameName = [NSString stringWithUTF8String:info.dli_fname ?: ""];
    NSString *mainPath = [[NSBundle mainBundle] bundlePath];
    BOOL fromMain = (mainPath != nil && [frameName hasPrefix:mainPath]);
    BOOL isOfficial = [origVal isEqualToString:kOfficialBundleID];

    if (fromMain && !isOfficial) {
        return kOfficialBundleID;
    }

    return origVal;
}

%end

%ctor {
    %init;
}