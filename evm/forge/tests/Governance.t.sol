// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {IWormhole} from "src/interfaces/IWormhole.sol";
import {ICircleIntegration} from "src/interfaces/ICircleIntegration.sol";

import {Setup} from "src/contracts/CircleIntegration/Setup.sol";
import {Implementation} from "src/contracts/CircleIntegration/Implementation.sol";

import {
    CircleIntegrationOverride,
    CraftedCctpMessageParams,
    CraftedVaaParams
} from "test-helpers/libraries/CircleIntegrationOverride.sol";
import {WormholeOverride} from "test-helpers/libraries/WormholeOverride.sol";

contract GovernanceTest is Test {
    using CircleIntegrationOverride for *;
    using WormholeOverride for *;

    bytes32 constant GOVERNANCE_MODULE =
        0x000000000000000000000000000000436972636c65496e746567726174696f6e;

    uint8 constant GOVERNANCE_REGISTER_EMITTER_AND_DOMAIN = 2;
    uint8 constant GOVERNANCE_UPGRADE_CONTRACT = 3;

    IWormhole wormhole;

    ICircleIntegration circleIntegration;

    function setupWormhole() public {
        wormhole = IWormhole(vm.envAddress("TESTING_WORMHOLE_ADDRESS"));
    }

    function setupCircleIntegration() public {
        // deploy Setup
        Setup setup = new Setup();

        // deploy Implementation
        Implementation implementation = new Implementation(
            address(wormhole),
            vm.envAddress("TESTING_CIRCLE_BRIDGE_ADDRESS") // tokenMessenger
        );

        // deploy Proxy
        ERC1967Proxy proxy =
            new ERC1967Proxy(address(setup), abi.encodeCall(setup.setup, address(implementation)));

        circleIntegration = ICircleIntegration(address(proxy));

        circleIntegration.setUpOverride(uint256(vm.envBytes32("TESTING_DEVNET_GUARDIAN")));
        assertEq(wormhole.guardianPrivateKey(), uint256(vm.envBytes32("TESTING_DEVNET_GUARDIAN")));
    }

    function setUp() public {
        setupWormhole();
        setupCircleIntegration();
    }

    function test_CannotConsumeGovernanceMessageInvalidGovernanceChainId(
        uint16 governanceChainId,
        uint8 action
    ) public {
        vm.assume(governanceChainId != circleIntegration.governanceChainId());

        (, bytes memory encodedVaa) = wormhole.craftGovernanceVaa(
            governanceChainId,
            circleIntegration.governanceContract(),
            GOVERNANCE_MODULE,
            action,
            circleIntegration.chainId(),
            69, // sequence
            abi.encodePacked("Mission accomplished.")
        );

        // You shall not pass!
        vm.expectRevert("invalid governance chain");
        circleIntegration.verifyGovernanceMessage(encodedVaa, action);
    }

    function test_CannotConsumeGovernanceMessageInvalidGovernanceContract(
        bytes32 governanceContract,
        uint8 action
    ) public {
        vm.assume(governanceContract != circleIntegration.governanceContract());

        (, bytes memory encodedVaa) = wormhole.craftGovernanceVaa(
            circleIntegration.governanceChainId(),
            governanceContract,
            GOVERNANCE_MODULE,
            action,
            circleIntegration.chainId(),
            69, // sequence
            abi.encodePacked("Mission accomplished.")
        );

        // You shall not pass!
        vm.expectRevert("invalid governance contract");
        circleIntegration.verifyGovernanceMessage(encodedVaa, action);
    }

    function test_CannotConsumeGovernanceMessageInvalidModule(
        bytes32 governanceModule,
        uint8 action
    ) public {
        vm.assume(governanceModule != GOVERNANCE_MODULE);

        (, bytes memory encodedVaa) = wormhole.craftGovernanceVaa(
            governanceModule,
            action,
            circleIntegration.chainId(),
            69, // sequence
            abi.encodePacked("Mission accomplished.")
        );

        // You shall not pass!
        vm.expectRevert("invalid governance module");
        circleIntegration.verifyGovernanceMessage(encodedVaa, action);
    }

    function test_CannotConsumeGovernanceMessageInvalidAction(uint8 action, uint8 wrongAction)
        public
    {
        vm.assume(action != wrongAction);

        (, bytes memory encodedVaa) = wormhole.craftGovernanceVaa(
            GOVERNANCE_MODULE,
            action,
            circleIntegration.chainId(),
            69, // sequence
            abi.encodePacked("Mission accomplished.")
        );

        // You shall not pass!
        vm.expectRevert("invalid governance action");
        circleIntegration.verifyGovernanceMessage(encodedVaa, wrongAction);
    }

    function test_CannotRegisterEmitterAndDomainInvalidLength(
        uint16 foreignChain,
        bytes32 foreignEmitter,
        uint32 domain
    ) public {
        vm.assume(foreignChain > 0);
        vm.assume(foreignChain != circleIntegration.chainId());
        vm.assume(foreignEmitter != bytes32(0));
        // For the purposes of this test, we will assume the domain set is > 0
        vm.assume(domain > 0);
        vm.assume(domain != circleIntegration.localDomain());

        // No emitters should be registered for this chain.
        assertEq(
            circleIntegration.getRegisteredEmitter(foreignChain), bytes32(0), "already registered"
        );
        assertEq(
            circleIntegration.getDomainFromChainId(foreignChain), 0, "domain already registered"
        );
        assertEq(circleIntegration.getChainIdFromDomain(domain), 0, "chain already registered");

        (, bytes memory encodedVaa) = wormhole.craftGovernanceVaa(
            GOVERNANCE_MODULE,
            GOVERNANCE_REGISTER_EMITTER_AND_DOMAIN, // action
            circleIntegration.chainId(),
            69, // sequence
            abi.encodePacked(foreignChain, foreignEmitter, domain, "But wait! There's more.")
        );

        // You shall not pass!
        vm.expectRevert("invalid governance payload length");
        circleIntegration.registerEmitterAndDomain(encodedVaa);
    }

    function test_CannotRegisterEmitterAndDomainInvalidTargetChain(
        uint16 targetChain,
        uint16 foreignChain,
        bytes32 foreignEmitter,
        uint32 domain
    ) public {
        vm.assume(targetChain != circleIntegration.chainId() && targetChain != 0);
        vm.assume(foreignChain > 0);
        vm.assume(foreignChain != circleIntegration.chainId());
        vm.assume(foreignEmitter != bytes32(0));
        // For the purposes of this test, we will assume the domain set is > 0
        vm.assume(domain > 0);
        vm.assume(domain != circleIntegration.localDomain());

        // No emitters should be registered for this chain.
        assertEq(
            circleIntegration.getRegisteredEmitter(foreignChain), bytes32(0), "already registered"
        );
        assertEq(
            circleIntegration.getDomainFromChainId(foreignChain), 0, "domain already registered"
        );
        assertEq(circleIntegration.getChainIdFromDomain(domain), 0, "chain already registered");

        (, bytes memory encodedVaa) = wormhole.craftGovernanceVaa(
            GOVERNANCE_MODULE,
            GOVERNANCE_REGISTER_EMITTER_AND_DOMAIN, // action
            targetChain,
            69, // sequence
            abi.encodePacked(foreignChain, foreignEmitter, domain)
        );

        // You shall not pass!
        vm.expectRevert("invalid target chain");
        circleIntegration.registerEmitterAndDomain(encodedVaa);
    }

    function test_CannotRegisterEmitterAndDomainInvalidForeignChain(
        bytes32 foreignEmitter,
        uint32 domain
    ) public {
        vm.assume(foreignEmitter != bytes32(0));
        // For the purposes of this test, we will assume the domain set is > 0
        vm.assume(domain > 0);
        vm.assume(domain != circleIntegration.localDomain());

        // No emitters should be registered for this chain.

        // emitterChain cannot be zero
        {
            uint16 foreignChain = 0;
            assertEq(
                circleIntegration.getRegisteredEmitter(foreignChain),
                bytes32(0),
                "already registered"
            );
            assertEq(
                circleIntegration.getDomainFromChainId(foreignChain), 0, "domain already registered"
            );
            assertEq(circleIntegration.getChainIdFromDomain(domain), 0, "chain already registered");

            (, bytes memory encodedVaa) = wormhole.craftGovernanceVaa(
                GOVERNANCE_MODULE,
                GOVERNANCE_REGISTER_EMITTER_AND_DOMAIN, // action
                circleIntegration.chainId(),
                69, // sequence
                abi.encodePacked(foreignChain, foreignEmitter, domain)
            );

            // You shall not pass!
            vm.expectRevert("invalid chain");
            circleIntegration.registerEmitterAndDomain(encodedVaa);
        }

        // emitterChain cannot be this chain's
        {
            uint16 foreignChain = circleIntegration.chainId();
            assertEq(
                circleIntegration.getRegisteredEmitter(foreignChain),
                bytes32(0),
                "already registered"
            );
            assertEq(
                circleIntegration.getDomainFromChainId(foreignChain), 0, "domain already registered"
            );
            assertEq(circleIntegration.getChainIdFromDomain(domain), 0, "chain already registered");

            (, bytes memory encodedVaa) = wormhole.craftGovernanceVaa(
                GOVERNANCE_MODULE,
                GOVERNANCE_REGISTER_EMITTER_AND_DOMAIN, // action
                circleIntegration.chainId(),
                69, // sequence
                abi.encodePacked(foreignChain, foreignEmitter, domain)
            );

            // You shall not pass!
            vm.expectRevert("invalid chain");
            circleIntegration.registerEmitterAndDomain(encodedVaa);
        }
    }

    function test_CannotRegisterEmitterAndDomainInvalidEmitterAddress(
        uint16 foreignChain,
        uint32 domain
    ) public {
        vm.assume(foreignChain > 0);
        vm.assume(foreignChain != circleIntegration.chainId());
        // For the purposes of this test, we will assume the domain set is > 0
        vm.assume(domain > 0);
        vm.assume(domain != circleIntegration.localDomain());

        // No emitters should be registered for this chain.
        assertEq(
            circleIntegration.getRegisteredEmitter(foreignChain), bytes32(0), "already registered"
        );
        assertEq(
            circleIntegration.getDomainFromChainId(foreignChain), 0, "domain already registered"
        );
        assertEq(circleIntegration.getChainIdFromDomain(domain), 0, "chain already registered");

        (, bytes memory encodedVaa) = wormhole.craftGovernanceVaa(
            GOVERNANCE_MODULE,
            GOVERNANCE_REGISTER_EMITTER_AND_DOMAIN, // action
            circleIntegration.chainId(),
            69, // sequence
            abi.encodePacked(
                foreignChain,
                bytes32(0), // emitterAddress
                domain
            )
        );

        // You shall not pass!
        vm.expectRevert("emitter cannot be zero address");
        circleIntegration.registerEmitterAndDomain(encodedVaa);
    }

    function test_CannotRegisterEmitterAndDomainInvalidDomain(
        uint16 foreignChain,
        bytes32 foreignEmitter
    ) public {
        vm.assume(foreignChain > 0);
        vm.assume(foreignChain != circleIntegration.chainId());
        vm.assume(foreignEmitter != bytes32(0));

        // No emitters should be registered for this chain.
        assertEq(
            circleIntegration.getRegisteredEmitter(foreignChain), bytes32(0), "already registered"
        );
        assertEq(
            circleIntegration.getDomainFromChainId(foreignChain), 0, "domain already registered"
        );

        {
            uint32 domain = circleIntegration.localDomain();
            assertEq(circleIntegration.getChainIdFromDomain(domain), 0, "chain already registered");

            (, bytes memory encodedVaa) = wormhole.craftGovernanceVaa(
                GOVERNANCE_MODULE,
                GOVERNANCE_REGISTER_EMITTER_AND_DOMAIN, // action
                circleIntegration.chainId(),
                69, // sequence
                abi.encodePacked(foreignChain, foreignEmitter, domain)
            );

            // You shall not pass!
            vm.expectRevert("domain == localDomain()");
            circleIntegration.registerEmitterAndDomain(encodedVaa);
        }
    }

    function test_RegisterEmitterAndDomainNoTarget() public {
        uint16 foreignChain = 42069;
        bytes32 foreignEmitter =
            bytes32(uint256(uint160(vm.envAddress("TESTING_FOREIGN_USDC_TOKEN_ADDRESS"))));
        uint32 domain = 69420;

        // No emitters should be registered for this chain.
        assertEq(
            circleIntegration.getRegisteredEmitter(foreignChain), bytes32(0), "already registered"
        );
        assertEq(
            circleIntegration.getDomainFromChainId(foreignChain), 0, "domain already registered"
        );
        assertEq(circleIntegration.getChainIdFromDomain(domain), 0, "chain already registered");

        (, bytes memory encodedVaa) = wormhole.craftGovernanceVaa(
            GOVERNANCE_MODULE,
            GOVERNANCE_REGISTER_EMITTER_AND_DOMAIN, // action
            0, // targetChain
            69, // sequence
            abi.encodePacked(foreignChain, foreignEmitter, domain)
        );

        // Register emitter and domain.
        circleIntegration.registerEmitterAndDomain(encodedVaa);

        assertEq(
            circleIntegration.getRegisteredEmitter(foreignChain),
            foreignEmitter,
            "wrong foreignEmitter"
        );
        assertEq(circleIntegration.getDomainFromChainId(foreignChain), domain, "wrong domain");
        assertEq(circleIntegration.getChainIdFromDomain(domain), foreignChain, "wrong chain");
    }

    function test_RegisterEmitterAndDomain(
        uint16 foreignChain,
        bytes32 foreignEmitter,
        uint32 domain
    ) public {
        vm.assume(foreignChain > 0);
        vm.assume(foreignChain != circleIntegration.chainId());
        vm.assume(foreignEmitter != bytes32(0));
        // For the purposes of this test, we will assume the domain set is > 0
        vm.assume(domain > 0);
        vm.assume(domain != circleIntegration.localDomain());

        // No emitters should be registered for this chain.
        assertEq(
            circleIntegration.getRegisteredEmitter(foreignChain), bytes32(0), "already registered"
        );
        assertEq(
            circleIntegration.getDomainFromChainId(foreignChain), 0, "domain already registered"
        );
        assertEq(circleIntegration.getChainIdFromDomain(domain), 0, "chain already registered");

        (, bytes memory encodedVaa) = wormhole.craftGovernanceVaa(
            GOVERNANCE_MODULE,
            GOVERNANCE_REGISTER_EMITTER_AND_DOMAIN, // action
            circleIntegration.chainId(),
            69, // sequence
            abi.encodePacked(foreignChain, foreignEmitter, domain)
        );

        // Register emitter and domain.
        circleIntegration.registerEmitterAndDomain(encodedVaa);

        assertEq(
            circleIntegration.getRegisteredEmitter(foreignChain),
            foreignEmitter,
            "wrong foreignEmitter"
        );
        assertEq(circleIntegration.getDomainFromChainId(foreignChain), domain, "wrong domain");
        assertEq(circleIntegration.getChainIdFromDomain(domain), foreignChain, "wrong chain");

        // we cannot register for this chain again
        {
            (, bytes memory anotherEncodedVaa) = wormhole.craftGovernanceVaa(
                GOVERNANCE_MODULE,
                GOVERNANCE_REGISTER_EMITTER_AND_DOMAIN, // action
                circleIntegration.chainId(),
                70, // sequence
                abi.encodePacked(foreignChain, foreignEmitter, domain)
            );

            // You shall not pass!
            vm.expectRevert("chain already registered");
            circleIntegration.registerEmitterAndDomain(anotherEncodedVaa);
        }
    }

    function test_CannotUpgradeContractInvalidImplementation(
        bytes12 garbage,
        address newImplementation
    ) public {
        vm.assume(garbage != bytes12(0));
        vm.assume(
            newImplementation != address(0) && !circleIntegration.isInitialized(newImplementation)
        );

        // First attempt to submit garbage implementation
        {
            (, bytes memory encodedVaa) = wormhole.craftGovernanceVaa(
                GOVERNANCE_MODULE,
                GOVERNANCE_UPGRADE_CONTRACT, // action
                circleIntegration.chainId(),
                69, // sequence
                abi.encodePacked(garbage, newImplementation)
            );

            // You shall not pass!
            vm.expectRevert("invalid address");
            circleIntegration.upgradeContract(encodedVaa);
        }

        // Now use legitimate-looking ERC20 address
        {
            (, bytes memory encodedVaa) = wormhole.craftGovernanceVaa(
                GOVERNANCE_MODULE,
                GOVERNANCE_UPGRADE_CONTRACT, // action
                circleIntegration.chainId(),
                69, // sequence
                abi.encodePacked(bytes12(0), newImplementation)
            );

            // You shall not pass!
            vm.expectRevert("invalid implementation");
            circleIntegration.upgradeContract(encodedVaa);
        }

        // Now use one of Wormhole's implementations
        {
            address wormholeImplementation = 0x46DB25598441915D59df8955DD2E4256bC3c6e95;

            (, bytes memory encodedVaa) = wormhole.craftGovernanceVaa(
                GOVERNANCE_MODULE,
                GOVERNANCE_UPGRADE_CONTRACT, // action
                circleIntegration.chainId(),
                69, // sequence
                abi.encodePacked(bytes12(0), wormholeImplementation)
            );

            // You shall not pass!
            vm.expectRevert("invalid implementation");
            circleIntegration.upgradeContract(encodedVaa);
        }
    }

    function test_UpgradeContract() public {
        // Deploy new implementation.
        Implementation implementation = new Implementation(
            address(wormhole),
            vm.envAddress("TESTING_CIRCLE_BRIDGE_ADDRESS") // tokenMessenger
        );

        // Should not be initialized yet.
        assertFalse(circleIntegration.isInitialized(address(implementation)), "already initialized");

        (, bytes memory encodedVaa) = wormhole.craftGovernanceVaa(
            GOVERNANCE_MODULE,
            GOVERNANCE_UPGRADE_CONTRACT, // action
            circleIntegration.chainId(),
            69, // sequence
            abi.encodePacked(bytes12(0), address(implementation))
        );

        // Upgrade contract.
        circleIntegration.upgradeContract(encodedVaa);

        // Should not be initialized yet.
        assertTrue(
            circleIntegration.isInitialized(address(implementation)),
            "implementation not initialized"
        );
    }
}
