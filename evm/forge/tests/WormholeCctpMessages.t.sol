// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {IWormhole} from "src/interfaces/IWormhole.sol";

import {WormholeCctpMessages} from "src/libraries/WormholeCctpMessages.sol";

contract MessagesTest is Test {
    using WormholeCctpMessages for *;

    function test_DepositWithPayloadSerde(
        bytes32 token,
        uint256 amount,
        uint32 sourceCctpDomain,
        uint32 targetCctpDomain,
        uint64 cctpNonce,
        bytes32 burnSource,
        bytes32 mintRecipient,
        bytes memory payload
    ) public {
        vm.assume(targetCctpDomain != sourceCctpDomain);
        vm.assume(payload.length > 0);
        vm.assume(payload.length < type(uint16).max);

        IWormhole.VM memory fakeVaa;
        fakeVaa.payload = token.encodeDeposit(
            amount,
            sourceCctpDomain,
            targetCctpDomain,
            cctpNonce,
            burnSource,
            mintRecipient,
            payload
        );

        // NOTE: 147 is the encoded message length up to the actual payload (including payload ID).
        assertEq(fakeVaa.payload.length, 147 + payload.length);

        uint8 payloadId = uint8(bytes1(fakeVaa.payload));
        assertEq(payloadId, 1);

        bytes32 decodedToken;
        uint256 decodedAmount;
        uint32 decodedSourceCctpDomain;
        uint32 decodedTargetCctpDomain;
        uint64 decodedCctpNonce;
        bytes32 decodedBurnSource;
        bytes32 decodedMintRecipient;
        bytes memory takenPayload;
        (
            decodedToken,
            decodedAmount,
            decodedSourceCctpDomain,
            decodedTargetCctpDomain,
            decodedCctpNonce,
            decodedBurnSource,
            decodedMintRecipient,
            takenPayload
        ) = fakeVaa.decodeDeposit();

        assertEq(decodedToken, token);
        assertEq(decodedAmount, amount);
        assertEq(decodedSourceCctpDomain, sourceCctpDomain);
        assertEq(decodedTargetCctpDomain, targetCctpDomain);
        assertEq(decodedCctpNonce, cctpNonce);
        assertEq(decodedBurnSource, burnSource);
        assertEq(decodedMintRecipient, mintRecipient);
        assertEq(keccak256(abi.encode(takenPayload)), keccak256(abi.encode(payload)));
    }
}
