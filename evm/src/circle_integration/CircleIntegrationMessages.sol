// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.13;

import {BytesLib} from "wormhole/libraries/external/BytesLib.sol";

import {CircleIntegrationStructs} from "./CircleIntegrationStructs.sol";

contract CircleIntegrationMessages is CircleIntegrationStructs {
    using BytesLib for bytes;

    function encodeDepositWithPayload(DepositWithPayload memory message) public pure returns (bytes memory) {
        return abi.encodePacked(
            uint8(1), // payloadId
            message.token,
            message.amount,
            message.sourceDomain,
            message.targetDomain,
            message.nonce,
            message.fromAddress,
            message.mintRecipient,
            uint16(message.payload.length),
            message.payload
        );
    }

    function decodeDepositWithPayload(bytes memory encoded) public pure returns (DepositWithPayload memory message) {
        // payloadId
        require(encoded.toUint8(0) == 1, "invalid message payloadId");

        uint256 index = 1;

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

        // fromAddress (contract caller)
        message.fromAddress = encoded.toBytes32(index);
        index += 32;

        // mintRecipient (target contract)
        message.mintRecipient = encoded.toBytes32(index);
        index += 32;

        // message payload length
        uint256 payloadLen = encoded.toUint16(index);
        index += 2;

        // parse the additional payload to confirm the entire message was parsed
        message.payload = encoded.slice(index, payloadLen);
        index += payloadLen;

        require(index == encoded.length, "invalid message length");
    }
}
