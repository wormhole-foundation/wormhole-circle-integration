// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Vm} from "forge-std/Vm.sol";

import {IUSDC} from "../IUSDC.sol";

library UsdcDeal {
    address constant VM_ADDRESS = address(bytes20(uint160(uint256(keccak256("hevm cheat code")))));
    Vm constant vm = Vm(VM_ADDRESS);

    function dealAndApprove(address usdcAddress, address to, uint256 amount) internal {
        IUSDC usdc = IUSDC(usdcAddress);
        vm.prank(usdc.masterMinter());
        usdc.configureMinter(address(this), amount);
        usdc.mint(address(this), amount);
        IERC20(usdcAddress).approve(to, amount);
    }
}
