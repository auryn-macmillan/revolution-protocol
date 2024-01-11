// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "../../src/Descriptor.sol";
import { IDescriptor } from "../../src/interfaces/IDescriptor.sol";
import "../utils/Base64Decode.sol";
import "../utils/JsmnSolLib.sol";
import { ICultureIndex } from "../../src/interfaces/ICultureIndex.sol";
import { RevolutionBuilderTest } from "../RevolutionBuilder.t.sol";

contract DescriptorTest is RevolutionBuilderTest {
    string tokenNamePrefix = "Vrb";

    // Helper function to decode base64 encoded metadata from a data URI
    function decodeMetadata(string memory uri) internal pure returns (string memory) {
        // Split the URI into its components and decode the base64 part
        (, string memory base64Part) = splitDataURI(uri);
        bytes memory decodedBytes = Base64Decode.decode(base64Part);
        return string(decodedBytes);
    }

    // Helper function to assert the integrity of the full metadata in the token URI
    function assertFullMetadataIntegrity(
        string memory uri,
        ICultureIndex.ArtPieceMetadata memory expectedMetadata,
        uint256 tokenId,
        string memory errorMessage
    ) internal {
        string memory metadataJson = decodeMetadata(uri);
        (string memory name, string memory description, string memory imageUrl, string memory animationUrl) = parseJson(
            metadataJson
        );

        //expected name should tokenNamePrefix + space + tokenId
        string memory expectedName = string(abi.encodePacked(tokenNamePrefix, " ", Strings.toString(tokenId)));

        assertEq(name, expectedName, string(abi.encodePacked(errorMessage, " - Name mismatch")));
        assertEq(
            description,
            string(abi.encodePacked(expectedMetadata.name, ". ", expectedMetadata.description)),
            string(abi.encodePacked(errorMessage, " - Description mismatch"))
        );
        assertEq(imageUrl, expectedMetadata.image, string(abi.encodePacked(errorMessage, " - Image URL mismatch")));
        assertEq(
            animationUrl,
            expectedMetadata.animationUrl,
            string(abi.encodePacked(errorMessage, " - Animation URL mismatch"))
        );
    }

    // Helper function to parse JSON strings into components
    function parseJson(
        string memory _json
    )
        internal
        returns (string memory name, string memory description, string memory image, string memory animationUrl)
    {
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
                } else if (keccak256(bytes(key)) == keccak256(bytes("animation_url"))) {
                    animationUrl = value;
                }
                // Skip the value token, as the key's value is always the next token
                i++;
            }
        }

        return (name, description, image, animationUrl);
    }

    // Helper function to check if the URI starts with a specific string
    function startsWith(string memory fullString, string memory searchString) internal pure returns (bool) {
        bytes memory fullStringBytes = bytes(fullString);
        bytes memory searchStringBytes = bytes(searchString);

        if (searchStringBytes.length > fullStringBytes.length) {
            return false;
        }

        for (uint i = 0; i < searchStringBytes.length; i++) {
            if (fullStringBytes[i] != searchStringBytes[i]) {
                return false;
            }
        }

        return true;
    }

    /// @notice Splits a data URI into its MIME type and base64 components.
    /// @param uri The data URI to split.
    /// @return mimeType The MIME type of the data.
    /// @return base64Data The base64 encoded data.
    function splitDataURI(string memory uri) internal pure returns (string memory mimeType, string memory base64Data) {
        // Find the comma that separates the MIME type from the base64 data
        bytes memory uriBytes = bytes(uri);
        uint256 commaIndex = findComma(uriBytes);

        // Extract the MIME type
        mimeType = string(substring(uriBytes, 5, commaIndex)); // Starting after 'data:'

        // Extract the base64 encoded data
        base64Data = string(substring(uriBytes, commaIndex + 1, uriBytes.length));

        return (mimeType, base64Data);
    }

    /// @notice Finds the index of the first comma in a bytes array.
    /// @param b The bytes array to search.
    /// @return The index of the first comma.
    function findComma(bytes memory b) internal pure returns (uint256) {
        for (uint256 i = 0; i < b.length; i++) {
            if (b[i] == ",") {
                return i;
            }
        }
        revert("Comma not found in data URI");
    }

    /// @notice Gets a substring from a bytes array, given the start and end index.
    /// @param b The bytes array to get a substring from.
    /// @param startIndex The start index of the substring.
    /// @param endIndex The end index of the substring.
    /// @return The substring.
    function substring(bytes memory b, uint256 startIndex, uint256 endIndex) internal pure returns (bytes memory) {
        bytes memory result = new bytes(endIndex - startIndex);
        for (uint256 i = startIndex; i < endIndex; i++) {
            result[i - startIndex] = b[i];
        }
        return result;
    }
}
