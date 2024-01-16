// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.19;

import {WormholeCctpTokenMessenger} from "src/contracts/WormholeCctpTokenMessenger.sol";

abstract contract State is WormholeCctpTokenMessenger {
    uint256 immutable _evmChain;

    constructor(address wormhole, address cctpTokenMessenger)
        WormholeCctpTokenMessenger(wormhole, cctpTokenMessenger)
    {
        _evmChain = block.chainid;
    }
}
