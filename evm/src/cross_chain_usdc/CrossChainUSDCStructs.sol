// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.13;

contract CrossChainUSDCStructs {
    struct RedeemParameters {
        bytes encodedWormholeMessage;
        bytes circleBridgeMessage;
        bytes circleAttestation;
    }

    struct WormholeDepositForBurn {
        uint8 payloadId; // == 1
        uint32 sourceDomain;
        uint32 targetDomain;
        uint64 nonce;
        bytes32 sender; // this contract
        bytes32 mintRecipient;
    }

    struct CircleDepositForBurn {
        // Message Header
        uint32 version;
        uint32 sourceDomain;
        uint32 targetDomain;
        uint64 nonce;
        bytes32 sender;
        bytes32 mintRecipient;
        // End of Message Header
        // There should be an arbitrary length message following the header,
        // but we don't need to parse this message for verification purposes.
    }
}
