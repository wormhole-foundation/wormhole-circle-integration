// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BytesLib} from "wormhole/libraries/external/BytesLib.sol";

import {IWormhole} from "wormhole/interfaces/IWormhole.sol";
import {ICircleIntegration} from "../src/interfaces/ICircleIntegration.sol";
import {IUSDC} from "../src/interfaces/circle/IUSDC.sol";

import {CircleIntegrationStructs} from "../src/circle_integration/CircleIntegrationStructs.sol";
import {CircleIntegrationSetup} from "../src/circle_integration/CircleIntegrationSetup.sol";
import {CircleIntegrationImplementation} from "../src/circle_integration/CircleIntegrationImplementation.sol";
import {CircleIntegrationProxy} from "../src/circle_integration/CircleIntegrationProxy.sol";

import {WormholeSimulator} from "wormhole-forge-sdk/WormholeSimulator.sol";

contract CircleIntegrationTest is Test {
    using BytesLib for bytes;

    bytes32 constant GOVERNANCE_MODULE = 0x000000000000000000000000000000436972636c65496e746567726174696f6e;

    uint8 constant GOVERNANCE_UPDATE_WORMHOLE_FINALITY = 1;
    uint8 constant GOVERNANCE_REGISTER_EMITTER_AND_DOMAIN = 2;
    uint8 constant GOVERNANCE_UPGRADE_CONTRACT = 3;

    // USDC
    IUSDC usdc;

    // dependencies
    WormholeSimulator wormholeSimulator;
    IWormhole wormhole;

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
                address(wormhole),
                uint8(1), // finality
                vm.envAddress("TESTING_CIRCLE_BRIDGE_ADDRESS"), // circleBridge
                uint16(1),
                bytes32(0x0000000000000000000000000000000000000000000000000000000000000004)
            )
        );

        circleIntegration = ICircleIntegration(address(proxy));
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
        // Set up USDC token for test
        if (amount > 0) {
            // First mint USDC.
            mintUSDC(amount);

            // Next set allowance.
            usdc.approve(address(circleIntegration), amount);
        }
    }

    function testEncodeDepositWithPayload(
        bytes32 token,
        uint256 amount,
        uint32 sourceDomain,
        uint32 targetDomain,
        uint64 nonce,
        bytes32 fromAddress,
        bytes32 mintRecipient,
        bytes memory payload
    ) public view {
        vm.assume(token != bytes32(0));
        vm.assume(amount > 0);
        vm.assume(targetDomain != sourceDomain);
        vm.assume(nonce > 0);
        vm.assume(fromAddress != bytes32(0));
        vm.assume(mintRecipient != bytes32(0));
        vm.assume(payload.length > 0);

        ICircleIntegration.DepositWithPayload memory deposit;
        deposit.token = token;
        deposit.amount = amount;

        deposit.sourceDomain = sourceDomain;
        deposit.targetDomain = targetDomain;

        deposit.nonce = nonce;
        deposit.fromAddress = fromAddress;
        deposit.mintRecipient = mintRecipient;
        deposit.payload = payload;

        bytes memory serialized = circleIntegration.encodeDepositWithPayload(deposit);

        // payload ID
        require(serialized.toUint8(0) == 1, "invalid payload");

        // token
        for (uint256 i = 0; i < 32;) {
            require(deposit.token[i] == serialized[i + 1], "invalid token serialization");
            unchecked {
                i += 1;
            }
        }

        // amount
        for (uint256 i = 0; i < 32;) {
            require(bytes32(deposit.amount)[i] == serialized[i + 33], "invalid amount serialization");
            unchecked {
                i += 1;
            }
        }

        // sourceDomain 65
        for (uint256 i = 0; i < 4;) {
            require(bytes4(deposit.sourceDomain)[i] == serialized[i + 65], "invalid sourceDomain serialization");
            unchecked {
                i += 1;
            }
        }
        // targetDomain 69 (hehe)
        for (uint256 i = 0; i < 4;) {
            require(bytes4(deposit.targetDomain)[i] == serialized[i + 69], "invalid targetDomain serialization");
            unchecked {
                i += 1;
            }
        }

        // nonce
        for (uint256 i = 0; i < 8;) {
            require(bytes8(deposit.nonce)[i] == serialized[i + 73], "invalid nonce serialization");
            unchecked {
                i += 1;
            }
        }

        // fromAddress
        for (uint256 i = 0; i < 8;) {
            require(deposit.fromAddress[i] == serialized[i + 81], "invalid fromAddress serialization");
            unchecked {
                i += 1;
            }
        }

        // mintRecipient
        for (uint256 i = 0; i < 8;) {
            require(deposit.mintRecipient[i] == serialized[i + 113], "invalid mintRecipient serialization");
            unchecked {
                i += 1;
            }
        }

        // payload length
        uint256 payloadLen = deposit.payload.length;
        for (uint256 i = 0; i < 2;) {
            require(bytes32(payloadLen)[i + 30] == serialized[i + 145], "invalid payload length serialization");
            unchecked {
                i += 1;
            }
        }

        // payload
        for (uint256 i = 0; i < payloadLen;) {
            require(deposit.payload[i] == serialized[i + 147], "invalid payload serialization");
            unchecked {
                i += 1;
            }
        }
    }

    function testDecodeDepositWithPayload(
        bytes32 token,
        uint256 amount,
        uint32 sourceDomain,
        uint32 targetDomain,
        uint64 nonce,
        bytes32 fromAddress,
        bytes32 mintRecipient,
        bytes memory payload
    ) public view {
        vm.assume(token != bytes32(0));
        vm.assume(amount > 0);
        vm.assume(targetDomain != sourceDomain);
        vm.assume(nonce > 0);
        vm.assume(fromAddress != bytes32(0));
        vm.assume(mintRecipient != bytes32(0));
        vm.assume(payload.length > 0);

        ICircleIntegration.DepositWithPayload memory expected;
        expected.token = token;
        expected.amount = amount;

        expected.sourceDomain = 0;
        expected.targetDomain = 1;

        expected.nonce = nonce;
        expected.fromAddress = fromAddress;
        expected.mintRecipient = mintRecipient;
        expected.payload = payload;

        bytes memory serialized = circleIntegration.encodeDepositWithPayload(expected);

        ICircleIntegration.DepositWithPayload memory deposit = circleIntegration.decodeDepositWithPayload(serialized);
        require(deposit.token == expected.token, "token != expected");
        require(deposit.amount == expected.amount, "amount != expected");
        require(deposit.sourceDomain == expected.sourceDomain, "sourceDomain != expected");
        require(deposit.targetDomain == expected.targetDomain, "targetDomain != expected");
        require(deposit.nonce == expected.nonce, "nonce != expected");
        require(deposit.fromAddress == expected.fromAddress, "fromAddress != expected");
        require(deposit.mintRecipient == expected.mintRecipient, "mintRecipient != expected");

        for (uint256 i = 0; i < deposit.payload.length;) {
            require(deposit.payload[i] == expected.payload[i], "payload != expected");
            unchecked {
                i += 1;
            }
        }
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
        vm.assume(
            targetChain != circleIntegration.chainId() &&
            targetChain != 0
        );
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

    function testRegisterEmitterAndDomainNoTarget() public {
        uint16 foreignChain = 42069;
        bytes32 foreignEmitter = bytes32(uint256(uint160(vm.envAddress("TESTING_FOREIGN_USDC_TOKEN_ADDRESS"))));
        uint32 domain = 69420;

        // No emitters should be registered for this chain.
        assertEq(circleIntegration.getRegisteredEmitter(foreignChain), bytes32(0), "already registered");
        assertEq(circleIntegration.getDomainFromChainId(foreignChain), 0, "domain already registered");
        assertEq(circleIntegration.getChainIdFromDomain(domain), 0, "chain already registered");

        bytes memory encodedMessage = wormholeSimulator.makeSignedGovernanceObservation(
            wormholeSimulator.governanceChainId(),
            wormholeSimulator.governanceContract(),
            GOVERNANCE_MODULE,
            GOVERNANCE_REGISTER_EMITTER_AND_DOMAIN,
            0, // NOTE: set the target chain to zero
            abi.encodePacked(foreignChain, foreignEmitter, domain)
        );

        // Register emitter and domain.
        circleIntegration.registerEmitterAndDomain(encodedMessage);

        require(circleIntegration.getRegisteredEmitter(foreignChain) == foreignEmitter, "wrong foreignEmitter");
        require(circleIntegration.getDomainFromChainId(foreignChain) == domain, "wrong domain");
        require(circleIntegration.getChainIdFromDomain(domain) == foreignChain, "wrong chain");
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

    function testCannotUpgradeContractInvalidImplementation(bytes12 garbage, address newImplementation) public {
        vm.assume(garbage != bytes12(0));
        vm.assume(newImplementation != address(0) && !circleIntegration.isInitialized(newImplementation));

        // First attempt to submit garbage implementation
        {
            bytes memory encodedMessage = wormholeSimulator.makeSignedGovernanceObservation(
                wormholeSimulator.governanceChainId(),
                wormholeSimulator.governanceContract(),
                GOVERNANCE_MODULE,
                GOVERNANCE_UPGRADE_CONTRACT,
                circleIntegration.chainId(),
                abi.encodePacked(garbage, newImplementation)
            );

            // You shall not pass!
            vm.expectRevert("invalid address");
            circleIntegration.upgradeContract(encodedMessage);
        }

        // Now use legitimate-looking ERC20 address
        {
            bytes memory encodedMessage = wormholeSimulator.makeSignedGovernanceObservation(
                wormholeSimulator.governanceChainId(),
                wormholeSimulator.governanceContract(),
                GOVERNANCE_MODULE,
                GOVERNANCE_UPGRADE_CONTRACT,
                circleIntegration.chainId(),
                abi.encodePacked(bytes12(0), newImplementation)
            );

            // You shall not pass!
            vm.expectRevert("invalid implementation");
            circleIntegration.upgradeContract(encodedMessage);
        }

        // Now use one of Wormhole's implementations
        {
            address wormholeImplementation = 0x46DB25598441915D59df8955DD2E4256bC3c6e95;

            bytes memory encodedMessage = wormholeSimulator.makeSignedGovernanceObservation(
                wormholeSimulator.governanceChainId(),
                wormholeSimulator.governanceContract(),
                GOVERNANCE_MODULE,
                GOVERNANCE_UPGRADE_CONTRACT,
                circleIntegration.chainId(),
                abi.encodePacked(bytes12(0), wormholeImplementation)
            );

            // You shall not pass!
            vm.expectRevert("invalid implementation");
            circleIntegration.upgradeContract(encodedMessage);
        }
    }

    function testUpgradeContract() public {
        // Deploy new implementation.
        CircleIntegrationImplementation implementation = new CircleIntegrationImplementation();

        // Should not be initialized yet.
        require(!circleIntegration.isInitialized(address(implementation)), "already initialized");

        bytes memory encodedMessage = wormholeSimulator.makeSignedGovernanceObservation(
            wormholeSimulator.governanceChainId(),
            wormholeSimulator.governanceContract(),
            GOVERNANCE_MODULE,
            GOVERNANCE_UPGRADE_CONTRACT,
            circleIntegration.chainId(),
            abi.encodePacked(bytes12(0), address(implementation))
        );

        // Upgrade contract.
        circleIntegration.upgradeContract(encodedMessage);

        // Should not be initialized yet.
        require(circleIntegration.isInitialized(address(implementation)), "implementation not initialized");
    }

    function testCannotTransferTokensWithPayloadInvalidToken(
        address token,
        uint256 amount,
        uint16 targetChain,
        bytes32 mintRecipient
    ) public {
        vm.assume(token != address(usdc));
        vm.assume(amount > 0 && amount <= maxUSDCAmountToMint());
        vm.assume(targetChain > 0 && targetChain != circleIntegration.chainId());
        vm.assume(mintRecipient != bytes32(0));

        prepareCircleIntegrationTest(amount);

        // You shall not pass!
        vm.expectRevert("token not accepted");
        circleIntegration.transferTokensWithPayload(
            ICircleIntegration.TransferParameters({
                token: token,
                amount: amount,
                targetChain: targetChain,
                mintRecipient: mintRecipient
            }),
            0, // batchId
            abi.encodePacked("All your base are belong to us") // payload
        );
    }

    function testCannotTransferTokensWithPayloadZeroAmount(uint16 targetChain, bytes32 mintRecipient) public {
        vm.assume(targetChain > 0 && targetChain != circleIntegration.chainId());
        vm.assume(mintRecipient != bytes32(0));

        uint256 amount = 0;
        prepareCircleIntegrationTest(amount);

        // You shall not pass!
        vm.expectRevert("amount must be > 0");
        circleIntegration.transferTokensWithPayload(
            ICircleIntegration.TransferParameters({
                token: address(usdc),
                amount: amount,
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
}
