// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IStrategy {
    // ==========================================
    //                   Events
    // ==========================================
    event DepositMade(address indexed user, uint256 amount);
    event WithdrawMade(address indexed user, uint256 assets, uint256 shares);
    // ==========================================
    //                  Functions
    // ==========================================
    function deposit(uint256 _amount) external returns (uint256 shares);
    function withdraw(uint256 shares) external returns (uint256 assets);
    function totalAssets() external view returns (uint256 totalAmount);
}
