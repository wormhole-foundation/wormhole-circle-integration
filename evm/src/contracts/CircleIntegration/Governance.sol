// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.19;

import {ERC1967Upgrade} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Upgrade.sol";

import {BytesParsing} from "src/libraries/BytesParsing.sol";
import {IWormhole} from "src/interfaces/IWormhole.sol";
import {IGovernance} from "src/interfaces/IGovernance.sol";

import {State} from "./State.sol";
import {
    getRegisteredEmitters,
    getChainToDomain,
    getConsumedVaas,
    getDomainToChain
} from "./Storage.sol";

abstract contract Governance is IGovernance, State, ERC1967Upgrade {
    using BytesParsing for bytes;

    /**
     * @dev Governance emitter chain ID.
     */
    uint16 constant _GOVERNANCE_CHAIN = 1;

    /**
     * @dev Governance emitter address.
     */
    bytes32 constant _GOVERNANCE_EMITTER =
        0x0000000000000000000000000000000000000000000000000000000000000004;

    /**
     * @dev "CircleIntegration" (left-padded with zeros).
     */
    bytes32 constant GOVERNANCE_MODULE =
        0x000000000000000000000000000000436972636c65496e746567726174696f6e;

    /**
     * @dev Governance action ID indicating decree to register new emitter and CCTP domain.
     */
    uint8 constant _ACTION_REGISTER_EMITTER_AND_DOMAIN = 2;

    /**
     * @dev Governance action ID indicating decree to upgrade contract.
     */
    uint8 constant _ACTION_CONTRACT_UPGRADE = 3;

    /// @inheritdoc IGovernance
    function registerEmitterAndDomain(bytes memory encodedVaa) public {
        (IWormhole.VM memory vaa, uint256 offset) =
            _verifyAndConsumeGovernanceMessage(encodedVaa, _ACTION_REGISTER_EMITTER_AND_DOMAIN);

        // Registering emitters should only be relevant for this contract's chain ID,
        // unless the target chain is 0 (which means all chains).
        uint16 targetChain;
        (targetChain, offset) = vaa.payload.asUint16Unchecked(offset);
        require(targetChain == 0 || targetChain == _chainId, "invalid target chain");

        uint16 foreignChain;
        (foreignChain, offset) = vaa.payload.asUint16Unchecked(offset);
        require(foreignChain != 0 && foreignChain != _chainId, "invalid chain");

        mapping(uint16 => bytes32) storage registeredEmitters = getRegisteredEmitters();

        // For now, ensure that we cannot register the same foreign chain again.
        require(registeredEmitters[foreignChain] == 0, "chain already registered");

        bytes32 foreignAddress;
        (foreignAddress, offset) = vaa.payload.asBytes32Unchecked(offset);
        require(foreignAddress != 0, "emitter cannot be zero address");

        uint32 cctpDomain;
        (cctpDomain, offset) = vaa.payload.asUint32Unchecked(offset);
        require(cctpDomain != _localCctpDomain, "domain == localDomain()");

        _checkLength(vaa.payload, offset);

        // Set the registeredEmitters state variable.
        registeredEmitters[foreignChain] = foreignAddress;

        // update the chainId to domain (and domain to chainId) mappings
        getChainToDomain()[foreignChain] = cctpDomain;
        getDomainToChain()[cctpDomain] = foreignChain;
    }

    /// @inheritdoc IGovernance
    function upgradeContract(bytes memory encodedVaa) public {
        (IWormhole.VM memory vaa, uint256 offset) =
            _verifyAndConsumeGovernanceMessage(encodedVaa, _ACTION_CONTRACT_UPGRADE);

        // contract upgrades should only be relevant for this contract's chain ID
        uint16 targetChain;
        (targetChain, offset) = vaa.payload.asUint16Unchecked(offset);
        require(targetChain == _chainId, "invalid target chain");

        bytes32 encodedImplementation;
        (encodedImplementation, offset) = vaa.payload.asBytes32Unchecked(offset);
        require(bytes12(encodedImplementation) == 0, "invalid address");

        _checkLength(vaa.payload, offset);

        address newImplementation;
        assembly ("memory-safe") {
            newImplementation := encodedImplementation
        }

        // Verify new implementation is CircleIntegration.
        {
            (, bytes memory queried) = newImplementation.staticcall(
                abi.encodeWithSignature("circleIntegrationImplementation()")
            );

            require(queried.length == 32, "invalid implementation");
            require(
                abi.decode(queried, (bytes32)) == keccak256("circleIntegrationImplementation()"),
                "invalid implementation"
            );
        }

        // Save the current implementation address for event.
        address currentImplementation = _getImplementation();

        _upgradeTo(newImplementation);

        // call initialize function of the new implementation
        (bool success, bytes memory reason) =
            newImplementation.delegatecall(abi.encodeWithSignature("initialize()"));
        require(success, string(reason));

        emit ContractUpgraded(currentImplementation, newImplementation);
    }

    /// @inheritdoc IGovernance
    function verifyGovernanceMessage(bytes memory encodedVaa, uint8 action)
        public
        view
        returns (bytes32, bytes memory)
    {
        (IWormhole.VM memory vaa,) = _verifyGovernanceMessage(getConsumedVaas(), encodedVaa, action);
        return (vaa.hash, vaa.payload);
    }

    function _verifyAndConsumeGovernanceMessage(bytes memory encodedVaa, uint8 action)
        private
        returns (IWormhole.VM memory, uint256)
    {
        mapping(bytes32 => bool) storage consumedVaas = getConsumedVaas();

        // verify the governance message
        (IWormhole.VM memory vaa, uint256 offset) =
            _verifyGovernanceMessage(consumedVaas, encodedVaa, action);

        // store the hash for replay protection
        consumedVaas[vaa.hash] = true;

        return (vaa, offset);
    }

    function _verifyGovernanceMessage(
        mapping(bytes32 => bool) storage consumedVaas,
        bytes memory encodedVaa,
        uint8 action
    ) private view returns (IWormhole.VM memory vaa, uint256 offset) {
        // Make sure the blockchain has not forked.
        require(block.chainid == _evmChain, "invalid evm chain");

        // verify the governance message
        bool valid;
        string memory reason;
        (vaa, valid, reason) = _wormhole.parseAndVerifyVM(encodedVaa);
        require(valid, reason);

        // Confirm that the governance message was sent from the governance contract.
        require(vaa.emitterChainId == _GOVERNANCE_CHAIN, "invalid governance chain");
        require(vaa.emitterAddress == _GOVERNANCE_EMITTER, "invalid governance contract");

        // Confirm that this governance action has not been consumed already.
        require(!consumedVaas[vaa.hash], "governance action already consumed");

        bytes32 govModule;
        (govModule, offset) = vaa.payload.asBytes32Unchecked(offset);

        require(govModule == GOVERNANCE_MODULE, "invalid governance module");

        uint8 govAction;
        (govAction, offset) = vaa.payload.asUint8Unchecked(offset);

        require(govAction == action, "invalid governance action");
    }

    function _checkLength(bytes memory encoded, uint256 expected) private pure {
        require(encoded.length == expected, "invalid governance payload length");
    }

    // getters

    /// @inheritdoc IGovernance
    function governanceChainId() public pure returns (uint16) {
        return _GOVERNANCE_CHAIN;
    }

    /// @inheritdoc IGovernance
    function governanceContract() public pure returns (bytes32) {
        return _GOVERNANCE_EMITTER;
    }
}
