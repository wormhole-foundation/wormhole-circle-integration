// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IWormhole} from "src/interfaces/IWormhole.sol";

import {Utils} from "src/libraries/Utils.sol";

import {WormholeCctpTokenMessenger} from "src/contracts/WormholeCctpTokenMessenger.sol";

contract InheritingWormholeCctp is WormholeCctpTokenMessenger {
    using Utils for address;
    using SafeERC20 for IERC20;

    uint32 constant _MY_BFF_DOMAIN = 1;
    bytes32 constant _MY_BFF_ADDR =
        0x000000000000000000000000deadbeefdeadbeefdeadbeefdeadbeefdeadbeef;

    address immutable _usdcAddress;

    constructor(address wormhole, address cctpTokenMessenger, address usdcAddress)
        WormholeCctpTokenMessenger(wormhole, cctpTokenMessenger)
    {
        _usdcAddress = usdcAddress;

        // YOLO.
        setTokenMessengerApproval(_usdcAddress, 2 ** 256 - 1);
    }

    function transferUsdc(uint256 amount, bytes32 mintRecipient, bytes calldata payload)
        public
        payable
        returns (uint64 wormholeSequence)
    {
        // Deposit tokens into this contract to prepare for burning.
        IERC20(_usdcAddress).safeTransferFrom(msg.sender, address(this), amount);

        (wormholeSequence,) = burnAndPublish(
            _MY_BFF_ADDR,
            _MY_BFF_DOMAIN,
            _usdcAddress,
            amount,
            mintRecipient,
            0, // wormholeNonce
            payload,
            msg.value
        );
    }

    function redeemUsdc(
        bytes calldata encodedCctpMessage,
        bytes calldata cctpAttestation,
        bytes calldata encodedVaa
    ) public {
        verifyVaaAndMint(encodedCctpMessage, cctpAttestation, encodedVaa);
    }

    function myBffDomain() public pure returns (uint32 domain) {
        domain = _MY_BFF_DOMAIN;
    }

    function myBffAddr() public pure returns (bytes32 addr) {
        addr = _MY_BFF_ADDR;
    }
}
