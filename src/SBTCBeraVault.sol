// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import {Token} from "./Token.sol";

import "./Errors.sol";

contract SBTCBeraVault is AccessControl {
    bytes32 public constant VAULT_OPERATOR_ROLE =
        keccak256("VAULT_OPERATOR_ROLE");
    bytes32 public constant ASSETS_MANAGEMENT_ROLE =
        keccak256("ASSETS_MANAGEMENT_ROLE");

    uint256 public constant D18 = 1e18;

    Token public immutable lpToken;

    address[] public underlyingAssets;
    address[] public withdrawTokens;

    mapping(address => uint8) public tokenDecimals;
    mapping(address => bool) public isUnderlyingAsset;
    mapping(address => bool) public isWithdrawToken;
    mapping(address => RedeemRequest) public redeemRequests;

    mapping(address => bool) public depositPaused;

    uint256 public latestRoundID;
    uint256 public cap;

    uint256 public requestingSharesInPast;
    mapping(address => uint256) public requestingSharesInRound;
    mapping(address => uint256) public redeemableAmountInPast;

    struct RedeemRequest {
        uint256 requestRound;
        address requestToken;
        uint256 requestShares;
    }

    event Deposit(
        address indexed caller,
        address indexed owner,
        address indexed asset,
        uint256 amount,
        uint256 shares
    );
    event RedeemRequested(
        address indexed owner,
        address indexed requestToken,
        uint256 shares,
        uint256 round
    );
    event RedeemCancelled(
        address indexed owner,
        address indexed requestToken,
        uint256 shares,
        uint256 round
    );
    event RedeemClaimed(
        address indexed owner,
        address indexed claimToken,
        uint256 amount
    );
    event RollToNextRound(uint256 round, uint256 share);
    event SetCap(uint256 oldValue, uint256 newValue);
    event SetDepositPause(address asset, bool flag);
    event AddUnderlyingAsset(address indexed asset);
    event RemoveUnderlyingAsset(address indexed asset);
    event AddWithdrawToken(address indexed withdrawToken);
    event RemoveWithdrawToken(address indexed withdrawToken);
    event AssetsWithdrawn(address indexed asset, uint256 amount);
    event AssetsRepaid(address indexed asset, uint256 amount);

    constructor(address _lpToken, uint256 _cap) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        lpToken = Token(_lpToken);
        cap = _cap;
    }

    function deposit(
        address _asset,
        uint256 _amount,
        address _receiver
    ) public returns (uint256 shares) {
        if ((shares = previewDeposit(_asset, _amount)) == 0)
            revert ZeroShares();

        if (lpToken.totalSupply() + shares > cap) revert DepositCapped();

        TransferHelper.safeTransferFrom(
            _asset,
            msg.sender,
            address(this),
            _amount
        );

        lpToken.mint(_receiver, shares);

        emit Deposit(msg.sender, _receiver, _asset, _amount, shares);
    }

    function mint(
        address _asset,
        uint256 _shares,
        address _receiver
    ) external returns (uint256 assets) {
        if (_shares == 0) revert ZeroShares();
        if (lpToken.totalSupply() + _shares > cap) revert DepositCapped();

        assets = previewMint(_asset, _shares);

        TransferHelper.safeTransferFrom(
            _asset,
            msg.sender,
            address(this),
            assets
        );

        lpToken.mint(_receiver, _shares);

        emit Deposit(msg.sender, _receiver, _asset, assets, _shares);
    }

    function requestRedeem(address _requestToken, uint256 _shares) external {
        if (!isWithdrawToken[_requestToken]) revert InvalidRequestToken();
        if (_shares == 0) revert ZeroShares();
        if (_shares > lpToken.balanceOf(msg.sender))
            revert InsufficientBalance();

        TransferHelper.safeTransferFrom(
            address(lpToken),
            msg.sender,
            address(this),
            _shares
        );

        RedeemRequest storage redeemRequest = redeemRequests[msg.sender];

        if (
            redeemRequest.requestShares > 0 &&
            redeemRequest.requestRound < latestRoundID
        ) {
            claimRedeemRequest();
        }

        if (redeemRequest.requestRound == latestRoundID) {
            if (
                redeemRequest.requestToken != address(0) &&
                redeemRequest.requestToken != _requestToken
            ) revert InvalidRequest();
            redeemRequest.requestToken = _requestToken;
            redeemRequest.requestShares += _shares;
        } else {
            redeemRequest.requestRound = latestRoundID;
            redeemRequest.requestToken = _requestToken;
            redeemRequest.requestShares = _shares;
        }
        requestingSharesInRound[_requestToken] += _shares;

        emit RedeemRequested(msg.sender, _requestToken, _shares, latestRoundID);
    }

    function cancelRequest() external {
        (
            address requestToken,
            uint256 requestingShares
        ) = pendingRedeemRequest();
        if (requestingShares == 0) revert NoRequestingShares();

        RedeemRequest storage redeemRequest = redeemRequests[msg.sender];

        redeemRequest.requestShares = 0;
        redeemRequest.requestToken = address(0);

        requestingSharesInRound[requestToken] -= requestingShares;

        TransferHelper.safeTransfer(
            address(lpToken),
            msg.sender,
            requestingShares
        );

        emit RedeemCancelled(
            msg.sender,
            requestToken,
            requestingShares,
            latestRoundID
        );
    }

    function claimRedeemRequest() public {
        (address requestToken, uint256 claimable) = claimableRedeemRequest();
        if (claimable == 0) revert NoClaimableRedeem();

        RedeemRequest storage redeemRequest = redeemRequests[msg.sender];
        uint256 requestShares = redeemRequest.requestShares;

        lpToken.burn(address(this), requestShares);

        redeemRequest.requestToken = address(0);
        redeemRequest.requestShares = 0;

        redeemableAmountInPast[requestToken] -= claimable;
        requestingSharesInPast -= requestShares;

        TransferHelper.safeTransfer(requestToken, msg.sender, claimable);

        emit RedeemClaimed(msg.sender, requestToken, claimable);
    }

    function pendingRedeemRequest()
        public
        view
        returns (address requestToken, uint256 shares)
    {
        RedeemRequest memory redeemRequest = redeemRequests[msg.sender];

        if (redeemRequest.requestRound == latestRoundID) {
            requestToken = redeemRequest.requestToken;
            shares = redeemRequest.requestShares;
        }
    }

    function claimableRedeemRequest()
        public
        view
        returns (address requestToken, uint256 assets)
    {
        RedeemRequest memory redeemRequest = redeemRequests[msg.sender];
        requestToken = redeemRequest.requestToken;

        uint256 round = redeemRequest.requestRound;
        uint256 shares = redeemRequest.requestShares;
        if (round < latestRoundID && shares != 0) {
            uint8 decimals = tokenDecimals[requestToken];
            assets = shares / (10 ** (18 - decimals));
        }
    }

    function previewDeposit(
        address _asset,
        uint256 _amount
    ) public view returns (uint256 shares) {
        if (depositPaused[_asset]) revert DepositPaused();
        if (!isUnderlyingAsset[_asset]) revert InvalidAsset();

        uint8 decimal = tokenDecimals[_asset];

        shares = _amount * (10 ** (18 - decimal));

        if (lpToken.totalSupply() + shares > cap) revert DepositCapped();
    }

    function previewMint(
        address _asset,
        uint256 _shares
    ) public view returns (uint256 assets) {
        if (depositPaused[_asset]) revert DepositPaused();
        if (!isUnderlyingAsset[_asset]) revert InvalidAsset();
        if (lpToken.totalSupply() + _shares > cap) revert DepositCapped();

        uint8 decimal = tokenDecimals[_asset];

        assets = _shares / (10 ** (18 - decimal));
    }

    function getRate() public pure returns (uint256 rate) {
        return D18;
    }

    function getUnderlyings()
        external
        view
        returns (address[] memory underlyings)
    {
        return underlyingAssets;
    }

    function rollToNextRound() external onlyRole(VAULT_OPERATOR_ROLE) {
        address[] memory tokens = withdrawTokens;

        uint256 requestingShares;
        uint256 length = tokens.length;
        uint256 i;
        for (i; i < length; i++) {
            address token = tokens[i];

            uint256 shares = requestingSharesInRound[token];
            uint8 decimal = tokenDecimals[token];
            uint256 withdrawAmount = shares / (10 ** (18 - decimal));

            if (
                ERC20(token).balanceOf(address(this)) <
                redeemableAmountInPast[token] + withdrawAmount
            ) revert InsufficientBalance();

            requestingShares += shares;

            redeemableAmountInPast[token] += withdrawAmount;
            requestingSharesInRound[token] = 0;
        }

        requestingSharesInPast += requestingShares;

        latestRoundID++;

        emit RollToNextRound(latestRoundID, requestingShares);
    }

    function withdrawAssets(
        address _asset,
        uint256 _amount
    ) external onlyRole(ASSETS_MANAGEMENT_ROLE) {
        if (!isUnderlyingAsset[_asset]) revert InvalidAsset();

        uint256 balance = ERC20(_asset).balanceOf(address(this));
        if (balance < _amount) revert InsufficientBalance();

        if (
            isWithdrawToken[_asset] &&
            balance < redeemableAmountInPast[_asset] + _amount
        ) revert InsufficientBalance();

        TransferHelper.safeTransfer(_asset, msg.sender, _amount);

        emit AssetsWithdrawn(_asset, _amount);
    }

    function repayAssets(
        address _asset,
        uint256 _amount
    ) external onlyRole(ASSETS_MANAGEMENT_ROLE) {
        if (!isUnderlyingAsset[_asset]) revert InvalidAsset();

        TransferHelper.safeTransferFrom(
            _asset,
            msg.sender,
            address(this),
            _amount
        );

        emit AssetsRepaid(_asset, _amount);
    }

    function setCap(uint256 _cap) external onlyRole(VAULT_OPERATOR_ROLE) {
        emit SetCap(cap, _cap);
        cap = _cap;
    }

    function addUnderlyingAsset(
        address _asset
    ) external onlyRole(VAULT_OPERATOR_ROLE) {
        if (_asset == address(0) || isUnderlyingAsset[_asset])
            revert InvalidAsset();

        isUnderlyingAsset[_asset] = true;
        underlyingAssets.push(_asset);

        uint8 decimals = ERC20(_asset).decimals();
        if (decimals > 18) revert InvalidDecimals();
        tokenDecimals[_asset] = decimals;

        emit AddUnderlyingAsset(_asset);
    }

    function removeUnderlyingAsset(
        address _asset
    ) external onlyRole(VAULT_OPERATOR_ROLE) {
        if (!isUnderlyingAsset[_asset]) revert InvalidAsset();

        address[] memory assets = underlyingAssets;

        uint256 length = assets.length;
        uint256 i;
        for (i; i < length; i++) {
            if (assets[i] == _asset) {
                underlyingAssets[i] = underlyingAssets[length - 1];
                underlyingAssets.pop();
                break;
            }
        }
        isUnderlyingAsset[_asset] = false;
        delete tokenDecimals[_asset];

        emit RemoveUnderlyingAsset(_asset);
    }

    function addWithdrawToken(
        address _withdrawToken
    ) external onlyRole(VAULT_OPERATOR_ROLE) {
        if (_withdrawToken == address(0) || isWithdrawToken[_withdrawToken])
            revert InvalidAsset();

        isWithdrawToken[_withdrawToken] = true;
        withdrawTokens.push(_withdrawToken);

        emit AddWithdrawToken(_withdrawToken);
    }

    function removeWithdrawToken(
        address _withdrawToken
    ) external onlyRole(VAULT_OPERATOR_ROLE) {
        if (!isWithdrawToken[_withdrawToken]) revert InvalidAsset();
        if (requestingSharesInRound[_withdrawToken] != 0) revert CannotRemove();

        address[] memory assets = withdrawTokens;

        uint256 length = assets.length;
        uint256 i;
        for (i; i < length; i++) {
            if (assets[i] == _withdrawToken) {
                withdrawTokens[i] = withdrawTokens[length - 1];
                withdrawTokens.pop();
                break;
            }
        }
        isWithdrawToken[_withdrawToken] = false;

        emit RemoveWithdrawToken(_withdrawToken);
    }

    function setDepositPause(
        address _token,
        bool _pause
    ) external onlyRole(VAULT_OPERATOR_ROLE) {
        depositPaused[_token] = _pause;
        emit SetDepositPause(_token, _pause);
    }
}
