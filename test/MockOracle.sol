// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Oracle} from "../src/oracle/Oracle.sol";

contract MockOracle is Oracle {
    uint256 public constant D18 = 1e18;

    uint256 internal _price = D18;

    constructor(address _token, string memory _name) Oracle(_token, _name) {
        token = _token;
        name = _name;
    }

    function getPrice() external view override returns (uint256 price) {
        price = _price;
    }

    function updatePrice(uint256 _p) external {
        _price = _p;
    }
}
