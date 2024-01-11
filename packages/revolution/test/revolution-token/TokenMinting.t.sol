// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { Test } from "forge-std/Test.sol";
import { RevolutionToken } from "../../src/RevolutionToken.sol";
import { IRevolutionToken } from "../../src/interfaces/IRevolutionToken.sol";
import { IDescriptorMinimal } from "../../src/interfaces/IDescriptorMinimal.sol";
import { ICultureIndex } from "../../src/interfaces/ICultureIndex.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { CultureIndex } from "../../src/culture-index/CultureIndex.sol";
import { MockERC20 } from "../mock/MockERC20.sol";
import { Descriptor } from "../../src/Descriptor.sol";
import { RevolutionPoints } from "../../src/RevolutionPoints.sol";
import "../utils/Base64Decode.sol";
import "../utils/JsmnSolLib.sol";
import { RevolutionTokenTestSuite } from "./RevolutionToken.t.sol";

/// @title RevolutionTokenTest
/// @dev The test suite for the RevolutionToken contract
contract TokenMintingTest is RevolutionTokenTestSuite {
    /// @dev Ensures the dropped art piece is equivalent to the top-voted piece
    function test_DroppedArtPieceMatchesTopVoted() public {
        vm.stopPrank();

        vm.startPrank(address(revolutionPointsEmitter));
        revolutionPoints.mint(address(this), 10);

        // ensure vote snapshot is taken
        vm.roll(vm.getBlockNumber() + 1);

        // Create a new art piece and simulate it being the top voted piece
        uint256 pieceId = createDefaultArtPiece();
        vm.roll(vm.getBlockNumber() + 2);

        vm.startPrank(address(this));
        cultureIndex.vote(pieceId); // Simulate voting for the piece to make it top-voted

        // Fetch the top voted piece before minting
        ICultureIndex.ArtPiece memory topVotedPieceBeforeMint = cultureIndex.getTopVotedPiece();

        // Mint a token
        vm.startPrank(address(auction));
        uint256 tokenId = revolutionToken.mint();

        // Fetch the dropped art piece associated with the minted token
        ICultureIndex.ArtPiece memory droppedArtPiece = revolutionToken.getArtPieceById(tokenId);

        // Now compare the relevant fields of topVotedPieceBeforeMint and droppedArtPiece
        assertEq(droppedArtPiece.pieceId, topVotedPieceBeforeMint.pieceId, "Piece ID should match");
        assertEq(droppedArtPiece.sponsor, topVotedPieceBeforeMint.sponsor, "Sponsor address should match");
        //ensure isDropped is now true
        assertTrue(droppedArtPiece.isDropped, "isDropped should be true");
        assertTrue(
            areArraysEqual(droppedArtPiece.creators, topVotedPieceBeforeMint.creators),
            "Creators array should match"
        );
        assertTrue(
            areArtPieceMetadataEqual(droppedArtPiece.metadata, topVotedPieceBeforeMint.metadata),
            "Metadata should match"
        );
    }

    // Helper function to compare ArtPieceMetadata structs
    function areArtPieceMetadataEqual(
        ICultureIndex.ArtPieceMetadata memory metadata1,
        ICultureIndex.ArtPieceMetadata memory metadata2
    ) internal pure returns (bool) {
        return (keccak256(bytes(metadata1.name)) == keccak256(bytes(metadata2.name)) &&
            keccak256(bytes(metadata1.description)) == keccak256(bytes(metadata2.description)) &&
            metadata1.mediaType == metadata2.mediaType &&
            keccak256(bytes(metadata1.image)) == keccak256(bytes(metadata2.image)) &&
            keccak256(bytes(metadata1.text)) == keccak256(bytes(metadata2.text)) &&
            keccak256(bytes(metadata1.animationUrl)) == keccak256(bytes(metadata2.animationUrl)));
    }

    // Helper function to compare arrays of creators
    function areArraysEqual(
        ICultureIndex.CreatorBps[] memory arr1,
        ICultureIndex.CreatorBps[] memory arr2
    ) internal pure returns (bool) {
        if (arr1.length != arr2.length) {
            return false;
        }
        for (uint i = 0; i < arr1.length; i++) {
            if (arr1[i].creator != arr2[i].creator || arr1[i].bps != arr2[i].bps) {
                return false;
            }
        }
        return true;
    }

    /// @dev Tests the minting with no pieces added
    function testMintWithNoPieces() public {
        vm.stopPrank();
        vm.startPrank(address(auction));

        // Try to remove max and expect to fail
        vm.expectRevert("dropTopVotedPiece failed");
        revolutionToken.mint();
    }

    /// @dev Tests basic minting
    function testMint() public {
        vm.stopPrank();
        vm.startPrank(address(auction));
        // Add a piece to the CultureIndex
        createDefaultArtPiece();
        vm.roll(vm.getBlockNumber() + 1);

        // Mint a token
        uint256 tokenId = revolutionToken.mint();

        // Validate the token
        uint256 totalSupply = revolutionToken.totalSupply();
        assertEq(revolutionToken.ownerOf(tokenId), address(auction), "The contract should own the newly minted token");
        assertEq(tokenId, 0, "First token ID should be 1");
        assertEq(totalSupply, 1, "Total supply should be 1");
    }

    /// @dev Tests minting a verb token to itself
    function testMintToItself() public {
        createDefaultArtPiece();

        uint256 initialTotalSupply = revolutionToken.totalSupply();
        vm.stopPrank();
        vm.startPrank(address(auction));
        vm.roll(vm.getBlockNumber() + 1);

        uint256 newTokenId = revolutionToken.mint();
        assertEq(revolutionToken.totalSupply(), initialTotalSupply + 1, "One new token should have been minted");
        assertEq(
            revolutionToken.ownerOf(newTokenId),
            address(auction),
            "The contract should own the newly minted token"
        );
    }

    /// @dev Tests burning a verb token
    function testBurn() public {
        createDefaultArtPiece();
        vm.roll(vm.getBlockNumber() + 1);

        vm.stopPrank();
        vm.startPrank(address(auction));

        uint256 tokenId = revolutionToken.mint();
        uint256 initialTotalSupply = revolutionToken.totalSupply();
        revolutionToken.burn(tokenId);
        uint256 newTotalSupply = revolutionToken.totalSupply();
        assertEq(newTotalSupply, initialTotalSupply - 1, "Total supply should decrease by 1 after burning");
    }

    /// @dev Ensures _currentVerbId increments correctly after each mint
    function test_MintingIncrement(uint200 voteWeight) public {
        vm.assume(voteWeight < type(uint200).max / 2);
        vm.stopPrank();
        vm.startPrank(address(revolutionPointsEmitter));
        revolutionPoints.mint(address(1), 10000);

        revolutionPoints.mint(address(this), voteWeight);

        // ensure vote snapshot is taken
        vm.roll(vm.getBlockNumber() + 1);

        uint256 pieceId1 = createDefaultArtPiece();
        uint256 pieceId2 = createDefaultArtPiece();
        vm.roll(vm.getBlockNumber() + 2);

        vm.startPrank(address(this));
        if (voteWeight == 0) vm.expectRevert(abi.encodeWithSignature("WEIGHT_TOO_LOW()"));
        cultureIndex.vote(pieceId1);

        uint256 expectedQuorum = ((10_000 + voteWeight) * cultureIndex.quorumVotesBPS()) / 10_000;

        bool shouldRevertMint = voteWeight < expectedQuorum;

        vm.startPrank(address(auction));
        if (shouldRevertMint) vm.expectRevert("dropTopVotedPiece failed");
        uint256 tokenId1 = revolutionToken.mint();
        if (!shouldRevertMint)
            assertEq(revolutionToken.totalSupply(), tokenId1 + 1, "CurrentVerbId should increment after first mint");

        vm.startPrank(address(this));
        if (voteWeight == 0) vm.expectRevert(abi.encodeWithSignature("WEIGHT_TOO_LOW()"));
        cultureIndex.vote(pieceId2);

        vm.startPrank(address(auction));
        if (shouldRevertMint) vm.expectRevert("dropTopVotedPiece failed");
        uint256 tokenId2 = revolutionToken.mint();
        if (!shouldRevertMint)
            assertEq(revolutionToken.totalSupply(), tokenId2 + 1, "CurrentVerbId should increment after second mint");
    }

    /// @dev Checks if the VerbCreated event is emitted with correct parameters on minting
    function testMintingEvent() public {
        createDefaultArtPiece();
        vm.roll(vm.getBlockNumber() + 1);

        (uint256 pieceId, ICultureIndex.ArtPieceMetadata memory metadata, , , ) = cultureIndex.pieces(0);

        emit log_uint(pieceId);

        ICultureIndex.CreatorBps[] memory creators = new ICultureIndex.CreatorBps[](1);
        creators[0] = ICultureIndex.CreatorBps({ creator: address(0x1), bps: 10000 });

        ICultureIndex.ArtPieceCondensed memory expectedArtPiece = ICultureIndex.ArtPieceCondensed({
            pieceId: 0,
            creators: creators,
            sponsor: address(executor)
        });

        vm.stopPrank();
        vm.startPrank(address(auction));

        vm.expectEmit(true, true, true, true);

        emit IRevolutionToken.VerbCreated(0, expectedArtPiece);

        revolutionToken.mint();
    }

    /// @dev Tests the burn function.
    function testBurnFunction() public {
        vm.stopPrank();
        vm.startPrank(address(auction));
        //create piece
        createDefaultArtPiece();
        vm.roll(vm.getBlockNumber() + 1);

        uint256 tokenId = revolutionToken.mint();

        vm.expectEmit(true, true, true, true);
        emit IRevolutionToken.VerbBurned(tokenId);

        revolutionToken.burn(tokenId);
        assertEq(revolutionToken.totalSupply(), 0, "Total supply should be 0 after burning");
        assertEq(revolutionToken.balanceOf(address(auction)), 0, "Auction should not own any tokens after burning");
    }

    /// @dev Validates that the token URI is correctly set and retrieved
    function testTokenURI() public {
        vm.stopPrank();
        vm.startPrank(address(auction));
        uint256 artPieceId = createDefaultArtPiece();
        vm.roll(vm.getBlockNumber() + 1);

        uint256 tokenId = revolutionToken.mint();
        (, ICultureIndex.ArtPieceMetadata memory metadata, , , ) = cultureIndex.pieces(artPieceId);
        // Assuming the descriptor returns a fixed URI for the given tokenId
        string memory expectedTokenURI = descriptor.tokenURI(tokenId, metadata);
        assertEq(
            revolutionToken.tokenURI(tokenId),
            expectedTokenURI,
            "Token URI should be correctly set and retrieved"
        );
    }

    /// @dev Ensures minting fetches and associates the top-voted piece from CultureIndex
    function test_TopVotedPieceMinting() public {
        vm.stopPrank();
        vm.startPrank(address(revolutionPointsEmitter));
        revolutionPoints.mint(address(this), 10);

        // ensure vote snapshot is taken
        vm.roll(vm.getBlockNumber() + 1);

        // Create a new piece and simulate it being the top voted piece
        uint256 pieceId = createDefaultArtPiece(); // This function should exist within the test contract

        vm.startPrank(address(this));
        cultureIndex.vote(pieceId); // Assuming vote function exists and we cast 10 votes

        // Mint a token
        vm.startPrank(address(auction));
        // fast forward to the next block
        vm.roll(vm.getBlockNumber() + 2);
        uint256 tokenId = revolutionToken.mint();

        // Validate the token is associated with the top voted piece
        uint256 mintedPieceId = revolutionToken.artPieces(tokenId);
        assertEq(mintedPieceId, pieceId, "Minted token should be associated with the top voted piece");
    }
}
