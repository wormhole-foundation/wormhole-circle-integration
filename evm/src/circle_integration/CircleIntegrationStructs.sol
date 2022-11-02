// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.13;

contract CircleIntegrationStructs {
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
}
