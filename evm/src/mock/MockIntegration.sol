// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.13;

import {IWormhole} from "wormhole/interfaces/IWormhole.sol";
import {ICircleIntegration} from "../interfaces/ICircleIntegration.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockIntegration {
    // owner address
    address public owner;

    // trusted sender address
    address public trustedSender;

    // trusted Wormhole chainId
    uint16 public trustedChainId;

    // redemption sequence
    uint256 public redemptionSequence;

    // payload mapping
    mapping(uint256 => bytes) payloadMap;

    // Wormhole's CircleIntegration instance
    ICircleIntegration public circleIntegration;

    // save the deployer's address in the `owner` state variable
    constructor() {
        owner = msg.sender;
    }

    function redeemTokensWithPayload(
        ICircleIntegration.RedeemParameters memory redeemParams,
        address transferRecipient
    ) public returns (uint256) {
        // mint USDC to this contract
        ICircleIntegration.DepositWithPayload memory deposit =
            circleIntegration.redeemTokensWithPayload(redeemParams);

        // verify that the sender is the trustedSender
        require(
            msg.sender == trustedSender &&
            circleIntegration.getChainIdFromDomain(deposit.sourceDomain) == trustedChainId,
            "invalid sender"
        );

        // uptick sequence
        redemptionSequence += 1;

        // save the payload
        payloadMap[redemptionSequence] = deposit.payload;

        // send the tokens to the transferRecipient address
        SafeERC20.safeTransfer(
            IERC20(address(uint160(uint256(deposit.token)))),
            transferRecipient,
            deposit.amount
        );

        return redemptionSequence;
    }

    function getPayload(uint256 redemptionSequence_) public view returns (bytes memory) {
        return payloadMap[redemptionSequence_];
    }

    function setup(
        address circleIntegrationAddress,
        address trustedSender_,
        uint16 trustedChainId_
    ) public onlyOwner {
        // create contract interfaces and store `trustedSender` address
        circleIntegration = ICircleIntegration(circleIntegrationAddress);
        trustedSender = trustedSender_;
        trustedChainId = trustedChainId_;
    }

    modifier onlyOwner() {
        require(owner == msg.sender, "caller not the owner");
        _;
    }
}
