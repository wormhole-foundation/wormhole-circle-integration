// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IWormhole} from "src/interfaces/IWormhole.sol";
import {IMessageTransmitter} from "src/interfaces/IMessageTransmitter.sol";
import {ITokenMessenger} from "src/interfaces/ITokenMessenger.sol";
import {ITokenMinter} from "src/interfaces/ITokenMinter.sol";
import {ICircleIntegration} from "src/interfaces/ICircleIntegration.sol";

import {Utils} from "src/libraries/Utils.sol";
import {WormholeCctpMessages} from "src/libraries/WormholeCctpMessages.sol";

import {Governance} from "./Governance.sol";
import {
    getChainToDomain,
    getConsumedVaas,
    getDomainToChain,
    getInitializedImplementations,
    getRegisteredEmitters
} from "./Storage.sol";

abstract contract Logic is ICircleIntegration, Governance {
    using Utils for address;
    using SafeERC20 for IERC20;
    using WormholeCctpMessages for *;

    /// @inheritdoc ICircleIntegration
    function transferTokensWithPayload(
        TransferParameters calldata transferParams,
        uint32 wormholeNonce,
        bytes calldata payload
    ) public payable returns (uint64 wormholeSequence) {
        // Is the foreign Wormhole Circle Integration registered?
        bytes32 destinationCaller = getRegisteredEmitters()[transferParams.targetChain];
        require(destinationCaller != 0, "target contract not registered");

        // Deposit tokens into this contract to prepare for burning.
        IERC20(transferParams.token).safeTransferFrom(
            msg.sender, address(this), transferParams.amount
        );

        // Approve the Token Messenger to spend tokens.
        setTokenMessengerApproval(transferParams.token, transferParams.amount);

        // Invoke Token Messenger to burn tokens and emit a CCTP token burn message.
        (wormholeSequence,) = burnAndPublish(
            destinationCaller,
            getChainToDomain()[transferParams.targetChain],
            transferParams.token,
            transferParams.amount,
            transferParams.mintRecipient,
            wormholeNonce,
            payload,
            msg.value
        );
    }

    /// @inheritdoc ICircleIntegration
    function redeemTokensWithPayload(RedeemParameters calldata params)
        public
        returns (DepositWithPayload memory deposit)
    {
        // This check prevents this contract existing on this network's potential fork, where it was
        // not freshly deployed. This is a safety measure to prevent replay attacks on the forked
        // network.
        require(evmChain() == block.chainid, "invalid evm chain");

        // Verify the VAA and mint tokens. Set the deposit struct with WormholeCctpTokenMessenger's
        // return values.
        IWormhole.VM memory vaa;
        (
            vaa,
            deposit.token,
            deposit.amount,
            deposit.sourceDomain,
            deposit.targetDomain,
            deposit.nonce,
            deposit.fromAddress,
            deposit.mintRecipient,
            deposit.payload
        ) = verifyVaaAndMintLegacy(
            params.encodedCctpMessage, params.cctpAttestation, params.encodedVaa
        );

        // Confirm that the caller is the `mintRecipient` to ensure atomic execution.
        require(
            msg.sender.toUniversalAddress() == deposit.mintRecipient, "caller must be mintRecipient"
        );

        // If this VAA does not come from a registered Wormhole Circle Integration contract, revert.
        requireEmitterLegacy(vaa, getRegisteredEmitters()[vaa.emitterChainId]);

        mapping(bytes32 => bool) storage consumedVaas = getConsumedVaas();

        // Revert if this message has been consumed already. This check is meant to prevent replay
        // attacks, but it may not be necessary because the CCTP Message Transmitter already keeps
        // track of used nonces.
        require(!consumedVaas[vaa.hash], "message already consumed");

        // Mark as consumed.
        consumedVaas[vaa.hash] = true;

        // Emit Redeemed event.
        emit Redeemed(vaa.emitterChainId, vaa.emitterAddress, vaa.sequence);
    }

    // getters

    /// @inheritdoc ICircleIntegration
    function fetchLocalTokenAddress(uint32 remoteDomain, bytes32 remoteToken)
        public
        view
        returns (bytes32)
    {
        return fetchLocalToken(remoteDomain, remoteToken);
    }

    /// @inheritdoc ICircleIntegration
    function addressToBytes32(address evmAddr) public pure returns (bytes32 converted) {
        converted = evmAddr.toUniversalAddress();
    }

    /// @inheritdoc ICircleIntegration
    function decodeDepositWithPayload(bytes memory encoded)
        public
        pure
        returns (DepositWithPayload memory deposit)
    {
        // This is a hack to get around using the decodeDeposit method. This is not a real VM
        // obviously.
        //
        // Plus, this getter should never be used in practice.
        IWormhole.VM memory fakeVaa;
        fakeVaa.payload = encoded;
        (
            deposit.token,
            deposit.amount,
            deposit.sourceDomain,
            deposit.targetDomain,
            deposit.nonce,
            deposit.fromAddress,
            deposit.mintRecipient,
            deposit.payload
        ) = fakeVaa.decodeDeposit();
    }

    /// @inheritdoc ICircleIntegration
    function encodeDepositWithPayload(DepositWithPayload memory message)
        public
        pure
        returns (bytes memory encoded)
    {
        encoded = message.token.encodeDeposit(
            message.amount,
            message.sourceDomain,
            message.targetDomain,
            message.nonce,
            message.fromAddress,
            message.mintRecipient,
            message.payload
        );
    }

    /// @inheritdoc ICircleIntegration
    function isInitialized(address impl) public view returns (bool) {
        return getInitializedImplementations()[impl];
    }

    /// @inheritdoc ICircleIntegration
    function wormhole() public view returns (IWormhole) {
        return _wormhole;
    }

    /// @inheritdoc ICircleIntegration
    function chainId() public view returns (uint16) {
        return _chainId;
    }

    /// @inheritdoc ICircleIntegration
    function wormholeFinality() public pure returns (uint8) {
        return _MESSAGE_FINALITY;
    }

    /// @inheritdoc ICircleIntegration
    function circleBridge() public view returns (ITokenMessenger) {
        return _tokenMessenger;
    }

    /// @inheritdoc ICircleIntegration
    function circleTokenMinter() public view returns (ITokenMinter) {
        return _tokenMinter;
    }

    /// @inheritdoc ICircleIntegration
    function circleTransmitter() public view returns (IMessageTransmitter) {
        return _messageTransmitter;
    }

    /// @inheritdoc ICircleIntegration
    function getRegisteredEmitter(uint16 chain) public view returns (bytes32) {
        return getRegisteredEmitters()[chain];
    }

    /// @inheritdoc ICircleIntegration
    function isAcceptedToken(address token) public view returns (bool) {
        return _tokenMinter.burnLimitsPerMessage(token) > 0;
    }

    /// @inheritdoc ICircleIntegration
    function getDomainFromChainId(uint16 chain) public view returns (uint32) {
        return getChainToDomain()[chain];
    }

    /// @inheritdoc ICircleIntegration
    function getChainIdFromDomain(uint32 cctpDomain) public view returns (uint16) {
        return getDomainToChain()[cctpDomain];
    }

    /// @inheritdoc ICircleIntegration
    function isMessageConsumed(bytes32 vaaHash) public view returns (bool) {
        return getConsumedVaas()[vaaHash];
    }

    /// @inheritdoc ICircleIntegration
    function localDomain() public view returns (uint32) {
        return _localCctpDomain;
    }

    /// @inheritdoc ICircleIntegration
    function evmChain() public view returns (uint256) {
        return _evmChain;
    }
}
