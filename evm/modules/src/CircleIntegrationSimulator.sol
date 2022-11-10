// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IWormhole} from "wormhole/interfaces/IWormhole.sol";
import {BytesLib} from "wormhole/libraries/external/BytesLib.sol";

import {CircleIntegrationMessages} from "../../src/circle_integration/CircleIntegrationMessages.sol";
import {CircleIntegrationSetup} from "../../src/circle_integration/CircleIntegrationSetup.sol";
import {CircleIntegrationImplementation} from "../../src/circle_integration/CircleIntegrationImplementation.sol";
import {CircleIntegrationProxy} from "../../src/circle_integration/CircleIntegrationProxy.sol";

import {ICircleIntegration} from "../../src/interfaces/ICircleIntegration.sol";
import {ICircleBridge} from "../../src/interfaces/circle/ICircleBridge.sol";
import {IMessageTransmitter} from "../../src/interfaces/circle/IMessageTransmitter.sol";

import "forge-std/Vm.sol";
import "forge-std/console.sol";

contract CircleIntegrationSimulator is CircleIntegrationMessages {
    using BytesLib for bytes;

    // Taken from forge-std/Script.sol
    address private constant VM_ADDRESS = address(bytes20(uint160(uint256(keccak256("hevm cheat code")))));
    Vm public constant vm = Vm(VM_ADDRESS);

    // Allow access to Wormhole
    ICircleIntegration public circleIntegration;

    // Save the guardian PK to sign messages with
    uint256 private messageAttesterPK;
    address public messageAttester;

    // Circle
    ICircleBridge circleBridge;

    constructor(address wormhole_, address circleBridge_, uint256 messageAttester_) {
        circleBridge = ICircleBridge(circleBridge_);

        circleIntegration = deployCircleIntegration(wormhole_);
        messageAttesterPK = messageAttester_;
        messageAttester = vm.addr(messageAttesterPK);

        setupMessageTransmitter();
    }

    function setupMessageTransmitter() internal {
        IMessageTransmitter messageTransmitter = circleBridge.localMessageTransmitter();

        vm.prank(messageTransmitter.attesterManager());
        messageTransmitter.enableAttester(messageAttester);

        vm.prank(messageTransmitter.attesterManager());
        address oldAttester = messageTransmitter.getEnabledAttester(0);
        require(messageTransmitter.isEnabledAttester(messageAttester), "enableAttester failed");

        vm.prank(messageTransmitter.attesterManager());
        messageTransmitter.disableAttester(oldAttester);
    }

    function findMessageSentInLogs(Vm.Log[] memory entries) public pure returns (bytes memory) {
        uint256 numEntries = entries.length;
        for (uint256 i = 0; i < numEntries;) {
            if (entries[i].topics[0] == keccak256("MessageSent(bytes)")) {
                return abi.decode(entries[i].data, (bytes));
            }
            unchecked {
                i += 1;
            }
        }
        revert("MessageSent not found");
    }

    function attestMessage(bytes memory message) public returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(messageAttesterPK, keccak256(message));
        return abi.encodePacked(r, s, v);
    }

    function deployCircleIntegration(address wormhole_) internal returns (ICircleIntegration) {
        // deploy Setup
        CircleIntegrationSetup setup = new CircleIntegrationSetup();

        // deploy Implementation
        CircleIntegrationImplementation implementation = new CircleIntegrationImplementation();

        // deploy Proxy
        CircleIntegrationProxy proxy = new CircleIntegrationProxy(
            address(setup),
            abi.encodeWithSelector(
                bytes4(keccak256("setup(address,address,uint8,address,uint16,bytes32)")),
                address(implementation),
                wormhole_,
                uint8(1), // finality
                address(circleBridge),
                uint16(1),
                bytes32(0x0000000000000000000000000000000000000000000000000000000000000004)
            )
        );

        return ICircleIntegration(address(proxy));
    }
}
