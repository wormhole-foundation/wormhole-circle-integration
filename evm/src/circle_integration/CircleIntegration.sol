// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../libraries/BytesLib.sol";

import {IWormhole} from "../interfaces/IWormhole.sol";

import "./CircleIntegrationGovernance.sol";
import "./CircleIntegrationMessages.sol";

/// @notice These contracts burn and mint USDC by using Circle's Cross-Chain Transfer Protocol allowing
/// for seemless cross-chain USDC transfers. They also emit Wormhole messages that contain instructions
/// describing what to do with the USDC on the target chain.
contract CircleIntegration is CircleIntegrationMessages, CircleIntegrationGovernance, ReentrancyGuard {
    using BytesLib for bytes;

    /// @dev `transferTokensWithPayload` calls the Circle Bridge contract to burn USDC. It emits
    /// a Wormhole message containing a user-specified payload with instructions for what to do with
    /// the USDC once it has been minted on the target chain.
    function transferTokensWithPayload(
        address token,
        uint256 amount,
        uint16 targetChain,
        bytes32 mintRecipient,
        bytes memory payload
    ) public payable nonReentrant returns (uint64 messageSequence) {
        // confirm that the token is accepted by the Circle Bridge
        require(isAcceptedToken(token), "token not accepted");

        // cache wormhole instance and fees to save on gas
        IWormhole wormhole = wormhole();
        uint256 wormholeFee = wormhole.messageFee();

        // Confirm that the caller has sent enough ether to pay for the wormhole
        // message fee.
        require(msg.value == wormholeFee, "insufficient value");

        // Call the circle bridge and depositForBurn. The mintRecipient
        // should be the target contract composing on this USDC integration.
        (uint64 nonce, uint256 amountReceived) = _transferTokens(
            token,
            amount,
            targetChain,
            mintRecipient
        );

        // encode depositForBurn message
        bytes memory encodedMessage = encodeWormholeDepositWithPayload(
            WormholeDepositWithPayload({
                payloadId: uint8(1),
                token: addressToBytes32(token),
                amount: amountReceived,
                sourceDomain: getChainDomain(chainId()),
                targetDomain: getChainDomain(targetChain),
                nonce: nonce,
                mintRecipient: mintRecipient,
                payload: payload
            })
        );

        // send the DepositForBurn wormhole message
        messageSequence = wormhole.publishMessage{value : wormholeFee}(
            0, // messageId, set to zero to opt out of batching
            encodedMessage,
            wormholeFinality()
        );
    }

    function _transferTokens(
        address token,
        uint256 amount,
        uint16 targetChain,
        bytes32 mintRecipient
    ) internal returns (uint64 nonce, uint256 amountReceived) {
        // sanity check user input
        require(amount > 0, "amount must be > 0");
        require(targetChain > 0, "invalid to chainId");
        require(mintRecipient != bytes32(0), "invalid mint recipient");

        // take custody of tokens
        amountReceived = custodyTokens(token, amount);

        // cache Circle Bridge instance
        ICircleBridge circleBridge = circleBridge();

        // approve the USDC Bridge to spend tokens
        SafeERC20.safeApprove(
            IERC20(token),
            address(circleBridge),
            amountReceived
        );

        // confirm that the target contract is registered
        require(
            getRegisteredEmitter(targetChain) != bytes32(0),
            "target contract not registered"
        );

        // burn USDC on the bridge
        nonce = circleBridge.depositForBurnWithCaller(
            amountReceived,
            getChainDomain(targetChain),
            mintRecipient,
            token,
            getRegisteredEmitter(targetChain)
        );
    }

    function custodyTokens(address token, uint256 amount) internal returns (uint256) {
        // query own token balance before transfer
        (,bytes memory queriedBalanceBefore) = token.staticcall(
            abi.encodeWithSelector(IERC20.balanceOf.selector,
            address(this))
        );
        uint256 balanceBefore = abi.decode(queriedBalanceBefore, (uint256));

        // deposit USDC
        SafeERC20.safeTransferFrom(
            IERC20(token),
            msg.sender,
            address(this),
            amount
        );

        // query own token balance after transfer
        (,bytes memory queriedBalanceAfter) = token.staticcall(
            abi.encodeWithSelector(IERC20.balanceOf.selector,
            address(this))
        );
        uint256 balanceAfter = abi.decode(queriedBalanceAfter, (uint256));

        return balanceAfter - balanceBefore;
    }

    /// @dev `redeemTokensWithPayload` verifies the Wormhole message from the source chain and
    /// verifies that the passed Circle Bridge message is valid. It calls the Circle Bridge
    /// contract by passing the Circle message and attestation to mint tokens to
    /// the specified mint recipient. It also verifies that the caller is the specified mint
    /// recipient to ensure atomic execution of the additional instructions in the Wormhole message.
    function redeemTokensWithPayload(
        RedeemParameters memory params
    ) public returns (WormholeDepositWithPayload memory wormholeDepositWithPayload) {
        // verify the wormhole message
        IWormhole.VM memory verifiedMessage = verifyWormholeRedeemMessage(
            params.encodedWormholeMessage
        );

        // decode the message payload into the WormholeDeposit struct
        wormholeDepositWithPayload = decodeWormholeDepositWithPayload(
            verifiedMessage.payload
        );

        // confirm that the caller is the mint recipient to ensure atomic execution
        require(
            addressToBytes32(msg.sender) == wormholeDepositWithPayload.mintRecipient,
            "caller must be mintRecipient"
        );

        // parse the circle bridge message
        CircleDeposit memory circleDeposit = decodeCircleDeposit(
            params.circleBridgeMessage
        );

        // confirm that the caller passed the correct message pair
        require(verifyCircleMessage(wormholeDepositWithPayload, circleDeposit), "invalid message pair");

        // call the circle bridge to mint tokens to the recipient
        bool success = circleTransmitter().receiveMessage(
            params.circleBridgeMessage,
            params.circleAttestation
        );
        require(success, "failed to mint USDC");
    }

    function verifyWormholeRedeemMessage(
        bytes memory encodedMessage
    ) internal returns (IWormhole.VM memory) {
        // parse and verify the Wormhole core message
        (
            IWormhole.VM memory verifiedMessage,
            bool valid,
            string memory reason
        ) = wormhole().parseAndVerifyVM(encodedMessage);

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

    function verifyCircleMessage(
        WormholeDepositWithPayload memory wormhole,
        CircleDeposit memory circle
    ) internal pure returns (bool) {
        return (
            wormhole.sourceDomain == circle.sourceDomain &&
            wormhole.targetDomain == circle.targetDomain &&
            wormhole.nonce == circle.nonce
        );
    }

    function addressToBytes32(address address_) public pure returns (bytes32) {
        return bytes32(uint256(uint160(address_)));
    }
}
