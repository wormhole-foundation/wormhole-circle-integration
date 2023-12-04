// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.19;

import {IWormhole} from "src/interfaces/IWormhole.sol";

import {BytesParsing} from "src/libraries/BytesParsing.sol";
import {Utils} from "src/libraries/Utils.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";

library WormholeOverride {
    using Utils for address;
    using BytesParsing for bytes;

    address constant VM_ADDRESS = address(bytes20(uint160(uint256(keccak256("hevm cheat code")))));
    Vm constant vm = Vm(VM_ADDRESS);

    uint16 constant GOVERNANCE_CHAIN_ID = 1;
    bytes32 constant GOVERNANCE_CONTRACT =
        0x0000000000000000000000000000000000000000000000000000000000000004;

    // keccak256("devnetGuardianPrivateKey") - 1
    bytes32 constant DEVNET_GUARDIAN_PK_SLOT =
        0x4c7087e9f1bf599f9f9fff4deb3ecae99b29adaab34a0f53d9fa9d61aeaecb63;

    error IncorrectSlot(bytes32);
    error UnexpectedGuardianLength(uint256);
    error UnexpectedGuardianSet(uint256, address);
    error NoLogsFound();

    function setUpOverride(IWormhole wormhole, uint256 signer) internal {
        address devnetGuardian = vm.addr(signer);

        bytes32 data = vm.load(address(wormhole), bytes32(uint256(2)));
        if (data != 0) {
            revert IncorrectSlot(bytes32(uint256(2)));
        }

        // Get slot for Guardian Set at the current index
        uint32 guardianSetIndex = wormhole.getCurrentGuardianSetIndex();
        bytes32 guardianSetSlot = keccak256(abi.encode(guardianSetIndex, 2));

        // Overwrite all but first guardian set to zero address. This isn't
        // necessary, but just in case we inadvertently access these slots
        // for any reason.
        uint256 numGuardians = uint256(vm.load(address(wormhole), guardianSetSlot));
        for (uint256 i = 1; i < numGuardians;) {
            vm.store(
                address(wormhole),
                bytes32(uint256(keccak256(abi.encodePacked(guardianSetSlot))) + i),
                0
            );
            unchecked {
                ++i;
            }
        }

        // Now overwrite the first guardian key with the devnet key specified
        // in the function argument.
        vm.store(
            address(wormhole),
            bytes32(uint256(keccak256(abi.encodePacked(guardianSetSlot))) + 0), // just explicit w/ index 0
            devnetGuardian.toUniversalAddress()
        );

        // Change the length to 1 guardian
        vm.store(
            address(wormhole),
            guardianSetSlot,
            bytes32(uint256(1)) // length == 1
        );

        // Confirm guardian set override
        address[] memory guardians = wormhole.getGuardianSet(guardianSetIndex).keys;
        if (guardians.length != 1 || guardians[0] != devnetGuardian) {
            revert UnexpectedGuardianSet(guardians.length, guardians[0]);
        }

        // Now do something crazy. Save the private key in a specific slot of Wormhole's storage for
        // retrieval later.
        vm.store(address(wormhole), DEVNET_GUARDIAN_PK_SLOT, bytes32(signer));
    }

    function guardianPrivateKey(IWormhole wormhole) internal view returns (uint256 pk) {
        pk = uint256(vm.load(address(wormhole), DEVNET_GUARDIAN_PK_SLOT));
    }

    function fetchWormholePublishedPayloads(Vm.Log[] memory logs)
        internal
        pure
        returns (bytes[] memory payloads)
    {
        if (logs.length == 0) {
            revert NoLogsFound();
        }

        bytes32 topic = keccak256("LogMessagePublished(address,uint64,uint32,bytes,uint8)");

        uint256 count;
        uint256 n = logs.length;
        for (uint256 i; i < n;) {
            unchecked {
                if (logs[i].topics[0] == topic) {
                    ++count;
                }
                ++i;
            }
        }

        // create log array to save published messages
        payloads = new bytes[](count);

        uint256 publishedIndex;
        for (uint256 i; i < n;) {
            unchecked {
                if (logs[i].topics[0] == topic) {
                    (,, payloads[publishedIndex],) =
                        abi.decode(logs[i].data, (uint64, uint32, bytes, uint8));
                    ++publishedIndex;
                }
                ++i;
            }
        }
    }

    function craftVaa(
        IWormhole wormhole,
        uint16 emitterChain,
        bytes32 emitterAddress,
        uint64 sequence,
        bytes memory payload
    ) internal view returns (IWormhole.VM memory vaa, bytes memory encoded) {
        vaa.version = 1;
        vaa.timestamp = uint32(block.timestamp);
        vaa.nonce = 420;
        vaa.emitterChainId = emitterChain;
        vaa.emitterAddress = emitterAddress;
        vaa.sequence = sequence;
        vaa.consistencyLevel = 1;
        vaa.payload = payload;

        bytes memory encodedBody = abi.encodePacked(
            vaa.timestamp,
            vaa.nonce,
            vaa.emitterChainId,
            vaa.emitterAddress,
            vaa.sequence,
            vaa.consistencyLevel,
            vaa.payload
        );
        vaa.hash = keccak256(abi.encodePacked(keccak256(encodedBody)));

        vaa.signatures = new IWormhole.Signature[](1);
        (vaa.signatures[0].v, vaa.signatures[0].r, vaa.signatures[0].s) =
            vm.sign(guardianPrivateKey(wormhole), vaa.hash);
        vaa.signatures[0].v -= 27;

        encoded = abi.encodePacked(
            vaa.version,
            wormhole.getCurrentGuardianSetIndex(),
            uint8(vaa.signatures.length),
            vaa.signatures[0].guardianIndex,
            vaa.signatures[0].r,
            vaa.signatures[0].s,
            vaa.signatures[0].v,
            encodedBody
        );
    }

    function craftGovernanceVaa(
        IWormhole wormhole,
        bytes32 module,
        uint8 action,
        uint16 targetChain,
        uint64 sequence,
        bytes memory decree
    ) internal view returns (IWormhole.VM memory vaa, bytes memory encoded) {
        (vaa, encoded) = craftGovernanceVaa(
            wormhole,
            GOVERNANCE_CHAIN_ID,
            GOVERNANCE_CONTRACT,
            module,
            action,
            targetChain,
            sequence,
            decree
        );
    }

    function craftGovernanceVaa(
        IWormhole wormhole,
        uint16 governanceChain,
        bytes32 governanceContract,
        bytes32 module,
        uint8 action,
        uint16 targetChain,
        uint64 sequence,
        bytes memory decree
    ) internal view returns (IWormhole.VM memory vaa, bytes memory encoded) {
        (vaa, encoded) = craftVaa(
            wormhole,
            governanceChain,
            governanceContract,
            sequence,
            abi.encodePacked(module, action, targetChain, decree)
        );
    }
}
