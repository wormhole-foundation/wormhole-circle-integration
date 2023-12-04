// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.0;

interface IGovernance {
    /**
     * @notice Event indicating when proxy is pointing to new implementation (logic) contract.
     * @param oldContract Previous implementation contract address.
     * @param newContract New implementation contract address.
     */
    event ContractUpgraded(address indexed oldContract, address indexed newContract);

    /**
     * @notice This method consumes a governance VAA to save a trusted foreign Circle Integration
     * contract address and to associate a Wormhole chain ID with a CCTP domain of the same network.
     * @param encodedVaa Wormhole governance VAA.
     * @dev The governance VAA is encoded with the following encoded information:
     *   Field           | Bytes | Type    | Index
     *   -----------------------------------------
     *   Foreign Chain   |     2 | uint16  |    35
     *   Foreign Emitter |    32 | bytes32 |    37
     *   CCTP Domain     |     4 | uint32  |    69
     */
    function registerEmitterAndDomain(bytes memory encodedVaa) external;

    /**
     * @notice This method consumes a governance VAA to upgrade the implementation (logic) contract
     * and to initialize this implementation.
     * @param encodedVaa Wormhole governance VAA.
     * @dev The governance VAA is encoded with the following encoded information:
     *   Field              | Bytes | Type    | Index
     *   --------------------------------------------
     *   New Implementation |    32 | bytes32 |    35
     */
    function upgradeContract(bytes memory encodedVaa) external;

    /**
     * @notice This method validates a governance VAA.
     * @dev Reverts if:
     * - The EVM network has forked.
     * - The governance message was not attested.
     * - The governance message was generated on the wrong network.
     * - The governance message was already consumed.
     * - The encoded governance module is not the Circle Integration's governance module.
     * - The encoded governance action does not equal the provided one.
     * @param encodedVaa Wormhole governance VAA.
     * @param action Expected governance action.
     * @return messageHash Wormhole governance message hash.
     * @return payload Verified Wormhole governance message payload.
     */
    function verifyGovernanceMessage(bytes memory encodedVaa, uint8 action)
        external
        view
        returns (bytes32 messageHash, bytes memory payload);

    /**
     * @notice Fetch Circle Integration's governance chain ID.
     * @return GovernanceChainId value.
     */
    function governanceChainId() external returns (uint16);

    /**
     * @notice Fetch Circle Integration's governance emitter address.
     * @return GovernanceContract address.
     */
    function governanceContract() external returns (bytes32);
}
