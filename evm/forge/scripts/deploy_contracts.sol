// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {IWormhole} from "src/interfaces/IWormhole.sol";
import {ITokenMessenger} from "src/interfaces/ITokenMessenger.sol";
import {IMessageTransmitter} from "src/interfaces/IMessageTransmitter.sol";
import {ICircleIntegration} from "src/interfaces/ICircleIntegration.sol";

import {Setup} from "src/contracts/CircleIntegration/Setup.sol";
import {Implementation} from "src/contracts/CircleIntegration/Implementation.sol";

contract ContractScript is Script {
    // Wormhole
    IWormhole wormhole;

    // Circle
    ITokenMessenger circleBridge;

    // Circle Integration
    CircleIntegrationSetup setup;
    CircleIntegrationImplementation implementation;
    ERC1967Proxy proxy;

    function setUp() public {
        // Wormhole
        wormhole = IWormhole(vm.envAddress("RELEASE_WORMHOLE_ADDRESS"));

        // Circle
        circleBridge = ITokenMessenger(vm.envAddress("RELEASE_CIRCLE_BRIDGE_ADDRESS"));
    }

    function deployCircleIntegration() public {
        // first Setup
        setup = new Setup();
        console2.log("CircleIntegrationSetup address: %s", address(setup));

        // next Implementation
        implementation = new Implementation(address(wormhole), address(circleBridge));
        console2.log("CircleIntegrationImplementation address: %s", address(implementation));

        console2.log("Wormhole address: %s, chainId: %s", address(wormhole), wormhole.chainId());

        // setup Proxy using Implementation
        proxy =
            new ERC1967Proxy(address(setup), abi.encodeCall(setup.setup, address(implementation)));
        console2.log("ERC1967Proxy address: %s", address(proxy));
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
