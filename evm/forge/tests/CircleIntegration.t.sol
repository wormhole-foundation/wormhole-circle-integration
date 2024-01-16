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

import {
    CircleIntegrationOverride,
    CraftedCctpMessageParams,
    CraftedVaaParams
} from "test-helpers/libraries/CircleIntegrationOverride.sol";
import {UsdcDeal} from "test-helpers/libraries/UsdcDeal.sol";
import {WormholeOverride} from "test-helpers/libraries/WormholeOverride.sol";

contract CircleIntegrationTest is Test {
    using Utils for *;
    using WormholeCctpMessages for *;
    using CircleIntegrationOverride for *;
    using WormholeOverride for *;
    using UsdcDeal for address;

    address immutable USDC_ADDRESS = vm.envAddress("TESTING_USDC_TOKEN_ADDRESS");
    bytes32 immutable FOREIGN_USDC_ADDRESS =
        bytes32(uint256(uint160(vm.envAddress("TESTING_FOREIGN_USDC_TOKEN_ADDRESS"))));

    bytes32 constant GOVERNANCE_MODULE =
        0x000000000000000000000000000000436972636c65496e746567726174696f6e;

    // dependencies
    IWormhole wormhole;

    ICircleIntegration circleIntegration;

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
    }

    function test_CannotTransferTokensWithPayloadInvalidToken() public {
        (uint16 targetChain,) = _registerEmitterAndDomain();

        uint256 amount = 69;

        // Perform test with WETH.
        address token = 0x9c3C9283D3e44854697Cd22D3Faa240Cfb032889;
        deal(token, address(this), amount);
        IERC20(token).approve(address(circleIntegration), amount);

        // You shall not pass!
        _expectRevert(
            abi.encodeCall(
                circleIntegration.transferTokensWithPayload,
                (
                    ICircleIntegration.TransferParameters({
                        token: token,
                        amount: amount,
                        targetChain: targetChain,
                        mintRecipient: 0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef
                    }),
                    0, // wormholeNonce
                    abi.encodePacked("All your base are belong to us") // payload
                )
            ),
            abi.encodeCall(this.Error, ("Burn token not supported")) // CCTP Token Messenger error
        );
    }

    function test_CannotTransferTokensWithPayloadZeroAmount() public {
        (uint16 targetChain,) = _registerEmitterAndDomain();

        // You shall not pass!
        _expectRevert(
            abi.encodeCall(
                circleIntegration.transferTokensWithPayload,
                (
                    ICircleIntegration.TransferParameters({
                        token: USDC_ADDRESS,
                        amount: 0,
                        targetChain: targetChain,
                        mintRecipient: 0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef
                    }),
                    0, // wormholeNonce
                    abi.encodePacked("All your base are belong to us") // payload
                )
            ),
            abi.encodeCall(this.Error, ("Amount must be nonzero")) // CCTP Token Messenger error
        );
    }

    function test_CannotTransferTokensWithPayloadInvalidMintRecipient() public {
        uint256 amount = 69;

        (uint16 targetChain,) = _registerEmitterAndDomain();

        _dealAndApproveUsdc(amount);

        // You shall not pass!
        _expectRevert(
            abi.encodeCall(
                circleIntegration.transferTokensWithPayload,
                (
                    ICircleIntegration.TransferParameters({
                        token: USDC_ADDRESS,
                        amount: amount,
                        targetChain: targetChain,
                        mintRecipient: 0
                    }),
                    0, // wormholeNonce
                    abi.encodePacked("All your base are belong to us") // payload
                )
            ),
            abi.encodeCall(this.Error, ("Mint recipient must be nonzero")) // CCTP Token Messenger error
        );
    }

    function test_CannotTransferTokensWithPayloadTargetContractNotRegistered() public {
        uint256 amount = 69;

        uint16 targetChain = 1;

        _dealAndApproveUsdc(amount);

        // You shall not pass!
        _expectRevert(
            abi.encodeCall(
                circleIntegration.transferTokensWithPayload,
                (
                    ICircleIntegration.TransferParameters({
                        token: USDC_ADDRESS,
                        amount: amount,
                        targetChain: targetChain,
                        mintRecipient: 0
                    }),
                    0, // wormholeNonce
                    abi.encodePacked("All your base are belong to us") // payload
                )
            ),
            abi.encodeCall(this.Error, ("target contract not registered"))
        );
    }

    function test_TransferTokensWithPayload(uint256 amount, bytes32 mintRecipient) public {
        amount = bound(amount, 1, _cctpBurnLimit());
        vm.assume(mintRecipient != bytes32(0));

        (uint16 targetChain, uint32 targetDomain) = _registerEmitterAndDomain();
        bytes[2] memory payloads = [
            abi.encodePacked("All your base are belong to us"),
            abi.encodePacked("You are on the way to destruction")
        ];

        _dealAndApproveUsdc(2 * amount);

        uint256 balanceBefore = IERC20(USDC_ADDRESS).balanceOf(address(this));

        vm.recordLogs();
        uint64[2] memory sequences = [
            circleIntegration.transferTokensWithPayload(
                ICircleIntegration.TransferParameters({
                    token: USDC_ADDRESS,
                    amount: amount,
                    targetChain: targetChain,
                    mintRecipient: mintRecipient
                }),
                420, // wormholeNonce
                payloads[0]
            ),
            circleIntegration.transferTokensWithPayload(
                ICircleIntegration.TransferParameters({
                    token: USDC_ADDRESS,
                    amount: amount,
                    targetChain: targetChain,
                    mintRecipient: mintRecipient
                }),
                420, // wormholeNonce
                payloads[1]
            )
        ];

        Vm.Log[] memory logs = vm.getRecordedLogs();

        bytes[] memory fetchedPayloads = logs.fetchWormholePublishedPayloads();
        assertEq(fetchedPayloads.length, 2);

        for (uint256 i; i < 2;) {
            assertEq(sequences[i], uint64(i));
            assertEq(
                keccak256(fetchedPayloads[i]),
                keccak256(
                    USDC_ADDRESS.encodeDeposit(
                        amount,
                        circleIntegration.circleBridge().localMessageTransmitter().localDomain(),
                        targetDomain,
                        circleIntegration.circleBridge().localMessageTransmitter()
                            .nextAvailableNonce() - 2 + uint64(i),
                        address(this).toUniversalAddress(),
                        mintRecipient,
                        payloads[i]
                    )
                )
            );
            unchecked {
                ++i;
            }
        }

        assertEq(IERC20(USDC_ADDRESS).balanceOf(address(this)) + 2 * amount, balanceBefore);
    }

    function test_CannotRedeemTokensWithPayloadUnknownEmitter(bytes32 messageSender) public {
        uint32 remoteDomain = 1;
        uint16 emitterChain = 6;

        ICircleIntegration.RedeemParameters memory redeemParams = circleIntegration
            .craftRedeemParameters(
            CraftedCctpMessageParams({
                remoteDomain: remoteDomain,
                nonce: 2 ** 64 - 1,
                remoteToken: FOREIGN_USDC_ADDRESS,
                mintRecipient: address(this).toUniversalAddress(),
                amount: 69
            }),
            CraftedVaaParams({emitterChain: emitterChain, sequence: 88}),
            0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef, // fromAddress
            abi.encodePacked("Somebody set up us the bomb"),
            messageSender
        );

        // You shall not pass!
        _expectRevert(
            abi.encodeCall(circleIntegration.redeemTokensWithPayload, (redeemParams)),
            abi.encodeCall(this.Error, ("unknown emitter"))
        );
    }

    function test_CannotRedeemTokensWithPayloadCallerMustBeMintRecipient(address mintRecipient)
        public
    {
        vm.assume(mintRecipient != address(0) && mintRecipient != address(this));

        (uint16 emitterChain, uint32 remoteDomain) = _registerEmitterAndDomain();

        ICircleIntegration.RedeemParameters memory redeemParams = circleIntegration
            .craftRedeemParameters(
            CraftedCctpMessageParams({
                remoteDomain: remoteDomain,
                nonce: 2 ** 64 - 1,
                remoteToken: FOREIGN_USDC_ADDRESS,
                mintRecipient: mintRecipient.toUniversalAddress(),
                amount: 69
            }),
            CraftedVaaParams({emitterChain: emitterChain, sequence: 88}),
            0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef, // fromAddress
            abi.encodePacked("Somebody set up us the bomb")
        );

        // You shall not pass!
        _expectRevert(
            abi.encodeCall(circleIntegration.redeemTokensWithPayload, (redeemParams)),
            abi.encodeCall(this.Error, ("caller must be mintRecipient"))
        );
    }

    function test_CannotRedeemTokensWithPayloadMintTokenNotSupported(bytes32 remoteToken) public {
        vm.assume(remoteToken != FOREIGN_USDC_ADDRESS);

        (uint16 emitterChain, uint32 remoteDomain) = _registerEmitterAndDomain();

        ICircleIntegration.RedeemParameters memory redeemParams = circleIntegration
            .craftRedeemParameters(
            CraftedCctpMessageParams({
                remoteDomain: remoteDomain,
                nonce: 2 ** 64 - 1,
                remoteToken: remoteToken,
                mintRecipient: address(this).toUniversalAddress(),
                amount: 69
            }),
            CraftedVaaParams({emitterChain: emitterChain, sequence: 88}),
            0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef, // fromAddress
            abi.encodePacked("Somebody set up us the bomb")
        );

        // You shall not pass!
        _expectRevert(
            abi.encodeCall(circleIntegration.redeemTokensWithPayload, (redeemParams)),
            abi.encodeCall(this.Error, ("Mint token not supported")) // CCTP Token Minter error
        );
    }

    function test_CannotRedeemTokensWithPayloadInvalidMessagePair() public {
        (uint16 emitterChain, uint32 remoteDomain) = _registerEmitterAndDomain();

        ICircleIntegration.RedeemParameters memory redeemParams1 = circleIntegration
            .craftRedeemParameters(
            CraftedCctpMessageParams({
                remoteDomain: remoteDomain,
                nonce: 2 ** 64 - 2,
                remoteToken: FOREIGN_USDC_ADDRESS,
                mintRecipient: address(this).toUniversalAddress(),
                amount: 69
            }),
            CraftedVaaParams({emitterChain: emitterChain, sequence: 88}),
            0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef, // fromAddress
            abi.encodePacked("Somebody set up us the bomb")
        );

        ICircleIntegration.RedeemParameters memory redeemParams2 = circleIntegration
            .craftRedeemParameters(
            CraftedCctpMessageParams({
                remoteDomain: remoteDomain,
                nonce: 2 ** 64 - 1,
                remoteToken: FOREIGN_USDC_ADDRESS,
                mintRecipient: address(this).toUniversalAddress(),
                amount: 69
            }),
            CraftedVaaParams({emitterChain: emitterChain, sequence: 89}),
            0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef, // fromAddress
            abi.encodePacked("Somebody set up us the bomb")
        );

        // Swap VAAs.
        bytes memory tmpEncodedVaa = redeemParams2.encodedVaa;
        redeemParams2.encodedVaa = redeemParams1.encodedVaa;
        redeemParams1.encodedVaa = tmpEncodedVaa;

        // You shall not pass!
        _expectRevert(
            abi.encodeCall(circleIntegration.redeemTokensWithPayload, (redeemParams1)),
            abi.encodeCall(this.Error, ("invalid message pair"))
        );
    }

    function test_RedeemTokensWithPayload(uint256 amount) public {
        amount = bound(amount, 1, _cctpMintLimit());
        (uint16 emitterChain, uint32 remoteDomain) = _registerEmitterAndDomain();

        ICircleIntegration.DepositWithPayload memory expected = ICircleIntegration
            .DepositWithPayload({
            token: USDC_ADDRESS.toUniversalAddress(),
            amount: amount,
            sourceDomain: remoteDomain,
            targetDomain: circleIntegration.circleBridge().localMessageTransmitter().localDomain(),
            nonce: 2 ** 64 - 1,
            fromAddress: 0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef,
            mintRecipient: address(this).toUniversalAddress(),
            payload: abi.encodePacked("Somebody set up us the bomb")
        });

        ICircleIntegration.RedeemParameters memory redeemParams = circleIntegration
            .craftRedeemParameters(
            CraftedCctpMessageParams({
                remoteDomain: expected.sourceDomain,
                nonce: expected.nonce,
                remoteToken: FOREIGN_USDC_ADDRESS,
                mintRecipient: expected.mintRecipient,
                amount: expected.amount
            }),
            CraftedVaaParams({emitterChain: emitterChain, sequence: 88}),
            expected.fromAddress, // fromAddress
            expected.payload
        );

        uint256 balanceBefore = IERC20(USDC_ADDRESS).balanceOf(address(this));

        ICircleIntegration.DepositWithPayload memory deposit =
            circleIntegration.redeemTokensWithPayload(redeemParams);
        assertEq(
            keccak256(circleIntegration.encodeDepositWithPayload(deposit)),
            keccak256(circleIntegration.encodeDepositWithPayload(expected))
        );

        assertEq(IERC20(USDC_ADDRESS).balanceOf(address(this)), amount + balanceBefore);
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
        // console.logBytes(response);
        // console.logBytes(expectedError);

        // compare revert strings
        assertEq(keccak256(response), keccak256(expectedError), "call did not revert as expected");
    }

    function _dealAndApproveUsdc(uint256 amount) internal {
        USDC_ADDRESS.dealAndApprove(address(circleIntegration), amount);
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
        cctpDomain = 1;

        bytes32 foreignEmitter = 0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF.toUniversalAddress();
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
