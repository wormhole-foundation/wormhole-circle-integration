// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.13;

import "../libraries/BytesLib.sol";

import "./CrossChainUSDCStructs.sol";

contract CrossChainUSDCMessages is CrossChainUSDCStructs {
    using BytesLib for bytes;

    function encodeWormholeDeposit(
        WormholeDeposit memory message
    ) public pure returns (bytes memory) {
        return abi.encodePacked(
            uint8(1), // payloadId
            message.token,
            message.amount,
            message.sourceDomain,
            message.targetDomain,
            message.nonce,
            message.circleSender
        );
    }

    function encodeWormholeDepositWithPayload(
        WormholeDepositWithPayload memory message
    ) public pure returns (bytes memory) {
        return abi.encodePacked(
            uint8(2), // payloadId
            message.depositHeader.token,
            message.depositHeader.amount,
            message.depositHeader.sourceDomain,
            message.depositHeader.targetDomain,
            message.depositHeader.nonce,
            message.depositHeader.circleSender,
            message.mintRecipient,
            message.payload.length,
            message.payload
        );
    }

    function decodeWormholeDeposit(
        bytes memory encoded
    ) public pure returns (WormholeDeposit memory message) {
        uint256 index = 0;

        // payloadId
        message.payloadId = encoded.toUint8(index);
        index += 1;

        require(message.payloadId == 1, "invalid message payloadId");

        // token address
        message.token = encoded.toBytes32(index);
        index += 32;

        // token amount
        message.amount = encoded.toUint256(index);
        index += 32;

        // source domain
        message.sourceDomain = encoded.toUint32(index);
        index += 4;

        // target domain
        message.targetDomain = encoded.toUint32(index);
        index += 4;

        // nonce
        message.nonce = encoded.toUint64(index);
        index += 8;

        // circle bridge source contract
        message.circleSender = encoded.toBytes32(index);
        index += 32;

        require(index == encoded.length, "invalid message length");
    }

    function decodeWormholeDepositWithPayload(
        bytes memory encoded
    ) public pure returns (WormholeDepositWithPayload memory message) {
        uint256 index = 0;

        // payloadId
        message.depositHeader.payloadId = encoded.toUint8(index);
        index += 1;

        require(message.depositHeader.payloadId == 2, "invalid message payloadId");

        // token address
        message.depositHeader.token = encoded.toBytes32(index);
        index += 32;

        // token amount
        message.depositHeader.amount = encoded.toUint256(index);
        index += 32;

        // source domain
        message.depositHeader.sourceDomain = encoded.toUint32(index);
        index += 4;

        // target domain
        message.depositHeader.targetDomain = encoded.toUint32(index);
        index += 4;

        // nonce
        message.depositHeader.nonce = encoded.toUint64(index);
        index += 8;

        // circle bridge source contract
        message.depositHeader.circleSender = encoded.toBytes32(index);
        index += 32;

        // mintRecipient (target contract)
        message.mintRecipient = encoded.toBytes32(index);
        index += 32;

        // message payload length
        uint256 payloadLen = encoded.toUint256(index);
        index += 32;

        // parse the additional payload to confirm the entire message was parsed
        message.payload = encoded.slice(index, payloadLen);
        index += payloadLen;

        require(index == encoded.length, "invalid message length");
    }

    function decodeCircleDeposit(
        bytes memory encoded
    ) public pure returns (CircleDeposit memory message) {
        uint256 index = 0;

        // version
        message.version = encoded.toUint32(index);
        index += 4;

        // source domain
        message.sourceDomain = encoded.toUint32(index);
        index += 4;

        // target domain
        message.targetDomain = encoded.toUint32(index);
        index += 4;

        // nonce
        message.nonce = encoded.toUint64(index);
        index += 8;

        // circle bridge source contract
        message.circleSender = encoded.toBytes32(index);
        index += 32;

        // circle bridge target contract
        message.circleReceiver = encoded.toBytes32(index);
        index += 32;
    }
}
