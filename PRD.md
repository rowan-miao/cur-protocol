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

### 3.2 操作相关

| 术语 | 定义 |
|------|------|
| stake | 用户通过 CURStaking 质押 CUR，并获得相应 sCUR 的操作 |
| unstake | 用户通过 CURStaking 销毁 sCUR，并赎回对应 CUR 的操作 |
| enterGauge | 用户将 sCUR 存入激励矿池，参与加权质押及 CUR 通胀奖励分配的操作 |
| exitGauge | 用户从激励矿池取回 sCUR 的操作，不等同于赎回 CUR |
| lock | 用户锁定 sCUR 以获得加成系数的操作 |
| unlock | 用户在锁仓到期正常解除锁仓限制的操作 |
| earlyUnlock | 用户在锁仓到期前提前解除锁仓的操作 |
| bindNFT | 用户绑定符合协议要求的 NFT，以获得对应等级的锁仓期限权限的操作。 |
| unbindNFT | 用户解绑NFT的操作 |
| getReward | 用户领取激励矿池中已累积且可领取的 CUR 通胀奖励的操作 |


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
| 基础质押 | stake / unstake | P0 | 第1期 | CURToken, sCUR，CURStaking |
| 质押凭证 | sCUR 1:1 铸造 / 销毁及本金锚定 | P0 | 第1期 | CURToken, CURStaking, sCUR |
| 通胀奖励 | IncentiveGauge | P0 | 第1期 | CURToken，sCUR, CURStaking |
| 锁仓加成 | veCURLock | P1 | 第1期 | CURStaking，sCUR，IncentiveGauge |
| NFT 权限 | NFTChecker | P2 | 第2期 | veCURLock |
| 收入反哺 | RevenueRebatePool | P1 | 第1期 | CURToken，sCUR，CURStaking |

---
## 5. 功能详述（产品视角）

### 5.1 流动性质押凭证（sCUR）

#### 5.1.1 功能描述

sCUR 是用户质押 CUR 后获得的生息凭证，代表用户在协议中的质押份额。sCUR 可自由转账、交易，也可存入激励矿池参与奖励分配。

#### 5.1.2 用户能做什么

| 操作 | 说明 |
|---|---|
| 持有 sCUR | 代表质押份额，价值随协议收入增长 |
| 转账 sCUR | 可在钱包间自由转移 |
| 交易 sCUR | 可在 DEX 上交易（如已集成） |
| 存入矿池 | 通过 `enterGauge` 参与激励奖励 |

#### 5.1.3 业务规则

- **兑换率**：sCUR 兑换 CUR 的比率，随协议收入注入而单调增长
- **初始汇率**：1 sCUR = 1 CUR
- **汇率只升不降**：仅由协议收入驱动，不受通胀奖励影响
- **收益来源**：协议收入注入 → `totalUnderlying` 增加 → 汇率上升
- **用户收益**：持有 sCUR 即可享受基础收益（体现在汇率增长中）

#### 5.1.4 用户价值

- **流动性**：sCUR 可自由转账、交易，解决传统质押的流动性锁定问题
- **可组合性**：sCUR 可被其他 DeFi 协议集成
- **被动收益**：持有即享受基础收益，无需额外操作

---

### 5.2 主质押合约（CURStaking）

#### 5.2.1 功能描述

CURStaking 是用户质押 CUR 和赎回 CUR 的主要入口，负责协调 CUR 与 sCUR 的转换，并与激励矿池交互。

#### 5.2.2 用户能做什么

| 操作 | 说明 | 前提 |
|---|---|---|
| 质押 CUR（`stake`） | 存入 CUR，获得等值 sCUR | 已授权 CUR、余额足够、数量 ≥ 最低门槛 |
| 赎回 CUR（`unstake`） | 销毁 sCUR，取回 CUR | sCUR 在钱包中（未存入矿池）、未锁仓 |
| 进入矿池（`enterGauge`） | 将 sCUR 存入激励矿池 | sCUR 在钱包中、未锁仓 |
| 退出矿池（`exitGauge`） | 从矿池取回 sCUR | 未锁仓 |

#### 5.2.3 业务规则

**质押（stake）**
- 用户按当前汇率获得 sCUR
- 有最低质押门槛（防止粉尘攻击）
- 质押后 sCUR 直接发放到用户钱包

**赎回（unstake）**
- 用户按当前汇率取回 CUR
- 只能赎回钱包中的 sCUR，矿池中的 sCUR 需先 `exitGauge`
- 锁仓期间不能赎回

**进入矿池（enterGauge）**
- sCUR 从用户钱包转入激励矿池托管
- 锁仓期间不能进入矿池
- 可多次进入，累加

**退出矿池（exitGauge）**
- sCUR 从矿池转回用户钱包
- 锁仓期间不能退出矿池
- 可部分退出

#### 5.2.4 用户价值

- **一站式入口**：质押、赎回、参与激励都在一个合约完成
- **灵活进出**：可部分质押、部分赎回、部分进出矿池
- **安全托管**：CUR 本金由合约托管，sCUR 由用户自己持有

---

### 5.3 激励矿池（IncentiveGauge）

#### 5.3.1 功能描述

激励矿池是用户通过质押 sCUR 参与 CUR 通胀奖励分配的场所。用户的奖励份额由"加权质押量"决定，权重越高，分到的奖励越多。

#### 5.3.2 用户能做什么

| 操作 | 说明 | 前提 |
|---|---|---|
| 领取奖励（`getReward`） | 领取累积的 CUR 通胀奖励 | 有可领取奖励 |
| 查看奖励 | 查询待领取奖励 | — |


#### 5.3.3 业务规则

**奖励来源**
- CUR 通胀奖励按预设的 4 年释放计划产出
- 释放速率逐年递减（第 1 年 1500 万，第 2 年 1200 万，第 3 年 800 万，第 4 年 500 万）

**奖励分配**
- 按用户权重占全网总权重的比例分配
- 权重 = 质押 sCUR 数量 × 加成系数
- 加成系数由锁仓时长决定（1.0x ~ 2.5x）

**领取方式**
- 手动领取，奖励以 CUR 形式直接发放到钱包
- 不自动复利

**权重变化**
- 所有权重变化（存入、取出、锁仓、解锁）在下次结算后生效
- 不回溯历史区间

#### 5.3.4 用户价值

- **竞争性收益**：锁仓越久，权重越高，分到的奖励越多
- **透明分配**：奖励按权重比例分配，公式公开
- **可持续性**：奖励释放与协议收入分离，避免死亡螺旋

---

### 5.4 锁仓加成（veCURLock）

#### 5.4.1 功能描述

锁仓加成管理器允许用户通过承诺锁仓时长来提升加权系数，从而在激励矿池中占据更大份额。

#### 5.4.2 用户能做什么

| 操作 | 说明 | 前提 |
|---|---|---|
| 锁仓（`lock`） | 锁定矿池中的 sCUR，获得加成系数 | 矿池中有 sCUR、未锁仓 |
| 正常解锁（`unlock`） | 锁仓到期后解除锁定 | 锁仓已到期 |
| 提前解锁（`earlyUnlock`） | 锁仓到期前解除锁定，触发惩罚 | 锁仓未到期 |

#### 5.4.3 锁仓档位与加成系数

| 锁仓时长 | 加成系数 | NFT 权限要求 |
|---|---|---|
| 30 天 | 1.15x | 无门槛 |
| 90 天 | 1.35x | 无门槛 |
| 180 天 | 1.65x | 无门槛 |
| 365 天 | 2.00x | 需持有中级 NFT |
| 730 天 | 2.50x | 需持有高级 NFT |

#### 5.4.4 业务规则

**锁仓（lock）**
- 锁仓时长必须是预设档位之一
- 锁仓时长不能超过用户 NFT 权限对应的上限
- 用户同一时间只能有一个锁仓承诺
- 锁仓作用于矿池中的 sCUR，不影响钱包中的 sCUR

**正常解锁（unlock）**
- 锁仓到期后可正常解锁
- 无惩罚
- 加成系数重置为 1.0x
- 权重按当前质押量重算

**提前解锁（earlyUnlock）**
- 锁仓到期前可提前解锁，但触发惩罚
- **本金罚没**：按公式罚没部分 sCUR
  - `Penalty = 本金 × 50% × (剩余时间 / 总锁仓时长)`
- **收益罚没**：未领取的 CUR 奖励 100% 没收，转入收入池
- **权益重置**：加成系数重置为 1.0x
- **NFT 释放**：解除 NFT 绑定，NFT 恢复自由状态

#### 5.4.5 用户价值

- **长期激励**：锁仓越久，加成越高
- **灵活退出**：可提前解锁，但需支付惩罚
- **NFT 权限**：持有 NFT 可解锁更高档位

---

### 5.5 NFT 权限验证器（NFTChecker）

#### 5.5.1 功能描述

NFTChecker 管理 NFT 白名单，验证用户 NFT 持有情况，决定用户可用的最大锁仓时长。

#### 5.5.2 用户能做什么

| 操作 | 说明 | 前提 |
|---|---|---|
| 绑定 NFT（`bindNFT(nftContract, tokenId)`） | 绑定 NFT 以获得锁仓权限 | NFT 在白名单中、用户持有该 NFT、用户未绑定、NFT 未被绑定 |
| 解绑 NFT（`unbindNFT()`） | 解除自己的 NFT 绑定 | 未锁仓、已绑定 |

#### 5.5.3 NFT 等级与权限

| 等级 | 常量 | 解锁权限 |
|---|---|---|
| 中级 NFT | `TIER_MID = 1` | 365 天锁仓 |
| 高级 NFT | `TIER_HIGH = 2` | 730 天锁仓 |

**无 NFT**：仅可选 ≤180 天锁仓。

> 实际白名单由 Owner 通过 `addWhiteListedContract` 添加，具体 NFT 类型（合作伙伴、贡献者、治理等）由部署时决定。

#### 5.5.4 业务规则

**绑定（bindNFT）**
- 用户必须是 NFT 的持有者（`ownerOf(tokenId)` 校验）
- 同一用户同时只能绑定 1 个 NFT
- 同一 NFT 同时只能绑定 1 个用户
- NFT 合约必须在白名单中

**解绑（unbindNFT）**
- **锁仓期间不能解绑**（`PositionLocked`）
- 未绑定 NFT 时不能解绑（`NotBound`）
- 解绑后 NFT 恢复自由，可用于其他账户

**权限生效**
- 权限变化仅影响后续锁仓，不回溯历史奖励

#### 5.5.5 用户价值

- **身份权益**：NFT 持有者解锁更高锁仓档位
- **防滥用**：同一 NFT 不能同时绑定多个账户
- **灵活性**：可随时解绑（未锁仓时）

---

### 5.6 收入反哺池（RevenueRebatePool）

#### 5.6.1 功能描述

收入反哺池收集协议收入和罚没资金，定期注入 CURStaking 以提升 sCUR 兑换率，使所有 sCUR 持有者受益。

#### 5.6.2 用户能做什么

> 收入反哺池的注入操作由 Owner 触发，普通用户被动受益。

| 操作 | 说明 | 权限 |
|---|---|---|
| 存入收入（`depositRevenue`） | 存入 CUR 到收入池 | 公开 |
| 注入 sCUR 池（`injectToSCUR`） | 将指定数量收入注入 sCUR 池 | 仅 Owner |
| 全部注入（`injectAll`） | 注入全部累计收入 | 仅 Owner |
| 设置阈值（`setNewthreshold`） | 设置自动注入阈值 | 仅 Owner |

#### 5.6.3 业务规则

**收入来源**
- 协议手续费、生态分红等外部收入
- 提前解锁的罚没资金

**注入机制**
- 收入注入 CURStaking，调用 `updateExchangeRate` 提升 sCUR 汇率
- 仅当 sCUR 总供应量 > 0 时可注入
- 汇率只升不降

**用户受益**
- 所有 sCUR 持有者按持有比例分享收益
- 无需操作，自动体现在汇率增长中

#### 5.6.4 用户价值

- **被动收益**：持有 sCUR 即可享受协议收入
- **公平分配**：按 sCUR 持有量比例分配
- **可持续性**：协议收入反哺，减少对通胀的依赖

### 5.7 空投合约（Airdrop）

#### 5.7.1 功能描述

Airdrop 合约负责向白名单用户分发固定数量的 CUR 空投奖励，作为协议早期支持者的激励。每个白名单地址限领一次，支持暂停。

#### 5.7.2 用户能做什么

| 操作 | 说明 | 前提 |
|---|---|---|
| 领取空投（`claim`） | 领取固定数量的 CUR 空投 | 在白名单中、未领取过 |
| 查询资格 | 查询自己是否在白名单、是否已领取 | — |
| 查询剩余 | 查询合约剩余可分发 CUR | — |

> 白名单管理、存入 CUR 由 Owner 操作，普通用户不直接操作。

#### 5.7.3 业务规则

**空投数量**
- 每个白名单地址固定领取 1000 CUR

**领取条件**
- 地址必须在白名单中
- 每个地址只能领取一次
- 合约必须有 ≥ 1000 CUR 的余额
- 合约未暂停

**领取方式**
- 用户主动调用 `claim`，CUR 直接发放到钱包
- 不支持代领

**白名单管理（Owner）**

- 单个添加：addToWhitelist(user)

- 批量添加：addWhitelist(address[] users)

- 移除：removeFromWhitelist(user)

**存入 CUR（Owner）**

- deposit(amount)：Owner 将 CUR 转入合约，用于分发

#### 5.7.4 用户价值

- **早期激励**：奖励早期支持者
- **公平分发**：白名单机制，每个地址限领一次
- **简单直接**：一键领取，无需复杂操作

#### 5.7.5 权限与治理

| 操作 | 权限 |
|---|---|
| 添加白名单 | 仅 Owner |
| 批量添加白名单 | 仅 Owner |
| 移除白名单 | 仅 Owner |
| 存入 CUR | 仅 Owner |
| 暂停/恢复 | 仅 Owner |

#### 5.7.6 关键约束

| 约束	| 说明 |
|---|---|
| 固定空投量 | 1000 CUR / 地址 |
| 单次领取	| 每个地址只能领取一次 |
| 白名单机制| 只有白名单地址可领取 |
| 可暂停 |	Owner 可暂停/恢复领取 |
| 余额校验 |	合约余额不足时 revert InsufficientBalance |

---

## 6. 验收标准（Acceptance Criteria）

### 6.1 质押功能（Stake）

```gherkin
Scenario: 用户成功质押 CUR
  Given 用户 alice 有 1000 CUR 余额
  And  用户 alice 已授权 CURStaking 使用 1000 CUR
  When 用户 alice 调用 stake(1000)
  Then 用户 alice 收到 1000 sCUR（初始汇率 1:1）
  And  CURStaking 合约 CUR 余额增加 1000
  And  用户 alice 的 sCUR 余额为 1000
  And  触发 Staked(alice, 1000, 1000) 事件
  And  触发 Mint(alice, 1000, 1000) 事件

Scenario: 用户质押数量为 0
  Given 用户 alice 有 1000 CUR 余额
  When 用户 alice 调用 stake(0)
  Then 交易回滚，错误 ZeroAmount

Scenario: 质押数量低于最低要求
  Given 用户 alice 有 1000 CUR 余额
  And  当前最低质押量为 minimumStake
  When 用户 alice 调用 stake(minimumStake - 1)
  Then 交易回滚，错误 BelowMinimumStake

Scenario: 用户余额不足
  Given 用户 alice 有 500 CUR 余额
  When 用户 alice 调用 stake(1000)
  Then 交易回滚，错误 ERC20InsufficientBalance

Scenario: 用户未授权合约
  Given 用户 alice 有 1000 CUR 余额
  And  用户 alice 未授权 CURStaking 使用 CUR
  When 用户 alice 调用 stake(1000)
  Then 交易回滚，错误 ERC20InsufficientAllowance

Scenario: 汇率变化后质押
  Given 用户 alice 有 2000 CUR 余额
  And  当前汇率为 1.2e18（1 sCUR = 1.2 CUR）
  When 用户 alice 调用 stake(1200)
  Then 用户 alice 收到 1000 sCUR
  And  触发 Staked(alice, 1200, 1000) 事件
```

### 6.2 赎回功能（Unstake）

```gherkin
Scenario: 用户成功赎回 CUR
  Given 用户 alice 已质押 1000 CUR
  And  用户 alice 持有 1000 sCUR（未存入 Gauge）
  And  sCUR 汇率为 1:1
  When 用户 alice 调用 unstake(1000)
  Then 用户 alice 的 sCUR 被销毁
  And  用户 alice 收到 1000 CUR
  And  用户 alice 的 sCUR 余额为 0
  And  触发 UnStaked(alice, 1000, 1000) 事件
  And  触发 Redeem(alice, 1000, 1000) 事件

Scenario: 赎回数量为 0
  Given 用户 alice 已质押 1000 CUR
  When 用户 alice 调用 unstake(0)
  Then 交易回滚，错误 ZeroAmount

Scenario: 赎回数量超过可用 sCUR
  Given 用户 alice 已质押 1000 CUR
  And  用户 alice 已将 600 sCUR 存入矿池
  And  用户 alice 钱包中仅有 400 sCUR
  When 用户 alice 调用 unstake(500)
  Then 交易回滚，错误 InsufficientFreeSCUR

Scenario: 底层资产不足
  Given 用户 alice 已质押 1000 CUR
  And  sCUR 的 totalUnderlying 小于赎回所需 CUR
  When 用户 alice 调用 unstake(1000)
  Then 交易回滚，错误 InsufficientUnderlying

Scenario: 用户锁仓期间赎回
  Given 用户 alice 已锁仓 1000 sCUR 30 天
  When 用户 alice 调用 unstake(100)
  Then 交易回滚，错误 PositionLocked

Scenario: 汇率变化后赎回
  Given 用户 alice 已质押 1000 CUR（获得 1000 sCUR）
  And  当前汇率为 1.5e18（1 sCUR = 1.5 CUR）
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
  And  用户 alice 已授权 CURStaking 使用 sCUR
  When 用户 alice 调用 enterGauge(600)
  Then 用户 alice 的 sCUR 余额减少 600
  And  gauge 持有 600 sCUR
  And  gauge 中 alice 的 depositedGauge = 600
  And  触发 EnterGauge(alice, 600) 事件
  And  触发 Deposit(alice, 600) 事件

Scenario: 进入矿池数量为 0
  Given 用户 alice 已质押 1000 CUR
  When 用户 alice 调用 enterGauge(0)
  Then 交易回滚，错误 ZeroAmount

Scenario: 进入矿池数量超过可用 sCUR
  Given 用户 alice 已质押 1000 CUR
  When 用户 alice 调用 enterGauge(1500)
  Then 交易回滚，错误 InsufficientAmount

Scenario: 用户锁仓期间进入矿池
  Given 用户 alice 已锁仓 1000 sCUR 30 天
  When 用户 alice 调用 enterGauge(100)
  Then 交易回滚，错误 PositionLocked

Scenario: 用户未授权 sCUR
  Given 用户 alice 已质押 1000 CUR
  And  用户 alice 未授权 CURStaking 使用 sCUR
  When 用户 alice 调用 enterGauge(600)
  Then 交易回滚，错误 ERC20InsufficientAllowance

Scenario: 用户多次进入矿池
  Given 用户 alice 已质押 1000 CUR
  When 用户 alice 调用 enterGauge(400)
  And  用户 alice 调用 enterGauge(300)
  Then 用户 alice 的 sCUR 余额减少 700
  And  gauge 中 alice 的 depositedGauge = 700
```

### 6.4 退出矿池（exitGauge）
```gherkin
Scenario: 用户成功退出矿池
  Given 用户 alice 已质押 1000 CUR
  And  用户 alice 已存入矿池 600 sCUR
  When 用户 alice 调用 exitGauge(600)
  Then 用户 alice 的 depositedGauge = 0
  And  用户 alice 的 sCUR 余额增加 600
  And  触发 ExitGauge(alice, 600) 事件
  And  触发 Withdraw(alice, 600) 事件

Scenario: 退出矿池数量为 0
  Given 用户 alice 已存入矿池 600 sCUR
  When 用户 alice 调用 exitGauge(0)
  Then 交易回滚，错误 ZeroAmount

Scenario: 退出数量超过矿池余额
  Given 用户 alice 已存入矿池 600 sCUR
  When 用户 alice 调用 exitGauge(800)
  Then 交易回滚，错误 InsufficientAmount

Scenario: 用户锁仓期间退出矿池
  Given 用户 alice 已锁仓 1000 sCUR 30 天
  When 用户 alice 调用 exitGauge(100)
  Then 交易回滚，错误 PositionLocked

Scenario: 用户部分退出矿池
  Given 用户 alice 已存入矿池 600 sCUR
  When 用户 alice 调用 exitGauge(250)
  Then 用户 alice 的 depositedGauge = 350
  And  用户 alice 的 sCUR 余额增加 250
```

### 6.5 锁仓功能（Lock）

```gherkin
Scenario: 用户成功锁仓 30 天
  Given 用户 alice 在矿池中有 1000 sCUR
  When 用户 alice 调用 lock(30 days)
  Then 用户 alice 的锁仓状态变为已锁仓
  And  用户 alice 的加成系数为 1.15e18
  And  用户 alice 的锁仓结束时间为 startTime + 30 days
  And  veCURLock 的 totalLocked 增加 1000
  And  触发 Locked(alice, 30 days, 1.15e18, endTime) 事件
  And  incentiveGauge.executeLock(alice) 被调用
  And  gauge 中 alice 的权重更新为 1000 × 1.15e18 / PRECISION = 1150
  And  触发 LockExecuted(alice) 事件

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
  And  veCURLock 的 totalLocked 减少 1000
  And  触发 Unlocked(alice, 1000) 事件
  And  incentiveGauge.executeUnlock(alice) 被调用
  And  gauge 中 alice 的权重重置为 userInfo.amount × 1.0e18 / PRECISION
  And  触发 UnlockExecuted(alice) 事件

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
  And  锁仓已过 15 天（剩余 15 天）
  And  用户 alice 已绑定 NFT
  When 用户 alice 调用 earlyUnlock()
  Then 用户 alice 的锁仓状态变为未锁仓
  And  veCURLock 的 totalLocked 减少 1000
  And  惩罚金额 = 1000 × 50% × (15/30) = 250 sCUR
  And  触发 EarlyUnlocked(alice, 1000, 250) 事件
  And  incentiveGauge.executeEarlyUnlock(alice, 250) 被调用
  And  gauge 中 alice 的 depositedGauge 减少 250
  And  gauge 中 alice 的 pendingRewards 被清零并转入 RevenueRebatePool
  And  gauge 调用 sCUR.burnGaugePenalty(250)，烧掉 gauge 的 250 sCUR
  And  CURStaking 将等值 CUR 转入 RevenueRebatePool
  And  gauge 中 alice 的权重重置为 (1000 - 250) × 1.0e18 / PRECISION
  And  用户的 NFT 绑定被解除
  And  触发 NFTUnbound(alice, ...) 事件

Scenario: 用户提前解锁时锁仓已到期
  Given 用户 alice 已锁仓 1000 sCUR 30 天
  And  锁仓已到期（时间已过 30 天）
  When 用户 alice 调用 earlyUnlock()
  Then 交易回滚，错误 AlreadyExpired

Scenario: 用户未锁仓时调用提前解锁
  Given 用户 alice 没有锁仓
  When 用户 alice 调用 earlyUnlock()
  Then 交易回滚，错误 NotLocked

Scenario: 惩罚金额计算正确（过半）
  Given 用户 alice 锁仓 1000 sCUR 30 天
  And  锁仓剩余 15 天
  When 用户 alice 调用 earlyUnlock()
  Then 惩罚金额 = 1000 × 50% × (15/30) = 250 sCUR

Scenario: 惩罚金额接近 0（到期前 1 秒）
  Given 用户 alice 锁仓 1000 sCUR 30 天
  And  锁仓剩余 1 秒
  When 用户 alice 调用 earlyUnlock()
  Then 惩罚金额 ≈ 0
  And  不调用 burnGaugePenalty（penalty == 0）
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

### 6.9 存入矿池(deposit)

```gherkin
Scenario: CURStaking 成功调用 deposit
  Given 用户 alice 已质押 1000 CUR
  And  用户 alice 已通过 enterGauge 将 600 sCUR 转入 gauge
  When CURStaking 调用 gauge.deposit(alice, 600)
  Then gauge 中 alice 的 userInfo.amount = 600
  And  gauge 的 totalWeight 增加 600 × bonus / PRECISION
  And  触发 Deposit(alice, 600) 事件

Scenario: 非 CURStaking 调用 deposit
  Given 用户 alice 尝试直接调用 gauge.deposit(alice, 600)
  When alice 调用 deposit(alice, 600)
  Then 交易回滚，错误 Unauthorized

Scenario: deposit 数量为 0
  Given CURStaking 调用 gauge.deposit(alice, 0)
  Then 交易回滚，错误 ZeroAmount

Scenario: 用户已锁仓，deposit 后权重按 bonus 计算
  Given 用户 alice 已锁仓 30 天（bonus = 1.15e18）
  And  gauge 中 alice 的 userInfo.amount = 0
  When CURStaking 调用 gauge.deposit(alice, 1000)
  Then gauge 中 alice 的 userInfo.amount = 1000
  And  gauge 中 alice 的权重 = 1000 × 1.15e18 / PRECISION = 1150

Scenario: 用户未锁仓，deposit 后权重按 1.0x 计算
  Given 用户 alice 未锁仓（bonus = 1.0e18）
  When CURStaking 调用 gauge.deposit(alice, 1000)
  Then gauge 中 alice 的 userInfo.amount = 1000
  And  gauge 中 alice 的权重 = 1000

Scenario: 用户多次 deposit
  Given 用户 alice 已质押 1000 CUR
  When CURStaking 调用 gauge.deposit(alice, 400)
  And  CURStaking 调用 gauge.deposit(alice, 300)
  Then gauge 中 alice 的 userInfo.amount = 700

Scenario: deposit 时结算历史奖励
  Given 用户 alice 在 gauge 中有 1000 sCUR
  And  时间过去 100 天，产生奖励
  When CURStaking 调用 gauge.deposit(alice, 500)
  Then alice 的历史奖励被结算到 pendingRewards
  And  alice 的 userInfo.amount 增加 500

Scenario: deposit 时刷新闲置奖励
  Given gauge 的 accumulatedIdleRewards > 0
  When CURStaking 调用 gauge.deposit(alice, 1000)
  Then accumulatedIdleRewards 被转入 revenueRebatePool
  And  触发 IdleRewardsFlushed 事件

Scenario: 合约暂停时 deposit
  Given gauge 已暂停
  When CURStaking 调用 gauge.deposit(alice, 1000)
  Then 交易回滚（whenNotPaused 拦截）
  ```
### 6.10 从矿池取出(withdraw)

```gherkin
Scenario: CURStaking 成功调用 withdraw
  Given 用户 alice 在 gauge 中有 600 sCUR
  When CURStaking 调用 gauge.withdraw(alice, 600)
  Then gauge 中 alice 的 userInfo.amount = 0
  And  600 sCUR 从 gauge 转回 alice
  And  gauge 的 totalWeight 减少 600 × bonus / PRECISION
  And  触发 Withdraw(alice, 600) 事件

Scenario: 非 CURStaking 调用 withdraw
  Given 用户 alice 尝试直接调用 gauge.withdraw(alice, 600)
  When alice 调用 withdraw(alice, 600)
  Then 交易回滚，错误 Unauthorized

Scenario: withdraw 数量为 0
  Given CURStaking 调用 gauge.withdraw(alice, 0)
  Then 交易回滚，错误 ZeroAmount

Scenario: withdraw 数量超过用户余额
  Given 用户 alice 在 gauge 中有 600 sCUR
  When CURStaking 调用 gauge.withdraw(alice, 800)
  Then 交易回滚，错误 InsufficientAmount

Scenario: 用户部分 withdraw
  Given 用户 alice 在 gauge 中有 600 sCUR
  When CURStaking 调用 gauge.withdraw(alice, 250)
  Then gauge 中 alice 的 userInfo.amount = 350
  And  250 sCUR 从 gauge 转回 alice

Scenario: withdraw 后权重正确更新
  Given 用户 alice 在 gauge 中有 1000 sCUR，bonus = 1.15e18，权重 = 1150
  When CURStaking 调用 gauge.withdraw(alice, 500)
  Then gauge 中 alice 的 userInfo.amount = 500
  And  gauge 中 alice 的权重 = 500 × 1.15e18 / PRECISION = 575

Scenario: withdraw 时结算历史奖励
  Given 用户 alice 在 gauge 中有 1000 sCUR
  And  时间过去 100 天，产生奖励
  When CURStaking 调用 gauge.withdraw(alice, 500)
  Then alice 的历史奖励被结算到 pendingRewards
  And  alice 的 userInfo.amount 减少 500

Scenario: withdraw 时刷新闲置奖励
  Given gauge 的 accumulatedIdleRewards > 0
  When CURStaking 调用 gauge.withdraw(alice, 1000)
  Then accumulatedIdleRewards 被转入 revenueRebatePool
  And  触发 IdleRewardsFlushed 事件

Scenario: 合约暂停时 withdraw
  Given gauge 已暂停
  When CURStaking 调用 gauge.withdraw(alice, 1000)
  Then 交易回滚（whenNotPaused 拦截）
```

### 6.11 领取空投（Claim）

```gherkin
Scenario: 白名单用户成功领取空投
  Given 用户 alice 在白名单中
  And  用户 alice 未领取过空投
  And  Airdrop 合约有 ≥ 1000 CUR 余额
  And  合约未暂停
  When 用户 alice 调用 claim()
  Then 用户 alice 收到 1000 CUR
  And  用户 alice 的 hasClaimed = true
  And  totalClaimed 增加 1000 CUR
  And  totalRecipients 增加 1
  And  触发 Claimed(alice, 1000) 事件

Scenario: 非白名单用户领取
  Given 用户 bob 不在白名单中
  When 用户 bob 调用 claim()
  Then 交易回滚，错误 NotWhitelisted

Scenario: 用户重复领取
  Given 用户 alice 已领取过空投
  When 用户 alice 再次调用 claim()
  Then 交易回滚，错误 AlreadyClaimed

Scenario: 合约 CUR 余额不足
  Given Airdrop 合约 CUR 余额 < 1000
  And  用户 alice 在白名单中
  When 用户 alice 调用 claim()
  Then 交易回滚，错误 InsufficientBalance

Scenario: 合约暂停时领取
  Given 合约已暂停
  And  用户 alice 在白名单中
  When 用户 alice 调用 claim()
  Then 交易回滚（whenNotPaused 拦截）

Scenario: Owner 添加单个白名单
  Given 用户 alice 不在白名单中
  When Owner 调用 addToWhitelist(alice)
  Then isWhitelisted[alice] = true
  And  触发 AddToWhitelist(alice) 事件

Scenario: Owner 批量添加白名单
  Given alice、bob、charlie 都不在白名单中
  When Owner 调用 addWhitelist([alice, bob, charlie])
  Then 三人 isWhitelisted = true
  And  触发 AddWhitelist([alice, bob, charlie]) 事件

Scenario: Owner 移除白名单
  Given 用户 alice 在白名单中
  When Owner 调用 removeFromWhitelist(alice)
  Then isWhitelisted[alice] = false
  And  触发 RemoveFromWhitelist(alice) 事件

Scenario: Owner 存入 CUR
  Given Owner 有 10000 CUR 并已 approve
  When Owner 调用 deposit(10000)
  Then 合约 CUR 余额增加 10000
  And  触发 Deposited(10000) 事件
```
---


## 7. 业务规则与公式

### 7.1 sCUR 兑换率公式

#### 7.1.1 当前兑换率

$$
exchangeRate = \frac{totalUnderlying \times PRECISION}{totalSupply(sCUR)}
$$

**参数说明：**

| 参数 | 说明 |
|------|------|
| `totalUnderlying` | sCUR 合约记录的底层 CUR 支撑资产数量，用于兑换率计算 |
| `totalSupply(sCUR)` | sCUR 总供应量 |
| `PRECISION` | 精度常数（1e18） |


#### 7.1.2 Stake（质押）

用户质押 CUR 时：

$$
sCURMinted = \frac{CURAmount \times PRECISION}{exchangeRate}
$$

#### 7.1.3 Unstake（赎回）

用户赎回时：

$$
CURReturned = \frac{sCURAmount \times exchangeRate}{PRECISION}
$$


#### 7.1.4 兑换率增长

当 RevenueRebatePool 将收益 CUR 注入协议时：

1. RevenueRebatePool 将真实 CUR 转入 CURStaking。
2. CURStaking 的实际 CUR 资产增加。
3. RevenueRebatePool 调用 sCURToken.updateExchangeRate(amount)。
4. sCUR 的 totalUnderlying 增加 amount。
5. sCUR 总供应量保持不变。
6. exchangeRate 相应提高。

因此：

- CUR 的实际资产始终由 CURStaking 持有。
- sCUR 仅更新底层资产 accounting，不接收真实 CUR。
- 在 totalSupply(sCUR) == 0 时，updateExchangeRate 会 revert NoSupply。
- 在 totalSupply(sCUR) > 0 时，汇率单调不减（newRate >= oldRate，否则 revert ExchangeRateCannotDecrease）。

#### 7.1.5 底层资产流转

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
  │ CUR → CURStaking（transfer）
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

### 7.2 用户权重公式

#### 7.2.1 基础权重

用户进入 IncentiveGauge 后（未锁仓时）：

$$
BaseWeight = GaugeAmount
$$

即：`1 sCUR = 1 Weight`


#### 7.2.2 锁仓加成权重

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


#### 7.2.3 全网总权重

$$
TotalWeight = \sum_{i} Weight_i
$$

该变量维护于：

```solidity
IncentiveGauge.totalWeight
```

### 7.3 奖励释放公式

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


### 7.4 Reward Per Token 模型

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



### 7.5 用户奖励公式

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


### 7.6 提前解锁罚没公式

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


### 7.7 提前解锁后的权重重置

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

### 7.8 奖励罚没规则

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

# 8. 非功能需求

## 8.1 安全要求

| 要求 | 说明 |
|---|---|
| 防重入攻击 | 所有涉及外部调用的函数具备防重入能力 |
| 权限控制 | 敏感操作（铸币、暂停、参数调整）严格权限控制 |
| 紧急暂停 | 检测到异常时可暂停关键操作，但允许用户紧急提取本金 |
| 防时间操纵 | 奖励分配基于累积模型，不依赖单次时间点 |
| 防除零错误 | 所有除法运算确保分母非零 |

## 8.2 可用性要求

| 要求 | 说明 |
|---|---|
| 可暂停 | 合约可被 Owner 暂停，暂停期间停止铸币、奖励分发 |
| 紧急提取 | 暂停期间允许用户通过 `emergencyWithdraw` 提取本金，未领取奖励清零 |
| 可恢复 | 暂停后可恢复，恢复后功能正常 |
| 多签控制 | 关键权限由多签钱包 + Timelock 控制 |

**紧急提取规则**：

| 项目 | 说明 |
|---|---|
| 触发条件 | 合约处于暂停状态（`whenPaused`） |
| 用户操作 | `CURStaking.emergencyWithdraw()` |
| 提取内容 | 矿池中的 sCUR + 钱包中的 sCUR，全部赎回为 CUR |
| 奖励处理 | 未领取奖励全部清零（放弃） |
| 触发事件 | `EmergencyWithdrawn(user, totalSCUR, CURAmount)` |

## 8.3 可扩展性要求

| 要求 | 说明 |
|---|---|
| 多重奖励支持 | 架构上支持未来扩展分发生态合作伙伴的代币 |
| NFT 白名单可扩展 | 支持动态添加/移除 NFT 白名单 |
| 参数可调整 | 敏感参数（如 NFT 白名单）经时间锁调整 |

## 8.4 合规与治理要求

| 要求 | 说明 |
|---|---|
| 时间锁延迟 | 敏感参数调整需经过3 天时间锁公示期 |
| 不可篡改项 | 释放速率按预设 4 年计划执行，不可通过治理修改 |
| 所有权移交 | 部署后将所有权移交给 Timelock，由多签管理 |

## 8.5 性能与体验要求

| 要求 | 说明 |
|---|---|
| Gas 优化 | 关键操作在合理 gas 范围内 |
| 透明度| 所有关键操作有事件记录，便于链下追踪 |
| 用户可查 | 用户可查询待领取奖励、锁仓状态、加成系数 |