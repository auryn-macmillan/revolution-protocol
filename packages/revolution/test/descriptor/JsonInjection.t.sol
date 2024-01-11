// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";
import { DescriptorTest } from "./Descriptor.t.sol";
import { ICultureIndex } from "../../src/interfaces/ICultureIndex.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

contract JsonInjectionAttackTest is DescriptorTest {
    using Strings for uint256;

    function setUp() public override {
        super.setUp();
        super.setMockParams();

        super.setRevolutionTokenParams("Vrbs", "VRBS", "https://example.com/token/", "Vrb");

        super.setCultureIndexParams("Vrbs", "Our community Vrbs. Must be 32x32.", 10, 500, 0);

        super.deployMock();
    }

    /// @notice Test `tokenURI` with injected animation
    function testTokenURIWithMixedMediaMetadata() public {
        uint256 tokenId = 3;
        ICultureIndex.ArtPieceMetadata memory expectedMetadata = ICultureIndex.ArtPieceMetadata({
            name: "Mona Lisa",
            description: "A renowned painting by Leonardo da Vinci",
            mediaType: ICultureIndex.MediaType.IMAGE,
            image: "ipfs://realMonaLisa",
            text: "",
            animationUrl: '", "image": "ipfs://fakeMonaLisa' // malicious string injected
        });

        string memory uri = descriptor.tokenURI(tokenId, expectedMetadata);

        string memory errorMessage = "Token URI should reflect the escaped animation URL";

        // The token URI should reflect both image and animation URLs
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
            //escaped characters
            '\\", \\"image\\": \\"ipfs://fakeMonaLisa',
            string(abi.encodePacked(errorMessage, " - Animation URL mismatch"))
        );
    }

    function _createArtPieceCreators() internal pure returns (ICultureIndex.CreatorBps[] memory) {
        ICultureIndex.CreatorBps[] memory creators = new ICultureIndex.CreatorBps[](1);
        creators[0] = ICultureIndex.CreatorBps({ creator: address(0xc), bps: 10_000 });
        return creators;
    }

    function _substring(string memory str, uint256 startIndex, uint256 endIndex) internal pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        bytes memory result = new bytes(endIndex - startIndex);
        for (uint256 i = startIndex; i < endIndex; ) {
            result[i - startIndex] = strBytes[i];
            unchecked {
                ++i;
            }
        }
        return string(result);
    }
}
