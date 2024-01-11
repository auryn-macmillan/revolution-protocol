// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { Test } from "forge-std/Test.sol";
import { RevolutionToken } from "../../src/RevolutionToken.sol";
import { IRevolutionToken } from "../../src/interfaces/IRevolutionToken.sol";
import { IDescriptorMinimal } from "../../src/interfaces/IDescriptorMinimal.sol";
import { ICultureIndex, ICultureIndexEvents } from "../../src/interfaces/ICultureIndex.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { CultureIndex } from "../../src/culture-index/CultureIndex.sol";
import { MockERC20 } from "../mock/MockERC20.sol";
import { Descriptor } from "../../src/Descriptor.sol";
import "../utils/Base64Decode.sol";
import "../utils/JsmnSolLib.sol";
import { CultureIndexTestSuite } from "./CultureIndex.t.sol";
import { ERC721CheckpointableUpgradeable } from "../../src/base/ERC721CheckpointableUpgradeable.sol";

/// @title RevolutionTokenTest
/// @dev The test suite for the RevolutionToken contract
contract CultureIndexAccessControlTest is CultureIndexTestSuite {
    function testSetQuorumVotesBPSWithinRange(uint104 newQuorumBPS) public {
        vm.assume(newQuorumBPS <= cultureIndex.MAX_QUORUM_VOTES_BPS());

        // Set new quorum BPS by owner
        cultureIndex._setQuorumVotesBPS(newQuorumBPS);
        vm.stopPrank();

        // Check if the quorum BPS is updated correctly
        uint256 currentQuorumBPS = cultureIndex.quorumVotesBPS();
        assertEq(currentQuorumBPS, newQuorumBPS, "Quorum BPS should be updated within valid range");
    }

    function testSetQuorumVotesBPSOutsideRange(uint104 newQuorumBPS) public {
        uint256 currentQuorumBPS = cultureIndex.quorumVotesBPS();
        vm.assume(newQuorumBPS > cultureIndex.MAX_QUORUM_VOTES_BPS());

        // Set new quorum BPS by owner
        vm.expectRevert(abi.encodeWithSignature("INVALID_QUORUM_BPS()"));
        cultureIndex._setQuorumVotesBPS(newQuorumBPS);
        vm.stopPrank();

        // Check if the quorum BPS is updated correctly
        assertEq(cultureIndex.quorumVotesBPS(), currentQuorumBPS, "Quorum BPS should be updated within valid range");
    }

    function testRevertNonOwnerSetQuorumVotesBPS() public {
        vm.stopPrank();
        address nonOwner = address(0x123); // An arbitrary non-owner address
        uint256 newQuorumBPS = 3000; // A valid quorum BPS value

        // Attempt to set new quorum BPS by non-owner and expect revert
        vm.startPrank(nonOwner);
        vm.expectRevert();
        cultureIndex._setQuorumVotesBPS(newQuorumBPS);
        vm.stopPrank();
    }

    function testDropTopVotedPieceOnlyIfQuorumIsMet(uint256 quorumBps) public {
        vm.assume(quorumBps > 200 && quorumBps <= cultureIndex.MAX_QUORUM_VOTES_BPS());

        // Set quorum BPS
        cultureIndex._setQuorumVotesBPS(quorumBps);
        vm.stopPrank();

        vm.startPrank(address(revolutionPointsEmitter));
        revolutionPoints.mint(address(0x21), quorumBps * 10);
        revolutionPoints.mint(address(this), ((quorumBps / 2) * (quorumBps)) / 10_000);

        vm.roll(vm.getBlockNumber() + 2);

        // Create an art piece
        uint256 pieceId = createDefaultArtPiece();

        vm.roll(vm.getBlockNumber() + 2);

        // Vote for the piece, but do not meet the quorum
        vm.startPrank(address(this));
        cultureIndex.vote(pieceId);

        emit log_address(address(cultureIndex.dropperAdmin()));

        // Attempt to drop the top-voted piece and expect it to fail
        vm.expectRevert(abi.encodeWithSignature("DOES_NOT_MEET_QUORUM()"));
        vm.startPrank(address(revolutionToken));
        cultureIndex.dropTopVotedPiece();

        // Additional votes to meet/exceed the quorum
        vm.startPrank(address(0x21));
        cultureIndex.vote(pieceId);
        vm.stopPrank();

        // Attempt to drop the top-voted piece, should succeed
        vm.startPrank(address(revolutionToken));
        ICultureIndex.ArtPieceCondensed memory droppedPiece = cultureIndex.dropTopVotedPiece();
        assertTrue(cultureIndex.getPieceById(droppedPiece.pieceId).isDropped, "Top voted piece should be dropped");
    }
}
