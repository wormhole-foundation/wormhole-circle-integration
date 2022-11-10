// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IWormhole} from "wormhole/interfaces/IWormhole.sol";
import {ICircleIntegration} from "../src/interfaces/ICircleIntegration.sol";
import {ICircleBridge} from "../src/interfaces/circle/ICircleBridge.sol";
import {IMessageTransmitter} from "../src/interfaces/circle/IMessageTransmitter.sol";

import {CircleIntegrationStructs} from "../src/circle_integration/CircleIntegrationStructs.sol";
import {CircleIntegrationSetup} from "../src/circle_integration/CircleIntegrationSetup.sol";
import {CircleIntegrationImplementation} from "../src/circle_integration/CircleIntegrationImplementation.sol";
import {CircleIntegrationProxy} from "../src/circle_integration/CircleIntegrationProxy.sol";

import {WormholeSimulator} from "wormhole-forge-sdk/WormholeSimulator.sol";
import {CircleIntegrationSimulator} from "wormhole-forge-sdk/CircleIntegrationSimulator.sol";

interface IUSDC is IERC20 {
    function mint(address to, uint256 amount) external;
    function configureMinter(address minter, uint256 minterAllowedAmount) external;
    function masterMinter() external view returns (address);
    function owner() external view returns (address);
    function blacklister() external view returns (address);
}

contract CircleIntegrationTest is Test {
    bytes32 constant GOVERNANCE_MODULE = 0x000000000000000000000000000000436972636c65496e746567726174696f6e;

    uint8 constant GOVERNANCE_UPDATE_WORMHOLE_FINALITY = 1;
    uint8 constant GOVERNANCE_REGISTER_EMITTER_AND_DOMAIN = 2;
    uint8 constant GOVERNANCE_REGISTER_ACCEPTED_TOKEN = 3;
    uint8 constant GOVERNANCE_REGISTER_TARGET_CHAIN_TOKEN = 4;

    // USDC
    IUSDC usdc;

    // dependencies
    WormholeSimulator wormholeSimulator;
    IWormhole wormhole;

    ICircleBridge circleBridge;
    IMessageTransmitter messageTransmitter;

    CircleIntegrationSimulator circleSimulator;
    ICircleIntegration circleIntegration;

    // foreign
    bytes32 foreignUsdc;

    function maxUSDCAmountToMint() public view returns (uint256) {
        return type(uint256).max - usdc.totalSupply();
    }

    function mintUSDC(uint256 amount) public {
        require(amount <= maxUSDCAmountToMint(), "total supply overflow");
        usdc.mint(address(this), amount);
    }

    function setupWormhole() public {
        // Set up this chain's Wormhole
        wormholeSimulator = new WormholeSimulator(
            vm.envAddress("TESTING_WORMHOLE_ADDRESS"), uint256(vm.envBytes32("TESTING_DEVNET_GUARDIAN")));
        wormhole = wormholeSimulator.wormhole();
    }

    function setupUSDC() public {
        usdc = IUSDC(vm.envAddress("TESTING_USDC_TOKEN_ADDRESS"));

        (, bytes memory queriedDecimals) = address(usdc).staticcall(abi.encodeWithSignature("decimals()"));
        uint8 decimals = abi.decode(queriedDecimals, (uint8));
        require(decimals == 6, "wrong USDC");

        // spoof .configureMinter() call with the master minter account
        // allow this test contract to mint USDC
        vm.prank(usdc.masterMinter());
        usdc.configureMinter(address(this), type(uint256).max);

        uint256 amount = 42069;
        mintUSDC(amount);
        require(usdc.balanceOf(address(this)) == amount);
    }

    function setupCircleIntegration() public {
        circleSimulator = new CircleIntegrationSimulator(
            address(wormhole),
            vm.envAddress("TESTING_CIRCLE_BRIDGE_ADDRESS"),
            uint256(vm.envBytes32("TESTING_DEVNET_GUARDIAN"))
        );
        circleIntegration = circleSimulator.circleIntegration();
        circleBridge = circleIntegration.circleBridge();
    }

    function setUp() public {
        // set up circle contracts (transferring ownership to address(this), etc)
        setupUSDC();

        // set up wormhole simulator
        setupWormhole();

        // now our contract
        setupCircleIntegration();

        foreignUsdc = bytes32(uint256(uint160(vm.envAddress("TESTING_FOREIGN_USDC_TOKEN_ADDRESS"))));
    }

    function registerToken(address token) public {
        bytes memory encodedMessage = wormholeSimulator.makeSignedGovernanceObservation(
            wormholeSimulator.governanceChainId(),
            wormholeSimulator.governanceContract(),
            GOVERNANCE_MODULE,
            GOVERNANCE_REGISTER_ACCEPTED_TOKEN,
            circleIntegration.chainId(),
            abi.encodePacked(bytes12(0), token)
        );

        // Register and should now be accepted.
        circleIntegration.registerAcceptedToken(encodedMessage);
    }

    function registerUsdcAndTarget() public {
        registerToken(address(usdc));

        // TODO;
    }

    function registerContract(uint16 foreignChain, bytes32 foreignEmitter, uint32 domain) public {
        bytes memory encodedMessage = wormholeSimulator.makeSignedGovernanceObservation(
            wormholeSimulator.governanceChainId(),
            wormholeSimulator.governanceContract(),
            GOVERNANCE_MODULE,
            GOVERNANCE_REGISTER_EMITTER_AND_DOMAIN,
            circleIntegration.chainId(),
            abi.encodePacked(foreignChain, foreignEmitter, domain)
        );

        // Register emitter and domain.
        circleIntegration.registerEmitterAndDomain(encodedMessage);
    }

    function prepareCircleIntegrationTest(uint256 amount) public {
        // Register USDC with CircleIntegration
        registerUsdcAndTarget();

        // Set up USDC token for test
        require(amount > 0, "amount == 0");

        // First mint USDC.
        mintUSDC(amount);

        // Next set allowance.
        usdc.approve(address(circleIntegration), amount);
    }

    function testCannotConsumeGovernanceMessageInvalidGovernanceChainId(uint16 governanceChainId, uint8 action)
        public
    {
        vm.assume(governanceChainId != wormholeSimulator.governanceChainId());

        bytes memory encodedMessage = wormholeSimulator.makeSignedGovernanceObservation(
            governanceChainId,
            wormholeSimulator.governanceContract(),
            GOVERNANCE_MODULE,
            action,
            circleIntegration.chainId(),
            abi.encodePacked("Mission accomplished.")
        );

        // You shall not pass!
        vm.expectRevert("invalid governance chain");
        circleIntegration.verifyGovernanceMessage(encodedMessage, action);
    }

    function testCannotConsumeGovernanceMessageInvalidGovernanceContract(bytes32 governanceContract, uint8 action)
        public
    {
        vm.assume(governanceContract != wormholeSimulator.governanceContract());

        bytes memory encodedMessage = wormholeSimulator.makeSignedGovernanceObservation(
            wormholeSimulator.governanceChainId(),
            governanceContract,
            GOVERNANCE_MODULE,
            action,
            circleIntegration.chainId(),
            abi.encodePacked("Mission accomplished.")
        );

        // You shall not pass!
        vm.expectRevert("invalid governance contract");
        circleIntegration.verifyGovernanceMessage(encodedMessage, action);
    }

    function testCannotConsumeGovernanceMessageInvalidModule(bytes32 governanceModule, uint8 action) public {
        vm.assume(governanceModule != GOVERNANCE_MODULE);

        bytes memory encodedMessage = wormholeSimulator.makeSignedGovernanceObservation(
            wormholeSimulator.governanceChainId(),
            wormholeSimulator.governanceContract(),
            governanceModule,
            action,
            circleIntegration.chainId(),
            abi.encodePacked("Mission accomplished.")
        );

        // You shall not pass!
        vm.expectRevert("invalid governance module");
        circleIntegration.verifyGovernanceMessage(encodedMessage, action);
    }

    function testCannotConsumeGovernanceMessageInvalidAction(uint8 action, uint8 wrongAction) public {
        vm.assume(action != wrongAction);

        bytes memory encodedMessage = wormholeSimulator.makeSignedGovernanceObservation(
            wormholeSimulator.governanceChainId(),
            wormholeSimulator.governanceContract(),
            GOVERNANCE_MODULE,
            action,
            circleIntegration.chainId(),
            abi.encodePacked("Mission accomplished.")
        );

        // You shall not pass!
        vm.expectRevert("invalid governance action");
        circleIntegration.verifyGovernanceMessage(encodedMessage, wrongAction);
    }

    function testCannotUpdateWormholeFinalityInvalidLength(uint8 finality) public {
        vm.assume(finality > 0 && finality != circleIntegration.wormholeFinality());

        bytes memory encodedMessage = wormholeSimulator.makeSignedGovernanceObservation(
            wormholeSimulator.governanceChainId(),
            wormholeSimulator.governanceContract(),
            GOVERNANCE_MODULE,
            GOVERNANCE_UPDATE_WORMHOLE_FINALITY,
            circleIntegration.chainId(),
            abi.encodePacked(finality, "But wait! There's more.")
        );

        // You shall not pass!
        vm.expectRevert("invalid governance payload length");
        circleIntegration.updateWormholeFinality(encodedMessage);
    }

    function testCannotUpdateWormholeFinalityInvalidTargetChain(uint16 targetChainId, uint8 finality) public {
        vm.assume(targetChainId != circleIntegration.chainId());
        vm.assume(finality > 0 && finality != circleIntegration.wormholeFinality());

        bytes memory encodedMessage = wormholeSimulator.makeSignedGovernanceObservation(
            wormholeSimulator.governanceChainId(),
            wormholeSimulator.governanceContract(),
            GOVERNANCE_MODULE,
            GOVERNANCE_UPDATE_WORMHOLE_FINALITY,
            targetChainId,
            abi.encodePacked(finality)
        );

        // You shall not pass!
        vm.expectRevert("invalid target chain");
        circleIntegration.updateWormholeFinality(encodedMessage);
    }

    function testUpdateWormholeFinality(uint8 finality) public {
        vm.assume(finality > 0 && finality != circleIntegration.wormholeFinality());

        assertEq(circleIntegration.wormholeFinality(), 1, "starting finality incorrect");

        bytes memory encodedMessage = wormholeSimulator.makeSignedGovernanceObservation(
            wormholeSimulator.governanceChainId(),
            wormholeSimulator.governanceContract(),
            GOVERNANCE_MODULE,
            GOVERNANCE_UPDATE_WORMHOLE_FINALITY,
            circleIntegration.chainId(),
            abi.encodePacked(finality)
        );

        // Update with governance message
        circleIntegration.updateWormholeFinality(encodedMessage);

        assertEq(circleIntegration.wormholeFinality(), finality, "new finality incorrect");
    }

    function testCannotRegisterEmitterAndDomainInvalidLength(uint16 foreignChain, bytes32 foreignEmitter, uint32 domain)
        public
    {
        vm.assume(foreignChain > 0);
        vm.assume(foreignChain != circleIntegration.chainId());
        vm.assume(foreignEmitter != bytes32(0));
        // For the purposes of this test, we will assume the domain set is > 0
        vm.assume(domain > 0);
        vm.assume(domain != circleIntegration.localDomain());

        // No emitters should be registered for this chain.
        assertEq(circleIntegration.getRegisteredEmitter(foreignChain), bytes32(0), "already registered");
        assertEq(circleIntegration.getDomainFromChainId(foreignChain), 0, "domain already registered");
        assertEq(circleIntegration.getChainIdFromDomain(domain), 0, "chain already registered");

        bytes memory encodedMessage = wormholeSimulator.makeSignedGovernanceObservation(
            wormholeSimulator.governanceChainId(),
            wormholeSimulator.governanceContract(),
            GOVERNANCE_MODULE,
            GOVERNANCE_REGISTER_EMITTER_AND_DOMAIN,
            circleIntegration.chainId(),
            abi.encodePacked(foreignChain, foreignEmitter, domain, "But wait! There's more.")
        );

        // You shall not pass!
        vm.expectRevert("invalid governance payload length");
        circleIntegration.registerEmitterAndDomain(encodedMessage);
    }

    function testCannotRegisterEmitterAndDomainInvalidTargetChain(
        uint16 targetChain,
        uint16 foreignChain,
        bytes32 foreignEmitter,
        uint32 domain
    ) public {
        vm.assume(targetChain != circleIntegration.chainId());
        vm.assume(foreignChain > 0);
        vm.assume(foreignChain != circleIntegration.chainId());
        vm.assume(foreignEmitter != bytes32(0));
        // For the purposes of this test, we will assume the domain set is > 0
        vm.assume(domain > 0);
        vm.assume(domain != circleIntegration.localDomain());

        // No emitters should be registered for this chain.
        assertEq(circleIntegration.getRegisteredEmitter(foreignChain), bytes32(0), "already registered");
        assertEq(circleIntegration.getDomainFromChainId(foreignChain), 0, "domain already registered");
        assertEq(circleIntegration.getChainIdFromDomain(domain), 0, "chain already registered");

        bytes memory encodedMessage = wormholeSimulator.makeSignedGovernanceObservation(
            wormholeSimulator.governanceChainId(),
            wormholeSimulator.governanceContract(),
            GOVERNANCE_MODULE,
            GOVERNANCE_REGISTER_EMITTER_AND_DOMAIN,
            targetChain,
            abi.encodePacked(foreignChain, foreignEmitter, domain)
        );

        // You shall not pass!
        vm.expectRevert("invalid target chain");
        circleIntegration.registerEmitterAndDomain(encodedMessage);
    }

    function testCannotRegisterEmitterAndDomainInvalidForeignChain(bytes32 foreignEmitter, uint32 domain) public {
        vm.assume(foreignEmitter != bytes32(0));
        // For the purposes of this test, we will assume the domain set is > 0
        vm.assume(domain > 0);
        vm.assume(domain != circleIntegration.localDomain());

        // No emitters should be registered for this chain.

        // emitterChain cannot be zero
        {
            uint16 foreignChain = 0;
            assertEq(circleIntegration.getRegisteredEmitter(foreignChain), bytes32(0), "already registered");
            assertEq(circleIntegration.getDomainFromChainId(foreignChain), 0, "domain already registered");
            assertEq(circleIntegration.getChainIdFromDomain(domain), 0, "chain already registered");

            bytes memory encodedMessage = wormholeSimulator.makeSignedGovernanceObservation(
                wormholeSimulator.governanceChainId(),
                wormholeSimulator.governanceContract(),
                GOVERNANCE_MODULE,
                GOVERNANCE_REGISTER_EMITTER_AND_DOMAIN,
                circleIntegration.chainId(),
                abi.encodePacked(foreignChain, foreignEmitter, domain)
            );

            // You shall not pass!
            vm.expectRevert("invalid chain");
            circleIntegration.registerEmitterAndDomain(encodedMessage);
        }

        // emitterChain cannot be this chain's
        {
            uint16 foreignChain = circleIntegration.chainId();
            assertEq(circleIntegration.getRegisteredEmitter(foreignChain), bytes32(0), "already registered");
            assertEq(circleIntegration.getDomainFromChainId(foreignChain), 0, "domain already registered");
            assertEq(circleIntegration.getChainIdFromDomain(domain), 0, "chain already registered");

            bytes memory encodedMessage = wormholeSimulator.makeSignedGovernanceObservation(
                wormholeSimulator.governanceChainId(),
                wormholeSimulator.governanceContract(),
                GOVERNANCE_MODULE,
                GOVERNANCE_REGISTER_EMITTER_AND_DOMAIN,
                circleIntegration.chainId(),
                abi.encodePacked(foreignChain, foreignEmitter, domain)
            );

            // You shall not pass!
            vm.expectRevert("invalid chain");
            circleIntegration.registerEmitterAndDomain(encodedMessage);
        }
    }

    function testCannotRegisterEmitterAndDomainInvalidEmitterAddress(uint16 foreignChain, uint32 domain) public {
        vm.assume(foreignChain > 0);
        vm.assume(foreignChain != circleIntegration.chainId());
        // For the purposes of this test, we will assume the domain set is > 0
        vm.assume(domain > 0);
        vm.assume(domain != circleIntegration.localDomain());

        // No emitters should be registered for this chain.
        assertEq(circleIntegration.getRegisteredEmitter(foreignChain), bytes32(0), "already registered");
        assertEq(circleIntegration.getDomainFromChainId(foreignChain), 0, "domain already registered");
        assertEq(circleIntegration.getChainIdFromDomain(domain), 0, "chain already registered");

        bytes memory encodedMessage = wormholeSimulator.makeSignedGovernanceObservation(
            wormholeSimulator.governanceChainId(),
            wormholeSimulator.governanceContract(),
            GOVERNANCE_MODULE,
            GOVERNANCE_REGISTER_EMITTER_AND_DOMAIN,
            circleIntegration.chainId(),
            abi.encodePacked(
                foreignChain,
                bytes32(0), // emitterAddress
                domain
            )
        );

        // You shall not pass!
        vm.expectRevert("emitter cannot be zero address");
        circleIntegration.registerEmitterAndDomain(encodedMessage);
    }

    function testCannotRegisterEmitterAndDomainInvalidDomain(uint16 foreignChain, bytes32 foreignEmitter) public {
        vm.assume(foreignChain > 0);
        vm.assume(foreignChain != circleIntegration.chainId());
        vm.assume(foreignEmitter != bytes32(0));

        // No emitters should be registered for this chain.
        assertEq(circleIntegration.getRegisteredEmitter(foreignChain), bytes32(0), "already registered");
        assertEq(circleIntegration.getDomainFromChainId(foreignChain), 0, "domain already registered");

        {
            uint32 domain = circleIntegration.localDomain();
            assertEq(circleIntegration.getChainIdFromDomain(domain), 0, "chain already registered");

            bytes memory encodedMessage = wormholeSimulator.makeSignedGovernanceObservation(
                wormholeSimulator.governanceChainId(),
                wormholeSimulator.governanceContract(),
                GOVERNANCE_MODULE,
                GOVERNANCE_REGISTER_EMITTER_AND_DOMAIN,
                circleIntegration.chainId(),
                abi.encodePacked(foreignChain, foreignEmitter, domain)
            );

            // You shall not pass!
            vm.expectRevert("domain == localDomain()");
            circleIntegration.registerEmitterAndDomain(encodedMessage);
        }
    }

    function testRegisterEmitterAndDomain(uint16 foreignChain, bytes32 foreignEmitter, uint32 domain) public {
        vm.assume(foreignChain > 0);
        vm.assume(foreignChain != circleIntegration.chainId());
        vm.assume(foreignEmitter != bytes32(0));
        // For the purposes of this test, we will assume the domain set is > 0
        vm.assume(domain > 0);
        vm.assume(domain != circleIntegration.localDomain());

        // No emitters should be registered for this chain.
        assertEq(circleIntegration.getRegisteredEmitter(foreignChain), bytes32(0), "already registered");
        assertEq(circleIntegration.getDomainFromChainId(foreignChain), 0, "domain already registered");
        assertEq(circleIntegration.getChainIdFromDomain(domain), 0, "chain already registered");

        bytes memory encodedMessage = wormholeSimulator.makeSignedGovernanceObservation(
            wormholeSimulator.governanceChainId(),
            wormholeSimulator.governanceContract(),
            GOVERNANCE_MODULE,
            GOVERNANCE_REGISTER_EMITTER_AND_DOMAIN,
            circleIntegration.chainId(),
            abi.encodePacked(foreignChain, foreignEmitter, domain)
        );

        // Register emitter and domain.
        circleIntegration.registerEmitterAndDomain(encodedMessage);

        require(circleIntegration.getRegisteredEmitter(foreignChain) == foreignEmitter, "wrong foreignEmitter");
        require(circleIntegration.getDomainFromChainId(foreignChain) == domain, "wrong domain");
        require(circleIntegration.getChainIdFromDomain(domain) == foreignChain, "wrong chain");

        // we cannot register for this chain again
        {
            bytes memory anotherMessage = wormholeSimulator.makeSignedGovernanceObservation(
                wormholeSimulator.governanceChainId(),
                wormholeSimulator.governanceContract(),
                GOVERNANCE_MODULE,
                GOVERNANCE_REGISTER_EMITTER_AND_DOMAIN,
                circleIntegration.chainId(),
                abi.encodePacked(foreignChain, foreignEmitter, domain)
            );

            // You shall not pass!
            vm.expectRevert("chain already registered");
            circleIntegration.registerEmitterAndDomain(anotherMessage);
        }
    }

    function testCannotRegisterTargetChainTokenInvalidLength(
        address sourceToken,
        uint16 targetChain,
        bytes32 targetToken
    ) public {
        vm.assume(sourceToken != address(0));
        vm.assume(targetChain > 0 && targetChain != circleIntegration.chainId());
        vm.assume(targetToken != bytes32(0));

        // First register source token
        registerToken(sourceToken);

        // Should not already exist.
        assertEq(
            circleIntegration.targetAcceptedToken(sourceToken, targetChain),
            bytes32(0),
            "target token already registered"
        );

        bytes memory encodedMessage = wormholeSimulator.makeSignedGovernanceObservation(
            wormholeSimulator.governanceChainId(),
            wormholeSimulator.governanceContract(),
            GOVERNANCE_MODULE,
            GOVERNANCE_REGISTER_TARGET_CHAIN_TOKEN,
            circleIntegration.chainId(),
            abi.encodePacked(bytes12(0), sourceToken, targetChain, targetToken, "But wait! There's more.")
        );

        // Now register target token.
        vm.expectRevert("invalid governance payload length");
        circleIntegration.registerTargetChainToken(encodedMessage);
    }

    function testCannotRegisterAcceptedTokenInvalidLength(address tokenAddress) public {
        vm.assume(tokenAddress != address(0));

        // Should not already be accepted.
        assertTrue(!circleIntegration.isAcceptedToken(tokenAddress), "token already registered");

        bytes memory encodedMessage = wormholeSimulator.makeSignedGovernanceObservation(
            wormholeSimulator.governanceChainId(),
            wormholeSimulator.governanceContract(),
            GOVERNANCE_MODULE,
            GOVERNANCE_REGISTER_ACCEPTED_TOKEN,
            circleIntegration.chainId(),
            abi.encodePacked(bytes12(0), tokenAddress, "But wait! There's more.")
        );

        // Register and should now be accepted.
        vm.expectRevert("invalid governance payload length");
        circleIntegration.registerAcceptedToken(encodedMessage);
    }

    function testCannotRegisterAcceptedTokenZeroAddress() public {
        // Should not already be accepted.
        address tokenAddress = address(0);
        assertTrue(!circleIntegration.isAcceptedToken(tokenAddress), "token already registered");

        bytes memory encodedMessage = wormholeSimulator.makeSignedGovernanceObservation(
            wormholeSimulator.governanceChainId(),
            wormholeSimulator.governanceContract(),
            GOVERNANCE_MODULE,
            GOVERNANCE_REGISTER_ACCEPTED_TOKEN,
            circleIntegration.chainId(),
            abi.encodePacked(bytes12(0), tokenAddress)
        );

        // You shall not pass!
        vm.expectRevert("token is zero address");
        circleIntegration.registerAcceptedToken(encodedMessage);
    }

    function testCannotRegisterAcceptedTokenInvalidToken(bytes12 garbage, address tokenAddress) public {
        vm.assume(garbage != bytes12(0));
        vm.assume(tokenAddress != address(0));

        // Should not already be accepted.
        assertTrue(!circleIntegration.isAcceptedToken(tokenAddress), "token already registered");

        bytes memory encodedMessage = wormholeSimulator.makeSignedGovernanceObservation(
            wormholeSimulator.governanceChainId(),
            wormholeSimulator.governanceContract(),
            GOVERNANCE_MODULE,
            GOVERNANCE_REGISTER_ACCEPTED_TOKEN,
            circleIntegration.chainId(),
            abi.encodePacked(garbage, tokenAddress)
        );

        // You shall not pass!
        vm.expectRevert("invalid address");
        circleIntegration.registerAcceptedToken(encodedMessage);
    }

    function testRegisterAcceptedToken(address tokenAddress) public {
        vm.assume(tokenAddress != address(0));

        // Should not already be accepted.
        assertTrue(!circleIntegration.isAcceptedToken(tokenAddress), "token already registered");

        bytes memory encodedMessage = wormholeSimulator.makeSignedGovernanceObservation(
            wormholeSimulator.governanceChainId(),
            wormholeSimulator.governanceContract(),
            GOVERNANCE_MODULE,
            GOVERNANCE_REGISTER_ACCEPTED_TOKEN,
            circleIntegration.chainId(),
            abi.encodePacked(bytes12(0), tokenAddress)
        );

        // Register and should now be accepted.
        circleIntegration.registerAcceptedToken(encodedMessage);

        assertTrue(circleIntegration.isAcceptedToken(tokenAddress), "token not registered");
    }

    function testCannotRegisterTargetChainTokenInvalidSourceToken(
        bytes12 garbage,
        address sourceToken,
        uint16 targetChain,
        bytes32 targetToken
    ) public {
        vm.assume(garbage != bytes12(0));
        vm.assume(sourceToken != address(0));
        vm.assume(targetChain > 0 && targetChain != circleIntegration.chainId());
        vm.assume(targetToken != bytes32(0));

        // Should not already exist.
        assertEq(
            circleIntegration.targetAcceptedToken(sourceToken, targetChain),
            bytes32(0),
            "target token already registered"
        );

        // First attempt to submit garbage source token
        {
            bytes memory encodedMessage = wormholeSimulator.makeSignedGovernanceObservation(
                wormholeSimulator.governanceChainId(),
                wormholeSimulator.governanceContract(),
                GOVERNANCE_MODULE,
                GOVERNANCE_REGISTER_TARGET_CHAIN_TOKEN,
                circleIntegration.chainId(),
                abi.encodePacked(garbage, sourceToken, targetChain, targetToken)
            );

            // You shall not pass!
            vm.expectRevert("invalid address");
            circleIntegration.registerTargetChainToken(encodedMessage);
        }

        // Now use legitimate-looking ERC20 address
        {
            bytes memory encodedMessage = wormholeSimulator.makeSignedGovernanceObservation(
                wormholeSimulator.governanceChainId(),
                wormholeSimulator.governanceContract(),
                GOVERNANCE_MODULE,
                GOVERNANCE_REGISTER_TARGET_CHAIN_TOKEN,
                circleIntegration.chainId(),
                abi.encodePacked(bytes12(0), sourceToken, targetChain, targetToken)
            );

            // You shall not pass!
            vm.expectRevert("source token not accepted");
            circleIntegration.registerTargetChainToken(encodedMessage);
        }
    }

    function testCannotRegisterTargetChainTokenInvalidTargetChain(address sourceToken, bytes32 targetToken) public {
        vm.assume(sourceToken != address(0));
        vm.assume(targetToken != bytes32(0));

        // First register source token
        registerToken(sourceToken);

        // Cannot register chain ID == 0
        {
            uint16 targetChain = 0;

            // Should not already exist.
            assertEq(
                circleIntegration.targetAcceptedToken(sourceToken, targetChain),
                bytes32(0),
                "target token already registered"
            );

            bytes memory encodedMessage = wormholeSimulator.makeSignedGovernanceObservation(
                wormholeSimulator.governanceChainId(),
                wormholeSimulator.governanceContract(),
                GOVERNANCE_MODULE,
                GOVERNANCE_REGISTER_TARGET_CHAIN_TOKEN,
                circleIntegration.chainId(),
                abi.encodePacked(bytes12(0), sourceToken, targetChain, targetToken)
            );

            // You shall not pass!
            vm.expectRevert("invalid target chain");
            circleIntegration.registerTargetChainToken(encodedMessage);
        }

        // Cannot register chain ID == this chain's
        {
            uint16 targetChain = circleIntegration.chainId();

            // Should not already exist.
            assertEq(
                circleIntegration.targetAcceptedToken(sourceToken, targetChain),
                bytes32(0),
                "target token already registered"
            );

            bytes memory encodedMessage = wormholeSimulator.makeSignedGovernanceObservation(
                wormholeSimulator.governanceChainId(),
                wormholeSimulator.governanceContract(),
                GOVERNANCE_MODULE,
                GOVERNANCE_REGISTER_TARGET_CHAIN_TOKEN,
                circleIntegration.chainId(),
                abi.encodePacked(bytes12(0), sourceToken, targetChain, targetToken)
            );

            // You shall not pass!
            vm.expectRevert("invalid target chain");
            circleIntegration.registerTargetChainToken(encodedMessage);
        }
    }

    function testCannotRegisterTargetChainTokenInvalidTargetToken(address sourceToken, uint16 targetChain) public {
        vm.assume(sourceToken != address(0));
        vm.assume(targetChain > 0 && targetChain != circleIntegration.chainId());

        // First register source token
        registerToken(sourceToken);

        // Should not already exist.
        assertEq(
            circleIntegration.targetAcceptedToken(sourceToken, targetChain),
            bytes32(0),
            "target token already registered"
        );

        bytes memory encodedMessage = wormholeSimulator.makeSignedGovernanceObservation(
            wormholeSimulator.governanceChainId(),
            wormholeSimulator.governanceContract(),
            GOVERNANCE_MODULE,
            GOVERNANCE_REGISTER_TARGET_CHAIN_TOKEN,
            circleIntegration.chainId(),
            abi.encodePacked(
                bytes12(0),
                sourceToken,
                targetChain,
                bytes32(0) // targetToken
            )
        );

        // You shall not pass!
        vm.expectRevert("target token is zero address");
        circleIntegration.registerTargetChainToken(encodedMessage);
    }

    function testRegisterTargetChainToken(address sourceToken, uint16 targetChain, bytes32 targetToken) public {
        vm.assume(sourceToken != address(0));
        vm.assume(targetChain > 0 && targetChain != circleIntegration.chainId());
        vm.assume(targetToken != bytes32(0));

        // First register source token
        registerToken(sourceToken);

        // Should not already exist.
        assertEq(
            circleIntegration.targetAcceptedToken(sourceToken, targetChain),
            bytes32(0),
            "target token already registered"
        );

        bytes memory encodedMessage = wormholeSimulator.makeSignedGovernanceObservation(
            wormholeSimulator.governanceChainId(),
            wormholeSimulator.governanceContract(),
            GOVERNANCE_MODULE,
            GOVERNANCE_REGISTER_TARGET_CHAIN_TOKEN,
            circleIntegration.chainId(),
            abi.encodePacked(bytes12(0), sourceToken, targetChain, targetToken)
        );

        // Now register target token.
        circleIntegration.registerTargetChainToken(encodedMessage);
        assertEq(
            circleIntegration.targetAcceptedToken(sourceToken, targetChain), targetToken, "target token not registered"
        );
    }

    function testCannotTransferTokensWithPayloadZeroAmount(uint16 targetChain, bytes32 mintRecipient) public {
        vm.assume(targetChain > 0 && targetChain != circleIntegration.chainId());
        vm.assume(mintRecipient != bytes32(0));

        // You shall not pass!
        vm.expectRevert("amount must be > 0");
        circleIntegration.transferTokensWithPayload(
            ICircleIntegration.TransferParameters({
                token: address(usdc),
                amount: 0,
                targetChain: targetChain,
                mintRecipient: mintRecipient
            }),
            0, // batchId
            abi.encodePacked("All your base are belong to us") // payload
        );
    }

    function testCannotTransferTokensWithPayloadInvalidMintRecipient(uint256 amount, uint16 targetChain) public {
        vm.assume(amount > 0 && amount <= maxUSDCAmountToMint());
        vm.assume(targetChain > 0 && targetChain != circleIntegration.chainId());

        prepareCircleIntegrationTest(amount);

        // You shall not pass!
        vm.expectRevert("invalid mint recipient");
        circleIntegration.transferTokensWithPayload(
            ICircleIntegration.TransferParameters({
                token: address(usdc),
                amount: amount,
                targetChain: targetChain,
                mintRecipient: bytes32(0)
            }),
            0, // batchId
            abi.encodePacked("All your base are belong to us") // payload
        );
    }

    // function testTransferTokensWithPayload(uint256 amount, uint16 targetChain, bytes32 mintRecipient) public {
    //     vm.assume(amount > 0 && amount <= maxUSDCAmountToMint());
    //     vm.assume(targetChain > 0 && targetChain != circleIntegration.chainId());
    //     vm.assume(mintRecipient != bytes32(0));

    //     registerContract(
    //         targetChain,
    //         0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef, // foreignEmitter
    //         1 // domain
    //     );

    //     prepareCircleIntegrationTest(amount);

    //     // Register target token
    //     circleIntegration.registerTargetChainToken(
    //         address(usdc), // sourceToken
    //         targetChain,
    //         foreignUsdc // targetToken
    //     );

    //     // Record balance.
    //     uint256 myBalanceBefore = usdc.balanceOf(address(this));
    //     assertEq(usdc.balanceOf(address(circleIntegration)), 0, "CircleIntegration has balance");

    //     bytes memory payload = abi.encodePacked("All your base are belong to us");

    //     vm.recordLogs();

    //     // Pass.
    //     circleIntegration.transferTokensWithPayload(address(usdc), amount, targetChain, mintRecipient, payload);

    //     // Prepare to check transaction logs for expected events.
    //     Vm.Log[] memory entries = vm.getRecordedLogs();

    //     // Circle's MessageSent value
    //     bytes memory message = circleSimulator.findMessageSentInLogs(entries);

    //     // Wormhole's LogMessagePublished values
    //     (uint64 sequence, uint32 batchId, bytes memory wormholePayload, uint8 finality) =
    //         wormholeSimulator.findLogMessagePublishedInLogs(entries);
    //     assertEq(sequence, 0, "sequence != expected");
    //     assertEq(batchId, 0, "batchId != expected");
    //     assertEq(finality, circleIntegration.wormholeFinality(), "finality != circleIntegration.wormholeFinality()");

    //     // Deserialize wormhole payload
    //     CircleIntegrationSimulator.DepositWithPayload memory deposit =
    //         circleSimulator.decodeDepositWithPayload(wormholePayload);
    //     assertEq(
    //         deposit.token,
    //         circleIntegration.targetAcceptedToken(address(usdc), targetChain),
    //         "deposit.token != expected"
    //     );
    //     assertEq(deposit.amount, amount, "deposit.amount != expected");
    //     assertEq(deposit.sourceDomain, circleIntegration.localDomain(), "deposit.sourceDomain != expected");
    //     assertEq(
    //         deposit.targetDomain,
    //         circleIntegration.getDomainFromChainId(targetChain),
    //         "deposit.targetDomain != expected"
    //     );
    //     assertEq(deposit.nonce, 112396, "deposit.nonce != expected");
    //     assertEq(deposit.mintRecipient, mintRecipient, "deposit.mintRecipient != expected");
    //     assertEq(deposit.payload, payload, "deposit.payload != expected");

    //     // My balance change should equal the amount transferred.
    //     assertEq(myBalanceBefore - usdc.balanceOf(address(this)), amount, "mismatch in my balance");

    //     // CircleIntegration's balance should not reflect having any USDC.
    //     assertEq(usdc.balanceOf(address(circleIntegration)), 0, "CircleIntegration has new balance");
    // }

    // function borkedTestRedeemTokensWithPayload(uint16 foreignChain) public {
    //     vm.assume(foreignChain > 0 && foreignChain != circleIntegration.chainId());

    //     uint32 foreignDomain = 1;
    //     // Register foreign CircleIntegration
    //     registerContract(
    //         foreignChain,
    //         bytes32(uint256(uint160(address(circleIntegration)))), // foreignEmitter
    //         foreignDomain // domain
    //     );

    //     uint256 amount = 42069;
    //     uint64 availableNonce = uint64(vm.envUint("TESTING_LAST_NONCE"));

    //     ICircleIntegration.RedeemParameters memory redeemParams;

    //     redeemParams.circleBridgeMessage = abi.encodePacked(
    //         messageTransmitter.version(),
    //         foreignDomain,
    //         circleIntegration.localDomain(),
    //         availableNonce,
    //         circleBridge.remoteCircleBridges(foreignDomain),
    //         bytes32(uint256(uint160(address(circleBridge)))),
    //         circleIntegration.getRegisteredEmitter(foreignChain), // expected caller
    //         bytes4(0), // ???
    //         foreignUsdc,
    //         bytes32(uint256(uint160(address(this)))), // attester
    //         amount
    //     );
    //     redeemParams.circleAttestation = circleSimulator.attestMessage(redeemParams.circleBridgeMessage);

    //     IWormhole.VM memory wormholeMessage;
    //     wormholeMessage.timestamp = uint32(block.timestamp);
    //     wormholeMessage.nonce = 0;
    //     wormholeMessage.emitterChainId = foreignChain;
    //     wormholeMessage.emitterAddress = bytes32(uint256(uint160(address(circleIntegration))));
    //     wormholeMessage.sequence = 0;
    //     wormholeMessage.consistencyLevel = 1;
    //     wormholeMessage.payload = circleSimulator.encodeDepositWithPayload(
    //         CircleIntegrationStructs.DepositWithPayload({
    //             token: foreignUsdc,
    //             amount: amount,
    //             sourceDomain: foreignDomain,
    //             targetDomain: circleIntegration.localDomain(),
    //             nonce: availableNonce,
    //             fromAddress: bytes32(uint256(uint160(address(this)))),
    //             mintRecipient: bytes32(uint256(uint160(address(this)))),
    //             payload: abi.encodePacked("All your base are belong to us")
    //         })
    //     );
    //     redeemParams.encodedWormholeMessage = wormholeSimulator.signDevnetObservation(wormholeMessage);

    //     circleIntegration.redeemTokensWithPayload(redeemParams);
    // }
}
