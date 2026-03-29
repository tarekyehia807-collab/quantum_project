// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";

/**
 * @title Quantum Mock Strategy
 * @dev A professional mock strategy contract to simulate yield generation 
 * and external protocol interactions for the QuantumVault.
 */
contract QuantumStrategy is IStrategy {
    using SafeERC20 for IERC20;

    // =========================================
    //            State Variables
    // =========================================
    
    // Immutable variables save gas as they are embedded directly into the contract bytecode
    IERC20 public immutable asset;
    address public immutable vault;

    // =========================================
    //                 Errors
    // =========================================
    error QuantumStrategy__OnlyVaultAllowed();
    error QuantumStrategy__InsufficientLiquidity();

    // =========================================
    //                Modifiers
    // =========================================
    
    /**
     * @dev Restricts access to functions so that only the designated Vault can call them.
     * This prevents random users from directly depositing/withdrawing and messing up accounting.
     */
    modifier onlyVault() {
        if (msg.sender != vault) revert QuantumStrategy__OnlyVaultAllowed();
        _;
    }

    // =========================================
    //               Constructor
    // =========================================
    constructor(address _asset, address _vault) {
        require(_asset != address(0), "Invalid asset address");
        require(_vault != address(0), "Invalid vault address");
        
        asset = IERC20(_asset);
        vault = _vault;
    }

    // =========================================
    //             Core Functions
    // =========================================

    /**
     * @dev Returns the total amount of assets currently held by this strategy.
     * In a real strategy (like Aave), this would call aToken.balanceOf(address(this)).
     */
    function totalAssets() external view override returns (uint256) {
        return asset.balanceOf(address(this));
    }

    /**
     * @dev Accepts assets from the Vault.
     * Requires the Vault to have already called `asset.approve(strategy, amount)`.
     */
    function deposit(uint256 amount) external override onlyVault returns (uint256) {
        // 1. Pull the funds from the Vault to this Strategy
        asset.safeTransferFrom(vault, address(this), amount);
        
        // 2. Return the amount to match the interface
        return amount;
    }

    /**
     * @dev Returns assets back to the Vault when users want to withdraw.
     */
   function withdraw(uint256 amount) external override onlyVault returns (uint256) {
        // 1. Safety check to ensure we don't try to send more than we have
        if (amount > asset.balanceOf(address(this))) {
            revert QuantumStrategy__InsufficientLiquidity();
        }

        // 2. Push the funds back to the Vault
        asset.safeTransfer(vault, amount);

        // 3. Return the amount to match the interface
        return amount;
    }
}