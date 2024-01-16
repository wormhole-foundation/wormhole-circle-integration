// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.19;

import {ICircleIntegration} from "src/interfaces/ICircleIntegration.sol";
import {IMessageTransmitter} from "src/interfaces/IMessageTransmitter.sol";
import {IWormhole} from "src/interfaces/IWormhole.sol";

import {BytesParsing} from "src/libraries/BytesParsing.sol";
import {Utils} from "src/libraries/Utils.sol";
import {WormholeCctpMessages} from "src/libraries/WormholeCctpMessages.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";

import {WormholeOverride} from "./WormholeOverride.sol";

struct CctpHeader {
    uint32 version;
    uint32 sourceDomain;
    uint32 destinationDomain;
    uint64 nonce;
    bytes32 sender;
    bytes32 recipient;
    bytes32 destinationCaller;
}

struct CctpMessage {
    CctpHeader header;
    bytes payload;
}

struct CctpTokenBurnMessage {
    CctpHeader header;
    uint32 version;
    bytes32 burnToken;
    bytes32 mintRecipient;
    uint256 amount;
    bytes32 messageSender;
}

struct CraftedCctpMessageParams {
    uint32 remoteDomain;
    uint64 nonce;
    bytes32 remoteToken;
    bytes32 mintRecipient;
    uint256 amount;
}

struct CraftedVaaParams {
    uint16 emitterChain;
    uint64 sequence;
}

library CircleIntegrationOverride {
    using WormholeCctpMessages for *;
    using WormholeOverride for IWormhole;
    using Utils for address;
    using BytesParsing for bytes;

    error NoLogsFound();

    address constant VM_ADDRESS = address(bytes20(uint160(uint256(keccak256("hevm cheat code")))));
    Vm constant vm = Vm(VM_ADDRESS);

    function setUpOverride(ICircleIntegration circleIntegration, uint256 signer) internal {
        circleIntegration.wormhole().setUpOverride(signer);

        // instantiate circle attester
        IMessageTransmitter transmitter = circleIntegration.circleTransmitter();

        // enable the guardian key as an attester
        vm.startPrank(transmitter.attesterManager());

        // set the signature threshold to 1
        transmitter.setSignatureThreshold(1);

        // enable our key as the attester
        transmitter.enableAttester(vm.addr(signer));

        vm.stopPrank();
    }

    function circleAttester(ICircleIntegration circleIntegration)
        internal
        view
        returns (uint256 pk)
    {
        pk = circleIntegration.wormhole().guardianPrivateKey();
    }

    function fetchCctpMessages(Vm.Log[] memory logs)
        internal
        pure
        returns (CctpMessage[] memory cctpMessages)
    {
        if (logs.length == 0) {
            revert NoLogsFound();
        }

        bytes32 topic = keccak256("MessageSent(bytes)");

        uint256 count;
        uint256 n = logs.length;
        for (uint256 i; i < n;) {
            unchecked {
                if (logs[i].topics[0] == topic) {
                    ++count;
                }
                ++i;
            }
        }

        // create log array to save published messages
        cctpMessages = new CctpMessage[](count);

        uint256 publishedIndex;
        for (uint256 i; i < n;) {
            unchecked {
                if (logs[i].topics[0] == topic) {
                    cctpMessages[publishedIndex] =
                        decodeCctpMessage(abi.decode(logs[i].data, (bytes)));
                    ++publishedIndex;
                }
                ++i;
            }
        }
    }

    function decodeCctpMessage(bytes memory encodedCctpMessage)
        internal
        pure
        returns (CctpMessage memory cctpMessage)
    {
        uint256 offset;

        (cctpMessage.header.version, offset) = encodedCctpMessage.asUint32Unchecked(offset);
        (cctpMessage.header.sourceDomain, offset) = encodedCctpMessage.asUint32Unchecked(offset);
        (cctpMessage.header.destinationDomain, offset) =
            encodedCctpMessage.asUint32Unchecked(offset);
        (cctpMessage.header.nonce, offset) = encodedCctpMessage.asUint64Unchecked(offset);
        (cctpMessage.header.sender, offset) = encodedCctpMessage.asBytes32Unchecked(offset);
        (cctpMessage.header.recipient, offset) = encodedCctpMessage.asBytes32Unchecked(offset);
        (cctpMessage.header.destinationCaller, offset) =
            encodedCctpMessage.asBytes32Unchecked(offset);
        (cctpMessage.payload, offset) = _takeRemainingBytes(encodedCctpMessage, offset);

        return cctpMessage;
    }

    function craftCctpTokenBurnMessage(
        ICircleIntegration circleIntegration,
        uint32 remoteDomain,
        uint64 nonce,
        bytes32 remoteToken,
        bytes32 mintRecipient,
        uint256 amount
    )
        internal
        view
        returns (
            CctpTokenBurnMessage memory burnMsg,
            bytes memory encoded,
            bytes memory attestation
        )
    {
        (burnMsg, encoded, attestation) = _craftCctpTokenBurnMessage(
            circleIntegration,
            remoteDomain,
            nonce,
            remoteToken,
            mintRecipient,
            amount,
            circleIntegration.getRegisteredEmitter(
                circleIntegration.getChainIdFromDomain(remoteDomain)
            ),
            address(circleIntegration).toUniversalAddress()
        );
    }

    function craftCctpTokenBurnMessage(
        ICircleIntegration circleIntegration,
        uint32 remoteDomain,
        uint64 nonce,
        bytes32 remoteToken,
        bytes32 mintRecipient,
        uint256 amount,
        bytes32 messageSender
    )
        internal
        view
        returns (
            CctpTokenBurnMessage memory burnMsg,
            bytes memory encoded,
            bytes memory attestation
        )
    {
        (burnMsg, encoded, attestation) = _craftCctpTokenBurnMessage(
            circleIntegration,
            remoteDomain,
            nonce,
            remoteToken,
            mintRecipient,
            amount,
            messageSender,
            address(circleIntegration).toUniversalAddress()
        );
    }

    function craftCctpTokenBurnMessage(
        ICircleIntegration circleIntegration,
        uint32 remoteDomain,
        uint64 nonce,
        bytes32 remoteToken,
        bytes32 mintRecipient,
        uint256 amount,
        bytes32 messageSender,
        bytes32 destinationCaller
    )
        internal
        view
        returns (
            CctpTokenBurnMessage memory burnMsg,
            bytes memory encoded,
            bytes memory attestation
        )
    {
        (burnMsg, encoded, attestation) = _craftCctpTokenBurnMessage(
            circleIntegration,
            remoteDomain,
            nonce,
            remoteToken,
            mintRecipient,
            amount,
            messageSender,
            destinationCaller
        );
    }

    function craftRedeemParameters(
        ICircleIntegration circleIntegration,
        CraftedCctpMessageParams memory cctpParams,
        CraftedVaaParams memory vaaParams,
        bytes32 fromAddress,
        bytes memory payload,
        bytes32 messageSender,
        bytes32 destinationCaller
    ) internal view returns (ICircleIntegration.RedeemParameters memory params) {
        params = _craftRedeemParameters(
            circleIntegration,
            cctpParams,
            vaaParams,
            fromAddress,
            payload,
            messageSender,
            destinationCaller
        );
    }

    function craftRedeemParameters(
        ICircleIntegration circleIntegration,
        CraftedCctpMessageParams memory cctpParams,
        CraftedVaaParams memory vaaParams,
        bytes32 fromAddress,
        bytes memory payload,
        bytes32 messageSender
    ) internal view returns (ICircleIntegration.RedeemParameters memory params) {
        params = _craftRedeemParameters(
            circleIntegration,
            cctpParams,
            vaaParams,
            fromAddress,
            payload,
            messageSender,
            address(circleIntegration).toUniversalAddress()
        );
    }

    function craftRedeemParameters(
        ICircleIntegration circleIntegration,
        CraftedCctpMessageParams memory cctpParams,
        CraftedVaaParams memory vaaParams,
        bytes32 fromAddress,
        bytes memory payload
    ) internal view returns (ICircleIntegration.RedeemParameters memory params) {
        params = _craftRedeemParameters(
            circleIntegration,
            cctpParams,
            vaaParams,
            fromAddress,
            payload,
            circleIntegration.getRegisteredEmitter(
                circleIntegration.getChainIdFromDomain(cctpParams.remoteDomain)
            ),
            address(circleIntegration).toUniversalAddress()
        );
    }

    // private

    function _takeRemainingBytes(bytes memory encoded, uint256 startOffset)
        private
        pure
        returns (bytes memory payload, uint256 offset)
    {
        uint256 payloadLength = encoded.length - startOffset;
        (payload, offset) = encoded.sliceUnchecked(offset, payloadLength);
    }

    function _craftRedeemParameters(
        ICircleIntegration circleIntegration,
        CraftedCctpMessageParams memory cctpParams,
        CraftedVaaParams memory vaaParams,
        bytes32 burnSource,
        bytes memory payload,
        bytes32 messageSender,
        bytes32 destinationCaller
    ) private view returns (ICircleIntegration.RedeemParameters memory params) {
        CctpTokenBurnMessage memory burnMsg;
        (burnMsg, params.encodedCctpMessage, params.cctpAttestation) = _craftCctpTokenBurnMessage(
            circleIntegration,
            cctpParams.remoteDomain,
            cctpParams.nonce,
            cctpParams.remoteToken,
            cctpParams.mintRecipient,
            cctpParams.amount,
            messageSender,
            destinationCaller
        );

        (, params.encodedVaa) = circleIntegration.wormhole().craftVaa(
            vaaParams.emitterChain,
            burnMsg.messageSender,
            vaaParams.sequence,
            burnMsg.burnToken.encodeDeposit(
                burnMsg.amount,
                burnMsg.header.sourceDomain,
                burnMsg.header.destinationDomain,
                burnMsg.header.nonce,
                burnSource,
                burnMsg.mintRecipient,
                payload
            )
        );
    }

    function _craftCctpTokenBurnMessage(
        ICircleIntegration circleIntegration,
        uint32 remoteDomain,
        uint64 nonce,
        bytes32 remoteToken,
        bytes32 mintRecipient,
        uint256 amount,
        bytes32 messageSender,
        bytes32 destinationCaller
    )
        private
        view
        returns (
            CctpTokenBurnMessage memory burnMsg,
            bytes memory encoded,
            bytes memory attestation
        )
    {
        burnMsg.header = CctpHeader({
            version: 0,
            sourceDomain: remoteDomain,
            destinationDomain: circleIntegration.localDomain(),
            nonce: nonce,
            sender: circleIntegration.circleBridge().remoteTokenMessengers(remoteDomain),
            recipient: address(circleIntegration.circleBridge()).toUniversalAddress(),
            destinationCaller: destinationCaller
        });

        burnMsg.burnToken = remoteToken;
        burnMsg.mintRecipient = mintRecipient;
        burnMsg.amount = amount;
        burnMsg.messageSender = messageSender;

        encoded = abi.encodePacked(
            burnMsg.header.version,
            burnMsg.header.sourceDomain,
            burnMsg.header.destinationDomain,
            burnMsg.header.nonce,
            burnMsg.header.sender,
            burnMsg.header.recipient,
            burnMsg.header.destinationCaller,
            burnMsg.version,
            burnMsg.burnToken,
            burnMsg.mintRecipient,
            burnMsg.amount,
            burnMsg.messageSender
        );

        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(circleAttester(circleIntegration), keccak256(encoded));
        attestation = abi.encodePacked(r, s, v);
    }
}
