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

        // 模拟初始代币分发
        deal(address(btcToken), user, 100 * 1e18); // 用户初始持有 100 BTCB
        deal(address(btcToken), otherUser, 50 * 1e18); // 另一个用户初始持有 50 BTCB
        deal(address(lpToken), address(asyncDistributor), 100 * 1e18); // Distributor 中初始持有 100 LP Token
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
            abi.encode(user, address(lpToken), 50 * 1e18) // 用户应领取 50 LP Token
        );
        bytes32[] memory proof = new bytes32[](0); // 简单情况，无 sibling hash
        bytes32 root = keccak256(abi.encode(leaf));

        vm.prank(owner);
        asyncDistributor.setRoot(root);

        // 用户在 Ethereum 上根据 Merkle Proof 领取 LP Token
        vm.startPrank(user);
        asyncDistributor.claim(proof, 50 * 1e18, 50 * 1e18);
        assertEq(lpToken.balanceOf(user), 50 * 1e18);

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

        // 在 Ethereum 上生成 Merkle Tree 根节点（root）
        bytes32 leaf1 = keccak256(
            abi.encode(user, address(lpToken), uint256(50 * 1e18)) // 用户应领取 50 LP Token
        );
        bytes32 leaf2 = keccak256(
            abi.encode(otherUser, address(lpToken), uint256(30 * 1e18)) // 另一个用户应领取 30 LP Token
        );
        bytes32 node = keccak256(abi.encodePacked(leaf1, leaf2));
        bytes32 root = node; // Merkle Tree 根节点

        vm.prank(owner);
        asyncDistributor.setRoot(root);

        // 用户在 Ethereum 上根据 Merkle Proof 领取 LP Token
        vm.startPrank(user);
        bytes32[] memory proof1 = new bytes32[](1);
        proof1[0] = leaf2; // 用户的 proof 包含 sibling hash
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
}
