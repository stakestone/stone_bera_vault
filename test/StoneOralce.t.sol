// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import "./MockStoneVault.sol";
import {StoneOracle} from "../src/oracle/StoneOracle.sol";
import {MockToken} from "./MockToken.sol";

contract StoneOracleTest is Test {
    StoneOracle public oracle;
    MockStoneVault public stoneVault;

    function setUp() public {
        MockToken mockToken = new MockToken(18);
        stoneVault = new MockStoneVault();
        oracle = new StoneOracle(
            address(mockToken),
            "Test Oracle",
            address(stoneVault)
        );
    }
    function testUpdatePrice() public {
        // Set a mock share price
        stoneVault.setSharePrice(100);
        oracle.updatePrice();
        assertEq(oracle.getPrice(), 100);
    }
    function testInvalidPrice() public {
        // Set a zero share price
        stoneVault.setSharePrice(0);
        vm.expectRevert(InvalidPrice.selector);
        oracle.updatePrice();
    }
    function testInitialPrice() public view {
        // Check the initial price after deployment
        assertEq(oracle.getPrice(), 1e18);
    }
}
