// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {BCPair} from "../src/bonding/BCPair.sol";
import {BCPairFactory} from "../src/bonding/BCPairFactory.sol";
import {BCRouter} from "../src/bonding/BCRouter.sol";
import {GradPadToken} from "../src/GradPadToken.sol";
import {GradPadFactoryV1} from "../src/GradPadFactoryV1.sol";

/// @notice Deploys the full GradPad contract suite in dependency order.
///         GradPadFactoryV1 is deployed behind a UUPS ERC1967 proxy so it can
///         be upgraded to V2+ without redeploying the proxy address.
///         After deployment, the proxy is granted EXECUTOR_ROLE on BCRouter
///         so it can seed initial reserves and trigger graduation.
///
/// Usage (dry-run):
///   forge script script/Deploy.s.sol --rpc-url $BASE_RPC_URL --sender $DEPLOYER_ADDRESS -vvvv
///
/// Usage (live deploy + verify):
///   forge script script/Deploy.s.sol \
///     --rpc-url $BASE_RPC_URL \
///     --broadcast --verify \
///     --etherscan-api-key $BASESCAN_API_KEY \
///     -vvvv
contract Deploy is Script {
    // Base mainnet Uniswap V2
    // TODO: verify factory address before mainnet deploy (plan had a 39-char typo)
    address constant UNISWAP_V2_FACTORY = 0x08909dC15E40173Ff4699343b6Eb8132c65E18EC;
    address constant UNISWAP_V2_ROUTER  = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer    = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);

        // 1. MockUSDC — pair asset token for development / Base Sepolia
        MockUSDC usdc = new MockUSDC();
        console.log("MockUSDC:               ", address(usdc));

        // 2. BCPair implementation (clone target)
        BCPair pairImpl = new BCPair();
        console.log("BCPair impl:            ", address(pairImpl));

        // 3. BCPairFactory — manages pair registry and clone creation
        BCPairFactory pairFactory = new BCPairFactory(deployer, address(pairImpl));
        console.log("BCPairFactory:          ", address(pairFactory));

        // 4. BCRouter — AMM execution layer; factory_ = pairFactory, admin = deployer
        BCRouter router = new BCRouter(address(pairFactory), deployer);
        console.log("BCRouter:               ", address(router));

        // 5. Wire router into pairFactory so createPair knows the router address
        pairFactory.setRouter(address(router));

        // 6. GradPadToken implementation (EIP-1167 clone target)
        GradPadToken tokenImpl = new GradPadToken();
        console.log("GradPadToken impl:      ", address(tokenImpl));

        // 7. GradPadFactoryV1 implementation — logic contract behind the proxy
        GradPadFactoryV1 factoryImpl = new GradPadFactoryV1();
        console.log("GradPadFactoryV1 impl:  ", address(factoryImpl));

        // 8. ERC1967 proxy — the stable address users and integrators interact with
        GradPadFactoryV1 factory = GradPadFactoryV1(address(new ERC1967Proxy(
            address(factoryImpl),
            abi.encodeCall(GradPadFactoryV1.initialize, (
                address(tokenImpl),
                address(router),
                address(pairFactory),
                UNISWAP_V2_FACTORY,
                UNISWAP_V2_ROUTER,
                address(usdc),
                deployer
            ))
        )));
        console.log("GradPadFactoryV1 proxy: ", address(factory));

        // 9. Grant the proxy EXECUTOR_ROLE on BCRouter so it can:
        //    - addInitialLiquidity on token creation
        //    - buy / sell during bonding phase
        //    - withdrawBondingCurveLiquidity at graduation
        router.grantRole(router.EXECUTOR_ROLE(), address(factory));
        console.log("EXECUTOR_ROLE granted to proxy on BCRouter");

        vm.stopBroadcast();
    }
}
