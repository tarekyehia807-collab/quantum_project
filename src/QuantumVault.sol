// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IQuantumVault} from "./interfaces/IQuantumVault.sol";
import {IStrategy} from "./interfaces/IStrategy.sol";
import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/**
 * @title QuantumVault
 * @dev Professional implementation of an ERC4626 Vault with integrated strategy management.
 */
contract QuantumVault is
    Initializable,
    ERC4626Upgradeable,
    OwnableUpgradeable,
    ReentrancyGuard,
    UUPSUpgradeable,
    IQuantumVault
{
    using SafeERC20 for IERC20;

    // =========================================
    //            State Variables
    // =========================================
    address public override strategy;
    address public override feeTreasury;
    uint256 public override entryFeeBasisPoints;
    uint256 public override exitFeeBasisPoints;
    uint256 public constant MAX_BPS = 10000;
    bool public override emergencyPause;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // =========================================
    //               Initializer
    // =========================================
    function initialize(
        IERC20 _asset,
        string memory _name,
        string memory _symbol,
        address _strategy,
        address _feeTreasury,
        uint256 _entryFeeBPS,
        uint256 _exitFeeBPS,
        address _owner
    ) public initializer {
        __ERC4626_init(_asset);
        __ERC20_init(_name, _symbol);
        __Ownable_init(_owner);
        // Note: No UUPS or ReentrancyGuard init needed in OpenZeppelin v5
        strategy = _strategy;
        feeTreasury = _feeTreasury;
        entryFeeBasisPoints = _entryFeeBPS;
        exitFeeBasisPoints = _exitFeeBPS;
    }

    // =========================================
    // 1. Asset Accounting
    // =========================================
    function totalAssets() public view override(ERC4626Upgradeable, IERC4626) returns (uint256) {
        uint256 idleAssets = IERC20(asset()).balanceOf(address(this));
        uint256 deployedAssets = strategy != address(0) ? IStrategy(strategy).totalAssets() : 0;
        return idleAssets + deployedAssets;
    }

    // =========================================
    // 2. Emergency Controls
    // =========================================
    function maxDeposit(address) public view override(ERC4626Upgradeable, IERC4626) returns (uint256) {
        if (emergencyPause) return 0;
        return type(uint256).max;
    }

    function maxWithdraw(address owner) public view override(ERC4626Upgradeable, IERC4626) returns (uint256) {
        if (emergencyPause) return 0;
        return super.maxWithdraw(owner);
    }

    // =========================================
    // 3. Fee Engine (Mathematically Consistent)
    // =========================================
    function _feeOnTotal(uint256 assets, uint256 feeBps) internal pure returns (uint256) {
        return (assets * feeBps) / MAX_BPS;
    }

    function previewDeposit(uint256 assets) public view override(ERC4626Upgradeable, IERC4626) returns (uint256) {
        uint256 fee = _feeOnTotal(assets, entryFeeBasisPoints);
        return super.previewDeposit(assets - fee);
    }

    // Calculation for: How many shares (Gross) are needed to get X assets (Net)?
    function previewWithdraw(uint256 assets) public view override(ERC4626Upgradeable, IERC4626) returns (uint256) {
        uint256 gross = (assets * MAX_BPS) / (MAX_BPS - exitFeeBasisPoints);
        return super.previewWithdraw(gross);
    }

    // Calculation for: How many assets (Net) will I get for X shares (Gross)?
    function previewRedeem(uint256 shares) public view override(ERC4626Upgradeable, IERC4626) returns (uint256) {
        uint256 grossAssets = super.previewRedeem(shares);
        uint256 fee = _feeOnTotal(grossAssets, exitFeeBasisPoints);
        return grossAssets - fee;
    }

    // =========================================
    // 4. Core Logic (Using Shares for Gross Math)
    // =========================================
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override nonReentrant {
        if (emergencyPause) revert QuantumVault__EmergencyPauseActive();

        uint256 fee = _feeOnTotal(assets, entryFeeBasisPoints);
        uint256 netAssets = assets - fee;

        super._deposit(caller, receiver, netAssets, shares);

        if (fee > 0) {
            IERC20(asset()).safeTransferFrom(caller, feeTreasury, fee);
        }

        if (strategy != address(0) && netAssets > 0) {
            IERC20(asset()).safeIncreaseAllowance(strategy, netAssets);
            IStrategy(strategy).deposit(netAssets);
        }
    }

    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        override
        nonReentrant
    {
        if (emergencyPause) revert QuantumVault__EmergencyPauseActive();

        // The 'shares' represent the Gross amount.
        // We convert shares back to assets to know exactly how much to pull from strategy.
        uint256 totalToPull = convertToAssets(shares);
        uint256 fee = totalToPull - assets; // The difference is the fee

        uint256 idle = IERC20(asset()).balanceOf(address(this));

        if (idle < totalToPull && strategy != address(0)) {
            IStrategy(strategy).withdraw(totalToPull - idle);
        }

        super._withdraw(caller, receiver, owner, assets, shares);

        if (fee > 0) {
            IERC20(asset()).safeTransfer(feeTreasury, fee);
        }
    }

    // =========================================
    // 5. Admin Functions
    // =========================================
    function togglePause() external override onlyOwner {
        emergencyPause = !emergencyPause;
        emit EmergencyPauseToggled(emergencyPause);
    }

    function updateStrategy(address newStrategy) external override onlyOwner {
        if (newStrategy == address(0)) revert QuantumVault__InvalidStrategy();
        emit StrategyUpdated(strategy, newStrategy);
        strategy = newStrategy;
    }

    function updateFees(uint256 newEntryFee, uint256 newExitFee) external override onlyOwner {
        if (newEntryFee > 1000 || newExitFee > 1000) revert QuantumVault__FeeExceedsMaximum();
        entryFeeBasisPoints = newEntryFee;
        exitFeeBasisPoints = newExitFee;
        emit FeesUpdated(newEntryFee, newExitFee);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
