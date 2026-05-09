#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static NSString *globalFakeResourcePath = nil;

@interface NSBundle (StS2Hook)
@end

@implementation NSBundle (StS2Hook)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        NSString *fakeBundlePath = [docs stringByAppendingPathComponent:@"FakeBundle_Data"];
        NSString *modsPath = [docs stringByAppendingPathComponent:@"mods"];
        NSFileManager *fm = [NSFileManager defaultManager];
        
        // 1. 快速创建目录
        [fm createDirectoryAtPath:modsPath withIntermediateDirectories:YES attributes:nil error:nil];
        [fm createDirectoryAtPath:fakeBundlePath withIntermediateDirectories:YES attributes:nil error:nil];
        
        // 2. 将原本的资源软链接进来
        NSString *realPath = [[NSBundle mainBundle] resourcePath];
        NSArray *items = [fm contentsOfDirectoryAtPath:realPath error:nil];
        for (NSString *item in items) {
            if ([item isEqualToString:@"mods"]) continue;
            NSString *dest = [fakeBundlePath stringByAppendingPathComponent:item];
            if (![fm fileExistsAtPath:dest]) {
                NSString *src = [realPath stringByAppendingPathComponent:item];
                [fm createSymbolicLinkAtPath:dest withDestinationPath:src error:nil];
            }
        }
        
        // 3. 将你的 Mods 文件夹软链接进来
        NSString *fakeModsDest = [fakeBundlePath stringByAppendingPathComponent:@"mods"];
        if (![fm fileExistsAtPath:fakeModsDest]) {
            [fm createSymbolicLinkAtPath:fakeModsDest withDestinationPath:modsPath error:nil];
        }
        
        // 保存伪造路径
        globalFakeResourcePath = fakeBundlePath;
        
        // 🔥 【核心修复】：绝对不碰 bundlePath！只劫持 resourcePath！保全 UIKit 的命！
        Method originalRes = class_getInstanceMethod([NSBundle class], @selector(resourcePath));
        Method swizzledRes = class_getInstanceMethod([self class], @selector(sts_resourcePath));
        method_exchangeImplementations(originalRes, swizzledRes);
    });
}

// 当游戏引擎询问资源在哪时，给它假路径
- (NSString *)sts_resourcePath {
    NSString *origPath = [self sts_resourcePath];
    if (![self isEqual:[NSBundle mainBundle]]) return origPath;
    return globalFakeResourcePath ? globalFakeResourcePath : origPath;
}

@end

// ---------------------------------------------------------
// 弹窗提示
// ---------------------------------------------------------
__attribute__((constructor))
static void sts2_init() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"MOD 引擎完美加载" 
                                   message:@"文件拦截已生效，快去放入 MOD 吧！" 
                                   preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"起飞" style:UIAlertActionStyleDefault handler:nil]];
        
        UIWindow *keyWindow = nil;
        for (UIWindow *window in [UIApplication sharedApplication].windows) {
            if (window.isKeyWindow) { keyWindow = window; break; }
        }
        [keyWindow.rootViewController presentViewController:alert animated:YES completion:nil];
    });
}
