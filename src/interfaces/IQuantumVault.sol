// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface IQuantumVault is IERC4626 {
    //==============================
    //          Errors
    //==============================
    error QuantumVault__EmergencyPauseActive();
    error QuantumVault__InvalidStrategy();
    error QuantumVault__Unauthorized();
    error QuantumVault__FeeExceedsMaximum();

    //==============================
    //          Events
    //==============================
    event StrategyUpdated(address indexed oldStrategy, address indexed newStrategy);
    event FeesUpdated(uint256 entryFeesBPS, uint256 exitFeesBPS);
    event EmergencyPauseToggled(bool status);

    //==============================
    //          View Functions
    //==============================
    function strategy() external view returns (address);
    function feeTreasury() external view returns (address);
    function entryFeeBasisPoints() external view returns (uint256);
    function exitFeeBasisPoints() external view returns (uint256);
    function emergencyPause() external view returns (bool);

    //==============================
    //          Admin Functions
    //==============================
    function togglePause() external;
    function updateStrategy(address newStrategy) external;
    function updateFees(uint256 newEntryFee, uint256 newExitFee) external;
}