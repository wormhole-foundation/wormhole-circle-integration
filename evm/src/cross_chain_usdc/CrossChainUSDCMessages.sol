// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.13;

import "../libraries/BytesLib.sol";

import "./CrossChainUSDCStructs.sol";

contract CrossChainUSDCMessages is CrossChainUSDCStructs {
    using BytesLib for bytes;

    function encodeDepositForBurnMessage(
        DepositForBurn memory message
    ) public pure returns (bytes memory) {
        return abi.encodePacked(
            uint8(1), // payloadId
            message.token,
            message.amount,
            message.sourceDomain,
            message.targetDomain,
            message.nonce,
            message.sender,
            message.mintRecipient
        );
    }

    function decodeDepositForBurnMessage(
        bytes memory encoded
    ) public pure returns (DepositForBurn memory message) {
        uint256 index = 0;

        // payloadId
        message.payloadId = encoded.toUint8(index);
        index += 1;

        require(message.payloadId == 1, "invalid message payloadId");

        // token address, encoded as bytes32
        message.token = encoded.toBytes32(index);
        index += 32;

        // amount burned
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

        // message sender
        message.sender = encoded.toBytes32(index);
        index += 32;

        // mint recipient
        message.mintRecipient = encoded.toBytes32(index);
        index += 32;

        require(index == encoded.length, "invalid message length");
    }
}