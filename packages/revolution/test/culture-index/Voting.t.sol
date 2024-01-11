// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { Test } from "forge-std/Test.sol";
import { CultureIndex } from "../../src/culture-index/CultureIndex.sol";
import { MockERC20 } from "../mock/MockERC20.sol";
import { ICultureIndex } from "../../src/interfaces/ICultureIndex.sol";
import { RevolutionPoints } from "../../src/RevolutionPoints.sol";
import { CultureIndexTestSuite } from "./CultureIndex.t.sol";

/**
 * @title CultureIndexTest
 * @dev Test contract for CultureIndex
 */
contract CultureIndexVotingBasicTest is CultureIndexTestSuite {
    /// @dev Tests the vote weight calculation with ERC721 token
    function testCalculateVoteWeight() public {
        address voter = address(0x1);
        uint256 pointsBalance = 100;
        uint256 erc721Balance = 2; // Number of ERC721 tokens held by the voter

        // Mock the Points and ERC721 token balances
        vm.mockCall(
            address(cultureIndex.votingPower().points()),
            abi.encodeWithSelector(revolutionPoints.getVotes.selector, voter),
            abi.encode(pointsBalance)
        );
        vm.mockCall(
            address(cultureIndex.votingPower().token()),
            abi.encodeWithSelector(cultureIndex.votingPower().getVotes.selector, voter),
            abi.encode(erc721Balance)
        );

        uint256 expectedWeight = pointsBalance + (erc721Balance * cultureIndex.revolutionTokenVoteWeight());
        uint256 actualWeight = cultureIndex.votingPower().getVotesWithWeights(
            voter,
            1,
            cultureIndex.revolutionTokenVoteWeight()
        );
        assertEq(expectedWeight, actualWeight);
    }

    /// @dev Tests voting with ERC721 token
    function testVoteWithRevolutionToken() public {
        address voter = address(0x1);
        uint256 erc721Weight = 3; // Number of ERC721 tokens held by the voter

        // Mock ERC721 token balance
        vm.mockCall(
            address(cultureIndex.votingPower().token()),
            abi.encodeWithSelector(cultureIndex.votingPower().getPastVotes.selector, voter, block.number),
            abi.encode(erc721Weight)
        );

        // Cast vote
        vm.startPrank(voter);
        vm.roll(vm.getBlockNumber() + 1);

        uint pieceId = createDefaultArtPiece();
        cultureIndex.vote(pieceId);
        vm.stopPrank();

        // Check vote is recorded with correct weight
        uint256 expectedWeight = erc721Weight * cultureIndex.revolutionTokenVoteWeight();
        ICultureIndex.Vote memory vote = cultureIndex.getVote(pieceId, voter);
        assertEq(vote.weight, expectedWeight);
    }

    /// @dev Tests impact of vote weights on top-voted piece ranking
    function testVoteWeightImpactOnTopVotedPiece() public {
        address voter1 = address(0x1);
        address voter2 = address(0x2);

        // Voter1 votes for piece1
        vm.stopPrank();
        vm.startPrank(address(revolutionPointsEmitter));
        revolutionPoints.mint(voter1, 100);
        vm.roll(vm.getBlockNumber() + 1); // Roll forward to ensure votes are snapshotted
        uint256 pieceId1 = createDefaultArtPiece();

        vm.startPrank(voter1);
        cultureIndex.vote(pieceId1);
        vm.stopPrank();

        // Voter2 votes for piece2 with higher weight
        vm.startPrank(address(revolutionPointsEmitter));
        revolutionPoints.mint(voter2, 200);
        vm.roll(vm.getBlockNumber() + 2); // Roll forward to ensure votes are snapshotted
        uint256 pieceId2 = createDefaultArtPiece();

        vm.startPrank(voter2);
        cultureIndex.vote(pieceId2);

        // Check top-voted piece
        ICultureIndex.ArtPiece memory topVotedPiece = cultureIndex.getTopVotedPiece();
        assertEq(topVotedPiece.pieceId, pieceId2, "Piece with higher total vote weight should be top voted");
    }

    function testNoDoubleVotingAfterERC721Transfer() public {
        vm.stopPrank();
        address voter = address(0x1);
        address recipient = address(0x2);
        uint256 tokenId = 0;

        // create 2 art pieces
        createDefaultArtPiece();

        // Mint an ERC721 token to the voter
        vm.startPrank(address(auction));
        vm.roll(vm.getBlockNumber() + 1);

        revolutionToken.mint();
        revolutionToken.transferFrom(address(auction), voter, tokenId);
        assertEq(revolutionToken.ownerOf(tokenId), voter);
        vm.roll(vm.getBlockNumber() + 2);

        uint256 artPieceId = createDefaultArtPiece();

        // Voter casts a vote for the art piece
        vm.startPrank(voter);
        cultureIndex.vote(artPieceId);
        vm.stopPrank();

        // Transfer the ERC721 token from voter to recipient
        vm.startPrank(voter);
        revolutionToken.transferFrom(voter, recipient, tokenId);
        vm.stopPrank();
        assertEq(revolutionToken.ownerOf(tokenId), recipient);

        // Attempt to have the original voter cast another vote
        vm.startPrank(voter);
        vm.expectRevert(abi.encodeWithSignature("ALREADY_VOTED()"));
        cultureIndex.vote(artPieceId);
        vm.stopPrank();

        // Attempt to have recipient cast a vote
        vm.startPrank(recipient);
        vm.expectRevert(abi.encodeWithSignature("WEIGHT_TOO_LOW()"));
        cultureIndex.vote(artPieceId);
        vm.stopPrank();
    }

    /// @dev Tests reset of vote weight after transferring all tokens
    function testVoteWeightResetAfterTokenTransfer() public {
        address voter = address(0x1);
        uint256 voteWeight = 100;

        // Set initial token balance and cast vote
        vm.stopPrank();
        vm.startPrank(address(revolutionPointsEmitter));
        revolutionPoints.mint(voter, voteWeight);
        vm.startPrank(voter);
        vm.roll(vm.getBlockNumber() + 1);
        uint256 pieceId = createDefaultArtPiece();

        cultureIndex.vote(pieceId);
        vm.stopPrank();

        vm.startPrank(address(revolutionPointsEmitter));
        revolutionPoints.mint(voter, voteWeight);
        vm.roll(vm.getBlockNumber() + 2);

        vm.startPrank(address(auction));
        revolutionToken.mint(); // Mint an ERC721 token to the owner

        // ensure that the ERC721 token is minted
        assertEq(revolutionToken.balanceOf(address(auction)), 1, "ERC721 token should be minted");
        // ensure cultureindex currentvotes is correct
        assertEq(
            cultureIndex.votingPower().getVotesWithWeights(
                address(auction),
                1,
                cultureIndex.revolutionTokenVoteWeight()
            ),
            cultureIndex.revolutionTokenVoteWeight(),
            "Vote weight for voter should be correct"
        );

        // burn the 721
        revolutionToken.burn(0);

        // ensure that the ERC721 token is burned
        assertEq(revolutionToken.balanceOf(address(auction)), 0, "ERC721 token should be burned");

        // ensure cultureindex currentvotes is correct
        assertEq(
            cultureIndex.votingPower().getVotesWithWeights(
                address(auction),
                1,
                cultureIndex.revolutionTokenVoteWeight()
            ),
            0,
            "Vote weight for auction should be zero"
        );

        // ensure that the points token balance is reflected for voter
        uint256 newWeight = cultureIndex.votingPower().getVotesWithWeights(
            voter,
            1,
            cultureIndex.revolutionTokenVoteWeight()
        );
        assertEq(newWeight, voteWeight * 2, "Vote weight should reset to zero after transferring all tokens");
    }

    /// @dev Tests that voting for an invalid piece ID fails
    function testRejectVoteForInvalidPieceId() public {
        uint256 invalidPieceId = 99999; // Assume this is an invalid ID
        address voter = address(0x1);
        vm.stopPrank();
        vm.startPrank(address(revolutionPointsEmitter));
        revolutionPoints.mint(voter, 100);

        vm.startPrank(voter);
        vm.roll(vm.getBlockNumber() + 1);
        vm.expectRevert(abi.encodeWithSignature("INVALID_PIECE_ID()"));
        cultureIndex.vote(invalidPieceId);
        vm.stopPrank();
    }

    /// @dev Tests vote weight calculation with changing token balances
    function testVoteWeightWithChangingTokenBalances() public {
        uint256 pieceId = createDefaultArtPiece();
        createDefaultArtPiece();
        address voter = address(this);
        uint256 initialPointsWeight = 50;
        vm.roll(vm.getBlockNumber() + 1);

        // Set initial token balances
        vm.stopPrank();
        vm.startPrank(address(revolutionPointsEmitter));
        revolutionPoints.mint(voter, initialPointsWeight);

        vm.startPrank(address(auction));
        revolutionToken.mint();
        //transfer to voter
        revolutionToken.transferFrom(address(auction), voter, 0);

        uint256 initialWeight = cultureIndex.votingPower().getVotesWithWeights(
            voter,
            1,
            cultureIndex.revolutionTokenVoteWeight()
        );
        uint256 expectedInitialWeight = initialPointsWeight + (1 * cultureIndex.revolutionTokenVoteWeight());
        assertEq(initialWeight, expectedInitialWeight);

        // Change token balances
        uint256 updatePointsWeight = 100; // Increased points weight

        vm.startPrank(address(revolutionPointsEmitter));
        revolutionPoints.mint(voter, updatePointsWeight);

        vm.startPrank(address(auction));
        revolutionToken.mint();
        // transfer to voter
        revolutionToken.transferFrom(address(auction), voter, 1);

        uint256 updatedWeight = cultureIndex.votingPower().getVotesWithWeights(
            voter,
            1,
            cultureIndex.revolutionTokenVoteWeight()
        );
        uint256 expectedUpdatedWeight = updatePointsWeight +
            initialPointsWeight +
            (2 * cultureIndex.revolutionTokenVoteWeight());
        assertEq(updatedWeight, expectedUpdatedWeight);

        //burn the first 2 revolution tokens
        revolutionToken.burn(0);
        revolutionToken.burn(1);

        // ensure that the ERC721 token is burned
        assertEq(revolutionToken.balanceOf(address(voter)), 0, "ERC721 token should be burned");

        // ensure cultureindex currentvotes is correct
        assertEq(
            cultureIndex.votingPower().getVotesWithWeights(address(voter), 1, cultureIndex.revolutionTokenVoteWeight()),
            updatePointsWeight + initialPointsWeight,
            "Vote weight should be correct"
        );
    }

    /**
     * @dev Test case to validate voting functionality
     *
     * We create a new art piece and cast a vote for it.
     * Then we validate the recorded vote and total voting weight.
     */
    function testVoting() public {
        // Mint some tokens to the voter
        vm.stopPrank();
        vm.startPrank(address(revolutionPointsEmitter));
        revolutionPoints.mint(address(this), 100);

        vm.roll(vm.getBlockNumber() + 1); // Roll forward to ensure votes are snapshotted

        uint256 newPieceId = createArtPiece(
            "Mona Lisa",
            "A masterpiece",
            ICultureIndex.MediaType.IMAGE,
            "ipfs://legends",
            "",
            "",
            address(0x1),
            10000
        );

        // Cast a vote
        vm.startPrank(address(this));
        cultureIndex.vote(newPieceId);

        // Validate the vote
        ICultureIndex.Vote memory pieceVotes = cultureIndex.getVote(newPieceId, address(this));
        uint256 totalVoteWeight = cultureIndex.totalVoteWeights(newPieceId);

        assertEq(pieceVotes.voterAddress, address(this), "Voter address should match");
        assertEq(pieceVotes.weight, 100, "Voting weight should be 100");
        assertEq(totalVoteWeight, 100, "Total voting weight should be 100");
    }

    function testBatchVotingSuccess() public {
        // Preconditions setup
        uint256[] memory pieceIds = new uint256[](2);

        vm.stopPrank();
        vm.startPrank(address(revolutionPointsEmitter));
        revolutionPoints.mint(address(this), 200);
        vm.roll(vm.getBlockNumber() + 1); // Roll forward to ensure votes are snapshotted

        pieceIds[0] = createDefaultArtPiece();
        pieceIds[1] = createDefaultArtPiece();

        // Perform batch voting
        vm.startPrank(address(this));
        cultureIndex.voteForMany(pieceIds);

        // Assertions
        for (uint256 i = 0; i < pieceIds.length; i++) {
            ICultureIndex.Vote memory vote = cultureIndex.getVote(pieceIds[i], address(this));
            assertEq(vote.voterAddress, address(this), "Voter address should match");
            assertEq(vote.weight, 200, "Vote weight should be correct");
        }
    }

    function testBatchVotingFailsForInvalidPieceIds() public {
        uint256[] memory pieceIds = new uint256[](2);
        pieceIds[0] = 999; // Invalid pieceId
        vm.stopPrank();
        vm.startPrank(address(revolutionPointsEmitter));
        revolutionPoints.mint(address(this), 200);
        vm.roll(vm.getBlockNumber() + 1); // Roll forward to ensure votes are snapshotted
        pieceIds[1] = createDefaultArtPiece(); // Valid pieceId

        // This should revert because one of the pieceIds is invalid
        vm.expectRevert(abi.encodeWithSignature("INVALID_PIECE_ID()"));
        cultureIndex.voteForMany(pieceIds);
    }

    function testBatchVotingFailsIfAlreadyVoted() public {
        vm.stopPrank();
        vm.startPrank(address(revolutionPointsEmitter));
        revolutionPoints.mint(address(this), 100);
        vm.roll(vm.getBlockNumber() + 1); // Roll forward to ensure votes are snapshotted

        vm.startPrank(address(this));
        uint256 pieceId = createDefaultArtPiece();

        cultureIndex.vote(pieceId); // Vote for the pieceId

        uint256[] memory pieceIds = new uint256[](1);
        pieceIds[0] = pieceId;

        // This should revert because the voter has already voted for this pieceId
        vm.expectRevert(abi.encodeWithSignature("ALREADY_VOTED()"));
        cultureIndex.voteForMany(pieceIds);
    }

    function testBatchVotingFailsIfPieceDropped() public {
        vm.stopPrank();
        vm.startPrank(address(revolutionPointsEmitter));
        revolutionPoints.mint(address(this), 100);
        vm.roll(vm.getBlockNumber() + 1); // Roll forward to ensure votes are snapshotted

        uint256 pieceId = createDefaultArtPiece();
        vm.startPrank(address(this));
        //vote for the piece
        cultureIndex.vote(pieceId);

        vm.startPrank(address(revolutionToken));
        vm.roll(vm.getBlockNumber() + 2); // Roll forward to ensure votes are snapshotted

        cultureIndex.dropTopVotedPiece(); // Drop the piece

        uint256[] memory pieceIds = new uint256[](1);
        pieceIds[0] = pieceId;

        // This should revert because the piece has been dropped
        vm.expectRevert(abi.encodeWithSignature("ALREADY_DROPPED()"));
        cultureIndex.voteForMany(pieceIds);
    }

    function testBatchVotingFailsForZeroWeight() public {
        uint256[] memory pieceIds = new uint256[](1);
        pieceIds[0] = createDefaultArtPiece();
        vm.roll(vm.getBlockNumber() + 1); // Roll forward to ensure votes are snapshotted
        // Do not mint any tokens to ensure weight is zero

        // This should revert because the voter weight is zero
        vm.expectRevert(abi.encodeWithSignature("WEIGHT_TOO_LOW()"));
        cultureIndex.voteForMany(pieceIds);
    }

    function testGasUsage() public {
        // Mint enough tokens for voting
        vm.stopPrank();
        vm.startPrank(address(revolutionPointsEmitter));
        revolutionPoints.mint(address(this), 100 * 100); // Mint enough tokens (e.g., 100 tokens per vote)
        vm.roll(vm.getBlockNumber() + 1); // Roll forward to ensure votes are snapshotted

        // Assume createArtPiece() is a function that sets up an art piece and returns its ID
        uint256[] memory pieceIds = new uint256[](100);
        for (uint256 i = 0; i < 100; i++) {
            pieceIds[i] = createDefaultArtPiece(); // Setup each art piece
        }

        vm.startPrank(address(this));
        // Measure gas for individual voting
        uint256 startGasIndividual = gasleft();
        for (uint256 i = 0; i < 100; i++) {
            cultureIndex.vote(pieceIds[i]);
        }
        uint256 gasUsedIndividual = startGasIndividual - gasleft();
        emit log_string("Gas used for individual votes");
        emit log_uint(gasUsedIndividual); // Log gas used for individual votes

        vm.stopPrank();

        setUp();

        vm.stopPrank();
        vm.startPrank(address(revolutionPointsEmitter));
        revolutionPoints.mint(address(this), 100 * 100); // Mint enough tokens (e.g., 100 tokens per vote)
        vm.roll(vm.getBlockNumber() + 2); // Roll forward to ensure votes are snapshotted
        vm.stopPrank();

        // Resetting state for a fair comparison
        // Reset contract state (this would need to be implemented to revert to initial state)
        uint256[] memory batchPieceIds = new uint256[](100);
        for (uint256 i = 0; i < 100; i++) {
            batchPieceIds[i] = createDefaultArtPiece(); // Setup each art piece
        }

        // Measure gas for batch voting
        uint256 startGasBatch = gasleft();

        vm.stopPrank();
        vm.startPrank(address(this));

        cultureIndex.voteForMany(batchPieceIds);
        uint256 gasUsedBatch = startGasBatch - gasleft();
        emit log_string("Gas used for batch votes");
        emit log_uint(gasUsedBatch); // Log gas used for batch votes

        // Log the difference in gas usage
        emit log_string("gas saved");
        emit log_int(int(gasUsedIndividual) - int(gasUsedBatch)); // This will log the saved gas

        //assert that batch voting is cheaper
        assertTrue(gasUsedBatch < gasUsedIndividual, "Batch voting should be cheaper");
    }

    /**
     * @dev Test case to validate the "one vote per address" rule
     *
     * We create a new art piece and cast a vote for it.
     * Then we try to vote again and expect it to fail.
     */
    function testCannotVoteTwice() public {
        // Mint some tokens to the voter
        vm.stopPrank();
        vm.startPrank(address(revolutionPointsEmitter));
        revolutionPoints.mint(address(this), 100);
        vm.roll(vm.getBlockNumber() + 1); // Roll forward to ensure votes are snapshotted

        uint256 newPieceId = createArtPiece(
            "Mona Lisa",
            "A masterpiece",
            ICultureIndex.MediaType.IMAGE,
            "ipfs://legends",
            "",
            "",
            address(0x1),
            10000
        );

        // Cast a vote
        vm.startPrank(address(this));
        cultureIndex.vote(newPieceId);

        // Try to vote again and expect to fail
        vm.expectRevert(abi.encodeWithSignature("ALREADY_VOTED()"));
        cultureIndex.vote(newPieceId);
    }

    /**
     * @dev Test case to validate that an address with no tokens cannot vote
     *
     * We create a new art piece and try to cast a vote without any tokens.
     * We expect the vote to fail.
     */
    function testCannotVoteWithoutTokens() public {
        uint256 newPieceId = createArtPiece(
            "Starry Night",
            "A masterpiece",
            ICultureIndex.MediaType.IMAGE,
            "ipfs://legends",
            "",
            "",
            address(0x1),
            10000
        );

        vm.roll(vm.getBlockNumber() + 1); // Roll forward to ensure votes are snapshotted

        // Try to vote and expect to fail
        vm.expectRevert(abi.encodeWithSignature("WEIGHT_TOO_LOW()"));
        cultureIndex.vote(newPieceId);
    }

    /**
     * @dev Test case to validate that a single address cannot vote twice on multiple pieces
     *
     * We create two new art pieces and cast a vote for each.
     * Then we try to vote again for both and expect both to fail.
     */
    function testCannotVoteOnMultiplePiecesTwice() public {
        // Mint some tokens to the voter
        vm.stopPrank();
        vm.startPrank(address(revolutionPointsEmitter));
        revolutionPoints.mint(address(this), 200);
        vm.roll(vm.getBlockNumber() + 1); // Roll forward to ensure votes are snapshotted

        uint256 firstPieceId = createArtPiece(
            "Mona Lisa",
            "A masterpiece",
            ICultureIndex.MediaType.IMAGE,
            "ipfs://legends",
            "",
            "",
            address(0x1),
            10000
        );

        uint256 secondPieceId = createArtPiece(
            "Starry Night",
            "Another masterpiece",
            ICultureIndex.MediaType.IMAGE,
            "ipfs://starrynight",
            "",
            "",
            address(0x2),
            10000
        );

        // Cast a vote for the first piece

        vm.startPrank(address(this));
        cultureIndex.vote(firstPieceId);

        // Cast a vote for the second piece
        cultureIndex.vote(secondPieceId);

        // Try to vote again for the first piece and expect to fail
        vm.expectRevert(abi.encodeWithSignature("ALREADY_VOTED()"));
        cultureIndex.vote(firstPieceId);

        // Try to vote again for the second piece and expect to fail
        vm.expectRevert(abi.encodeWithSignature("ALREADY_VOTED()"));
        cultureIndex.vote(secondPieceId);
    }

    /**
     * @dev Test case to validate that an address with no tokens cannot vote on multiple pieces
     *
     * We create two new art pieces and try to cast a vote for each without any tokens.
     * We expect both votes to fail.
     */
    function testCannotVoteWithoutTokensMultiplePieces() public {
        uint256 firstPieceId = createArtPiece(
            "Mona Lisa",
            "A masterpiece",
            ICultureIndex.MediaType.IMAGE,
            "ipfs://legends",
            "",
            "",
            address(0x1),
            10000
        );

        uint256 secondPieceId = createArtPiece(
            "Starry Night",
            "Another masterpiece",
            ICultureIndex.MediaType.IMAGE,
            "ipfs://starrynight",
            "",
            "",
            address(0x2),
            10000
        );
        vm.roll(vm.getBlockNumber() + 1); // Roll forward to ensure votes are snapshotted

        // Try to vote for the first piece and expect to fail
        vm.expectRevert(abi.encodeWithSignature("WEIGHT_TOO_LOW()"));
        cultureIndex.vote(firstPieceId);

        // Try to vote for the second piece and expect to fail
        vm.expectRevert(abi.encodeWithSignature("WEIGHT_TOO_LOW()"));
        cultureIndex.vote(secondPieceId);
    }

    function testVoteAfterTransferringTokens() public {
        // Mint tokens and vote
        vm.stopPrank();
        vm.startPrank(address(revolutionPointsEmitter));
        revolutionPoints.mint(address(this), 100);
        vm.roll(vm.getBlockNumber() + 1); // Roll forward to ensure votes are snapshotted

        uint256 newPieceId = createDefaultArtPiece();

        vm.startPrank(address(this));
        cultureIndex.vote(newPieceId);

        // Transfer all tokens to another account
        address anotherAccount = address(0x4);
        vm.expectRevert(abi.encodeWithSignature("TRANSFER_NOT_ALLOWED()"));
        revolutionPoints.transfer(anotherAccount, 100);

        vm.startPrank(anotherAccount);

        // Try to vote again and expect to fail
        vm.expectRevert(abi.encodeWithSignature("WEIGHT_TOO_LOW()"));
        cultureIndex.vote(newPieceId);
    }

    function testInvalidPieceID() public {
        // Mint some tokens to the voter
        vm.stopPrank();
        vm.startPrank(address(revolutionPointsEmitter));
        revolutionPoints.mint(address(this), 100);
        vm.roll(vm.getBlockNumber() + 1); // Roll forward to ensure votes are snapshotted

        vm.startPrank(address(this));
        // Attempt to vote for an invalid piece ID
        vm.expectRevert(abi.encodeWithSignature("INVALID_PIECE_ID()"));
        cultureIndex.vote(9999);
    }

    /**
     * @dev Test case to validate that voting on a dropped piece fails.
     *
     * We create a new art piece, drop it, and then try to cast a vote for it.
     * We expect the vote to fail since the piece has been dropped.
     */
    function testCannotVoteOnDroppedPiece() public {
        vm.stopPrank();
        vm.startPrank(address(revolutionPointsEmitter));
        revolutionPoints.mint(address(this), 100);
        vm.roll(vm.getBlockNumber() + 1); // Roll forward to ensure votes are snapshotted

        uint256 newPieceId = createDefaultArtPiece();

        vm.roll(vm.getBlockNumber() + 2); // Roll forward to ensure votes are snapshotted

        //prank this
        vm.startPrank(address(this));
        cultureIndex.vote(newPieceId);

        // Drop the top-voted piece (which should be the new piece)
        vm.startPrank(address(revolutionToken));
        //vote for the piece
        cultureIndex.dropTopVotedPiece();

        //mint to new address
        vm.startPrank(address(revolutionPointsEmitter));
        revolutionPoints.mint(address(auction), 100);

        //prank auction
        vm.startPrank(address(auction));

        // Try to vote for the dropped piece and expect to fail
        vm.expectRevert(abi.encodeWithSignature("ALREADY_DROPPED()"));
        cultureIndex.vote(newPieceId);
    }

    function testCalculateVoteWeights(uint200 pointsBalance, uint40 erc721Balance) public {
        vm.assume(pointsBalance > 0);
        vm.assume(erc721Balance < 1_000);
        vm.stopPrank();
        vm.startPrank(address(revolutionPointsEmitter));
        revolutionPoints.mint(address(auction), pointsBalance);

        vm.roll(vm.getBlockNumber() + 1);

        vm.startPrank(address(this));

        // Create art pieces and drop them
        for (uint256 i; i < erc721Balance; i++) {
            createDefaultArtPiece();
            vm.roll(vm.getBlockNumber() + (i + 1) * 2);
            vm.startPrank(address(auction));
            cultureIndex.vote(i);
            revolutionToken.mint();
        }

        vm.roll(vm.getBlockNumber() + 3);

        // Calculate expected vote weight
        uint256 expectedVoteWeight = pointsBalance + (erc721Balance * cultureIndex.revolutionTokenVoteWeight());

        // Get the actual vote weight from the contract
        uint256 actualVoteWeight = cultureIndex.votingPower().getVotesWithWeights(
            address(auction),
            1,
            cultureIndex.revolutionTokenVoteWeight()
        );

        // Assert that the actual vote weight matches the expected value
        assertEq(actualVoteWeight, expectedVoteWeight, "Vote weight calculation does not match expected value");
    }

    function testQuorumVotesCalculation(uint200 pointsTotalSupply, uint256 erc721TotalSupply) public {
        vm.assume(pointsTotalSupply > 0);
        vm.assume(erc721TotalSupply < 1_000);
        // Initial settings
        uint256 quorumBPS = cultureIndex.quorumVotesBPS(); // Example quorum BPS (20%)

        // Set the quorum BPS
        cultureIndex._setQuorumVotesBPS(quorumBPS);

        // Set the Points and ERC721 total supplies
        vm.startPrank(address(revolutionPointsEmitter));
        revolutionPoints.mint(address(this), pointsTotalSupply);

        vm.roll(vm.getBlockNumber() + 1);

        //for desired erc721 supply, loop create art pieces and drop
        for (uint256 i = 0; i < erc721TotalSupply; i++) {
            createDefaultArtPiece();
            vm.roll(vm.getBlockNumber() + 1);
            vm.startPrank(address(this));
            cultureIndex.vote(i);

            vm.startPrank(address(auction));
            revolutionToken.mint();

            //transfer to voter
            revolutionToken.transferFrom(address(auction), address(this), i);
        }

        // Calculate expected quorum votes
        uint256 expectedQuorumVotes = (quorumBPS *
            (pointsTotalSupply + erc721TotalSupply * cultureIndex.revolutionTokenVoteWeight())) / 10_000;
        // Get the quorum votes from the contract
        uint256 actualQuorumVotes = cultureIndex.quorumVotes();

        // Assert that the actual quorum votes match the expected value
        assertEq(actualQuorumVotes, expectedQuorumVotes, "Quorum votes calculation does not match expected value");
    }
}
