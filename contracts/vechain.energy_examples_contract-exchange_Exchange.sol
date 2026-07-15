// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";
import "./IUniswapV2Router02.sol";

contract Exchange is Initializable, AccessControlUpgradeable, UUPSUpgradeable {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    address public exchangeRouter;

    event Deposit(address from, uint256 amount);
    event Withdraw(address to, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyRole(UPGRADER_ROLE)
    {}

    receive() external payable virtual {
        emit Deposit(_msgSender(), msg.value);
    }

    function withdraw(address payable account) public onlyRole(ADMIN_ROLE) {
        uint256 amount = address(this).balance;
        AddressUpgradeable.sendValue(account, amount);
        emit Withdraw(account, amount);
    }

    function setExchangeRouter(address newRouter) public onlyRole(ADMIN_ROLE) {
        exchangeRouter = newRouter;
    }

    function swap(IERC20Upgradeable token, uint256 minRate) public onlyRole(ADMIN_ROLE) {
        require(exchangeRouter != address(0), "exchangeRouter needs to be set");
        uint256 amountIn = token.balanceOf(address(this));
        uint256 amountOutMin = amountIn / minRate;

        require(
            token.approve(address(exchangeRouter), amountIn),
            "approve failed."
        );

        address[] memory path = new address[](2);
        path[0] = address(token);
        path[1] = IUniswapV2Router02(exchangeRouter).WETH();
        IUniswapV2Router02(exchangeRouter).swapExactTokensForETH(
            amountIn,
            amountOutMin,
            path,
            address(this),
            block.timestamp
        );
    }

    function swapForWallet(address account, IERC20Upgradeable token, uint256 minRate) public onlyRole(ADMIN_ROLE) {
        require(exchangeRouter != address(0), "exchangeRouter needs to be set");
        uint256 amountIn = token.balanceOf(account);
        uint256 amountOutMin = amountIn / minRate;

        SafeERC20Upgradeable.safeTransferFrom(token, account, address(this), amountIn);

        require(
            token.approve(address(exchangeRouter), amountIn),
            "approve failed."
        );
        
        address[] memory path = new address[](2);
        path[0] = address(token);
        path[1] = IUniswapV2Router02(exchangeRouter).WETH();
        IUniswapV2Router02(exchangeRouter).swapExactTokensForETH(
            amountIn,
            amountOutMin,
            path,
            account,
            block.timestamp
        );
    }
}
