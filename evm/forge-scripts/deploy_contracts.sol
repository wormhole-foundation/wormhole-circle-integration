// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {IWormhole} from "wormhole/interfaces/IWormhole.sol";

import {ICircleBridge} from "../src/interfaces/circle/ICircleBridge.sol";
import {IMessageTransmitter} from "../src/interfaces/circle/IMessageTransmitter.sol";

import {CircleIntegrationSetup} from "../src/circle_integration/CircleIntegrationSetup.sol";
import {CircleIntegrationImplementation} from "../src/circle_integration/CircleIntegrationImplementation.sol";
import {CircleIntegrationProxy} from "../src/circle_integration/CircleIntegrationProxy.sol";

import {WormholeSimulator} from "wormhole-forge-sdk/WormholeSimulator.sol";

contract ContractScript is Script {
    // Wormhole
    WormholeSimulator wormholeSimulator;

    // Circle
    ICircleBridge circleBridge;

    // Circle Integration
    CircleIntegrationSetup setup;
    CircleIntegrationImplementation implementation;
    CircleIntegrationProxy proxy;

    function setUp() public {
        // Wormhole
        wormholeSimulator = wormholeSimulator = new WormholeSimulator(
            vm.envAddress("RELEASE_WORMHOLE_ADDRESS"), 0);

        // Circle
        circleBridge = ICircleBridge(vm.envAddress("RELEASE_CIRCLE_BRIDGE_ADDRESS"));
    }

    function deployCircleIntegrationImplementation() public {
        // next Implementation
        implementation = new CircleIntegrationImplementation();
    }

    function deployCircleIntegration() public {
        // first Setup
        setup = new CircleIntegrationSetup();

        // setup Proxy using Implementation
        proxy = new CircleIntegrationProxy(
            address(setup),
            abi.encodeWithSelector(
                bytes4(keccak256("setup(address,address,uint8,address,uint16,bytes32)")),
                address(implementation),
                address(wormholeSimulator.wormhole()),
                uint8(1), // finality
                address(circleBridge),
                wormholeSimulator.governanceChainId(),
                wormholeSimulator.governanceContract()
            )
        );
    }

    function run() public {
        // begin sending transactions
        vm.startBroadcast();

        // deploy Circle Integration implementation
        deployCircleIntegrationImplementation();

        // deploy Circle Integration proxy
        deployCircleIntegration();

        // finished
        vm.stopBroadcast();
    }
}
