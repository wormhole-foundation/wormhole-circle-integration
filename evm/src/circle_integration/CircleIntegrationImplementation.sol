// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.19;

import {ERC1967Upgrade} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Upgrade.sol";

import {CircleIntegration} from "./CircleIntegration.sol";

// Goerli
uint256 constant ETH_EVM_CHAIN_ID = 5;
// Fuji
uint256 constant AVALANCHE_EVM_CHAIN_ID = 43113;
// Arbitrum Goerli
uint256 constant ARBITRUM_EVM_CHAIN_ID = 421613;
// Optimism Goerli
uint256 constant OPTIMISM_EVM_CHAIN_ID = 420;

bytes32 constant ETH_EMITTER = bytes32(uint256(uint160(address(0x0A69146716B3a21622287Efa1607424c663069a4))));
bytes32 constant AVALANCHE_EMITTER = bytes32(uint256(uint160(address(0x58f4C17449c90665891C42E14D34aae7a26A472e))));
bytes32 constant ARBITRUM_EMITTER = bytes32(uint256(uint160(address(0x2E8F5E00a9C5D450A72700546B89E2b70DfB00f2))));
bytes32 constant OPTIMISM_EMITTER = bytes32(uint256(uint160(address(0x2703483B1a5a7c577e8680de9Df8Be03c6f30e3c))));

uint16 constant ETH_CHAIN_ID = 2;
uint16 constant AVALANCHE_CHAIN_ID = 6;
uint16 constant ARBITRUM_CHAIN_ID = 23;
uint16 constant OPTIMISM_CHAIN_ID = 24;

uint32 constant ETH_DOMAIN = 0;
uint32 constant AVALANCHE_DOMAIN = 1;
uint32 constant ARBITRUM_DOMAIN = 3;
uint32 constant OPTIMISM_DOMAIN = 2;

contract CircleIntegrationImplementation is CircleIntegration {
    function initialize() public virtual initializer {
        // update the registeredEmitters state variable
        if (block.chainid != ETH_EVM_CHAIN_ID) {
            setEmitter(ETH_CHAIN_ID, ETH_EMITTER);
            setChainIdToDomain(ETH_CHAIN_ID, ETH_DOMAIN);
            setDomainToChainId(ETH_DOMAIN, ETH_CHAIN_ID);
        }

        if (block.chainid != AVALANCHE_EVM_CHAIN_ID) {
            setEmitter(AVALANCHE_CHAIN_ID, AVALANCHE_EMITTER);
            setChainIdToDomain(AVALANCHE_CHAIN_ID, AVALANCHE_DOMAIN);
            setDomainToChainId(AVALANCHE_DOMAIN, AVALANCHE_CHAIN_ID);
        }

        if (block.chainid != ARBITRUM_EVM_CHAIN_ID) {
            setEmitter(ARBITRUM_CHAIN_ID, ARBITRUM_EMITTER);
            setChainIdToDomain(ARBITRUM_CHAIN_ID, ARBITRUM_DOMAIN);
            setDomainToChainId(ARBITRUM_DOMAIN, ARBITRUM_CHAIN_ID);
        }

        if (block.chainid != OPTIMISM_EVM_CHAIN_ID) {
            setEmitter(OPTIMISM_CHAIN_ID, OPTIMISM_EMITTER);
            setChainIdToDomain(OPTIMISM_CHAIN_ID, OPTIMISM_DOMAIN);
            setDomainToChainId(OPTIMISM_DOMAIN, OPTIMISM_CHAIN_ID);
        }
    }

    modifier initializer() {
        address impl = ERC1967Upgrade._getImplementation();

        require(!isInitialized(impl), "already initialized");

        setInitialized(impl);

        _;
    }

    function circleIntegrationImplementation() public pure returns (bytes32) {
        return keccak256("circleIntegrationImplementation()");
    }
}
