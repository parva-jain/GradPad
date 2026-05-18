// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title GradPadToken
/// @notice ERC20 token deployed by GradPadFactory as an EIP-1167 minimal proxy clone.
///         Supply is split into named Buckets — each bucket defines who gets what share,
///         when they can claim it (cliff), and how long it vests linearly.
///         Exactly one bucket must be flagged `isLiquidity`; that share seeds the Uniswap V2
///         pair at graduation. All other buckets vest on-chain after graduation.
/// @dev    Clone-friendly: constructor does nothing. `initialize()` is called once by factory.
///         Name/symbol are stored in private fields because the ERC20 constructor cannot run
///         on clones (they copy bytecode, not constructor effects).
contract GradPadToken is ERC20, ReentrancyGuard {
    // ============ STRUCTS ============

    /// @notice A single allocation slice of the total token supply.
    /// @param name            Human-readable label (e.g. "Team", "Liquidity").
    /// @param basisPoints     Share of totalSupply, out of 10 000 (e.g. 3000 = 30%).
    /// @param recipient       Address that can call claimBucket. Ignored when isLiquidity = true.
    /// @param cliff           Seconds after graduation before vesting starts.
    /// @param vestingDuration Seconds from cliff end to full vest. 0 = instant at cliff end.
    /// @param isLiquidity     If true, this share is transferred to the BCPair at launch and
    ///                        later routed into Uniswap V2 at graduation. No claiming.
    struct Bucket {
        string  name;
        uint256 basisPoints;
        address recipient;
        uint256 cliff;
        uint256 vestingDuration;
        bool    isLiquidity;
    }

    // ============ CONSTANTS ============

    uint256 public constant BASIS_POINTS = 10_000;

    // ============ STATE ============

    // Stored separately because ERC20 constructor can't run on clones.
    string private _tokenName;
    string private _tokenSymbol;

    /// @notice Factory that deployed this clone. Used for access control.
    address public factory;

    /// @notice The Bucket array. Immutable after initialization.
    Bucket[] public buckets;

    /// @notice Total supply frozen at initialization time.
    ///         Stored explicitly because totalSupply() reflects live minted supply;
    ///         bucket math always references the original figure.
    uint256 public totalTokenSupply;

    /// @notice Unix timestamp set at graduation. Zero while still in bonding phase.
    uint256 public graduationTimestamp;

    /// @notice True during bonding curve phase. Flips to false at graduation.
    bool public bondingPhase;

    /// @notice Tracks tokens already paid out per bucket to prevent double-claiming.
    mapping(uint256 => uint256) public claimedPerBucket;

    // ============ EVENTS ============

    event Graduated(uint256 timestamp);
    event BucketClaimed(uint256 indexed bucketIndex, address indexed recipient, uint256 amount);

    // ============ ERRORS ============

    error AlreadyInitialized();
    error Unauthorized();
    error AlreadyGraduated();

    // ============ CONSTRUCTOR ============

    /// @dev Empty — clones cannot run constructors. All setup happens in initialize().
    constructor() ERC20("", "") {}

    // ============ MODIFIERS ============

    modifier onlyFactory() {
        _onlyFactory();
        _;
    }

    function _onlyFactory() internal view {
        if (msg.sender != factory) revert Unauthorized();
    }

    // ============ BUCKET VALIDATION ============

    /// @notice Enforces invariants on a bucket array before it is stored.
    ///         Rules:
    ///           1. At least 1, at most 10 buckets.
    ///           2. basisPoints across all buckets must sum to exactly 10 000.
    ///           3. Exactly one bucket may have isLiquidity = true.
    ///           4. Every non-liquidity bucket must have a non-zero recipient.
    /// @dev Pure function — no state reads. Called once at initialization.
    function _validateBuckets(Bucket[] memory _buckets) internal pure {
        require(
            _buckets.length >= 1 && _buckets.length <= 10,
            "GradPad: invalid bucket count"
        );

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

        require(total == BASIS_POINTS, "GradPad: buckets must sum to 100%");
        require(liquidityCount == 1, "GradPad: exactly one liquidity bucket");
    }

    // ============ INITIALIZATION ============

    /// @notice One-shot initializer called by GradPadFactory immediately after clone deployment.
    /// @param name_         Token name.
    /// @param symbol_       Token symbol.
    /// @param totalSupply_  Total token supply (in wei, 18 decimals).
    /// @param _buckets      Allocation array. Validated by _validateBuckets before storing.
    /// @param factory_      Factory address — becomes the sole privileged caller.
    function initialize(
        string memory name_,
        string memory symbol_,
        uint256 totalSupply_,
        Bucket[] memory _buckets,
        address factory_
    ) external {
        // Replay protection: factory is set only once.
        if (factory != address(0)) revert AlreadyInitialized();

        _tokenName    = name_;
        _tokenSymbol  = symbol_;
        factory       = factory_;
        totalTokenSupply = totalSupply_;
        bondingPhase  = true;

        // Validate before storing — bad arrays revert here.
        _validateBuckets(_buckets);
        for (uint256 i = 0; i < _buckets.length; i++) {
            buckets.push(_buckets[i]);
        }

        // Mint entire supply to this contract.
        // The factory reads the liquidity bucket's basisPoints to calculate how many
        // tokens to pull to the BCPair via transferLiquidityToBCPair().
        _mint(address(this), totalSupply_);
    }

    // ============ NAME / SYMBOL OVERRIDES ============

    /// @inheritdoc ERC20
    function name() public view override returns (string memory) {
        return _tokenName;
    }

    /// @inheritdoc ERC20
    function symbol() public view override returns (string memory) {
        return _tokenSymbol;
    }

    // ============ FACTORY FUNCTIONS ============

    /// @notice Transfer the liquidity bucket's token share to the BCPair at launch.
    /// @dev    Called by factory after creating the BCPair. Finds the isLiquidity bucket,
    ///         computes its token amount, and transfers it directly to `bcPair`.
    /// @param bcPair The bonding curve pair that will hold the tokens during bonding phase.
    function transferLiquidityToBcPair(address bcPair) external onlyFactory {
        for (uint256 i = 0; i < buckets.length; i++) {
            if (buckets[i].isLiquidity) {
                uint256 amount = (totalTokenSupply * buckets[i].basisPoints) / BASIS_POINTS;
                _transfer(address(this), bcPair, amount);
                return;
            }
        }
    }

    /// @notice Flip to post-graduation state. Called by factory when bonding curve threshold
    ///         is hit and Uniswap V2 liquidity has been seeded.
    function graduate() external onlyFactory {
        if (graduationTimestamp != 0) revert AlreadyGraduated();
        graduationTimestamp = block.timestamp;
        bondingPhase = false;
        emit Graduated(block.timestamp);
    }

    /// @notice Test helper — lets factory (or this contract in setUp) force-set graduation.
    /// @dev    Only callable by factory so it cannot be exploited in production;
    ///         in tests the test contract deploys as factory.
    function setGraduationTimestamp(uint256 ts) external {
        if (msg.sender != factory && msg.sender != address(this)) revert Unauthorized();
        graduationTimestamp = ts;
        bondingPhase = false;
    }

    // ============ CLAIMING ============

    /// @notice Claim vested tokens from a non-liquidity bucket.
    ///         Cliff and linear vesting are measured from graduationTimestamp.
    /// @param bucketIndex Index into the buckets array.
    function claimBucket(uint256 bucketIndex) external nonReentrant {
        require(graduationTimestamp > 0, "GradPad: not graduated");
        require(bucketIndex < buckets.length, "GradPad: invalid bucket");
        Bucket memory bucket = buckets[bucketIndex];
        require(!bucket.isLiquidity, "GradPad: cannot claim liquidity");
        require(msg.sender == bucket.recipient, "GradPad: not recipient");

        uint256 elapsed = block.timestamp - graduationTimestamp;
        require(elapsed >= bucket.cliff, "GradPad: cliff not elapsed");

        uint256 bucketTokens = (totalTokenSupply * bucket.basisPoints) / BASIS_POINTS;
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

    // ============ VIEW HELPERS ============

    /// @notice Number of buckets configured on this token.
    function bucketCount() external view returns (uint256) {
        return buckets.length;
    }
}
