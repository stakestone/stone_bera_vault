// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";

contract AsyncDistributor is AccessControl {
    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");

    uint256 public constant duration = 30 days;

    bytes32 public root;

    address public immutable token;

    uint256 public terminateTime;
    bool public terminated;

    mapping(address => uint256) public claimed;

    event Claimed(address indexed user, address indexed token, uint256 amount);
    event SetRoot(bytes32 oldRoot, bytes32 newRoot);
    event Terminate(uint256 time);
    event Terminated(address indexed token, uint256 leftTokens, uint256 time);

    constructor(address _token) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        token = _token;
    }

    function claim(
        bytes32[] memory _proof,
        uint256 _totalAmount,
        uint256 _amount
    ) external {
        require(!terminated, "terminated");

        bytes32 leaf = keccak256(
            bytes.concat(keccak256(abi.encode(msg.sender, token, _totalAmount)))
        );

        require(MerkleProof.verify(_proof, root, leaf), "Invalid proof");
        claimed[msg.sender] += _amount;

        require(claimed[msg.sender] <= _totalAmount, "Exceed amount");
        TransferHelper.safeTransfer(token, msg.sender, _amount);

        emit Claimed(msg.sender, token, _amount);
    }

    function setRoot(bytes32 _root) external onlyRole(OWNER_ROLE) {
        emit SetRoot(root, _root);
        root = _root;
    }

    function terminate() external onlyRole(OWNER_ROLE) {
        terminateTime = block.timestamp;
        emit Terminate(terminateTime);
    }

    function finalizeTerminate() external onlyRole(OWNER_ROLE) {
        require(block.timestamp - terminateTime > duration, "terminating");

        uint256 tokenAmount = ERC20(token).balanceOf(address(this));
        TransferHelper.safeTransfer(token, msg.sender, tokenAmount);

        terminated = true;

        emit Terminated(token, tokenAmount, block.timestamp);
    }
}
