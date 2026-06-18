# YZR3 Cheat - 英雄3 (Hero3) Game Mod

iOS Unity IL2CPP 游戏修改插件，基于 Dobby inline hook 框架。

参考 [jycheatv2](https://github.com/weihaiwh/jycheatv2) (剑影江湖) 架构。

## 功能

| 功能 | Hook目标 | 说明 |
|------|----------|------|
| 无CD | `CheckCanUseSkill` | 技能无冷却 |
| 伤害秒杀 | `get_limitDamage` | 伤害值可调 (100~999999) |
| 商店购买 | `PurchaseItem` | 直接调用购买方法 |
| IAP模拟 | `ApplePayOnSuccess` | 内购协议流程分析 |

## 目标游戏

- **游戏**: 英雄3 (Hero3)
- **Bundle**: `com.hero.yzr3.ios`
- **引擎**: Unity + IL2CPP (AOT)
- **平台**: iOS ARM64

## IL2CPP 方法签名 (dump.cs)

### 战斗相关
| 方法 | 类 | 签名 | 偏移 |
|------|-----|------|------|
| CheckCanUseSkill | SkillDataModule | `bool(int skillID)` | 0x343b04 |
| get_limitDamage | (待确认) | `int()` | - |

### 商店/IAP相关
| 方法 | 类 | 签名 | 偏移 |
|------|-----|------|------|
| PurchaseItem | ShopDataModule | `void(shopId,shopItemId,buyCount,IsShopJduge,freeScroll,heroID)` | 0x489128 |
| ReqShopInfo | ShopDataModule | `void(shopId, isRefresh)` | 0x349fb8 |
| InitIAP | SDKDataModule | `void()` | 0x348b50 |
| StartApplePay | SDKDataModule | `void(applicationUsername, productId)` | 0x34af60 |
| ApplePayOnSuccess | SDKDataModule | `void(receipt)` | 0x34a27c |
| SDKApplePayTransaction | SDKDataModule | `void(receipt)` | 0x34a27c |
| SendPayRequestGameServer | SDKDataModule | `void(shopId,shopItemMeta,method,count,heroId)` | 0x489128 |
| PurchaseProduct | (IAP) | `void(productId, applicationUsername)` | 0x34af60 |

### 商店协议 (Protobuf)
| 消息 | 字段 |
|------|------|
| GameMessage_PurchaseShopItem | shopId, shopItemId, buyNum, freeSlot, heroId |
| GameMessage_PurchaseShopItemRet | code, shopId, shopItemId, purchaseTimesUsed, items, rewards, heroId |
| NewSdkRechargeRequest | shopId, shopItemId, taType, amount, buyNum, reqtime, heroId, clientSdkDesc |
| NewSdkRechargeResponse | errorCode, transactionRequestInfo, taType |
| ApplePayVerifyIdTokenV1 | (Apple receipt verification) |

### 商店类型 (ShopDisplayType)
| 值 | 名称 | 说明 |
|----|------|------|
| 52 | YuanBao | 元宝商店 |
| 55 | DayBundle | 日礼包 |
| 56 | WeeklyBundle | 周礼包 |
| 57 | MonthlyBundle | 月礼包 |
| 58 | LifeBundle | 终身礼包 |
| 63 | TimeLimitSkin | 限时皮肤 |
| 65 | BeginnerGift | 新手礼包 |
| 66 | Fund | 基金 |

### IAP 流程
```
InitIAP → StartApplePay(username, productId)
  → [Apple StoreKit] → ApplePayOnSuccess(receipt)
  → SDKApplePayTransaction(receipt)
  → SendPayRequestGameServer(shopId, meta, method, count, heroId)
  → NewSdkRechargeRequest → Server → NewSdkRechargeResponse
```

## 构建

GitHub Actions 自动构建，push 到 main/master 分支自动触发。

也可手动触发 `workflow_dispatch`。

## 使用

1. 从 [Releases](https://github.com/weihaiwh/yzrcheat/releases) 下载 dylib
2. 注入目标应用 (巨魔/越狱)
3. 浮动球 🏹 点击展开面板

## 项目结构

```
yzrcheat/
├── .github/workflows/build.yml   # GitHub Actions 构建流程
├── YZR3_HeroCheat.m              # 主插件源码 (ObjC + Dobby hook)
├── YZR3_HeroCheat.plist          # 过滤器 (com.hero.yzr3.ios)
├── dobby.h                       # Dobby hook 框架头文件
└── README.md                     # 本文件
```
