// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.13;

contract CircleIntegrationStorage {
    struct State {
        /// @dev Wormhole chain ID of this contract
        uint16 chainId;

        /**
         * @dev The number of block confirmations needed before the wormhole network
         * will attest a message.
         */
        uint8 wormholeFinality;

        /// @dev Circle domain for this blockchain (grabbed from Circle's MessageTransmitter)
        uint32 localDomain;

        /// @dev address of the Wormhole contract on this chain
        address wormhole;

        /// @dev Wormhole governance chain ID
        uint16 governanceChainId;

        /// @dev Wormhole governance contract address (bytes32 zero-left-padded)
        bytes32 governanceContract;

        /// @dev address of the Circle Bridge contract on this chain
        address circleBridgeAddress;

        /// @dev address of the Circle Message Transmitter on this chain
        address circleTransmitterAddress;

        /// @dev address of the Circle Token Minter on this chain
        address circleTokenMinterAddress;

        /// @dev mapping of initialized implementation (logic) contracts
        mapping(address => bool) initializedImplementations;

        /// @dev Wormhole chain ID to known emitter address mapping
        mapping(uint16 => bytes32) registeredEmitters;

        /// @dev Wormhole chain ID to Circle chain domain mapping
        mapping(uint16 => uint32) chainIdToDomain;

        /// @dev Wormhole chain ID to Circle chain domain mapping
        mapping(uint32 => uint16) domainToChainId;

        /// @dev verified Wormhole message hash to boolean
        mapping(bytes32 => bool) consumedMessages;

        /// @dev expected EVM chainid
        uint256 evmChain;

        /// @dev storage gap for additional state variables in future versions
        uint256[50] ______gap;
    }
}

contract CircleIntegrationState {
    CircleIntegrationStorage.State _state;
}
