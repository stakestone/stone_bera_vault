// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Oracle} from "./Oracle.sol";
import "../Errors.sol";

interface IStoneVault {
    function currentSharePrice() external returns (uint256 price);
}

contract StoneOracle is Oracle {
    uint256 public constant D18 = 1e18;

    IStoneVault public immutable stoneVault;

    uint256[] internal prices;

    constructor(
        address _token,
        string memory _name,
        address _stoneVault
    ) Oracle(_token, _name) {
        require(
            _token != address(0) && _stoneVault != address(0),
            "ZERO ADDRESS"
        );

        token = _token;
        name = _name;

        stoneVault = IStoneVault(_stoneVault);

        updatePrice();
    }

    function getPrice() external view override returns (uint256 price) {
        price = prices[prices.length - 1];
    }

    function updatePrice() public {
        uint256 price = stoneVault.currentSharePrice();
        if (price == 0) revert InvalidPrice();

        prices.push(price);
    }
}
