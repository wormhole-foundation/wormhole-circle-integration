// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Upgrade.sol";

import "./CircleIntegrationSetters.sol";
import "./CircleIntegrationGetters.sol";
import "./CircleIntegrationState.sol";

contract CircleIntegrationGovernance is CircleIntegrationGetters, ERC1967Upgrade {
    event ContractUpgraded(address indexed oldContract, address indexed newContract);
    event WormholeFinalityUpdated(uint8 indexed oldLevel, uint8 indexed newFinality);
    event OwnershipTransfered(address indexed oldOwner, address indexed newOwner);

    /// @dev upgrade serves to upgrade contract implementations
    function upgrade(uint16 chainId_, address newImplementation) public onlyOwner {
        require(chainId_ == chainId(), "wrong chain");

        address currentImplementation = _getImplementation();

        _upgradeTo(newImplementation);

        /// @dev call initialize function of the new implementation
        (bool success, bytes memory reason) = newImplementation.delegatecall(
            abi.encodeWithSignature("initialize()")
        );

        require(success, string(reason));

        emit ContractUpgraded(currentImplementation, newImplementation);
    }

    /// @dev updateWormholeFinality serves to change the wormhole messaging consistencyLevel
    function updateWormholeFinality(
        uint16 chainId_,
        uint8 newWormholeFinality
    ) public onlyOwner {
        require(chainId_ == chainId(), "wrong chain");
        require(newWormholeFinality > 0, "invalid wormhole finality");

        uint8 currentWormholeFinality = wormholeFinality();

        setWormholeFinality(newWormholeFinality);

        emit WormholeFinalityUpdated(currentWormholeFinality, newWormholeFinality);
    }

    /**
     * @dev submitOwnershipTransferRequest serves to begin the ownership transfer process of the contracts
     * - it saves an address for the new owner in the pending state
     */
    function submitOwnershipTransferRequest(
        uint16 chainId_,
        address newOwner
    ) public onlyOwner {
        require(chainId_ == chainId(), "wrong chain");
        require(newOwner != address(0), "newOwner cannot equal address(0)");

        setPendingOwner(newOwner);
    }

    /**
     * @dev confirmOwnershipTransferRequest serves to finalize an ownership transfer
     * - it checks that the caller is the pendingOwner to validate the wallet address
     * - it updates the owner state variable with the pendingOwner state variable
     */
    function confirmOwnershipTransferRequest() public {
        /// cache the new owner address
        address newOwner = pendingOwner();

        require(msg.sender == newOwner, "caller must be pendingOwner");

        /// cache currentOwner for Event
        address currentOwner = owner();

        /// @dev update the owner in the contract state and reset the pending owner
        setOwner(newOwner);
        setPendingOwner(address(0));

        emit OwnershipTransfered(currentOwner, newOwner);
    }

    /// @dev registerEmitter serves to save trusted emitter contract addresses
    function registerEmitter(
        uint16 emitterChainId,
        bytes32 emitterAddress
    ) public onlyOwner {
        // sanity check both input arguments
        require(
            emitterAddress != bytes32(0),
            "emitterAddress cannot equal bytes32(0)"
        );
        require(
            getRegisteredEmitter(emitterChainId) == bytes32(0),
            "emitterChainId already registered"
        );

        // update the registeredEmitters state variable
        setEmitter(emitterChainId, emitterAddress);
    }

    /// @dev registerChainDomain serves to save the USDC Bridge chain domains
    function registerChainDomain(uint16 chainId_, uint32 domain) public onlyOwner {
        // update the chainDomains state variable
        setChainDomain(chainId_, domain);
    }

    /// @dev addAcceptedToken serves to determine which tokens can be burned + minted
    /// via the Circle Bridge
    function registerAcceptedToken(address token) public onlyOwner {
        // update the acceptedTokens mapping
        addAcceptedToken(token);
    }

    function registerTargetChainToken(address sourceToken, uint16 chainId_, address targetToken) public onlyOwner {
        require(isAcceptedToken(sourceToken), "token not accepted");

        // update the targetAcceptedTokens mapping
        addTargetAcceptedToken(sourceToken, chainId_, targetToken);
    }

    modifier onlyOwner() {
        require(owner() == msg.sender, "caller not the owner");
        _;
    }
}
