// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { AuctionHouseTest } from "./AuctionHouse.t.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ICultureIndex } from "../../src/interfaces/ICultureIndex.sol";
import { IRevolutionToken } from "../../src/interfaces/IRevolutionToken.sol";
import { MockWETH } from "../mock/MockWETH.sol";
import { toDaysWadUnsafe } from "../../src/libs/SignedWadMath.sol";

contract AuctionHouseOutOfGasTest is AuctionHouseTest {
    // create an auction with a piece of art with given number of creators and finish it
    function _createAndFinishAuction() internal {
        uint nCreators = cultureIndex.MAX_NUM_CREATORS();
        address[] memory creatorAddresses = new address[](nCreators);
        uint256[] memory creatorBps = new uint256[](nCreators);
        uint256 totalBps = 0;
        address[] memory creators = new address[](nCreators);
        for (uint i = 0; i < nCreators; i++) {
            creators[i] = address(uint160(0x1234 + i));
        }

        for (uint256 i = 0; i < nCreators; i++) {
            creatorAddresses[i] = address(creators[i]);
            if (i == nCreators - 1) {
                creatorBps[i] = 10_000 - totalBps;
            } else {
                creatorBps[i] = (10_000) / (nCreators - 1);
            }
            totalBps += creatorBps[i];
        }

        // create the initial art piece
        uint256 verbId = createArtPieceMultiCreator(
            createLongString(cultureIndex.MAX_NAME_LENGTH()),
            createLongString(cultureIndex.MAX_DESCRIPTION_LENGTH()),
            ICultureIndex.MediaType.ANIMATION,
            string.concat("ipfs://", createLongString(cultureIndex.MAX_IMAGE_LENGTH() - 7)),
            string.concat("ipfs://", createLongString(cultureIndex.MAX_TEXT_LENGTH() - 7)),
            string.concat("ipfs://", createLongString(cultureIndex.MAX_ANIMATION_URL_LENGTH() - 7)),
            creatorAddresses,
            creatorBps
        );

        vm.roll(vm.getBlockNumber() + 1); // roll block number to enable voting snapshot

        vm.startPrank(auction.owner());
        auction.unpause();
        vm.stopPrank();

        uint256 bidAmount = auction.reservePrice();
        vm.deal(address(creators[nCreators - 1]), bidAmount + 1 ether);
        vm.startPrank(address(creators[nCreators - 1]));
        auction.createBid{ value: bidAmount }(verbId, address(creators[nCreators - 1]));
        vm.stopPrank();

        vm.warp(block.timestamp + auction.duration() + 1); // Fast forward time to end the auction

        // create another art piece so that it's possible to create next auction
        createArtPieceMultiCreator(
            createLongString(cultureIndex.MAX_NAME_LENGTH()),
            createLongString(cultureIndex.MAX_DESCRIPTION_LENGTH()),
            ICultureIndex.MediaType.ANIMATION,
            string.concat("ipfs://", createLongString(cultureIndex.MAX_IMAGE_LENGTH() - 7)),
            string.concat("ipfs://", createLongString(cultureIndex.MAX_TEXT_LENGTH() - 7)),
            string.concat("ipfs://", createLongString(cultureIndex.MAX_ANIMATION_URL_LENGTH() - 7)),
            creatorAddresses,
            creatorBps
        );
        vm.roll(vm.getBlockNumber() + 1); // roll block number to enable voting snapshot
    }

    // Helper function to create a string of a specified length
    function createLongString(uint length) internal pure returns (string memory) {
        bytes memory buffer = new bytes(length);
        for (uint i = 0; i < length; i++) {
            buffer[i] = bytes1(uint8(65 + (i % 26))); // Fills the string with a repeating pattern of letters
        }
        return string(buffer);
    }

    //attempt to trigger an auction paused error with differing gas amounts
    function test_OutOfGas_DOS(uint gasUsed) public {
        vm.assume(gasUsed < 31_000_000); // block gas limit is 30m
        vm.startPrank(cultureIndex.owner());
        cultureIndex._setQuorumVotesBPS(0);
        vm.stopPrank();

        _createAndFinishAuction();

        assertFalse(auction.paused());

        try auction.settleCurrentAndCreateNewAuction{ gas: gasUsed }() {
            // if the auction is paused, this will fail
            assertFalse(auction.paused());
        } catch {}

        assertFalse(auction.paused());
    }
}

contract ContractWithoutReceiveOrFallback {
    // This contract intentionally does not have receive() or fallback()
    // functions to test the behavior of sending Ether to such a contract.
}

contract ContractThatRejectsEther {
    // This contract has a receive() function that reverts any Ether transfers.
    receive() external payable {
        revert("Rejecting Ether transfer");
    }

    // Alternatively, you could use a fallback function that reverts.
    // fallback() external payable {
    //     revert("Rejecting Ether transfer");
    // }
}
