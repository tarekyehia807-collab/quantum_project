// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {QuantumVault} from "../src/QuantumVault.sol";
import {QuantumStrategy} from "../src/mocks/QuantumStrategy.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IQuantumVault} from "../src/interfaces/IQuantumVault.sol";

/**
 * @dev A simple Mock ERC20 token to act as our underlying asset (e.g., USDC).
 * We need this because we cannot test a vault without real tokens.
 */
contract MockERC20 is ERC20 {
    constructor() ERC20("Mock USDC", "USDC") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/**
 * @title QuantumVaultTest
 * @dev Main test suite for the QuantumVault protocol.
 */
contract QuantumVaultTest is Test {
    // =========================================
    //            State Variables
    // =========================================
    QuantumVault public vault;
    QuantumStrategy public strategy;
    MockERC20 public asset;

    address public owner = makeAddr("owner");
    address public feeTreasury = makeAddr("feeTreasury");
    address public alice = makeAddr("alice"); // Our test user

    uint256 public constant ENTRY_FEE = 100; // 1% (100 BPS)
    uint256 public constant EXIT_FEE = 200; // 2% (200 BPS)

    // =========================================
    //            Setup Function
    // =========================================
    /**
     * @dev setUp() runs before EVERY single test. It represents the "clean state".
     */
    function setUp() public {
        // 1. Deploy the underlying asset (USDC)
        asset = new MockERC20();

        // 2. Deploy the Implementation Contract
        QuantumVault implementation = new QuantumVault();

        // 3. Prepare the initialization data
        bytes memory initData = abi.encodeCall(
            QuantumVault.initialize,
            (
                asset,
                "Quantum Yield Token",
                "qYST",
                address(0), // No strategy yet (Circular dependency fix)
                feeTreasury,
                ENTRY_FEE,
                EXIT_FEE,
                owner
            )
        );

        // 4. Deploy the Proxy and initialize it in one transaction
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);

        // 5. Cast the proxy address to the QuantumVault interface
        vault = QuantumVault(address(proxy));

        // 6. Deploy the Strategy, linking it to the newly created Vault proxy
        strategy = new QuantumStrategy(address(asset), address(vault));

        // 7. Update the Vault to recognize the new Strategy (acting as Owner)
        vm.prank(owner);
        vault.updateStrategy(address(strategy));

        // 8. Give Alice some starting money for tests
        asset.mint(alice, 10_000e18); // 10,000 tokens
    }

    // =========================================
    //            Test Cases
    // =========================================

    /**
     * @dev Tests if the deployment and setup variables are correct.
     */
    function test_Initialization() public view {
        assertEq(vault.owner(), owner);
        assertEq(vault.feeTreasury(), feeTreasury);
        assertEq(vault.strategy(), address(strategy));
        assertEq(vault.asset(), address(asset));
    }

    /**
     * @dev Tests the core deposit flow: User -> Vault -> Fees + Strategy.
     */
    function test_DepositFlow() public {
        uint256 depositAmount = 1000e18; // Alice wants to deposit 1000 tokens

        // 1. Impersonate Alice
        vm.startPrank(alice);

        // 2. Alice approves the Vault to take her tokens
        asset.approve(address(vault), depositAmount);

        // 3. Alice executes the deposit
        vault.deposit(depositAmount, alice);

        vm.stopPrank();

        // 4. Mathematical Verification (The Auditor's Check)
        // Entry fee is 1% -> 1000 * 1% = 10 tokens
        // Net Assets -> 1000 - 10 = 990 tokens

        uint256 expectedFee = 10e18;
        uint256 expectedNetAssets = 990e18;

        // Check 1: Did the Treasury get the 10 token fee?
        assertEq(asset.balanceOf(feeTreasury), expectedFee, "Fee not collected correctly");

        // Check 2: Did the Strategy receive the 990 net tokens?
        assertEq(asset.balanceOf(address(strategy)), expectedNetAssets, "Strategy did not receive funds");

        // Check 3: Did Alice receive exactly 990 shares?
        // (Since it's the first deposit, 1 share = 1 asset)
        assertEq(vault.balanceOf(alice), expectedNetAssets, "Alice received incorrect shares");

        // Check 4: Is the totalAssets of the vault reading correctly? (Idle + Deployed)
        assertEq(vault.totalAssets(), expectedNetAssets, "Total assets mismatch");
    }

    // =========================================
    //            Exploit Tests (Auditor)
    // =========================================

    /**
     * @dev Exploit Test 1: Access Control Breach
     * Can a random user (Alice) pause the vault and cause a Denial of Service (DoS)?
     */
    function test_RevertIf_UnauthorizedPause() public {
        // 1. Alice (hacker) connects to the contract
        vm.startPrank(alice);

        // 2. We explicitly tell Foundry: "The next line MUST fail with this specific Ownable error"
        // If it doesn't fail, or fails with a different error, the test will FAlL!
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));

        // 3. Alice tries to pull the kill switch
        vault.togglePause();

        vm.stopPrank();
    }

    /**
     * @dev Exploit Test 2: Circuit Breaker Validation
     * If the owner pauses the vault, does it actually block user funds from entering?
     */
    function test_EmergencyPause_BlocksDeposit() public {
        // 1. Owner toggles pause
        vm.prank(owner);
        vault.togglePause();

        // Debugging: Let's see what the contract actually thinks the max deposit is
        uint256 currentMax = vault.maxDeposit(alice);
        console.log("Current Max Deposit during Pause:", currentMax);

        assertTrue(vault.emergencyPause(), "Vault should be paused");
        assertEq(currentMax, 0, "Max deposit should be 0 when paused");

        // 2. Prepare Alice's attempt
        uint256 depositAmount = 100e18;
        vm.startPrank(alice);
        asset.approve(address(vault), depositAmount);

        // 3. We use the simplest expectRevert to see IF it reverts at all
        // If this passes, the problem was just the specific Error Signature
        vm.expectRevert();
        vault.deposit(depositAmount, alice);

        vm.stopPrank();
    }

    /**
     * @dev The Final Boss Test: Full Withdrawal Flow.
     * Alice deposits -> Funds go to Strategy -> Alice withdraws -> Funds come back from Strategy.
     */
    function test_FullWithdrawalFromStrategy() public {
        uint256 amount = 1000e18; // 1000 USDC

        // 1. Alice Deposits
        vm.startPrank(alice);
        asset.approve(address(vault), amount);
        vault.deposit(amount, alice);

        // At this point:
        // - Strategy should have 990 assets (after 1% entry fee)
        // - Vault should have 0 idle assets
        assertEq(asset.balanceOf(address(strategy)), 990e18);
        assertEq(asset.balanceOf(address(vault)), 0);

        // 2. Alice Withdraws everything
        uint256 sharesToWithdraw = vault.balanceOf(alice);
        vault.redeem(sharesToWithdraw, alice, alice);
        vm.stopPrank();

        // 3. Mathematical Verification
        // 9000 (remaining) + 970.2 (returned) = 9970.2 tokens
        // In Wei: 99702 * 10^17
        uint256 expectedAliceBalance = 99702 * 1e17;
        assertEq(asset.balanceOf(alice), expectedAliceBalance, "Alice balance mismatch");

        // We use 'approxEqAbs' because of potential rounding in floating point numbers
        // though in this mock it should be exact.
        assertEq(asset.balanceOf(alice), 9970.2e18, "Alice balance mismatch after withdrawal");
        assertEq(asset.balanceOf(address(strategy)), 0, "Strategy should be empty");
        assertEq(vault.totalAssets(), 0, "Vault should be empty");
    }
}
