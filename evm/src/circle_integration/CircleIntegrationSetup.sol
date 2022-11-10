// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.0;

import {ERC1967Upgrade} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Upgrade.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {IWormhole} from "wormhole/interfaces/IWormhole.sol";
import {ICircleBridge} from "../interfaces/circle/ICircleBridge.sol";
import {IMessageTransmitter} from "../interfaces/circle/IMessageTransmitter.sol";

import {CircleIntegrationSetters} from "./CircleIntegrationSetters.sol";

contract CircleIntegrationSetup is CircleIntegrationSetters, ERC1967Upgrade, Context {
    function setup(
        address implementation,
        address wormholeAddress,
        uint8 finality,
        address circleBridgeAddress,
        uint16 governanceChainId,
        bytes32 governanceContract
    ) public {
        require(implementation != address(0), "invalid implementation");
        require(wormholeAddress != address(0), "invalid wormhole address");
        require(circleBridgeAddress != address(0), "invalid circle bridge address");

        setWormhole(wormholeAddress);
        setChainId(IWormhole(wormholeAddress).chainId());
        setWormholeFinality(finality);
        setCircleBridge(circleBridgeAddress);
        setGovernance(governanceChainId, governanceContract);

        IMessageTransmitter messageTransmitter = ICircleBridge(circleBridgeAddress).localMessageTransmitter();
        setCircleTransmitter(address(messageTransmitter));
        setLocalDomain(messageTransmitter.localDomain());

        // set the implementation
        _upgradeTo(implementation);

        // call initialize function of the new implementation
        (bool success, bytes memory reason) = implementation.delegatecall(abi.encodeWithSignature("initialize()"));
        require(success, string(reason));
    }
}
