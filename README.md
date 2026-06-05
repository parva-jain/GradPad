# GradPad

A token launchpad where every token starts on a virtual-reserve bonding curve and automatically graduates to Uniswap V2 once a USDC threshold is met.

---

## Repository Layout

```
contracts/   Solidity smart contracts (Foundry)
subgraph/    The Graph indexer for on-chain events
app/         Frontend application
```

---

## Contracts

### Overview

Tokens are created through a single upgradeable factory (`GradPadFactoryV1`, deployed behind a UUPS ERC1967 proxy). Each token gets its own bonding curve pair (`BCPair`) that uses a constant-product formula with a virtual initial reserve — so price discovery starts at a predictable level without requiring any upfront USDC.

Once a token's bonding curve accumulates enough real USDC (the graduation threshold), the factory pulls all liquidity and seeds a Uniswap V2 pool, locking the LP tokens permanently. Non-liquidity token allocations (team, advisors, etc.) vest linearly starting from the graduation timestamp.

**Key contracts:**

| Contract | Role |
|---|---|
| `GradPadFactoryV1` | Main entry point — create tokens, buy, sell, graduate. UUPS upgradeable. |
| `GradPadToken` | Per-token ERC20 with ERC20Permit and vesting buckets. Deployed as EIP-1167 clones. |
| `BCPair` | Constant-product bonding curve pair. Tracks real vs. virtual USDC to prevent donation-based graduation spoofing. |
| `BCPairFactory` | Deploys `BCPair` clones with nonce-based salts (collision-safe). |
| `BCRouter` | AMM execution layer — gated by `EXECUTOR_ROLE` so only the factory can trade. |

For a detailed contract-by-contract breakdown, see [`contracts/README.md`](contracts/README.md).

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)

### Environment

Create `contracts/.env`:

```env
DEPLOYER_PRIVATE_KEY=0x...
BASE_RPC_URL=https://mainnet.base.org
BASE_SEPOLIA_RPC_URL=https://sepolia.base.org
BASESCAN_API_KEY=...
```

### Compile

```bash
cd contracts
forge build
```

### Test

```bash
cd contracts

# Offline tests only (no RPC required)
forge test --no-match-contract "Fork|Integration"

# Full suite including Base mainnet fork tests
forge test
```

### Deploy

```bash
cd contracts

# Dry run
forge script script/Deploy.s.sol \
  --rpc-url $BASE_RPC_URL \
  --sender $DEPLOYER_ADDRESS \
  -vvvv

# Live deploy + verify
forge script script/Deploy.s.sol \
  --rpc-url $BASE_RPC_URL \
  --broadcast --verify \
  --etherscan-api-key $BASESCAN_API_KEY \
  -vvvv
```

The script prints every deployed address. Copy the proxy address (`GradPadFactoryV1 proxy`) and the deployment block number — you will need both for the subgraph.

---

## Subgraph

*Documentation coming soon.*

The subgraph indexes `GradPadFactoryV1` events (token creation, trades, graduation) and `GradPadToken` events (bucket claims) to power the frontend's real-time feed, price charts, and vesting dashboards.

After deploying contracts, update `subgraph/subgraph.yaml` with the proxy address and start block, then deploy to The Graph.

---

## Frontend

*Documentation coming soon.*

---
