// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {IWormhole} from "src/interfaces/IWormhole.sol";
import {ICircleIntegration} from "src/interfaces/ICircleIntegration.sol";

import {Utils} from "src/libraries/Utils.sol";
import {WormholeCctpMessages} from "src/libraries/WormholeCctpMessages.sol";

import {Setup} from "src/contracts/CircleIntegration/Setup.sol";
import {Implementation} from "src/contracts/CircleIntegration/Implementation.sol";

import {ComposingWithCircleIntegration} from "../integrations/ComposingWithCircleIntegration.sol";
import {InheritingWormholeCctp} from "../integrations/InheritingWormholeCctp.sol";

import {
    CircleIntegrationOverride,
    CraftedCctpMessageParams,
    CraftedVaaParams
} from "test-helpers/libraries/CircleIntegrationOverride.sol";
import {UsdcDeal} from "test-helpers/libraries/UsdcDeal.sol";
import {WormholeOverride} from "test-helpers/libraries/WormholeOverride.sol";

contract CircleIntegrationComparison is Test {
    using Utils for *;
    using WormholeCctpMessages for *;
    using CircleIntegrationOverride for *;
    using WormholeOverride for *;
    using UsdcDeal for address;

    address immutable USDC_ADDRESS = vm.envAddress("TESTING_USDC_TOKEN_ADDRESS");
    bytes32 immutable FOREIGN_USDC_ADDRESS =
        bytes32(uint256(uint160(vm.envAddress("TESTING_FOREIGN_USDC_TOKEN_ADDRESS"))));

    address constant FORKED_CIRCLE_INTEGRATION_ADDRESS = 0x2703483B1a5a7c577e8680de9Df8Be03c6f30e3c;

    // dependencies
    IWormhole wormhole;

    ICircleIntegration circleIntegration;
    ICircleIntegration forkedCircleIntegration;

    ComposingWithCircleIntegration composedContract;
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

        forkedCircleIntegration = ICircleIntegration(FORKED_CIRCLE_INTEGRATION_ADDRESS);
    }

    function setUp() public {
        setupUSDC();
        setupWormhole();
        setupCircleIntegration();

        composedContract =
            new ComposingWithCircleIntegration(address(circleIntegration), USDC_ADDRESS);

        inheritedContract = new InheritingWormholeCctp(
            address(wormhole),
            address(circleIntegration.circleBridge()), // tokenMessenger
            USDC_ADDRESS
        );
    }

    function test_Inherited__TransferUsdc(uint256 amount, bytes32 mintRecipient, bytes32 data)
        public
    {
        amount = bound(amount, 1, _cctpBurnLimit());
        vm.assume(mintRecipient != bytes32(0));
        vm.assume(data != bytes32(0));

        (uint16 targetChain,) = _registerEmitterAndDomain(circleIntegration);
        bytes memory payload = _generatePayload512(data);

        _dealAndApproveUsdc(amount, inheritedContract);

        inheritedContract.transferUsdc(amount, mintRecipient, payload);

        // This is here to avoid the unused variable warning.
        targetChain;
    }

    function test_Composed__TransferUsdc(uint256 amount, bytes32 mintRecipient, bytes32 data)
        public
    {
        amount = bound(amount, 1, _cctpBurnLimit());
        vm.assume(mintRecipient != bytes32(0));
        vm.assume(data != bytes32(0));

        (uint16 targetChain,) = _registerEmitterAndDomain(circleIntegration);
        bytes memory payload = _generatePayload512(data);

        _dealAndApproveUsdc(amount, composedContract);

        composedContract.transferUsdc(targetChain, amount, mintRecipient, payload);
    }

    function test_Latest__TransferTokensWithPayload(
        uint256 amount,
        bytes32 mintRecipient,
        bytes32 data
    ) public {
        amount = bound(amount, 1, _cctpBurnLimit());
        vm.assume(mintRecipient != bytes32(0));
        vm.assume(data != bytes32(0));

        (uint16 targetChain,) = _registerEmitterAndDomain(circleIntegration);
        bytes memory payload = _generatePayload512(data);

        _dealAndApproveUsdc(amount, circleIntegration);

        circleIntegration.transferTokensWithPayload(
            ICircleIntegration.TransferParameters({
                token: USDC_ADDRESS,
                amount: amount,
                targetChain: targetChain,
                mintRecipient: mintRecipient
            }),
            420, // wormholeNonce
            payload
        );
    }

    function test_Fork__TransferTokensWithPayload(
        uint256 amount,
        bytes32 mintRecipient,
        bytes32 data
    ) public {
        amount = bound(amount, 1, _cctpBurnLimit());
        vm.assume(mintRecipient != bytes32(0));
        vm.assume(data != bytes32(0));

        (uint16 targetChain,) = _registerEmitterAndDomain(forkedCircleIntegration);
        bytes memory payload = _generatePayload512(data);

        _dealAndApproveUsdc(amount, forkedCircleIntegration);

        forkedCircleIntegration.transferTokensWithPayload(
            ICircleIntegration.TransferParameters({
                token: USDC_ADDRESS,
                amount: amount,
                targetChain: targetChain,
                mintRecipient: mintRecipient
            }),
            420, // wormholeNonce
            payload
        );
    }

    function test_Control__TransferTokensWithPayload(
        uint256 amount,
        bytes32 mintRecipient,
        bytes32 data
    ) public {
        amount = bound(amount, 1, _cctpBurnLimit());
        vm.assume(mintRecipient != bytes32(0));
        vm.assume(data != bytes32(0));

        (uint16 targetChain,) = _registerEmitterAndDomain(forkedCircleIntegration);
        bytes memory payload = _generatePayload512(data);

        _dealAndApproveUsdc(amount, circleIntegration);

        // This is here to avoid the unused variable warning.
        mintRecipient;
        targetChain;
        payload;
    }

    function test_Inherited__RedeemUsdc(uint256 amount, bytes32 fromAddress, bytes32 data) public {
        amount = bound(amount, 1, _cctpMintLimit());
        vm.assume(fromAddress != bytes32(0));
        vm.assume(data != bytes32(0));

        (uint16 emitterChain, uint32 remoteDomain) = _registerEmitterAndDomain(circleIntegration);

        ICircleIntegration.RedeemParameters memory redeemParams = circleIntegration
            .craftRedeemParameters(
            CraftedCctpMessageParams({
                remoteDomain: remoteDomain,
                nonce: 2 ** 64 - 1,
                remoteToken: FOREIGN_USDC_ADDRESS,
                mintRecipient: address(this).toUniversalAddress(),
                amount: amount
            }),
            CraftedVaaParams({emitterChain: emitterChain, sequence: 88}),
            fromAddress,
            _generatePayload512(data), // payload
            circleIntegration.getRegisteredEmitter(
                circleIntegration.getChainIdFromDomain(remoteDomain)
            ), // messageSender
            address(inheritedContract).toUniversalAddress() // destinationCaller
        );

        inheritedContract.redeemUsdc(
            redeemParams.encodedCctpMessage, redeemParams.cctpAttestation, redeemParams.encodedVaa
        );
    }

    function test_Composed__RedeemUsdc(uint256 amount, bytes32 fromAddress, bytes32 data) public {
        amount = bound(amount, 1, _cctpMintLimit());
        vm.assume(fromAddress != bytes32(0));
        vm.assume(data != bytes32(0));

        (uint16 emitterChain, uint32 remoteDomain) = _registerEmitterAndDomain(circleIntegration);

        ICircleIntegration.RedeemParameters memory redeemParams = circleIntegration
            .craftRedeemParameters(
            CraftedCctpMessageParams({
                remoteDomain: remoteDomain,
                nonce: 2 ** 64 - 1,
                remoteToken: FOREIGN_USDC_ADDRESS,
                mintRecipient: address(composedContract).toUniversalAddress(),
                amount: amount
            }),
            CraftedVaaParams({emitterChain: emitterChain, sequence: 88}),
            fromAddress,
            _generatePayload512(data) // payload
        );

        composedContract.redeemUsdc(redeemParams);
    }

    function test_Latest__RedeemTokensWithPayload(uint256 amount, bytes32 fromAddress, bytes32 data)
        public
    {
        amount = bound(amount, 1, _cctpMintLimit());
        vm.assume(fromAddress != bytes32(0));
        vm.assume(data != bytes32(0));

        (uint16 emitterChain, uint32 remoteDomain) = _registerEmitterAndDomain(circleIntegration);

        ICircleIntegration.RedeemParameters memory redeemParams = circleIntegration
            .craftRedeemParameters(
            CraftedCctpMessageParams({
                remoteDomain: remoteDomain,
                nonce: 2 ** 64 - 1,
                remoteToken: FOREIGN_USDC_ADDRESS,
                mintRecipient: address(this).toUniversalAddress(),
                amount: amount
            }),
            CraftedVaaParams({emitterChain: emitterChain, sequence: 88}),
            fromAddress,
            _generatePayload512(data) // payload
        );

        circleIntegration.redeemTokensWithPayload(redeemParams);
    }

    function test_Fork__RedeemTokensWithPayload(uint256 amount, bytes32 fromAddress, bytes32 data)
        public
    {
        amount = bound(amount, 1, _cctpMintLimit());
        vm.assume(fromAddress != bytes32(0));
        vm.assume(data != bytes32(0));

        (uint16 emitterChain, uint32 remoteDomain) =
            _registerEmitterAndDomain(forkedCircleIntegration);

        ICircleIntegration.RedeemParameters memory redeemParams = forkedCircleIntegration
            .craftRedeemParameters(
            CraftedCctpMessageParams({
                remoteDomain: remoteDomain,
                nonce: 2 ** 64 - 1,
                remoteToken: FOREIGN_USDC_ADDRESS,
                mintRecipient: address(this).toUniversalAddress(),
                amount: amount
            }),
            CraftedVaaParams({emitterChain: emitterChain, sequence: 88}),
            fromAddress,
            _generatePayload512(data) // payload
        );

        forkedCircleIntegration.redeemTokensWithPayload(redeemParams);
    }

    function test_Control__RedeemTokensWithPayload(
        uint256 amount,
        bytes32 fromAddress,
        bytes32 data
    ) public {
        amount = bound(amount, 1, _cctpMintLimit());
        vm.assume(fromAddress != bytes32(0));
        vm.assume(data != bytes32(0));

        (uint16 emitterChain, uint32 remoteDomain) =
            _registerEmitterAndDomain(forkedCircleIntegration);

        ICircleIntegration.RedeemParameters memory redeemParams = forkedCircleIntegration
            .craftRedeemParameters(
            CraftedCctpMessageParams({
                remoteDomain: remoteDomain,
                nonce: 2 ** 64 - 1,
                remoteToken: FOREIGN_USDC_ADDRESS,
                mintRecipient: address(this).toUniversalAddress(),
                amount: amount
            }),
            CraftedVaaParams({emitterChain: emitterChain, sequence: 88}),
            fromAddress,
            _generatePayload512(data) // payload
        );

        // This is here to avoid the unused variable warning.
        redeemParams;
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

    function _dealAndApproveUsdc(uint256 amount, ICircleIntegration integration) internal {
        USDC_ADDRESS.dealAndApprove(address(integration), amount);
    }

    function _dealAndApproveUsdc(uint256 amount, ComposingWithCircleIntegration integration)
        internal
    {
        USDC_ADDRESS.dealAndApprove(address(integration), amount);
    }

    function _dealAndApproveUsdc(uint256 amount, InheritingWormholeCctp integration) internal {
        USDC_ADDRESS.dealAndApprove(address(integration), amount);
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

    function _registerEmitterAndDomain(ICircleIntegration integration)
        internal
        returns (uint16 foreignChain, uint32 cctpDomain)
    {
        // Register Avalanche.
        foreignChain = 6;
        bytes32 foreignEmitter = 0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF.toUniversalAddress();
        cctpDomain = 1;

        vm.store(
            address(integration), keccak256(abi.encode(foreignChain, uint256(6))), foreignEmitter
        );
        vm.store(
            address(integration),
            keccak256(abi.encode(foreignChain, uint256(7))),
            bytes32(uint256(cctpDomain))
        );
        vm.store(
            address(integration),
            keccak256(abi.encode(cctpDomain, uint256(8))),
            bytes32(uint256(foreignChain))
        );
    }

    function _generatePayload512(bytes32 data) internal pure returns (bytes memory payload) {
        payload = abi.encode(
            data,
            data,
            data,
            data,
            data,
            data,
            data,
            data,
            data,
            data,
            data,
            data,
            data,
            data,
            data,
            data
        );
    }

    function Error(string memory text) public pure returns (string memory) {
        return text;
    }
}
