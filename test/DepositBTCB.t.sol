// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../src/asyncVault/AsyncVault.sol";
import "../src/asyncVault/AsyncDistributor.sol";
import {MockToken} from "./MockToken.sol";

contract CrossChainTest is Test {
    using SafeERC20 for ERC20;

    // 合约实例
    AsyncVault asyncVault;
    AsyncDistributor asyncDistributor;
    ERC20 btcToken;
    ERC20 lpToken;

    // 地址模拟
    address owner = address(1);
    address user = address(2);
    address otherUser = address(3);
    address operator = address(4);
    address assetManager = address(5);
    function setUp() public {
        btcToken = new MockToken(18);
        lpToken = new MockToken(18);

        // 部署 Vault 和 Distributor 合约
        asyncVault = new AsyncVault(address(btcToken));
        asyncDistributor = new AsyncDistributor(address(lpToken));

        // 分配权限
        vm.prank(owner);
        asyncVault.grantRole(asyncVault.DEFAULT_ADMIN_ROLE(), owner);
        asyncDistributor.grantRole(
            asyncDistributor.DEFAULT_ADMIN_ROLE(),
            owner
        );
        asyncDistributor.grantRole(asyncDistributor.OWNER_ROLE(), owner);
        asyncVault.grantRole(asyncVault.VAULT_OPERATOR_ROLE(), operator);
        asyncVault.grantRole(asyncVault.ASSETS_MANAGEMENT_ROLE(), assetManager);

        // 模拟初始代币分发
        deal(address(btcToken), user, 100 * 1e18); // 用户初始持有 100 BTCB
        deal(address(btcToken), otherUser, 50 * 1e18); // 另一个用户初始持有 50 BTCB
        deal(address(lpToken), address(asyncDistributor), 100 * 1e18); // Distributor 中初始持有 100 LP Token
    }
    function testVaultDeposit() public {
        vm.startPrank(user);
        btcToken.approve(address(asyncVault), 10 * 1e18);

        asyncVault.deposit(10 * 1e18, user);

        assertEq(btcToken.balanceOf(address(asyncVault)), 10 * 1e18);
        assertEq(btcToken.balanceOf(user), 90 * 1e18);

        vm.stopPrank();
    }
    function testPauseVault() public {
        vm.startPrank(operator);
        asyncVault.setPause(true);
        vm.startPrank(user);
        btcToken.approve(address(asyncVault), 10 * 1e18);
        vm.expectRevert("paused");
        asyncVault.deposit(10 * 1e18, user);
        vm.stopPrank();
    }

    function testTerminateDistribution() public {
        vm.startPrank(owner);
        asyncDistributor.terminate();
        assertEq(asyncDistributor.terminateTime(), block.timestamp);
        vm.stopPrank();
    }
    function testCrossChainWorkflow() public {
        vm.startPrank(user);

        // 用户在 BNB Chain 上将 BTCB 存入 AsyncVault
        btcToken.approve(address(asyncVault), 20 * 1e18);
        asyncVault.deposit(20 * 1e18, user);
        assertEq(btcToken.balanceOf(address(asyncVault)), 20 * 1e18);

        vm.stopPrank();

        // 在 Ethereum 上生成 Merkle Tree 根节点（root）
        bytes32 leaf = keccak256(
            bytes.concat(
                keccak256(abi.encode(user, address(lpToken), 50 * 1e18))
            )
        );
        bytes32[] memory proof = new bytes32[](0); // 简单情况，无 sibling hash
        bytes32 root = leaf;

        vm.prank(owner);
        asyncDistributor.setRoot(root);

        // 用户在 Ethereum 上根据 Merkle Proof 领取 LP Token
        vm.startPrank(user);
        asyncDistributor.claim(proof, 50 * 1e18, 50 * 1e18);
        assertEq(lpToken.balanceOf(user), 50 * 1e18);

        vm.stopPrank();
    }
    function testCrossChainWorkflow_claimMultipleTimes() public {
        vm.startPrank(user);

        // 用户在 BNB Chain 上将 BTCB 存入 AsyncVault
        btcToken.approve(address(asyncVault), 20 * 1e18);
        asyncVault.deposit(20 * 1e18, user);
        assertEq(btcToken.balanceOf(address(asyncVault)), 20 * 1e18);

        vm.stopPrank();

        // 在 Ethereum 上生成 Merkle Tree 根节点（root）
        bytes32 leaf = keccak256(
            bytes.concat(
                keccak256(abi.encode(user, address(lpToken), 50 * 1e18))
            )
        );
        bytes32[] memory proof = new bytes32[](0); // 简单情况，无 sibling hash
        bytes32 root = leaf;
        vm.prank(owner);
        asyncDistributor.setRoot(root);

        // 用户在 Ethereum 上根据 Merkle Proof 领取 LP Token
        vm.startPrank(user);
        asyncDistributor.claim(proof, 50 * 1e18, 30 * 1e18);
        asyncDistributor.claim(proof, 50 * 1e18, 20 * 1e18);
        assertEq(lpToken.balanceOf(user), 50 * 1e18);
        vm.expectRevert("Exceed amount");
        asyncDistributor.claim(proof, 50 * 1e18, 1 * 1e18);

        vm.stopPrank();
    }
    function testCrossChainWorkflowWithMultipleLeaves() public {
        vm.startPrank(user);

        // 用户在 BNB Chain 上将 BTCB 存入 AsyncVault
        btcToken.approve(address(asyncVault), 20 * 1e18);
        asyncVault.deposit(20 * 1e18, user);
        assertEq(btcToken.balanceOf(address(asyncVault)), 20 * 1e18);

        vm.stopPrank();
        vm.startPrank(otherUser);
        // 另一个用户也存入 BTCB
        btcToken.approve(address(asyncVault), 10 * 1e18);
        asyncVault.deposit(10 * 1e18, otherUser);
        assertEq(btcToken.balanceOf(address(asyncVault)), 30 * 1e18);

        vm.stopPrank();

        // Merkle 树构造
        bytes32 leaf1 = keccak256(
            bytes.concat(
                keccak256(
                    abi.encode(user, address(lpToken), uint256(50 * 1e18))
                )
            )
        );
        bytes32 leaf2 = keccak256(
            bytes.concat(
                keccak256(
                    abi.encode(otherUser, address(lpToken), uint256(30 * 1e18))
                )
            )
        );
        bytes32 root = keccak256(abi.encodePacked(leaf1, leaf2));

        vm.prank(owner);
        asyncDistributor.setRoot(root);
        // 用户的 Proof
        bytes32[] memory proof1 = new bytes32[](1);
        proof1[0] = leaf2;
        // 校验
        vm.startPrank(user);
        asyncDistributor.claim(proof1, 50 * 1e18, 50 * 1e18);
        assertEq(lpToken.balanceOf(user), 50 * 1e18);
        vm.stopPrank();
        // 另一个用户在 Ethereum 上根据 Merkle Proof 领取 LP Token
        vm.startPrank(otherUser);
        bytes32[] memory proof2 = new bytes32[](1);
        proof2[0] = leaf1; // 另一个用户的 proof 包含 sibling hash
        asyncDistributor.claim(proof2, 30 * 1e18, 30 * 1e18);
        assertEq(lpToken.balanceOf(otherUser), 30 * 1e18);
        vm.stopPrank();
    }

    function testInvalidProof() public {
        bytes32 merkleRoot = keccak256(
            abi.encodePacked(
                keccak256(abi.encode(user, address(lpToken), 50 * 1e18))
            )
        );
        vm.startPrank(owner);
        asyncDistributor.setRoot(merkleRoot);

        vm.startPrank(user);
        bytes32[] memory invalidProof = new bytes32[](1);
        invalidProof[0] = keccak256(abi.encodePacked("Invalid"));

        vm.expectRevert("Invalid proof");
        asyncDistributor.claim(invalidProof, 50 * 1e18, 50 * 1e18);

        vm.stopPrank();
    }
    function testFinalizeTerminate() public {
        vm.startPrank(owner);

        asyncDistributor.terminate();
        assertEq(asyncDistributor.terminateTime(), block.timestamp);
        // Simulate 31 days passing
        vm.warp(block.timestamp + 30 days + 1);

        uint256 remainingBalance = lpToken.balanceOf(address(asyncDistributor));
        asyncDistributor.finalizeTerminate();

        assertEq(lpToken.balanceOf(owner), remainingBalance);
        assertEq(lpToken.balanceOf(address(asyncDistributor)), 0);
        assertTrue(asyncDistributor.terminated());
        vm.stopPrank();
    }
    function testFinalizeTerminate_edgeCase() public {
        vm.startPrank(owner);

        asyncDistributor.terminate();
        assertEq(asyncDistributor.terminateTime(), block.timestamp);
        // Simulate 31 days passing
        vm.warp(block.timestamp + 30 days);

        uint256 remainingBalance = lpToken.balanceOf(address(asyncDistributor));
        vm.expectRevert("terminating");
        asyncDistributor.finalizeTerminate();

        assertEq(lpToken.balanceOf(owner), 0);
        assertEq(
            lpToken.balanceOf(address(asyncDistributor)),
            remainingBalance
        );
        assertTrue(!asyncDistributor.terminated());
        vm.stopPrank();
    }
    function testWithdrawToken_Success() public {
        deal(address(btcToken), address(asyncVault), 300 * 1e18);

        // 模拟 manager 执行 withdrawToken
        vm.startPrank(assetManager);

        uint256 initialBalance = btcToken.balanceOf(assetManager);
        uint256 withdrawAmount = 200 * 1e18;

        asyncVault.withdrawToken(withdrawAmount);

        uint256 finalBalance = btcToken.balanceOf(assetManager);
        uint256 vaultBalance = btcToken.balanceOf(address(asyncVault));

        assertEq(
            finalBalance,
            initialBalance + withdrawAmount,
            "Manager balance incorrect"
        );
        assertEq(vaultBalance, 100 * 1e18, "Vault balance incorrect");
        asyncVault.withdrawToken(100 * 1e18);
        assertEq(
            btcToken.balanceOf(address(assetManager)) - finalBalance,
            100 * 1e18,
            "Manager balance incorrect"
        );

        assertEq(
            btcToken.balanceOf(address(asyncVault)),
            0,
            "Vault balance incorrect"
        );

        vm.stopPrank();
    }
    function testWithdrawToken_Unauthorized() public {
        deal(address(btcToken), address(asyncVault), 300 * 1e18);
        // 模拟未授权用户尝试提款
        vm.startPrank(user);
        uint256 withdrawAmount = 1 * 1e18;
        vm.expectRevert();
        asyncVault.withdrawToken(withdrawAmount);
        vm.stopPrank();
        vm.startPrank(operator);
        withdrawAmount = 1 * 1e18;
        vm.expectRevert();
        asyncVault.withdrawToken(withdrawAmount);
        vm.stopPrank();
    }
    function testWithdrawToken_UpdateBlock() public {
        deal(address(btcToken), address(asyncVault), 300 * 1e18);
        vm.startPrank(assetManager);

        uint256 withdrawAmount = 100 * 1e18;
        uint256 initialUpdateAt = asyncVault.updateAt();
        console.log("initialUpdateAt is %s", initialUpdateAt);
        vm.roll(block.number + 1);

        asyncVault.withdrawToken(withdrawAmount);

        uint256 finalUpdateAt = asyncVault.updateAt();
        console.log("finalUpdateAt is %s", finalUpdateAt);
        assertTrue(finalUpdateAt > initialUpdateAt, "updateAt not updated");

        vm.stopPrank();
    }
    function testWithdrawToken_ExceedVaultBalance() public {
        deal(address(btcToken), address(asyncVault), 300 * 1e18);
        vm.startPrank(assetManager);

        uint256 withdrawAmount = 300 * 1e18; // 超过 Vault 初始余额
        asyncVault.withdrawToken(withdrawAmount);

        vm.expectRevert();
        asyncVault.withdrawToken(1);
        vm.stopPrank();
    }
}
