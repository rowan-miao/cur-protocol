# CUR Protocol

CUR Protocol is a decentralized staking protocol that combines liquid staking with a Compound-style global reward index.

Users stake $CUR and receive $sCUR as a liquid staking receipt token. The protocol is organized into modular smart contracts with clearly defined responsibilities for staking, reward distribution, time-based locking, NFT permissions, and protocol revenue.

## Core Mechanisms

- **Liquid Staking**
  - Stake $CUR and receive $sCUR.
  - $sCUR is minted 1:1 with deposited $CUR.
  - $sCUR remains transferable as a liquid staking receipt.

- **Dynamic Exchange Rate**
  - The amount of $sCUR does not automatically increase when protocol revenue is generated.
  - Instead, protocol revenue increases the underlying $CUR backing the system.
  - The economic value of $sCUR is reflected through the dynamic exchange rate.

- **Compound-style Reward Distribution**
  - Rewards are distributed using a global reward index.
  - User reward weight is determined by staking amount and lock bonus.
  - User weight affects reward distribution only, not the total amount of rewards released by the protocol.

- **Time-weighted Locking**
  - Longer lock periods provide higher reward weight coefficients.
  - Lock durations range from 30 days to 730 days.

- **NFT-based Lock Permissions**
  - NFTs are used as permission mechanisms for advanced lock tiers.
  - NFT ownership can unlock access to higher lock tiers and longer lock durations.

- **Protocol Revenue Rebate**
  - Protocol revenue is routed through the RevenueRebatePool and contributes to the underlying CUR value supporting sCUR.
  

---

## Project Structure

```
cur-protocol/
├── src/
│ ├── core/
│ │ ├── CURToken.sol 
│ │ ├── sCUR.sol
│ │ └── CURStaking.sol 
│ ├── modules/
│ │ ├── IncentiveGauge.sol
│ │ ├── RevenueRebatePool.sol 
│ │ ├── veCURLock.sol 
│ │ ├── NFTChecker.sol 
│ │ └── Airdrop.sol
│ └── interfaces/
│ ├── ICURStaking.sol
│ ├── IIncentiveGauge.sol
│ └── ...
├── test/
│ ├── CURToken.t.sol
│ ├── sCUR.t.sol
│ ├── CURStaking.t.sol
│ └── ...
├── script/
│ └── Deploy.s.sol
├── foundry.toml
└── README.md
```

---

## Architecture

The protocol is organized into several modular smart contracts with clearly separated responsibilities:

```text
                         ┌──────────────────┐
                         │     CURToken     │
                         │    $CUR Token    │
                         └────────┬─────────┘
                                  │
                                  ▼
                         ┌──────────────────┐
                         │   CURStaking     │
                         │  Stake / Unstake │
                         │ Reward Settlement│
                         └───────┬──────────┘
                                 │
                    ┌────────────┼────────────┐
                    │            │            │
                    ▼            ▼            ▼
             ┌────────────┐ ┌────────────┐ ┌──────────────┐
             │    sCUR    │ │ Incentive  │ │  veCURLock   │
             │ Liquid     │ │   Gauge    │ │ Time Lock    │
             │ Receipt    │ │  Rewards   │ │              │
             └────────────┘ └────────────┘ └──────┬───────┘
                                                  │
                                                  ▼
                                           ┌──────────────┐
                                           │ NFTChecker   │
                                           │ Permissions  │
                                           └──────────────┘

             Protocol Revenue
                      │
                      ▼
          ┌────────────────────┐
          │ RevenueRebatePool  │
          │                    │
          │ Revenue → CUR      │
          └─────────┬──────────┘
                    │
                    ▼
             Underlying CUR
                    │
                    ▼
          ┌────────────────────┐
          │  sCUR ExchangeRate │
          │                    │
          │  Value of sCUR     │
          └────────────────────┘
```
---
                       
## Core Contracts

| Contract | Description | 
|-----------|------|
| `CURToken.sol` | ERC-20 staking token | 
| `sCUR.sol` | Liquid staking receipt token |
| `CURStaking.sol` | Core staking and reward settlement contract | 
| `IncentiveGauge.sol` | Handles staking incentive and reward distribution |
| `veCURLock.sol` | Manages time-based locking and bonus coefficients | 
| `NFTChecker.sol` | Verifies NFT ownership and lock permissions |
| `RevenueRebatePool.sol` | Handles protocol revenue collection and rebate into the staking system | 

---

## Liquid Staking Model

When a user deposits $CUR, the protocol mints $sCUR at a 1:1 ratio.

100 CUR deposited
        ↓
100 sCUR minted

The amount of $sCUR represents the user's staking position.

However, the economic value of $sCUR can increase through protocol revenue.

---
## Exchange Rate

The protocol tracks the amount of underlying $CUR and the total $sCUR supply.

$$
exchangeRate = \frac{totalUnderlying \times PRECISION}{totalSupply(sCUR)}
$$

For example:
**Initial:**

totalUnderlying = 1,000 CUR
totalSupply     = 1,000 sCUR

exchangeRate = 1.00 CUR / sCUR

**After the protocol generates 100 CUR of revenue:**
totalUnderlying = 1,100 CUR
totalSupply     = 1,000 sCUR

exchangeRate = 1.10 CUR / sCUR

**Therefore:**
1 sCUR = 1.10 CUR
100 sCUR = 110 CUR

**The important distinction is:**
sCUR quantity  → represents staking principal
exchange rate  → represents current economic value

---
### Global Reward Index

CUR Protocol uses a Compound-style global reward index to distribute staking rewards.

During each reward period, the total amount of newly released rewards is determined solely by the protocol's emission schedule:

$$ R_{total}=EmissionRate\times\Delta t $$

Where:

EmissionRate is the protocol's reward emission rate.
Δt is the elapsed time since the previous reward update.
The total emitted rewards are independent of the total weighted stake.

Each user's effective reward weight is calculated as:

$$ W_i = S_i \times B_i $$

Where:

$S_i$ is the user's effective staked amount.
$B_i$ is the user's lock-based bonus coefficient.
$W_i$ is the user's effective reward weight.

The global reward index is then updated according to:

$$ \boxed{ \Delta Index= \frac{R_{total}}{W_{total}} } $$

where:

$$ W_{total}=\sum_{i=1}^{n}W_i $$

A user's reward is calculated from their effective weight and the change in the global reward index:

$$ \boxed{ Reward_i=W_i\times\Delta Index } $$

Therefore:

$$ Reward_i = R_{total} \times \frac{W_i}{W_{total}} $$

This ensures that increasing a user's weight only changes their share of the reward pool; it does not increase the total amount of rewards emitted by the protocol.

## Installation

Install dependencies
```bash
forge install
```

Build
```bash
forge build
```

---

## Testing

Run all tests
```bash
forge test
```

Run with verbosity
```bash
forge test -vv
```

Run specific test
```bash
forge test --match-test test_Stake_Success -vv
```

Gas report
```bash
forge test --gas-report
```

Coverage
```bash
forge coverage
```
