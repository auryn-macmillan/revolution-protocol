// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { Test } from "forge-std/Test.sol";
import { CultureIndex } from "../../src/culture-index/CultureIndex.sol";
import { MockERC20 } from "../mock/MockERC20.sol";
import { ICultureIndex, ICultureIndexEvents } from "../../src/interfaces/ICultureIndex.sol";
import { RevolutionPoints } from "../../src/RevolutionPoints.sol";
import { CultureIndexTestSuite } from "./CultureIndex.t.sol";
import { ERC721CheckpointableUpgradeable } from "../../src/base/ERC721CheckpointableUpgradeable.sol";

/**
 * @title CultureIndex Edge Case Test
 * @dev Test contract for CultureIndex
 */
contract CultureIndexEdgeCaseTest is CultureIndexTestSuite {
    //utility function to insert and mint n number of pieces
    function _insertPiecesAndVote(uint256 n) public {
        address voter = address(89);

        // Create 1 million pieces
        for (uint256 i = 0; i < n; i++) {
            uint256 randomAmount = uint256(keccak256(abi.encodePacked(block.timestamp, i))) % 1000;

            //mint revolutionPoints to voter
            vm.prank(address(revolutionPointsEmitter));
            revolutionPoints.mint(voter, randomAmount > 0 ? randomAmount : 1);
            vm.roll(vm.getBlockNumber() + 1);

            uint256 pieceId = createDefaultArtPiece();

            //every 1000 blocks roll vm.getBlockNumber + 1 to avoid limit
            if (i % 10000 == 0) {
                vm.roll(vm.getBlockNumber() + 1);
            }

            vm.prank(voter);
            cultureIndex.vote(pieceId);
        }
    }

    // insert 1 million pieces, test gas
    function test__MaxPieces() public {
        vm.stopPrank();

        address voter = address(89);

        // Create 10_000 pieces
        _insertPiecesAndVote(10_000);

        //vm roll
        vm.roll(vm.getBlockNumber() + 1);

        // log maxHeap size
        emit log_named_uint("maxHeapSize", maxHeap.size());

        // calculate gas left
        uint256 gasLeft = gasleft();

        //drop top voted piece
        vm.prank(address(revolutionToken));
        cultureIndex.dropTopVotedPiece();

        // calculate gas used
        uint256 gasUsed = gasLeft - gasleft();

        emit log_named_uint("gasUsed", gasUsed);

        //now insert 100_000 pieces and ensure gas used is less than double what it was before

        // Create 1 million pieces
        _insertPiecesAndVote(100_000);

        // roll
        vm.roll(vm.getBlockNumber() + 1);

        // calculate gas left
        gasLeft = gasleft();

        //drop top voted piece
        vm.prank(address(revolutionToken));

        cultureIndex.dropTopVotedPiece();

        // calculate gas used
        uint256 gasUsed100 = gasLeft - gasleft();

        emit log_named_uint("gasUsed100k", gasUsed100);

        //ensure gas used is less than double what it was before
        assertLt(gasUsed100, gasUsed * 2, "gas used should be less than double what it was before");
    }
}
