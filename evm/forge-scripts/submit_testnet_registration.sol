// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {ICircleIntegration} from "../src/interfaces/ICircleIntegration.sol";
import {IWormhole} from "../src/interfaces/IWormhole.sol";

contract ContractScript is Script {
    // Circle integration
    ICircleIntegration integration;

    // Wormhole
    IWormhole wormhole;

    // Circle integration governance
    bytes32 constant GOVERNANCE_MODULE = 0x000000000000000000000000000000436972636c65496e746567726174696f6e;
    uint8 constant GOVERNANCE_REGISTER_EMITTER_AND_DOMAIN = 2;

    function setUp() public {
        // Circle integration
        integration = ICircleIntegration(vm.envAddress("CIRCLE_INTEGRATION_PROXY"));

        // wormhole
        wormhole = IWormhole(vm.envAddress("RELEASE_WORMHOLE_ADDRESS"));
    }

    function doubleKeccak256(bytes memory body) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(keccak256(body)));
    }

    function encodeObservation(IWormhole.VM memory wormholeMessage) public pure returns (bytes memory) {
        return abi.encodePacked(
            wormholeMessage.timestamp,
            wormholeMessage.nonce,
            wormholeMessage.emitterChainId,
            wormholeMessage.emitterAddress,
            wormholeMessage.sequence,
            wormholeMessage.consistencyLevel,
            wormholeMessage.payload
        );
    }

    function signObservation(uint256 guardian, IWormhole.VM memory wormholeMessage)
        public
        view
        returns (bytes memory)
    {
        require(guardian != 0, "devnetGuardian is zero address");

        bytes memory body = encodeObservation(wormholeMessage);

        // Sign the hash with the devnet guardian private key
        IWormhole.Signature[] memory sigs = new IWormhole.Signature[](1);
        (sigs[0].v, sigs[0].r, sigs[0].s) = vm.sign(guardian, doubleKeccak256(body));
        sigs[0].guardianIndex = 0;

        return abi.encodePacked(
            uint8(1),
            wormhole.getCurrentGuardianSetIndex(),
            uint8(sigs.length),
            sigs[0].guardianIndex,
            sigs[0].r,
            sigs[0].s,
            sigs[0].v - 27,
            body
        );
    }

    function makeRegistrationObservation(
        bytes memory decree
    ) internal view returns (IWormhole.VM memory message) {
        message.timestamp = uint32(block.timestamp);
        message.nonce = 0;
        message.emitterChainId = wormhole.governanceChainId();
        message.emitterAddress = wormhole.governanceContract();
        message.sequence = wormhole.nextSequence(msg.sender);
        message.consistencyLevel = 1;
        message.payload = abi.encodePacked(
            GOVERNANCE_MODULE,
            GOVERNANCE_REGISTER_EMITTER_AND_DOMAIN,
            uint16(vm.envUint("TARGET_CHAIN")),
            decree
        );
    }

    function generateRegistrationVaa() internal returns (bytes memory vaa) {
        IWormhole.VM memory message = makeRegistrationObservation(
            abi.encodePacked(
                uint16(vm.envUint("FOREIGN_CHAIN")),
                bytes32(vm.envBytes32("FOREIGN_EMITTER")),
                uint32(vm.envUint("FOREIGN_DOMAIN"))
            )
        );

        // sign the governance message with the signer key
        vaa = signObservation(
            uint256(vm.envBytes32("SIGNER_KEY")),
            message
        );
    }

    function submitRegistrationVaa() internal {
        integration.registerEmitterAndDomain(generateRegistrationVaa());
    }

    function run() public {
        // begin sending transactions
        vm.startBroadcast();

        // query registration vaa
        submitRegistrationVaa();

        // finished
        vm.stopBroadcast();
    }
}
