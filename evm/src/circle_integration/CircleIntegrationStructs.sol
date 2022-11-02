// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.13;

contract CircleIntegrationStructs {
    struct TransferParameters {
        address token;
        uint256 amount;
        uint16 targetChain;
        bytes32 mintRecipient;
    }

    struct RedeemParameters {
        bytes circleMessage;
        bytes circleAttestation;
        bytes encodedWormholeMessage;
    }

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
}
