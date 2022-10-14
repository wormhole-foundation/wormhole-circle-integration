// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/interfaces/IWormhole.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {WormholeSimulator} from "wormhole-solidity/WormholeSimulator.sol";

import "forge-std/console.sol";

interface IUSDC {
    function balanceOf(address account) external view returns (uint256);
    function mint(address to, uint256 amount) external;
    function configureMinter(address minter, uint256 minterAllowedAmount) external;
    function masterMinter() external view returns (address);
}

interface IUSDCBridge {
    function depositForBurnWithCaller(
        uint256 _amount,
        uint32 _destinationDomain,
        bytes32 _mintRecipient,
        address _burnToken,
        bytes32 _destinationCaller
    ) external returns (uint64 _nonce);
}

contract CrossChainUSDC is Test {
    IWormhole wormhole;
    uint256 guardianSigner;

    // Wormhole simulator
    WormholeSimulator public wormholeSimulator;

    // USDC
    IUSDC usdc = IUSDC(0x07865c6E87B9F70255377e024ace6630C1Eaa37F);
    IUSDCBridge usdcBridge = IUSDCBridge(0xdAbec94B97F7b5FCA28f050cC8EeAc2Dc9920476);

    function setUp() public {
        // verify that we're using the correct fork (AVAX mainnet in this case)
        require(block.chainid == vm.envUint("TESTING_FORK_CHAINID"), "wrong evm");

        // this will be used to sign wormhole messages
        guardianSigner = uint256(vm.envBytes32("TESTING_DEVNET_GUARDIAN"));

        // set up Wormhole using Wormhole existing on AVAX mainnet
        wormholeSimulator = new WormholeSimulator(vm.envAddress("TESTING_WORMHOLE_ADDRESS"), guardianSigner);

        // we may need to interact with Wormhole throughout the test
        wormhole = wormholeSimulator.wormhole();

        // verify Wormhole state from fork
        require(wormhole.chainId() == uint16(vm.envUint("TESTING_WORMHOLE_CHAINID")), "wrong chainId");
        require(wormhole.messageFee() == vm.envUint("TESTING_WORMHOLE_MESSAGE_FEE"), "wrong messageFee");
        require(
            wormhole.getCurrentGuardianSetIndex() == uint32(vm.envUint("TESTING_WORMHOLE_GUARDIAN_SET_INDEX")),
            "wrong guardian set index"
        );

        // spoof .configureMinter() call with the master minter account
        vm.prank(usdc.masterMinter());
        // allow this test contract to mint USDC
        usdc.configureMinter(address(this), type(uint256).max);

        // mint $1000 USDC to the test contract (or an external user)
        usdc.mint(address(this), 1000e6);
    }

    function testBalance() public {
        // verify the test contract has $1000 USDC
        uint256 balance = usdc.balanceOf(address(this));
        assertEq(balance, 1000e6);
    }

    function testDeposit() public {
        // variables needed to call the USDC Bridge contract
        uint32 destinationDomain = 1;
        bytes32 mintRecipient = bytes32(uint256(uint160(address(this))));
        uint256 amount = 1e6;
        bytes32 targetWormholeContract = bytes32(uint256(uint160(address(this))));

        SafeERC20.safeApprove(
            IERC20(address(usdc)),
            address(usdcBridge),
            amount
        );

        // burn USDC on the bridge
        uint64 nonce = usdcBridge.depositForBurnWithCaller(
            amount,
            destinationDomain,
            mintRecipient,
            address(usdc),
            targetWormholeContract
        );
    }
}