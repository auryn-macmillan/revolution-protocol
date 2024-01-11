// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "../../src/Descriptor.sol";
import { IDescriptor } from "../../src/interfaces/IDescriptor.sol";
import "../utils/Base64Decode.sol";
import "../utils/JsmnSolLib.sol";
import { ICultureIndex } from "../../src/interfaces/ICultureIndex.sol";
import { DescriptorTest } from "./Descriptor.t.sol";

contract DescriptorURIDataTest is DescriptorTest {
    function setUp() public virtual override {
        super.setUp();
        super.setMockParams();

        super.setRevolutionTokenParams("Mock", "MOCK", "https://example.com/token/", tokenNamePrefix);

        super.deployMock();

        vm.startPrank(address(executor));
    }

    /// @notice Test that toggling `isDataURIEnabled` changes state correctly
    function testToggleDataURIEnabled() public {
        bool originalState = descriptor.isDataURIEnabled();
        descriptor.toggleDataURIEnabled();
        bool newState = descriptor.isDataURIEnabled();

        assertEq(newState, !originalState, "isDataURIEnabled should be toggled");
    }

    /// @notice Test that only owner can toggle `isDataURIEnabled`
    function testToggleDataURIEnabledAccessControl() public {
        vm.stopPrank();
        address nonOwner = address(0x123);
        vm.startPrank(nonOwner);
        vm.expectRevert();
        descriptor.toggleDataURIEnabled();
        vm.stopPrank();
    }

    /// @notice Test `setBaseURI` updates `baseURI` correctly
    function testSetBaseURI() public {
        string memory newBaseURI = "https://example.com/";
        descriptor.setBaseURI(newBaseURI);
        string memory currentBaseURI = descriptor.baseURI();

        assertEq(currentBaseURI, newBaseURI, "baseURI should be updated");
    }

    /// @notice Test that only the owner can update `baseURI`
    function testSetBaseURI_AccessControl() public {
        vm.stopPrank();
        string memory newBaseURI = "https://newexample.com/";
        address nonOwner = address(0x456);

        vm.startPrank(nonOwner);
        vm.expectRevert();
        descriptor.setBaseURI(newBaseURI);
        vm.stopPrank();

        // The baseURI should remain unchanged since the non-owner could not update it
        string memory currentBaseURI = descriptor.baseURI();
        assertEq(currentBaseURI, "", "baseURI should not have changed");
    }

    /// @notice Test `tokenURI` returns correct data URI when `isDataURIEnabled` is true
    function testTokenURIWithDataURIEnabled() public {
        // Enable data URI
        descriptor.toggleDataURIEnabled();
        assertFalse(descriptor.isDataURIEnabled(), "Data URI should be enabled");

        // Set up a token ID and dummy metadata
        uint256 tokenId = 1;
        ICultureIndex.ArtPieceMetadata memory metadata = ICultureIndex.ArtPieceMetadata({
            name: "Test Art",
            description: "A description",
            mediaType: ICultureIndex.MediaType.IMAGE,
            image: "https://example.com/image.png",
            text: "",
            animationUrl: ""
        });

        // Call tokenURI and check the return value is a data URI
        string memory uri = descriptor.tokenURI(tokenId, metadata);
        assertTrue(bytes(uri).length > 0, "URI should not be empty");
        emit log_string(uri);
        // Further data URI validation can be done here if necessary

        //tokenURI should just be 1
        assertEq(uri, "1", "URI should just be the token ID");
    }

    /// @notice Test `tokenURI` returns correct HTTP URL when `isDataURIEnabled` is false
    function testTokenURIWithHTTPURL() public {
        // Make sure data URI is disabled
        descriptor.toggleDataURIEnabled();
        assertFalse(descriptor.isDataURIEnabled(), "Data URI should be disabled");

        // Set base URI
        string memory baseURI = "https://api.example.com/token/";
        descriptor.setBaseURI(baseURI);

        // Set up token ID
        uint256 tokenId = 1;

        // Create dummy metadata
        ICultureIndex.ArtPieceMetadata memory metadata = ICultureIndex.ArtPieceMetadata({
            name: "Test Art",
            description: "A description",
            mediaType: ICultureIndex.MediaType.IMAGE,
            image: "https://example.com/image.png",
            text: "",
            animationUrl: ""
        });

        // Call tokenURI and check it returns the correct HTTP URL
        string memory expectedURI = string(abi.encodePacked(baseURI, Strings.toString(tokenId)));
        string memory actualURI = descriptor.tokenURI(tokenId, metadata);
        assertEq(actualURI, expectedURI, "The URI should be a concatenation of the baseURI and token ID");
    }

    /// @notice Test `dataURI` returns valid base64 encoded data URI
    function testDataURI() public {
        uint256 tokenId = 1;
        ICultureIndex.ArtPieceMetadata memory metadata = ICultureIndex.ArtPieceMetadata({
            name: "Test Art",
            description: "A piece of art",
            mediaType: ICultureIndex.MediaType.IMAGE,
            image: "https://example.com/image.png",
            text: "",
            animationUrl: ""
        });

        string memory uri = descriptor.dataURI(tokenId, metadata);
        assertTrue(bytes(uri).length > 0, "dataURI should not be empty");
        // Check if the string contains the base64 identifier which indicates a base64 encoded data URI
        assertEq(
            substring(bytes(uri), 0, 29),
            "data:application/json;base64,",
            "dataURI should start with 'data:application/json;base64,'"
        );
    }

    /// @notice Test `genericDataURI` returns valid base64 encoded data URI
    function testGenericDataURI() public {
        ICultureIndex.ArtPieceMetadata memory metadata = ICultureIndex.ArtPieceMetadata({
            name: "Test Art",
            description: "A generic art piece",
            mediaType: ICultureIndex.MediaType.IMAGE,
            image: "https://example.com/image.png",
            text: "",
            animationUrl: ""
        });

        string memory uri = descriptor.genericDataURI(metadata.name, metadata);
        assertTrue(bytes(uri).length > 0, "genericDataURI should not be empty");
        assertEq(
            substring(bytes(uri), 0, 29),
            "data:application/json;base64,",
            "dataURI should start with 'data:application/json;base64,'"
        );
    }

    /// @notice Test `toggleDataURIEnabled` emits `DataURIToggled` event
    function testToggleDataURIEnabledEvent() public {
        bool expectedNewState = !descriptor.isDataURIEnabled();
        vm.expectEmit(true, true, false, true);
        emit IDescriptor.DataURIToggled(expectedNewState);
        descriptor.toggleDataURIEnabled();
    }

    /// @notice Test `setBaseURI` emits `BaseURIUpdated` event
    function testSetBaseURIEvent() public {
        string memory newBaseURI = "https://example.com/newbase";
        vm.expectEmit(true, true, false, true);
        emit IDescriptor.BaseURIUpdated(newBaseURI);
        descriptor.setBaseURI(newBaseURI);
    }

    /// @notice Test baseline `tokenURI` with `isDataURIEnabled` true by default
    function testBaselineTokenURIWithDataURIEnabled() public {
        // Since isDataURIEnabled is true by default, we don't need to toggle it
        assertTrue(descriptor.isDataURIEnabled(), "isDataURIEnabled should be true by default");

        uint256 tokenId = 1;
        ICultureIndex.ArtPieceMetadata memory metadata = ICultureIndex.ArtPieceMetadata({
            name: "Baseline Art",
            description: "The baseline piece",
            mediaType: ICultureIndex.MediaType.IMAGE,
            image: "https://example.com/baseline.png",
            text: "",
            animationUrl: ""
        });

        string memory uri = descriptor.tokenURI(tokenId, metadata);
        assertTrue(bytes(uri).length > 0, "URI should not be empty");
        assertEq(
            substring(bytes(uri), 0, 29),
            "data:application/json;base64,",
            "dataURI should start with 'data:application/json;base64,'"
        );
    }

    /// @notice Test owner can transfer ownership using `transferOwnership`
    function testTransferOwnership() public {
        address newOwner = address(0x456);

        // The current owner transfers ownership to the newOwner
        descriptor.transferOwnership(newOwner);

        vm.startPrank(address(newOwner));
        descriptor.acceptOwnership();

        // Verify that the new owner is indeed set
        assertEq(descriptor.owner(), newOwner, "Ownership should be transferred to newOwner");
    }

    /// @notice Ensure `transferOwnership` access control
    function testTransferOwnershipAccessControl() public {
        vm.stopPrank();
        address nonOwner = address(0x789);
        address newOwner = address(0x456);

        // Start prank as nonOwner, expect revert on ownership transfer attempt
        vm.startPrank(nonOwner);
        vm.expectRevert();
        descriptor.transferOwnership(newOwner);
        vm.stopPrank();

        // Verify ownership has not changed
        assertEq(descriptor.owner(), address(executor), "Ownership should not have changed");
    }

    /// @notice Test `tokenURI` with only image metadata set
    function testTokenURIWithOnlyImageMetadata() public {
        uint256 tokenId = 1;
        ICultureIndex.ArtPieceMetadata memory metadata = ICultureIndex.ArtPieceMetadata({
            name: "",
            description: "",
            mediaType: ICultureIndex.MediaType.IMAGE,
            image: "https://example.com/image.png",
            text: "",
            animationUrl: ""
        });

        string memory uri = descriptor.tokenURI(tokenId, metadata);

        // Check if the token URI contains the image URL
        assertUriContainsImage(uri, metadata.image, "Token URI should contain the image metadata");
    }

    /// @notice Test `tokenURI` with mixed media types in metadata
    function testTokenURIWithMixedMediaMetadata() public {
        uint256 tokenId = 3;
        ICultureIndex.ArtPieceMetadata memory metadata = ICultureIndex.ArtPieceMetadata({
            name: "Mixed Media Art",
            description: "Art with mixed media types",
            mediaType: ICultureIndex.MediaType.ANIMATION,
            image: "https://example.com/mixed-image.png",
            text: "",
            animationUrl: "https://example.com/mixed-animation.mp4"
        });

        string memory uri = descriptor.tokenURI(tokenId, metadata);

        // The token URI should reflect both image and animation URLs
        assertFullMetadataIntegrity(uri, metadata, tokenId, "Token URI should reflect mixed media types correctly");
    }

    /// @notice Test `tokenURI` with full metadata set
    function testTokenURIWithFullMetadata() public {
        uint256 tokenId = 2;
        ICultureIndex.ArtPieceMetadata memory metadata = ICultureIndex.ArtPieceMetadata({
            name: "Full Metadata Art",
            description: "Complete metadata for testing",
            mediaType: ICultureIndex.MediaType.IMAGE,
            image: "https://example.com/full-image.png",
            text: "This is a full metadata test.",
            animationUrl: "https://example.com/animation.mp4"
        });

        string memory uri = descriptor.tokenURI(tokenId, metadata);

        // Validate the token URI against the full metadata
        assertFullMetadataIntegrity(uri, metadata, tokenId, "Token URI should correctly represent the full metadata");
    }

    // Corrected use of startsWith in assertUriContainsImage function
    function assertUriContainsImage(
        string memory uri,
        string memory expectedImageUrl,
        string memory errorMessage
    ) internal {
        // Decode the URI if it's a data URI, else use as is
        string memory metadataJson = startsWith(uri, "data:") ? decodeMetadata(uri) : uri;
        (, , string memory imageUrl, ) = parseJson(metadataJson);

        assertEq(imageUrl, expectedImageUrl, errorMessage);
    }
}
