// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {IWormhole} from "../src/interfaces/IWormhole.sol";
import {ICircleBridge} from "../src/interfaces/circle/ICircleBridge.sol";

import {CrossChainUSDCSetup} from "../src/cross_chain_usdc/CrossChainUSDCSetup.sol";
import {CrossChainUSDCImplementation} from "../src/cross_chain_usdc/CrossChainUSDCImplementation.sol";
import {CrossChainUSDCProxy} from "../src/cross_chain_usdc/CrossChainUSDCProxy.sol";

import "forge-std/console.sol";

contract ContractScript is Script {
    IWormhole wormhole;
    ICircleBridge circleBridge;

    // USDCShuttle
    CrossChainUSDCSetup setup;
    CrossChainUSDCImplementation implementation;
    CrossChainUSDCProxy proxy;

    function setUp() public {
        wormhole = IWormhole(vm.envAddress("RELEASE_WORMHOLE_ADDRESS"));
        circleBridge = ICircleBridge(vm.envAddress("RELEASE_CIRCLE_BRIDGE_ADDRESS"));
    }

    function deployUSDCShuttle() public {
        // first Setup
        setup = new CrossChainUSDCSetup();

        // next Implementation
        implementation = new CrossChainUSDCImplementation();

        // setup Proxy using Implementation
        //         address implementation,
        // uint16 chainId,
        // address wormhole,
        // uint8 finality,
        // address circleBridgeAddress
        proxy = new CrossChainUSDCProxy(
            address(setup),
            abi.encodeWithSelector(
                bytes4(keccak256("setup(address,uint16,address,uint8,address)")),
                address(implementation),
                wormhole.chainId(),
                address(wormhole),
                uint8(1), // finality
                address(circleBridge)
            )
        );
    }

    function run() public {
        // begin sending transactions
        vm.startBroadcast();

        // HelloWorld.sol
        deployUSDCShuttle();

        // finished
        vm.stopBroadcast();
    }
}
