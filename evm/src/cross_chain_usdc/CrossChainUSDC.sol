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
        bytes memory encodedMessage = encodeDepositForBurnMessage(
            DepositForBurn({
                payloadId: uint8(1),
                token: addressToBytes32(token),
                amount: amount,
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
        if (getRegisteredEmitter(vm.emitterChainId) == vm.emitterAddress) {
            return true;
        }

        return false;
    }

    function addressToBytes32(address address_) public pure returns (bytes32) {
        return bytes32(uint256(uint160(address_)));
    }
}
