// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import {Token} from "../src/Token.sol";
import {OracleConfigurator} from "../src/oracle/OracleConfigurator.sol";
import "forge-std/Test.sol";
import "../src/StoneBeraVault.sol";
import "./MockToken.sol";
import "./MockOracle.sol";

contract StoneBeraVaultTest is Test {
    StoneBeraVault public vault;
    Token public lpToken;
    MockToken public underlyingToken;
    MockToken public underlyingToken1;
    MockToken public withdrawToken;
    MockOracle public oracle;
    MockOracle public oracle1;
    MockOracle public oracleW;
    OracleConfigurator public oracleConfigurator;

    address public user = address(1);
    address public operator = address(3);
    address public assetManager = address(4);

    uint256 public constant CAP = 10000 * 1e18;

    function setUp() public {
        lpToken = new Token("LP Token", "LPT");
        withdrawToken = new MockToken(18);
        oracleW = new MockOracle(
            address(withdrawToken),
            "withdrawToken Oracle"
        );
        underlyingToken = new MockToken(18);
        oracle = new MockOracle(
            address(underlyingToken),
            "underlyingToken Oracle"
        );
        underlyingToken1 = new MockToken(8);
        oracle1 = new MockOracle(
            address(underlyingToken1),
            "underlyingToken1 Oracle"
        );
        oracleConfigurator = new OracleConfigurator();
        oracleConfigurator.grantRole(
            oracleConfigurator.ORACLE_MANAGER_ROLE(),
            address(this)
        );
        oracleConfigurator.updateOracle(
            address(withdrawToken),
            address(oracleW)
        );
        oracleConfigurator.updateOracle(
            address(underlyingToken),
            address(oracle)
        );
        oracleConfigurator.updateOracle(
            address(underlyingToken1),
            address(oracle1)
        );
        vault = new StoneBeraVault(
            address(lpToken),
            address(withdrawToken),
            address(oracleConfigurator),
            CAP
        );
        vault.grantRole(vault.VAULT_OPERATOR_ROLE(), operator);
        vault.grantRole(vault.ASSETS_MANAGEMENT_ROLE(), assetManager);
        lpToken.grantRole(lpToken.MINTER_ROLE(), address(vault));
        lpToken.grantRole(lpToken.BURNER_ROLE(), address(vault));

        vm.deal(user, 10000 * 1e18);
        vm.deal(address(vault), 10000 * 1e18);
        withdrawToken.mint(assetManager, 100000 * 1e18);
    }

    function testRollToNext_WithPriceFluctuation_underlyingTokenPriceRise_InsufficientBalance()
        public
    {
        // 添加 underlying asset
        vm.startPrank(operator);
        vault.addUnderlyingAsset(address(underlyingToken));
        withdrawToken.mint(address(vault), 100 * 1e18);

        // 设置初始价格
        oracle.updatePrice(1 * 1e18);
        oracleW.updatePrice(1 * 1e18);

        // 用户存入 underlying asset
        underlyingToken.mint(user, 100 * 1e18);
        vm.startPrank(user);
        underlyingToken.approve(address(vault), 100 * 1e18);
        vault.deposit(address(underlyingToken), 100 * 1e18, user);

        // 进入下一轮
        vm.startPrank(operator);
        console.log("rollToNextRound1...");
        vault.rollToNextRound();
        vm.stopPrank();
        // 更改 underlying asset 价格为极高
        oracle.updatePrice(1000 * 1e18);
        // 用户请求赎回
        uint256 shares = lpToken.balanceOf(user);
        vm.startPrank(user);
        lpToken.approve(address(vault), type(uint256).max);
        vault.requestRedeem(shares);
        uint256 vault_left = withdrawToken.balanceOf(address(vault));
        console.log("vault_left is:", vault_left);

        // 进入下一轮，用户可以 claim
        vm.startPrank(operator);
        console.log("rollToNextRound2...");
        vm.expectRevert(InsufficientBalance.selector);
        vault.rollToNextRound();
        vm.stopPrank();
    }

    function testRollToNext_WithPriceFluctuation_withdrawTokenPriceLow_InsufficientBalance()
        public
    {
        // 添加 underlying asset
        vm.startPrank(operator);
        vault.addUnderlyingAsset(address(underlyingToken));
        withdrawToken.mint(address(vault), 100 * 1e18);

        // 设置初始价格
        oracle.updatePrice(1 * 1e18);
        oracleW.updatePrice(1 * 1e18);

        // 用户存入 underlying asset
        underlyingToken.mint(user, 100 * 1e18);
        vm.startPrank(user);
        underlyingToken.approve(address(vault), 100 * 1e18);
        vault.deposit(address(underlyingToken), 100 * 1e18, user);

        // 进入下一轮
        vm.startPrank(operator);
        console.log("rollToNextRound1...");
        vault.rollToNextRound();
        vm.stopPrank();
        // 更改 withdrawToken 价格为极低
        oracleW.updatePrice(0.01 * 1e18);
        // 用户请求赎回
        uint256 shares = lpToken.balanceOf(user);
        vm.startPrank(user);
        lpToken.approve(address(vault), type(uint256).max);
        vault.requestRedeem(shares);
        uint256 vault_left = withdrawToken.balanceOf(address(vault));
        console.log("vault_left is:", vault_left);

        // 进入下一轮，用户可以 claim
        vm.startPrank(operator);
        console.log("rollToNextRound2...");
        vm.expectRevert(InsufficientBalance.selector);
        vault.rollToNextRound();
        vm.stopPrank();
    }

    function testRedeem_managerBorrowToken_repayToken() public {
        uint256 depositAmount = 1000 * 1e18;
        //     // 添加 underlying asset
        vm.startPrank(operator);
        vault.addUnderlyingAsset(address(underlyingToken));
        vault.addUnderlyingAsset(address(withdrawToken));
        withdrawToken.mint(address(vault), depositAmount);

        // 设置初始价格
        oracle.updatePrice(1 * 1e18);
        oracleW.updatePrice(1 * 1e18);
        vm.startPrank(user);
        // 用户存入 underlying asset
        underlyingToken.mint(user, depositAmount);
        underlyingToken.approve(address(vault), type(uint256).max);
        vault.deposit(address(underlyingToken), depositAmount, user);
        vm.startPrank(operator);
        // 进入下一轮
        vault.rollToNextRound();
        vm.startPrank(user);
        // 用户请求赎回所有 shares
        uint256 shares = lpToken.balanceOf(user);
        lpToken.approve(address(vault), type(uint256).max);
        vault.requestRedeem(shares);
        uint256 totalValue = depositAmount * 2;
        uint256 totalSupply = lpToken.totalSupply();
        uint256 expectedRate = (totalValue / totalSupply) * 1e18;
        uint256 actualRate = vault.getRate();
        assertEq(actualRate, expectedRate, "Rate after deposit is incorrect");
        //change withdrawTokenPrice
        uint256 withdrawTokenPrice = 0.8 * 1e18;
        oracleW.updatePrice(withdrawTokenPrice);
        // 进入下一轮，用户可以 claim
        vm.expectRevert(InsufficientBalance.selector);
        vm.startPrank(operator);
        vault.rollToNextRound();

        vm.startPrank(assetManager);
        vault.withdrawAssets(
            address(underlyingToken),
            underlyingToken.balanceOf(address(vault))
        );
        //calculate how much asset manager should repay to the vault to cover this user's withdraw
        uint256 share = vault.requestingSharesInRound();
        uint256 repayAmt = ((share * actualRate) / withdrawTokenPrice);
        withdrawToken.approve(address(vault), type(uint256).max);
        vault.repayAssets(address(withdrawToken), repayAmt - depositAmount);

        //not roll to next round,withdraw should fail
        vm.expectRevert(NoClaimableRedeem.selector);
        vm.startPrank(user);
        vault.claimRedeemRequest();
        console.log("vault balance...");
        console.logUint(withdrawToken.balanceOf(address(vault)));

        console.log("getRate1...");
        console.logUint(vault.getRate());

        vm.startPrank(operator);
        vault.rollToNextRound();

        //user withdraw
        vm.startPrank(user);
        vault.claimRedeemRequest();
    }

    // 测试当合约余额不足以支付所有赎回请求时的情况
    function testRedeem_managerBorrowToken_InsufficientBalance() public {
        //     // 添加 underlying asset
        vm.startPrank(operator);
        vault.addUnderlyingAsset(address(underlyingToken));
        // 设置初始价格
        oracle.updatePrice(1 * 1e18);
        oracleW.updatePrice(1 * 1e18);
        vm.startPrank(user);
        // 用户存入 underlying asset
        underlyingToken.mint(user, 200 * 1e18);
        underlyingToken.approve(address(vault), 200 * 1e18);
        vault.deposit(address(underlyingToken), 200 * 1e18, user);
        assertEq(lpToken.balanceOf(user), 200 * 1e18);
        assertEq(underlyingToken.balanceOf(address(vault)), 200 * 1e18);
        //asset manager withdraw underlying asset
        vm.startPrank(assetManager);
        vault.withdrawAssets(
            address(underlyingToken),
            underlyingToken.balanceOf(address(vault))
        );
        assertEq(underlyingToken.balanceOf(assetManager), 200 * 1e18);
        assertEq(underlyingToken.balanceOf(address(vault)), 0);
        vm.startPrank(operator);
        // 进入下一轮
        vault.rollToNextRound();
        vm.startPrank(user);
        // 用户请求赎回所有 shares
        uint256 shares = lpToken.balanceOf(user);
        lpToken.approve(address(vault), type(uint256).max);
        vault.requestRedeem(shares / 2);
        vault.requestRedeem(shares / 2);
        assertEq(
            vault.requestingSharesInRound(),
            shares,
            "requestingSharesInRound is correct"
        );
        vm.startPrank(operator);
        vm.expectRevert(InsufficientBalance.selector);
        vault.rollToNextRound();
        // repay to vault
        vm.startPrank(assetManager);
        vm.expectRevert(InvalidAsset.selector);
        vault.repayAssets(address(withdrawToken), 100 * 1e18);
        vm.startPrank(operator);
        vault.addUnderlyingAsset(address(withdrawToken));
        vm.expectRevert();
        vault.repayAssets(address(withdrawToken), 100 * 1e18);
        vm.startPrank(assetManager);
        withdrawToken.approve(address(vault), 1000 * 1e18);
        vault.repayAssets(address(withdrawToken), 100 * 1e18);
        vm.startPrank(operator);
        console.log("getRate...");
        console.logUint(vault.getRate());
        vm.expectRevert(InsufficientBalance.selector);
        vault.rollToNextRound();
        vm.startPrank(assetManager);
        vault.repayAssets(address(withdrawToken), 100 * 1e18);
        vm.startPrank(operator);
        vault.rollToNextRound();
        vm.startPrank(user);
        vault.claimRedeemRequest();
        assertEq(withdrawToken.balanceOf(user), 200 * 1e18);
    }

    // 测试在连续多轮赎回请求中的累积误差
    function testRedeemWithAccumulatedRoundingErrors() public {
        // 添加 underlying asset
        vm.startPrank(operator);
        vault.addUnderlyingAsset(address(underlyingToken));
        vault.addUnderlyingAsset(address(withdrawToken));
        // 设置初始价格
        oracle.updatePrice(1 * 1e18);
        oracleW.updatePrice(1 * 1e18);
        // 用户存入 underlying asset
        underlyingToken.mint(user, 1000 * 1e18);
        vm.startPrank(user);
        underlyingToken.approve(address(vault), 1000 * 1e18);
        vault.deposit(address(underlyingToken), 1000 * 1e18, user);
        vm.startPrank(operator);
        // 进入下一轮
        vault.rollToNextRound();
        vm.startPrank(assetManager);
        vault.withdrawAssets(
            address(underlyingToken),
            underlyingToken.balanceOf(address(vault))
        );
        // 进行多次小额赎回和价格波动
        for (uint256 i = 0; i < 100; i++) {
            vm.startPrank(assetManager);
            withdrawToken.approve(address(vault), 1000 * 1e18);
            vault.repayAssets(address(withdrawToken), 1 * 1e18);
            vm.startPrank(operator);
            // 随机更改价格
            oracle.updatePrice(
                (uint256(keccak256(abi.encode(i))) % 1000) * 1e18
            );
            oracleW.updatePrice(
                (uint256(keccak256(abi.encode(i + 1))) % 1000) * 1e18
            );
            // 请求赎回一小部分 shares
            uint256 sharesToRedeem = lpToken.balanceOf(user) / 100;
            vm.startPrank(user);
            lpToken.approve(address(vault), type(uint256).max);
            vault.requestRedeem(sharesToRedeem);
            vm.startPrank(operator);
            // 进入下一轮
            vault.rollToNextRound();
            vm.startPrank(user);
            // claim 赎回
            vault.claimRedeemRequest();
        }
    }

    //用户多轮申请取款 测试requestingSharesInPast
    function testRedeem_multipleDepsosit_multipleRequestClaim() public {
        uint256 mintAmout = 10000 * 1e18;
        uint256 depositAmount = 1000 * 1e18;
        address user2 = address(2);
        //     // 添加 underlying asset
        vm.startPrank(operator);
        vault.addUnderlyingAsset(address(underlyingToken));
        vault.addUnderlyingAsset(address(withdrawToken));

        // 设置初始价格
        oracle.updatePrice(1 * 1e18);
        oracleW.updatePrice(1 * 1e18);
        vm.startPrank(user);
        underlyingToken.mint(user, mintAmout);
        underlyingToken.mint(user2, mintAmout);

        underlyingToken.approve(address(vault), type(uint256).max);
        vault.mint(address(underlyingToken), depositAmount, user);
        vm.startPrank(user2);
        underlyingToken.approve(address(vault), type(uint256).max);
        vault.mint(address(underlyingToken), depositAmount, user2);

        vm.startPrank(operator);
        vault.rollToNextRound();
        //change Price
        uint256 withdrawTokenPrice = 0.8 * 1e18;
        oracleW.updatePrice(withdrawTokenPrice);
        uint256 underlyingTokenPrice = 2.5 * 1e18;
        oracle1.updatePrice(underlyingTokenPrice);

        vm.startPrank(user2);
        vm.expectRevert(ZeroShares.selector);
        vault.deposit(address(underlyingToken), 0, user2);
        //user2 deposit same amount again
        vault.deposit(address(underlyingToken), depositAmount, user2);
        //check user2 shares,new share = new depositValue*activeShares/activeAssets
        uint256 newshare = ((depositAmount * underlyingTokenPrice) * 2000e18) /
            2000e18 /
            underlyingTokenPrice;
        assertEq(
            lpToken.balanceOf(user2),
            depositAmount + newshare,
            "user2 share is incorrect"
        );
        // user2 request redeem half the shares
        uint256 shares = lpToken.balanceOf(user2);
        vm.startPrank(user2);
        lpToken.approve(address(vault), type(uint256).max);
        vault.requestRedeem(shares / 2);
        vm.startPrank(assetManager);
        uint256 borrowAmt = underlyingToken.balanceOf(address(vault));
        vault.withdrawAssets(address(underlyingToken), borrowAmt / 2);
        vm.expectRevert(InsufficientBalance.selector);
        vault.withdrawAssets(address(underlyingToken), borrowAmt);
        vm.expectRevert(InvalidAsset.selector);
        vault.withdrawAssets(address(underlyingToken1), borrowAmt / 2);
        vault.withdrawAssets(address(underlyingToken), borrowAmt / 2);

        //calculate how much asset manager should repay to the vault to cover this user's withdraw
        uint256 share = vault.requestingSharesInRound();
        uint256 rate = vault.getRate();
        console.log("rate...");
        console.logUint(rate);

        uint256 totalValue = depositAmount * 3;
        uint256 totalSupply = lpToken.totalSupply();
        uint256 expectedRate = (totalValue / totalSupply) * 1e18;
        uint256 actualRate = vault.getRate();
        assertEq(actualRate, expectedRate, "Rate after deposit is incorrect");
        // calc the repay amount
        uint256 calAmt = (share * rate) / withdrawTokenPrice;
        console.log("calAmt ...");
        console.logUint(calAmt);
        vm.startPrank(assetManager);
        withdrawToken.approve(address(vault), type(uint256).max);
        vault.repayAssets(address(withdrawToken), calAmt / 2);
        vault.repayAssets(address(withdrawToken), calAmt / 2);

        vm.startPrank(operator);
        vault.rollToNextRound();
        uint256 claimed = vault.redeemableAmountInPast();
        assertEq(claimed, ((shares / 2) * actualRate) / withdrawTokenPrice);
        //user2 request the left shares
        vm.startPrank(user2);
        lpToken.approve(address(vault), type(uint256).max);
        vault.requestRedeem(shares / 2);

        //user withdraw
        uint256 redeemableAmountInPast = vault.redeemableAmountInPast();
        assertEq(
            redeemableAmountInPast,
            0,
            "redeemableAmountInPast is correct"
        );
        assertEq(
            vault.requestingSharesInPast(),
            0,
            "requestingSharesInPast is correct"
        );
        assertEq(
            vault.requestingSharesInRound(),
            shares / 2,
            "requestingSharesInRound is correct"
        );
        vm.expectRevert(NoClaimableRedeem.selector);
        vault.claimRedeemRequest();

        totalValue =
            (underlyingTokenPrice * depositAmount * 3) -
            (claimed * withdrawTokenPrice);
        totalSupply = lpToken.totalSupply();
        uint256 latestRate = (totalValue / totalSupply) * 1e18;
        vm.startPrank(assetManager);
        borrowAmt = underlyingToken.balanceOf(address(vault));
        vault.withdrawAssets(address(underlyingToken), borrowAmt);

        uint256 repayAmt = (vault.requestingSharesInRound() * latestRate) /
            withdrawTokenPrice /
            1e18;

        vault.repayAssets(address(withdrawToken), repayAmt);

        vm.startPrank(operator);
        vault.rollToNextRound();
        vm.startPrank(user2);
        console.log("start claimRedeemRequest ...");

        vault.claimRedeemRequest();
        console.log("start claimRedeemRequest1 ...");

        uint256 newClaim = ((shares / 2) * vault.roundPricePerShare(2)) /
            withdrawTokenPrice;
        assertEq(
            claimed + newClaim,
            withdrawToken.balanceOf(user2),
            "claimRedeemRequest success"
        );
    }
}
