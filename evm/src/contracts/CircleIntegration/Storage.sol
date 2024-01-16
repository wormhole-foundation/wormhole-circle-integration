// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.19;

/**
 * WARNING: This is the state layout of V0 before the first upgrade.
 * Slots 0 -> 4 inclusive and slot 10 will be wiped to 0 on initialisation of the new
 * implementation and will be safe to use again in the future. We are no longer
 * using those variables in state, but they are instead immutables in the new implementation.
 * If using those slots again, ensure the slots are not being wiped to 0 in the
 * initialiser in future upgrades.
 */
/**
 * struct State {
 *         // state.slot := 0x0
 *         uint16 chainId;
 *         uint8 wormholeFinality;
 *         uint32 localDomain;
 *         address wormhole;
 *         uint16 governanceChainId;
 *
 *         // state.slot := 0x1
 *         bytes32 governanceContract;
 *
 *         // state.slot := 0x2
 *         address circleBridgeAddress;
 *
 *         // state.slot := 0x3
 *         address circleTransmitterAddress;
 *
 *         // state.slot := 0x4
 *         address circleTokenMinterAddress;
 *
 *         // state.slot := 0x5
 *         mapping(address => bool) initializedImplementations;
 *
 *         // state.slot := 0x6
 *         mapping(uint16 => bytes32) registeredEmitters;
 *
 *         // state.slot := 0x7
 *         mapping(uint16 => uint32) chainIdToDomain;
 *
 *         // state.slot := 0x8
 *         mapping(uint32 => uint16) domainToChainId;
 *
 *         // state.slot := 0x9
 *         mapping(bytes32 => bool) consumedMessages;
 *
 *         // state.slot := 0xa
 *         uint256 evmChain;
 *     }
 */
function getInitializedImplementations() pure returns (mapping(address => bool) storage state) {
    assembly ("memory-safe") {
        state.slot := 0x5
    }
}

function getRegisteredEmitters() pure returns (mapping(uint16 => bytes32) storage state) {
    assembly ("memory-safe") {
        state.slot := 0x6
    }
}

function getChainToDomain() pure returns (mapping(uint16 => uint32) storage state) {
    assembly ("memory-safe") {
        state.slot := 0x7
    }
}

function getDomainToChain() pure returns (mapping(uint32 => uint16) storage state) {
    assembly ("memory-safe") {
        state.slot := 0x8
    }
}

function getConsumedVaas() pure returns (mapping(bytes32 => bool) storage state) {
    assembly ("memory-safe") {
        state.slot := 0x9
    }
}
