/**
 * 英雄3 (Hero3) v1.0 - Dobby inline hook 插件
 * 目标: com.hero.yzr3.ios
 *
 * 功能:
 *   - 无CD (CheckCanUseSkill -> return true)
 *   - 伤害秒杀 (get_limitDamage -> return 设定值)
 *   - 商店直接购买 (PurchaseItem 直接调用)
 *   - IAP内购模拟 (ApplePayOnSuccess 直接发送receipt)
 *   - 可拖动浮动球 + 面板UI
 *
 * 参考: jycheatv2 (剑影江湖) 的 Dobby inline hook 架构
 *
 * IL2CPP方法签名 (来自dump.cs):
 *   CheckCanUseSkill(int skillID)->bool  [SkillDataModule, 偏移0x343b04]
 *   get_limitDamage()->int               [RuntimeConfig?]
 *   PurchaseItem(shopId,shopItemId,buyCount,IsShopJduge,freeScroll,heroID) [ShopDataModule, 偏移0x489128]
 *   ApplePayOnSuccess(string receipt)     [SDKDataModule, 偏移0x34a27c]
 *   SendPayRequestGameServer(shopId,meta,method,count,heroId) [SDKDataModule, 偏移0x489128]
 */

#import <mach-o/dyld.h>
#import <mach/mach.h>
#import <dispatch/dispatch.h>
#import <UIKit/UIKit.h>
#import <stdio.h>
#import <string.h>
#import <dlfcn.h>

#include "dobby.h"

// ============================================================
// 日志
// ============================================================

static FILE *g_logFile = NULL;
static NSMutableArray *g_debugLines = nil;
static UILabel *g_debugLabel = nil;

static void ylog(NSString *fmt, ...) {
    va_list args; va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    NSLog(@"[YZR3] %@", msg);
    if (g_debugLines) {
        [g_debugLines addObject:msg];
        if (g_debugLines.count > 50) [g_debugLines removeObjectAtIndex:0];
    }
    if (g_debugLabel) g_debugLabel.text = [g_debugLines componentsJoinedByString:@"\n"];
    if (!g_logFile) {
        NSString *p = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/yzr3.log"];
        g_logFile = fopen([p UTF8String], "a");
    }
    if (g_logFile) { fprintf(g_logFile, "%s\n", [msg UTF8String]); fflush(g_logFile); }
}

// ============================================================
// 全局状态
// ============================================================

static BOOL g_noCD = YES;
static BOOL g_damageCheat = YES;
static int g_damageLimit = 999999;

static void *g_funcCheckCanUseSkill = NULL;
static void *g_funcLimitDmg = NULL;
static void *g_funcPurchaseItem = NULL;
static void *g_funcApplePayOnSuccess = NULL;
static void *g_funcSendPayRequest = NULL;

typedef BOOL (*CheckCanUseSkillType)(void *self, int skillID);
static CheckCanUseSkillType g_origCheckCanUseSkill = NULL;

typedef int (*LimitDmgFuncType)(void *self);
static LimitDmgFuncType g_origLimitDmg = NULL;

typedef void (*PurchaseItemFuncType)(void *self, int shopId, int shopItemId, int buyCount, BOOL isShopJudge, void *freeScroll, int heroID);
static PurchaseItemFuncType g_origPurchaseItem = NULL;

typedef void (*ApplePayOnSuccessType)(void *self, void *receipt);
static ApplePayOnSuccessType g_origApplePayOnSuccess = NULL;

static BOOL g_cdHooked = NO;
static BOOL g_limitHooked = NO;

static int g_shopId = 0;
static int g_shopItemId = 0;
static int g_buyCount = 1;
static int g_heroId = 0;

static UIView *g_panel = nil;
static UIButton *g_btnCD = nil;
static UIButton *g_btnDmg = nil;
static UISlider *g_slider = nil;
static UILabel *g_sliderLabel = nil;
static UITextField *g_tfShopId = nil;
static UITextField *g_tfItemId = nil;
static UITextField *g_tfCount = nil;
static UIButton *g_btnBuy = nil;
static UIButton *g_btnIAP = nil;
static BOOL g_panelOpen = NO;

// ============================================================
// 替代函数
// ============================================================

static BOOL hookCheckCanUseSkill(void *self, int skillID) {
    return YES;
}

static int hookLimitDmg(void *self) {
    return g_damageLimit;
}

// ============================================================
// IL2CPP运行时API
// ============================================================

typedef void* (*Il2CppDomainGet)(void);
typedef void** (*Il2CppDomainGetAssemblies)(void*, size_t*);
typedef void* (*Il2CppAssemblyGetImage)(void*);
typedef size_t (*Il2CppImageGetClassCount)(void*);
typedef void* (*Il2CppImageGetClass)(void*, size_t);
typedef void* (*Il2CppClassGetMethods)(void*, void**);
typedef const char* (*Il2CppMethodGetName)(void*);
typedef uint32_t (*Il2CppMethodGetParamCount)(void*);
typedef const char* (*Il2CppClassGetName)(void*);

// ============================================================
// 查找IL2CPP方法
// ============================================================

typedef struct {
    const char *name;
    void **outFunc;
    int paramCount;
} MethodTarget;

static void findIL2CPP(void) {
    ylog(@"=== YZR3 IL2CPP Runtime Search ===");
    void *h = dlopen(NULL, RTLD_LAZY);
    if (!h) { ylog(@"dlopen FAIL"); return; }

    Il2CppDomainGet domain_get = dlsym(h, "il2cpp_domain_get");
    Il2CppDomainGetAssemblies get_assemblies = dlsym(h, "il2cpp_domain_get_assemblies");
    Il2CppAssemblyGetImage get_image = dlsym(h, "il2cpp_assembly_get_image");
    Il2CppImageGetClassCount class_count = dlsym(h, "il2cpp_image_get_class_count");
    Il2CppImageGetClass get_class = dlsym(h, "il2cpp_image_get_class");
    Il2CppClassGetMethods get_methods = dlsym(h, "il2cpp_class_get_methods");
    Il2CppMethodGetName method_name = dlsym(h, "il2cpp_method_get_name");
    Il2CppMethodGetParamCount param_count = dlsym(h, "il2cpp_method_get_param_count");
    Il2CppClassGetName class_name_func = dlsym(h, "il2cpp_class_get_name");

    if (!domain_get || !method_name) { ylog(@"IL2CPP APIs not found"); return; }
    void *domain = domain_get();
    if (!domain) return;

    size_t assemCount = 0;
    void **assemblies = get_assemblies(domain, &assemCount);
    if (!assemblies) return;

    MethodTarget targets[] = {
        {"CheckCanUseSkill",  &g_funcCheckCanUseSkill,  1},
        {"get_limitDamage",   &g_funcLimitDmg,          0},
        {"PurchaseItem",      &g_funcPurchaseItem,      6},
        {"ApplePayOnSuccess", &g_funcApplePayOnSuccess, 1},
        {"SendPayRequestGameServer", &g_funcSendPayRequest, 5},
    };
    int targetCount = sizeof(targets) / sizeof(targets[0]);
    int found = 0;
    int totalMethods = 0;

    for (size_t a = 0; a < assemCount && found < targetCount; a++) {
        void *img = get_image(assemblies[a]);
        if (!img) continue;
        size_t cnt = class_count ? class_count(img) : 0;
        for (size_t c = 0; c < cnt && found < targetCount; c++) {
            void *klass = get_class(img, c);
            if (!klass) continue;
            const char *cn = class_name_func ? class_name_func(klass) : NULL;
            void *iter = NULL;
            void *m = NULL;
            while ((m = get_methods(klass, &iter)) != NULL) {
                totalMethods++;
                const char *n = method_name(m);
                if (!n) continue;
                for (int t = 0; t < targetCount; t++) {
                    if (*targets[t].outFunc) continue;
                    if (strcmp(n, targets[t].name) != 0) continue;
                    uint32_t pc = param_count ? param_count(m) : 0;
                    if (targets[t].paramCount >= 0 && pc != targets[t].paramCount) continue;
                    ylog(@"FOUND %s class=%s params=%u", n, cn ?: "?", pc);
                    memcpy(targets[t].outFunc, m, sizeof(void*));
                    ylog(@"  funcAddr=%p", *targets[t].outFunc);
                    found++;
                }
            }
        }
    }
    ylog(@"Scanned %d methods, found %d/%d targets", totalMethods, found, targetCount);
}

// ============================================================
// Dobby Hook 操作
// ============================================================

static void hookCDFunc(BOOL enable) {
    if (!g_funcCheckCanUseSkill) { ylog(@"CheckCanUseSkill: not found"); return; }
    if (enable && !g_cdHooked) {
        int ret = DobbyHook(g_funcCheckCanUseSkill, hookCheckCanUseSkill, (void **)&g_origCheckCanUseSkill);
        if (ret == 0) { g_cdHooked = YES; ylog(@"CD: DobbyHook OK at %p", g_funcCheckCanUseSkill); }
        else { ylog(@"CD: DobbyHook FAILED ret=%d", ret); }
    } else if (!enable && g_cdHooked) {
        int ret = DobbyDestroy(g_funcCheckCanUseSkill);
        if (ret == 0) { g_cdHooked = NO; g_origCheckCanUseSkill = NULL; ylog(@"CD: restored"); }
    }
}

static void hookLimitDmgFunc(BOOL enable) {
    if (!g_funcLimitDmg) { ylog(@"get_limitDamage: not found"); return; }
    if (enable && !g_limitHooked) {
        int ret = DobbyHook(g_funcLimitDmg, hookLimitDmg, (void **)&g_origLimitDmg);
        if (ret == 0) { g_limitHooked = YES; ylog(@"LimitDmg: DobbyHook OK at %p", g_funcLimitDmg); }
        else { ylog(@"LimitDmg: DobbyHook FAILED ret=%d", ret); }
    } else if (!enable && g_limitHooked) {
        int ret = DobbyDestroy(g_funcLimitDmg);
        if (ret == 0) { g_limitHooked = NO; g_origLimitDmg = NULL; ylog(@"LimitDmg: restored"); }
    }
}

static void applyAllHooks(void) {
    if (!g_funcCheckCanUseSkill) findIL2CPP();
    if (g_noCD) hookCDFunc(YES);
    if (g_damageCheat) hookLimitDmgFunc(YES);
    ylog(@"applyAllHooks done");
}

// ============================================================
// 商店/IAP 直接调用
// ============================================================

/**
 * 直接调用 ShopDataModule.PurchaseItem
 * 绕过UI和条件检查, 直接向服务器发送购买请求
 * 注意: 服务器端仍会验证货币/条件, 此处仅绕过客户端限制
 */
static void directPurchaseItem(int shopId, int shopItemId, int count) {
    if (!g_funcPurchaseItem) {
        ylog(@"PurchaseItem func not found, trying IL2CPP search...");
        findIL2CPP();
        if (!g_funcPurchaseItem) { ylog(@"Still not found, abort"); return; }
    }
    ylog(@"DirectPurchase: shopId=%d itemId=%d count=%d", shopId, shopItemId, count);

    // PurchaseItem是实例方法, 需要ShopDataModule单例
    // ShopDataModule : Singleton_CSharp<ShopDataModule>
    // 通过IL2CPP查找单例: ShopDataModule.Instance 或 get_Instance()
    // 简化方案: 直接用函数地址+偏移调用 (需要单例指针)

    // TODO: 获取ShopDataModule单例指针的方法:
    // 1. 通过il2cpp_class_get_method_from_name查找get_Instance
    // 2. 调用get_Instance()获取单例
    // 3. 用单例指针调用PurchaseItem

    ylog(@"[WARN] PurchaseItem requires singleton instance - not yet implemented");
    ylog(@"[INFO] Use IAP method instead for RMB purchases");
}

/**
 * IAP内购模拟: 直接调用 ApplePayOnSuccess
 * 传入伪造的receipt, 触发游戏服务器验证流程
 * 注意: 伪造receipt无法通过Apple服务器验证, 仅用于研究协议流程
 */
static void simulateIAP(const char *fakeReceipt) {
    if (!g_funcApplePayOnSuccess) {
        ylog(@"ApplePayOnSuccess func not found");
        findIL2CPP();
        if (!g_funcApplePayOnSuccess) { ylog(@"Still not found, abort"); return; }
    }
    ylog(@"SimulateIAP: receipt=%s", fakeReceipt);

    // ApplePayOnSuccess是SDKDataModule实例方法
    // 需要单例指针 + NSString* receipt
    // TODO: 获取SDKDataModule单例

    ylog(@"[WARN] ApplePayOnSuccess requires singleton instance - not yet implemented");
    ylog(@"[INFO] IAP flow: InitIAP -> StartApplePay -> ApplePayOnSuccess -> SDKApplePayTransaction");
    ylog(@"[INFO] Protocol: NewSdkRechargeRequest{shopId,shopItemId,taType,amount,buyNum,reqtime,heroId,clientSdkDesc}");
    ylog(@"[INFO] Response: NewSdkRechargeResponse{errorCode,transactionRequestInfo,taType}");
}

// ============================================================
// UI
// ============================================================

static void refreshButtons(void) {
    [g_btnCD setTitle: g_noCD ? @"\U00002705 \u65e0CD: \u5f00" : @"\U0000274c \u65e0CD: \u5173" forState:UIControlStateNormal];
    g_btnCD.backgroundColor = g_noCD ? [UIColor colorWithRed:0.15 green:0.75 blue:0.15 alpha:0.95] : [UIColor colorWithRed:0.7 green:0.15 blue:0.15 alpha:0.95];
    [g_btnDmg setTitle: g_damageCheat ? @"\U00002705 \u79d2\u6740: \u5f00" : @"\U0000274c \u79d2\u6740: \u5173" forState:UIControlStateNormal];
    g_btnDmg.backgroundColor = g_damageCheat ? [UIColor colorWithRed:0.15 green:0.75 blue:0.15 alpha:0.95] : [UIColor colorWithRed:0.7 green:0.15 blue:0.15 alpha:0.95];
}

static void layoutPanel(UIView *bv) {
    if (!bv || !g_panel) return;
    CGRect bf=bv.frame, sc=[UIScreen mainScreen].bounds;
    CGFloat pw=280, ph=520;
    CGFloat px=bf.origin.x-pw-8; if(px<4)px=bf.origin.x+bf.size.width+8;
    CGFloat py=bf.origin.y+bf.size.height/2-ph/2;
    if(py<4)py=4; if(pyy+ph>sc.size.height-4)py=sc.size.height-ph-4;
    g_panel.frame=CGRectMake(px,py,pw,ph);
}

static void togglePanel(UIView *bv) {
    g_panelOpen=!g_panelOpen; g_panel.hidden=!g_panelOpen;
    if(g_panelOpen)layoutPanel(bv);
}

@interface YZR3ActionHandler : NSObject
+ (instancetype)shared;
- (void)onCD;
- (void)onDmg;
- (void)sliderChanged:(UISlider *)slider;
- (void)onBuy;
- (void)onIAP;
@end

@implementation YZR3ActionHandler
+ (instancetype)shared { static YZR3ActionHandler *s; static dispatch_once_t o; dispatch_once(&o,^{s=[[self alloc]init];}); return s; }
- (void)onCD {
    g_noCD=!g_noCD; refreshButtons();
    hookCDFunc(g_noCD);
}
- (void)onDmg {
    g_damageCheat=!g_damageCheat; refreshButtons();
    hookLimitDmgFunc(g_damageCheat);
}
- (void)sliderChanged:(UISlider *)s {
    g_damageLimit=(int)s.value;
    g_sliderLabel.text=[NSString stringWithFormat:@"\u4f24\u5bb3: %d",g_damageLimit];
}
- (void)onBuy {
    g_shopId = g_tfShopId.text.intValue;
    g_shopItemId = g_tfItemId.text.intValue;
    g_buyCount = g_tfCount.text.intValue;
    if (g_buyCount < 1) g_buyCount = 1;
    ylog(@"Buy: shopId=%d itemId=%d count=%d", g_shopId, g_shopItemId, g_buyCount);
    directPurchaseItem(g_shopId, g_shopItemId, g_buyCount);
}
- (void)onIAP {
    g_shopId = g_tfShopId.text.intValue;
    g_shopItemId = g_tfItemId.text.intValue;
    ylog(@"IAP: shopId=%d itemId=%d", g_shopId, g_shopItemId);
    simulateIAP("fake_receipt_for_research");
}
@end

@interface YZR3BallView : UIView { CGPoint _ts; BOOL _drag; }
@end
@implementation YZR3BallView
- (instancetype)init {
    self=[super initWithFrame:CGRectMake([UIScreen mainScreen].bounds.size.width-54,100,44,44)];
    if(self){
        self.backgroundColor=[UIColor colorWithRed:0.9 green:0.3 blue:0.1 alpha:0.9];
        self.layer.cornerRadius=22; self.userInteractionEnabled=YES;
        UILabel*l=[[UILabel alloc]initWithFrame:CGRectMake(0,0,44,44)];
        l.text=@"\U0001f3f9"; l.textColor=[UIColor whiteColor];
        l.font=[UIFont boldSystemFontOfSize:20]; l.textAlignment=NSTextAlignmentCenter;
        [self addSubview:l];
    }
    return self;
}
- (BOOL)pointInside:(CGPoint)p withEvent:(UIEvent*)e{return CGRectContainsPoint(CGRectInset(self.bounds,-8,-8),p);}
- (void)touchesBegan:(NSSet*)t withEvent:(UIEvent*)e{_ts=[[t anyObject]locationInView:self.superview];_drag=NO;}
- (void)touchesMoved:(NSSet*)t withEvent:(UIEvent*)e{
    CGPoint c=[[t anyObject]locationInView:self.superview];
    CGFloat dx=c.x-_ts.x,dy=c.y-_ts.y;
    if(fabs(dx)>5||fabs(dy)>5){
        _drag=YES; CGRect f=self.frame; CGRect sc=[UIScreen mainScreen].bounds;
        f.origin.x=MAX(0,MIN(sc.size.width-f.size.width,f.origin.x+dx));
        f.origin.y=MAX(50,MIN(sc.size.height-f.size.height-50,f.origin.y+dy));
        self.frame=f; _ts=c;
        if(g_panelOpen)layoutPanel(self);
    }
}
- (void)touchesEnded:(NSSet*)t withEvent:(UIEvent*)e{if(!_drag)togglePanel(self);_drag=NO;}
- (void)touchesCancelled:(NSSet*)t withEvent:(UIEvent*)e{_drag=NO;}
@end

static UIWindow *getKeyWindow(void) {
    if (@available(iOS 15.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive &&
                [scene isKindOfClass:[UIWindowScene class]]) {
                for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                    if (w.isKeyWindow && !w.isHidden) return w;
                }
                for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                    if (!w.isHidden) return w;
                }
            }
        }
    }
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (w.isKeyWindow && !w.isHidden) return w;
    }
    return nil;
}

static void setupUI(void) {
    UIWindow *win = getKeyWindow();
    if (!win) { dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1.0*NSEC_PER_SEC)),dispatch_get_main_queue(),^{setupUI();}); return; }

    YZR3BallView *ball = [[YZR3BallView alloc] init];
    [win addSubview:ball];

    CGFloat pw=280, ph=520;
    g_panel=[[UIView alloc]initWithFrame:CGRectMake(0,0,pw,ph)];
    g_panel.backgroundColor=[UIColor colorWithRed:0.08 green:0.08 blue:0.12 alpha:0.98];
    g_panel.layer.cornerRadius=14; g_panel.hidden=YES;
    [win addSubview:g_panel];

    // Title
    UILabel *title=[[UILabel alloc]initWithFrame:CGRectMake(0,10,pw,24)];
    title.text=@"\u82f1\u96c43 YZR3 Cheat v1.0"; title.textColor=[UIColor cyanColor];
    title.font=[UIFont boldSystemFontOfSize:15]; title.textAlignment=NSTextAlignmentCenter;
    [g_panel addSubview:title];

    // No CD button
    g_btnCD=[UIButton buttonWithType:UIButtonTypeCustom]; g_btnCD.frame=CGRectMake(16,42,248,36);
    g_btnCD.layer.cornerRadius=8;
    [g_btnCD addTarget:[YZR3ActionHandler shared] action:@selector(onCD) forControlEvents:UIControlEventTouchUpInside];
    [g_panel addSubview:g_btnCD];

    // Damage/SecKill button
    g_btnDmg=[UIButton buttonWithType:UIButtonTypeCustom]; g_btnDmg.frame=CGRectMake(16,84,248,36);
    g_btnDmg.layer.cornerRadius=8;
    [g_btnDmg addTarget:[YZR3ActionHandler shared] action:@selector(onDmg) forControlEvents:UIControlEventTouchUpInside];
    [g_panel addSubview:g_btnDmg];

    // Damage slider
    g_sliderLabel=[[UILabel alloc]initWithFrame:CGRectMake(16,128,248,20)];
    g_sliderLabel.text=@"\u4f24\u5bb3\u503c: 999999"; g_sliderLabel.textColor=[UIColor whiteColor];
    g_sliderLabel.font=[UIFont systemFontOfSize:13]; [g_panel addSubview:g_sliderLabel];

    g_slider=[[UISlider alloc]initWithFrame:CGRectMake(16,150,248,28)];
    g_slider.minimumValue=100; g_slider.maximumValue=999999; g_slider.value=999999;
    [g_slider addTarget:[YZR3ActionHandler shared] action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [g_panel addSubview:g_slider];

    // Shop section
    UILabel *shopTitle=[[UILabel alloc]initWithFrame:CGRectMake(16,186,248,20)];
    shopTitle.text=@"\u5546\u5e97\u8d2d\u4e70"; shopTitle.textColor=[UIColor yellowColor];
    shopTitle.font=[UIFont boldSystemFontOfSize:13]; [g_panel addSubview:shopTitle];

    // ShopId input
    UILabel *lbl1=[[UILabel alloc]initWithFrame:CGRectMake(16,210,60,24)];
    lbl1.text=@"ShopId:"; lbl1.textColor=[UIColor whiteColor]; lbl1.font=[UIFont systemFontOfSize:11];
    [g_panel addSubview:lbl1];
    g_tfShopId=[[UITextField alloc]initWithFrame:CGRectMake(76,210,188,24)];
    g_tfShopId.backgroundColor=[UIColor colorWithRed:0.2 green:0.2 blue:0.3 alpha:1];
    g_tfShopId.textColor=[UIColor whiteColor]; g_tfShopId.font=[UIFont systemFontOfSize:12];
    g_tfShopId.keyboardType=UIKeyboardTypeNumberPad; g_tfShopId.text=@"0";
    g_tfShopId.layer.cornerRadius=4; [g_panel addSubview:g_tfShopId];

    // ItemId input
    UILabel *lbl2=[[UILabel alloc]initWithFrame:CGRectMake(16,240,60,24)];
    lbl2.text=@"ItemId:"; lbl2.textColor=[UIColor whiteColor]; lbl2.font=[UIFont systemFontOfSize:11];
    [g_panel addSubview:lbl2];
    g_tfItemId=[[UITextField alloc]initWithFrame:CGRectMake(76,240,188,24)];
    g_tfItemId.backgroundColor=[UIColor colorWithRed:0.2 green:0.2 blue:0.3 alpha:1];
    g_tfItemId.textColor=[UIColor whiteColor]; g_tfItemId.font=[UIFont systemFontOfSize:12];
    g_tfItemId.keyboardType=UIKeyboardTypeNumberPad; g_tfItemId.text=@"0";
    g_tfItemId.layer.cornerRadius=4; [g_panel addSubview:g_tfItemId];

    // Count input
    UILabel *lbl3=[[UILabel alloc]initWithFrame:CGRectMake(16,270,60,24)];
    lbl3.text=@"Count:"; lbl3.textColor=[UIColor whiteColor]; lbl3.font=[UIFont systemFontOfSize:11];
    [g_panel addSubview:lbl3];
    g_tfCount=[[UITextField alloc]initWithFrame:CGRectMake(76,270,188,24)];
    g_tfCount.backgroundColor=[UIColor colorWithRed:0.2 green:0.2 blue:0.3 alpha:1];
    g_tfCount.textColor=[UIColor whiteColor]; g_tfCount.font=[UIFont systemFontOfSize:12];
    g_tfCount.keyboardType=UIKeyboardTypeNumberPad; g_tfCount.text=@"1";
    g_tfCount.layer.cornerRadius=4; [g_panel addSubview:g_tfCount];

    // Buy button
    g_btnBuy=[UIButton buttonWithType:UIButtonTypeCustom]; g_btnBuy.frame=CGRectMake(16,302,120,32);
    g_btnBuy.backgroundColor=[UIColor colorWithRed:0.2 green:0.6 blue:0.9 alpha:0.95];
    [g_btnBuy setTitle:@"\u8d2d\u4e70\u5546\u54c1" forState:UIControlStateNormal];
    g_btnBuy.layer.cornerRadius=6;
    [g_btnBuy addTarget:[YZR3ActionHandler shared] action:@selector(onBuy) forControlEvents:UIControlEventTouchUpInside];
    [g_panel addSubview:g_btnBuy];

    // IAP button
    g_btnIAP=[UIButton buttonWithType:UIButtonTypeCustom]; g_btnIAP.frame=CGRectMake(144,302,120,32);
    g_btnIAP.backgroundColor=[UIColor colorWithRed:0.8 green:0.3 blue:0.8 alpha:0.95];
    [g_btnIAP setTitle:@"IAP\u6a21\u62df" forState:UIControlStateNormal];
    g_btnIAP.layer.cornerRadius=6;
    [g_btnIAP addTarget:[YZR3ActionHandler shared] action:@selector(onIAP) forControlEvents:UIControlEventTouchUpInside];
    [g_panel addSubview:g_btnIAP];

    // Debug log
    g_debugLabel=[[UILabel alloc]initWithFrame:CGRectMake(8,344,pw-16,168)];
    g_debugLabel.textColor=[UIColor colorWithRed:0.2 green:1.0 blue:0.2 alpha:1.0];
    g_debugLabel.font=[UIFont fontWithName:@"Menlo" size:9]; g_debugLabel.numberOfLines=0;
    [g_panel addSubview:g_debugLabel];

    refreshButtons();
    ylog(@"UI setup done");
}

// ============================================================
// 入口
// ============================================================

__attribute__((constructor))
static void initialize(void) {
    static BOOL loaded = NO;
    if (loaded) { ylog(@"Already loaded, skip"); return; }
    loaded = YES;

    g_debugLines=[NSMutableArray new];
    ylog(@"========== YZR3 Hero3 Cheat v1.0 ==========");
    ylog(@"iOS %@", [[UIDevice currentDevice] systemVersion]);
    ylog(@"Bundle %@", [[NSBundle mainBundle] bundleIdentifier]);

    // 延迟5秒等IL2CPP运行时初始化完成
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(5.0*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        ylog(@"5s delay done, applying hooks...");
        applyAllHooks();

        // 等3秒后显示UI
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(3.0*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
            setupUI();
        });
    });
}
