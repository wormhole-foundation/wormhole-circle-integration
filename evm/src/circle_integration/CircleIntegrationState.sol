// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.13;

import {IWormhole} from "../interfaces/IWormhole.sol";

contract CircleIntegrationStorage {
    struct State {
        // Wormhole chain ID of this contract
        uint16 chainId;

        // The number of block confirmations needed before the wormhole network
        // will attest a message.
        uint8 wormholeFinality;

        // owner of this contract
        address owner;

        // intermediate state when transfering contract ownership
        address pendingOwner;

        // address of the Wormhole contract on this chain
        address wormhole;

        // address of the trusted Circle Bridge contract on this chain
        address circleBridgeAddress;

        // address of the trusted Circle Message Transmitter on this chain
        address circleTransmitterAddress;

        // mapping of initialized implementations
        mapping(address => bool) initializedImplementations;

        // Wormhole chain ID to known emitter address mapping
        mapping(uint16 => bytes32) registeredEmitters;

        // Circle Bridge accepted tokens
        mapping(address => bool) acceptedTokens;

        // Cricle Bridge accepted token to target chain accepted token
        mapping(address => mapping(uint16 => address)) targetAcceptedTokens;

        // Wormhole chain ID to USDC Chain Domain Mapping
        mapping(uint16 => uint32) chainDomains;

        // verified message hash to boolean
        mapping(bytes32 => bool) consumedMessages;

        // storage gap
        uint256[50] ______gap;
    }
}

contract CircleIntegrationState {
    CircleIntegrationStorage.State _state;
}

