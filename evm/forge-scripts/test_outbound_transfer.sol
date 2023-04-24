// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {ICircleIntegration} from "../src/interfaces/ICircleIntegration.sol";

interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);
}

contract ContractScript is Script {
    // Circle integration
    ICircleIntegration integration;

    function setUp() public {
        // Circle integration
        integration = ICircleIntegration(vm.envAddress("DEPLOYED_ADDRESS"));
    }

    function transferTokens(
        address token,
        uint256 amount,
        uint16 targetChain
    ) public {
        // Format the mintRecipient.
        bytes32 mintRecipient = integration.addressToBytes32(
            address(0x49887A216375FDED17DC1aAAD4920c3777265614)
        );

        // Format transferParameters.
        ICircleIntegration.TransferParameters memory transferParameters =
            ICircleIntegration.TransferParameters({
                token: token,
                amount: amount,
                targetChain: targetChain,
                mintRecipient: mintRecipient
            });

        // Approve the bridge to spend USDC.
        IERC20(token).approve(address(integration), amount);

        // Transfer the tokens.
        uint64 sequence = integration.transferTokensWithPayload(
            transferParameters,
            0, // nonce
            abi.encodePacked(hex"deadbeef")
        );

        console.log("Wormhole sequence: %s", sequence);
    }

    function run() public {
        // begin sending transactions
        vm.startBroadcast();

        // query state variables
        transferTokens(
            vm.envAddress("TOKEN_ADDRESS"),
            vm.envUint("TEST_AMOUNT"),
            uint16(vm.envUint("TARGET_CHAIN"))
        );

        // finished
        vm.stopBroadcast();
    }
}
