// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {IWormhole} from "../src/interfaces/IWormhole.sol";
import {ICircleBridge} from "../src/interfaces/circle/ICircleBridge.sol";
import {IMessageTransmitter} from "../src/interfaces/circle/IMessageTransmitter.sol";

import {CircleIntegrationSetup} from "../src/circle_integration/CircleIntegrationSetup.sol";
import {CircleIntegrationImplementation} from "../src/circle_integration/CircleIntegrationImplementation.sol";
import {CircleIntegrationProxy} from "../src/circle_integration/CircleIntegrationProxy.sol";

import "forge-std/console.sol";

contract ContractScript is Script {
    IWormhole wormhole;
    ICircleBridge circleBridge;
    IMessageTransmitter messageTransmitter;

    // USDC Burn/Mint contracts
    CircleIntegrationSetup setup;
    CircleIntegrationImplementation implementation;
    CircleIntegrationProxy proxy;

    function setUp() public {
        wormhole = IWormhole(vm.envAddress("RELEASE_WORMHOLE_ADDRESS"));
        circleBridge = ICircleBridge(vm.envAddress("RELEASE_CIRCLE_BRIDGE_ADDRESS"));
        messageTransmitter = IMessageTransmitter(vm.envAddress("RELEASE_MESSAGE_TRANSMITTER_ADDRESS"));
    }

    function deployUSDCIntegration() public {
        // first Setup
        setup = new CircleIntegrationSetup();

        // next Implementation
        implementation = new CircleIntegrationImplementation();

        // setup Proxy using Implementation
        proxy = new CircleIntegrationProxy(
            address(setup),
            abi.encodeWithSelector(
                bytes4(keccak256("setup(address,uint16,address,uint8,address,address)")),
                address(implementation),
                wormhole.chainId(),
                address(wormhole),
                uint8(1), // finality
                address(circleBridge),
                address(messageTransmitter)
            )
        );
    }

    function run() public {
        // begin sending transactions
        vm.startBroadcast();

        // HelloWorld.sol
        deployUSDCIntegration();

        // finished
        vm.stopBroadcast();
    }
}
