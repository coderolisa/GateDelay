// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../contracts/CollateralManager.sol";

contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(string memory name_, string memory symbol_) {
        name = name_;
        symbol = symbol_;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address recipient, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "MockERC20: insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[recipient] += amount;
        emit Transfer(msg.sender, recipient, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool) {
        require(balanceOf[sender] >= amount, "MockERC20: insufficient balance");
        require(allowance[sender][msg.sender] >= amount, "MockERC20: allowance exceeded");
        allowance[sender][msg.sender] -= amount;
        balanceOf[sender] -= amount;
        balanceOf[recipient] += amount;
        emit Transfer(sender, recipient, amount);
        return true;
    }

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }
}

contract UserWallet {
    MockERC20 public token;
    CollateralManager public manager;

    constructor(MockERC20 token_, CollateralManager manager_) {
        token = token_;
        manager = manager_;
    }

    function deposit(address tokenAddr, uint256 amount) external {
        manager.depositCollateral(tokenAddr, amount);
    }

    function withdraw(address tokenAddr, uint256 amount) external {
        manager.withdrawCollateral(tokenAddr, amount);
    }

    function borrow(uint256 amount) external {
        manager.borrow(amount);
    }

    function repay(uint256 amount) external {
        manager.repay(amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        return token.approve(spender, amount);
    }
}

contract Liquidator {
    CollateralManager public manager;

    constructor(CollateralManager manager_) {
        manager = manager_;
    }

    function liquidate(address borrower, address tokenAddr, uint256 amount) external {
        manager.liquidate(borrower, tokenAddr, amount);
    }
}

contract CollateralManagerTest {
    CollateralManager internal manager;
    MockERC20 internal collateral;
    UserWallet internal user;
    Liquidator internal liquidator;

    function setUp() public {
        manager = new CollateralManager();
        collateral = new MockERC20("Collateral", "COL");
        user = new UserWallet(collateral, manager);
        liquidator = new Liquidator(manager);

        collateral.mint(address(user), 200e18);
        collateral.mint(address(liquidator), 200e18);
        collateral.mint(address(this), 200e18);
        manager.updatePrice(address(collateral), 1e18);

        collateral.approve(address(manager), 200e18);
        user.approve(address(manager), 200e18);
    }

    function assertEq(uint256 a, uint256 b, string memory message) internal pure {
        if (a != b) {
            revert(message);
        }
    }

    function assertTrue(bool condition, string memory message) internal pure {
        if (!condition) {
            revert(message);
        }
    }

    function testDepositAndCollateralQueries() public {
        user.approve(address(manager), 100e18);
        user.deposit(address(collateral), 100e18);

        assertEq(manager.getCollateralAmount(address(user), address(collateral)), 100e18, "Collateral amount mismatch");
        assertEq(manager.getCollateralValue(address(user), address(collateral)), 100e18, "Collateral value mismatch");
    }

    function testBorrowAndHealthFactor() public {
        user.approve(address(manager), 120e18);
        user.deposit(address(collateral), 120e18);
        user.borrow(60e18);

        uint256 expectedRequired = 90e18;
        assertTrue(manager.getDebt(address(user)) == 60e18, "Debt should be 60");
        assertTrue(manager.getCollateralValue(address(user), address(collateral)) == 120e18, "Collateral value should be 120");
        assertTrue(manager.getHealthFactor(address(user)) > 1e18, "Health factor should be above 1.0");
        assertTrue(manager.getRequiredCollateralValue(address(user)) == expectedRequired, "Required collateral mismatch");
    }

    function testWithdrawRevertsWhenUndercollateralized() public {
        user.approve(address(manager), 120e18);
        user.deposit(address(collateral), 120e18);
        user.borrow(70e18);

        bool reverted = false;
        try user.withdraw(address(collateral), 16e18) {
            reverted = false;
        } catch {
            reverted = true;
        }

        assertTrue(reverted, "Expected undercollateralized withdrawal to revert");
    }

    function testLiquidationPath() public {
        collateral.approve(address(manager), 100e18);
        user.deposit(address(collateral), 100e18);
        user.borrow(50e18);

        manager.updatePrice(address(collateral), 5e17);
        assertTrue(manager.canBeLiquidated(address(user)), "Position should be liquidatable");

        liquidator.liquidate(address(user), address(collateral), 20e18);
        uint256 seized = 42_000000000000000000; // 42 tokens at price 0.5 with 5% bonus
        assertEq(collateral.balanceOf(address(liquidator)), 200e18 + seized, "Liquidator should receive collateral");
        assertEq(manager.getDebt(address(user)), 30e18, "Remaining debt should be 30");
    }
}
