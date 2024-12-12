// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {AsyncVault} from "../src/asyncVault/AsyncVault.sol";
import {AsyncDistributor} from "../src/asyncVault/AsyncDistributor.sol";
import {MockToken} from "./MockToken.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract AsyncVaultTest is Test {
    MockToken public btcToken;
    MockToken public lpToken;
    AsyncVault public asyncVault;
    AsyncDistributor public asyncDistributor;

    address public user = address(0x1234);
    address public owner = address(this);

    bytes32 public merkleRoot;

    function setUp() public {
        btcToken = new MockToken(18);
        lpToken = new MockToken(18);

        // Deploy AsyncVault and AsyncDistributor
        asyncVault = new AsyncVault(address(btcToken));
        asyncDistributor = new AsyncDistributor(address(lpToken));

        // Set roles
        asyncVault.grantRole(asyncVault.VAULT_OPERATOR_ROLE(), owner);
        asyncVault.grantRole(asyncVault.ASSETS_MANAGEMENT_ROLE(), owner);
        asyncDistributor.grantRole(asyncDistributor.OWNER_ROLE(), owner);

        // Mint tokens to user and vault
        btcToken.mint(user, 1000 * 1e18);
        lpToken.mint(address(asyncDistributor), 500 * 1e18);
    }

    function testVaultDeposit() public {
        vm.startPrank(user);
        btcToken.approve(address(asyncVault), 10 * 1e18);

        asyncVault.deposit(10 * 1e18, user);

        assertEq(btcToken.balanceOf(address(asyncVault)), 10 * 1e18);
        assertEq(btcToken.balanceOf(user), 990 * 1e18);

        vm.stopPrank();
    }
    function testPauseVault() public {
        asyncVault.setPause(true);

        vm.startPrank(user);
        btcToken.approve(address(asyncVault), 10 * 1e18);
        vm.expectRevert("paused");
        asyncVault.deposit(10 * 1e18, user);
        vm.stopPrank();
    }

    function testTerminateDistribution() public {
        asyncDistributor.terminate();
        assertEq(asyncDistributor.terminateTime(), block.timestamp);
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
        bytes32 root = keccak256(abi.encodePacked(leaf));

        vm.prank(owner);
        asyncDistributor.setRoot(root);

        // 用户在 Ethereum 上根据 Merkle Proof 领取 LP Token
        vm.startPrank(user);
        asyncDistributor.claim(proof, 50 * 1e18, 50 * 1e18);
        assertEq(lpToken.balanceOf(user), 50 * 1e18);

        vm.stopPrank();
    }
    function testInvalidProof() public {
        merkleRoot = keccak256(
            abi.encodePacked(
                keccak256(abi.encode(user, address(lpToken), 50 * 1e18))
            )
        );
        asyncDistributor.setRoot(merkleRoot);

        vm.startPrank(user);
        bytes32[] memory invalidProof = new bytes32[](1);
        invalidProof[0] = keccak256(abi.encodePacked("Invalid"));

        vm.expectRevert("Invalid proof");
        asyncDistributor.claim(invalidProof, 50 * 1e18, 50 * 1e18);

        vm.stopPrank();
    }

    function testDoubleClaim() public {
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
        bytes32 root = keccak256(abi.encodePacked(leaf));

        vm.prank(owner);
        asyncDistributor.setRoot(root);

        // 用户在 Ethereum 上根据 Merkle Proof 领取 LP Token
        vm.startPrank(user);

        asyncDistributor.claim(proof, 50 * 1e18, 30 * 1e18);
        asyncDistributor.claim(proof, 50 * 1e18, 20 * 1e18);
        assertEq(lpToken.balanceOf(user), 50 * 1e18);
        assertEq(asyncDistributor.claimed(user), 50 * 1e18);
        vm.expectRevert("Exceed amount");
        asyncDistributor.claim(proof, 50 * 1e18, 10 * 1e18);

        vm.stopPrank();
    }

    function testFinalizeTerminate() public {
        asyncDistributor.terminate();
        assertEq(asyncDistributor.terminateTime(), block.timestamp);

        // Simulate 31 days passing
        vm.warp(block.timestamp + 31 days);

        uint256 remainingBalance = lpToken.balanceOf(address(asyncDistributor));
        asyncDistributor.finalizeTerminate();

        assertEq(lpToken.balanceOf(owner), remainingBalance);
        assertEq(lpToken.balanceOf(address(asyncDistributor)), 0);
        assertTrue(asyncDistributor.terminated());
    }
}
