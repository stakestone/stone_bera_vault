// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {AggregatorV3Interface} from "../interfaces/AggregatorV3Interface.sol";

interface IBeraSTONEVault {
    function getRate() external view returns (uint256 rate);
}

contract BeraStoneRateAdapter is AggregatorV3Interface {
    uint8 public constant override decimals = 18;

    string public constant override description = "beraSTONE/ETH exchange rate";

    uint256 public constant override version = 0;

    address public constant beraSTONEVaultAddr =
        0x8f88aE3798E8fF3D0e0DE7465A0863C9bbB577f0;

    function latestRoundData()
        external
        view
        override
        returns (uint80, int256, uint256, uint256, uint80)
    {
        uint256 rate = IBeraSTONEVault(beraSTONEVaultAddr).getRate();

        return (0, int256(rate), 0, 0, 0);
    }
}
