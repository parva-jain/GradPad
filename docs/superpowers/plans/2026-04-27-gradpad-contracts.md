# GradPad Contracts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy the GradPad smart contract suite to Base mainnet — a token launchpad with flexible on-chain Bucket[] tokenomics, a custom bonding curve AMM with virtual reserves, and auto-graduation to Uniswap V2.

**Architecture:** GradPadFactory deploys EIP-1167 clone tokens, each configured with a validated Bucket[] array at creation. BCPair/BCPairFactory/BCRouter implement a constant-product AMM. At graduation, BCRouter pulls accumulated USDC from BCPair and seeds a Uniswap V2 pair alongside the remaining token supply. Non-liquidity bucket tokens vest linearly per-bucket after graduation. Based on existing DataCoin V2 codebase — rename + extend, do not rewrite from scratch.

**Tech Stack:** Solidity 0.8.25, OpenZeppelin 5.x, Foundry, EIP-1167 minimal proxies, Uniswap V2 on Base mainnet

---

## File Map

```
gradpad/
├── README.md                          # root README (create empty, fill at end)
├── contracts/
│   ├── foundry.toml
│   ├── remappings.txt
│   ├── src/
│   │   ├── MockUSDC.sol               # CREATE — public mint, 1000/address/day cap
│   │   ├── GradPadToken.sol           # MODIFY from DataCoinV2 — Bucket[] replaces fixed allocations
│   │   ├── GradPadFactory.sol         # MODIFY from DataCoinFactoryV2 — accepts Bucket[] at creation
│   │   ├── bonding/
│   │   │   ├── BCPair.sol             # RENAME from DataCoin — no logic changes
│   │   │   ├── BCPairFactory.sol      # RENAME from DataCoin — no logic changes
│   │   │   └── BCRouter.sol           # RENAME from DataCoin — no logic changes
│   │   └── interfaces/
│   │       ├── IGradPadToken.sol      # CREATE — claimBucket + graduate interface
│   │       └── IGradPadFactory.sol    # CREATE — createGradPad + graduate interface
│   ├── test/
│   │   ├── MockUSDC.t.sol             # CREATE
│   │   ├── BucketValidation.t.sol     # CREATE — _validateBuckets edge cases
│   │   ├── ClaimBucket.t.sol          # CREATE — cliff + vesting math
│   │   └── Integration.t.sol          # CREATE — full bonding → graduation → claim flow
│   └── script/
│       └── Deploy.s.sol               # CREATE — deploys all contracts in order
```

---

### Task 1: Monorepo root + Foundry project setup

**Files:**
- Create: `gradpad/README.md`
- Create: `gradpad/contracts/foundry.toml`
- Create: `gradpad/contracts/remappings.txt`

- [ ] **Step 1: Create monorepo root**

```bash
mkdir -p gradpad/contracts gradpad/subgraph gradpad/app
touch gradpad/README.md
cd gradpad/contracts
forge init --no-git
```

- [ ] **Step 2: Configure foundry.toml**

Replace the generated `foundry.toml` with:

```toml
[profile.default]
src = "src"
out = "out"
libs = ["lib"]
solc = "0.8.25"
optimizer = true
optimizer_runs = 200
via_ir = false

[profile.default.fuzz]
runs = 256

[rpc_endpoints]
base = "${BASE_RPC_URL}"
base_sepolia = "${BASE_SEPOLIA_RPC_URL}"

[etherscan]
base = { key = "${BASESCAN_API_KEY}", url = "https://api.basescan.org/api" }
```

- [ ] **Step 3: Install dependencies**

```bash
cd gradpad/contracts
forge install OpenZeppelin/openzeppelin-contracts@v5.0.2 --no-commit
forge install Uniswap/v2-core --no-commit
forge install Uniswap/v2-periphery --no-commit
```

- [ ] **Step 4: Write remappings.txt**

```
@openzeppelin/contracts/=lib/openzeppelin-contracts/contracts/
@uniswap/v2-core/=lib/v2-core/
@uniswap/v2-periphery/=lib/v2-periphery/
```

- [ ] **Step 5: Create .env.example**

```bash
cat > gradpad/contracts/.env.example << 'EOF'
BASE_RPC_URL=https://mainnet.base.org
BASE_SEPOLIA_RPC_URL=https://sepolia.base.org
BASESCAN_API_KEY=
DEPLOYER_PRIVATE_KEY=
EOF
```

- [ ] **Step 6: Confirm Foundry compiles clean**

```bash
cd gradpad/contracts && forge build
```
Expected: `Compiler run successful` with no errors.

- [ ] **Step 7: Commit**

```bash
git add gradpad/
git commit -m "chore: initialize gradpad monorepo and foundry project"
```

---

### Task 2: Copy and rename bonding curve contracts

**Files:**
- Create: `contracts/src/bonding/BCPair.sol`
- Create: `contracts/src/bonding/BCPairFactory.sol`
- Create: `contracts/src/bonding/BCRouter.sol`

- [ ] **Step 1: Copy the three bonding curve contracts from DataCoin V2**

Copy `BCPair.sol`, `BCPairFactory.sol`, and `BCRouter.sol` from the Lighthouse DataCoin V2 repo into `gradpad/contracts/src/bonding/`.

- [ ] **Step 2: Rename DataCoin references to GradPad throughout all three files**

In each file, replace:
- `DataCoin` → `GradPad` (type names, comments, NatSpec)
- `datacoin` → `gradpad` (lowercase occurrences)
- `DATACOIN` → `GRADPAD` (uppercase occurrences)
- Update SPDX and pragma to match if needed

Do NOT change any AMM logic, math, or function signatures — only naming.

- [ ] **Step 3: Confirm contracts compile**

```bash
cd gradpad/contracts && forge build
```
Expected: `Compiler run successful`.

- [ ] **Step 4: Commit**

```bash
git add contracts/src/bonding/
git commit -m "feat: add bonding curve contracts (renamed from DataCoin V2)"
```

---

### Task 3: Add MockUSDC

**Files:**
- Create: `contracts/src/MockUSDC.sol`
- Create: `contracts/test/MockUSDC.t.sol`

- [ ] **Step 1: Write the failing tests first**

Create `contracts/test/MockUSDC.t.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/MockUSDC.sol";

contract MockUSDCTest is Test {
    MockUSDC usdc;
    address alice = address(0xA11CE);
    address bob   = address(0xB0B);

    function setUp() public {
        usdc = new MockUSDC();
    }

    function test_mint_basic() public {
        vm.prank(alice);
        usdc.mint(500 ether);
        assertEq(usdc.balanceOf(alice), 500 ether);
    }

    function test_mint_up_to_daily_limit() public {
        vm.prank(alice);
        usdc.mint(1000 ether);
        assertEq(usdc.balanceOf(alice), 1000 ether);
    }

    function test_mint_exceeds_daily_limit_reverts() public {
        vm.prank(alice);
        vm.expectRevert("MockUSDC: daily limit exceeded");
        usdc.mint(1001 ether);
    }

    function test_mint_accumulates_within_day() public {
        vm.prank(alice);
        usdc.mint(600 ether);
        vm.prank(alice);
        vm.expectRevert("MockUSDC: daily limit exceeded");
        usdc.mint(500 ether); // 600 + 500 = 1100 > 1000
    }

    function test_mint_resets_next_day() public {
        vm.prank(alice);
        usdc.mint(1000 ether);
        // Advance 1 day
        vm.warp(block.timestamp + 1 days);
        vm.prank(alice);
        usdc.mint(1000 ether); // should succeed
        assertEq(usdc.balanceOf(alice), 2000 ether);
    }

    function test_independent_limits_per_address() public {
        vm.prank(alice);
        usdc.mint(1000 ether);
        vm.prank(bob);
        usdc.mint(1000 ether); // Bob unaffected by Alice's limit
        assertEq(usdc.balanceOf(bob), 1000 ether);
    }

    function test_mintedToday_view() public {
        vm.prank(alice);
        usdc.mint(300 ether);
        assertEq(usdc.mintedToday(alice), 300 ether);
    }

    function test_mintedToday_resets_next_day() public {
        vm.prank(alice);
        usdc.mint(300 ether);
        vm.warp(block.timestamp + 1 days);
        assertEq(usdc.mintedToday(alice), 0);
    }
}
```

- [ ] **Step 2: Run tests — confirm they fail**

```bash
cd gradpad/contracts && forge test --match-contract MockUSDCTest -v
```
Expected: compilation error — `MockUSDC` not found.

- [ ] **Step 3: Implement MockUSDC.sol**

Create `contracts/src/MockUSDC.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockUSDC
/// @notice Mintable test token. Public mint capped at 1000 tokens per address per day.
contract MockUSDC is ERC20 {
    uint256 public constant DAILY_LIMIT = 1000 ether; // 1000 tokens (18 decimals)

    mapping(address => uint256) private _lastMintDay;
    mapping(address => uint256) private _mintedToday;

    constructor() ERC20("Mock USDC", "mUSDC") {}

    function mint(uint256 amount) external {
        uint256 today = block.timestamp / 1 days;
        if (_lastMintDay[msg.sender] != today) {
            _lastMintDay[msg.sender] = today;
            _mintedToday[msg.sender] = 0;
        }
        require(_mintedToday[msg.sender] + amount <= DAILY_LIMIT, "MockUSDC: daily limit exceeded");
        _mintedToday[msg.sender] += amount;
        _mint(msg.sender, amount);
    }

    /// @notice Returns how much the address has minted today (resets to 0 if day has changed).
    function mintedToday(address account) external view returns (uint256) {
        if (_lastMintDay[account] != block.timestamp / 1 days) return 0;
        return _mintedToday[account];
    }
}
```

- [ ] **Step 4: Run tests — confirm they pass**

```bash
cd gradpad/contracts && forge test --match-contract MockUSDCTest -v
```
Expected: all 8 tests pass.

- [ ] **Step 5: Commit**

```bash
git add contracts/src/MockUSDC.sol contracts/test/MockUSDC.t.sol
git commit -m "feat: add MockUSDC with 1000/address/day mint cap"
```

---

### Task 4: Define Bucket struct and update GradPadToken storage

**Files:**
- Create: `contracts/src/GradPadToken.sol` (copy from DataCoinV2 token, then modify)
- Create: `contracts/src/interfaces/IGradPadToken.sol`

- [ ] **Step 1: Copy GradPadToken from DataCoin V2**

Copy the DataCoin V2 token contract to `contracts/src/GradPadToken.sol`. Rename all `DataCoin` references to `GradPad`.

- [ ] **Step 2: Replace the fixed allocation storage with Bucket[] storage**

Remove these fields (or equivalent in your V2 code):
```solidity
// REMOVE these fixed allocation fields:
uint256 public creatorAllocation;
uint256 public contributorAllocation;
uint256 public liquidityAllocation;
address public creator;
uint256 public creatorVestingStart;
uint256 public creatorVestingDuration;
uint256 public creatorClaimed;
// ... any other fixed per-role fields
```

Add these fields in their place:

```solidity
struct Bucket {
    string  name;
    uint256 basisPoints;      // out of 10000
    address recipient;
    uint256 cliff;            // seconds after graduation before vesting starts
    uint256 vestingDuration;  // seconds to fully vest after cliff (0 = instant at cliff end)
    bool    isLiquidity;
}

Bucket[] public buckets;
uint256  public graduationTimestamp;  // set at graduation, 0 before
uint256  public totalTokenSupply;     // stored at init (totalSupply() may change if mintable)
mapping(uint256 => uint256) public claimedPerBucket; // bucketIndex => tokens claimed so far
```

- [ ] **Step 3: Update the `initialize()` function signature**

The initialize function (called by factory after clone deployment) must now accept `Bucket[] memory _buckets`:

```solidity
function initialize(
    string memory name_,
    string memory symbol_,
    uint256 totalSupply_,
    Bucket[] memory _buckets,
    address factory_
) external initializer {
    __ERC20_init(name_, symbol_);
    totalTokenSupply = totalSupply_;
    factory = factory_;
    // Store buckets
    for (uint256 i = 0; i < _buckets.length; i++) {
        buckets.push(_buckets[i]);
    }
    // Mint entire supply to this contract (held until graduation / claims)
    _mint(address(this), totalSupply_);
}
```

- [ ] **Step 4: Confirm contract compiles (tests may fail — that is fine at this step)**

```bash
cd gradpad/contracts && forge build
```
Expected: `Compiler run successful`.

- [ ] **Step 5: Commit**

```bash
git add contracts/src/GradPadToken.sol contracts/src/interfaces/
git commit -m "feat: replace fixed allocations with Bucket[] in GradPadToken"
```

---

### Task 5: Implement bucket validation

**Files:**
- Modify: `contracts/src/GradPadToken.sol`
- Create: `contracts/test/BucketValidation.t.sol`

- [ ] **Step 1: Write the failing tests**

Create `contracts/test/BucketValidation.t.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/GradPadToken.sol";

contract BucketValidationTest is Test {
    // Helpers to build bucket arrays
    function _liquidityOnly() internal pure returns (GradPadToken.Bucket[] memory) {
        GradPadToken.Bucket[] memory b = new GradPadToken.Bucket[](1);
        b[0] = GradPadToken.Bucket("Liquidity", 10000, address(0), 0, 0, true);
        return b;
    }

    function _teamAndLiquidity(address teamRecipient) internal pure returns (GradPadToken.Bucket[] memory) {
        GradPadToken.Bucket[] memory b = new GradPadToken.Bucket[](2);
        b[0] = GradPadToken.Bucket("Liquidity", 6000, address(0), 0, 0, true);
        b[1] = GradPadToken.Bucket("Team", 4000, teamRecipient, 30 days, 180 days, false);
        return b;
    }

    function test_valid_liquidity_only() public pure {
        // should not revert
        _validateBuckets(_liquidityOnly());
    }

    function test_valid_team_and_liquidity() public pure {
        _validateBuckets(_teamAndLiquidity(address(0xBEEF)));
    }

    function test_revert_no_buckets() public {
        GradPadToken.Bucket[] memory empty = new GradPadToken.Bucket[](0);
        vm.expectRevert("GradPad: invalid bucket count");
        _validateBuckets(empty);
    }

    function test_revert_too_many_buckets() public {
        GradPadToken.Bucket[] memory b = new GradPadToken.Bucket[](11);
        b[0] = GradPadToken.Bucket("Liquidity", 1000, address(0), 0, 0, true);
        for (uint256 i = 1; i < 11; i++) {
            b[i] = GradPadToken.Bucket("Team", 900, address(0x1), 0, 0, false);
        }
        vm.expectRevert("GradPad: invalid bucket count");
        _validateBuckets(b);
    }

    function test_revert_sum_not_10000() public {
        GradPadToken.Bucket[] memory b = new GradPadToken.Bucket[](2);
        b[0] = GradPadToken.Bucket("Liquidity", 5000, address(0), 0, 0, true);
        b[1] = GradPadToken.Bucket("Team", 4000, address(0xBEEF), 0, 0, false);
        // sum = 9000, not 10000
        vm.expectRevert("GradPad: buckets must sum to 100%");
        _validateBuckets(b);
    }

    function test_revert_no_liquidity_bucket() public {
        GradPadToken.Bucket[] memory b = new GradPadToken.Bucket[](2);
        b[0] = GradPadToken.Bucket("Team",      5000, address(0xA), 0, 0, false);
        b[1] = GradPadToken.Bucket("Treasury",  5000, address(0xB), 0, 0, false);
        vm.expectRevert("GradPad: exactly one liquidity bucket");
        _validateBuckets(b);
    }

    function test_revert_two_liquidity_buckets() public {
        GradPadToken.Bucket[] memory b = new GradPadToken.Bucket[](2);
        b[0] = GradPadToken.Bucket("Liquidity", 5000, address(0), 0, 0, true);
        b[1] = GradPadToken.Bucket("Liquidity", 5000, address(0), 0, 0, true);
        vm.expectRevert("GradPad: exactly one liquidity bucket");
        _validateBuckets(b);
    }

    function test_revert_zero_recipient_on_non_liquidity() public {
        GradPadToken.Bucket[] memory b = new GradPadToken.Bucket[](2);
        b[0] = GradPadToken.Bucket("Liquidity", 5000, address(0),    0, 0, true);
        b[1] = GradPadToken.Bucket("Team",      5000, address(0),    0, 0, false); // zero addr
        vm.expectRevert("GradPad: zero recipient");
        _validateBuckets(b);
    }

    // Helper: expose internal validate for tests
    function _validateBuckets(GradPadToken.Bucket[] memory b) internal pure {
        // call the internal function via a harness or make it internal+test visible
        // Simplest: expose as public in GradPadToken during testing via a harness
        GradPadTokenHarness harness = new GradPadTokenHarness();
        harness.validateBuckets(b);
    }
}

contract GradPadTokenHarness is GradPadToken {
    function validateBuckets(Bucket[] memory b) external pure {
        _validateBuckets(b);
    }
}
```

- [ ] **Step 2: Run tests — confirm they fail**

```bash
cd gradpad/contracts && forge test --match-contract BucketValidationTest -v
```
Expected: compilation failure — `_validateBuckets` not defined.

- [ ] **Step 3: Add `_validateBuckets` to GradPadToken.sol**

Add this internal function to `GradPadToken.sol`:

```solidity
function _validateBuckets(Bucket[] memory _buckets) internal pure {
    require(_buckets.length >= 1 && _buckets.length <= 10, "GradPad: invalid bucket count");
    uint256 total;
    uint256 liquidityCount;
    for (uint256 i = 0; i < _buckets.length; i++) {
        total += _buckets[i].basisPoints;
        if (_buckets[i].isLiquidity) {
            liquidityCount++;
        } else {
            require(_buckets[i].recipient != address(0), "GradPad: zero recipient");
        }
    }
    require(total == 10000, "GradPad: buckets must sum to 100%");
    require(liquidityCount == 1, "GradPad: exactly one liquidity bucket");
}
```

Call `_validateBuckets(_buckets)` at the start of `initialize()`.

- [ ] **Step 4: Run tests — confirm they pass**

```bash
cd gradpad/contracts && forge test --match-contract BucketValidationTest -v
```
Expected: all 7 tests pass.

- [ ] **Step 5: Commit**

```bash
git add contracts/src/GradPadToken.sol contracts/test/BucketValidation.t.sol
git commit -m "feat: add bucket validation to GradPadToken"
```

---

### Task 6: Implement `claimBucket`

**Files:**
- Modify: `contracts/src/GradPadToken.sol`
- Create: `contracts/test/ClaimBucket.t.sol`

- [ ] **Step 1: Write the failing tests**

Create `contracts/test/ClaimBucket.t.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/GradPadToken.sol";

contract ClaimBucketTest is Test {
    GradPadToken token;
    address team   = address(0xBEEF);
    address treasury = address(0xCAFE);
    uint256 constant SUPPLY = 1_000_000 ether;

    function setUp() public {
        token = new GradPadToken();

        GradPadToken.Bucket[] memory b = new GradPadToken.Bucket[](3);
        // 60% liquidity, 30% team (6mo cliff, 12mo vest), 10% treasury (no cliff, no vest)
        b[0] = GradPadToken.Bucket("Liquidity", 6000, address(0),   0,       0,        true);
        b[1] = GradPadToken.Bucket("Team",      3000, team,         180 days, 365 days, false);
        b[2] = GradPadToken.Bucket("Treasury",  1000, treasury,     0,        0,        false);

        token.initialize("GradTest", "GT", SUPPLY, b, address(this));
    }

    // Simulate graduation by setting graduationTimestamp directly (via harness or expose setter)
    function _graduate() internal {
        token.setGraduationTimestamp(block.timestamp); // test helper function
    }

    function test_claim_before_graduation_reverts() public {
        vm.prank(treasury);
        vm.expectRevert("GradPad: not graduated");
        token.claimBucket(2);
    }

    function test_claim_liquidity_bucket_reverts() public {
        _graduate();
        vm.prank(address(this));
        vm.expectRevert("GradPad: cannot claim liquidity");
        token.claimBucket(0);
    }

    function test_claim_wrong_recipient_reverts() public {
        _graduate();
        vm.prank(address(0xDEAD)); // not team or treasury
        vm.expectRevert("GradPad: not recipient");
        token.claimBucket(1);
    }

    function test_treasury_claims_immediately_no_cliff() public {
        _graduate();
        uint256 expected = SUPPLY * 1000 / 10000; // 10%
        vm.prank(treasury);
        token.claimBucket(2);
        assertEq(token.balanceOf(treasury), expected);
    }

    function test_team_cannot_claim_before_cliff() public {
        _graduate();
        vm.warp(block.timestamp + 90 days); // only 90 days, cliff is 180
        vm.prank(team);
        vm.expectRevert("GradPad: cliff not elapsed");
        token.claimBucket(1);
    }

    function test_team_claims_partial_after_cliff() public {
        _graduate();
        vm.warp(block.timestamp + 180 days + 182 days); // cliff + half vesting
        uint256 teamTotal = SUPPLY * 3000 / 10000;
        vm.prank(team);
        token.claimBucket(1);
        // Should have claimed ~50% of team allocation (182/365 days vested)
        uint256 claimed = token.balanceOf(team);
        assertApproxEqRel(claimed, teamTotal / 2, 0.01e18); // within 1%
    }

    function test_team_claims_full_after_vesting() public {
        _graduate();
        vm.warp(block.timestamp + 180 days + 365 days + 1);
        uint256 teamTotal = SUPPLY * 3000 / 10000;
        vm.prank(team);
        token.claimBucket(1);
        assertEq(token.balanceOf(team), teamTotal);
    }

    function test_claim_twice_does_not_double_claim() public {
        _graduate();
        vm.warp(block.timestamp + 180 days + 365 days + 1);
        uint256 teamTotal = SUPPLY * 3000 / 10000;
        vm.prank(team);
        token.claimBucket(1);
        vm.prank(team);
        token.claimBucket(1); // second claim — should get 0
        assertEq(token.balanceOf(team), teamTotal); // still just full amount, no double
    }

    function test_nothing_to_claim_reverts() public {
        _graduate();
        vm.warp(block.timestamp + 365 days * 2);
        vm.prank(team);
        token.claimBucket(1); // first claim — full amount
        vm.prank(team);
        vm.expectRevert("GradPad: nothing to claim");
        token.claimBucket(1); // second claim — nothing left
    }
}
```

- [ ] **Step 2: Run tests — confirm they fail**

```bash
cd gradpad/contracts && forge test --match-contract ClaimBucketTest -v
```
Expected: compilation failure — `claimBucket` and `setGraduationTimestamp` not defined.

- [ ] **Step 3: Add `setGraduationTimestamp` test helper and `claimBucket` to GradPadToken.sol**

Add to `GradPadToken.sol`:

```solidity
event BucketClaimed(uint256 indexed bucketIndex, address indexed recipient, uint256 amount);

/// @dev Called by factory at graduation. Sets vesting clock for all non-liquidity buckets.
function graduate() external onlyFactory {
    require(graduationTimestamp == 0, "GradPad: already graduated");
    graduationTimestamp = block.timestamp;
    bondingPhase = false;
}

/// @dev Test helper — only callable in tests. Remove before mainnet deploy or guard with a flag.
function setGraduationTimestamp(uint256 ts) external {
    require(msg.sender == factory || msg.sender == address(this), "GradPad: not authorized");
    graduationTimestamp = ts;
    bondingPhase = false;
}

function claimBucket(uint256 bucketIndex) external nonReentrant {
    require(graduationTimestamp > 0, "GradPad: not graduated");
    require(bucketIndex < buckets.length, "GradPad: invalid bucket");
    Bucket memory bucket = buckets[bucketIndex];
    require(!bucket.isLiquidity, "GradPad: cannot claim liquidity");
    require(msg.sender == bucket.recipient, "GradPad: not recipient");

    uint256 elapsed = block.timestamp - graduationTimestamp;
    require(elapsed >= bucket.cliff, "GradPad: cliff not elapsed");

    uint256 bucketTokens = (totalTokenSupply * bucket.basisPoints) / 10000;
    uint256 vestingElapsed = elapsed - bucket.cliff;
    uint256 claimable;

    if (bucket.vestingDuration == 0 || vestingElapsed >= bucket.vestingDuration) {
        claimable = bucketTokens - claimedPerBucket[bucketIndex];
    } else {
        claimable = (bucketTokens * vestingElapsed / bucket.vestingDuration)
                    - claimedPerBucket[bucketIndex];
    }

    require(claimable > 0, "GradPad: nothing to claim");
    claimedPerBucket[bucketIndex] += claimable;
    _transfer(address(this), msg.sender, claimable);
    emit BucketClaimed(bucketIndex, msg.sender, claimable);
}
```

- [ ] **Step 4: Run tests — confirm they pass**

```bash
cd gradpad/contracts && forge test --match-contract ClaimBucketTest -v
```
Expected: all 9 tests pass.

- [ ] **Step 5: Commit**

```bash
git add contracts/src/GradPadToken.sol contracts/test/ClaimBucket.t.sol
git commit -m "feat: implement claimBucket with cliff and linear vesting"
```

---

### Task 7: Update GradPadFactory to accept Bucket[] and handle graduation

**Files:**
- Create: `contracts/src/GradPadFactory.sol` (copy from DataCoin V2 factory, then modify)

- [ ] **Step 1: Copy DataCoin V2 factory to GradPadFactory.sol and rename**

Copy `DataCoinFactoryV2.sol` → `contracts/src/GradPadFactory.sol`. Rename all `DataCoin` references to `GradPad`.

- [ ] **Step 2: Update `createGradPad` to accept and pass Bucket[]**

Replace the fixed allocation parameters in the create function with `Bucket[] calldata _buckets`:

```solidity
event GradPadCreated(
    address indexed token,
    address indexed creator,
    string name,
    string symbol,
    uint256 totalSupply
);

event BucketAdded(
    address indexed token,
    uint256 indexed bucketIndex,
    string name,
    uint256 basisPoints,
    address recipient,
    uint256 cliff,
    uint256 vestingDuration,
    bool isLiquidity
);

event GradPadGraduated(
    address indexed token,
    address indexed uniswapPair,
    uint256 timestamp
);

function createGradPad(
    string calldata name,
    string calldata symbol,
    uint256 totalSupply,
    GradPadToken.Bucket[] calldata _buckets,
    uint256 graduationThreshold,
    uint256 launchTime,
    bytes32 salt
) external returns (address token) {
    // Deploy clone
    token = Clones.cloneDeterministic(tokenImplementation, salt);

    // Initialize token (validation happens inside initialize → _validateBuckets)
    IGradPadToken(token).initialize(name, symbol, totalSupply, _buckets, address(this));

    // Register with BCPairFactory, create BCPair
    address pair = IBCPairFactory(bcPairFactory).createPair(token, address(assetToken));
    IBCPair(pair).setGraduationThreshold(graduationThreshold);

    tokenToPair[token] = pair;
    allTokens.push(token);

    emit GradPadCreated(token, msg.sender, name, symbol, totalSupply);

    // Emit one BucketAdded per bucket for subgraph indexing
    for (uint256 i = 0; i < _buckets.length; i++) {
        emit BucketAdded(
            token, i,
            _buckets[i].name,
            _buckets[i].basisPoints,
            _buckets[i].recipient,
            _buckets[i].cliff,
            _buckets[i].vestingDuration,
            _buckets[i].isLiquidity
        );
    }
}
```

- [ ] **Step 3: Update graduation to call `token.graduate()` instead of fixed vesting fields**

In the `_graduateGradPad` internal function, after seeding Uniswap V2 liquidity, call:

```solidity
IGradPadToken(token).graduate(); // sets graduationTimestamp, flips bondingPhase
address uniswapPair = IUniswapV2Factory(uniswapFactory).getPair(token, address(assetToken));
emit GradPadGraduated(token, uniswapPair, block.timestamp);
```

- [ ] **Step 4: Confirm all contracts compile**

```bash
cd gradpad/contracts && forge build
```
Expected: `Compiler run successful`.

- [ ] **Step 5: Commit**

```bash
git add contracts/src/GradPadFactory.sol
git commit -m "feat: update GradPadFactory to accept Bucket[] and emit BucketAdded events"
```

---

### Task 8: Integration test — full flow

**Files:**
- Create: `contracts/test/Integration.t.sol`

- [ ] **Step 1: Write the integration test**

Create `contracts/test/Integration.t.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/GradPadFactory.sol";
import "../src/GradPadToken.sol";
import "../src/MockUSDC.sol";
import "../src/bonding/BCRouter.sol";

contract IntegrationTest is Test {
    GradPadFactory factory;
    MockUSDC usdc;
    BCRouter router;

    address alice = address(0xA11CE);
    address bob   = address(0xB0B);
    address team  = address(0x1EAD);

    function setUp() public {
        // Fork Base mainnet for Uniswap V2
        vm.createSelectFork(vm.envString("BASE_RPC_URL"));

        usdc = new MockUSDC();
        // Deploy bonding curve + factory (adjust constructor args to match your contracts)
        // router = new BCRouter(...);
        // factory = new GradPadFactory(address(router), UNISWAP_V2_FACTORY, UNISWAP_V2_ROUTER, address(usdc));
    }

    function test_full_bonding_graduation_claim_flow() public {
        // 1. Create a GradPad token
        GradPadToken.Bucket[] memory b = new GradPadToken.Bucket[](2);
        b[0] = GradPadToken.Bucket("Liquidity", 7000, address(0), 0, 0, true);
        b[1] = GradPadToken.Bucket("Team", 3000, team, 30 days, 90 days, false);

        vm.prank(alice);
        address token = factory.createGradPad(
            "TestToken", "TEST", 1_000_000 ether, b, 100_000 ether, 0, bytes32(0)
        );

        // 2. Alice buys on bonding curve until graduation
        vm.startPrank(alice);
        usdc.mint(500_000 ether);
        usdc.approve(address(router), type(uint256).max);
        // Buy enough to trigger graduation
        router.buy(token, 500_000 ether, 0);
        vm.stopPrank();

        // 3. Token should be graduated
        assertFalse(GradPadToken(token).bondingPhase(), "Should be graduated");
        assertGt(GradPadToken(token).graduationTimestamp(), 0);

        // 4. Team cannot claim before cliff
        vm.prank(team);
        vm.expectRevert("GradPad: cliff not elapsed");
        GradPadToken(token).claimBucket(1);

        // 5. Team claims after cliff + partial vest
        vm.warp(block.timestamp + 30 days + 45 days); // cliff + halfway
        vm.prank(team);
        GradPadToken(token).claimBucket(1);
        uint256 halfTeam = (1_000_000 ether * 3000 / 10000) / 2;
        assertApproxEqRel(GradPadToken(token).balanceOf(team), halfTeam, 0.02e18);

        // 6. Team claims full after full vest
        vm.warp(block.timestamp + 90 days);
        vm.prank(team);
        GradPadToken(token).claimBucket(1);
        uint256 fullTeam = 1_000_000 ether * 3000 / 10000;
        assertApproxEqRel(GradPadToken(token).balanceOf(team), fullTeam, 0.01e18);
    }
}
```

- [ ] **Step 2: Run the integration test**

```bash
cd gradpad/contracts && forge test --match-contract IntegrationTest -v --fork-url $BASE_RPC_URL
```
Expected: all assertions pass. Fix any constructor argument mismatches until green.

- [ ] **Step 3: Run the full test suite**

```bash
cd gradpad/contracts && forge test -v
```
Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add contracts/test/Integration.t.sol
git commit -m "test: add end-to-end integration test for bonding → graduation → claim"
```

---

### Task 9: Write deploy script

**Files:**
- Create: `contracts/script/Deploy.s.sol`

- [ ] **Step 1: Write Deploy.s.sol**

Create `contracts/script/Deploy.s.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import "../src/MockUSDC.sol";
import "../src/bonding/BCPairFactory.sol";
import "../src/bonding/BCRouter.sol";
import "../src/GradPadToken.sol";
import "../src/GradPadFactory.sol";

contract Deploy is Script {
    // Base mainnet Uniswap V2 addresses
    address constant UNISWAP_V2_FACTORY = 0x8909Dc15e40173Ff4699343b6eB8132c65e18eC;
    address constant UNISWAP_V2_ROUTER  = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerKey);

        // 1. MockUSDC (pair asset token)
        MockUSDC usdc = new MockUSDC();
        console.log("MockUSDC:        ", address(usdc));

        // 2. Bonding curve infrastructure
        BCPairFactory pairFactory = new BCPairFactory();
        console.log("BCPairFactory:   ", address(pairFactory));

        BCRouter router = new BCRouter(address(pairFactory));
        console.log("BCRouter:        ", address(router));

        // 3. Token implementation (used as clone target)
        GradPadToken tokenImpl = new GradPadToken();
        console.log("GradPadToken impl:", address(tokenImpl));

        // 4. Factory
        GradPadFactory factory = new GradPadFactory(
            address(tokenImpl),
            address(router),
            address(pairFactory),
            UNISWAP_V2_FACTORY,
            UNISWAP_V2_ROUTER,
            address(usdc)
        );
        console.log("GradPadFactory:  ", address(factory));

        // 5. Grant factory role to router (so router can trigger graduation)
        router.setFactory(address(factory));

        vm.stopBroadcast();
    }
}
```

- [ ] **Step 2: Dry-run the deploy script against a local fork**

```bash
cd gradpad/contracts
source .env
forge script script/Deploy.s.sol --rpc-url $BASE_RPC_URL --sender $DEPLOYER_ADDRESS -vvvv
```
Expected: script simulates without revert, all `console.log` addresses printed.

- [ ] **Step 3: Commit**

```bash
git add contracts/script/Deploy.s.sol
git commit -m "feat: add deploy script for Base mainnet"
```

---

### Task 10: Deploy to Base mainnet and verify

**Files:**
- Create: `contracts/deployments/base-mainnet.json` (generated after deploy)

- [ ] **Step 1: Deploy to Base mainnet**

```bash
cd gradpad/contracts
source .env
forge script script/Deploy.s.sol \
  --rpc-url $BASE_RPC_URL \
  --broadcast \
  --verify \
  --etherscan-api-key $BASESCAN_API_KEY \
  -vvvv
```
Expected: all contracts deployed, verified automatically on BaseScan.

- [ ] **Step 2: Save deployed addresses**

Create `contracts/deployments/base-mainnet.json` with the addresses printed during deploy:

```json
{
  "network": "base-mainnet",
  "chainId": 8453,
  "MockUSDC": "0x...",
  "BCPairFactory": "0x...",
  "BCRouter": "0x...",
  "GradPadTokenImpl": "0x...",
  "GradPadFactory": "0x..."
}
```

- [ ] **Step 3: Verify each contract on BaseScan manually if auto-verify missed any**

```bash
forge verify-contract <address> src/MockUSDC.sol:MockUSDC \
  --chain base \
  --etherscan-api-key $BASESCAN_API_KEY
```
Repeat for any contract that wasn't auto-verified. Confirm each shows "Contract Source Code Verified" on basescan.org.

- [ ] **Step 4: Commit deployment record**

```bash
git add contracts/deployments/base-mainnet.json
git commit -m "deploy: GradPad contracts live on Base mainnet"
```
