// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";

contract AsyncVault is AccessControl {
    bytes32 public constant VAULT_OPERATOR_ROLE =
        keccak256("VAULT_OPERATOR_ROLE");
    bytes32 public constant ASSETS_MANAGEMENT_ROLE =
        keccak256("ASSETS_MANAGEMENT_ROLE");

    address public immutable token;

    bool public paused;

    uint256 public updateAt;

    event Deposit(
        address indexed caller,
        address indexed owner,
        address indexed asset,
        uint256 amount
    );
    event TokenWithdrawn(address indexed asset, uint256 amount, uint256 block);
    event Pause(bool flag, uint256 time);

    constructor(address _token) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        token = _token;
        updateAt = block.number;
    }

    function deposit(uint256 _amount, address _receiver) external {
        require(!paused, "paused");

        TransferHelper.safeTransferFrom(
            token,
            msg.sender,
            address(this),
            _amount
        );

        emit Deposit(msg.sender, _receiver, token, _amount);
    }

    function withdrawToken(
        uint256 _amount
    ) external onlyRole(ASSETS_MANAGEMENT_ROLE) {
        TransferHelper.safeTransfer(token, msg.sender, _amount);

        updateAt = block.number;

        emit TokenWithdrawn(token, _amount, updateAt);
    }

    function setPause(bool _flag) external onlyRole(VAULT_OPERATOR_ROLE) {
        paused = _flag;

        emit Pause(_flag, block.timestamp);
    }
}
