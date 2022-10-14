// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Upgrade.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";

import "./CrossChainUSDCSetters.sol";

contract CrossChainUSDCSetup is CrossChainUSDCSetters, ERC1967Upgrade, Context {
    function setup(
        address implementation,
        uint16 chainId,
        address wormhole,
        uint8 finality,
        address circleBridgeAddress,
        address circleTransmitterAddress
    ) public {
        require(implementation != address(0), "invalid implementation");
        require(chainId > 0, "invalid chainId");
        require(wormhole != address(0), "invalid wormhole address");
        require(circleBridgeAddress != address(0), "invalid circle bridge address");
        require(circleTransmitterAddress != address(0), "invalid circle transmitter address");

        setOwner(_msgSender());
        setChainId(chainId);
        setWormhole(wormhole);
        setWormholeFinality(finality);
        setCircleBridge(circleBridgeAddress);
        setCircleTransmitter(circleTransmitterAddress);

        // set the implementation
        _upgradeTo(implementation);

        // call initialize function of the new implementation
        (bool success, bytes memory reason) = implementation.delegatecall(abi.encodeWithSignature("initialize()"));
        require(success, string(reason));
    }
}