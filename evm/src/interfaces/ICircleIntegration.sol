// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.13;

import {IWormhole} from "./IWormhole.sol";
import {ICircleBridge} from "./circle/ICircleBridge.sol";
import {IMessageTransmitter} from "./circle/IMessageTransmitter.sol";

interface ICircleIntegration {
    struct RedeemParameters {
        bytes encodedWormholeMessage;
        bytes circleBridgeMessage;
        bytes circleAttestation;
    }

    struct WormholeDepositWithPayload {
        uint8 payloadId; // == 1
        bytes32 token;
        uint256 amount;
        uint32 sourceDomain;
        uint32 targetDomain;
        uint64 nonce;
        bytes32 fromAddress;
        bytes32 mintRecipient;
        bytes payload;
    }

    struct CircleDeposit {
        // Message Header
        uint32 version;
        uint32 sourceDomain;
        uint32 targetDomain;
        uint64 nonce;
        bytes32 circleSender;
        bytes32 circleReceiver;
        // End of Message Header
        // There should be an arbitrary length message following the header,
        // but we don't need to parse this message for verification purposes.
    }

    function transferTokensWithPayload(
        address token,
        uint256 amount,
        uint16 targetChain,
        bytes32 mintRecipient,
        bytes memory payload
    ) external payable returns (uint64 messageSequence);

    function redeemTokensWithPayload(
        RedeemParameters memory params
    ) external returns (WormholeDepositWithPayload memory wormholeDepositWithPayload);

    function encodeWormholeDepositWithPayload(
        WormholeDepositWithPayload memory message
    ) external pure returns (bytes memory);

    function decodeWormholeDepositWithPayload(
        bytes memory encoded
    ) external pure returns (WormholeDepositWithPayload memory message);

    function decodeCircleDeposit(
        bytes memory encoded
    ) external pure returns (CircleDeposit memory message);

    function owner() external view returns (address);

    function pendingOwner() external view returns (address);

    function isInitialized(address impl) external view returns (bool);

    function wormhole() external view returns (IWormhole);

    function chainId() external view returns (uint16);

    function wormholeFinality() external view returns (uint8);

    function circleBridge() external view returns (ICircleBridge);

    function circleTransmitter() external view returns (IMessageTransmitter);

    function getRegisteredEmitter(uint16 emitterChainId) external view returns (bytes32);

    function isAcceptedToken(address token) external view returns (bool);

    function getChainDomain(uint16 chainId_) external view returns (uint32);

    function isMessageConsumed(bytes32 hash) external view returns (bool);
}
