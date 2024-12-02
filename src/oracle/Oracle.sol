// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

abstract contract Oracle {
    address public immutable token;

    string public name;

    constructor(address _token, string memory _name) {
        token = _token;
        name = _name;
    }

    function getPrice() external view virtual returns (uint256 price) {}
}
