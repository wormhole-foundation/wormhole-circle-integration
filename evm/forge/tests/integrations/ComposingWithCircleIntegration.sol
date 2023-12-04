// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ICircleIntegration} from "src/interfaces/ICircleIntegration.sol";
import {IWormhole} from "src/interfaces/IWormhole.sol";

import {Utils} from "src/libraries/Utils.sol";

contract ComposingWithCircleIntegration {
    using SafeERC20 for IERC20;
    using Utils for address;

    uint32 constant _MY_BFF_DOMAIN = 1;
    bytes32 constant _MY_BFF_ADDR =
        0x000000000000000000000000deadbeefdeadbeefdeadbeefdeadbeefdeadbeef;

    ICircleIntegration immutable _circleIntegration;
    address immutable _usdcAddress;

    constructor(address circleIntegration, address usdcAddress) {
        _circleIntegration = ICircleIntegration(circleIntegration);
        _usdcAddress = usdcAddress;

        // YOLO.
        IERC20(_usdcAddress).forceApprove(address(_circleIntegration), 2 ** 256 - 1);
    }

    function transferUsdc(
        uint16 targetChain,
        uint256 amount,
        bytes32 mintRecipient,
        bytes calldata payload
    ) public payable returns (uint64 wormholeSequence) {
        IERC20(_usdcAddress).safeTransferFrom(msg.sender, address(this), amount);

        wormholeSequence = _circleIntegration.transferTokensWithPayload{value: msg.value}(
            ICircleIntegration.TransferParameters({
                token: _usdcAddress,
                amount: amount,
                targetChain: targetChain,
                mintRecipient: mintRecipient
            }),
            0, // wormholeNonce
            payload
        );
    }

    function redeemUsdc(ICircleIntegration.RedeemParameters calldata params) public {
        ICircleIntegration.DepositWithPayload memory deposit =
            _circleIntegration.redeemTokensWithPayload(params);

        IERC20(_usdcAddress).safeTransfer(msg.sender, deposit.amount);
    }

    function myBffDomain() public pure returns (uint32 domain) {
        domain = _MY_BFF_DOMAIN;
    }

    function myBffAddr() public pure returns (bytes32 addr) {
        addr = _MY_BFF_ADDR;
    }
}
