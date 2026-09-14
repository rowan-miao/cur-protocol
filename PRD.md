# CUR Staking Protocol - 产品需求文档（PRD）

---

## 1. 文档信息与修订历史

| 版本 | 日期 | 修改章节 | 修改内容 | 修改人 | 审核人 |
|------|------|---------|---------|--------|--------|
| v1.0 | 2026-06-03 | 全部 | 初稿创建 | PM | Tech Lead |

---

## 2. 产品概述

### 2.1 产品定位

CUR Staking Protocol 是一个基于加权 Compound Index 模型的去中心化质押协议。用户质押 CUR 代币获得可交易的生息凭证 sCUR，通过锁仓承诺提升加权份额，NFT 仅用于解锁更高锁仓权限。

### 2.2 产品背景

- CUR 代币持有者缺乏稳定的生息渠道
- 现有质押协议存在流动性锁定问题
- 需要长期激励机制平衡短期投机与长期持有

### 2.3 目标用户

| 用户类型 | 特征 | 核心诉求 |
|---------|------|---------|
| CUR 持有者 | 持有 CUR 代币 | 获得稳定收益 |
| DeFi 收益追求者 | 活跃链上用户 | 追求高 APR |
| 长期投资者 | 信任协议价值 | 锁仓获得更高收益 |

### 2.4 核心价值主张

| 价值 | 说明 |
|------|------|
| 流动性 | sCUR 可自由交易，解决质押资产流动性问题 |
| 激励机制 | 锁仓加权机制激励长期质押 |
| 可持续性 | 奖励分发与协议收入分离 |
| 可组合性 | sCUR 可被其他 DeFi 协议集成 |

### 2.5 成功衡量指标（KPI）

| 指标 | 目标值（第1年） | 衡量方式 |
|------|-----------------|---------|
| TVL（总锁仓价值） | ≥ 1000万 CUR | 链上查询 |
| 活跃用户数 | ≥ 5000 | 事件统计 |
| 锁仓率 | ≥ 50% | 锁仓量/总质押量 |
| 目标 APR | 15-30% | 公式计算 |
| 协议收入 | ≥ 40万 CUR | 收入池统计 |

---

## 3. 名词术语表

### 3.1 代币相关

| 术语 | 定义 |
|------|------|
| CUR | 协议的原生治理和奖励代币 |
| sCUR | 流动性质押凭证，1:1 锚定底层 CUR |
| exchangeRate | sCUR 兑换 CUR 的汇率，随协议收入增长 |

### 3.2 合约相关

| 术语 | 定义 |
|------|------|
| CURStaking | 主质押合约，用户交互入口，负责 CUR 与 sCUR 的质押和赎回 |
| IncentiveGauge | 激励矿池合约，负责用户加权质押和 CUR 通胀奖励分发 |
| veCURLock | 锁仓加成管理器，负责锁仓状态、锁仓系数和提前解锁惩罚 |
| NFTChecker | NFT 权限验证器，负责验证 NFT 所有权及锁仓权限 |
| RevenueRebatePool | 协议收入反哺池，负责收集协议收入和罚没资金，并将 CUR 反哺至 CURStaking，同时更新 sCUR 兑换率 |

### 3.3 操作相关

| 术语 | 定义 |
|------|------|
| stake | 用户质押 CUR 获得 sCUR 的操作 |
| unstake | 用户销毁 sCUR 赎回 CUR 的操作 |
| enterGauge | 用户将 sCUR 存入激励矿池的操作 |
| exitGauge | 用户从激励矿池取出 sCUR 的操作 |
| lock | 用户锁定 sCUR 以获得加成系数的操作 |
| earlyUnlock | 用户在锁仓到期前提前解锁的操作 |
| getReward | 用户领取通胀奖励的操作 |

### 3.4 状态变量

| 术语 | 定义 |
|------|------|
| totalWeight | IncentiveGauge 中的全网总权重，Σ(User Weight) |
| rewardPerToken | 全局奖励指数，表示每个单位权重累积的奖励 |
| rewardPerTokenPaid | 用户上次记录的奖励指数 |
| pendingRewards | 用户待领取的 CUR 奖励 |
| emissionRate | 每秒释放的 CUR 数量，随时间递减 |
| totalUnderlying | sCUR 合约持有的底层 CUR 总量 |
| bonusFactor | 锁仓加成系数（1.15x ~ 2.50x） |
| depositedGauge | 用户在矿池中的 sCUR 数量 |
| penalty | 提前解锁时被罚没的 sCUR 数量 |


### 3.5 技术常数

| 术语 | 定义 |
|------|------|
| PRECISION | 精度常数（1e18），用于固定点运算 |
| PENALTY_RATE | 惩罚率常数（5000），表示 50% |

---

## 4. 需求优先级与分期规划

### 4.1 优先级定义

| 优先级 | 说明 |
|--------|------|
| P0 | 必须实现，第1期上线 |
| P1 | 重要功能，第1期或第2期 |
| P2 | 锦上添花，可延后 |

### 4.2 分期规划

| 模块 | 功能 | 优先级 | 计划迭代 | 依赖 |
|------|------|--------|---------|------|
| 基础质押 | stake / unstake | P0 | 第1期 | CURToken, sCUR |
| 质押凭证 | sCUR 1:1 铸造 / 销毁及本金锚定 | P0 | 第1期 | CURToken, CURStaking, sCUR |
| 通胀奖励 | IncentiveGauge | P0 | 第1期 | sCUR, CURStaking |
| 锁仓加成 | veCURLock | P1 | 第1期 | CURStaking |
| NFT 权限 | NFTChecker | P2 | 第2期 | veCURLock |
| 收入反哺 | RevenueRebatePool | P1 | 第1期 | sCUR，CURStaking |

---

## 5. 功能详述

### 5.1 流动性质押凭证（sCUR）

#### 5.1.1 功能描述

sCUR 是生息质押凭证，代表用户质押的 CUR 份额，汇率随协议收入增长。

#### 5.1.2 函数规格

**mint(address to, uint256 CURAmount)**

| 项目 | 说明 |
|------|------|
| 功能 | 铸造 sCUR（仅 CURStaking 可调用） |
| 参数 | `to` : 接收地址<br>`CURAmount` : 质押的 CUR 数量 |
| 返回 | `sCURAmount` : 铸造的 sCUR 数量 |
| 权限 | 仅 Minter（CURStaking）|
| 异常 | `ZeroAddress`: to 为 0 <br> `ZeroAmount`: CURAmount == 0 |
| 事件 | `Mint(address indexed to, uint256 CURAmount, uint256 sCURAmount)` |

**redeem(address from, uint256 sCURAmount)**

| 项目 | 说明 |
|------|------|
| 功能 | 销毁 sCUR，释放 CUR（仅 CURStaking 可调用） |
| 参数 | `from` : 持有者地址 <br>`sCURAmount` : 销毁数量 |
| 返回 | `CURAmount` : 释放的 CUR 数量 |
| 权限 | 仅 Minter（CURStaking）|
| 异常 | `ZeroAddress`: from 为 0<br>`ZeroAmount`: sCURAmount == 0 |
| 事件 | `Redeem(address indexed from, uint256 CURAmount, uint256 sCURAmount)` |

**updateExchangeRate(uint256 additionalCUR)**

| 项目 | 说明 |
|------|------|
| 功能 | 协议收入注入，更新汇率（仅 RevenueRebatePool 可调用） |
| 参数 | `additionalCUR` : 注入的 CUR 数量 |
| 返回 | `newRate` : 新汇率 |
| 权限 | 仅 Minter（RevenueRebatePool）|
| 异常 | `ZeroAmount`: additionalCUR == 0<br>`ExchangeRateCannotDecrease`: 汇率不能下降 |
| 事件 | `UpdateExchangeRate(uint256 oldRate, uint256 newRate)` |

#### 5.1.3 业务规则

- 汇率更新公式：`exchangeRate_new = totalUnderlying × PRECISION / totalSupply(sCUR)`
- 汇率只升不降，仅由协议收入驱动

### 5.2 主质押合约（CURStaking）

#### 5.2.1 功能描述

用户质押入口，管理 CUR ↔ sCUR 兑换，与矿池交互。

#### 5.2.2 函数规格

**stake(uint256 CURAmount)**

| 项目 | 说明 |
|------|------|
| 功能 | 用户质押 CUR，获取 sCUR |
| 参数 | `CURAmount` : 质押的 CUR 数量 |
| 返回 | `sCURAmount` : 获得的 sCUR 数量 |
| 异常 | `ZeroAmount`: CURAmount == 0<br>`InsufficientAmount`: 余额不足 |
| 事件 | `Staked(address indexed user, uint256 CURAmount, uint256 sCURAmount)` |
| 权限 | 公开 |

**unstake(uint256 sCURAmount)**

| 项目 | 说明 |
|------|------|
| 功能 | 销毁 sCUR，赎回 CUR |
| 参数 | `sCURAmount` : 赎回的 sCUR 数量 |
| 返回 | `CURAmount` : 获得的 CUR 数量 |
| 异常 | `ZeroAmount`: sCURAmount == 0<br>`InsufficientFreeSCUR`: 可用 sCUR 不足<br>`InsufficientBalance`: 合约余额不足 |
| 事件 | `UnStaked(address indexed user, uint256 sCURAmount, uint256 CURAmount)` |
| 权限 | 公开 |

**enterGauge(uint256 sCURAmount)**

| 项目 | 说明 |
|------|------|
| 功能 | 将 sCUR 存入激励矿池 |
| 参数 | `sCURAmount` : 存入数量 |
| 异常 | `ZeroAmount`: sCURAmount == 0<br>`InsufficientAmount`: 可用 sCUR 不足 |
| 事件 | `EnterGauge(address indexed user, uint256 sCURAmount)` |
| 权限 | 公开 |

**exitGauge(uint256 sCURAmount)**

| 项目 | 说明 |
|------|------|
| 功能 | 从激励矿池取出 sCUR |
| 参数 | `sCURAmount` : 取出数量 |
| 异常 | `ZeroAmount`: sCURAmount == 0<br>`InsufficientAmount`: 矿池余额不足 |
| 事件 | `ExitGauge(address indexed user, uint256 sCURAmount)` |
| 权限 | 公开 |

### 5.3 激励矿池（IncentiveGauge）

#### 5.3.1 功能描述

用户将 sCUR 存入矿池参与权重竞争，权重基于锁仓系数，可获得 CUR 通胀奖励。

#### 5.3.2 函数规格

**deposit(address user, uint256 amount)**

| 项目 | 说明 |
|------|------|
| 功能 | 将 sCUR 存入矿池 |
| 参数 | `user` : 用户地址，`amount` : 存入数量 |
| 权限 | 仅 `CURStaking` 可调用 |
| 异常 | `ZeroAmount`: amount == 0<br>`Unauthorized`: 调用者非 CURStaking |

**withdraw(address user, uint256 amount)**

| 项目 | 说明 |
|------|------|
| 功能 | 从矿池取出 sCUR |
| 参数 | `user` : 用户地址，`amount` : 取出数量 |
| 权限 | 仅 `CURStaking` 可调用 |
| 异常 | `ZeroAmount`: amount == 0<br>`InsufficientAmount`: 矿池余额不足 |

**getReward()**

| 项目 | 说明 |
|------|------|
| 功能 | 领取待领取的 CUR 奖励 |
| 权限 | 公开（仅用户本人） |
| 异常 | `ZeroReward`: 无奖励可领取 |

#### 5.3.3 业务规则

- 奖励指数更新：`rewardPerToken += (emissionRate × Δt × PRECISION) / totalWeight`
- 用户奖励：`pending += userWeight × (rewardPerToken - userRewardPerTokenPaid) / PRECISION`
- 释放速率随时间递减（4年计划）

### 5.4 锁仓加成（veCURLock）

#### 5.4.1 加权规则

| 锁仓时长 | 加成系数 | NFT 权限 |
|---------|---------|---------|
| 30天 | 1.15x | 无门槛 |
| 90天 | 1.35x | 无门槛 |
| 180天 | 1.65x | 无门槛 |
| 365天 | 2.00x | 中级 NFT |
| 730天 | 2.50x | 高级 NFT |

#### 5.4.2 函数规格

**lock(uint256 duration)**

| 项目 | 说明 |
|------|------|
| 功能 | 用户锁仓，获得加权权重 |
| 参数 | `duration` : 锁仓时长（秒） |
| 异常 | `InvalidDuration`: 时长无效<br> `DurationExceedsPermission`: 超出 NFT 权限<br>`AlreadyLocked`: 已锁仓 |
| 事件 | `Locked(address indexed user, uint256 duration, uint256 bonusFactor, uint256 endTime)` |

**unlock()**

| 项目 | 说明 |
|------|------|
| 功能 | 用户正常解锁 |
| 异常 | `NotLocked`: 未锁仓<br> `NotExpired`: 锁仓时限未到|
| 事件 | `Unlocked(address indexed user, uint256 amount);` |

**earlyUnlock()**

| 项目 | 说明 |
|------|------|
| 功能 | 提前解锁，执行惩罚 |
| 异常 | `NotLocked`: 未锁仓<br>`AlreadyExpired`: 已到期 |
| 事件 | `EarlyUnlocked(address indexed user, uint256 amount, uint256 penalty)` |

**bindNFT(address nftContract, uint256 tokenId)**

| 项目 | 说明 |
|------|------|
| 功能 | 绑定 NFT 获取锁仓权限 |
| 参数 | `nftContract` : NFT 合约地址<br>`tokenId` : NFT ID |
| 权限 | 公开 |
| 异常 | `NotNFTOwner`: 不是 NFT 持有者<br>`AlreadyBound`: NFT 已被绑定 |
| 事件 | `NFTBound(address indexed user, address indexed nftContract, uint256 tokenId, uint8 tier)` |

**unbindNFT()**

| 项目 | 说明 |
|------|------|
| 功能 | 解绑 NFT |
| 权限 | 公开 |
| 异常 | `NotBound`: 未绑定 NFT |
| 事件 | `NFTUnbound(address indexed user)` |

**getBonus(address user)**

| 项目 | 说明 |
|------|------|
| 功能 | 获取用户当前加成系数 |
| 返回 | `bonusFactor` - 加成系数（1e18 = 1.0x）|
| 权限 | 公开（view）|

#### 5.4.3 惩罚公式

 > penalty = amount × 50% × (剩余锁仓天数 / 总锁仓天数)


- 本金罚没：销毁 penalty 数量的 sCUR
- 收益罚没：未领取的 CUR 奖励转入收入池

---

### 5.5 NFT 权限验证器（NFTChecker）

#### 5.5.1 功能描述

管理 NFT 白名单，验证用户 NFT 持有情况，提供锁仓权限等级。

#### 5.5.2 函数规格

**addWhitelistedContract(address nftContract, uint8 tier)**

| 项目 | 说明 |
|------|------|
| 功能 | 添加 NFT 合约到白名单 |
| 参数 | `nftContract` : NFT 合约地址<br>`tier` : 等级（1=中级，2=高级）|
| 权限 | 仅 Owner |
| 异常 | `ZeroAddress`: 地址为 0<br>`InvalidTier`: 等级无效 |
| 事件 | `ContractWhiteListed(address indexed nftContract, uint8 tier)` |

**removeWhitelistedContract(address nftContract)**

| 项目 | 说明 |
|------|------|
| 功能 | 从白名单移除 NFT 合约 |
| 参数 | `nftContract` : NFT 合约地址 |
| 权限 | 仅 Owner |
| 异常 | `NotWhitelisted`: 合约不在白名单中 |
| 事件 | `ContractRemove(address indexed nftContract)` |

**bindNFT(address nftContract, uint256 tokenId)**

| 项目 | 说明 |
|------|------|
| 功能 | 用户绑定 NFT 到账户 |
| 参数 | `nftContract` : NFT 合约地址<br>`tokenId` : NFT ID |
| 权限 | 公开 |
| 异常 | `NotWhitelisted`: NFT 不在白名单<br>`UserAlreadyBound`: 用户已绑定<br>`NFTAlreadyBound`: NFT 已被绑定<br>`NotOwner`: 用户不是 NFT 持有者 |
| 事件 | `NFTBound(address indexed user, address indexed nftContract, uint256 tokenId, uint8 tier)` |

**unbindNFT()**

| 项目 | 说明 |
|------|------|
| 功能 | 用户解绑 NFT |
| 权限 | 公开 |
| 异常 | `NoBinding`: 用户未绑定 NFT |
| 事件 | `NFTUnbound(address indexed user)` |

**getMaxLockDays(address user)**

| 项目 | 说明 |
|------|------|
| 功能 | 获取用户最大可锁仓天数 |
| 返回 | `maxDays` : 最大锁仓天数（180/365/730）|
| 权限 | 公开（view）|

---

### 5.6 收入反哺池（RevenueRebatePool）

#### 5.6.1 功能描述

收集协议收入，定期注入 sCUR 池提升汇率。

#### 5.6.2 函数规格

**depositRevenue(uint256 amount)**

| 项目 | 说明 |
|------|------|
| 功能 | 存入协议收入 |
| 参数 | `amount` : 存入的 CUR 数量 |
| 权限 | 公开（协议收入来源）|
| 异常 | `ZeroAmount`: amount == 0 |
| 事件 | `RevenueDeposited(address indexed user, uint256 amount)` |


**injectToSCUR(uint256 amount)**

| 项目 | 说明 |
|------|------|
| 功能 | 将收入注入 sCUR 池 |
| 参数 | `amount` : 注入的 CUR 数量 |
| 权限 | 仅 Owner |
| 异常 | `ZeroAmount`: amount == 0<br>`ExceedsRevenue`: 超过累计收入<br>`InsufficientBalance`: 合约余额不足 |
| 事件 | `RevenueInjected(uint256 amount)` |

**injectAll()**

| 项目 | 说明 |
|------|------|
| 功能 | 注入全部累计收入 |
| 权限 | 仅 Owner |
| 异常 | `BelowThreshold`: 低于阈值 |
| 事件 | `RevenueInjectedAll(uint256 amount)` |


**setThreshold(uint256 newThreshold)**

| 项目 | 说明 |
|------|------|
| 功能 | 设置自动注入阈值 |
| 参数 | `newThreshold` : 新阈值 |
| 权限 | 仅 Owner |
| 事件 | `ThresholdUpdated(uint256 newthreshold)` |


---



## 6. 验收标准（Acceptance Criteria）

### 6.1 质押功能（Stake）

```gherkin
Scenario: 用户成功质押 CUR
  Given 用户 alice 有 1000 CUR 余额
  And  用户 alice 已授权合约使用 1000 CUR
  When 用户 alice 调用 stake(1000)
  Then 用户 alice 收到 1000 sCUR（初始汇率 1:1）
  And CURStaking 合约 CUR 余额增加 1000
  And 用户 alice 的 stakedSCUR = 1000
  And 触发 Staked(alice, 1000, 1000)

Scenario: 用户质押数量为 0
  Given 用户 alice 有 1000 CUR 余额
  When 用户 alice 调用 stake(0)
  Then 交易回滚，错误 ZeroAmount

Scenario: 用户余额不足
  Given 用户 alice 有 500 CUR 余额
  When 用户 alice 调用 stake(1000)
  Then 交易回滚，错误 InsufficientAmount

Scenario: 用户未授权合约
  Given 用户 alice 有 1000 CUR 余额
  And  用户 alice 未授权合约使用 CUR
  When 用户 alice 调用 stake(1000)
  Then 交易回滚

Scenario: 汇率变化后质押
  Given 用户 alice 有 1000 CUR 余额
  And  当前汇率为 1.2（1 sCUR = 1.2 CUR）
  When 用户 alice 调用 stake(1200)
  Then 用户 alice 收到 1000 sCUR
  And  触发 Staked(alice, 1200, 1000) 事件
```

### 6.2 赎回功能（Unstake）

```gherkin
Scenario: 用户成功赎回 CUR
  Given 用户 alice 已质押 1000 CUR
  And 用户 alice 持有 1000 sCUR
  And 用户 alice 没有将 sCUR 存入 Gauge
  And sCUR 汇率为 1:1
  When 用户 alice 调用 unstake(1000)
  Then 用户 alice 的 sCUR 被销毁
  And 用户 alice 收到 1000 CUR
  And 用户 alice 的 stakedSCUR = 0
  And 触发 UnStaked(alice,1000,1000)
  And 触发 Redeem(alice,1000,1000)

Scenario: 赎回数量为 0
  Given 用户 alice 已质押 1000 CUR
  When 用户 alice 调用 unstake(0)
  Then 交易回滚，错误 ZeroAmount

Scenario: 赎回数量超过可用 sCUR
  Given 用户 alice 已质押 1000 CUR
  And  用户 alice 已将 600 sCUR 存入矿池
  When 用户 alice 调用 unstake(500)
  Then 交易回滚，错误 InsufficientFreeSCUR

Scenario: 合约 CUR 余额不足
  Given 用户 alice 已质押 1000 CUR
  And  合约 CUR 余额为 500
  When 用户 alice 调用 unstake(1000)
  Then 交易回滚，错误 InsufficientBalance

Scenario: 汇率变化后赎回
  Given 用户 alice 已质押 1000 CUR（获得 1000 sCUR）
  And  当前汇率为 1.5（1 sCUR = 1.5 CUR）
  And  合约有足够 CUR 余额
  When 用户 alice 调用 unstake(1000)
  Then 用户 alice 收到 1500 CUR
  And  触发 UnStaked(alice, 1000, 1500) 事件
```

### 6.3 进入矿池（enterGauge）

```gherkin
Scenario: 用户成功进入矿池
  Given 用户 alice 已质押 1000 CUR
  And  用户 alice 持有 1000 sCUR
  And  用户 alice 未存入矿池
  When 用户 alice 调用 enterGauge(600)
  Then 用户 alice 的 depositedGauge = 600
  And  触发 EnterGauge(alice, 600) 事件

Scenario: 进入矿池数量为 0
  Given 用户 alice 已质押 1000 CUR
  When 用户 alice 调用 enterGauge(0)
  Then 交易回滚，错误 ZeroAmount

Scenario: 进入矿池数量超过可用 sCUR
  Given 用户 alice 已质押 1000 CUR
  When 用户 alice 调用 enterGauge(1500)
  Then 交易回滚，错误 InsufficientAmount

Scenario: 用户多次进入矿池
  Given 用户 alice 已质押 1000 CUR
  When 用户 alice 调用 enterGauge(400)
  And  用户 alice 调用 enterGauge(300)
  Then 用户 alice 的 depositedGauge = 700
```

### 6.4 退出矿池（exitGauge）
```gherkin
Scenario: 用户成功退出矿池
  Given 用户 alice 已质押 1000 CUR
  And  用户 alice 已存入矿池 600 sCUR
  When 用户 alice 调用 exitGauge(600)
  Then 用户 alice 的 depositedGauge = 0
  And  触发 ExitGauge(alice, 600) 事件

Scenario: 退出矿池数量为 0
  Given 用户 alice 已存入矿池 600 sCUR
  When 用户 alice 调用 exitGauge(0)
  Then 交易回滚，错误 ZeroAmount

Scenario: 退出数量超过矿池余额
  Given 用户 alice 已存入矿池 600 sCUR
  When 用户 alice 调用 exitGauge(800)
  Then 交易回滚，错误 InsufficientAmount

Scenario: 用户部分退出矿池
  Given 用户 alice 已存入矿池 600 sCUR
  When 用户 alice 调用 exitGauge(250)
  Then 用户 alice 的 depositedGauge = 350
```

### 6.5 锁仓功能（Lock）

```gherkin
Scenario: 用户成功锁仓 30 天
  Given 用户 alice 在矿池中有 1000 sCUR
  And  用户 alice 持有 1000 sCUR
  When 用户 alice 调用 lock(30 days)
  Then 用户 alice 的锁仓状态变为已锁仓
  And  用户 alice 的加成系数为 1.15e18
  And  用户 alice 的锁仓结束时间为 startTime + 30 days
  And  totalLocked 增加 1000
  And  触发 Locked(alice, 30 days, 1.15e18, endTime) 事件
  And  incentiveGauge.executeLock 被调用，传入 (alice, 1000, 1.15e18)

Scenario: 用户成功锁仓 90 天
  Given 用户 alice 在矿池中有 1000 sCUR
  When 用户 alice 调用 lock(90 days)
  Then 用户 alice 的加成系数为 1.35e18

Scenario: 用户成功锁仓 180 天
  Given 用户 alice 在矿池中有 1000 sCUR
  When 用户 alice 调用 lock(180 days)
  Then 用户 alice 的加成系数为 1.65e18

Scenario: 用户成功锁仓 365 天（持有中级 NFT）
  Given 用户 alice 在矿池中有 1000 sCUR
  And  用户 alice 持有中级 NFT（tier = 1）
  When 用户 alice 调用 lock(365 days)
  Then 用户 alice 的加成系数为 2.00e18

Scenario: 用户成功锁仓 730 天（持有高级 NFT）
  Given 用户 alice 在矿池中有 1000 sCUR
  And  用户 alice 持有高级 NFT（tier = 2）
  When 用户 alice 调用 lock(730 days)
  Then 用户 alice 的加成系数为 2.50e18

Scenario: 锁仓时长无效
  Given 用户 alice 在矿池中有 1000 sCUR
  When 用户 alice 调用 lock(1 days)
  Then 交易回滚，错误 InvalidDuration

Scenario: 用户锁仓时长超出 NFT 权限
  Given 用户 alice 在矿池中有 1000 sCUR
  And  用户 alice 没有绑定任何 NFT
  When 用户 alice 调用 lock(365 days)
  Then 交易回滚，错误 DurationExceedsPermission

Scenario: 用户已锁仓，再次锁仓
  Given 用户 alice 已锁仓 1000 sCUR 30 天
  When 用户 alice 调用 lock(30 days)
  Then 交易回滚，错误 AlreadyLocked

Scenario: 用户在矿池中没有 sCUR
  Given 用户 alice 在矿池中有 0 sCUR
  When 用户 alice 调用 lock(30 days)
  Then 交易回滚，错误 ZeroSCUR
```

### 6.6 正常解锁（unlock）

```gherkin
Scenario: 用户成功正常解锁
  Given 用户 alice 已锁仓 1000 sCUR 30 天
  And  锁仓已到期（时间已过 30 天）
  When 用户 alice 调用 unlock()
  Then 用户 alice 的锁仓状态变为未锁仓
  And  totalLocked 减少 1000
  And  触发 Unlocked(alice, 1000) 事件
  And  incentiveGauge.executeUnlock 被调用，传入 (alice, 1000, bonusFactor)
  And  NFT 绑定被释放（如果有）

Scenario: 用户尝试在锁仓到期前正常解锁
  Given 用户 alice 已锁仓 1000 sCUR 30 天
  And  锁仓仅过了 15 天
  When 用户 alice 调用 unlock()
  Then 交易回滚，错误 NotExpired

Scenario: 用户未锁仓时调用解锁
  Given 用户 alice 没有锁仓
  When 用户 alice 调用 unlock()
  Then 交易回滚，错误 NotLocked

```
### 6.7 提前解锁（earlyUnlock）

```gherkin
Scenario: 用户成功提前解锁（产生惩罚）
  Given 用户 alice 已锁仓 1000 sCUR 30 天
  And  锁仓已过 15 天
  When 用户 alice 调用 earlyUnlock()
  Then 用户 alice 的锁仓状态变为未锁仓
  And  totalLocked 减少 1000
  And  计算惩罚金额
  And  触发 EarlyUnlocked(alice, 1000, penalty) 事件
  And  incentiveGauge.executeEarlyUnlock 被调用，传入 (alice, 1000, bonusFactor, penalty)

Scenario: 用户提前解锁时锁仓已到期
  Given 用户 alice 已锁仓 1000 sCUR 30 天
  And  锁仓已到期（时间已过 30 天）
  When 用户 alice 调用 earlyUnlock()
  Then 交易回滚，错误 AlreadyExpired

Scenario: 用户未锁仓时调用提前解锁
  Given 用户 alice 没有锁仓
  When 用户 alice 调用 earlyUnlock()
  Then 交易回滚，错误 NotLocked

Scenario: 惩罚金额计算正确
  Given 用户 alice 锁仓 1000 sCUR 30 天
  And  锁仓剩余 15 天
  When 用户 alice 调用 earlyUnlock()
  Then 惩罚金额 = 1000 × 50% × (15/30) = 250 sCUR
```




### 6.8 领取奖励（GetReward）

```gherkin
Scenario: 用户成功领取奖励
  Given 用户 alice 在矿池中有 1000 sCUR（权重 1000）
  And  时间过去 100 天，产生 500 CUR 奖励
  And  用户 alice 应得奖励 100 CUR
  And  用户 alice 的待领取奖励 pendingRewards = 100
  When 用户 alice 调用 getReward()
  Then 用户 alice 收到 100 CUR
  And  用户 alice 的 pendingRewards 变为 0
  And  触发 GetReward(alice, 100) 事件

Scenario: 用户无奖励可领取
  Given 用户 alice 从未参与质押
  When 用户 alice 调用 getReward()
  Then 交易回滚，错误 ZeroReward

Scenario: 用户奖励已被领完，再次领取
  Given 用户 alice 有 100 CUR 待领取奖励
  When 用户 alice 调用 getReward() 领取奖励
  And  用户 alice 再次调用 getReward()
  Then 第二次调用交易回滚，错误 ZeroReward

Scenario: 多个用户分别领取奖励
  Given 用户 alice 应得奖励 100 CUR
  And  用户 bob 应得奖励 200 CUR
  When 用户 alice 调用 getReward()
  And  用户 bob 调用 getReward()
  Then 用户 alice 收到 100 CUR
  And  用户 bob 收到 200 CUR
```
---

## 7.数据结构

### 7.1 CURStaking 

**用户信息**

```solidity
struct UserInfo {
    uint256 stakedSCUR;     // 用户持有的 sCUR 总量
    uint256 depositedGauge; // 用户在矿池中的 sCUR 数量
}
mapping(address => UserInfo) public users;
```

### 7.2 IncentiveGauge 

**用户信息**

```solidity
struct UserInfo {
    uint256 amount;                 // 用户质押的 sCUR 数量
    uint256 weight;                 // 用户加权权重
    uint256 rewardPerTokenPaid;     // 用户上次记录的奖励指数
    uint256 pendingRewards;         // 待领取奖励
}
mapping(address => UserInfo) public users;
```

**全局状态**

```solidity
uint256 public startTime;           // 合约部署时间
uint256 public rewardPerToken;      // 累计奖励指数
uint256 public lastUpdateTime;      // 上次更新时间
uint256 public emissionRate;        // 当前释放速率
uint256 public totalWeight;         // 全网总权重
```

**通胀释放常量**

```solidity
uint256 public constant EMISSION_RATE_Y1 = (15_000_000 * 1e18) / SECONDS_PER_YEAR;
uint256 public constant EMISSION_RATE_Y2 = (12_000_000 * 1e18) / SECONDS_PER_YEAR;
uint256 public constant EMISSION_RATE_Y3 = (8_000_000 * 1e18) / SECONDS_PER_YEAR;
uint256 public constant EMISSION_RATE_Y4 = (5_000_000 * 1e18) / SECONDS_PER_YEAR;
```


### 7.3 veCURLock

**锁仓信息**

```solidity
struct LockInfo {
    uint256 amount;         // 锁仓的 sCUR 数量
    uint256 startTime;      // 开始时间
    uint256 endTime;        // 结束时间
    uint256 duration;       // 锁仓时长
    uint256 bonusFactor;    // 加成系数
    bool isLocked;          // 是否在锁仓中
}
mapping(address => LockInfo) public locks;
```

**NFT 绑定信息**

```solidity
struct NFTBinding {
    address nftContract;    // NFT 合约地址
    uint256 tokenId;        // NFT ID
    uint8 tier;             // NFT 等级
    bool isBound;           // 是否绑定
}
mapping(address => NFTBinding) public nftBindings;
mapping(address => mapping(uint256 => bool)) public isNFTBound;
```

**锁仓时间与加成系数**

```solidity
// 锁仓时长常量
uint256 public constant DURATION_30 = 30 days;
uint256 public constant DURATION_90 = 90 days;
uint256 public constant DURATION_180 = 180 days;
uint256 public constant DURATION_365 = 365 days;
uint256 public constant DURATION_730 = 730 days;

// 加成系数常量
uint256 public constant BONUS_30 = 1.15se18;
uint256 public constant BONUS_90 = 1.35e18;
uint256 public constant BONUS_180 = 1.65e18;
uint256 public constant BONUS_365 = 2.00e18;
uint256 public constant BONUS_730 = 2.50e18;
```

### 7.4 NFTChecker

**数据结构**

```solidity
struct UserBinding {
  address nftContract;
  uint256 tokenId;
  uint8 tier;
  uint256 bindTime;
  bool isBound;
}
mapping(address => bool) public whitelistedContracts;
mapping(address => uint8) public contractTiers;
mapping(address => UserBinding) public userBindings;
mapping(address => mapping(uint256 => bool)) public nftBound;
address[] public whitelistedContractsList;
```

**常量**

```solidity
uint8 public constant TIER_NONE = 0;
uint8 public constant TIER_MID = 1;
uint8 public constant TIER_HIGH = 2;
```


### 7.5 RevenueRebatePool

**状态变量**

```solidity
uint256 public totalRevenue;    // 累计待注入收入
uint256 public threshold;       // 自动注入阈值
```

### 7.6 sCUR 核心状态

```solidity
uint256 public currentExchangeRate;  // 当前汇率
uint256 public totalUnderlying;      // 底层 CUR 总量
mapping(address => bool) public minters;  // 授权铸造者
```

### 7.7 精度常数（通用）

```solidity
uint256 public constant PRECISION = 1e18;           // 固定点运算精度
uint256 public constant PENALTY_RATE = 5000;        // 惩罚率 50%
uint256 public constant SECONDS_PER_YEAR = 365 days; // 一年秒数
```

---

## 8. 业务规则与公式

### 8.1 sCUR 兑换率公式

#### 8.1.1 当前兑换率

$$
exchangeRate = \frac{totalUnderlying \times PRECISION}{totalSupply(sCUR)}
$$

**参数说明：**

| 参数 | 说明 |
|------|------|
| `totalUnderlying` | sCUR 合约记录的底层 CUR 价值总量，用于兑换率计算 |
| `totalSupply(sCUR)` | sCUR 总供应量 |
| `PRECISION` | 精度常数（1e18） |


#### 8.1.2 Stake（质押）

用户质押 CUR 时：

$$
sCURMinted = \frac{CURAmount \times PRECISION}{exchangeRate}
$$

#### 8.1.3 Unstake（赎回）

用户赎回时：

$$
CURReturned = \frac{sCURAmount \times exchangeRate}{PRECISION}
$$

#### 8.1.4 兑换率增长

#### 8.1.4 兑换率增长

当 RevenueRebatePool 将收益 CUR 注入协议时：

1. RevenueRebatePool 将真实 CUR 转入 CURStaking。
2. CURStaking 的实际 CUR 资产增加。
3. 调用 sCURToken.updateExchangeRate(amount)。
4. sCUR 的 totalUnderlying 增加 amount。
5. sCUR 总供应量保持不变。
6. exchangeRate 相应提高。

因此：

- CUR 的实际资产始终由 CURStaking 持有。
- sCUR 仅更新底层资产 accounting，不接收真实 CUR。
- 在 totalSupply(sCUR) > 0 的情况下，正常收益注入不会降低 exchangeRate。

#### 8.1.5 底层资产流转

用户 Stake：

用户
  │
  │ CUR
  ▼
CURStaking
  │
  │ mint
  ▼
用户获得 sCUR


Revenue 注入：

RevenueRebatePool
  │
  │ CUR
  ▼
CURStaking
  │
  │ updateExchangeRate(amount)
  ▼
sCUR accounting
  │
  ▼
exchangeRate ↑


用户 Unstake：

用户
  │
  │ sCUR
  ▼
sCUR accounting
  │
  │ burn
  ▼
sCUR supply ↓

CURStaking
  │
  │ CUR
  ▼
用户

### 8.2 用户权重公式

#### 8.2.1 基础权重（进入矿池）

用户进入 IncentiveGauge 后：

$$
BaseWeight = GaugeAmount
$$

即：`1 sCUR = 1 Weight`


#### 8.2.2 锁仓加成权重

用户锁仓后：

$$
Weight = GaugeAmount \times BonusFactor
$$

**加成系数表：**

| 锁仓时长 | 加成系数（BonusFactor） |
|---------|----------------------|
| 30天 | 1.15 |
| 90天 | 1.35 |
| 180天 | 1.65 |
| 365天 | 2.00 |
| 730天 | 2.50 |

**示例：**

$$
\begin{aligned}
GaugeAmount &= 1000 \text{ sCUR} \\
锁仓时长 &= 180 \text{ 天} \\
BonusFactor &= 1.65 \\
Weight &= 1000 \times 1.65 = 1650
\end{aligned}
$$


#### 8.2.3 全网总权重

$$
TotalWeight = \sum_{i} Weight_i
$$

该变量维护于：

```solidity
IncentiveGauge.totalWeight
```

### 8.3 奖励释放公式

协议采用固定排放模型：

$$
RewardEmission = EmissionRate \times \Delta t
$$

其中：

$$
\Delta t = block.timestamp - lastUpdateTime
$$


**释放速率：**

| 年份 | CUR / 年 |
|------|----------|
| Year1 | 15,000,000 |
| Year2 | 12,000,000 |
| Year3 | 8,000,000 |
| Year4 | 5,000,000 |

每秒释放速率：
$$
EmissionRate_y = \frac{Allocation_y}{365 \times 24 \times 3600}
$$

其中 `365 × 24 × 3600 = 31,536,000` 秒（一年的秒数）


### 8.4 Reward Per Token 模型

**全局奖励指数：**

$$
rewardPerToken
$$

**更新公式：**

$$
rewardPerToken \mathrel{+}= \frac{EmissionRate \times \Delta t \times PRECISION}{totalWeight}
$$

对应代码：

```solidity
rewardPerToken += (rewardAdded * PRECISION) / totalWeight;
```

其中：

$$
rewardAdded = EmissionRate \times \Delta t
$$



### 8.5 用户奖励公式

**用户奖励：**

$$
PendingReward \mathrel{+}= \frac{Weight \times (rewardPerToken - rewardPerTokenPaid)}{PRECISION}
$$

对应代码：

```solidity
pending = weight * ( rewardPerToken - rewardPerTokenPaid ) / PRECISION;
```

**用户领取奖励：**

$$
ClaimReward = PendingReward
$$

领取后：

$$
PendingReward = 0 
$$

对应代码：
```solidity
userInfo.pendingRewards = 0;
curToken.transfer(msg.sender, reward);
```


### 8.6 提前解锁罚没公式

**剩余锁仓比例：**

$$
RemainingRatio = \frac{RemainingTime}{LockDuration}
$$

其中：

- `RemainingTime`：剩余锁仓时间（秒）
- `LockDuration`：总锁仓时间（秒）


罚没本金：

$$
Penalty = GaugeAmount \times 50\% \times RemainingRatio
$$

即：

$$
Penalty = \frac{GaugeAmount \times 5000 \times RemainingTime}{LockDuration \times 10000}
$$

使用 `5000` 表示 `50\%`（因为 `5000 / 10000 = 50\%`）：


### 8.7 提前解锁后的权重重置

**提前解锁后：**

$$
BonusFactor = 1.00x
$$


用户权重重置：

$$
Weight = RemainingGaugeAmount
$$

其中：

$$
RemainingGaugeAmount = GaugeAmount - Penalty
$$



### 8.8 奖励罚没规则

提前解锁时：

$$
PendingReward = 0
$$

所有未领取奖励转入收入池：

$$
PendingReward \rightarrow RevenueRebatePool
$$

对应代码：

```solidity
curToken.transfer(address(revenueRebatePool), pendingReward);
```


## 9. 非功能需求
### 9.1 安全要求

| 要求  |  实现方式 |
| ------------ | ------------ |
|  防重入攻击 |  `ReentrancyGuard` |
|  权限控制 | `Ownable`, `onlyMinter`  |
|  紧急暂停 | `Pausable`  |
|  防时间操纵 | `rewardPerToken` 累积模型  |
|  防除零错误  | 条件判断 + 精度处理  |

---

## 10. 边界条件与异常处理

### 10.1 错误类型汇总

| 错误类型 | 触发场景 | 处理方式 |
|---------|---------|---------|
| `ZeroAmount` | 输入数量为 0 | `revert` |
| `ZeroAddress` | 传入零地址 | `revert` |
| `InsufficientAmount` | 余额不足 | `revert` |
| `InsufficientFreeSCUR` | 赎回矿池中的 sCUR | `revert` |
| `InsufficientBalance` | 合约 CUR 余额不足 | `revert` |
| `Unauthorized` | 非授权合约调用 | `revert` |
| `InsufficientWeight` | 权重不足 | `revert` |
| `ZeroReward` | 无奖励可领取 | `revert` |
| `InvalidDuration` | 锁仓时长无效 | `revert` |
| `AlreadyLocked` | 重复锁仓 | `revert` |
| `DurationExceedsPermission` | 锁仓超出 NFT 权限 | `revert` |
| `NotLocked` | 未锁仓时调用解锁 | `revert` |
| `AlreadyExpired` | 已到期时调用提前解锁 | `revert` |
| `NotExpired` | 未到期时调用正常解锁 | `revert` |
| `NotBound` | 未绑定 NFT 时调用解绑 | `revert` |
| `AlreadyBound` | NFT 已被绑定时再次绑定 | `revert` |、

### 10.2 数值边界

| 边界类型 | 最小值 | 最大值 | 说明 |
|---------|-------|-------|------|
| 锁仓时长 | 30 days | 730 days | 超出范围 `InvalidDuration` |
| 质押金额 | > 0 | 用户余额 | 零金额 `ZeroAmount` |
| 赎回数量 | > 0 | 可用 sCUR | 零金额 `ZeroAmount`，超额  `InsufficientFreeSCUR` |
| 加成系数 | 1.0x | 2.5x | 由锁仓时长决定 |
| 惩罚比例 | 0% | 50% | 按剩余时间线性计算 |



## 11. 集成与依赖

### 11.1 核心合约依赖

| 合约 | 依赖关系 | 说明 |
|------|----------|------|
| CURStaking.sol | sCURToken, CURToken, IncentiveGauge, veCURLock，RevenueRebatePool | 管理 CUR <-> sCUR 兑换、流动性托管，以及用户加权质押份额 |
| IncentiveGauge.sol | CURStaking, veCURLock, sCURToken, RevenueRebatePool | 用户将 sCUR 质押到矿池，计算加权份额和分发 CUR 通胀奖励 |
| veCURLock.sol | IncentiveGauge, NFTChecker | 管理锁仓加成系数和提前解锁惩罚指令，并通知 IncentiveGauge 更新用户状态 |
| NFTChecker.sol | veCURLock | 验证用户 NFT 权限，解锁不同锁仓时长 |
| RevenueRebatePool.sol | CURStaking, IncentiveGauge，sCURToken | 接收协议收入和罚没资金，并将收益 CUR 注入 CURStaking，同时更新 sCUR 底层资产 accounting 和兑换率 |

### 11.2 模块交互流程

1. 用户调用 CURStaking.stake() 质押 CUR，获得 sCUR。
2. 用户将 sCUR 存入 IncentiveGauge.deposit()，矿池记录加权份额。
3. veCURLock.lock() 可对质押的 sCUR 进行锁仓，返回加权系数。
4. 用户的加权份额用于 IncentiveGauge 的奖励分配计算，但不改变协议实际释放的基础奖励规模。
5. 提前解锁 veCURLock.earlyUnlock() 会触发 IncentiveGauge 执行本金罚没和奖励没收。
6. NFTChecker 提供锁仓权限验证，决定最大可锁仓时长。
7. RevenueRebatePool 将协议收入或罚没形成的 CUR 转入 CURStaking，并调用 sCURToken.updateExchangeRate() 更新 sCUR 的底层资产 accounting，从而提升 sCUR 汇率。

### 11.3 sCUR 冻结规则

- 存入 IncentiveGauge 的 sCUR 会被冻结，不可转账，直到用户退出矿池。
- veCURLock 锁仓的 sCUR 对应的加权份额仅影响奖励计算，不直接增加 sCUR 可用余额。
- 提前解锁会触发部分 sCUR 销毁（罚没）并释放剩余 sCUR。

### 11.4 外部依赖

| 依赖项 | 版本 | 用途 |
|--------|------|------|
| OpenZeppelin Contracts | v5.5.0 | ERC20、Ownable、Pausable、ReentrancyGuard |
| Foundry Forge Std | latest | 测试框架 |

### 11.5 部署顺序

| 顺序 | 合约 | 依赖 |
|--------|------|------|
| 1 | CURToken | 无|
| 2 | sCUR | CURToken |
| 3 | NFTChecker | 无 |
| 4 | RevenueRebatePool | CURToken, sCUR |
| 5 | CURStaking | CURToken, sCUR，RevenueRebatePool |
| 6 | 设置 sCUR 的 minter 为 CURStaking |  ——  |
| 7 | veCURLock | CURStaking, NFTChecker, IncentiveGauge |
| 8 | IncentiveGauge | CURToken, sCUR, CURStaking, veCURLock, RevenueRebatePool |
| 9 | 设置 CURStaking 的 gauge 和 veLock |  ——  |
| 10 | 设置 veCURLock 的 incentiveGauge |  —— |
| 11 | 设置 IncentiveGauge 的 revenueRebatePool |  —— |
| 12 | 设置 RevenueRebatePool 的 curStaking |  —— |














