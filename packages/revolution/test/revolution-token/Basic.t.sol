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
import { RevolutionTokenTestSuite } from "./RevolutionToken.t.sol";

/// @title RevolutionTokenTest
/// @dev The test suite for the RevolutionToken contract
contract TokenBasicTest is RevolutionTokenTestSuite {
    /// @dev Tests token metadata integrity after minting
    function testTokenMetadataIntegrity() public {
        // Create an art piece and mint a token
        uint256 artPieceId = createDefaultArtPiece();
        vm.roll(vm.getBlockNumber() + 1);

        vm.stopPrank();
        vm.startPrank(address(auction));
        uint256 tokenId = revolutionToken.mint();

        // Retrieve the token metadata URI
        string memory tokenURI = revolutionToken.tokenURI(tokenId);

        emit log_string(tokenURI);

        // Extract the base64 encoded part of the tokenURI
        string memory base64Metadata = substring(tokenURI, 29, bytes(tokenURI).length);
        emit log_string(base64Metadata);

        // Decode the base64 encoded metadata
        string memory metadataJson = decodeMetadata(base64Metadata);
        emit log_string(metadataJson);

        // Parse the JSON to get metadata fields
        (string memory name, string memory description, string memory image) = parseJson(metadataJson);

        // Retrieve the expected metadata directly from the art piece for comparison
        (, ICultureIndex.ArtPieceMetadata memory metadata, , , ) = cultureIndex.pieces(artPieceId);

        //assert name equals Verb + tokenId
        string memory expectedName = string(abi.encodePacked(tokenNamePrefix, " ", Strings.toString(tokenId)));

        // Assert that the token metadata matches the expected metadata from the art piece
        assertEq(name, expectedName, "Token name does not match expected name");
        assertEq(
            description,
            string(abi.encodePacked(metadata.name, ". ", metadata.description)),
            "Token description does not match expected description"
        );
        assertEq(image, metadata.image, "Token image does not match expected image URL");
    }

    /// @dev Tests the symbol of the RevolutionToken
    function testSymbol() public {
        assertEq(revolutionToken.symbol(), tokenSymbol, "Symbol should be VRBS");
    }

    /// @dev Tests the name of the RevolutionToken
    function testName() public {
        assertEq(revolutionToken.name(), tokenName, "Name should be Vrbs");
    }

    /// @dev Tests the contract URI of the RevolutionToken
    function testContractURI() public {
        assertEq(
            revolutionToken.contractURI(),
            string(abi.encodePacked("ipfs://", revolutionTokenParams.contractURIHash)),
            "Contract URI should match"
        );
    }

    /// @dev Tests the initial state of the contract variables
    function testInitialVariablesState() public {
        address minter = revolutionToken.minter();
        address descriptorAddress = address(revolutionToken.descriptor());
        address cultureIndexAddress = address(revolutionToken.cultureIndex());

        assertEq(minter, address(auction), "Initial minter should be the auction");
        assertEq(descriptorAddress, address(descriptor), "Initial descriptor should be set correctly");
        assertEq(cultureIndexAddress, address(cultureIndex), "Initial cultureIndex should be set correctly");
    }

    /// @dev Tests that minted tokens are correctly associated with the art piece from CultureIndex
    function testCorrectArtAssociation() public {
        uint256 artPieceId = createDefaultArtPiece();
        vm.roll(vm.getBlockNumber() + 1);

        vm.stopPrank();
        vm.startPrank(address(auction));
        uint256 tokenId = revolutionToken.mint();

        uint256 recordedPieceId = revolutionToken.artPieces(tokenId);

        // Validate the token's associated art piece
        assertEq(recordedPieceId, artPieceId, "Minted token should be associated with the correct art piece");
    }

    /// @dev Tests creating an art piece with valid parameters.
    function testCreatePieceWithValidParameters() public {
        // Arrange
        string memory name = "Mona Lisa";
        string memory description = "A masterpiece";
        string memory image = "ipfs://legends";
        string memory animationUrl = "";
        string memory text = "";
        address creatorAddress = address(0x1);
        ICultureIndex.MediaType mediaType = ICultureIndex.MediaType.IMAGE;

        ICultureIndex.CreatorBps[] memory creators = new ICultureIndex.CreatorBps[](1);
        creators[0] = ICultureIndex.CreatorBps({ creator: creatorAddress, bps: 10_000 });

        // Check for PieceCreated event
        vm.expectEmit(true, true, true, true);
        emit ICultureIndexEvents.PieceCreated(
            0,
            address(this),
            ICultureIndex.ArtPieceMetadata({
                name: name,
                description: description,
                image: image,
                animationUrl: animationUrl,
                text: text,
                mediaType: mediaType
            }),
            creators
        );

        vm.stopPrank();
        vm.startPrank(address(this));
        uint256 artPieceId = createArtPiece(
            name,
            description,
            mediaType,
            image,
            text,
            animationUrl,
            creatorAddress,
            10_000
        );

        // Act
        (, ICultureIndex.ArtPieceMetadata memory metadata, , , ) = cultureIndex.pieces(artPieceId);

        // Assert
        assertEq(metadata.name, "Mona Lisa", "The name of the art piece should match the provided name.");
        assertEq(
            metadata.description,
            "A masterpiece",
            "The description of the art piece should match the provided description."
        );
        assertEq(metadata.image, "ipfs://legends", "The image URL of the art piece should match the provided URL.");
    }

    /// @dev Tests creating an art piece with invalid total basis points.
    function testCreatePieceWithInvalidBasisPoints() public {
        // Arrange
        string memory name = "Faulty Piece";
        string memory description = "This should not work";
        ICultureIndex.MediaType mediaType = ICultureIndex.MediaType.IMAGE;
        string memory image = "ipfs://faultyimage";
        string memory animationUrl = "";
        string memory text = "";
        address creatorAddress = address(0x1);
        uint256 invalidCreatorBps = 9999; // Invalid because it does not sum up to 10000

        // Act & Assert
        vm.expectRevert(abi.encodeWithSignature("INVALID_BPS_SUM()"));
        createArtPiece(name, description, mediaType, image, text, animationUrl, creatorAddress, invalidCreatorBps);
    }

    /// @dev Tests creating an art piece with a zero address in the creator array.
    function testCreatePieceWithZeroAddress() public {
        // Arrange
        string memory name = "No Creator Piece";
        string memory description = "This piece has no creator";
        ICultureIndex.MediaType mediaType = ICultureIndex.MediaType.IMAGE;
        string memory image = "ipfs://noimage";
        string memory animationUrl = "";
        string memory text = "";
        address zeroCreatorAddress = address(0); // Zero address used intentionally for test
        uint256 creatorBps = 10000;

        // Act & Assert
        vm.expectRevert(abi.encodeWithSignature("ADDRESS_ZERO()"));
        createArtPiece(name, description, mediaType, image, text, animationUrl, zeroCreatorAddress, creatorBps);
    }

    /// @dev Tests that creating an art piece with more than 100 creators fails.
    function testCreatePieceWithExcessCreators() public {
        // Arrange
        string memory name = "Too Many Creators";
        string memory description = "This piece has too many creators";
        ICultureIndex.MediaType mediaType = ICultureIndex.MediaType.IMAGE;
        string memory image = "ipfs://toomanycreators";
        string memory animationUrl = "";
        string memory text = "";

        // Creating a creators array with more than 100 creators should fail
        ICultureIndex.CreatorBps[] memory creators = new ICultureIndex.CreatorBps[](101);
        for (uint i = 0; i < 101; i++) {
            creators[i] = ICultureIndex.CreatorBps({ creator: address(uint160(i + 1)), bps: 100 });
        }

        // Act & Assert
        vm.expectRevert(abi.encodeWithSignature("MAX_NUM_CREATORS_EXCEEDED()"));
        cultureIndex.createPiece(
            ICultureIndex.ArtPieceMetadata({
                name: name,
                description: description,
                mediaType: mediaType,
                image: image,
                text: text,
                animationUrl: animationUrl
            }),
            creators
        );
    }

    /// @dev Tests that the pieceCount is incremented correctly after each successful creation.
    function testPieceCountIncrement() public {
        // Arrange
        uint256 initialPieceCount = cultureIndex.pieceCount();

        // Act
        createDefaultArtPiece();
        createDefaultArtPiece(); // Creating a second piece to verify increment

        // Assert
        uint256 newPieceCount = cultureIndex.pieceCount();
        assertEq(newPieceCount, initialPieceCount + 2, "pieceCount should be incremented by 2");
    }

    /// @dev Tests that voting on an art piece increments the totalVoteWeights and votes mapping correctly.
    function test_VotingOnArtPiece() public {
        // Arrange
        address voter = address(0x2);
        uint256 voteWeight = 100;

        // We assume govToken is the token used for voting, and voter has enough balance
        vm.stopPrank();
        vm.startPrank(address(revolutionPointsEmitter));
        revolutionPoints.mint(voter, voteWeight);

        vm.roll(vm.getBlockNumber() + 1);

        uint256 artPieceId = createDefaultArtPiece();

        uint256 initialTotalVoteWeight = cultureIndex.totalVoteWeights(artPieceId);

        // Act
        // Assuming the voter is msg.sender for the vote function, and it only takes the artPieceId
        vm.startPrank(voter); // Set the next message sender to the voter address
        cultureIndex.vote(artPieceId);

        // Assert
        uint256 newTotalVoteWeight = cultureIndex.totalVoteWeights(artPieceId);

        assertEq(
            newTotalVoteWeight,
            initialTotalVoteWeight + voteWeight,
            "Total vote weight should be incremented by the vote weight"
        );
    }

    /// @dev Tests that a vote from a voter with a zero balance is rejected.
    function testVotingWithZeroBalance() public {
        vm.stopPrank();
        // Arrange
        uint256 artPieceId = createDefaultArtPiece();
        vm.roll(vm.getBlockNumber() + 1);
        address voter = address(0x3); // An address that does not hold any voting tokens

        // Act & Assert
        vm.startPrank(voter); // Set the next message sender to the voter address
        vm.expectRevert(abi.encodeWithSignature("WEIGHT_TOO_LOW()"));
        cultureIndex.vote(artPieceId); // Trying to vote
    }

    /// @dev Tests that a voter cannot vote for a piece more than once.
    function testDoubleVotingRestriction() public {
        // Arrange
        address voter = address(0x4);
        uint256 voteWeight = 50;

        // Give the voter some tokens and allow them to vote
        vm.stopPrank();
        vm.startPrank(address(revolutionPointsEmitter));
        revolutionPoints.mint(voter, voteWeight);
        vm.roll(vm.getBlockNumber() + 1);

        uint256 artPieceId = createDefaultArtPiece();

        // First vote
        vm.startPrank(voter);
        cultureIndex.vote(artPieceId);

        // Act & Assert
        // Attempt to vote again
        vm.startPrank(voter);
        vm.expectRevert(abi.encodeWithSignature("ALREADY_VOTED()"));
        cultureIndex.vote(artPieceId);
    }

    /// @dev Tests that voting on an already dropped piece is rejected.
    function testVotingOnDroppedPiece() public {
        // Arrange
        uint256 artPieceId = createDefaultArtPiece();
        address voter = address(0x5);
        uint256 voteWeight = 100;
        vm.roll(vm.getBlockNumber() + 1);

        vm.stopPrank();
        vm.startPrank(address(auction));

        // Simulate dropping the piece
        revolutionToken.mint(); // Replace with your actual function to mark a piece as dropped

        // Give the voter some tokens
        vm.stopPrank();
        vm.startPrank(address(revolutionPointsEmitter));
        revolutionPoints.mint(voter, voteWeight);
        vm.roll(vm.getBlockNumber() + 1);

        // Act & Assert
        vm.startPrank(voter); // Set the next message sender to the voter address
        vm.expectRevert(abi.encodeWithSignature("ALREADY_DROPPED()"));
        cultureIndex.vote(artPieceId);
    }

    /// @dev Tests that getTopVotedPiece returns the correct art piece.
    function test_GetTopVotedPiece() public {
        // Arrange

        // Assign vote weights
        uint256 firstPieceVoteWeight = 100;
        uint256 secondPieceVoteWeight = 200;
        address voter = address(0x6);

        // Give the voter some tokens and vote on both pieces
        vm.stopPrank();
        vm.startPrank(address(revolutionPointsEmitter));
        revolutionPoints.mint(voter, firstPieceVoteWeight);

        // Vote on the first piece
        vm.startPrank(voter);
        vm.roll(vm.getBlockNumber() + 1);

        uint256 firstArtPieceId = createDefaultArtPiece();

        cultureIndex.vote(firstArtPieceId);

        vm.startPrank(address(revolutionPointsEmitter));
        revolutionPoints.mint(voter, secondPieceVoteWeight);
        vm.roll(vm.getBlockNumber() + 1);

        // Vote on the second piece with a higher weight
        uint256 secondArtPieceId = createArtPiece(
            "Second Piece",
            "Another masterpiece",
            ICultureIndex.MediaType.IMAGE,
            "ipfs://secondpiece",
            "",
            "",
            address(0x2),
            10000
        );
        vm.startPrank(voter);
        cultureIndex.vote(secondArtPieceId);

        // Act
        ICultureIndex.ArtPiece memory topPiece = cultureIndex.getTopVotedPiece();

        // Assert
        assertEq(
            topPiece.pieceId,
            secondArtPieceId,
            "The top voted piece should be the second piece with higher votes"
        );
    }

    /// @dev Tests that dropTopVotedPiece updates the isDropped flag of the art piece.
    function test_DropTopVotedPiece() public {
        // Arrange
        // Vote on the piece to make it the top voted
        address voter = address(0x7);
        vm.stopPrank();
        vm.startPrank(address(revolutionPointsEmitter));
        revolutionPoints.mint(voter, 100);
        vm.roll(vm.getBlockNumber() + 1);

        uint256 artPieceId = createDefaultArtPiece();

        vm.startPrank(voter);
        cultureIndex.vote(artPieceId);
        vm.stopPrank();
        vm.roll(vm.getBlockNumber() + 1);

        vm.startPrank(address(auction));
        // Act
        revolutionToken.mint();

        // Assert
        ICultureIndex.ArtPiece memory piece = cultureIndex.getPieceById(artPieceId);
        assertTrue(piece.isDropped, "Art piece should be marked as dropped after dropping");
    }

    /// @dev Tests that dropTopVotedPiece fails with the correct error when the heap is empty.
    function testDropTopVotedPieceOnEmptyHeap() public {
        // Arrange
        // Ensure no art pieces have been created or all created pieces are already dropped
        vm.stopPrank();
        vm.startPrank(address(auction));

        // Act & Assert
        vm.expectRevert("dropTopVotedPiece failed");
        revolutionToken.mint();
    }

    /// @dev Tests that voting on a non-existent art piece is rejected.
    function testVotingOnNonExistentArtPiece() public {
        // Arrange
        uint256 nonExistentArtPieceId = 999; // Assuming this ID has not been created
        address voter = address(0x9);
        uint256 voteWeight = 100;

        vm.stopPrank();
        vm.startPrank(address(revolutionPointsEmitter));
        revolutionPoints.mint(voter, voteWeight);
        vm.roll(vm.getBlockNumber() + 1);

        // Act & Assert
        vm.startPrank(voter);
        vm.expectRevert(abi.encodeWithSignature("INVALID_PIECE_ID()"));
        cultureIndex.vote(nonExistentArtPieceId);
    }

    /// @dev Tests that retrieving votes for a non-existent art piece is rejected.
    function testRetrievingVotesForNonExistentArtPiece() public {
        // Arrange
        uint256 nonExistentArtPieceId = 999; // Assuming this ID has not been created

        // Act & Assert
        vm.expectRevert(abi.encodeWithSignature("INVALID_PIECE_ID()"));
        cultureIndex.getVote(nonExistentArtPieceId, address(this)); // This function should revert
    }

    // Helper function to decode base64 encoded metadata
    function decodeMetadata(string memory base64Metadata) internal pure returns (string memory) {
        // Decode the base64 string
        return string(Base64Decode.decode(base64Metadata));
    }

    // Helper function to extract a substring from a string
    function substring(string memory str, uint256 startIndex, uint256 endIndex) internal pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        bytes memory result = new bytes(endIndex - startIndex);
        for (uint256 i = startIndex; i < endIndex; i++) {
            result[i - startIndex] = strBytes[i];
        }
        return string(result);
    }

    // Helper function to parse JSON strings into components
    function parseJson(
        string memory _json
    ) internal returns (string memory name, string memory description, string memory image) {
        uint returnValue;
        JsmnSolLib.Token[] memory tokens;
        uint actualNum;

        // Number of tokens to be parsed in the JSON (could be estimated or exactly known)
        uint256 numTokens = 20; // Increase if necessary to accommodate all fields in the JSON

        // Parse the JSON
        (returnValue, tokens, actualNum) = JsmnSolLib.parse(_json, numTokens);

        emit log_uint(returnValue);
        emit log_uint(actualNum);
        emit log_uint(tokens.length);

        // Extract values from JSON by token indices
        for (uint256 i = 0; i < actualNum; i++) {
            JsmnSolLib.Token memory t = tokens[i];

            // Check if the token is a key
            if (t.jsmnType == JsmnSolLib.JsmnType.STRING && (i + 1) < actualNum) {
                string memory key = JsmnSolLib.getBytes(_json, t.start, t.end);
                string memory value = JsmnSolLib.getBytes(_json, tokens[i + 1].start, tokens[i + 1].end);

                // Compare the key with expected fields
                if (keccak256(bytes(key)) == keccak256(bytes("name"))) {
                    name = value;
                } else if (keccak256(bytes(key)) == keccak256(bytes("description"))) {
                    description = value;
                } else if (keccak256(bytes(key)) == keccak256(bytes("image"))) {
                    image = value;
                }
                // Skip the value token, as the key's value is always the next token
                i++;
            }
        }

        return (name, description, image);
    }

    /// @dev Tests the interaction with the CultureIndex during minting
    function testCultureIndexInteraction() public {
        vm.stopPrank();
        vm.startPrank(address(auction));

        //create piece
        createDefaultArtPiece();
        vm.roll(vm.getBlockNumber() + 1);

        uint256 preMintPieceId = cultureIndex.topVotedPieceId();
        uint256 tokenId = revolutionToken.mint();
        uint256 pieceId = revolutionToken.artPieces(tokenId);

        assertTrue(pieceId == preMintPieceId, "Art piece ID should match top voted piece ID before minting");
    }
}
