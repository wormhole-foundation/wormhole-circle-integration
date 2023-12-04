// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {MockIntegration} from "../../src/mock/MockIntegration.sol";

contract ContractScript is Script {
    function deployMockIntegration() public {
        // first Setup
        new MockIntegration();
    }

    function run() public {
        // begin sending transactions
        vm.startBroadcast();

        // MockIntegration.sol
        deployMockIntegration();

        // finished
        vm.stopBroadcast();
    }
}
