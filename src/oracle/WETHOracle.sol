// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Oracle} from "./Oracle.sol";

contract WETHOracle is Oracle {
    uint256 public constant D18 = 1e18;

    constructor(address _token, string memory _name) Oracle(_token, _name) {
        require(_token != address(0), "Invalid Address");

        token = _token;
        name = _name;
    }

    function getPrice() external view override returns (uint256 price) {
        price = D18;
    }
}
