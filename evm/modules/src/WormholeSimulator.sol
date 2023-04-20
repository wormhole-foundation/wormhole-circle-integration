// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.19;

import {IWormhole} from "wormhole/interfaces/IWormhole.sol";
import {BytesLib} from "wormhole/libraries/external/BytesLib.sol";

import {Setup} from "wormhole/Setup.sol";
import {Implementation} from "wormhole/Implementation.sol";
import {Wormhole} from "wormhole/Wormhole.sol";

import "forge-std/Vm.sol";
import "forge-std/console.sol";

contract WormholeSimulator {
    using BytesLib for bytes;

    uint16 constant GOVERNANCE_CHAIN_ID = 1;
    bytes32 constant GOVERNANCE_CONTRACT = 0x0000000000000000000000000000000000000000000000000000000000000004;

    // Taken from forge-std/Script.sol
    address private constant VM_ADDRESS = address(bytes20(uint160(uint256(keccak256("hevm cheat code")))));
    Vm public constant vm = Vm(VM_ADDRESS);

    // Allow access to Wormhole
    IWormhole public wormhole;

    // Save the guardian PK to sign messages with
    uint256 private devnetGuardianPK;
    address public devnetGuardian;

    // storage
    uint64 governanceSequence;

    constructor(address wormhole_, uint256 devnetGuardian_) {
        governanceSequence = 0;

        wormhole = IWormhole(wormhole_);

        if (devnetGuardian_ > 0) {
            devnetGuardianPK = devnetGuardian_;
            devnetGuardian = vm.addr(devnetGuardianPK);
            overrideToDevnetGuardian();
        }
    }

    function overrideToDevnetGuardian() internal {
        bytes32 data = vm.load(address(wormhole), bytes32(uint256(2)));
        require(data == bytes32(0), "incorrect slot");

        // Get slot for Guardian Set at the current index
        uint32 guardianSetIndex = wormhole.getCurrentGuardianSetIndex();
        bytes32 guardianSetSlot = keccak256(abi.encode(guardianSetIndex, 2));

        // Overwrite all but first guardian set to zero address. This isn't
        // necessary, but just in case we inadvertently access these slots
        // for any reason.
        uint256 numGuardians = uint256(vm.load(address(wormhole), guardianSetSlot));
        for (uint256 i = 1; i < numGuardians;) {
            vm.store(address(wormhole), bytes32(uint256(keccak256(abi.encodePacked(guardianSetSlot))) + i), bytes32(0));
            unchecked {
                i += 1;
            }
        }

        // Now overwrite the first guardian key with the devnet key specified
        // in the function argument.
        vm.store(
            address(wormhole),
            bytes32(uint256(keccak256(abi.encodePacked(guardianSetSlot))) + 0), // just explicit w/ index 0
            bytes32(uint256(uint160(devnetGuardian)))
        );

        // Change the length to 1 guardian
        vm.store(
            address(wormhole),
            guardianSetSlot,
            bytes32(uint256(1)) // length == 1
        );

        // Confirm guardian set override
        address[] memory guardians = wormhole.getGuardianSet(guardianSetIndex).keys;
        require(guardians.length == 1, "guardians.length != 1");
        require(guardians[0] == devnetGuardian, "incorrect guardian set override");
    }

    function doubleKeccak256(bytes memory body) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(keccak256(body)));
    }

    function parseVMFromLogs(Vm.Log memory log) internal pure returns (IWormhole.VM memory vm_) {
        uint256 index = 0;

        // emitterAddress
        vm_.emitterAddress = bytes32(log.topics[1]);

        // sequence
        vm_.sequence = log.data.toUint64(index + 32 - 8);
        index += 32;

        // nonce
        vm_.nonce = log.data.toUint32(index + 32 - 4);
        index += 32;

        // skip random bytes
        index += 32;

        // consistency level
        vm_.consistencyLevel = log.data.toUint8(index + 32 - 1);
        index += 32;

        // length of payload
        uint256 payloadLen = log.data.toUint256(index);
        index += 32;

        vm_.payload = log.data.slice(index, payloadLen);
        index += payloadLen;

        // trailing bytes (due to 32 byte slot overlap)
        index += log.data.length - index;

        require(index == log.data.length, "failed to parse wormhole message");
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

    function signDevnetObservation(IWormhole.VM memory wormholeMessage) public view returns (bytes memory) {
        return signObservation(devnetGuardianPK, wormholeMessage);
    }

    function findLogMessagePublishedInLogs(Vm.Log[] memory entries)
        public
        pure
        returns (uint64, uint32, bytes memory, uint8)
    {
        uint256 numEntries = entries.length;
        for (uint256 i = 0; i < numEntries;) {
            if (entries[i].topics[0] == keccak256("LogMessagePublished(address,uint64,uint32,bytes,uint8)")) {
                return abi.decode(entries[i].data, (uint64, uint32, bytes, uint8));
            }
            unchecked {
                i += 1;
            }
        }
        revert("LogMessagePublished not found");
    }

    function fetchSignedMessageFromLogs(Vm.Log memory log, uint16 emitterChainId, bytes32 emitterAddress)
        public
        view
        returns (bytes memory)
    {
        // Create message instance
        IWormhole.VM memory vm_;

        // Parse wormhole message from ethereum logs
        vm_ = parseVMFromLogs(log);

        // Set empty body values before computing the hash
        vm_.version = uint8(1);
        vm_.timestamp = uint32(block.timestamp);
        vm_.emitterChainId = emitterChainId;
        vm_.emitterAddress = emitterAddress;

        // Compute the hash of the body
        bytes memory body = encodeObservation(vm_);
        vm_.hash = doubleKeccak256(body);

        // Sign the hash with the devnet guardian private key
        IWormhole.Signature[] memory sigs = new IWormhole.Signature[](1);
        (sigs[0].v, sigs[0].r, sigs[0].s) = vm.sign(devnetGuardianPK, vm_.hash);
        sigs[0].guardianIndex = 0;

        return abi.encodePacked(
            vm_.version,
            wormhole.getCurrentGuardianSetIndex(),
            uint8(sigs.length),
            sigs[0].guardianIndex,
            sigs[0].r,
            sigs[0].s,
            sigs[0].v - 27,
            body
        );
    }

    function deployForeignWormhole(uint16 chainId) public returns (address) {
        require(chainId != wormhole.chainId(), "chainId cannot equal this chain's");

        // deploy Setup
        Setup setup = new Setup();

        // deploy Implementation
        Implementation implementation = new Implementation();

        address[] memory guardians = new address[](1);
        guardians[0] = devnetGuardian;

        // deploy Wormhole
        Wormhole foreignWormhole = new Wormhole(
            address(setup),
            abi.encodeWithSelector(
                bytes4(keccak256("setup(address,address[],uint16,uint16,bytes32,uint256)")),
                address(implementation),
                guardians,
                chainId,
                GOVERNANCE_CHAIN_ID,
                GOVERNANCE_CONTRACT,
                block.chainid // evm chain id
            )
        );

        return address(foreignWormhole);
    }

    function makeGovernanceObservation(
        uint16 governanceChainId_,
        bytes32 governanceContract_,
        bytes32 module,
        uint8 action,
        uint16 chainId,
        bytes memory decree
    ) public returns (IWormhole.VM memory message) {
        message.timestamp = uint32(block.timestamp);
        message.nonce = 0;
        message.emitterChainId = governanceChainId_;
        message.emitterAddress = governanceContract_;
        unchecked {
            governanceSequence += 1;
        }
        message.sequence = governanceSequence;
        message.consistencyLevel = 1;
        message.payload = abi.encodePacked(module, action, chainId, decree);
    }

    function makeSignedGovernanceObservation(
        uint16 governanceChainId_,
        bytes32 governanceContract_,
        bytes32 module,
        uint8 action,
        uint16 chainId,
        bytes memory decree
    ) public returns (bytes memory) {
        return signObservation(
            devnetGuardianPK,
            makeGovernanceObservation(governanceChainId_, governanceContract_, module, action, chainId, decree)
        );
    }

    function governanceChainId() public pure returns (uint16) {
        return GOVERNANCE_CHAIN_ID;
    }

    function governanceContract() public pure returns (bytes32) {
        return GOVERNANCE_CONTRACT;
    }
}
