// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {ICircleIntegration} from "src/interfaces/ICircleIntegration.sol";
import {IWormhole} from "src/interfaces/IWormhole.sol";

import {Utils} from "src/libraries/Utils.sol";
import {WormholeCctpMessages} from "src/libraries/WormholeCctpMessages.sol";

import {Setup} from "src/contracts/CircleIntegration/Setup.sol";
import {Implementation} from "src/contracts/CircleIntegration/Implementation.sol";

import {InheritingWormholeCctp} from "./integrations/InheritingWormholeCctp.sol";

import {
    CircleIntegrationOverride,
    CctpMessage,
    CraftedCctpMessageParams,
    CraftedVaaParams
} from "test-helpers/libraries/CircleIntegrationOverride.sol";
import {UsdcDeal} from "test-helpers/libraries/UsdcDeal.sol";
import {WormholeOverride} from "test-helpers/libraries/WormholeOverride.sol";

contract InheritingWormholeCctpTest is Test {
    using Utils for *;
    using WormholeCctpMessages for *;
    using CircleIntegrationOverride for *;
    using WormholeOverride for *;
    using UsdcDeal for address;

    address immutable USDC_ADDRESS = vm.envAddress("TESTING_USDC_TOKEN_ADDRESS");
    bytes32 immutable FOREIGN_USDC_ADDRESS =
        bytes32(uint256(uint160(vm.envAddress("TESTING_FOREIGN_USDC_TOKEN_ADDRESS"))));

    // dependencies
    IWormhole wormhole;

    // Not a dependency, but using the override as a convenience.
    ICircleIntegration circleIntegration;

    InheritingWormholeCctp inheritedContract;

    function setupWormhole() public {
        wormhole = IWormhole(vm.envAddress("TESTING_WORMHOLE_ADDRESS"));
    }

    function setupUSDC() public {
        (, bytes memory queriedDecimals) =
            USDC_ADDRESS.staticcall(abi.encodeWithSignature("decimals()"));
        uint8 decimals = abi.decode(queriedDecimals, (uint8));
        assertEq(decimals, 6, "wrong USDC");
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
        setupUSDC();
        setupWormhole();
        setupCircleIntegration();

        // set up the inheriting contract
        inheritedContract = new InheritingWormholeCctp(
            address(wormhole),
            address(circleIntegration.circleBridge()), // tokenMessenger
            USDC_ADDRESS
        );
    }

    function test_TransferUsdc(uint256 amount, bytes32 mintRecipient) public {
        amount = bound(amount, 1, _cctpBurnLimit());
        vm.assume(mintRecipient != bytes32(0));

        bytes memory payload = abi.encodePacked("All your base are belong to us");

        _dealAndApproveUsdc(amount);

        uint256 balanceBefore = IERC20(USDC_ADDRESS).balanceOf(address(this));

        vm.recordLogs();
        uint64 wormholeSequence = inheritedContract.transferUsdc(amount, mintRecipient, payload);
        assertEq(wormholeSequence, 0);

        Vm.Log[] memory logs = vm.getRecordedLogs();

        bytes[] memory fetchedPayloads = logs.fetchWormholePublishedPayloads();
        assertEq(fetchedPayloads.length, 1);
        assertEq(
            keccak256(fetchedPayloads[0]),
            keccak256(
                USDC_ADDRESS.encodeDeposit(
                    amount,
                    7, // sourceCctpDomain
                    inheritedContract.myBffDomain(), // targetCctpDomain
                    circleIntegration.circleBridge().localMessageTransmitter().nextAvailableNonce()
                        - 1,
                    address(this).toUniversalAddress(),
                    mintRecipient,
                    payload
                )
            )
        );

        CctpMessage[] memory fetchedCctpMessages = logs.fetchCctpMessages();
        assertEq(fetchedCctpMessages.length, 1);
        assertEq(fetchedCctpMessages[0].header.destinationCaller, inheritedContract.myBffAddr());

        assertEq(IERC20(USDC_ADDRESS).balanceOf(address(this)) + amount, balanceBefore);
    }

    function _getUsdcBalance(address owner) internal view returns (uint256 balance) {
        balance = IERC20(USDC_ADDRESS).balanceOf(owner);
    }

    function _getUsdcBalance() internal view returns (uint256 balance) {
        balance = _getUsdcBalance(address(this));
    }

    function _expectRevert(bytes memory encodedCall, bytes memory expectedError) internal {
        (bool success, bytes memory response) =
            address(circleIntegration).call{value: msg.value}(encodedCall);
        assertFalse(success, "call did not revert");

        // compare revert strings
        assertEq(keccak256(response), keccak256(expectedError), "call did not revert as expected");
    }

    function _dealAndApproveUsdc(uint256 amount) internal {
        USDC_ADDRESS.dealAndApprove(address(inheritedContract), amount);
    }

    function _cctpBurnLimit() internal returns (uint256 limit) {
        limit = circleIntegration.circleBridge().localMinter().burnLimitsPerMessage(USDC_ADDRESS);

        // Having this check prevents us forking a network where Circle has not set a burn limit.
        assertGt(limit, 0);
    }

    function _cctpMintLimit() internal returns (uint256 limit) {
        // This is a hack, assuming the burn limit == mint limit. This really is not the case
        // because there is a mint allowance that is enforced by the USDC contract per registered
        // minter. We use this out of convenience since inbound transfers can never be greater than
        // outbound transfers (which are managed by the burn limit).
        return _cctpBurnLimit();
    }

    function _registerEmitterAndDomain()
        internal
        returns (uint16 foreignChain, uint32 cctpDomain)
    {
        // Register Avalanche.
        foreignChain = 6;
        bytes32 foreignEmitter = 0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF.toUniversalAddress();
        cctpDomain = 1;

        vm.store(
            address(circleIntegration),
            keccak256(abi.encode(foreignChain, uint256(6))),
            foreignEmitter
        );
        vm.store(
            address(circleIntegration),
            keccak256(abi.encode(foreignChain, uint256(7))),
            bytes32(uint256(cctpDomain))
        );
        vm.store(
            address(circleIntegration),
            keccak256(abi.encode(cctpDomain, uint256(8))),
            bytes32(uint256(foreignChain))
        );
    }

    function Error(string memory text) public pure returns (string memory) {
        return text;
    }
}
