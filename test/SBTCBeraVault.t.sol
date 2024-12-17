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
    uint256 cap = 100 * 1e18; // Set a cap for the vault

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

        sBTCBeraVault = new SBTCBeraVault(address(lpToken), cap);
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

        sBTCBeraVault.addWithdrawToken(address(tokenA));
        sBTCBeraVault.addWithdrawToken(address(tokenC));

        lpToken.grantRole(lpToken.MINTER_ROLE(), address(sBTCBeraVault));
        lpToken.grantRole(lpToken.BURNER_ROLE(), address(sBTCBeraVault));

        console.log("sBTCBeraVault Address: %s", address(sBTCBeraVault));
    }
    function test_addUnderlyingAsset() public {
        address user = address(1);
        vm.startPrank(user);
        vm.expectRevert();
        sBTCBeraVault.addUnderlyingAsset(address(tokenC));
        vm.stopPrank();
        sBTCBeraVault.grantRole(sBTCBeraVault.ASSETS_MANAGEMENT_ROLE(), user);
        vm.expectRevert();
        vm.startPrank(user);
        sBTCBeraVault.addUnderlyingAsset(address(tokenC));
        vm.stopPrank();

        assertTrue(sBTCBeraVault.isUnderlyingAsset(address(tokenA)));
        assertTrue(sBTCBeraVault.isUnderlyingAsset(address(tokenB)));
        assertEq(sBTCBeraVault.underlyingAssets(0), address(tokenA));
        assertEq(sBTCBeraVault.underlyingAssets(1), address(tokenB));
        assertEq(sBTCBeraVault.getUnderlyings().length, 2);

        sBTCBeraVault.addUnderlyingAsset(address(tokenC));
        assertTrue(sBTCBeraVault.isUnderlyingAsset(address(tokenC)));
        assertEq(sBTCBeraVault.underlyingAssets(2), address(tokenC));
        vm.expectRevert(InvalidAsset.selector);
        sBTCBeraVault.addUnderlyingAsset(address(0));
        vm.expectRevert(InvalidAsset.selector);
        sBTCBeraVault.addUnderlyingAsset(address(tokenA));
        MockToken tokenD = new MockToken(19);
        vm.expectRevert(InvalidDecimals.selector);
        sBTCBeraVault.addUnderlyingAsset(address(tokenD));
        assertEq(sBTCBeraVault.getUnderlyings().length, 3);
        assertEq(sBTCBeraVault.tokenDecimals(address(tokenA)), 18);
        assertEq(sBTCBeraVault.tokenDecimals(address(tokenB)), 8);
        assertEq(sBTCBeraVault.tokenDecimals(address(tokenC)), 6);
    }
    function test_addWithdrawToken() public {
        address user = address(1);
        vm.startPrank(user);
        vm.expectRevert();
        sBTCBeraVault.addWithdrawToken(address(tokenC));
        vm.stopPrank();
        sBTCBeraVault.grantRole(sBTCBeraVault.ASSETS_MANAGEMENT_ROLE(), user);
        vm.expectRevert();
        vm.startPrank(user);
        sBTCBeraVault.addWithdrawToken(address(tokenC));
        vm.stopPrank();

        assertTrue(sBTCBeraVault.isWithdrawToken(address(tokenA)));
        assertTrue(!sBTCBeraVault.isWithdrawToken(address(tokenB)));
        assertTrue(sBTCBeraVault.isWithdrawToken(address(tokenC)));

        assertEq(sBTCBeraVault.withdrawTokens(0), address(tokenA));
        assertEq(sBTCBeraVault.withdrawTokens(1), address(tokenC));

        sBTCBeraVault.addWithdrawToken(address(tokenB));
        assertTrue(sBTCBeraVault.isWithdrawToken(address(tokenB)));
        assertEq(sBTCBeraVault.withdrawTokens(2), address(tokenB));
        vm.expectRevert(InvalidAsset.selector);
        sBTCBeraVault.addWithdrawToken(address(0));
        vm.expectRevert(InvalidAsset.selector);
        sBTCBeraVault.addWithdrawToken(address(tokenA));
    }

    function test_removeUnderlyingAsset() public {
        sBTCBeraVault.addUnderlyingAsset(address(tokenC));

        address user = address(1);
        vm.startPrank(user);
        vm.expectRevert();
        sBTCBeraVault.removeUnderlyingAsset(address(tokenA));
        vm.stopPrank();
        sBTCBeraVault.grantRole(sBTCBeraVault.ASSETS_MANAGEMENT_ROLE(), user);
        vm.expectRevert();
        vm.startPrank(user);
        sBTCBeraVault.removeUnderlyingAsset(address(tokenA));
        vm.stopPrank();

        sBTCBeraVault.removeUnderlyingAsset(address(tokenA));
        assertTrue(!sBTCBeraVault.isUnderlyingAsset(address(tokenA)));
        assertTrue(sBTCBeraVault.isUnderlyingAsset(address(tokenB)));
        assertEq(sBTCBeraVault.underlyingAssets(0), address(tokenC));
        assertEq(sBTCBeraVault.underlyingAssets(1), address(tokenB));
        assertEq(sBTCBeraVault.getUnderlyings().length, 2);

        sBTCBeraVault.removeUnderlyingAsset(address(tokenB));
        assertTrue(!sBTCBeraVault.isUnderlyingAsset(address(tokenA)));
        assertTrue(!sBTCBeraVault.isUnderlyingAsset(address(tokenB)));
        assertTrue(sBTCBeraVault.isUnderlyingAsset(address(tokenC)));
        assertEq(sBTCBeraVault.getUnderlyings().length, 1);
        vm.expectRevert(InvalidAsset.selector);
        sBTCBeraVault.removeUnderlyingAsset(address(tokenA));
    }
    function test_removeWithdrawToken() public {
        address user = address(1);
        vm.startPrank(user);
        vm.expectRevert();
        sBTCBeraVault.removeWithdrawToken(address(tokenA));
        vm.stopPrank();
        sBTCBeraVault.grantRole(sBTCBeraVault.ASSETS_MANAGEMENT_ROLE(), user);
        vm.expectRevert();
        vm.startPrank(user);
        sBTCBeraVault.removeWithdrawToken(address(tokenA));
        vm.stopPrank();

        sBTCBeraVault.addWithdrawToken(address(tokenB));
        sBTCBeraVault.removeWithdrawToken(address(tokenA));
        assertTrue(!sBTCBeraVault.isWithdrawToken(address(tokenA)));
        assertTrue(sBTCBeraVault.isWithdrawToken(address(tokenB)));
        assertTrue(sBTCBeraVault.isWithdrawToken(address(tokenC)));

        assertEq(sBTCBeraVault.withdrawTokens(0), address(tokenB));
        assertEq(sBTCBeraVault.withdrawTokens(1), address(tokenC));

        sBTCBeraVault.removeWithdrawToken(address(tokenB));
        assertTrue(!sBTCBeraVault.isWithdrawToken(address(tokenA)));
        assertTrue(!sBTCBeraVault.isWithdrawToken(address(tokenB)));
        assertTrue(sBTCBeraVault.isWithdrawToken(address(tokenC)));
        vm.expectRevert(InvalidAsset.selector);
        sBTCBeraVault.removeWithdrawToken(address(tokenA));

        //if (requestingSharesInRound[_withdrawToken] != 0) revert CannotRemove();
        tokenA.approve(address(sBTCBeraVault), 1e18);
        sBTCBeraVault.deposit(address(tokenA), 1e18, address(this));
        lpToken.approve(address(sBTCBeraVault), 1e18);
        sBTCBeraVault.requestRedeem(address(tokenC), 1e18);
        vm.expectRevert(CannotRemove.selector);
        sBTCBeraVault.removeWithdrawToken(address(tokenC));
    }

    function test_deposit_basic() public {
        address user = address(1);
        vm.startPrank(user);
        assertEq(sBTCBeraVault.tokenDecimals(address(tokenA)), 18);
        tokenA.mint(user, 10000 * 1e18);
        tokenA.approve(address(sBTCBeraVault), 1e18);
        sBTCBeraVault.deposit(address(tokenA), 1e18, msg.sender);
        assertEq(lpToken.balanceOf(msg.sender), 1e18);
        assertEq(tokenA.balanceOf(user), 9999 * 1e18);

        vm.stopPrank();
        tokenB.approve(address(sBTCBeraVault), 2e8);
        sBTCBeraVault.deposit(address(tokenB), 2e8, address(this));
        assertEq(lpToken.balanceOf(address(this)), 2e18);
        assertEq(tokenB.balanceOf(address(this)), 9998 * 1e8);

        tokenC.approve(address(sBTCBeraVault), 2e6);
        vm.expectRevert(InvalidAsset.selector);
        sBTCBeraVault.deposit(address(tokenC), 2e6, address(this));
        assertEq(lpToken.balanceOf(address(this)), 2e18);
        assertEq(tokenC.balanceOf(address(this)), 10000 * 1e6);
    }

    function test_mint_basic() public {
        tokenA.approve(address(sBTCBeraVault), 1e18);

        sBTCBeraVault.mint(address(tokenA), 1e18, msg.sender);
        assertEq(lpToken.balanceOf(msg.sender), 1e18);

        tokenA.approve(address(sBTCBeraVault), 2e18);
        sBTCBeraVault.mint(address(tokenA), 2e18, address(this));
        assertEq(lpToken.balanceOf(address(this)), 2e18);
    }

    function test_mint_capped() public {
        tokenA.approve(address(sBTCBeraVault), 1001 * 1e18);

        vm.expectRevert(DepositCapped.selector);
        sBTCBeraVault.mint(address(tokenA), 1001 * 1e18, msg.sender);
    }

    function test_roll_with_no_request() public {
        tokenA.approve(address(sBTCBeraVault), 1e18);
        sBTCBeraVault.deposit(address(tokenA), 1e18, msg.sender);
        address user = address(1);
        vm.startPrank(user);
        vm.expectRevert();
        sBTCBeraVault.rollToNextRound();
        vm.stopPrank();
        sBTCBeraVault.grantRole(
            sBTCBeraVault.ASSETS_MANAGEMENT_ROLE(),
            address(user)
        );
        vm.expectRevert();
        vm.startPrank(user);
        sBTCBeraVault.rollToNextRound();
        vm.stopPrank();
        sBTCBeraVault.rollToNextRound();
        assertEq(lpToken.balanceOf(msg.sender), 1e18);
    }

    function test_cancelRequest() public {
        vm.expectRevert(NoRequestingShares.selector);
        sBTCBeraVault.cancelRequest();
        address alice = address(0xA11CE);
        tokenA.approve(address(sBTCBeraVault), 1e18);

        sBTCBeraVault.deposit(address(tokenA), 1e18, alice);
        assertEq(lpToken.balanceOf(alice), 1e18);
        (address requestToken, uint256 shares) = sBTCBeraVault
            .pendingRedeemRequest();
        assertEq(shares, 0);

        vm.startPrank(alice);

        lpToken.approve(address(sBTCBeraVault), 5e17);
        sBTCBeraVault.requestRedeem(address(tokenA), 5e17);
        vm.expectRevert(NoClaimableRedeem.selector);
        sBTCBeraVault.claimRedeemRequest();
        (requestToken, shares) = sBTCBeraVault.pendingRedeemRequest();
        assertEq(shares, 5e17);

        sBTCBeraVault.cancelRequest();
        (requestToken, shares) = sBTCBeraVault.pendingRedeemRequest();
        assertEq(shares, 0);

        lpToken.approve(address(sBTCBeraVault), 5e17);
        sBTCBeraVault.requestRedeem(address(tokenA), 5e17);
        (requestToken, shares) = sBTCBeraVault.pendingRedeemRequest();
        assertEq(shares, 5e17);
        vm.stopPrank();
    }

    function test_roll_basic_depositA_withdrawC() public {
        address alice = address(0xA11CE);

        tokenA.approve(address(sBTCBeraVault), 1e18);
        sBTCBeraVault.deposit(address(tokenA), 1e18, alice);
        assertEq(lpToken.balanceOf(alice), 1e18);
        vm.expectRevert(InsufficientBalance.selector);
        sBTCBeraVault.withdrawAssets(address(tokenA), 2e18);
        vm.expectRevert();
        vm.startPrank(alice);
        sBTCBeraVault.withdrawAssets(address(tokenA), 2e18);
        vm.stopPrank();
        sBTCBeraVault.grantRole(
            sBTCBeraVault.VAULT_OPERATOR_ROLE(),
            address(alice)
        );
        vm.expectRevert();
        vm.startPrank(alice);
        sBTCBeraVault.withdrawAssets(address(tokenA), 2e18);
        vm.stopPrank();
        //manager withdraws A and repay B+C
        sBTCBeraVault.withdrawAssets(address(tokenA), 1e18);
        tokenB.approve(address(sBTCBeraVault), 1e8);
        tokenC.approve(address(sBTCBeraVault), 1e8);
        vm.startPrank(alice);
        vm.expectRevert();
        sBTCBeraVault.repayAssets(address(tokenB), 5e7);
        vm.stopPrank();
        sBTCBeraVault.grantRole(
            sBTCBeraVault.VAULT_OPERATOR_ROLE(),
            address(alice)
        );
        vm.expectRevert();
        vm.startPrank(alice);
        sBTCBeraVault.repayAssets(address(tokenB), 5e7);
        vm.stopPrank();

        sBTCBeraVault.repayAssets(address(tokenB), 5e7);
        vm.expectRevert(InvalidAsset.selector);
        sBTCBeraVault.repayAssets(address(tokenC), 5e5);
        sBTCBeraVault.addUnderlyingAsset(address(tokenC));
        sBTCBeraVault.repayAssets(address(tokenC), 5e5);

        //user starts request redeem
        vm.startPrank(alice);
        uint256 redeemAmount = 5e17;
        lpToken.approve(address(sBTCBeraVault), redeemAmount);
        vm.expectRevert(InvalidRequestToken.selector);
        sBTCBeraVault.requestRedeem(address(tokenB), redeemAmount);
        sBTCBeraVault.requestRedeem(address(tokenC), redeemAmount);

        (address requestToken, uint256 shares) = sBTCBeraVault
            .pendingRedeemRequest();
        assertEq(shares, redeemAmount);
        assertEq(lpToken.balanceOf(alice), 1e18 - 5e17);
        vm.stopPrank();

        assertEq(sBTCBeraVault.redeemableAmountInPast(address(tokenC)), 0);
        assertEq(
            sBTCBeraVault.requestingSharesInRound(address(tokenC)),
            redeemAmount
        );
        sBTCBeraVault.rollToNextRound();

        vm.startPrank(alice);
        uint256 claimable;
        (requestToken, claimable) = sBTCBeraVault.claimableRedeemRequest();
        assertEq(claimable, redeemAmount / 1e12);
        assertEq(requestToken, address(tokenC));

        (requestToken, shares) = sBTCBeraVault.pendingRedeemRequest();
        assertEq(shares, 0);
        sBTCBeraVault.claimRedeemRequest();
        (requestToken, claimable) = sBTCBeraVault.claimableRedeemRequest();
        assertEq(claimable, 0);
        (requestToken, shares) = sBTCBeraVault.pendingRedeemRequest();
        assertEq(shares, 0);

        uint256 balance = tokenC.balanceOf(alice);
        assertEq(balance, redeemAmount / 1e12);
        vm.stopPrank();
    }
    function test_multipleRedeemRequestsOneRound_sameToken() public {
        address user = address(1);
        tokenA.mint(user, 10000 * 1e18);
        // User deposits some tokens and requests redeem twice
        vm.startPrank(user);
        // Ensure approval before deposit
        tokenA.approve(address(sBTCBeraVault), 5e18); // Approve the correct amount
        sBTCBeraVault.deposit(address(tokenA), 5e18, user);
        lpToken.approve(address(sBTCBeraVault), 5e18);
        sBTCBeraVault.requestRedeem(address(tokenA), 3e18); // First redeem request
        sBTCBeraVault.requestRedeem(address(tokenA), 2e18); // Second redeem request (same token)

        // Check pending redeem request (should have 5e18 requested)
        (address requestToken, uint256 shares) = sBTCBeraVault
            .pendingRedeemRequest();
        assertEq(shares, 5e18);
        // Should not be allowed to request a different token in the same round
        vm.expectRevert(InvalidRequestToken.selector);
        sBTCBeraVault.requestRedeem(address(tokenB), 1e8);
        vm.stopPrank();
        // Roll to the next round
        sBTCBeraVault.rollToNextRound();

        // Check the redeemable amount after the round ends
        uint256 redeemableAmount = sBTCBeraVault.redeemableAmountInPast(
            address(tokenA)
        );
        assertEq(redeemableAmount, 5e18);
        vm.startPrank(user);
        uint256 claimable;
        // Claim the redeem request
        (requestToken, claimable) = sBTCBeraVault.claimableRedeemRequest();
        assertEq(claimable, 5e18); // The amount to be claimed should be the total requested
        // Execute the claim
        uint256 userBalance = tokenA.balanceOf(user);
        sBTCBeraVault.claimRedeemRequest();
        // Check user balance after claiming
        uint256 userBalance2 = tokenA.balanceOf(user);
        assertEq(userBalance2 - userBalance, 5e18); // User should receive the full amount of tokenA they requested
    }

    function test_multipleRedeemRequestsMultipleRounds_sameToken() public {
        address user = address(1);
        tokenA.mint(user, 10000 * 1e18);
        // User deposits tokens and makes a redeem request in round 1
        vm.startPrank(user);
        tokenA.approve(address(sBTCBeraVault), 5e18);
        sBTCBeraVault.deposit(address(tokenA), 5e18, user);

        lpToken.approve(address(sBTCBeraVault), 5e18);
        sBTCBeraVault.requestRedeem(address(tokenA), 2e18); // Round 1 redeem request
        vm.stopPrank();
        // Move to next round and request another redeem
        sBTCBeraVault.rollToNextRound();
        vm.startPrank(user);
        (address requestToken, uint256 claimable) = sBTCBeraVault
            .claimableRedeemRequest();
        assertEq(claimable, 2e18);
        lpToken.approve(address(sBTCBeraVault), 3e18);
        sBTCBeraVault.requestRedeem(address(tokenA), 3e18); // Round 2 redeem request
        (requestToken, claimable) = sBTCBeraVault.claimableRedeemRequest();
        assertEq(claimable, 0);
        vm.stopPrank();
        // Move to next round and claim both requests
        sBTCBeraVault.rollToNextRound();
        // Ensure both requests are claimable
        vm.startPrank(user);
        (requestToken, claimable) = sBTCBeraVault.claimableRedeemRequest();
        assertEq(claimable, 3e18);
        uint256 userBalance = tokenA.balanceOf(user);
        sBTCBeraVault.claimRedeemRequest();
        uint256 userBalance2 = tokenA.balanceOf(user);
        assertEq(userBalance2 - userBalance, 3e18);
        (requestToken, claimable) = sBTCBeraVault.claimableRedeemRequest();
        assertEq(claimable, 0);
        vm.stopPrank();
    }
    function test_multipleRedeemRequestsDifferentTokensNotAllowed() public {
        address user = address(1);
        tokenA.mint(user, 10000 * 1e18);
        tokenB.mint(user, 10000 * 1e8);
        vm.startPrank(user);
        tokenA.approve(address(sBTCBeraVault), 5e18);
        tokenB.approve(address(sBTCBeraVault), 2e8);
        // User deposits both tokens and requests redeem for each token in round 1
        sBTCBeraVault.deposit(address(tokenA), 5e18, user);
        sBTCBeraVault.deposit(address(tokenB), 2e8, user);

        lpToken.approve(address(sBTCBeraVault), 5e18);
        sBTCBeraVault.requestRedeem(address(tokenA), 2e18); // Request tokenA redeem
        vm.expectRevert(InvalidRequestToken.selector);
        sBTCBeraVault.requestRedeem(address(tokenB), 1e8); // Request tokenB redeem
        vm.stopPrank();
    }
    function test_multipleRoundsRedeemDifferentTokens() public {
        sBTCBeraVault.addUnderlyingAsset(address(tokenC));
        sBTCBeraVault.addWithdrawToken(address(tokenB));
        address user = address(1);
        vm.startPrank(user);
        tokenA.mint(user, 100 * 1e18);
        tokenB.mint(user, 100 * 1e8);
        tokenC.mint(user, 100 * 1e6);

        tokenA.approve(address(sBTCBeraVault), 5e18);
        tokenB.approve(address(sBTCBeraVault), 5e8);
        tokenC.approve(address(sBTCBeraVault), 5e6);

        sBTCBeraVault.deposit(address(tokenA), 5e18, user);
        sBTCBeraVault.deposit(address(tokenB), 5e8, user);
        sBTCBeraVault.deposit(address(tokenC), 5e6, user);

        // User makes a redeem request for tokenA in round 1
        lpToken.approve(address(sBTCBeraVault), 5e18);
        sBTCBeraVault.requestRedeem(address(tokenA), 2e18); // Round 1 redeem request
        vm.stopPrank();
        // Move to the next round and request redeem for tokenB
        sBTCBeraVault.rollToNextRound();
        vm.startPrank(user);
        uint256 userBalance = tokenA.balanceOf(user);
        (address requestToken, uint256 claimable) = sBTCBeraVault
            .claimableRedeemRequest();
        assertEq(requestToken, address(tokenA));
        assertEq(claimable, 2e18);

        lpToken.approve(address(sBTCBeraVault), 5e18);
        sBTCBeraVault.requestRedeem(address(tokenB), 3e18); // Round 2 redeem request

        //TokenA is paid to user after Round 2 redeem request
        uint256 userBalance2 = tokenA.balanceOf(user);
        assertEq(userBalance2 - userBalance, 2e18);
        //only tokenB is pending to pay
        uint256 shares;
        (requestToken, shares) = sBTCBeraVault.pendingRedeemRequest();
        assertEq(requestToken, address(tokenB));
        assertEq(shares, 3e18);
        vm.stopPrank();
        // Move to the next round and request redeem for tokenC
        sBTCBeraVault.rollToNextRound();
        vm.startPrank(user);
        uint256 userBalance3 = tokenB.balanceOf(user);
        lpToken.approve(address(sBTCBeraVault), 5e18);
        console.log(
            "After redeem request, tokenC balance:",
            tokenC.balanceOf(user)
        );
        (requestToken, claimable) = sBTCBeraVault.claimableRedeemRequest();
        assertEq(requestToken, address(tokenB));
        assertEq(claimable, 3e8);

        sBTCBeraVault.requestRedeem(address(tokenC), 1e18); // Round 3 redeem request
        console.log(
            "After1 redeem request, tokenC balance:",
            tokenC.balanceOf(user)
        );

        //TokenA is paid to user after Round 2 redeem request
        uint256 userBalance4 = tokenB.balanceOf(user);
        assertEq(userBalance4 - userBalance3, 3e8);
        //only tokenC is pending to pay
        (requestToken, shares) = sBTCBeraVault.pendingRedeemRequest();
        assertEq(requestToken, address(tokenC));
        assertEq(shares, 1e18);
        vm.stopPrank();
        // Move to the next round and claim the redeem requests
        sBTCBeraVault.rollToNextRound();
        vm.startPrank(user);
        uint256 userBalance5 = tokenC.balanceOf(user);
        // Claim tokenA redeem request
        (requestToken, claimable) = sBTCBeraVault.claimableRedeemRequest();
        assertEq(requestToken, address(tokenC));
        assertEq(claimable, 1e6);
        sBTCBeraVault.claimRedeemRequest();
        uint256 userBalance6 = tokenC.balanceOf(user);
        assertEq(userBalance6 - userBalance5, 1e6);

        // Verify the balances of the user for each token
        uint256 balanceTokenA = tokenA.balanceOf(user);
        uint256 balanceTokenB = tokenB.balanceOf(user);
        uint256 balanceTokenC = tokenC.balanceOf(user);

        // User should have received the full amount they requested for each token
        assertEq(balanceTokenA, 97e18); //100-5+2
        assertEq(balanceTokenB, 98e8); //100-5+3
        assertEq(balanceTokenC, 96e6); //100-5+1

        vm.stopPrank();
    }
    function test_rollToNextRound_InsufficientBalance() public {
        address user1 = address(1);
        address user2 = address(2);

        // Mint tokens for both users
        tokenA.mint(user1, 4e18); // User 1: 4 tokenA
        tokenB.mint(user1, 6e8); // User 1: 6 tokenB
        tokenA.mint(user2, 5e18); // User 2: 5 tokenA

        // Approve the vault to spend tokens for both users
        vm.startPrank(user1);
        tokenA.approve(address(sBTCBeraVault), 4e18);
        tokenB.approve(address(sBTCBeraVault), 6e8);
        lpToken.approve(address(sBTCBeraVault), 5e18); // Approve LP token for the vault to use
        sBTCBeraVault.deposit(address(tokenA), 4e18, user1);
        sBTCBeraVault.deposit(address(tokenB), 6e8, user1);
        vm.stopPrank();

        vm.startPrank(user2);
        tokenA.approve(address(sBTCBeraVault), 5e18);
        lpToken.approve(address(sBTCBeraVault), 5e18); // Approve LP token for the vault to use
        sBTCBeraVault.deposit(address(tokenA), 5e18, user2);
        vm.stopPrank();

        // User 1 requests to redeem tokenA (5e18), more than they have in vault
        vm.startPrank(user1);
        sBTCBeraVault.requestRedeem(address(tokenA), 5e18); // First redeem request (exceeds available balance)
        vm.stopPrank();

        // Execute rollToNextRound by address(this)
        sBTCBeraVault.rollToNextRound(); // Move to the next round

        // User 2 requests to redeem tokenA (5e18)
        vm.startPrank(user2);
        sBTCBeraVault.requestRedeem(address(tokenA), 5e18); // Second redeem request
        vm.stopPrank();

        // Execute rollToNextRound again (this should fail due to insufficient balance in the vault)
        vm.expectRevert(InsufficientBalance.selector);
        sBTCBeraVault.rollToNextRound(); // Expect revert due to insufficient balance
    }
    function test_withdrawAssets_InsufficientBalance() public {
        address user = address(1);
        // Mint tokens for the user
        tokenA.mint(user, 4e18); // User: 4 tokenA
        tokenB.mint(user, 6e8); // User: 6 tokenB

        // Approve the vault to spend tokens
        vm.startPrank(user);
        tokenA.approve(address(sBTCBeraVault), 4e18);
        tokenB.approve(address(sBTCBeraVault), 6e8);
        lpToken.approve(address(sBTCBeraVault), 100e18); // Approve LP token for the vault to use

        // Deposit tokenA and tokenB into the vault
        sBTCBeraVault.deposit(address(tokenA), 4e18, user); // Deposit tokenA: 4e18
        sBTCBeraVault.deposit(address(tokenB), 6e8, user); // Deposit tokenB: 6e8
        vm.stopPrank();

        // Execute rollToNextRound (as address(this)) to transition to the next round
        sBTCBeraVault.rollToNextRound(); // Transition to next round

        // User makes a redeem request for tokenA (requesting 5e18, which exceeds the balance)
        vm.startPrank(user);
        sBTCBeraVault.requestRedeem(address(tokenA), 3e18); // User requests to redeem 5e18 of tokenA
        vm.stopPrank();
        address assetManager = address(2);
        sBTCBeraVault.grantRole(
            sBTCBeraVault.ASSETS_MANAGEMENT_ROLE(),
            assetManager
        );
        sBTCBeraVault.rollToNextRound(); // Transition to next round
        //assetManager withdraw
        vm.startPrank(assetManager);
        sBTCBeraVault.withdrawAssets(address(tokenA), 1e18); // success

        vm.expectRevert(InsufficientBalance.selector); // Expect revert due to insufficient balance
        // Attempt to withdraw tokenA, but redeemableAmountInPast[tokenA] + amount exceeds the balance
        sBTCBeraVault.withdrawAssets(address(tokenA), 1e18); // Trying to withdraw,but balance < redeemableAmountInPast[_asset] + _amount
        assertEq(tokenA.balanceOf(address(sBTCBeraVault)), 3e18);
        assertEq(tokenA.balanceOf(assetManager), 1e18);
    }

    function test_deposit_capped() public {
        tokenA.approve(address(sBTCBeraVault), 1001 * 1e18);
        vm.expectRevert(DepositCapped.selector);
        sBTCBeraVault.deposit(address(tokenA), 1001 * 1e18, msg.sender);
    }

    function test_depositCappedException() public {
        tokenA.approve(address(sBTCBeraVault), 1000 * 1e18);
        sBTCBeraVault.deposit(address(tokenA), 100e18, address(this)); // Attempt to deposit
        vm.expectRevert(DepositCapped.selector); // Expect the DepositCapped revert
        sBTCBeraVault.deposit(address(tokenA), 1e18, address(this)); // Attempt to deposit
        vm.expectRevert(ZeroShares.selector);
        sBTCBeraVault.deposit(address(tokenA), 0, address(this)); // Attempt to deposit
    }

    // Test for Mint Capped Exception
    function test_mintCappedException() public {
        tokenA.approve(address(sBTCBeraVault), 1000 * 1e18);
        sBTCBeraVault.mint(address(tokenA), 100e18, address(this)); // Attempt to mint
        vm.expectRevert(DepositCapped.selector); // Expect the DepositCapped revert
        sBTCBeraVault.mint(address(tokenA), 1e18, address(this)); // Attempt to mint
        vm.expectRevert(ZeroShares.selector);
        sBTCBeraVault.mint(address(tokenA), 0, address(this)); // Attempt to mint
    }

    // Test for Preview Deposit Capped Exception
    function test_previewDepositCappedException() public {
        tokenA.approve(address(sBTCBeraVault), 1000 * 1e18);
        address user = address(1);
        vm.startPrank(user);
        vm.expectRevert();
        sBTCBeraVault.setDepositPause(address(tokenA), true);
        vm.stopPrank();
        sBTCBeraVault.grantRole(sBTCBeraVault.ASSETS_MANAGEMENT_ROLE(), user);
        vm.expectRevert();
        vm.startPrank(user);
        sBTCBeraVault.setDepositPause(address(tokenA), true);
        vm.stopPrank();

        sBTCBeraVault.setDepositPause(address(tokenA), true);
        //test DepositPause
        vm.expectRevert(DepositPaused.selector);
        sBTCBeraVault.previewDeposit(address(tokenA), 1e18);
        sBTCBeraVault.setDepositPause(address(tokenA), false);
        sBTCBeraVault.previewDeposit(address(tokenA), 1e18);
        //test UnderlyingAsset
        sBTCBeraVault.removeUnderlyingAsset(address(tokenA));
        vm.expectRevert(InvalidAsset.selector);
        sBTCBeraVault.previewDeposit(address(tokenA), 1e18);
        sBTCBeraVault.addUnderlyingAsset(address(tokenA));
        //test cap
        sBTCBeraVault.deposit(address(tokenA), 100e18, address(this)); // Attempt to deposit
        vm.expectRevert(DepositCapped.selector); // Expect the DepositCapped revert
        sBTCBeraVault.previewDeposit(address(tokenA), 1e18);
    }

    // Test for Preview Mint Exception
    function test_previewMintException() public {
        tokenA.approve(address(sBTCBeraVault), 1000 * 1e18);
        sBTCBeraVault.setDepositPause(address(tokenA), true);
        //test DepositPause
        vm.expectRevert(DepositPaused.selector);
        sBTCBeraVault.previewMint(address(tokenA), 1e18);
        sBTCBeraVault.setDepositPause(address(tokenA), false);
        sBTCBeraVault.previewMint(address(tokenA), 1e18);
        //test UnderlyingAsset
        sBTCBeraVault.removeUnderlyingAsset(address(tokenA));
        vm.expectRevert(InvalidAsset.selector);
        sBTCBeraVault.previewMint(address(tokenA), 1e18);
        sBTCBeraVault.addUnderlyingAsset(address(tokenA));
        //test cap
        sBTCBeraVault.deposit(address(tokenA), 100e18, address(this)); // Attempt to deposit
        vm.expectRevert(DepositCapped.selector); // Expect the DepositCapped revert
        sBTCBeraVault.previewMint(address(tokenA), 1e18);
    }

    // Test for Set Cap and Ensure it Works
    function test_setCap() public {
        uint256 newCap = 20000 * 1e18; // Set a new cap for the vault
        address user = address(1);
        vm.startPrank(user);
        vm.expectRevert();
        sBTCBeraVault.setCap(newCap);
        vm.stopPrank();
        sBTCBeraVault.grantRole(sBTCBeraVault.ASSETS_MANAGEMENT_ROLE(), user);
        vm.expectRevert();
        vm.startPrank(user);
        sBTCBeraVault.setCap(newCap);
        vm.stopPrank();

        sBTCBeraVault.setCap(newCap);
        uint256 updatedCap = sBTCBeraVault.cap();
        assertEq(updatedCap, newCap); // Assert that the new cap is correctly set
    }
    function testCancelAndSubmitNewRedeemRequest() public {
        uint256 depositAmount = 1e18; // 1 tokenA
        uint256 redeemShares = 1e18; // 1 share
        uint256 newRedeemShares = 5e17; // 0.5 share

        // Deposit tokenA to get shares
        tokenA.approve(address(sBTCBeraVault), depositAmount);
        sBTCBeraVault.deposit(address(tokenA), depositAmount, address(this));

        // Submit a redeem request for tokenA
        lpToken.approve(address(sBTCBeraVault), redeemShares);
        sBTCBeraVault.requestRedeem(address(tokenA), redeemShares);

        // Verify initial redeem request state
        (address requestToken, uint256 shares) = sBTCBeraVault
            .pendingRedeemRequest();
        assertEq(
            requestToken,
            address(tokenA),
            "Initial request token mismatch"
        );
        assertEq(shares, redeemShares, "Initial request shares mismatch");

        // Cancel the redeem request
        sBTCBeraVault.cancelRequest();

        // Verify cancel request state
        (requestToken, shares) = sBTCBeraVault.pendingRedeemRequest();
        assertEq(requestToken, address(0), "Request token should be cleared");
        assertEq(shares, 0, "Request shares should be cleared");

        // Submit a new redeem request for tokenC
        lpToken.approve(address(sBTCBeraVault), newRedeemShares);
        sBTCBeraVault.requestRedeem(address(tokenC), newRedeemShares);

        // Verify new redeem request state
        (requestToken, shares) = sBTCBeraVault.pendingRedeemRequest();
        assertEq(requestToken, address(tokenC), "New request token mismatch");
        assertEq(shares, newRedeemShares, "New request shares mismatch");
    }
    function test_multipleRoundsRedeem() public {
        sBTCBeraVault.addUnderlyingAsset(address(tokenC));

        tokenA.approve(address(sBTCBeraVault), 5e18);
        tokenB.approve(address(sBTCBeraVault), 5e8);

        sBTCBeraVault.deposit(address(tokenA), 5e18, address(this));
        sBTCBeraVault.deposit(address(tokenB), 5e8, address(this));

        // Round 1
        lpToken.approve(address(sBTCBeraVault), 50e18);
        sBTCBeraVault.requestRedeem(address(tokenC), 1e4);
        uint256 withdrawTokenAmount = tokenA.balanceOf(address(sBTCBeraVault));
        sBTCBeraVault.withdrawAssets(address(tokenA), withdrawTokenAmount);
        // Repay assets based on expected amount
        tokenC.approve(address(sBTCBeraVault), type(uint256).max);
        sBTCBeraVault.repayAssets(address(tokenC), 1e6);

        // Move to Round 2
        sBTCBeraVault.rollToNextRound();
        address requestToken;
        uint256 claimable;
        (requestToken, claimable) = sBTCBeraVault.claimableRedeemRequest();
        uint256 expectedClaimable = (uint256(1e4) * uint256(10 ** 6)) /
            uint256(10 ** 18);
        assertEq(
            claimable,
            expectedClaimable,
            "Claimable amount in round 1 is incorrect"
        );
        sBTCBeraVault.requestRedeem(address(tokenC), 2e18); // address(this) requests 2e4 shares
        // Repay assets based on expected amount
        sBTCBeraVault.repayAssets(address(tokenC), 2e6);
        // Move to Round 3
        sBTCBeraVault.rollToNextRound();

        (requestToken, claimable) = sBTCBeraVault.claimableRedeemRequest();
        expectedClaimable =
            (uint256(2e18) * uint256(10 ** 6)) /
            uint256(10 ** 18);
        assertEq(
            claimable,
            expectedClaimable,
            "Claimable amount in round 2 is incorrect"
        );

        uint256 BalanceBefore = tokenC.balanceOf(address(this));
        sBTCBeraVault.claimRedeemRequest();
        uint256 BalanceAfter = tokenC.balanceOf(address(this));
        assertEq(
            BalanceAfter - BalanceBefore,
            expectedClaimable,
            "Incorrect redeem amount paid in round 1"
        );
    }
    function test_setFeeRecipient() public {
        address user = address(1);
        address feeRecipient = address(2);
        vm.startPrank(user);
        vm.expectRevert();
        sBTCBeraVault.setFeeRecipient(feeRecipient);
        vm.stopPrank();

        vm.expectRevert(ZeroAddress.selector);
        sBTCBeraVault.setFeeRecipient(address(0));

        sBTCBeraVault.setFeeRecipient(feeRecipient);
        assertEq(sBTCBeraVault.feeRecipient(), feeRecipient);
    }
    function test_setFeeRate() public {
        address user = address(1);
        address feeRecipient = address(2);
        vm.startPrank(user);
        vm.expectRevert();
        sBTCBeraVault.setFeeRate(address(tokenA), 1e6);
        vm.stopPrank();

        vm.expectRevert(NoFeeRecipient.selector);
        sBTCBeraVault.setFeeRate(address(tokenC), 1e6);

        sBTCBeraVault.setFeeRecipient(feeRecipient);

        vm.expectRevert(InvalidAsset.selector);
        sBTCBeraVault.setFeeRate(address(tokenC), 1e6);

        sBTCBeraVault.addUnderlyingAsset(address(tokenC));

        vm.expectRevert(InvalidFeeRate.selector);
        sBTCBeraVault.setFeeRate(address(tokenC), 1000001);

        sBTCBeraVault.setFeeRate(address(tokenC), 1e6);

        assertEq(sBTCBeraVault.feeRate(address(tokenC)), 1e6);
        assertEq(sBTCBeraVault.feeRate(address(tokenA)), 0);
    }
    function test_deposit_withFee() public {
        address user = address(1);
        address feeRecipient = address(2);
        sBTCBeraVault.setFeeRecipient(feeRecipient);

        sBTCBeraVault.setFeeRate(address(tokenA), 8e5);
        assertEq(sBTCBeraVault.feeRate(address(tokenA)), 8e5);

        vm.startPrank(user);
        tokenA.mint(user, 10000 * 1e18);
        tokenA.approve(address(sBTCBeraVault), 1e18);
        sBTCBeraVault.deposit(address(tokenA), 1e18, user);
        assertEq(
            lpToken.balanceOf(user),
            1e18 * (1 - 8e5 / 1e6),
            "lpToken mismatch"
        );
        assertEq(tokenA.balanceOf(user), 9999 * 1e18, "Token mismatch");
        assertEq(
            lpToken.balanceOf(feeRecipient),
            (1e18 * 8e5) / 1e6,
            "fee mismatch"
        );
        vm.stopPrank();

        sBTCBeraVault.setFeeRate(address(tokenA), 1e6);
        vm.startPrank(user);
        tokenA.approve(address(sBTCBeraVault), 2e18);
        sBTCBeraVault.mint(address(tokenA), 2e18, user);
        assertEq(
            lpToken.balanceOf(user),
            1e18 * (1 - 8e5 / 1e6) + 2e18 * (1 - 1)
        );
        assertEq(tokenA.balanceOf(user), 9997 * 1e18);
        assertEq(lpToken.balanceOf(feeRecipient), (1e18 * 8e5) / 1e6 + 2e18);
    }
}
