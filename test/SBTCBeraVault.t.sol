// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SBTCBeraVault} from "../src/SBTCBeraVault.sol";
import {Token} from "../src/Token.sol";
import {MockToken} from "./MockToken.sol";

import "../src/Errors.sol";

contract SBTCBeraVaultTest is Test {
    using Math for uint256;
    Token public lpToken;

    MockToken public tokenA;
    MockToken public tokenB;
    MockToken public tokenC;

    SBTCBeraVault public sBTCBeraVault;

    function setUp() public {
        console.log("Deployer: %s", msg.sender);

        lpToken = new Token("Vault Token", "T");
        console.log("LP Token Address: %s", address(lpToken));

        tokenA = new MockToken(18);
        tokenB = new MockToken(8);
        tokenC = new MockToken(6);

        tokenA.mint(address(this), 10000 * 1e18);
        tokenB.mint(address(this), 10000 * 1e8);
        tokenC.mint(address(this), 10000 * 1e6);

        sBTCBeraVault = new SBTCBeraVault(address(lpToken), 1000 * 1e18);
        sBTCBeraVault.grantRole(
            sBTCBeraVault.VAULT_OPERATOR_ROLE(),
            address(this)
        );
        sBTCBeraVault.grantRole(
            sBTCBeraVault.ASSETS_MANAGEMENT_ROLE(),
            address(this)
        );

        sBTCBeraVault.addUnderlyingAsset(address(tokenA));
        sBTCBeraVault.addUnderlyingAsset(address(tokenB));
        sBTCBeraVault.addUnderlyingAsset(address(tokenC));

        lpToken.grantRole(lpToken.MINTER_ROLE(), address(sBTCBeraVault));
        lpToken.grantRole(lpToken.BURNER_ROLE(), address(sBTCBeraVault));

        console.log("sBTCBeraVault Address: %s", address(sBTCBeraVault));
    }

    // function test_removeUnderlyingAsset() public {
    //     assertTrue(sBTCBeraVault.isUnderlyingAsset(address(tokenA)));
    //     assertTrue(sBTCBeraVault.isUnderlyingAsset(address(tokenB)));
    //     assertEq(sBTCBeraVault.underlyingAssets(0), address(tokenA));
    //     assertEq(sBTCBeraVault.underlyingAssets(1), address(tokenB));
    //     assertEq(sBTCBeraVault.getUnderlyings().length, 3);

    //     sBTCBeraVault.removeUnderlyingAsset(address(tokenA));
    //     assertTrue(!sBTCBeraVault.isUnderlyingAsset(address(tokenA)));
    //     assertTrue(sBTCBeraVault.isUnderlyingAsset(address(tokenB)));
    //     assertEq(sBTCBeraVault.underlyingAssets(0), address(tokenC));
    //     assertEq(sBTCBeraVault.underlyingAssets(1), address(tokenB));
    //     assertEq(sBTCBeraVault.getUnderlyings().length, 2);

    //     sBTCBeraVault.removeUnderlyingAsset(address(tokenB));
    //     assertTrue(!sBTCBeraVault.isUnderlyingAsset(address(tokenA)));
    //     assertTrue(!sBTCBeraVault.isUnderlyingAsset(address(tokenB)));
    //     assertTrue(sBTCBeraVault.isUnderlyingAsset(address(tokenC)));
    //     assertEq(sBTCBeraVault.getUnderlyings().length, 1);
    // }

    function test_deposit_basic() public {
        address user = address(1);
        vm.prank(user);
        console.log("decimal is :");
        console.logUint(sBTCBeraVault.tokenDecimals(address(tokenA)));
        tokenA.mint(user, 10000 * 1e18);
        tokenA.approve(address(sBTCBeraVault), 1e18);
        sBTCBeraVault.deposit(address(tokenA), 1e18, msg.sender);
        assertEq(lpToken.balanceOf(msg.sender), 1e18);
        vm.stopPrank();
        tokenB.approve(address(sBTCBeraVault), 2e8);
        sBTCBeraVault.deposit(address(tokenB), 2e8, address(this));
        assertEq(lpToken.balanceOf(address(this)), 2e18);
        tokenC.approve(address(sBTCBeraVault), 2e6);
        sBTCBeraVault.deposit(address(tokenC), 2e6, address(this));
        assertEq(lpToken.balanceOf(address(this)), 4e18);
    }

    // function test_deposit_capped() public {
    //     tokenA.approve(address(sBTCBeraVault), 1001 * 1e18);
    //     vm.expectRevert(DepositCapped.selector);
    //     sBTCBeraVault.deposit(address(tokenA), 1001 * 1e18, msg.sender);
    // }

    // function test_mint_basic() public {
    //     tokenA.approve(address(sBTCBeraVault), 1e18);

    //     sBTCBeraVault.mint(address(tokenA), 1e18, msg.sender);
    //     assertEq(lpToken.balanceOf(msg.sender), 1e18);

    //     tokenA.approve(address(sBTCBeraVault), 2e18);
    //     sBTCBeraVault.mint(address(tokenA), 2e18, address(this));
    //     assertEq(lpToken.balanceOf(address(this)), 2e18);
    // }

    // function test_mint_capped() public {
    //     tokenA.approve(address(sBTCBeraVault), 1001 * 1e18);

    //     vm.expectRevert(DepositCapped.selector);
    //     sBTCBeraVault.mint(address(tokenA), 1001 * 1e18, msg.sender);
    // }

    // function test_roll_with_no_request() public {
    //     tokenA.approve(address(sBTCBeraVault), 1e18);
    //     sBTCBeraVault.deposit(address(tokenA), 1e18, msg.sender);
    //     sBTCBeraVault.rollToNextRound();
    //     assertEq(lpToken.balanceOf(msg.sender), 1e18);
    // }

    // function test_cancelRequest() public {
    //     address alice = address(0xA11CE);

    //     tokenA.approve(address(sBTCBeraVault), 1e18);

    //     sBTCBeraVault.deposit(address(tokenA), 1e18, alice);
    //     assertEq(lpToken.balanceOf(alice), 1e18);
    //     (address requestToken, uint256 shares) = sBTCBeraVault
    //         .pendingRedeemRequest();
    //     assertEq(shares, 0);

    //     vm.startPrank(alice);

    //     lpToken.approve(address(sBTCBeraVault), 5e17);
    //     sBTCBeraVault.requestRedeem(address(tokenA), 5e17);
    //     (requestToken, shares) = sBTCBeraVault.pendingRedeemRequest();
    //     assertEq(shares, 5e17);

    //     sBTCBeraVault.cancelRequest();
    //     (requestToken, shares) = sBTCBeraVault.pendingRedeemRequest();
    //     assertEq(shares, 0);

    //     lpToken.approve(address(sBTCBeraVault), 5e17);
    //     sBTCBeraVault.requestRedeem(address(tokenA), 5e17);
    //     (requestToken, shares) = sBTCBeraVault.pendingRedeemRequest();
    //     assertEq(shares, 5e17);
    //     vm.stopPrank();
    // }

    // function test_roll_basic_depositA_withdrawB() public {
    //     address alice = address(0xA11CE);

    //     tokenA.approve(address(sBTCBeraVault), 1e18);

    //     sBTCBeraVault.deposit(address(tokenA), 1e18, alice);
    //     assertEq(lpToken.balanceOf(alice), 1e18);

    //     vm.startPrank(alice);
    //     uint256 redeemAmount = 5e17;
    //     lpToken.approve(address(sBTCBeraVault), redeemAmount);
    //     sBTCBeraVault.requestRedeem(address(tokenB), redeemAmount);
    //     (address requestToken, uint256 shares) = sBTCBeraVault
    //         .pendingRedeemRequest();
    //     assertEq(shares, redeemAmount);
    //     assertEq(lpToken.balanceOf(alice), 1e18 - 5e17);
    //     vm.stopPrank();

    //     assertEq(sBTCBeraVault.redeemableAmountInPast(address(tokenB)), 0);
    //     assertEq(
    //         sBTCBeraVault.requestingSharesInRound(address(tokenB)),
    //         redeemAmount
    //     );

    //     sBTCBeraVault.withdrawAssets(address(tokenA), 1e18);
    //     tokenB.approve(address(sBTCBeraVault), 1e8);
    //     sBTCBeraVault.repayAssets(address(tokenB), 1e8);

    //     sBTCBeraVault.rollToNextRound();

    //     vm.startPrank(alice);
    //     uint256 claimable;
    //     (requestToken, claimable) = sBTCBeraVault.claimableRedeemRequest();
    //     assertEq(claimable, redeemAmount);

    //     (requestToken, shares) = sBTCBeraVault.pendingRedeemRequest();
    //     assertEq(shares, 0);
    //     sBTCBeraVault.claimRedeemRequest();
    //     (requestToken, claimable) = sBTCBeraVault.claimableRedeemRequest();
    //     assertEq(claimable, 0);
    //     (requestToken, shares) = sBTCBeraVault.pendingRedeemRequest();
    //     assertEq(shares, 0);
    //     assertEq(tokenB.balanceOf(alice), redeemAmount);
    //     vm.stopPrank();
    // }

    // function testMultipleTokenRequestsInSameRound() public {
    //     tokenA.approve(address(sBTCBeraVault), 1e18);
    //     sBTCBeraVault.deposit(address(tokenA), 1e18, address(this));
    //     tokenB.approve(address(sBTCBeraVault), 2e8);
    //     sBTCBeraVault.deposit(address(tokenB), 2e8, address(this));

    //     sBTCBeraVault.requestRedeem(address(tokenA), 4e17);
    //     console.log("pendingRedeemRequest is...");
    //     (address requestToken, uint256 shares) = sBTCBeraVault
    //         .pendingRedeemRequest();
    //     console.logUint(shares);
    //     sBTCBeraVault.requestRedeem(address(tokenB), 1e8);
    //     console.log("pendingRedeemRequest is...");
    //     (requestToken, shares) = sBTCBeraVault.pendingRedeemRequest();
    //     console.logUint(shares);

    //     // 断言 redeemRequest.requests 数组的长度为 2
    //     // 断言 redeemRequest.requests[0].token 等于 token1
    //     // 断言 redeemRequest.requests[0].shares 等于 100
    //     // ... 其他断言
    // }
}
