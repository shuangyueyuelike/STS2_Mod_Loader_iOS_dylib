#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// 全局变量，用来只存一次假路径
static NSString *globalFakeBundlePath = nil;

@interface NSBundle (StS2Hook)
@end

@implementation NSBundle (StS2Hook)

// +load 方法在插件刚注入内存时执行，只执行一次！
+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // 1. 预先计算好 FakeBundle 的路径
        NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        globalFakeBundlePath = [docs stringByAppendingPathComponent:@"FakeBundle_Data"];
        NSString *modsPath = [docs stringByAppendingPathComponent:@"mods"];
        NSFileManager *fm = [NSFileManager defaultManager];
        
        // 2. 强行创建两个必备目录
        [fm createDirectoryAtPath:modsPath withIntermediateDirectories:YES attributes:nil error:nil];
        [fm createDirectoryAtPath:globalFakeBundlePath withIntermediateDirectories:YES attributes:nil error:nil];
        
        // 3. 将真实游戏包里的文件软链接到假目录（重体力活，仅干一次）
        NSString *realPath = [[NSBundle mainBundle] bundlePath];
        NSArray *items = [fm contentsOfDirectoryAtPath:realPath error:nil];
        for (NSString *item in items) {
            if ([item isEqualToString:@"mods"]) continue; // 屏蔽自带的 mods 目录
            NSString *dest = [globalFakeBundlePath stringByAppendingPathComponent:item];
            if (![fm fileExistsAtPath:dest]) {
                NSString *src = [realPath stringByAppendingPathComponent:item];
                [fm createSymbolicLinkAtPath:dest withDestinationPath:src error:nil];
            }
        }
        
        // 4. 把玩家放 Mod 的目录，也软链接进去
        NSString *fakeModsDest = [globalFakeBundlePath stringByAppendingPathComponent:@"mods"];
        if (![fm fileExistsAtPath:fakeModsDest]) {
            [fm createSymbolicLinkAtPath:fakeModsDest withDestinationPath:modsPath error:nil];
        }
        
        // 5. 挂载 Hook，把系统原来的路径查询方法偷梁换柱
        Method originalBundle = class_getInstanceMethod([NSBundle class], @selector(bundlePath));
        Method swizzledBundle = class_getInstanceMethod([self class], @selector(sts_bundlePath));
        method_exchangeImplementations(originalBundle, swizzledBundle);
        
        Method originalRes = class_getInstanceMethod([NSBundle class], @selector(resourcePath));
        Method swizzledRes = class_getInstanceMethod([self class], @selector(sts_resourcePath));
        method_exchangeImplementations(originalRes, swizzledRes);
    });
}

// 极速返回机制：一旦游戏询问，瞬间甩给它假路径，没有任何 IO 卡顿！
- (NSString *)sts_bundlePath {
    NSString *origPath = [self sts_bundlePath];
    if (![self isEqual:[NSBundle mainBundle]]) return origPath;
    return globalFakeBundlePath ? globalFakeBundlePath : origPath;
}

- (NSString *)sts_resourcePath {
    NSString *origPath = [self sts_resourcePath];
    if (![self isEqual:[NSBundle mainBundle]]) return origPath;
    return globalFakeBundlePath ? globalFakeBundlePath : origPath;
}

@end

// ---------------------------------------------------------
// 恢复原作者绝对生效的弹窗代码
// ---------------------------------------------------------
__attribute__((constructor))
static void init() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        NSString *modsPath = [docs stringByAppendingPathComponent:@"mods"];
        
        BOOL docsExist = [fm fileExistsAtPath:modsPath];
        NSString *msg = docsExist ? @"MOD 引擎完美加载！\n请在『文件』App放入MOD" : @"初始化失败";
        
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"STS2 Mod Loader" 
                                   message:msg 
                                   preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"起飞" style:UIAlertActionStyleDefault handler:nil]];
        
        // 使用你实测过有效的原作者原生弹出方式
        [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:alert animated:YES completion:nil];
    });
}
