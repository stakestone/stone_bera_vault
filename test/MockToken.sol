// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    uint8 internal _decimals;

    constructor(uint8 _d) ERC20("Token", "T") {
        _decimals = _d;
    }
    function decimals() public view override returns (uint8) {
        return _decimals;
    }
    function mint(address _to, uint256 _amount) external {
        _mint(_to, _amount);
    }
    function burn(address _from, uint256 _amount) external {
        _burn(_from, _amount);
    }
}
