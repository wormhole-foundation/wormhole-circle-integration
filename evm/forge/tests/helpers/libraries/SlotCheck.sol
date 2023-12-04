// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.19;

import {Vm} from "forge-std/Vm.sol";

library SlotCheck {
    address constant VM_ADDRESS = address(bytes20(uint160(uint256(keccak256("hevm cheat code")))));
    Vm constant vm = Vm(VM_ADDRESS);

    function slotValueEquals(address contractAddr, uint256 slot, bool expected)
        internal
        view
        returns (bool agrees)
    {
        agrees = slotValueEquals(contractAddr, bytes32(slot), expected);
    }

    function slotValueEquals(address contractAddr, uint256 slot, uint256 expected)
        internal
        view
        returns (bool agrees)
    {
        agrees = slotValueEquals(contractAddr, bytes32(slot), expected);
    }

    function slotValueEquals(address contractAddr, uint256 slot, address expected)
        internal
        view
        returns (bool agrees)
    {
        agrees = slotValueEquals(contractAddr, bytes32(slot), expected);
    }

    function slotValueEquals(address contractAddr, uint256 slot, bytes32 expected)
        internal
        view
        returns (bool agrees)
    {
        agrees = slotValueEquals(contractAddr, bytes32(slot), expected);
    }

    function slotValueEquals(address contractAddr, bytes32 slot, bool expected)
        internal
        view
        returns (bool agrees)
    {
        agrees = slotValueEquals(contractAddr, slot, uint256(expected ? 1 : 0));
    }

    function slotValueEquals(address contractAddr, bytes32 slot, uint256 expected)
        internal
        view
        returns (bool agrees)
    {
        agrees = slotValueEquals(contractAddr, slot, bytes32(expected));
    }

    function slotValueEquals(address contractAddr, bytes32 slot, address expected)
        internal
        view
        returns (bool agrees)
    {
        agrees = slotValueEquals(contractAddr, slot, bytes32(uint256(uint160(expected))));
    }

    function slotValueEquals(address contractAddr, bytes32 slot, bytes32 expected)
        internal
        view
        returns (bool agrees)
    {
        agrees = vm.load(contractAddr, slot) == expected;
    }

    function slotValueZero(address contractAddr, uint256 slot)
        internal
        view
        returns (bool agrees)
    {
        agrees = slotValueZero(contractAddr, bytes32(slot));
    }

    function slotValueZero(address contractAddr, bytes32 slot)
        internal
        view
        returns (bool agrees)
    {
        agrees = slotValueEquals(contractAddr, slot, bytes32(0));
    }
}
