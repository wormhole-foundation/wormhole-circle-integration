// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {IWormhole} from "src/interfaces/IWormhole.sol";
import {ICircleIntegration} from "src/interfaces/ICircleIntegration.sol";

import {Utils} from "src/libraries/Utils.sol";

import {Implementation} from "src/contracts/CircleIntegration/Implementation.sol";

import {CircleIntegrationOverride} from "test-helpers/libraries/CircleIntegrationOverride.sol";
import {SlotCheck} from "test-helpers/libraries/SlotCheck.sol";
import {WormholeOverride} from "test-helpers/libraries/WormholeOverride.sol";

contract ForkSlots is Test {
    using CircleIntegrationOverride for *;
    using WormholeOverride for *;
    using Utils for address;
    using SlotCheck for *;

    bytes32 constant GOVERNANCE_MODULE =
        0x000000000000000000000000000000436972636c65496e746567726174696f6e;

    address constant FORKED_CIRCLE_INTEGRATION_ADDRESS = 0x2703483B1a5a7c577e8680de9Df8Be03c6f30e3c;

    ICircleIntegration forked;
    address forkedAddress;

    IWormhole wormhole;

    // Expected at slot 0x0.

    uint16 expectedChainId;
    uint8 expectedWormholeFinality;
    uint32 expectedLocalDomain;
    address expectedWormholeAddress;
    uint16 expectedGovernanceChainId;

    // Expected at slot 0x1.
    bytes32 expectedGovernanceContract;

    // Expected at slot 0x2.
    address expectedCircleBridgeAddress;

    // Expected at slot 0x3.
    address expectedCircleTransmitterAddress;

    // Expected at slot 0x4.
    address expectedCircleTokenMinterAddress;

    // Expected at slot 0xa.
    uint256 expectedEvmChain;

    function setUp() public {
        forked = ICircleIntegration(FORKED_CIRCLE_INTEGRATION_ADDRESS);
        forked.setUpOverride(uint256(vm.envBytes32("TESTING_DEVNET_GUARDIAN")));
        forkedAddress = address(forked);

        wormhole = forked.wormhole();

        // Set expected values.
        expectedChainId = forked.chainId();
        expectedWormholeFinality = forked.wormholeFinality();
        expectedLocalDomain = forked.localDomain();
        expectedWormholeAddress = address(forked.wormhole());
        expectedGovernanceChainId = forked.governanceChainId();
        expectedGovernanceContract = forked.governanceContract();
        expectedCircleBridgeAddress = address(forked.circleBridge());
        expectedCircleTransmitterAddress = address(forked.circleTransmitter());
        expectedCircleTokenMinterAddress = address(forked.circleTokenMinter());
        expectedEvmChain = forked.evmChain();
    }

    function test_UpgradeForkAndCheckSlots() public {
        // Deploy new implementation.
        Implementation implementation = new Implementation(
            address(wormhole),
            vm.envAddress("TESTING_CIRCLE_BRIDGE_ADDRESS") // tokenMessenger
        );

        // Should not be initialized yet.
        bool isInitialized = forked.isInitialized(address(implementation));
        assertFalse(isInitialized, "already initialized");

        (IWormhole.VM memory vaa, bytes memory encodedVaa) = wormhole.craftGovernanceVaa(
            GOVERNANCE_MODULE,
            3, // action
            forked.chainId(),
            69, // sequence
            abi.encodePacked(address(implementation).toUniversalAddress())
        );

        // This VAA should not have been consumed yet.
        bool isVaaConsumed = forked.isMessageConsumed(vaa.hash);
        assertFalse(isVaaConsumed, "VAA already consumed");

        // Before upgrading, fetch some expected values.
        uint16 expectedRegisteredChainId = 6; // Avalanche (Fuji)
        bytes32 expectedEmitter = forked.getRegisteredEmitter(expectedRegisteredChainId);
        uint32 expectedCctpDomain = forked.getDomainFromChainId(expectedRegisteredChainId);

        // Check slots before upgrade.
        {
            bytes32 slotZeroData = vm.load(address(forked), bytes32(0));

            // If the data is already zeroed, check the remaining zeroed slots. Otherwise check that
            // the slots are the expected values from the existing getters.
            if (slotZeroData != 0) {
                // Now check slots that will be zeroed.
                uint256 bitOffset;

                // First 2 bytes is chain ID.
                assertEq(
                    uint16(uint256(slotZeroData >> bitOffset)),
                    expectedChainId,
                    "slot 0x0 not equal to expected before upgrade"
                );
                bitOffset += 16;

                // Next byte is wormhole finality.
                assertEq(
                    uint8(uint256(slotZeroData >> bitOffset)),
                    expectedWormholeFinality,
                    "slot 0x0 not equal to expected before upgrade"
                );
                bitOffset += 8;

                // Next 4 bytes is local domain.
                assertEq(
                    uint32(uint256(slotZeroData >> bitOffset)),
                    expectedLocalDomain,
                    "slot 0x0 not equal to expected before upgrade"
                );
                bitOffset += 32;

                // Next 20 bytes is wormhole address.
                assertEq(
                    address(uint160(uint256(slotZeroData >> bitOffset))),
                    expectedWormholeAddress,
                    "slot 0x0 not equal to expected before upgrade"
                );
                bitOffset += 160;

                // Next 2 bytes is governance chain ID.
                assertEq(
                    uint16(uint256(slotZeroData >> bitOffset)),
                    expectedGovernanceChainId,
                    "slot 0x0 not equal to expected before upgrade"
                );
                bitOffset += 16;

                // Remaining bytes are zero.
                assertEq(
                    uint256(slotZeroData >> bitOffset),
                    0,
                    "slot 0x0 not equal to expected before upgrade"
                );
            }
            if (slotZeroData == 0) {
                assertTrue(
                    forkedAddress.slotValueZero(0x1),
                    "slot 0x1 not equal to expected before upgrade"
                );
                assertTrue(
                    forkedAddress.slotValueZero(0x2),
                    "slot 0x2 not equal to expected before upgrade"
                );
                assertTrue(
                    forkedAddress.slotValueZero(0x3),
                    "slot 0x3 not equal to expected before upgrade"
                );
                assertTrue(
                    forkedAddress.slotValueZero(0x4),
                    "slot 0x4 not equal to expected before upgrade"
                );
            } else {
                assertTrue(
                    forkedAddress.slotValueEquals(0x1, expectedGovernanceContract),
                    "slot 0x1 not equal to expected before upgrade"
                );
                assertTrue(
                    forkedAddress.slotValueEquals(0x2, expectedCircleBridgeAddress),
                    "slot 0x2 not equal to expected before upgrade"
                );
                assertTrue(
                    forkedAddress.slotValueEquals(0x3, expectedCircleTransmitterAddress),
                    "slot 0x3 not equal to expected before upgrade"
                );
                assertTrue(
                    forkedAddress.slotValueEquals(0x4, expectedCircleTokenMinterAddress),
                    "slot 0x4 not equal to expected before upgrade"
                );
            }
            assertTrue(
                forkedAddress.slotValueEquals(
                    keccak256(abi.encode(address(implementation), uint256(0x5))), isInitialized
                ),
                "mapped slot 0x5 not equal to expected before upgrade"
            );
            assertTrue(
                forkedAddress.slotValueEquals(
                    keccak256(abi.encode(expectedRegisteredChainId, uint256(0x6))), expectedEmitter
                ),
                "mapped slot 0x6 not equal to expected before upgrade"
            );
            assertTrue(
                forkedAddress.slotValueEquals(
                    keccak256(abi.encode(expectedRegisteredChainId, uint256(0x7))),
                    expectedCctpDomain
                ),
                "mapped slot 0x7 not equal to expected before upgrade"
            );
            assertTrue(
                forkedAddress.slotValueEquals(
                    keccak256(abi.encode(expectedCctpDomain, uint256(0x8))),
                    expectedRegisteredChainId
                ),
                "mapped slot 0x8 not equal to expected before upgrade"
            );
            assertTrue(
                forkedAddress.slotValueEquals(
                    keccak256(abi.encode(vaa.hash, uint256(0x9))), isVaaConsumed
                ),
                "mapped slot 0x9 not equal to expected before upgrade"
            );
            if (slotZeroData == 0) {
                assertTrue(
                    forkedAddress.slotValueZero(0xa),
                    "slot 0xa not equal to expected before upgrade"
                );
            } else {
                assertTrue(
                    forkedAddress.slotValueEquals(0xa, expectedEvmChain),
                    "slot 0xa not equal to expected before upgrade"
                );
            }
        }

        // Upgrade contract.
        forked.upgradeContract(encodedVaa);

        // Now initialized.
        isInitialized = forked.isInitialized(address(implementation));
        assertTrue(isInitialized, "implementation not initialized");

        // VAA now consumed.
        isVaaConsumed = forked.isMessageConsumed(vaa.hash);
        assertTrue(isVaaConsumed, "VAA not consumed");

        // Now check all slots that were checked before.
        {
            assertTrue(
                forkedAddress.slotValueZero(bytes32(0)),
                "slot 0x0 not equal to expected after upgrade"
            );
            assertTrue(
                forkedAddress.slotValueZero(0x1), "slot 0x1 not equal to expected after upgrade"
            );
            assertTrue(
                forkedAddress.slotValueZero(0x2), "slot 0x2 not equal to expected after upgrade"
            );
            assertTrue(
                forkedAddress.slotValueZero(0x3), "slot 0x3 not equal to expected after upgrade"
            );
            assertTrue(
                forkedAddress.slotValueZero(0x4), "slot 0x4 not equal to expected after upgrade"
            );
            assertTrue(
                forkedAddress.slotValueEquals(
                    keccak256(abi.encode(address(implementation), uint256(0x5))), isInitialized
                ),
                "mapped slot 0x5 not equal to expected after upgrade"
            );
            assertTrue(
                forkedAddress.slotValueEquals(
                    keccak256(abi.encode(expectedRegisteredChainId, uint256(0x6))), expectedEmitter
                ),
                "mapped slot 0x6 not equal to expected after upgrade"
            );
            assertTrue(
                forkedAddress.slotValueEquals(
                    keccak256(abi.encode(expectedRegisteredChainId, uint256(0x7))),
                    expectedCctpDomain
                ),
                "mapped slot 0x7 not equal to expected after upgrade"
            );
            assertTrue(
                forkedAddress.slotValueEquals(
                    keccak256(abi.encode(expectedCctpDomain, uint256(0x8))),
                    expectedRegisteredChainId
                ),
                "mapped slot 0x8 not equal to expected after upgrade"
            );
            assertTrue(
                forkedAddress.slotValueEquals(
                    keccak256(abi.encode(vaa.hash, uint256(0x9))), isVaaConsumed
                ),
                "mapped slot 0x9 not equal to expected after upgrade"
            );
            assertTrue(
                forkedAddress.slotValueZero(0xa), "slot 0xa not equal to expected after upgrade"
            );
        }

        // Make sure getters still retrieve expected values.
        assertEq(forked.chainId(), expectedChainId, "chainId not equal to expected after upgrade");
        assertEq(
            forked.wormholeFinality(),
            expectedWormholeFinality,
            "wormholeFinality not equal to expected after upgrade"
        );
        assertEq(
            forked.localDomain(),
            expectedLocalDomain,
            "localDomain not equal to expected after upgrade"
        );
        assertEq(
            address(forked.wormhole()),
            expectedWormholeAddress,
            "wormholeAddress not equal to expected after upgrade"
        );
        assertEq(
            forked.governanceChainId(),
            expectedGovernanceChainId,
            "governanceChainId not equal to expected after upgrade"
        );
        assertEq(
            forked.governanceContract(),
            expectedGovernanceContract,
            "governanceContract not equal to expected after upgrade"
        );
        assertEq(
            address(forked.circleBridge()),
            expectedCircleBridgeAddress,
            "circleBridgeAddress not equal to expected after upgrade"
        );
        assertEq(
            address(forked.circleTransmitter()),
            expectedCircleTransmitterAddress,
            "circleTransmitterAddress not equal to expected after upgrade"
        );
        assertEq(
            address(forked.circleTokenMinter()),
            expectedCircleTokenMinterAddress,
            "circleTokenMinterAddress not equal to expected after upgrade"
        );
        assertEq(
            forked.evmChain(), expectedEvmChain, "evmChain not equal to expected after upgrade"
        );
    }
}
