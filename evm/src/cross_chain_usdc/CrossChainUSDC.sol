// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../libraries/BytesLib.sol";

import {IWormhole} from "../interfaces/IWormhole.sol";

import "./CrossChainUSDCGovernance.sol";
import "./CrossChainUSDCMessages.sol";

contract CrossChainUSDC is CrossChainUSDCMessages, CrossChainUSDCGovernance, ReentrancyGuard {
    using BytesLib for bytes;

    function transferTokens(
        address token,
        uint256 amount,
        uint16 toChain,
        bytes32 mintRecipient
    ) public payable nonReentrant returns (uint64 messageSequence) {
        // sanity check user input
        require(amount > 0, "amount must be > 0");
        require(toChain > 0, "invalid to chainId");
        require(mintRecipient != bytes32(0), "invalid mint recipient");

        // take custody of tokens
        _custodyTokens(token, amount);

        // cache wormhole instance and fees to save on gas
        IWormhole wormhole = wormhole();
        uint256 wormholeFee = wormhole.messageFee();

        // Confirm that the caller has sent enough ether to pay for the wormhole
        // message fee.
        require(msg.value == wormholeFee, "insufficient value");

        // cache Circle Bridge instance
        ICircleBridge circleBridge = circleBridge();

        // approve the USDC Bridge to spend tokens
        SafeERC20.safeApprove(
            IERC20(token),
            address(circleBridge),
            amount
        );

        // cache toChain information to save gas
        uint32 targetChainDomain = getChainDomain(toChain);
        bytes32 targetContract = getRegisteredEmitter(toChain);

        // burn USDC on the bridge
        uint64 nonce = circleBridge.depositForBurnWithCaller(
            amount,
            targetChainDomain,
            mintRecipient,
            token,
            targetContract
        );

        // encode depositForBurn message
        bytes memory encodedMessage = encodeWormholeDepositForBurnMessage(
            WormholeDepositForBurn({
                payloadId: uint8(1),
                sourceDomain: getChainDomain(chainId()),
                targetDomain: targetChainDomain,
                nonce: nonce,
                sender: addressToBytes32(address(this)),
                mintRecipient: mintRecipient
            })
        );

        // send the DepositForBurn wormhole message
        messageSequence = wormhole.publishMessage{value : wormholeFee}(
            0, // messageId, set to zero to opt out of batching
            encodedMessage,
            wormholeFinality()
        );
    }

    function redeemTokens(RedeemParameters memory params) public {
        // parse and verify the Wormhole core message
        (
            IWormhole.VM memory verifiedMessage,
            bool valid,
            string memory reason
        ) = wormhole().parseAndVerifyVM(params.encodedWormholeMessage);

        // confirm that the core layer verified the message
        require(valid, reason);

        // verify that this message was emitted by a trusted contract
        require(verifyEmitter(verifiedMessage), "unknown emitter");

         // revert if this message has been consumed already
        require(!isMessageConsumed(verifiedMessage.hash), "message already consumed");
        consumeMessage(verifiedMessage.hash);

        // decode the message payload into the DepositForBurn struct
        WormholeDepositForBurn memory wormholePayload = decodeWormholeDepositForBurnMessage(
            verifiedMessage.payload
        );

        // parse the circle bridge message
        CircleDepositForBurn memory circlePayload = decodeCircleDepositForBurnMessage(
            params.circleBridgeMessage
        );

        // confirm that the caller passed the correct message pair
        require(verifyCircleMessage(wormholePayload, circlePayload), "invalid message pair");

        // call the circle bridge to mint tokens to the recipient
        bool success = circleTransmitter().receiveMessage(
            params.circleBridgeMessage,
            params.circleAttestation
        );
        require(success, "failed to mint USDC");
    }

    function _custodyTokens(address token, uint256 amount) internal {
        /// query own token balance before transfer
        (,bytes memory queriedBalanceBefore) = token.staticcall(
            abi.encodeWithSelector(IERC20.balanceOf.selector,
            address(this))
        );
        uint256 balanceBefore = abi.decode(queriedBalanceBefore, (uint256));

        /// deposit USDC/EUROC
        SafeERC20.safeTransferFrom(
            IERC20(token),
            msg.sender,
            address(this),
            amount
        );

        /// query own token balance after transfer
        (,bytes memory queriedBalanceAfter) = token.staticcall(
            abi.encodeWithSelector(IERC20.balanceOf.selector,
            address(this))
        );
        uint256 balanceAfter = abi.decode(queriedBalanceAfter, (uint256));

        // This check is necessary until circle publishes the source code
        // for the USDC Bridge.
        require(
            amount == balanceAfter - balanceBefore,
            "USDC doesn't charge fees :/"
        );
    }

    function verifyEmitter(IWormhole.VM memory vm) internal view returns (bool) {
        // verify that the sender of the wormhole message is a trusted
        return (getRegisteredEmitter(vm.emitterChainId) == vm.emitterAddress);
    }

    function verifyCircleMessage(
        WormholeDepositForBurn memory wormhole,
        CircleDepositForBurn memory circle
    ) internal pure returns (bool) {
        return (
            wormhole.sourceDomain == circle.sourceDomain &&
            wormhole.targetDomain == circle.targetDomain &&
            wormhole.nonce == circle.nonce &&
            wormhole.sender == circle.sender &&
            wormhole.mintRecipient == circle.mintRecipient
        );
    }

    function addressToBytes32(address address_) public pure returns (bytes32) {
        return bytes32(uint256(uint160(address_)));
    }
}