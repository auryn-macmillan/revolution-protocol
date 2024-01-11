// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { Test } from "forge-std/Test.sol";
import { RevolutionToken } from "../../src/RevolutionToken.sol";
import { ICultureIndex, ICultureIndexEvents } from "../../src/interfaces/ICultureIndex.sol";
import { IRevolutionToken } from "../../src/interfaces/IRevolutionToken.sol";
import { IDescriptorMinimal } from "../../src/interfaces/IDescriptorMinimal.sol";
import { ICultureIndex } from "../../src/interfaces/ICultureIndex.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { CultureIndex } from "../../src/culture-index/CultureIndex.sol";
import { MockERC20 } from "../mock/MockERC20.sol";
import { Descriptor } from "../../src/Descriptor.sol";
import "../utils/Base64Decode.sol";
import "../utils/JsmnSolLib.sol";
import { RevolutionTokenTestSuite } from "./RevolutionToken.t.sol";

/// @title RevolutionTokenTest
/// @dev The test suite for the RevolutionToken contract
contract TokenSecurityTest is RevolutionTokenTestSuite {
    //from https://github.com/code-423n4/2023-12-revolutionprotocol-findings/issues/49
    function testBlockingOfTransferAndRedelegating() public {
        address user = address(0x1234);
        address attacker = address(0x4321);

        vm.stopPrank();

        // create 3 random pieces
        createDefaultArtPiece();
        createDefaultArtPiece();
        createDefaultArtPiece();

        vm.roll(vm.getBlockNumber() + 1);

        // transfer 2 pieces to normal user and 1 to the attacker
        vm.startPrank(address(auction));
        revolutionToken.mint();
        revolutionToken.transferFrom(address(auction), user, 0);

        revolutionToken.mint();
        revolutionToken.transferFrom(address(auction), user, 1);

        revolutionToken.mint();
        revolutionToken.transferFrom(address(auction), attacker, 2);

        vm.stopPrank();

        // user delegates his votes to attacker
        vm.prank(user);
        revolutionToken.delegate(attacker);

        // attacker delegates to address(0) multiple times, blocking user from redelegating
        vm.prank(attacker);
        vm.expectRevert();
        revolutionToken.delegate(address(0));

        vm.prank(attacker);
        vm.expectRevert();
        revolutionToken.delegate(address(0));

        // now, user cannot redelegate
        vm.prank(user);
        revolutionToken.delegate(user);

        // attacker transfer his only NFT to an address controlled by himself
        // he doesn't lose anything, but he still trapped victim's votes and NFTs
        vm.prank(attacker);
        revolutionToken.transferFrom(attacker, address(0x43214321), 2);

        // user cannot transfer any of his NTFs either
        vm.prank(user);
        revolutionToken.transferFrom(user, address(0x1234567890), 0);
    }
}
