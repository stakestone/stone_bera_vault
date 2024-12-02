// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {StoneBeraVault} from "../src/StoneBeraVault.sol";
import {Token} from "../src/Token.sol";
import {OracleConfigurator} from "../src/oracle/OracleConfigurator.sol";

import {MockToken} from "./MockToken.sol";
import {MockOracle} from "./MockOracle.sol";

import "../src/Errors.sol";

contract StoneBeraVaultTest is Test {
    using Math for uint256;

    Token public lpToken;

    MockToken public tokenA;
    MockToken public tokenB;

    MockOracle public oracleA;
    MockOracle public oracleB;

    OracleConfigurator public oracleConfigurator;

    StoneBeraVault public stoneBeraVault;

    function setUp() public {
        console.log("Deployer: %s", msg.sender);

        lpToken = new Token("Vault Token", "T");
        console.log("LP Token Address: %s", address(lpToken));

        tokenA = new MockToken(18);
        tokenB = new MockToken(18);

        tokenA.mint(address(this), 10000 * 1e18);
        tokenB.mint(address(this), 10000 * 1e18);

        oracleA = new MockOracle(address(tokenA), "Token A Oracle");
        oracleB = new MockOracle(address(tokenB), "Token B Oracle");

        oracleConfigurator = new OracleConfigurator();
        oracleConfigurator.grantRole(
            oracleConfigurator.ORACLE_MANAGER_ROLE(),
            address(this)
        );
        console.log(
            "OracleConfigurator Address: %s",
            address(oracleConfigurator)
        );
        oracleConfigurator.updateOracle(address(tokenA), address(oracleA));
        oracleConfigurator.updateOracle(address(tokenB), address(oracleB));

        stoneBeraVault = new StoneBeraVault(
            address(lpToken),
            address(tokenB),
            address(oracleConfigurator),
            1000 * 1e18
        );
        stoneBeraVault.grantRole(
            stoneBeraVault.VAULT_OPERATOR_ROLE(),
            address(this)
        );
        stoneBeraVault.grantRole(
            stoneBeraVault.ASSETS_MANAGEMENT_ROLE(),
            address(this)
        );

        stoneBeraVault.addUnderlyingAsset(address(tokenA));
        stoneBeraVault.addUnderlyingAsset(address(tokenB));

        lpToken.grantRole(lpToken.MINTER_ROLE(), address(stoneBeraVault));
        lpToken.grantRole(lpToken.BURNER_ROLE(), address(stoneBeraVault));

        console.log("StoneBeraVault Address: %s", address(stoneBeraVault));
    }

    function test_removeUnderlyingAsset() public {
        assertTrue(stoneBeraVault.isUnderlyingAssets(address(tokenA)));
        assertTrue(stoneBeraVault.isUnderlyingAssets(address(tokenB)));
        assertEq(stoneBeraVault.underlyingAssets(0), address(tokenA));
        assertEq(stoneBeraVault.underlyingAssets(1), address(tokenB));
        assertEq(stoneBeraVault.getUnderlyings().length, 2);

        stoneBeraVault.removeUnderlyingAsset(address(tokenA));
        assertTrue(!stoneBeraVault.isUnderlyingAssets(address(tokenA)));
        assertTrue(stoneBeraVault.isUnderlyingAssets(address(tokenB)));
        assertEq(stoneBeraVault.underlyingAssets(0), address(tokenB));
        assertEq(stoneBeraVault.getUnderlyings().length, 1);

        stoneBeraVault.removeUnderlyingAsset(address(tokenB));
        assertTrue(!stoneBeraVault.isUnderlyingAssets(address(tokenA)));
        assertTrue(!stoneBeraVault.isUnderlyingAssets(address(tokenB)));
        assertEq(stoneBeraVault.getUnderlyings().length, 0);
    }

    function test_deposit_basic() public {
        tokenA.approve(address(stoneBeraVault), 1e18);

        stoneBeraVault.deposit(address(tokenA), 1e18, msg.sender);
        assertEq(lpToken.balanceOf(msg.sender), 1e18);

        assertEq(stoneBeraVault.getRate(), 1e18);

        tokenA.approve(address(stoneBeraVault), 2e18);
        stoneBeraVault.deposit(address(tokenA), 2e18, address(this));
        assertEq(lpToken.balanceOf(address(this)), 2e18);

        assertEq(stoneBeraVault.getRate(), 1e18);
    }

    function test_deposit_capped() public {
        tokenA.approve(address(stoneBeraVault), 1001 * 1e18);

        vm.expectRevert(DepositCapped.selector);
        stoneBeraVault.deposit(address(tokenA), 1001 * 1e18, msg.sender);
    }

    function test_mint_basic() public {
        tokenA.approve(address(stoneBeraVault), 1e18);

        stoneBeraVault.mint(address(tokenA), 1e18, msg.sender);
        assertEq(lpToken.balanceOf(msg.sender), 1e18);
        assertEq(stoneBeraVault.getRate(), 1e18);

        tokenA.approve(address(stoneBeraVault), 2e18);
        stoneBeraVault.mint(address(tokenA), 2e18, address(this));
        assertEq(lpToken.balanceOf(address(this)), 2e18);
        assertEq(stoneBeraVault.getRate(), 1e18);
    }

    function test_mint_capped() public {
        tokenA.approve(address(stoneBeraVault), 1001 * 1e18);

        vm.expectRevert(DepositCapped.selector);
        stoneBeraVault.mint(address(tokenA), 1001 * 1e18, msg.sender);
    }

    function test_roll_with_no_request() public {
        tokenA.approve(address(stoneBeraVault), 1e18);

        stoneBeraVault.deposit(address(tokenA), 1e18, msg.sender);
        assertEq(lpToken.balanceOf(msg.sender), 1e18);

        assertEq(stoneBeraVault.getRate(), 1e18);
        stoneBeraVault.rollToNextRound();
        assertEq(stoneBeraVault.getRate(), 1e18);
    }

    function test_deposit_diff_A_price() public {
        address bob = address(0xB0B);

        tokenA.approve(address(stoneBeraVault), 1e18);

        stoneBeraVault.deposit(address(tokenA), 1e18, msg.sender);
        assertEq(lpToken.balanceOf(msg.sender), 1e18);
        assertEq(stoneBeraVault.getRate(), 1e18);

        uint256 price = 1.1 * 1e18;
        oracleA.updatePrice(price);

        assertEq(stoneBeraVault.getRate(), price);

        tokenB.approve(address(stoneBeraVault), 1e18);
        stoneBeraVault.deposit(address(tokenB), 1e18, bob);
        assertEq(
            lpToken.balanceOf(bob),
            uint256(1e18).mulDiv(1e18, price, Math.Rounding.Floor)
        );
        assertEq(stoneBeraVault.getRate(), price);
    }

    function test_deposit_diff_B_price() public {
        address bob = address(0xB0B);

        tokenA.approve(address(stoneBeraVault), 1e18);

        stoneBeraVault.deposit(address(tokenA), 1e18, msg.sender);
        assertEq(lpToken.balanceOf(msg.sender), 1e18);

        uint256 price = 1.1 * 1e18;
        oracleB.updatePrice(price);
        assertEq(stoneBeraVault.getRate(), 1e18);

        tokenB.approve(address(stoneBeraVault), 1e18);
        stoneBeraVault.deposit(address(tokenB), 1e18, bob);
        assertEq(lpToken.balanceOf(bob), price);

        assertEq(stoneBeraVault.getRate(), 1e18);
    }

    function test_deposit_init_diff_A_price() public {
        address bob = address(0xB0B);

        uint256 price = 1.1 * 1e18;
        oracleA.updatePrice(price);

        tokenA.approve(address(stoneBeraVault), 1e18);

        stoneBeraVault.deposit(address(tokenA), 1e18, msg.sender);
        assertEq(lpToken.balanceOf(msg.sender), price);
        assertEq(stoneBeraVault.getRate(), 1e18);

        tokenB.approve(address(stoneBeraVault), 1e18);
        stoneBeraVault.deposit(address(tokenB), 1e18, bob);
        assertEq(stoneBeraVault.activeAssets(), price + 1e18);
        assertEq(stoneBeraVault.activeAssets(), stoneBeraVault.totalAssets());
        assertEq(lpToken.balanceOf(bob), 1e18);
        assertEq(stoneBeraVault.getRate(), 1e18);
    }

    function test_deposit_all_diff_A_price() public {
        address bob = address(0xB0B);

        uint256 price = 1.1 * 1e18;
        oracleA.updatePrice(price);

        tokenA.approve(address(stoneBeraVault), 1e18);

        stoneBeraVault.deposit(address(tokenA), 1e18, msg.sender);
        assertEq(lpToken.balanceOf(msg.sender), price);
        assertEq(stoneBeraVault.getRate(), 1e18);

        tokenB.approve(address(stoneBeraVault), 1e18);
        stoneBeraVault.deposit(address(tokenB), 1e18, bob);
        assertEq(stoneBeraVault.activeAssets(), price + 1e18);
        assertEq(stoneBeraVault.activeAssets(), stoneBeraVault.totalAssets());
        assertEq(lpToken.balanceOf(bob), 1e18);
        assertEq(stoneBeraVault.getRate(), 1e18);

        tokenA.approve(address(stoneBeraVault), 1e18);
        stoneBeraVault.deposit(address(tokenA), 1e18, bob);
        assertEq(lpToken.balanceOf(bob), 1e18 + price);
        assertEq(stoneBeraVault.getRate(), 1e18);

        uint256 price1 = 1.2 * 1e18;
        oracleA.updatePrice(price1);

        assertEq(lpToken.totalSupply(), (1e18 + 2 * price));
        assertEq(
            stoneBeraVault.getRate(),
            (price1 * 2e18 + 1e18 * 1e18) / (1e18 + 2 * price)
        );

        tokenA.approve(address(stoneBeraVault), 1e18);
        stoneBeraVault.deposit(address(tokenA), 1e18, bob);
        assertEq(
            stoneBeraVault.getRate(),
            (price1 * 2e18 + 1e18 * 1e18) / (1e18 + 2 * price)
        );
        assertEq(
            lpToken.balanceOf(bob),
            1e18 +
                price +
                price1.mulDiv(
                    1e18,
                    stoneBeraVault.getRate(),
                    Math.Rounding.Floor
                )
        );
    }

    function test_mint_diff_A_price() public {
        address alice = address(0xA11CE);
        address bob = address(0xB0B);

        tokenA.approve(address(stoneBeraVault), 1e18);

        stoneBeraVault.mint(address(tokenA), 1e18, msg.sender);
        assertEq(lpToken.balanceOf(msg.sender), 1e18);
        assertEq(stoneBeraVault.getRate(), 1e18);

        uint256 price = 1.1 * 1e18;
        oracleA.updatePrice(price);

        assertEq(stoneBeraVault.getRate(), price);

        tokenA.approve(address(stoneBeraVault), 1e18 + 1);
        stoneBeraVault.mint(address(tokenA), 1e18, alice);
        assertEq(lpToken.balanceOf(alice), 1e18);
        assertEq(stoneBeraVault.getRate(), price);

        tokenB.approve(address(stoneBeraVault), price + 1);
        stoneBeraVault.mint(address(tokenB), 1e18, bob);
        assertEq(lpToken.balanceOf(alice), 1e18);
        assertEq(stoneBeraVault.getRate(), price);
    }

    function test_mint_init_diff_A_price() public {
        address alice = address(0xA11CE);
        address bob = address(0xB0B);

        uint256 price = 1.1 * 1e18;
        oracleA.updatePrice(price);

        tokenA.approve(address(stoneBeraVault), price);

        stoneBeraVault.mint(address(tokenA), 1e18, msg.sender);
        assertEq(lpToken.balanceOf(msg.sender), 1e18);
        assertEq(stoneBeraVault.getRate(), 1e18);

        tokenA.approve(address(stoneBeraVault), price);
        stoneBeraVault.mint(address(tokenA), 1e18, alice);
        assertEq(lpToken.balanceOf(alice), 1e18);
        assertEq(stoneBeraVault.getRate(), 1e18);

        tokenB.approve(address(stoneBeraVault), 1e18);
        stoneBeraVault.mint(address(tokenB), 1e18, bob);
        assertEq(lpToken.balanceOf(alice), 1e18);
        assertEq(stoneBeraVault.getRate(), 1e18);
    }

    function test_cancelRequest() public {
        address alice = address(0xA11CE);

        tokenA.approve(address(stoneBeraVault), 1e18);

        stoneBeraVault.deposit(address(tokenA), 1e18, alice);
        assertEq(lpToken.balanceOf(alice), 1e18);

        assertEq(stoneBeraVault.pendingRedeemRequest(), 0);
        assertEq(stoneBeraVault.getRate(), 1e18);

        vm.startPrank(alice);

        lpToken.approve(address(stoneBeraVault), 5e17);
        stoneBeraVault.requestRedeem(5e17);
        assertEq(stoneBeraVault.pendingRedeemRequest(), 5e17);
        assertEq(stoneBeraVault.getRate(), 1e18);

        stoneBeraVault.cancelRequest();
        assertEq(stoneBeraVault.pendingRedeemRequest(), 0);
        assertEq(stoneBeraVault.getRate(), 1e18);

        vm.stopPrank();
    }

    function test_roll_basic_depositA() public {
        address alice = address(0xA11CE);

        tokenA.approve(address(stoneBeraVault), 1e18);

        stoneBeraVault.deposit(address(tokenA), 1e18, alice);
        assertEq(lpToken.balanceOf(alice), 1e18);

        vm.startPrank(alice);
        uint256 redeemAmount = 5e17;
        lpToken.approve(address(stoneBeraVault), redeemAmount);
        stoneBeraVault.requestRedeem(redeemAmount);
        assertEq(stoneBeraVault.pendingRedeemRequest(), redeemAmount);
        assertEq(lpToken.balanceOf(alice), 1e18 - 5e17);
        vm.stopPrank();

        assertEq(stoneBeraVault.getRate(), 1e18);
        assertEq(stoneBeraVault.redeemableAmountInPast(), 0);
        assertEq(stoneBeraVault.requestingSharesInRound(), redeemAmount);

        stoneBeraVault.withdrawAssets(address(tokenA), 1e18);
        tokenB.approve(address(stoneBeraVault), 1e18);
        stoneBeraVault.repayAssets(address(tokenB), 1e18);

        stoneBeraVault.rollToNextRound();

        assertEq(stoneBeraVault.roundPricePerShare(0), 1e18);
        assertEq(stoneBeraVault.withdrawTokenPrice(0), 1e18);

        vm.startPrank(alice);
        assertEq(stoneBeraVault.claimableRedeemRequest(), redeemAmount);
        assertEq(stoneBeraVault.pendingRedeemRequest(), 0);
        stoneBeraVault.claimRedeemRequest();
        assertEq(stoneBeraVault.claimableRedeemRequest(), 0);
        assertEq(stoneBeraVault.pendingRedeemRequest(), 0);
        assertEq(tokenB.balanceOf(alice), redeemAmount);
        vm.stopPrank();
    }

    function test_roll_basic_depositB() public {
        address alice = address(0xA11CE);

        tokenB.approve(address(stoneBeraVault), 1e18);

        stoneBeraVault.deposit(address(tokenB), 1e18, alice);
        assertEq(lpToken.balanceOf(alice), 1e18);

        vm.startPrank(alice);
        uint256 redeemAmount = 5e17;
        lpToken.approve(address(stoneBeraVault), redeemAmount);
        stoneBeraVault.requestRedeem(redeemAmount);
        assertEq(stoneBeraVault.pendingRedeemRequest(), redeemAmount);
        assertEq(lpToken.balanceOf(alice), 1e18 - 5e17);
        vm.stopPrank();

        assertEq(stoneBeraVault.getRate(), 1e18);
        assertEq(stoneBeraVault.redeemableAmountInPast(), 0);
        assertEq(stoneBeraVault.requestingSharesInRound(), redeemAmount);

        stoneBeraVault.rollToNextRound();

        assertEq(stoneBeraVault.roundPricePerShare(0), 1e18);
        assertEq(stoneBeraVault.withdrawTokenPrice(0), 1e18);

        vm.startPrank(alice);
        assertEq(stoneBeraVault.claimableRedeemRequest(), redeemAmount);
        assertEq(stoneBeraVault.pendingRedeemRequest(), 0);
        stoneBeraVault.claimRedeemRequest();
        assertEq(stoneBeraVault.claimableRedeemRequest(), 0);
        assertEq(stoneBeraVault.pendingRedeemRequest(), 0);
        assertEq(tokenB.balanceOf(alice), redeemAmount);
        vm.stopPrank();
    }

    function test_roll_diff_B_price() public {
        address alice = address(0xA11CE);

        tokenB.approve(address(stoneBeraVault), 1e18);

        stoneBeraVault.deposit(address(tokenB), 1e18, alice);
        assertEq(lpToken.balanceOf(alice), 1e18);

        vm.startPrank(alice);
        uint256 redeemAmount = 5e17;
        lpToken.approve(address(stoneBeraVault), redeemAmount);
        stoneBeraVault.requestRedeem(redeemAmount);
        assertEq(stoneBeraVault.pendingRedeemRequest(), redeemAmount);
        assertEq(lpToken.balanceOf(alice), 1e18 - 5e17);
        vm.stopPrank();

        assertEq(stoneBeraVault.getRate(), 1e18);
        assertEq(stoneBeraVault.redeemableAmountInPast(), 0);
        assertEq(stoneBeraVault.requestingSharesInRound(), redeemAmount);

        uint256 price = 1.1 * 1e18;
        oracleB.updatePrice(price);
        stoneBeraVault.rollToNextRound();

        assertEq(stoneBeraVault.roundPricePerShare(0), price);
        assertEq(stoneBeraVault.withdrawTokenPrice(0), price);

        vm.startPrank(alice);
        assertEq(stoneBeraVault.claimableRedeemRequest(), redeemAmount);
        assertEq(stoneBeraVault.pendingRedeemRequest(), 0);
        stoneBeraVault.claimRedeemRequest();
        assertEq(stoneBeraVault.claimableRedeemRequest(), 0);
        assertEq(stoneBeraVault.pendingRedeemRequest(), 0);
        assertEq(tokenB.balanceOf(alice), redeemAmount);
        vm.stopPrank();
    }

    function test_roll_multiple_diff_B_price() public {
        address alice = address(0xA11CE);

        tokenA.approve(address(stoneBeraVault), 1e18);
        tokenB.approve(address(stoneBeraVault), 1e18);

        stoneBeraVault.deposit(address(tokenA), 1e18, alice);
        stoneBeraVault.deposit(address(tokenB), 1e18, alice);

        assertEq(lpToken.balanceOf(alice), 2e18);

        vm.startPrank(alice);
        uint256 redeemAmount = 1e18;
        lpToken.approve(address(stoneBeraVault), redeemAmount);
        stoneBeraVault.requestRedeem(redeemAmount);
        assertEq(stoneBeraVault.pendingRedeemRequest(), redeemAmount);
        assertEq(lpToken.balanceOf(alice), 1e18);
        vm.stopPrank();

        assertEq(stoneBeraVault.getRate(), 1e18);
        assertEq(stoneBeraVault.redeemableAmountInPast(), 0);
        assertEq(stoneBeraVault.requestingSharesInRound(), redeemAmount);

        uint256 price = 1.1 * 1e18;
        oracleB.updatePrice(price);
        uint256 rate = ((price + 1e18) * 1e18) / 2e18;
        assertEq(stoneBeraVault.getRate(), rate);

        stoneBeraVault.rollToNextRound();

        assertEq(stoneBeraVault.roundPricePerShare(0), rate);
        assertEq(stoneBeraVault.withdrawTokenPrice(0), price);

        vm.startPrank(alice);
        uint256 redeemable = redeemAmount.mulDiv(
            rate,
            price,
            Math.Rounding.Floor
        );
        assertEq(stoneBeraVault.claimableRedeemRequest(), redeemable);
        assertEq(stoneBeraVault.pendingRedeemRequest(), 0);
        stoneBeraVault.claimRedeemRequest();
        assertEq(stoneBeraVault.getRate() + 1, rate);

        assertEq(stoneBeraVault.claimableRedeemRequest(), 0);
        assertEq(stoneBeraVault.pendingRedeemRequest(), 0);
        assertEq(tokenB.balanceOf(alice), redeemable);
        vm.stopPrank();
    }
}
