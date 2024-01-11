// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { AuctionHouseTest } from "./AuctionHouse.t.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ICultureIndex } from "../../src/interfaces/ICultureIndex.sol";
import { IRevolutionToken } from "../../src/interfaces/IRevolutionToken.sol";
import { MockWETH } from "../mock/MockWETH.sol";
import { toDaysWadUnsafe } from "../../src/libs/SignedWadMath.sol";

contract AuctionHouseSettleTest is AuctionHouseTest {
    // Fallback function to allow contract to receive Ether
    receive() external payable {}

    function test__VotesCount(uint8 nDays) public {
        createDefaultArtPiece();

        vm.roll(vm.getBlockNumber() + 1);

        auction.unpause();

        uint256 bidAmount = auction.reservePrice();
        vm.deal(address(11), bidAmount);
        vm.startPrank(address(11));
        auction.createBid{ value: bidAmount }(0, address(11)); // Assuming first auction's verbId is 0
        vm.stopPrank();

        vm.warp(block.timestamp + auction.duration() + nDays); // Fast forward time to end the auction

        createDefaultArtPiece();
        auction.settleCurrentAndCreateNewAuction();
        vm.roll(vm.getBlockNumber() + 1);

        assertEq(revolutionToken.ownerOf(0), address(11), "Verb should be transferred to the highest bidder");
        // cultureIndex currentVotes of highest bidder should be 10
        assertEq(
            cultureIndex.votingPower().getVotesWithWeights(address(11), 1, cultureIndex.revolutionTokenVoteWeight()),
            cultureIndex.revolutionTokenVoteWeight(),
            "Highest bidder should have 10 votes"
        );
    }

    function test__OwnerPayment(uint8 nDays) public {
        createDefaultArtPiece();
        vm.roll(vm.getBlockNumber() + 1); // roll block number to enable voting snapshot

        auction.unpause();

        uint256 bidAmount = auction.reservePrice();
        vm.deal(address(11), bidAmount);
        vm.startPrank(address(11));
        auction.createBid{ value: bidAmount }(0, address(11)); // Assuming first auction's verbId is 0
        vm.stopPrank();

        vm.warp(block.timestamp + auction.duration() + nDays); // Fast forward time to end the auction

        createDefaultArtPiece();
        auction.settleCurrentAndCreateNewAuction();
        vm.roll(vm.getBlockNumber() + 1);

        //calculate fee
        uint256 auctioneerPayment = (bidAmount * (10_000 - auction.creatorRateBps())) / 10_000;

        //amount spent on governance
        uint256 etherToSpendOnGovernanceTotal = (bidAmount * auction.creatorRateBps()) /
            10_000 -
            (bidAmount * (auction.entropyRateBps() * auction.creatorRateBps())) /
            10_000 /
            10_000;

        uint256 feeAmount = revolutionPointsEmitter.computeTotalReward(etherToSpendOnGovernanceTotal);

        uint msgValueRemaining = etherToSpendOnGovernanceTotal - feeAmount;

        uint pointsEmitterValueGrants = (msgValueRemaining * revolutionPointsEmitter.creatorRateBps()) / 10_000;
        uint pointsEmitterValueGrantsDirect = (pointsEmitterValueGrants * revolutionPointsEmitter.entropyRateBps()) /
            10_000;
        uint pointsEmitterValueGrantsGov = pointsEmitterValueGrants - pointsEmitterValueGrantsDirect;

        uint pointsEmitterValueOwner = msgValueRemaining - pointsEmitterValueGrants;

        assertEq(
            address(executor).balance,
            auctioneerPayment + pointsEmitterValueOwner + pointsEmitterValueGrantsGov,
            "Bid amount minus entropy should be transferred to the auction house owner"
        );
    }

    function test__SettlingAuctionWithNoBids(uint8 nDays) public {
        uint256 verbId = createDefaultArtPiece();
        vm.roll(vm.getBlockNumber() + 1); // roll block number to enable voting snapshot

        auction.unpause();

        vm.warp(block.timestamp + auction.duration() + nDays); // Fast forward time to end the auction

        // Assuming revolutionToken.burn is called for auctions with no bids
        vm.expectEmit(true, true, true, true);
        emit IRevolutionToken.VerbBurned(verbId);

        auction.settleCurrentAndCreateNewAuction();
    }

    function test__SettlingAuctionPrematurely() public {
        createDefaultArtPiece();
        auction.unpause();

        vm.expectRevert();
        auction.settleAuction(); // Attempt to settle before the auction ends
    }

    function test__TransferFailureAndFallbackToWETH(uint256 amount) public {
        vm.assume(amount > revolutionPointsEmitter.minPurchaseAmount());
        vm.assume(amount > auction.reservePrice());
        vm.assume(amount < revolutionPointsEmitter.maxPurchaseAmount());

        createDefaultArtPiece();
        vm.roll(vm.getBlockNumber() + 1); // roll block number to enable voting snapshot

        auction.unpause();

        address recipient = address(new ContractThatRejectsEther());

        auction.transferOwnership(recipient);

        vm.startPrank(recipient);
        auction.acceptOwnership();

        vm.startPrank(address(auction));

        vm.deal(address(auction), amount);
        auction.createBid{ value: amount }(0, address(this)); // Assuming first auction's verbId is 0

        // Initially, recipient should have 0 ether and 0 WETH
        assertEq(recipient.balance, 0);
        assertEq(IERC20(address(weth)).balanceOf(recipient), 0);

        //go in future
        vm.warp(block.timestamp + auction.duration() + 1); // Fast forward time to end the auction

        auction.settleCurrentAndCreateNewAuction();

        // Check if the recipient received WETH instead of Ether
        uint256 creatorRate = auction.creatorRateBps();
        assertEq(IERC20(address(weth)).balanceOf(recipient), (amount * (10_000 - creatorRate)) / 10_000);
        assertEq(recipient.balance, 0); // Ether balance should still be 0
        //make sure voting weight on culture index is 721 vote weight for winning bidder
        assertEq(
            cultureIndex.votingPower().getVotesWithWeights(address(this), 1, cultureIndex.revolutionTokenVoteWeight()),
            cultureIndex.revolutionTokenVoteWeight(),
            "Highest bidder should have 10 votes"
        );
    }

    function test__TransferToEOA() public {
        createDefaultArtPiece();
        vm.roll(vm.getBlockNumber() + 1); // roll block number to enable voting snapshot

        auction.unpause();

        address recipient = address(0x123); // Some EOA address
        uint256 amount = 1 ether;

        auction.transferOwnership(recipient);

        vm.startPrank(recipient);
        auction.acceptOwnership();

        vm.startPrank(address(auction));
        vm.deal(address(auction), amount);
        auction.createBid{ value: amount }(0, address(this)); // Assuming first auction's verbId is 0

        // Initially, recipient should have 0 ether
        assertEq(recipient.balance, 0);

        //go in future
        vm.warp(block.timestamp + auction.duration() + 1); // Fast forward time to end the auction

        auction.settleCurrentAndCreateNewAuction();

        // Check if the recipient received Ether
        uint256 creatorRate = auction.creatorRateBps();
        assertEq(recipient.balance, (amount * (10_000 - creatorRate)) / 10_000);
        //make sure voting weight on culture index is 721 vote weight for winning bidder
        assertEq(
            cultureIndex.votingPower().getVotesWithWeights(address(this), 1, cultureIndex.revolutionTokenVoteWeight()),
            cultureIndex.revolutionTokenVoteWeight(),
            "Highest bidder should have 10 votes"
        );
    }

    function test__TransferToContractWithoutReceiveOrFallback(uint256 amount) public {
        vm.assume(amount > revolutionPointsEmitter.minPurchaseAmount());
        vm.assume(amount > auction.reservePrice());
        vm.assume(amount < revolutionPointsEmitter.maxPurchaseAmount());

        createDefaultArtPiece();
        vm.roll(vm.getBlockNumber() + 1); // roll block number to enable voting snapshot

        auction.unpause();

        address recipient = address(new ContractWithoutReceiveOrFallback());

        auction.transferOwnership(recipient);

        vm.startPrank(recipient);
        auction.acceptOwnership();

        vm.startPrank(address(auction));

        vm.deal(address(auction), amount);
        auction.createBid{ value: amount }(0, address(this)); // Assuming first auction's verbId is 0

        // Initially, recipient should have 0 ether and 0 WETH
        assertEq(recipient.balance, 0);
        assertEq(IERC20(address(weth)).balanceOf(recipient), 0);

        //go in future
        vm.warp(block.timestamp + auction.duration() + 1); // Fast forward time to end the auction

        auction.settleCurrentAndCreateNewAuction();

        // Check if the recipient received WETH instead of Ether
        uint256 creatorRate = auction.creatorRateBps();

        assertEq(IERC20(address(weth)).balanceOf(recipient), (amount * (10_000 - creatorRate)) / 10_000);
        assertEq(recipient.balance, 0); // Ether balance should still be 0
        //make sure voting weight on culture index is 721 vote weight for winning bidder
        assertEq(
            cultureIndex.votingPower().getVotesWithWeights(address(this), 1, cultureIndex.revolutionTokenVoteWeight()),
            cultureIndex.revolutionTokenVoteWeight(),
            "Highest bidder should have 10 votes"
        );
    }

    function getTokenQuoteForEtherHelper(uint256 etherAmount, int256 supply) public view returns (int gainedX) {
        // Note: By using toDaysWadUnsafe(block.timestamp - startTime) we are establishing that 1 "unit of time" is 1 day.
        // solhint-disable-next-line not-rely-on-time
        return
            revolutionPointsEmitter.vrgdac().yToX({
                timeSinceStart: toDaysWadUnsafe(block.timestamp - revolutionPointsEmitter.startTime()),
                sold: supply,
                amount: int(etherAmount)
            });
    }

    function getCreatorGovernancePayoutHelper(uint bidAmount) public returns (uint) {
        // Ether going to owner of the auction
        uint auctioneerPayment = (bidAmount * (10_000 - auction.creatorRateBps())) / 10_000;

        //Total amount of ether going to creator
        uint creatorsAuctionShare = bidAmount - auctioneerPayment;
        uint ethPaidToCreators = (creatorsAuctionShare * auction.entropyRateBps()) / (10_000);
        // uint ethPaidToCreators = 0;
        // for (uint256 i = 0; i < numCreators; i++) {
        //     uint256 paymentAmount = (entropyRateAmount * creators[i].bps) / (10_000 * 10_000);
        //     ethPaidToCreators += paymentAmount;
        // }

        //amount to buy creators governance with
        uint creatorPointsEther = (creatorsAuctionShare - ethPaidToCreators);

        uint msgValueRemaining = creatorPointsEther - revolutionPointsEmitter.computeTotalReward(creatorPointsEther);

        uint grantsShare = (msgValueRemaining * revolutionPointsEmitter.creatorRateBps()) / 10_000;
        uint buyersShare = msgValueRemaining - grantsShare;
        uint grantsDirectPayment = (grantsShare * revolutionPointsEmitter.entropyRateBps()) / 10_000;
        uint grantsGovernancePayment = grantsShare - grantsDirectPayment;

        int expectedGrantsGovernanceTokenPayout = revolutionPointsEmitter.getTokenQuoteForEther(
            grantsGovernancePayment
        );

        return uint256(getTokenQuoteForEtherHelper(buyersShare, expectedGrantsGovernanceTokenPayout));
    }

    //assuming dao owns both auction and revolutionPointsEmitter
    function getDAOPayout(uint bidAmount) public returns (uint) {
        // Ether going to owner of the auction
        uint auctioneerPayment = (bidAmount * (10_000 - auction.creatorRateBps())) / 10_000;

        //Total amount of ether going to creator
        uint creatorsAuctionShare = bidAmount - auctioneerPayment;

        uint creatorPointsEther = (creatorsAuctionShare * (10_000 - auction.entropyRateBps())) / 10_000;

        uint msgValueRemaining = creatorPointsEther - revolutionPointsEmitter.computeTotalReward(creatorPointsEther);

        uint grantsShare = (msgValueRemaining * revolutionPointsEmitter.creatorRateBps()) / 10_000;
        uint buyersShare = msgValueRemaining - grantsShare;
        uint grantsDirectPayment = (grantsShare * revolutionPointsEmitter.entropyRateBps()) / 10_000;
        uint grantsGovernancePayment = grantsShare - grantsDirectPayment;

        return auctioneerPayment + grantsGovernancePayment + buyersShare;
    }

    function getGrantsDirectPayment(uint bidAmount) public returns (uint) {
        uint creatorsAuctionShare = (bidAmount * auction.creatorRateBps()) / 10_000;
        uint creatorsGovernancePayment = (creatorsAuctionShare * (10_000 - auction.entropyRateBps())) / 10_000;

        uint msgValueRemaining = creatorsGovernancePayment -
            revolutionPointsEmitter.computeTotalReward(creatorsGovernancePayment);

        uint grantsShare = (msgValueRemaining * revolutionPointsEmitter.creatorRateBps()) / 10_000;
        uint buyersShare = msgValueRemaining - grantsShare;
        return (grantsShare * revolutionPointsEmitter.entropyRateBps()) / 10_000;
    }

    function test__SettlingAuctionWithMultipleCreators(uint8 nCreators) public {
        vm.assume(nCreators > 0);
        vm.assume(nCreators < cultureIndex.MAX_NUM_CREATORS());

        address[] memory creatorAddresses = new address[](nCreators);
        uint256[] memory creatorBps = new uint256[](nCreators);
        uint256 totalBps = 0;

        // Assume n creators with equal share
        for (uint256 i = 0; i < nCreators; i++) {
            creatorAddresses[i] = address(uint160(i + 1)); // Example creator addresses
            if (i == nCreators - 1) {
                creatorBps[i] = 10_000 - totalBps;
            } else {
                creatorBps[i] = (10_000) / (nCreators - 1);
            }

            totalBps += creatorBps[i];
        }

        createArtPieceMultiCreator(
            "Multi Creator Art",
            "An art piece with multiple creators",
            ICultureIndex.MediaType.IMAGE,
            "ipfs://multi-creator-art",
            "",
            "",
            creatorAddresses,
            creatorBps
        );

        vm.roll(vm.getBlockNumber() + 1); // roll block number to enable voting snapshot

        auction.unpause();

        vm.deal(address(21_000), auction.reservePrice() + 1 ether);
        vm.startPrank(address(21_000));
        auction.createBid{ value: auction.reservePrice() }(0, address(21_000));
        vm.stopPrank();

        vm.warp(block.timestamp + auction.duration() + 1); // Fast forward time to end the auction

        // Track balances before auction settlement
        uint256[] memory balancesBefore = new uint256[](creatorAddresses.length);
        uint256[] memory mockWETHBalancesBefore = new uint256[](creatorAddresses.length);
        uint256[] memory governanceTokenBalancesBefore = new uint256[](creatorAddresses.length);
        for (uint256 i = 0; i < creatorAddresses.length; i++) {
            balancesBefore[i] = address(creatorAddresses[i]).balance;
            governanceTokenBalancesBefore[i] = revolutionPoints.balanceOf(creatorAddresses[i]);
            mockWETHBalancesBefore[i] = MockWETH(payable(weth)).balanceOf(creatorAddresses[i]);
        }

        uint expectedGovernanceTokenPayout = getCreatorGovernancePayoutHelper(auction.reservePrice());

        auction.settleCurrentAndCreateNewAuction();

        //assert auctionHouse balance is 0
        assertEq(address(auction).balance, 0);

        // Verify each creator's payout
        for (uint256 i = 0; i < creatorAddresses.length; i++) {
            uint256 expectedEtherShare = uint256(
                ((auction.reservePrice()) * creatorBps[i] * auction.creatorRateBps()) / 10_000 / 10_000
            );

            //either the creator gets ETH or WETH
            assertEq(
                address(creatorAddresses[i]).balance - balancesBefore[i] > 0
                    ? address(creatorAddresses[i]).balance - balancesBefore[i]
                    : MockWETH(payable(weth)).balanceOf(creatorAddresses[i]) - mockWETHBalancesBefore[i],
                (expectedEtherShare * auction.entropyRateBps()) / 10_000,
                "Incorrect ETH payout for creator"
            );

            assertEq(
                revolutionPoints.balanceOf(creatorAddresses[i]) - governanceTokenBalancesBefore[i],
                uint256((expectedGovernanceTokenPayout * creatorBps[i]) / 10_000),
                "Incorrect governance token payout for creator"
            );
        }

        // Verify ownership of the verb
        assertEq(revolutionToken.ownerOf(0), address(21_000), "Verb should be transferred to the highest bidder");
        // Verify voting weight on culture index is 721 vote weight for winning bidder
        assertEq(
            cultureIndex.votingPower().getVotesWithWeights(
                address(21_000),
                1,
                cultureIndex.revolutionTokenVoteWeight()
            ),
            cultureIndex.revolutionTokenVoteWeight(),
            "Highest bidder should have 10 votes"
        );
    }

    function test__SettlingAuctionWithWinningBidAndCreatorPayout(uint256 bidAmount) public {
        vm.assume(bidAmount > revolutionPointsEmitter.minPurchaseAmount());
        vm.assume(bidAmount > auction.reservePrice());
        vm.assume(bidAmount < revolutionPointsEmitter.maxPurchaseAmount());

        uint256 verbId = createArtPiece(
            "Art Piece",
            "A new art piece",
            ICultureIndex.MediaType.IMAGE,
            "ipfs://image",
            "",
            "",
            address(0x1),
            10_000
        );
        vm.roll(vm.getBlockNumber() + 1); // roll block number to enable voting snapshot

        auction.unpause();

        vm.deal(address(21_000), bidAmount);
        vm.startPrank(address(21_000));
        auction.createBid{ value: bidAmount }(verbId, address(21_000));
        vm.stopPrank();

        vm.warp(block.timestamp + auction.duration() + 1); // Fast forward time to end the auction

        // Track ETH balances
        uint256 balanceBeforeCreator = address(0x1).balance;
        uint256 balanceBeforeOwner = address(dao).balance;

        uint256 expectedGovernanceTokens = getCreatorGovernancePayoutHelper(bidAmount);

        //create default art piece and roll
        createDefaultArtPiece();
        vm.roll(vm.getBlockNumber() + 1);

        auction.settleCurrentAndCreateNewAuction();

        // Ether going to owner of the auction
        uint256 auctioneerPayment = (bidAmount * (10_000 - auction.creatorRateBps())) / 10_000;

        //Total amount of ether going to creator
        uint256 creatorsShare = bidAmount - auctioneerPayment;

        uint creatorsDirectPayment = (creatorsShare * (auction.entropyRateBps())) / 10_000;

        uint creatorsGovernancePayment = creatorsShare - creatorsDirectPayment;

        // Checking if the creator received their share
        assertEq(
            address(0x1).balance - balanceBeforeCreator,
            creatorsDirectPayment,
            "Creator did not receive the correct amount of ETH"
        );

        uint expectedGrantsDirectPayout = getGrantsDirectPayment(bidAmount);

        assertApproxEqAbs(
            address(revolutionPointsEmitter.creatorsAddress()).balance,
            expectedGrantsDirectPayout,
            // "Grants address did not receive the correct amount of ETH"
            10
        );

        assertApproxEqAbs(
            address(executor).balance - balanceBeforeOwner,
            getDAOPayout(bidAmount),
            10
            // "Owner did not receive the correct amount of ETH"
        );

        assertEq(revolutionToken.ownerOf(verbId), address(21_000), "Verb should be transferred to the highest bidder");
        // Checking voting weight on culture index is 721 vote weight for winning bidder
        assertEq(
            cultureIndex.votingPower().getVotesWithWeights(
                address(21_000),
                1,
                cultureIndex.revolutionTokenVoteWeight()
            ),
            cultureIndex.revolutionTokenVoteWeight(),
            "Highest bidder should have 10 votes"
        );

        assertEq(
            revolutionPoints.balanceOf(address(0x1)),
            expectedGovernanceTokens,
            "Creator did not receive the correct amount of governance tokens"
        );
    }

    function test__EntropyPecentCannotLeadToDos() public {
        //set entropy to 9999
        auction.setEntropyRateBps(9999);
        //set reserve price to 0.005 ether
        uint bidAmount = 0.005 ether;
        auction.setReservePrice(bidAmount);

        uint256 verbId = createDefaultArtPiece();
        vm.roll(vm.getBlockNumber() + 1); // roll block number to enable voting snapshot

        uint256 balance = 1 ether;
        address alice = vm.addr(uint256(1001));
        vm.deal(alice, balance);

        auction.unpause();
        vm.stopPrank();

        vm.prank(alice);
        auction.createBid{ value: bidAmount }(verbId, alice);

        (, , , uint256 endTime, , ) = auction.auction();
        vm.warp(endTime + 1);

        auction.settleCurrentAndCreateNewAuction();

        //ensure creator got no governance, but got ETH
        assertEq(revolutionPoints.balanceOf(address(0x1)), 0);

        // Ether going to owner of the auction
        uint256 auctioneerPayment = (bidAmount * (10_000 - auction.creatorRateBps())) / 10_000;

        //Total amount of ether going to creator
        uint256 creatorsShare = bidAmount - auctioneerPayment;

        assertEq(address(0x1).balance, creatorsShare);
    }

    function test__SettleAuctionZeroEntropyRate() public {
        // set entropy rate to 0
        auction.setEntropyRateBps(0);

        createDefaultArtPiece();
        vm.roll(vm.getBlockNumber() + 1); // roll block number to enable voting snapshot

        auction.unpause();

        address recipient = address(0x123); // Some EOA address
        uint256 amount = 1 ether;

        vm.startPrank(address(auction));
        vm.deal(address(auction), amount);
        auction.createBid{ value: amount }(0, address(this)); // Assuming first auction's verbId is 0
        //go in future
        vm.warp(block.timestamp + auction.duration() + 1); // Fast forward time to end the auction

        auction.settleCurrentAndCreateNewAuction();
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
