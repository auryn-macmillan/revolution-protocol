// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { Test } from "forge-std/Test.sol";
import { RevolutionPoints } from "../../src/RevolutionPoints.sol";
import { RevolutionBuilderTest } from "../RevolutionBuilder.t.sol";
import { IRevolutionBuilder } from "../../src/interfaces/IRevolutionBuilder.sol";
import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

contract PointsTestSuite is RevolutionBuilderTest {
    event Log(string, uint);

    function setUp() public override {
        super.setUp();
        super.setMockParams();

        super.setPointsParams("Revolution Governance", "GOV");

        super.setCultureIndexParams("Vrbs", "Our community Vrbs. Must be 32x32.", 10, 200, 0);

        super.deployMock();
    }

    function testTransferRestrictions() public {
        // Setup: Mint some tokens to an account
        address account1 = address(0x1);
        uint256 mintAmount = 1000 * 1e18;
        vm.startPrank(address(revolutionPointsEmitter));
        revolutionPoints.mint(account1, mintAmount);
        assertEq(revolutionPoints.balanceOf(account1), mintAmount, "Minting failed");

        // Attempt to transfer tokens from account1 to account2
        address account2 = address(0x2);
        uint256 transferAmount = 500 * 1e18;
        vm.startPrank(account1);
        vm.expectRevert(abi.encodeWithSignature("TRANSFER_NOT_ALLOWED()"));
        revolutionPoints.transfer(account2, transferAmount);
        vm.stopPrank();

        // Verify that the balances remain unchanged
        assertEq(revolutionPoints.balanceOf(account1), mintAmount, "Balance of account1 should not change");
        assertEq(revolutionPoints.balanceOf(account2), 0, "Balance of account2 should remain zero");
    }

    function testApprovalRestrictions() public {
        // Setup: Use two accounts
        address owner = address(revolutionPointsEmitter);
        address spender = address(0x2);

        // Attempt to approve spender by the owner
        uint256 approvalAmount = 500 * 1e18;
        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSignature("TRANSFER_NOT_ALLOWED()"));
        revolutionPoints.approve(spender, approvalAmount);
        vm.stopPrank();

        // Verify that the allowance remains zero
        assertEq(revolutionPoints.allowance(owner, spender), 0, "Allowance should remain zero");
    }

    function testMintingBehavior() public {
        address account = address(0x3);
        uint256 mintAmount = 500 * 1e18;

        // Attempt minting by a non-owner
        address nonOwner = address(0x4);
        vm.startPrank(nonOwner);
        vm.expectRevert();
        revolutionPoints.mint(account, mintAmount);
        vm.stopPrank();

        // Verify that the balance remains unchanged
        assertEq(revolutionPoints.balanceOf(account), 0, "Non-owner should not be able to mint");

        // Minting by the owner
        vm.startPrank(address(revolutionPointsEmitter));
        revolutionPoints.mint(account, mintAmount);
        vm.stopPrank();

        // Verify balance and total supply
        assertEq(revolutionPoints.balanceOf(account), mintAmount, "Minting failed to update balance");
        assertEq(revolutionPoints.totalSupply(), mintAmount, "Total supply not updated correctly");
    }

    function testVotingAndDelegation() public {
        address delegate = address(0x6);
        uint256 mintAmount = 1000 * 1e18;

        // Mint tokens to the owner
        vm.startPrank(address(revolutionPointsEmitter));
        revolutionPoints.mint(address(this), mintAmount);
        vm.stopPrank();

        // Delegate voting power
        revolutionPoints.delegate(delegate);

        // Check the voting power of the delegate
        assertEq(revolutionPoints.getVotes(delegate), mintAmount, "Delegation failed to assign voting power");

        // Ensure that no tokens were transferred in the process of delegation
        assertEq(revolutionPoints.balanceOf(delegate), 0, "Delegation should not transfer tokens");
    }

    function testTokenMetadata() public {
        assertEq(revolutionPoints.name(), "Revolution Governance", "Incorrect token name");
        assertEq(revolutionPoints.symbol(), "GOV", "Incorrect token symbol");
        assertEq(revolutionPoints.decimals(), 18, "Incorrect number of decimals");
    }

    function testSupplyInvariants(uint256 mintAmount1) public {
        vm.assume(mintAmount1 < type(uint208).max);

        uint256 total = mintAmount1 + mintAmount1 / 10;

        vm.assume(total < type(uint208).max);
        address account1 = address(0x7);
        address account2 = address(0x8);

        // Mint tokens to different accounts
        vm.startPrank(address(revolutionPointsEmitter));
        revolutionPoints.mint(account1, mintAmount1);
        revolutionPoints.mint(account2, mintAmount1 / 10);
        vm.stopPrank();

        // Check total supply
        uint256 totalSupply = revolutionPoints.totalSupply();

        emit Log("totalSupply", totalSupply);

        assertEq(totalSupply, mintAmount1 + mintAmount1 / 10, "Total supply should equal sum of balances");

        // Check individual balances
        assertEq(revolutionPoints.balanceOf(account1), mintAmount1, "Incorrect balance for account1");
        assertEq(revolutionPoints.balanceOf(account2), mintAmount1 / 10, "Incorrect balance for account2");
    }

    function testEdgeCases() public {
        // Minting an excessive amount of tokens (overflow check)
        uint256 excessiveAmount = type(uint256).max;
        vm.startPrank(address(revolutionPointsEmitter));
        vm.expectRevert();
        revolutionPoints.mint(address(1), excessiveAmount);
        vm.stopPrank();
    }

    function testOwnershipTransferAndManagerRevert() public {
        // Attempt to initialize contract by a non-manager account
        address minter = address(0x10);
        address nonManager = address(0x10);
        IRevolutionBuilder.PointsTokenParams memory params = IRevolutionBuilder.PointsTokenParams("Test Token", "TST");
        vm.startPrank(nonManager);
        vm.expectRevert(abi.encodeWithSignature("InvalidInitialization()"));
        revolutionPoints.initialize(nonManager, minter, params);
        vm.stopPrank();

        // Transfer ownership and test minting by new owner
        address newOwner = address(0x11);
        vm.startPrank(address(executor));
        Ownable2StepUpgradeable(address(revolutionPoints)).transferOwnership(newOwner);
        vm.stopPrank();

        vm.startPrank(newOwner);

        //accept ownership
        Ownable2StepUpgradeable(address(revolutionPoints)).acceptOwnership();

        //set new owner as minter
        revolutionPoints.setMinter(newOwner);

        revolutionPoints.mint(address(1), 100 * 1e18);
        assertEq(revolutionPoints.balanceOf(address(1)), 100 * 1e18, "New owner should be able to mint");

        //ensure minting to address(0) is not allowed
        vm.expectRevert();
        revolutionPoints.mint(address(0), 100 * 1e18);
        vm.stopPrank();

        //assert newOwner is minter and owner
        assertEq(revolutionPoints.minter(), newOwner, "New owner should be minter");
        assertEq(Ownable2StepUpgradeable(address(revolutionPoints)).owner(), newOwner, "New owner should be owner");
    }
}
