// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {WETHOracle} from "../src/oracle/WETHOracle.sol";

contract WETHOracleTest is Test {
    WETHOracle oracle;

    function setUp() public {
        oracle = new WETHOracle(address(1), "WETH Oracle");
    }

    function testPrice() public {
        uint256 expectedPrice = 1e18;
        assertEq(oracle.getPrice(), expectedPrice);
    }

    function testInvalidTokenAddress() public {
        vm.expectRevert("Invalid Address");
        new WETHOracle(address(0), "WETH Oracle");
    }
}
