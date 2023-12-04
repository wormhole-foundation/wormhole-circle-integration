// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.19;

library Utils {
    error AddressOverflow(bytes32 addr);

    function toUniversalAddress(address evmAddr) internal pure returns (bytes32 converted) {
        assembly ("memory-safe") {
            converted := and(0xffffffffffffffffffffffffffffffffffffffff, evmAddr)
        }
    }

    function fromUniversalAddress(bytes32 universalAddr)
        internal
        pure
        returns (address converted)
    {
        if (bytes12(universalAddr) != 0) {
            revert AddressOverflow(universalAddr);
        }

        assembly ("memory-safe") {
            converted := universalAddr
        }
    }

    function revertBuiltIn(string memory reason) internal pure {
        // NOTE: Using require is the easy way to revert with the built-in Error type.
        require(false, reason);
    }
}
