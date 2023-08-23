// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {ICircleIntegration} from "../src/interfaces/ICircleIntegration.sol";

contract ContractScript is Script {
    // Circle integration
    ICircleIntegration integration;

    function setUp() public {
        // Circle integration
        integration = ICircleIntegration(vm.envAddress("CIRCLE_INTEGRATION_PROXY"));
    }

    function readStateVariables() public {
        // wormhole finality
        uint8 finality = integration.wormholeFinality();
        console.log("Wormhole finality:");
        console.log(finality);

        // registered contract
        bytes32 registered = integration.getRegisteredEmitter(uint16(vm.envUint("TARGET_CHAIN_ID")));
        console.log("\n Registered contract:");
        console.logBytes32(registered);

        // domain
        uint32 domain = integration.getDomainFromChainId(uint16(vm.envUint("TARGET_CHAIN_ID")));
        console.log("\n Registered domain:");
        console.log(domain);

        // is implementation initialized
        bool isInitialized = integration.isInitialized(vm.envAddress("IMPLEMENTATION_ADDRESS"));
        console.log("\n Is Implementation Initialized:");
        console.log(isInitialized);
    }

    function run() public {
        // begin sending transactions
        vm.startBroadcast();

        // query state variables
        readStateVariables();

        // finished
        vm.stopBroadcast();
    }
}
