// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.13;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IWormhole} from "wormhole/interfaces/IWormhole.sol";
import {BytesLib} from "wormhole/libraries/external/BytesLib.sol";

import {ICircleBridge} from "../interfaces/circle/ICircleBridge.sol";

import {CircleIntegrationGovernance} from "./CircleIntegrationGovernance.sol";
import {CircleIntegrationMessages} from "./CircleIntegrationMessages.sol";

/// @notice These contracts burn and mint USDC by using Circle's Cross-Chain Transfer Protocol allowing
/// for seemless cross-chain USDC transfers. They also emit Wormhole messages that contain instructions
/// describing what to do with the USDC on the target chain.
contract CircleIntegration is CircleIntegrationMessages, CircleIntegrationGovernance, ReentrancyGuard {
    using BytesLib for bytes;

    /// @dev `transferTokensWithPayload` calls the Circle Bridge contract to burn USDC. It emits
    /// a Wormhole message containing a user-specified payload with instructions for what to do with
    /// the USDC once it has been minted on the target chain.
    function transferTokensWithPayload(TransferParameters memory transferParams, uint32 batchId, bytes memory payload)
        public
        payable
        nonReentrant
        returns (uint64 messageSequence)
    {
        // cache wormhole instance and fees to save on gas
        IWormhole wormhole = wormhole();
        uint256 wormholeFee = wormhole.messageFee();

        // Confirm that the caller has sent enough ether to pay for the wormhole
        // message fee.
        require(msg.value == wormholeFee, "insufficient value");

        // Call the circle bridge and depositForBurn. The mintRecipient
        // should be the target contract composing on this USDC integration.
        (bytes32 targetToken, uint64 nonce, uint256 amountReceived) = _transferTokens(
            transferParams.token, transferParams.amount, transferParams.targetChain, transferParams.mintRecipient
        );

        // encode depositForBurn message
        bytes memory encodedMessage = encodeDepositWithPayload(
            DepositWithPayload({
                token: targetToken,
                amount: amountReceived,
                sourceDomain: localDomain(),
                targetDomain: getDomainFromChainId(transferParams.targetChain),
                nonce: nonce,
                fromAddress: addressToBytes32(msg.sender),
                mintRecipient: transferParams.mintRecipient,
                payload: payload
            })
        );

        // send the DepositForBurn wormhole message
        messageSequence = wormhole.publishMessage{value: wormholeFee}(batchId, encodedMessage, wormholeFinality());
    }

    function _transferTokens(address token, uint256 amount, uint16 targetChain, bytes32 mintRecipient)
        internal
        returns (bytes32 targetToken, uint64 nonce, uint256 amountReceived)
    {
        // sanity check user input
        require(amount > 0, "amount must be > 0");
        require(mintRecipient != bytes32(0), "invalid mint recipient");
        require(isAcceptedToken(token), "token not accepted");
        require(getRegisteredEmitter(targetChain) != bytes32(0), "target contract not registered");

        targetToken = targetAcceptedToken(token, targetChain);
        require(targetToken != bytes32(0), "target token not registered");

        // take custody of tokens
        amountReceived = custodyTokens(token, amount);

        // cache Circle Bridge instance
        ICircleBridge circleBridge = circleBridge();

        // approve the USDC Bridge to spend tokens
        SafeERC20.safeApprove(IERC20(token), address(circleBridge), amountReceived);

        // burn USDC on the bridge
        nonce = circleBridge.depositForBurnWithCaller(
            amountReceived, getDomainFromChainId(targetChain), mintRecipient, token, getRegisteredEmitter(targetChain)
        );
    }

    function custodyTokens(address token, uint256 amount) internal returns (uint256) {
        // query own token balance before transfer
        (, bytes memory queriedBalanceBefore) =
            token.staticcall(abi.encodeWithSelector(IERC20.balanceOf.selector, address(this)));
        uint256 balanceBefore = abi.decode(queriedBalanceBefore, (uint256));

        // deposit USDC
        SafeERC20.safeTransferFrom(IERC20(token), msg.sender, address(this), amount);

        // query own token balance after transfer
        (, bytes memory queriedBalanceAfter) =
            token.staticcall(abi.encodeWithSelector(IERC20.balanceOf.selector, address(this)));
        uint256 balanceAfter = abi.decode(queriedBalanceAfter, (uint256));

        return balanceAfter - balanceBefore;
    }

    /// @dev `redeemTokensWithPayload` verifies the Wormhole message from the source chain and
    /// verifies that the passed Circle Bridge message is valid. It calls the Circle Bridge
    /// contract by passing the Circle message and attestation to mint tokens to
    /// the specified mint recipient. It also verifies that the caller is the specified mint
    /// recipient to ensure atomic execution of the additional instructions in the Wormhole message.
    function redeemTokensWithPayload(RedeemParameters memory params)
        public
        returns (DepositWithPayload memory depositInfo)
    {
        // verify the wormhole message
        IWormhole.VM memory verifiedMessage = verifyWormholeRedeemMessage(params.encodedWormholeMessage);

        // decode the message payload into the WormholeDeposit struct
        depositInfo = decodeDepositWithPayload(verifiedMessage.payload);

        // confirm that the caller is the mint recipient to ensure atomic execution
        require(addressToBytes32(msg.sender) == depositInfo.mintRecipient, "caller must be mintRecipient");

        // confirm that the caller passed the correct message pair
        require(
            verifyCircleMessage(
                params.circleBridgeMessage, depositInfo.sourceDomain, depositInfo.targetDomain, depositInfo.nonce
            ),
            "invalid message pair"
        );

        // call the circle bridge to mint tokens to the recipient
        bool success = circleTransmitter().receiveMessage(params.circleBridgeMessage, params.circleAttestation);
        require(success, "failed to mint USDC");
    }

    function verifyWormholeRedeemMessage(bytes memory encodedMessage) internal returns (IWormhole.VM memory) {
        require(evmChain() == block.chainid, "invalid evm chain");

        // parse and verify the Wormhole core message
        (IWormhole.VM memory verifiedMessage, bool valid, string memory reason) =
            wormhole().parseAndVerifyVM(encodedMessage);

        // confirm that the core layer verified the message
        require(valid, reason);

        // verify that this message was emitted by a trusted contract
        require(verifyEmitter(verifiedMessage), "unknown emitter");

        // revert if this message has been consumed already
        require(!isMessageConsumed(verifiedMessage.hash), "message already consumed");
        consumeMessage(verifiedMessage.hash);

        return verifiedMessage;
    }

    function verifyEmitter(IWormhole.VM memory vm) internal view returns (bool) {
        // verify that the sender of the wormhole message is a trusted
        return (getRegisteredEmitter(vm.emitterChainId) == vm.emitterAddress);
    }

    function verifyCircleMessage(bytes memory circleMessage, uint32 sourceDomain, uint32 targetDomain, uint64 nonce)
        internal
        pure
        returns (bool)
    {
        // parse the circle bridge message
        uint32 circleSourceDomain = circleMessage.toUint32(4);
        uint32 circleTargetDomain = circleMessage.toUint32(8);
        uint64 circleNonce = circleMessage.toUint64(12);

        return (sourceDomain == circleSourceDomain && targetDomain == circleTargetDomain && nonce == circleNonce);
    }

    function addressToBytes32(address address_) public pure returns (bytes32) {
        return bytes32(uint256(uint160(address_)));
    }
}
