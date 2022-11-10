// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.13;

import {ERC1967Upgrade} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Upgrade.sol";

import {IWormhole} from "wormhole/interfaces/IWormhole.sol";
import {BytesLib} from "wormhole/libraries/external/BytesLib.sol";

import {CircleIntegrationSetters} from "./CircleIntegrationSetters.sol";
import {CircleIntegrationGetters} from "./CircleIntegrationGetters.sol";
import {CircleIntegrationState} from "./CircleIntegrationState.sol";

contract CircleIntegrationGovernance is CircleIntegrationGetters, ERC1967Upgrade {
    using BytesLib for bytes;

    event ContractUpgraded(address indexed oldContract, address indexed newContract);
    event WormholeFinalityUpdated(uint8 indexed oldLevel, uint8 indexed newFinality);
    event OwnershipTransfered(address indexed oldOwner, address indexed newOwner);

    // "CircleIntegration" (left padded)
    bytes32 constant GOVERNANCE_MODULE = 0x000000000000000000000000000000436972636c65496e746567726174696f6e;

    uint8 constant GOVERNANCE_UPDATE_WORMHOLE_FINALITY = 1;
    uint256 constant GOVERNANCE_UPDATE_WORMHOLE_FINALITY_LENGTH = 36;

    uint8 constant GOVERNANCE_REGISTER_EMITTER_AND_DOMAIN = 2;
    uint256 constant GOVERNANCE_REGISTER_EMITTER_AND_DOMAIN_LENGTH = 73;

    uint8 constant GOVERNANCE_REGISTER_ACCEPTED_TOKEN = 3;
    uint256 constant GOVERNANCE_REGISTER_ACCEPTED_TOKEN_LENGTH = 67;

    uint8 constant GOVERNANCE_REGISTER_TARGET_CHAIN_TOKEN = 4;
    uint256 constant GOVERNANCE_REGISTER_TARGET_CHAIN_TOKEN_LENGTH = 101;

    /// @dev updateWormholeFinality serves to change the wormhole messaging consistencyLevel
    function updateWormholeFinality(bytes memory encodedMessage) public {
        bytes memory payload = verifyAndConsumeGovernanceMessage(encodedMessage, GOVERNANCE_UPDATE_WORMHOLE_FINALITY);
        require(payload.length == GOVERNANCE_UPDATE_WORMHOLE_FINALITY_LENGTH, "invalid governance payload length");

        uint8 currentWormholeFinality = wormholeFinality();

        // Updating finality should only be relevant for this contract's chain ID
        require(payload.toUint16(33) == chainId(), "invalid target chain");

        // Finality value at byte 35
        uint8 newWormholeFinality = payload.toUint8(35);
        require(newWormholeFinality > 0, "invalid finality");

        setWormholeFinality(newWormholeFinality);

        emit WormholeFinalityUpdated(currentWormholeFinality, newWormholeFinality);
    }

    /// @dev registerEmitterAndDomain serves to save trusted emitter contract addresses
    /// and Circle's chain domain
    function registerEmitterAndDomain(bytes memory encodedMessage) public {
        bytes memory payload = verifyAndConsumeGovernanceMessage(encodedMessage, GOVERNANCE_REGISTER_EMITTER_AND_DOMAIN);
        require(payload.length == GOVERNANCE_REGISTER_EMITTER_AND_DOMAIN_LENGTH, "invalid governance payload length");

        // Updating finality should only be relevant for this contract's chain ID
        require(payload.toUint16(33) == chainId(), "invalid target chain");

        // emitterChainId at byte 35
        uint16 emitterChainId = payload.toUint16(35);
        require(emitterChainId > 0 && emitterChainId != chainId(), "invalid chain");
        require(getRegisteredEmitter(emitterChainId) == bytes32(0), "chain already registered");

        // emitterAddress at byte 37
        bytes32 emitterAddress = payload.toBytes32(37);
        require(emitterAddress != bytes32(0), "emitter cannot be zero address");

        // domain at byte 69 (hehe)
        uint32 domain = payload.toUint32(69);
        require(domain != localDomain(), "domain == localDomain()");

        // update the registeredEmitters state variable
        setEmitter(emitterChainId, emitterAddress);

        // update the chainId to domain (and domain to chainId) mappings
        setChainIdToDomain(emitterChainId, domain);
        setDomainToChainId(domain, emitterChainId);
    }

    /// @dev addAcceptedToken serves to determine which tokens can be burned + minted
    /// via the Circle Bridge
    function registerAcceptedToken(bytes memory encodedMessage) public {
        bytes memory payload = verifyAndConsumeGovernanceMessage(encodedMessage, GOVERNANCE_REGISTER_ACCEPTED_TOKEN);
        require(payload.length == GOVERNANCE_REGISTER_ACCEPTED_TOKEN_LENGTH, "invalid governance payload length");

        // Updating finality should only be relevant for this contract's chain ID
        require(payload.toUint16(33) == chainId(), "invalid target chain");

        // token at byte 35 (32 bytes, but last 20 is the address)
        address token = readAddressFromBytes32(payload, 35);
        require(token != address(0), "token is zero address");

        // update the acceptedTokens mapping
        addAcceptedToken(token);
    }

    function registerTargetChainToken(bytes memory encodedMessage) public {
        bytes memory payload = verifyAndConsumeGovernanceMessage(encodedMessage, GOVERNANCE_REGISTER_TARGET_CHAIN_TOKEN);
        require(payload.length == GOVERNANCE_REGISTER_TARGET_CHAIN_TOKEN_LENGTH, "invalid governance payload length");

        // Updating finality should only be relevant for this contract's chain ID
        require(payload.toUint16(33) == chainId(), "invalid target chain");

        // sourceToken at byte 35 (32 bytes, but last 20 is the address)
        address sourceToken = readAddressFromBytes32(payload, 35);
        require(isAcceptedToken(sourceToken), "source token not accepted");

        // targetChain at byte 67
        uint16 targetChain = payload.toUint16(67);
        require(targetChain > 0 && targetChain != chainId(), "invalid target chain");

        // targetToken at byte 69 (hehe)
        bytes32 targetToken = payload.toBytes32(69);
        require(targetToken != bytes32(0), "target token is zero address");

        // update the targetAcceptedTokens mapping
        addTargetAcceptedToken(sourceToken, targetChain, targetToken);
    }

    /// @dev upgrade serves to upgrade contract implementations
    function upgrade(uint16 chainId_, address newImplementation) public onlyOwner {
        require(chainId_ == chainId(), "wrong chain");

        address currentImplementation = _getImplementation();

        _upgradeTo(newImplementation);

        /// @dev call initialize function of the new implementation
        (bool success, bytes memory reason) = newImplementation.delegatecall(abi.encodeWithSignature("initialize()"));

        require(success, string(reason));

        emit ContractUpgraded(currentImplementation, newImplementation);
    }

    modifier onlyOwner() {
        require(owner() == msg.sender, "caller not the owner");
        _;
    }

    function verifyAndConsumeGovernanceMessage(bytes memory encodedMessage, uint8 action)
        internal
        returns (bytes memory)
    {
        (bytes32 messageHash, bytes memory payload) = verifyGovernanceMessage(encodedMessage, action);
        consumeMessage(messageHash);
        return payload;
    }

    function verifyGovernanceMessage(bytes memory encodedMessage, uint8 action)
        public
        view
        returns (bytes32 messageHash, bytes memory payload)
    {
        (IWormhole.VM memory vm, bool valid, string memory reason) = wormhole().parseAndVerifyVM(encodedMessage);

        require(valid, reason);
        require(vm.emitterChainId == governanceChainId(), "invalid governance chain");
        require(vm.emitterAddress == governanceContract(), "invalid governance contract");
        require(!isMessageConsumed(vm.hash), "governance action already consumed");

        payload = vm.payload;
        // module at byte 0
        require(payload.toBytes32(0) == GOVERNANCE_MODULE, "invalid governance module");
        // action at byte 32
        require(payload.toUint8(32) == action, "invalid governance action");

        messageHash = vm.hash;
    }

    function readAddressFromBytes32(bytes memory serialized, uint256 start) internal pure returns (address) {
        uint256 end = start + 12;
        for (uint256 i = start; i < end;) {
            require(serialized.toUint8(i) == 0, "invalid address");
            unchecked {
                i += 1;
            }
        }
        return serialized.toAddress(end);
    }
}
