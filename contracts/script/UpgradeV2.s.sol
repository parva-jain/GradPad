// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {GradPadFactoryV1} from "../src/GradPadFactoryV1.sol";
import {GradPadFactoryV2} from "../src/GradPadFactoryV2.sol";

/// @notice Upgrades the GradPad proxy from V1 → V2 in a single transaction.
///         initializeV2 sets platform fee params AND repairs the incorrect
///         uniswapV2Factory address stored during V1 deployment.
///
/// Dry run (no broadcast):
///   forge script script/UpgradeV2.s.sol --rpc-url $BASE_RPC_URL -vvvv
///
/// Live upgrade:
///   forge script script/UpgradeV2.s.sol --rpc-url $BASE_RPC_URL --broadcast -vvvv
contract UpgradeV2 is Script {
    address constant PROXY = 0xc2AaE1Bdfb4D178B8a0D72750e10ffb98813948A;

    // Platform fee: 1% (100 basis points). Set to 0 to disable fees entirely.
    uint256 constant FEE_BPS = 100;

    function run() external {
        uint256 deployerKey   = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployerAddr  = vm.addr(deployerKey);

        console.log("Upgrading from:    ", GradPadFactoryV1(PROXY).version());
        console.log("uniswapV2Factory (before):", GradPadFactoryV1(PROXY).uniswapV2Factory());

        vm.startBroadcast(deployerKey);

        // 1. Deploy V2 implementation
        GradPadFactoryV2 implV2 = new GradPadFactoryV2();
        console.log("GradPadFactoryV2 impl:", address(implV2));

        // 2. Upgrade proxy and call initializeV2() in a single transaction.
        //    initializeV2 sets fee params and fixes uniswapV2Factory from the router.
        GradPadFactoryV1(PROXY).upgradeToAndCall(
            address(implV2),
            abi.encodeCall(GradPadFactoryV2.initializeV2, (FEE_BPS, deployerAddr))
        );

        vm.stopBroadcast();

        // 3. Verify (read-only, no broadcast needed)
        console.log("Version after upgrade:", GradPadFactoryV2(PROXY).version());
        console.log("uniswapV2Factory (fixed):", GradPadFactoryV2(PROXY).uniswapV2Factory());
        console.log("platformFeePercent:", GradPadFactoryV2(PROXY).platformFeePercent());
        console.log("feeRecipient:", GradPadFactoryV2(PROXY).feeRecipient());
    }
}
