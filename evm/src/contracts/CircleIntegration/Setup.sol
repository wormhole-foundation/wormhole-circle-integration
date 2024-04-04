// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.19;

import {ERC1967Upgrade} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Upgrade.sol";

contract Setup is ERC1967Upgrade {
    function setup(address implementation) public {
        require(implementation != address(0), "invalid implementation");

        // set the implementation
        _upgradeTo(implementation);

        // call initialize function of the new implementation
        (bool success, bytes memory reason) =
            implementation.delegatecall(abi.encodeWithSignature("initialize()"));
        require(success, string(reason));
    }
}
