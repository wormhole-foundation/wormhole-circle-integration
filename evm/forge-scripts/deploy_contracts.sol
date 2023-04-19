// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {IWormhole} from "wormhole/interfaces/IWormhole.sol";

import {ICircleBridge} from "../src/interfaces/circle/ICircleBridge.sol";
import {IMessageTransmitter} from "../src/interfaces/circle/IMessageTransmitter.sol";

import {CircleIntegrationSetup} from "../src/circle_integration/CircleIntegrationSetup.sol";
import {CircleIntegrationImplementation} from "../src/circle_integration/CircleIntegrationImplementation.sol";
import {CircleIntegrationProxy} from "../src/circle_integration/CircleIntegrationProxy.sol";
import {ICircleIntegration} from "../src/interfaces/ICircleIntegration.sol";

contract ContractScript is Script {
    // Wormhole
    IWormhole wormhole;

    // Circle
    ICircleBridge circleBridge;

    // Circle Integration
    CircleIntegrationSetup setup;
    CircleIntegrationImplementation implementation;
    CircleIntegrationProxy proxy;

    function setUp() public {
        // Wormhole
        wormhole = IWormhole(vm.envAddress("RELEASE_WORMHOLE_ADDRESS"));

        // Circle
        circleBridge = ICircleBridge(vm.envAddress("RELEASE_CIRCLE_BRIDGE_ADDRESS"));
    }

    function deployCircleIntegration() public {
        // first Setup
        setup = new CircleIntegrationSetup();

        // next Implementation
        implementation = new CircleIntegrationImplementation();

        console.log("Wormhole address: %s, chainId: %s", address(wormhole), wormhole.chainId());

        // setup Proxy using Implementation
        proxy = new CircleIntegrationProxy(
            address(setup),
            abi.encodeWithSelector(
                bytes4(keccak256("setup(address,address,uint8,address,uint16,bytes32)")),
                address(implementation),
                address(wormhole),
                uint8(vm.envUint("RELEASE_WORMHOLE_FINALITY")),
                address(circleBridge),
                wormhole.governanceChainId(),
                wormhole.governanceContract()
            )
        );
    }

    function run() public {
        // begin sending transactions
        vm.startBroadcast();

        // deploy Circle Integration proxy
        deployCircleIntegration();

        // finished
        vm.stopBroadcast();
    }
}
