// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {Oracle} from "./Oracle.sol";
import "../Errors.sol";

contract OracleConfigurator is AccessControl {
    bytes32 public constant ORACLE_MANAGER_ROLE =
        keccak256("ORACLE_MANAGER_ROLE");

    mapping(address => address) public oracles;

    event OracleUpdated(address oldOracle, address newOracle);

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function updateOracle(
        address _token,
        address _oracle
    ) external onlyRole(ORACLE_MANAGER_ROLE) {
        if (_token == address(0)) revert InvalidToken();
        if (_oracle == address(0)) revert InvalidOracle();

        emit OracleUpdated(oracles[_token], _oracle);

        oracles[_token] = _oracle;
    }

    function getPrice(address _token) external view returns (uint256 price) {
        address oracle = oracles[_token];

        if (_token == address(0) || oracle == address(0)) revert InvalidToken();

        price = Oracle(oracle).getPrice();
    }
}
