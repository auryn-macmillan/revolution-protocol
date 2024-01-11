// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { Test } from "forge-std/Test.sol";
import { AuctionHouse } from "../../src/AuctionHouse.sol";
import { MockERC20 } from "../mock/MockERC20.sol";
import { RevolutionToken } from "../../src/RevolutionToken.sol";
import { IRevolutionToken } from "../../src/interfaces/IRevolutionToken.sol";
import { Descriptor } from "../../src/Descriptor.sol";
import { CultureIndex } from "../../src/culture-index/CultureIndex.sol";
import { IDescriptorMinimal } from "../../src/interfaces/IDescriptorMinimal.sol";
import { ICultureIndex, ICultureIndexEvents } from "../../src/interfaces/ICultureIndex.sol";
import { IAuctionHouse } from "../../src/interfaces/IAuctionHouse.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { RevolutionPoints } from "../../src/RevolutionPoints.sol";
import { RevolutionPointsEmitter } from "../../src/RevolutionPointsEmitter.sol";
import { IRevolutionPointsEmitter } from "../../src/interfaces/IRevolutionPointsEmitter.sol";
import { wadMul, wadDiv } from "../../src/libs/SignedWadMath.sol";
import { RevolutionProtocolRewards } from "@cobuild/protocol-rewards/src/RevolutionProtocolRewards.sol";
import { PointsEmitterRewards } from "@cobuild/protocol-rewards/src/abstract/PointsEmitter/PointsEmitterRewards.sol";
import { ERC721CheckpointableUpgradeable } from "../../src/base/ERC721CheckpointableUpgradeable.sol";
import { RevolutionBuilderTest } from "../RevolutionBuilder.t.sol";

contract AuctionHouseTest is RevolutionBuilderTest {
    function setUp() public override {
        super.setUp();
        super.setMockParams();

        super.setPointsParams("Revolution Governance", "GOV");

        super.setCultureIndexParams("Vrbs", "Our community Vrbs. Must be 32x32.", 10, 200, 0);

        super.setRevolutionTokenParams("Vrbs", "VRBS", "QmQzDwaZ7yQxHHs7sQQenJVB89riTSacSGcJRv9jtHPuz5", "Vrb");

        super.setAuctionParams(
            15 minutes, // timeBuffer
            1 ether, // reservePrice
            24 hours, // duration
            5, // minBidIncrementPercentage
            2_000, // creatorRateBps
            5_000, //entropyRateBps
            1_000 //minCreatorRateBps
        );

        super.deployMock();

        vm.startPrank(address(executor));
    }

    // Utility function to create a new art piece and return its ID
    function createArtPiece(
        string memory name,
        string memory description,
        ICultureIndex.MediaType mediaType,
        string memory image,
        string memory text,
        string memory animationUrl,
        address creatorAddress,
        uint256 creatorBps
    ) internal returns (uint256) {
        address[] memory creatorAddresses = new address[](1);
        creatorAddresses[0] = creatorAddress;

        uint256[] memory creatorBpsArray = new uint256[](1);
        creatorBpsArray[0] = creatorBps;

        return
            createArtPieceMultiCreator(
                name,
                description,
                mediaType,
                image,
                text,
                animationUrl,
                creatorAddresses,
                creatorBpsArray
            );
    }

    //Utility function to create default art piece
    function createDefaultArtPiece() public returns (uint256) {
        return
            createArtPiece(
                "Mona Lisa",
                "A masterpiece",
                ICultureIndex.MediaType.IMAGE,
                "ipfs://legends",
                "",
                "",
                address(0x1),
                10000
            );
    }

    // Utility function to create a new art piece with multiple creators and return its ID
    function createArtPieceMultiCreator(
        string memory name,
        string memory description,
        ICultureIndex.MediaType mediaType,
        string memory image,
        string memory text,
        string memory animationUrl,
        address[] memory creatorAddresses,
        uint256[] memory creatorBps
    ) internal returns (uint256) {
        ICultureIndex.ArtPieceMetadata memory metadata = ICultureIndex.ArtPieceMetadata({
            name: name,
            description: description,
            mediaType: mediaType,
            image: image,
            text: text,
            animationUrl: animationUrl
        });

        ICultureIndex.CreatorBps[] memory creators = new ICultureIndex.CreatorBps[](creatorAddresses.length);
        for (uint256 i = 0; i < creatorAddresses.length; i++) {
            creators[i] = ICultureIndex.CreatorBps({ creator: creatorAddresses[i], bps: creatorBps[i] });
        }

        return cultureIndex.createPiece(metadata, creators);
    }
}
