// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";

interface IStoneBeraVault {
    function lpToken() external returns (address);

    function deposit(
        address _asset,
        uint256 _amount,
        address _receiver
    ) external returns (uint256 shares);
}

interface IWETH {
    function deposit() external payable;

    function balanceOf(address _user) external returns (uint256);
}

contract DepositWrapper {
    address public immutable weth;
    address public immutable vault;
    address public immutable token;

    constructor(address _weth, address _vault) {
        weth = _weth;
        vault = _vault;
        token = IStoneBeraVault(vault).lpToken();
    }

    function depositETH(
        address _receiver
    ) external payable returns (uint256 minted) {
        require(msg.value > 0, "zero value");

        IWETH wETH = IWETH(weth);
        wETH.deposit{value: msg.value}();

        uint256 bal = wETH.balanceOf(address(this));
        TransferHelper.safeApprove(weth, vault, bal);

        minted = IStoneBeraVault(vault).deposit(weth, bal, _receiver);
    }

    receive() external payable {
        revert("Forbidden");
    }
}
