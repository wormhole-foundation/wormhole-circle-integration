// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.0;

import {IWormhole} from "./IWormhole.sol";
import {IMessageTransmitter} from "./IMessageTransmitter.sol";
import {ITokenMessenger} from "./ITokenMessenger.sol";
import {ITokenMinter} from "./ITokenMinter.sol";

import {IGovernance} from "./IGovernance.sol";

/**
 * @title Wormhole Circle Integration.
 * @notice This contract burns and mints Circle-supported tokens by using Circle's Cross-Chain
 * Transfer Protocol. It also emits Wormhole messages with arbitrary payloads to allow for
 * additional composability when performing cross-chain transfers of Circle-suppored assets. These
 * messages are paired with each other by encoding the CCTP source domain, target domain, and nonce.
 */
interface ICircleIntegration is IGovernance {
    /**
     * @notice Message encoded in Wormhole message payload. Wormhole CCTP ensures that this message
     * is paired with the corresponding CCTP Token Burn message.
     */
    struct DepositWithPayload {
        bytes32 token;
        uint256 amount;
        uint32 sourceDomain;
        uint32 targetDomain;
        uint64 nonce;
        bytes32 fromAddress;
        bytes32 mintRecipient;
        bytes payload;
    }

    /**
     * @notice Parameters used for outbound transfers.
     */
    struct TransferParameters {
        address token;
        uint256 amount;
        uint16 targetChain;
        bytes32 mintRecipient;
    }

    /**
     * @notice Parameters used for inbound transfers.
     */
    struct RedeemParameters {
        bytes encodedVaa;
        bytes encodedCctpMessage;
        bytes cctpAttestation;
    }

    /**
     * @notice Emitted when Circle-supported assets have been minted to the mintRecipient.
     * @param emitterChainId Wormhole chain ID of source emitter contract.
     * @param emitterAddress Universal address of source emitter.
     * @param sequence Wormhole message sequence used to mint tokens.
     */
    event Redeemed(
        uint16 indexed emitterChainId, bytes32 indexed emitterAddress, uint64 indexed sequence
    );

    /**
     * @notice This method calls the CCTP Token Messenger contract to burn Circle-supported tokens.
     * It emits a Wormhole message containing a user-specified payload with instructions for what to
     * do with the Circle-supported assets once they have been minted on the target chain.
     * @dev This method does not protect against re-entrancy here because we rely on the CCTP Token
     * Messenger contract to protect against any possible re-entrancy. We are leaning on the fact
     * that the Token Messenger keeps track of its local tokens, which are the only tokens it allows
     * to burn.
     *
     *  Reverts if:
     * - `targetChain` is not supported (i.e. no Wormhole Circle Integration exists on targeted
     *   network).
     * - User passes insufficient value to pay Wormhole message fee (reverts at Wormhole level).
     * - `token` is not supported by CCTP Token Messenger (reverts at CCTP level).
     * - `amount` is zero (reverts at CCTP level).
     * - `mintRecipient` is zero address (reverts at CCTP level).
     * @param transferParams Struct containing the following attributes:
     * - `token` Address of the token to be burned.
     * - `amount` Amount of `token` to be burned.
     * - `targetChain` Wormhole chain ID of the target blockchain.
     * - `mintRecipient` The recipient wallet or contract address on the target chain.
     * @param wormholeNonce Arbitrary ID for integrator-specific use.
     * @param payload Arbitrary payload to be delivered to the target chain via Wormhole.
     * @return wormholeSequence Wormhole message sequence number for this contract.
     */
    function transferTokensWithPayload(
        TransferParameters calldata transferParams,
        uint32 wormholeNonce,
        bytes calldata payload
    ) external payable returns (uint64 wormholeSequence);

    /**
     * @notice This method verifies a Wormhole VAA from the source chain and reconciles this message
     * with the CCTP message. It calls the CCTP Message Transmitter using the CCTP attestation to
     * allow the CCTP Token Minter to mint tokens to the specified mint recipient.
     * @dev This contract requires that the mint recipient is the caller to ensure atomic execution
     * of the additional instructions in the Wormhole message.
     *
     * Reverts if:
     * - Wormhole message is not properly attested (reverts at Wormhole level).
     * - Wormhole message was not emitted from a registered contract.
     * - Wormhole message was already consumed by this contract.
     * - msg.sender is not the encoded mint recipient.
     * - CCTP Token Burn message and Wormhole message are not associated with each other.
     * - CCTP Message Transmitter's `receiveMessage` call fails (reverts at CCTP level).
     * @param params Struct containing the following attributes:
     * - `encodedVaa` Wormhole VAA reflecting message emitted by a registered contract, encoding the
     *    CCTP message information to reconcile with the provided CCTP message.
     * - `encodedCctpMessage` CCTP Message emitted by the CCTP Token Messenger contract with
     *    information regarding the token burned from the source network.
     * - `cctpAttestation` Serialized EC signature(s) attesting the CCTP message.
     * @return deposit Struct containing the following attributes:
     * - `token` Address (left padded with zeros) of minted token.
     * - `amount` Amount of tokens minted.
     * - `sourceDomain` CCTP domain of originating network (where tokens were burned).
     * - `targetDomain` CCTP domain of this network.
     * - `nonce` CCTP sequence number for token burn.
     * - `fromAddress` Source network's caller address.
     * - `mintRecipient` Recipient of minted tokens (must be caller of this contract).
     * - `payload` Message encoding integrator-specific information.
     */
    function redeemTokensWithPayload(RedeemParameters calldata params)
        external
        returns (DepositWithPayload memory deposit);

    /**
     * @notice Fetches the local token address given an address and domain from
     * a different chain.
     * @param sourceDomain CCTP domain for the sending chain.
     * @param sourceToken Address of the token for the sending chain.
     * @return LocalToken address left-padded with zeros.
     */
    function fetchLocalTokenAddress(uint32 sourceDomain, bytes32 sourceToken)
        external
        view
        returns (bytes32);

    /**
     * @notice Converts EVM address to universal (32-bytes left-padded with zeros) address.
     * @param evmAddr Address to convert.
     * @return converted Universal address.
     */
    function addressToBytes32(address evmAddr) external view returns (bytes32 converted);

    /**
     * @notice This method encodes the `DepositWithPayload` struct into the Wormhole message
     * payload, which includes its payload ID.
     * @param message `DepositWithPayload` struct containing the following attributes:
     * - `token` Address (left padded with zeros) of minted token.
     * - `amount` Amount of tokens minted.
     * - `sourceDomain` CCTP domain of originating network (where tokens were burned).
     * - `targetDomain` CCTP domain of target network.
     * - `nonce` CCTP sequence number for token burn.
     * - `fromAddress` Source network's caller address.
     * - `mintRecipient` Recipient of minted tokens (must be caller of this contract).
     * - `payload` Message encoding integrator-specific information.
     * @return EncodedDepositWithPayload bytes
     */
    function encodeDepositWithPayload(DepositWithPayload memory message)
        external
        pure
        returns (bytes memory);

    /**
     * @notice This method decodes an encoded `DepositWithPayload` struct.
     * @dev Reverts if:
     * - The first byte (payloadId) does not equal 1.
     * - The length of the payload does not equal the encoded length.
     * @param encoded Encoded `DepositWithPayload` message.
     * @return deposit `DepositWithPayload` struct containing the following attributes:
     * - `token` Address (left padded with zeros) of minted token.
     * - `amount` Amount of tokens minted.
     * - `sourceDomain` CCTP domain of originating network (where tokens were burned).
     * - `targetDomain` CCTP domain of target network.
     * - `nonce` CCTP sequence number for token burn.
     * - `fromAddress` Source network's caller address.
     * - `mintRecipient` Recipient of minted tokens (must be caller of this contract).
     * - `payload` Message encoding integrator-specific information.
     */
    function decodeDepositWithPayload(bytes memory encoded)
        external
        pure
        returns (DepositWithPayload memory deposit);

    /**
     * @notice This method checks whether deployed implementation has been initialized.
     * @param impl Address of implementation (logic) contract.
     * @return IsInitialized indicating whether implementation has been initialized.
     */
    function isInitialized(address impl) external view returns (bool);

    /**
     * @notice Wormhole contract interface.
     * @return IWormhole interface.
     */
    function wormhole() external view returns (IWormhole);

    /**
     * @notice Wormhole chain ID of this network.
     * @return ChainId value.
     */
    function chainId() external view returns (uint16);

    /**
     * @notice Wormhole message finality.
     * @return WormholeFinality value.
     */
    function wormholeFinality() external view returns (uint8);

    /**
     * @notice CCTP Token Messenger contract interface.
     * @return ITokenMessenger interface.
     */
    function circleBridge() external view returns (ITokenMessenger);

    /**
     * @notice CCTP Token Minter contract interface.
     * @return ITokenMinter interface.
     */
    function circleTokenMinter() external view returns (ITokenMinter);

    /**
     * @notice CCTP Message Transmitter contract interface.
     * @return ICircleTransmitter interface.
     */
    function circleTransmitter() external view returns (IMessageTransmitter);

    /**
     * @notice Registered Circle Integration contract for a particular Wormhole chain ID.
     * @param chain Wormhole chain ID for message sender.
     * @return RegisteredEmitter as universal address.
     */
    function getRegisteredEmitter(uint16 chain) external view returns (bytes32);

    /**
     * @notice This method checks whether token is valid using CCTP Token Minter's burn limit.
     * @param token Address of Circle-supported token.
     * @return AcceptedToken indicating whether token is valid.
     */
    function isAcceptedToken(address token) external view returns (bool);

    /**
     * @notice Convert CCTP domain to Wormhole chain ID.
     * @param chain Wormhole chain ID.
     * @return CctpDomain value.
     */
    function getDomainFromChainId(uint16 chain) external view returns (uint32);

    /**
     * @notice Convert Wormhole chain ID to CCTP domain.
     * @param cctpDomain CCTP domain.
     * @return ChainId value.
     */
    function getChainIdFromDomain(uint32 cctpDomain) external view returns (uint16);

    /**
     * @notice This method checks if Wormhole message was already consumed by this contract.
     * @param vaaHash Wormhole message hash.
     * @return IsMessageConsumed indicating whether message has been consumed.
     */
    function isMessageConsumed(bytes32 vaaHash) external view returns (bool);

    /**
     * @notice Fetch CCTP domain of this network.
     * @return LocalDomain value.
     */
    function localDomain() external view returns (uint32);

    /**
     * @notice Fetch this network's EVM chain ID.
     * @return EVMChainID value.
     */
    function evmChain() external view returns (uint256);
}
