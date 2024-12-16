// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";

import {Token} from "./Token.sol";
import {OracleConfigurator} from "./oracle/OracleConfigurator.sol";

import "./Errors.sol";

contract StoneBeraVault is AccessControl {
    using Math for uint256;

    bytes32 public constant VAULT_OPERATOR_ROLE =
        keccak256("VAULT_OPERATOR_ROLE");
    bytes32 public constant ASSETS_MANAGEMENT_ROLE =
        keccak256("ASSETS_MANAGEMENT_ROLE");

    uint256 public constant D18 = 1e18;
    uint256 public constant D6 = 1e6;

    Token public immutable lpToken;
    ERC20 public immutable withdrawToken;

    OracleConfigurator public immutable oracleConfigurator;

    address[] public underlyingAssets;

    mapping(address => bool) public isUnderlyingAssets;
    mapping(address => RedeemRequest) public redeemRequests;
    mapping(uint256 => uint256) public roundPricePerShare;
    mapping(uint256 => uint256) public withdrawTokenPrice;
    mapping(address => bool) public depositPaused;

    mapping(address => uint256) public feeRate;

    uint256 public latestRoundID;
    uint256 public cap;
    uint256 public assetsBorrowed;

    uint256 public redeemableAmountInPast; // calculated as withdrawToken
    uint256 public requestingSharesInPast; // calculated as share
    uint256 public requestingSharesInRound; // calculated as share

    address public feeRecipient;

    struct RedeemRequest {
        uint256 requestRound;
        uint256 requestShares;
    }

    event Deposit(
        address indexed caller,
        address indexed owner,
        address indexed asset,
        uint256 amount,
        uint256 shares
    );
    event RedeemRequested(address indexed owner, uint256 shares, uint256 round);
    event RedeemCancelled(address indexed owner, uint256 shares, uint256 round);
    event RedeemClaimed(address indexed owner, uint256 amount);
    event RollToNextRound(
        uint256 round,
        uint256 share,
        uint256 withdrawTokenAmount,
        uint256 sharePrice,
        uint256 withdrawTokenPrice
    );
    event FeeCharged(address recipient, uint256 fee);
    event SetCap(uint256 oldValue, uint256 newValue);
    event SetDepositPause(address indexed asset, bool flag);
    event SetFeeRate(address indexed asset, uint256 feeRate);
    event SetFeeRecipient(address oldValue, address newValue);
    event AddUnderlyingAsset(address indexed asset);
    event RemoveUnderlyingAsset(address indexed asset);
    event AssetsWithdrawn(address indexed asset, uint256 amount, uint256 value);
    event AssetsRepaid(address indexed asset, uint256 amount, uint256 value);

    constructor(
        address _lpToken,
        address _withdrawToken,
        address _oracleConfigurator,
        uint256 _cap
    ) {
        if (
            _lpToken == address(0) ||
            _withdrawToken == address(0) ||
            _oracleConfigurator == address(0)
        ) revert ZeroAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        lpToken = Token(_lpToken);
        withdrawToken = Token(_withdrawToken);
        cap = _cap;

        oracleConfigurator = OracleConfigurator(_oracleConfigurator);

        if (oracleConfigurator.oracles(address(_withdrawToken)) == address(0))
            revert InvalidOracle();
    }

    function deposit(
        address _asset,
        uint256 _amount,
        address _receiver
    ) public returns (uint256 shares) {
        if (depositPaused[_asset]) revert DepositPaused();
        if ((shares = previewDeposit(_asset, _amount)) == 0)
            revert ZeroShares();

        if (lpToken.totalSupply() + shares > cap) revert DepositCapped();

        TransferHelper.safeTransferFrom(
            _asset,
            msg.sender,
            address(this),
            _amount
        );

        uint256 fee;
        uint256 rate = feeRate[_asset];
        if (rate != 0) {
            fee = shares.mulDiv(rate, D6);
        }

        if (fee == 0) {
            lpToken.mint(_receiver, shares);
        } else {
            shares -= fee;
            lpToken.mint(_receiver, shares);
            lpToken.mint(feeRecipient, fee);

            emit FeeCharged(feeRecipient, fee);
        }

        emit Deposit(msg.sender, _receiver, _asset, _amount, shares);
    }

    function mint(
        address _asset,
        uint256 _shares,
        address _receiver
    ) external returns (uint256 assets) {
        if (depositPaused[_asset]) revert DepositPaused();
        if (_shares == 0) revert ZeroShares();
        if (lpToken.totalSupply() + _shares > cap) revert DepositCapped();

        assets = previewMint(_asset, _shares);

        TransferHelper.safeTransferFrom(
            _asset,
            msg.sender,
            address(this),
            assets
        );

        uint256 fee;
        uint256 rate = feeRate[_asset];
        if (rate != 0) {
            fee = _shares.mulDiv(rate, D6);
        }

        if (fee == 0) {
            lpToken.mint(_receiver, _shares);
        } else {
            _shares -= fee;
            lpToken.mint(_receiver, _shares);
            lpToken.mint(feeRecipient, fee);

            emit FeeCharged(feeRecipient, fee);
        }

        emit Deposit(msg.sender, _receiver, _asset, assets, _shares);
    }

    function requestRedeem(uint256 _shares) external {
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
            redeemRequest.requestShares += _shares;
        } else {
            redeemRequest.requestRound = latestRoundID;
            redeemRequest.requestShares = _shares;
        }
        requestingSharesInRound += _shares;

        emit RedeemRequested(msg.sender, _shares, latestRoundID);
    }

    function cancelRequest() external {
        if (pendingRedeemRequest() == 0) revert NoRequestingShares();

        RedeemRequest storage redeemRequest = redeemRequests[msg.sender];

        uint256 requestingShares = redeemRequest.requestShares;
        redeemRequest.requestShares = 0;

        requestingSharesInRound -= requestingShares;

        TransferHelper.safeTransfer(
            address(lpToken),
            msg.sender,
            requestingShares
        );

        emit RedeemCancelled(msg.sender, requestingShares, latestRoundID);
    }

    function claimRedeemRequest() public {
        RedeemRequest storage redeemRequest = redeemRequests[msg.sender];
        uint256 requestShares = redeemRequest.requestShares;

        uint256 claimable;
        uint256 round = redeemRequest.requestRound;
        if (round < latestRoundID && redeemRequest.requestShares != 0) {
            claimable = redeemRequest.requestShares.mulDiv(
                roundPricePerShare[round],
                withdrawTokenPrice[round],
                Math.Rounding.Floor
            );
        } else {
            revert NoClaimableRedeem();
        }

        lpToken.burn(address(this), requestShares);

        redeemRequest.requestShares = 0;

        redeemableAmountInPast -= claimable;
        requestingSharesInPast -= requestShares;

        if (claimable > 0)
            TransferHelper.safeTransfer(
                address(withdrawToken),
                msg.sender,
                claimable
            );

        emit RedeemClaimed(msg.sender, claimable);
    }

    function pendingRedeemRequest() public view returns (uint256 shares) {
        RedeemRequest memory redeemRequest = redeemRequests[msg.sender];

        return
            redeemRequest.requestRound == latestRoundID
                ? redeemRequest.requestShares
                : 0;
    }

    function claimableRedeemRequest() external view returns (uint256 assets) {
        RedeemRequest memory redeemRequest = redeemRequests[msg.sender];

        uint256 round = redeemRequest.requestRound;
        if (round < latestRoundID && redeemRequest.requestShares != 0) {
            assets = redeemRequest.requestShares.mulDiv(
                roundPricePerShare[round],
                withdrawTokenPrice[round],
                Math.Rounding.Floor
            );
        }
    }

    function totalAssets() public view returns (uint256 totalManagedAssets) {
        uint256 length = underlyingAssets.length;
        uint256 i;

        address _this = address(this);

        for (i; i < length; i++) {
            address tokenAddr = underlyingAssets[i];
            ERC20 token = ERC20(tokenAddr);
            uint256 balance = token.balanceOf(_this);

            if (balance != 0) {
                uint256 price = oracleConfigurator.getPrice(tokenAddr);
                uint256 value = price.mulDiv(balance, D18, Math.Rounding.Floor);

                totalManagedAssets += value;
            }
        }
        totalManagedAssets += assetsBorrowed;
    }

    function activeAssets() public view returns (uint256 assets) {
        uint256 price = oracleConfigurator.getPrice(address(withdrawToken));
        uint256 reservedValue = redeemableAmountInPast.mulDiv(
            price,
            D18,
            Math.Rounding.Floor
        );

        return totalAssets() - reservedValue;
    }

    function activeShares() public view returns (uint256 shares) {
        return lpToken.totalSupply() - requestingSharesInPast;
    }

    function convertToShares(
        uint256 _assets
    ) public view returns (uint256 shares) {
        uint256 supply = lpToken.totalSupply();

        return
            supply == 0
                ? _assets
                : _assets.mulDiv(
                    activeShares(),
                    activeAssets(),
                    Math.Rounding.Floor
                );
    }

    function convertToAssets(
        uint256 _shares
    ) public view returns (uint256 assets) {
        uint256 supply = lpToken.totalSupply();

        return
            supply == 0
                ? _shares
                : _shares.mulDiv(
                    activeAssets(),
                    activeShares(),
                    Math.Rounding.Floor
                );
    }

    function previewDeposit(
        address _asset,
        uint256 _amount
    ) public view returns (uint256 shares) {
        if (!isUnderlyingAssets[_asset]) revert InvalidAsset();

        uint256 price = oracleConfigurator.getPrice(_asset);
        uint256 value = _amount.mulDiv(price, D18, Math.Rounding.Floor);

        return convertToShares(value);
    }

    function previewMint(
        address _asset,
        uint256 _shares
    ) public view returns (uint256 assets) {
        if (!isUnderlyingAssets[_asset]) revert InvalidAsset();

        uint256 price = oracleConfigurator.getPrice(_asset);
        uint256 amount = _shares.mulDiv(D18, price, Math.Rounding.Ceil);
        uint256 supply = lpToken.totalSupply();

        return
            supply == 0
                ? amount
                : amount.mulDiv(
                    activeAssets(),
                    activeShares(),
                    Math.Rounding.Ceil
                );
    }

    function getRate() public view returns (uint256 rate) {
        return activeAssets().mulDiv(D18, activeShares(), Math.Rounding.Floor);
    }

    function getUnderlyings()
        external
        view
        returns (address[] memory underlyings)
    {
        return underlyingAssets;
    }

    function rollToNextRound() external onlyRole(VAULT_OPERATOR_ROLE) {
        uint256 price = oracleConfigurator.getPrice(address(withdrawToken));
        uint256 rate = getRate();

        uint256 requestingShares = requestingSharesInRound;
        uint256 withdrawTokenAmount = requestingShares.mulDiv(
            rate,
            price,
            Math.Rounding.Ceil
        );

        if (
            withdrawToken.balanceOf(address(this)) <
            redeemableAmountInPast + withdrawTokenAmount
        ) revert InsufficientBalance();

        redeemableAmountInPast += withdrawTokenAmount;
        requestingSharesInPast += requestingShares;
        requestingSharesInRound = 0;

        roundPricePerShare[latestRoundID] = rate;
        withdrawTokenPrice[latestRoundID] = price;

        emit RollToNextRound(
            latestRoundID,
            requestingShares,
            withdrawTokenAmount,
            rate,
            price
        );
        latestRoundID++;
    }

    function withdrawAssets(
        address _asset,
        uint256 _amount
    ) external onlyRole(ASSETS_MANAGEMENT_ROLE) {
        if (!isUnderlyingAssets[_asset]) revert InvalidAsset();

        uint256 balance = ERC20(_asset).balanceOf(address(this));
        if (balance < _amount) revert InsufficientBalance();

        if (
            _asset == address(withdrawToken) &&
            balance < redeemableAmountInPast + _amount
        ) revert InsufficientBalance();

        uint256 price = oracleConfigurator.getPrice(_asset);
        uint256 value = _amount.mulDiv(price, D18, Math.Rounding.Ceil);

        assetsBorrowed += value;

        TransferHelper.safeTransfer(_asset, msg.sender, _amount);

        emit AssetsWithdrawn(_asset, _amount, value);
    }

    function repayAssets(
        address _asset,
        uint256 _amount
    ) external onlyRole(ASSETS_MANAGEMENT_ROLE) {
        if (!isUnderlyingAssets[_asset]) revert InvalidAsset();

        TransferHelper.safeTransferFrom(
            _asset,
            msg.sender,
            address(this),
            _amount
        );

        uint256 price = oracleConfigurator.getPrice(_asset);
        uint256 value = _amount.mulDiv(price, D18, Math.Rounding.Floor);

        if (value > assetsBorrowed) {
            assetsBorrowed = 0;
        } else {
            assetsBorrowed -= value;
        }

        emit AssetsRepaid(_asset, _amount, value);
    }

    function setCap(uint256 _cap) external onlyRole(VAULT_OPERATOR_ROLE) {
        emit SetCap(cap, _cap);
        cap = _cap;
    }

    function addUnderlyingAsset(
        address _asset
    ) external onlyRole(VAULT_OPERATOR_ROLE) {
        if (_asset == address(0) || isUnderlyingAssets[_asset])
            revert InvalidAsset();
        if (oracleConfigurator.oracles(_asset) == address(0))
            revert InvalidOracle();

        isUnderlyingAssets[_asset] = true;
        underlyingAssets.push(_asset);

        emit AddUnderlyingAsset(_asset);
    }

    function removeUnderlyingAsset(
        address _asset
    ) external onlyRole(VAULT_OPERATOR_ROLE) {
        if (!isUnderlyingAssets[_asset]) revert InvalidAsset();

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
        isUnderlyingAssets[_asset] = false;

        emit RemoveUnderlyingAsset(_asset);
    }

    function setDepositPause(
        address _token,
        bool _pause
    ) external onlyRole(VAULT_OPERATOR_ROLE) {
        depositPaused[_token] = _pause;
        emit SetDepositPause(_token, _pause);
    }

    function setFeeRate(
        address _token,
        uint256 _feeRate
    ) external onlyRole(VAULT_OPERATOR_ROLE) {
        if (feeRecipient == address(0)) revert NoFeeRecipient();
        if (!isUnderlyingAssets[_token]) revert InvalidAsset();
        if (_feeRate > D6) revert InvalidFeeRate();

        feeRate[_token] = _feeRate;

        emit SetFeeRate(_token, _feeRate);
    }

    function setFeeRecipient(
        address _feeRecipient
    ) external onlyRole(VAULT_OPERATOR_ROLE) {
        if (_feeRecipient == address(0)) revert ZeroAddress();

        emit SetFeeRecipient(feeRecipient, _feeRecipient);
        feeRecipient = _feeRecipient;
    }
}
