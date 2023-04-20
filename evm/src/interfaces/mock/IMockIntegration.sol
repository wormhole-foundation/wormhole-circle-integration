// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.19;

import { ICircleIntegration } from "../ICircleIntegration.sol";

interface IMockIntegration {
    function owner() external view returns (address);
    function trustedSender() external view returns (address);
    function trustedChainId() external view returns (uint16);
    function redemptionSequence() external view returns (uint256);
    function circleIntegration() external view returns (ICircleIntegration);

    function redeemTokensWithPayload(
        ICircleIntegration.RedeemParameters memory redeemParams,
        address transferRecipient
    ) external returns (uint256);

    function getPayload(uint256 redemptionSequence_) external view returns (bytes memory);

    function setup(
        address circleIntegrationAddress,
        address trustedRecipient_,
        uint16 trustedChainId_
    ) external;
}
