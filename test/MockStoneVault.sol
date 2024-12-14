// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

interface IStoneVault {
    function currentSharePrice() external returns (uint256 price);
}

contract MockStoneVault is IStoneVault {
    uint256 public sharePrice = 1e18;

    function currentSharePrice() external view override returns (uint256) {
        return sharePrice;
    }

    function setSharePrice(uint256 _price) public {
        sharePrice = _price;
    }
}
