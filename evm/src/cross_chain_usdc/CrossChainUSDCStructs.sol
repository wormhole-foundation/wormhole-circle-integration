// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.13;

contract CrossChainUSDCStructs {
    struct DepositForBurn {
        uint8 payloadId; // == 1
        bytes32 token;
        uint256 amount;
        uint32 sourceDomain;
        uint32 targetDomain;
        uint64 nonce;
        bytes32 sender; // this contract
        bytes32 mintRecipient;
    }
}
