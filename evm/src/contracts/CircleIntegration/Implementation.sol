// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.19;

import {ERC1967Upgrade} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Upgrade.sol";

import {Logic} from "./Logic.sol";
import {State} from "./State.sol";
import {getInitializedImplementations} from "./Storage.sol";

contract Implementation is Logic {
    constructor(address wormhole, address cctpTokenMessenger) State(wormhole, cctpTokenMessenger) {}

    function initialize() public virtual initializer {
        // This function needs to be exposed for an upgrade to pass. Any additional logic can be
        // placed here.

        // WARNING: This snippet should be removed for any following contract upgrades
        // We are using the below snippet to reset storage slots that are no longer being used
        // for safety and to free them up for future use. We don't want to inadvertantly wipe
        // the same slots on future upgrades. See Storage.sol for reasoning.
        assembly ("memory-safe") {
            sstore(0x0, 0x0)
            sstore(0x1, 0x0)
            sstore(0x2, 0x0)
            sstore(0x3, 0x0)
            sstore(0x4, 0x0)
            sstore(0xA, 0x0)
        }
    }

    modifier initializer() {
        address impl = ERC1967Upgrade._getImplementation();

        mapping(address => bool) storage initialized = getInitializedImplementations();

        // NOTE: Reverting with Error(string) comes from the old implementation, so we preserve it.
        require(!initialized[impl], "already initialized");

        // Mark implementation as initialized.
        initialized[impl] = true;

        _;
    }

    function circleIntegrationImplementation() public pure returns (bytes32) {
        return keccak256("circleIntegrationImplementation()");
    }
}
