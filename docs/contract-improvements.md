# GradPad Contract Improvements

**Status:** Ready to implement  
**Priority:** Fix bugs first, then optimisations, then features

---

## Bug Fixes (implement first)

### BUG-1: BCPairFactory salt collision on same-block deployments

**File:** `contracts/src/bonding/BCPairFactory.sol` — `createPair()` lines 63–70

**Problem:** Salt is derived from `token0 + token1 + block.timestamp`. Two tokens launched in the same block produce identical salts; the second `CREATE2` call reverts.

**Fix:** Replace `timestamp()` with a monotonic nonce.

```solidity
// Add to state variables:
uint256 private _pairNonce;

// Replace the assembly salt block with:
bytes32 deploySalt = keccak256(abi.encodePacked(token0, token1, _pairNonce++));
pair = Clones.cloneDeterministic(pairImpl, deploySalt);
```

---

### BUG-2: `assetBalance()` reads live ERC-20 balance instead of tracked reserve

**File:** `contracts/src/bonding/BCPair.sol` — `assetBalance()` line 189

**Problem:** Anyone can `transfer` USDC directly to the pair contract, inflating `assetBalance()` and potentially triggering spurious graduation in `GradPadFactory.buyGPToken()`.

**Fix:** Return `_pool.reserve1` (the tracked reserve) instead of the live balance.

```solidity
// Before:
function assetBalance() external view returns (uint256) {
    return IERC20(token1).balanceOf(address(this));
}

// After:
function assetBalance() external view returns (uint256) {
    return _pool.reserve1;
}
```

Note: `transferLiquidity()` still needs to transfer the actual balance (in case of rounding dust). That call already reads balances directly at withdrawal time so no change needed there.

---

### BUG-3: `setGraduationTimestamp` allows `address(this)` to call itself

**File:** `contracts/src/GradPadToken.sol` — `setGraduationTimestamp()` lines 201–205

**Problem:** The `msg.sender == address(this)` branch is dead code in production (no path calls it) and is a confusing surface area — each clone's `address(this)` is different from the implementation's, so the guard doesn't even protect uniformly. It exists only to support a test pattern.

**Fix:** Remove the `address(this)` branch entirely. In tests, deploy the test contract as the factory (set `factory = address(testContract)` in setUp) instead of relying on self-calls.

```solidity
// Before:
function setGraduationTimestamp(uint256 ts) external {
    if (msg.sender != factory && msg.sender != address(this)) revert Unauthorized();
    ...
}

// After: remove the function entirely from production code.
// Tests that need force-graduation should set themselves as factory in setUp.
```

---

## Gas Optimisations

### OPT-1: Pack BCPair reserves as `uint128` (Uniswap V2 pattern)

**File:** `contracts/src/bonding/BCPair.sol`

**Problem:** The `Pool` struct uses 4 separate 32-byte storage slots. Every swap does 4 SLOADs. Packing reserves as `uint128` halves the storage reads — exactly the rationale behind Uniswap V2's design.

**Fix:** Replace the `Pool` struct with packed slot layout.

```solidity
// Remove Pool struct. Replace _pool state variable with:
uint128 private _reserve0;    // slot 0, lower 128 bits — GradPad reserve
uint128 private _reserve1;    // slot 0, upper 128 bits — Asset reserve
uint256 private _k;           // slot 1 — constant product (set at init, acts as floor)
uint32  private _lastUpdated; // slot 2 lower 32 bits

// Update getPool() to reconstruct the struct:
function getPool() external view returns (Pool memory) {
    return Pool({
        reserve0: _reserve0,
        reserve1: _reserve1,
        k: _k,
        lastUpdated: _lastUpdated
    });
}

// Update all internal reads/writes to use the packed fields directly.
```

Keep the `Pool` struct as a memory-only return type for `getPool()` to preserve the external interface.

---

### OPT-2: `unchecked` arithmetic in hot paths

**File:** `contracts/src/bonding/BCRouter.sol` — `buy()` and `sell()`  
**File:** `contracts/src/GradPadToken.sol` — `claimBucket()`

The subtractions below are guaranteed safe by checks immediately above them. Wrapping in `unchecked` saves ~20 gas each per call.

**BCRouter.buy():**
```solidity
// newTokenReserve < pool.reserve0 is guaranteed by the AMM formula (reserve shrinks on buy)
unchecked {
    tokensOut = pool.reserve0 - newTokenReserve;
}
```

**BCRouter.sell():**
```solidity
// newAssetReserve < pool.reserve1 is guaranteed by the AMM formula (reserve shrinks on sell)
unchecked {
    assetOut = pool.reserve1 - newAssetReserve;
}
```

**GradPadToken.claimBucket():**
```solidity
// elapsed >= bucket.cliff is checked on line above with require()
unchecked {
    uint256 vestingElapsed = elapsed - bucket.cliff;
}
// bucketTokens * vestingElapsed / vestingDuration <= bucketTokens, and
// claimedPerBucket[bucketIndex] <= that value by invariant
unchecked {
    claimable = (bucketTokens * vestingElapsed / bucket.vestingDuration)
                - claimedPerBucket[bucketIndex];
}
```

---

### OPT-3: Replace `Clones.cloneDeterministic` with inline assembly clone deployer

**File:** `contracts/src/bonding/BCPairFactory.sol` — `createPair()`  
**File:** `contracts/src/GradPadFactory.sol` — `createGPToken()`

Writing the EIP-1167 deployer in assembly demonstrates understanding of what the clone proxy actually is. Replace the OZ library call with a private function:

```solidity
error CloneDeploymentFailed();

function _cloneDeterministic(address implementation, bytes32 salt)
    private
    returns (address instance)
{
    assembly {
        // EIP-1167 minimal proxy: 45 bytes
        // Packs the implementation address into the standard delegation bytecode
        let ptr := mload(0x40)
        mstore(ptr,         0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
        mstore(add(ptr, 0x14), shl(0x60, implementation))
        mstore(add(ptr, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
        instance := create2(0, ptr, 0x37, salt)
    }
    if (instance == address(0)) revert CloneDeploymentFailed();
}
```

Remove the `Clones` import after replacing both call sites.

---

## Feature Additions

### FEAT-1: EIP-2612 permit support on GradPadToken

**File:** `contracts/src/GradPadToken.sol`

**Why:** Allows users to sign an off-chain approval and pass it into `buyGPToken` — approve + buy in one transaction instead of two. Shows EIP knowledge. OZ provides the extension.

**Fix:**

```solidity
// Add import:
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

// Change contract declaration:
contract GradPadToken is ERC20, ERC20Permit, ReentrancyGuard {

// ERC20Permit requires a name in its constructor. Since GradPadToken uses
// empty-string ERC20 constructor (clone pattern), override _EIP712Name:
function _EIP712Name() internal view override returns (string memory) {
    return _tokenName;
}
```

Then add a convenience function on `GradPadFactory`:

```solidity
/// @notice Sell using an EIP-2612 permit — approve + sell in one tx.
function sellGPTokenWithPermit(
    address token,
    uint256 tokenAmountIn,
    address to,
    uint256 minAssetOut,
    uint256 deadline,
    uint8 v, bytes32 r, bytes32 s
) external returns (uint256 assetOut) {
    IERC20Permit(token).permit(msg.sender, address(this), tokenAmountIn, deadline, v, r, s);
    return sellGPToken(token, tokenAmountIn, to, minAssetOut);
}
```

A `permitBuyGPToken` variant needs permit on MockUSDC (which is not ERC20Permit), so skip that for now unless you add permit to MockUSDC too.

---

### FEAT-2: UUPS upgrade pattern (alternative to Transparent)

**Files:** `contracts/src/GradPadFactoryV1.sol`, `contracts/src/GradPadFactoryV2.sol`

**Why:** Transparent Proxy incurs an SLOAD on every call to check whether the caller is the ProxyAdmin — even for regular user calls. UUPS moves upgrade logic into the implementation and eliminates ProxyAdmin entirely, saving gas on every interaction. The trade-off: if you upgrade to an implementation that lacks `upgradeTo()`, the contract is bricked (Transparent's admin check is externally safe from this).

**Fix:**

```solidity
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

/// @dev Uses UUPS rather than Transparent Proxy to eliminate the per-call
///      ProxyAdmin SLOAD. Trade-off: upgrade safety relies on the new
///      implementation retaining a valid upgradeTo() — there is no external
///      safety net. Mitigated by always testing upgrades before executing on mainnet.
contract GradPadFactoryV1 is Initializable, UUPSUpgradeable {

    // Add the authorization hook — only owner can upgrade:
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
```

Deployment uses `ERC1967Proxy` directly (no ProxyAdmin contract):
```solidity
// In deploy script:
ERC1967Proxy proxy = new ERC1967Proxy(
    address(implV1),
    abi.encodeCall(GradPadFactoryV1.initialize, (...))
);
```

Write a `UpgradeTest.t.sol` that:
1. Deploys V1 through ERC1967Proxy
2. Verifies state
3. Upgrades to V2 via `upgradeToAndCall`
4. Verifies old state persists + new V2 function available
5. Verifies a non-owner cannot call `upgradeTo`

---

## Implementation Order

```
1. BUG-1   BCPairFactory nonce salt
2. BUG-2   assetBalance() tracked reserve
3. BUG-3   Remove setGraduationTimestamp self-call
4. OPT-1   Pack BCPair reserves as uint128
5. OPT-2   unchecked arithmetic in hot paths
6. OPT-3   Assembly clone deployer
7. FEAT-1  EIP-2612 permit on GradPadToken
8. FEAT-2  UUPS on GradPadFactoryV1/V2
```

Run `forge test` after each numbered item before moving to the next.

---

## Test coverage to add/update

- **BUG-1:** Test two `createGPToken` calls in same block (use `vm.warp` to same timestamp) — should not revert.
- **BUG-2:** Test direct USDC transfer to BCPair does not affect graduation threshold check.
- **OPT-1:** Verify `getPool()` returns correct values after packing refactor.
- **OPT-2:** Fuzz tests for `claimBucket` should still pass after `unchecked` changes.
- **FEAT-1:** Test `sellGPTokenWithPermit` with a signed EIP-712 permit (use `vm.sign`).
- **FEAT-2:** Full upgrade test sequence in `UpgradeTest.t.sol` as described above.
