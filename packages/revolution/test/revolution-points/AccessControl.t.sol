// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { Test } from "forge-std/Test.sol";
import { RevolutionPoints } from "../../src/RevolutionPoints.sol";
import { RevolutionBuilderTest } from "../RevolutionBuilder.t.sol";
import { IRevolutionBuilder } from "../../src/interfaces/IRevolutionBuilder.sol";
import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

contract PointsTestSuite is RevolutionBuilderTest {
    function setUp() public override {
        super.setUp();
        super.setMockParams();

        super.setPointsParams("Revolution Governance", "GOV");

        super.setCultureIndexParams("Vrbs", "Our community Vrbs. Must be 32x32.", 10, 200, 0);

        super.deployMock();
    }

    function test__basicAccessControl() public {
        address nonMinter = address(0x9);
        uint256 mintAmount = 500 * 1e18;

        // Attempt to mint tokens by a non-minter
        vm.startPrank(nonMinter);
        vm.expectRevert();
        revolutionPoints.mint(address(1), mintAmount);
        vm.stopPrank();

        // Minting by the minter
        vm.startPrank(address(revolutionPointsEmitter));
        revolutionPoints.mint(address(1), mintAmount);
        vm.stopPrank();

        //Minting by the owner should fail
        vm.startPrank(address(executor));
        vm.expectRevert();
        revolutionPoints.mint(address(1), mintAmount);
        vm.stopPrank();

        // Verify that the minting was successful
        assertEq(revolutionPoints.balanceOf(address(1)), mintAmount, "Owner should be able to mint");
    }

    function test__MinterAccessControl() public {
        // make sure the owner can't mint, only the minter
        // then create a new minter and make sure they can mint
        // and the old minter can't mint

        uint256 mintAmount = 500 * 1e18;
        address oldMinter = address(revolutionPointsEmitter);

        //Minting by the owner should fail
        vm.prank(address(executor));
        vm.expectRevert();
        revolutionPoints.mint(address(1), mintAmount);

        address newMinter = address(0x2);
        vm.prank(address(executor));
        revolutionPoints.setMinter(newMinter);

        //assert minter is set
        assertEq(revolutionPoints.minter(), newMinter, "Minter should be set");

        //Minting by the owner should fail
        vm.prank(address(executor));
        vm.expectRevert();
        revolutionPoints.mint(address(1), mintAmount);

        // assert no tokens minted
        assertEq(revolutionPoints.balanceOf(address(1)), 0, "Owner should not be able to mint");

        // minting by new minter should work
        vm.prank(newMinter);
        revolutionPoints.mint(address(1), mintAmount);

        // assert balance
        assertEq(revolutionPoints.balanceOf(address(1)), mintAmount, "Owner should be able to mint");

        // make sure old minter can't mint
        vm.prank(oldMinter);
        vm.expectRevert();
        revolutionPoints.mint(address(1), mintAmount);
    }

    function test__MinterLocking() public {
        // make sure the current minter can mint
        // then lock the minter
        // make sure they can still mint
        // try to set a new minter, assert that it fails and the old minter is still there
        // and can still mint

        uint256 mintAmount = 500 * 1e18;
        address oldMinter = address(revolutionPointsEmitter);

        // Current minter should work
        vm.prank(address(revolutionPointsEmitter));
        revolutionPoints.mint(address(1), mintAmount);

        // assert balance
        assertEq(revolutionPoints.balanceOf(address(1)), mintAmount, "Owner should be able to mint");

        // lock minter
        vm.prank(address(executor));
        revolutionPoints.lockMinter();

        // assert minter is locked
        assertEq(revolutionPoints.isMinterLocked(), true, "Minter should be locked");

        // assert minter is still set
        assertEq(revolutionPoints.minter(), oldMinter, "Minter should be set");

        // assert minter can still mint
        vm.prank(oldMinter);
        revolutionPoints.mint(address(1), mintAmount);

        // assert balance
        assertEq(revolutionPoints.balanceOf(address(1)), mintAmount * 2, "Owner should be able to mint");

        // try to set new minter
        address newMinter = address(0x2);
        vm.prank(address(executor));
        vm.expectRevert();
        revolutionPoints.setMinter(newMinter);

        // assert minter is still set
        assertEq(revolutionPoints.minter(), oldMinter, "Minter should be set");

        // assert minter can still mint
        vm.prank(oldMinter);
        revolutionPoints.mint(address(1), mintAmount);

        // assert balance
        assertEq(revolutionPoints.balanceOf(address(1)), mintAmount * 3, "Owner should be able to mint");
    }
}
