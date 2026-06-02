// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../lib/PRBMath.sol";

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

contract CollateralManager {
    using PRBMath for uint256;

    uint256 public constant PRICE_UNIT = 1e18;
    uint256 public constant COLLATERALIZATION_RATIO = 150e16;
    uint256 public constant LIQUIDATION_THRESHOLD = 110e16;
    uint256 public constant LIQUIDATION_BONUS = 105e16;

    address public owner;
    mapping(address => mapping(address => uint256)) private collateralDeposits;
    mapping(address => uint256) private debtBalances;
    mapping(address => uint256) public prices;
    address[] public collateralTokens;
    mapping(address => bool) public isCollateralToken;

    event CollateralDeposited(address indexed account, address indexed token, uint256 amount);
    event CollateralWithdrawn(address indexed account, address indexed token, uint256 amount);
    event DebtBorrowed(address indexed account, uint256 amount);
    event DebtRepaid(address indexed account, uint256 amount);
    event Liquidated(address indexed borrower, address indexed liquidator, address token, uint256 debtRepaid, uint256 collateralSeized);
    event PriceUpdated(address indexed token, uint256 price);

    modifier onlyOwner() {
        require(msg.sender == owner, "CollateralManager: caller is not owner");
        _;
    }

    modifier positiveAmount(uint256 amount) {
        require(amount > 0, "CollateralManager: amount must be greater than zero");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function depositCollateral(address token, uint256 amount) external positiveAmount(amount) {
        require(IERC20(token).transferFrom(msg.sender, address(this), amount), "CollateralManager: transfer failed");
        collateralDeposits[msg.sender][token] += amount;
        if (!isCollateralToken[token]) {
            isCollateralToken[token] = true;
            collateralTokens.push(token);
        }
        emit CollateralDeposited(msg.sender, token, amount);
    }

    function withdrawCollateral(address token, uint256 amount) external positiveAmount(amount) {
        uint256 current = collateralDeposits[msg.sender][token];
        require(amount <= current, "CollateralManager: insufficient collateral");

        collateralDeposits[msg.sender][token] = current - amount;
        require(_isHealthy(msg.sender), "CollateralManager: withdrawal would undercollateralize position");

        require(IERC20(token).transfer(msg.sender, amount), "CollateralManager: transfer failed");
        emit CollateralWithdrawn(msg.sender, token, amount);
    }

    function borrow(uint256 amount) external positiveAmount(amount) {
        uint256 newDebt = debtBalances[msg.sender] + amount;
        require(_isCollateralized(msg.sender, newDebt), "CollateralManager: insufficient collateral to borrow");

        debtBalances[msg.sender] = newDebt;
        emit DebtBorrowed(msg.sender, amount);
    }

    function repay(uint256 amount) external positiveAmount(amount) {
        uint256 currentDebt = debtBalances[msg.sender];
        require(amount <= currentDebt, "CollateralManager: repay amount exceeds debt");
        debtBalances[msg.sender] = currentDebt - amount;
        emit DebtRepaid(msg.sender, amount);
    }

    function liquidate(address borrower, address token, uint256 debtToCover) external positiveAmount(debtToCover) {
        require(_canBeLiquidated(borrower), "CollateralManager: borrower is not liquidatable");
        require(prices[token] > 0, "CollateralManager: token price is not set");
        require(debtToCover <= debtBalances[borrower], "CollateralManager: debtToCover exceeds borrower debt");

        uint256 debitedValue = PRBMath.mulDiv(debtToCover, LIQUIDATION_BONUS, PRICE_UNIT);
        uint256 collateralRequired = PRBMath.mulDiv(debitedValue, PRICE_UNIT, prices[token]);
        uint256 currentCollateral = collateralDeposits[borrower][token];
        require(collateralRequired <= currentCollateral, "CollateralManager: not enough collateral in selected token");

        debtBalances[borrower] -= debtToCover;
        collateralDeposits[borrower][token] = currentCollateral - collateralRequired;

        require(IERC20(token).transfer(msg.sender, collateralRequired), "CollateralManager: transfer failed");
        emit Liquidated(borrower, msg.sender, token, debtToCover, collateralRequired);
    }

    function updatePrice(address token, uint256 price) external onlyOwner {
        require(price > 0, "CollateralManager: price must be greater than zero");
        prices[token] = price;
        emit PriceUpdated(token, price);
    }

    function getCollateralAmount(address account, address token) external view returns (uint256) {
        return collateralDeposits[account][token];
    }

    function getCollateralValue(address account, address token) public view returns (uint256) {
        return PRBMath.mulDiv(collateralDeposits[account][token], prices[token], PRICE_UNIT);
    }

    function getTotalCollateralValue(address account) public view returns (uint256) {
        return _getTotalCollateralValue(account);
    }

    function getDebt(address account) external view returns (uint256) {
        return debtBalances[account];
    }

    function getRequiredCollateralValue(address account) external view returns (uint256) {
        return PRBMath.mulDiv(debtBalances[account], COLLATERALIZATION_RATIO, PRICE_UNIT);
    }

    function getHealthFactor(address account) external view returns (uint256) {
        uint256 debt = debtBalances[account];
        if (debt == 0) {
            return type(uint256).max;
        }
        uint256 required = PRBMath.mulDiv(debt, COLLATERALIZATION_RATIO, PRICE_UNIT);
        if (required == 0) {
            return type(uint256).max;
        }
        return PRBMath.mulDiv(_getTotalCollateralValue(account), PRICE_UNIT, required);
    }

    function canBeLiquidated(address account) external view returns (bool) {
        return _canBeLiquidated(account);
    }

    function _isCollateralized(address account, uint256 debt) internal view returns (bool) {
        if (debt == 0) {
            return true;
        }
        return _getTotalCollateralValue(account) >= PRBMath.mulDiv(debt, COLLATERALIZATION_RATIO, PRICE_UNIT);
    }

    function _isHealthy(address account) internal view returns (bool) {
        return _isCollateralized(account, debtBalances[account]);
    }

    function _canBeLiquidated(address account) internal view returns (bool) {
        uint256 debt = debtBalances[account];
        if (debt == 0) {
            return false;
        }
        return _getTotalCollateralValue(account) < PRBMath.mulDiv(debt, LIQUIDATION_THRESHOLD, PRICE_UNIT);
    }

    function _getTotalCollateralValue(address account) internal view returns (uint256) {
        uint256 total;
        address[] memory tokens = _getKnownTokens();
        for (uint256 i = 0; i < tokens.length; i++) {
            total += PRBMath.mulDiv(collateralDeposits[account][tokens[i]], prices[tokens[i]], PRICE_UNIT);
        }
        return total;
    }

    function _getKnownTokens() internal view returns (address[] storage) {
        return collateralTokens;
    }
}
