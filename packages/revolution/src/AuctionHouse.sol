// SPDX-License-Identifier: GPL-3.0

/// @title A Revolution auction house

/*********************************
 * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ *
 * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ *
 * ░░░░░░█████████░░█████████░░░ *
 * ░░░░░░██░░░████░░██░░░████░░░ *
 * ░░██████░░░████████░░░████░░░ *
 * ░░██░░██░░░████░░██░░░████░░░ *
 * ░░██░░██░░░████░░██░░░████░░░ *
 * ░░░░░░█████████░░█████████░░░ *
 * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ *
 * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ *
 *********************************/

// LICENSE
// AuctionHouse.sol is a modified version of Zora's AuctionHouse.sol:
// https://github.com/ourzora/auction-house/blob/54a12ec1a6cf562e49f0a4917990474b11350a2d/contracts/AuctionHouse.sol
//
// AuctionHouse.sol source code Copyright Zora licensed under the GPL-3.0 license.

pragma solidity ^0.8.22;

import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { IAuctionHouse } from "./interfaces/IAuctionHouse.sol";
import { IRevolutionToken } from "./interfaces/IRevolutionToken.sol";
import { IWETH } from "./interfaces/IWETH.sol";
import { IRevolutionPointsEmitter } from "./interfaces/IRevolutionPointsEmitter.sol";
import { ICultureIndex } from "./interfaces/ICultureIndex.sol";
import { IRevolutionBuilder } from "./interfaces/IRevolutionBuilder.sol";
import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

import { UUPS } from "./libs/proxy/UUPS.sol";
import { VersionedContract } from "./version/VersionedContract.sol";

contract AuctionHouse is
    IAuctionHouse,
    VersionedContract,
    UUPS,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    Ownable2StepUpgradeable
{
    // The Revolution ERC721 token contract
    IRevolutionToken public revolutionToken;

    // The RevolutionPoints emitter contract
    IRevolutionPointsEmitter public revolutionPointsEmitter;

    // The address of the WETH contract
    address public WETH;

    // The minimum amount of time left in an auction after a new bid is created
    uint256 public timeBuffer;

    // The minimum price accepted in an auction
    uint256 public reservePrice;

    // The minimum percentage difference between the last bid amount and the current bid
    uint8 public minBidIncrementPercentage;

    // The split of the winning bid that is reserved for the creator of the Art Piece in basis points
    uint256 public creatorRateBps;

    // The all time minimum split of the winning bid that is reserved for the creator of the Art Piece in basis points
    uint256 public minCreatorRateBps;

    // The split of (auction proceeds * creatorRate) that is sent to the creator as ether in basis points
    uint256 public entropyRateBps;

    // The duration of a single auction
    uint256 public duration;

    // The active auction
    IAuctionHouse.Auction public auction;

    ///                                                          ///
    ///                         IMMUTABLES                       ///
    ///                                                          ///

    /// @notice The contract upgrade manager
    IRevolutionBuilder public immutable manager;

    // The minimum gasleft() threshold for creating an auction (required to mint a RevolutionToken)
    uint32 public constant MIN_TOKEN_MINT_GAS_THRESHOLD = 500_000;

    ///                                                          ///
    ///                         CONSTRUCTOR                      ///
    ///                                                          ///

    /// @param _manager The contract upgrade manager address
    constructor(address _manager) payable initializer {
        if (_manager == address(0)) revert ADDRESS_ZERO();
        manager = IRevolutionBuilder(_manager);
    }

    ///                                                          ///
    ///                         INITIALIZER                      ///
    ///                                                          ///

    /**
     * @notice Initialize the auction house and base contracts,
     * populate configuration values, and pause the contract.
     * @dev This function can only be called once.
     * @param _revolutionToken The address of the Revolution ERC721 token contract.
     * @param _revolutionPointsEmitter The address of the ERC-20 points emitter contract.
     * @param _initialOwner The address of the owner.
     * @param _weth The address of the WETH contract
     * @param _auctionParams The auction params for auctions.
     */
    function initialize(
        address _revolutionToken,
        address _revolutionPointsEmitter,
        address _initialOwner,
        address _weth,
        IRevolutionBuilder.AuctionParams calldata _auctionParams
    ) external initializer {
        if (msg.sender != address(manager)) revert NOT_MANAGER();
        if (_weth == address(0)) revert ADDRESS_ZERO();

        __Pausable_init();
        __ReentrancyGuard_init();
        __Ownable_init(_initialOwner);

        _pause();

        if (_auctionParams.creatorRateBps < _auctionParams.minCreatorRateBps) revert CREATOR_RATE_TOO_LOW();

        revolutionToken = IRevolutionToken(_revolutionToken);
        revolutionPointsEmitter = IRevolutionPointsEmitter(_revolutionPointsEmitter);
        timeBuffer = _auctionParams.timeBuffer;
        reservePrice = _auctionParams.reservePrice;
        minBidIncrementPercentage = _auctionParams.minBidIncrementPercentage;
        duration = _auctionParams.duration;
        creatorRateBps = _auctionParams.creatorRateBps;
        entropyRateBps = _auctionParams.entropyRateBps;
        minCreatorRateBps = _auctionParams.minCreatorRateBps;
        WETH = _weth;
    }

    /**
     * @notice Settle the current auction, mint a new Verb, and put it up for auction.
     */
    // Can technically reenter via cross function reentrancies in _createAuction, auction, and pause, but those are only callable by the owner.
    // @wardens if you can find an exploit here go for it - we might be wrong.
    // slither-disable-next-line reentrancy-eth
    function settleCurrentAndCreateNewAuction() external override nonReentrant whenNotPaused {
        _settleAuction();
        _createAuction();
    }

    /**
     * @notice Settle the current auction.
     * @dev This function can only be called when the contract is paused.
     */
    function settleAuction() external override whenPaused nonReentrant {
        _settleAuction();
    }

    /**
     * @notice Create a bid for a Token, with a given amount.
     * @dev This contract only accepts payment in ETH.
     * @param verbId The ID of the Token to bid on.
     * @param bidder The address of the bidder.
     */
    function createBid(uint256 verbId, address bidder) external payable override nonReentrant {
        IAuctionHouse.Auction memory _auction = auction;

        //require bidder is valid address
        if (bidder == address(0)) revert ADDRESS_ZERO();
        if (_auction.verbId != verbId) revert INVALID_VERB_ID();
        if (block.timestamp >= _auction.endTime) revert AUCTION_EXPIRED();
        if (msg.value < reservePrice) revert BELOW_RESERVE_PRICE();
        if (msg.value < _auction.amount + ((_auction.amount * minBidIncrementPercentage) / 100)) revert BID_TOO_LOW();

        address payable lastBidder = _auction.bidder;

        auction.amount = msg.value;
        auction.bidder = payable(bidder);

        // Extend the auction if the bid was received within `timeBuffer` of the auction end time
        bool extended = _auction.endTime - block.timestamp < timeBuffer;
        if (extended) auction.endTime = _auction.endTime = block.timestamp + timeBuffer;

        // Refund the last bidder, if applicable
        if (lastBidder != address(0)) _safeTransferETHWithFallback(lastBidder, _auction.amount);

        emit AuctionBid(_auction.verbId, bidder, msg.sender, msg.value, extended);

        if (extended) emit AuctionExtended(_auction.verbId, _auction.endTime);
    }

    /**
     * @notice Pause the Revolution auction house.
     * @dev This function can only be called by the owner when the
     * contract is unpaused. While no new auctions can be started when paused,
     * anyone can settle an ongoing auction.
     */
    function pause() external override onlyOwner {
        _pause();
    }

    /**
     * @notice Set the split of the winning bid that is reserved for the creator of the Art Piece (token) in basis points.
     * @dev Only callable by the owner.
     * @param _creatorRateBps New creator rate in basis points.
     */
    function setCreatorRateBps(uint256 _creatorRateBps) external onlyOwner {
        if (_creatorRateBps < minCreatorRateBps) revert CREATOR_RATE_TOO_LOW();

        if (_creatorRateBps > 10_000) revert INVALID_BPS();
        creatorRateBps = _creatorRateBps;

        emit CreatorRateBpsUpdated(_creatorRateBps);
    }

    /**
     * @notice Set the minimum split of the winning bid that is reserved for the creator of the Art Piece (token) in basis points.
     * @dev Only callable by the owner.
     * @param _minCreatorRateBps New minimum creator rate in basis points.
     */
    function setMinCreatorRateBps(uint256 _minCreatorRateBps) external onlyOwner {
        if (_minCreatorRateBps > creatorRateBps) revert MIN_CREATOR_RATE_ABOVE_CREATOR_RATE();

        if (_minCreatorRateBps > 10_000) revert INVALID_BPS();

        //ensure new min rate cannot be lower than previous min rate
        if (_minCreatorRateBps <= minCreatorRateBps) revert MIN_CREATOR_RATE_NOT_INCREASED();

        minCreatorRateBps = _minCreatorRateBps;

        emit MinCreatorRateBpsUpdated(_minCreatorRateBps);
    }

    /**
     * @notice Set the split of (auction proceeds * creatorRate) that is sent to the creator as ether in basis points.
     * @dev Only callable by the owner.
     * @param _entropyRateBps New entropy rate in basis points.
     */
    function setEntropyRateBps(uint256 _entropyRateBps) external onlyOwner {
        if (_entropyRateBps > 10_000) revert INVALID_BPS();

        entropyRateBps = _entropyRateBps;
        emit EntropyRateBpsUpdated(_entropyRateBps);
    }

    /**
     * @notice Unpause the Revolution auction house.
     * @dev This function can only be called by the owner when the
     * contract is paused. If required, this function will start a new auction.
     */
    function unpause() external override onlyOwner {
        _unpause();

        if (auction.startTime == 0 || auction.settled) {
            _createAuction();
        }
    }

    /**
     * @notice Set the auction time buffer.
     * @dev Only callable by the owner.
     */
    function setTimeBuffer(uint256 _timeBuffer) external override onlyOwner {
        timeBuffer = _timeBuffer;

        emit AuctionTimeBufferUpdated(_timeBuffer);
    }

    /**
     * @notice Set the auction reserve price.
     * @dev Only callable by the owner.
     */
    function setReservePrice(uint256 _reservePrice) external override onlyOwner {
        reservePrice = _reservePrice;

        emit AuctionReservePriceUpdated(_reservePrice);
    }

    /**
     * @notice Set the auction minimum bid increment percentage.
     * @dev Only callable by the owner.
     */
    function setMinBidIncrementPercentage(uint8 _minBidIncrementPercentage) external override onlyOwner {
        minBidIncrementPercentage = _minBidIncrementPercentage;

        emit AuctionMinBidIncrementPercentageUpdated(_minBidIncrementPercentage);
    }

    /**
     * @notice Create an auction.
     * @dev Store the auction details in the `auction` state variable and emit an AuctionCreated event.
     * If the mint reverts, the minter was updated without pausing this contract first. To remedy this,
     * catch the revert and pause this contract.
     */
    function _createAuction() internal {
        // Check if there's enough gas to safely execute token.mint() and subsequent operations
        if (gasleft() < MIN_TOKEN_MINT_GAS_THRESHOLD) revert INSUFFICIENT_GAS_FOR_AUCTION();

        try revolutionToken.mint() returns (uint256 verbId) {
            uint256 startTime = block.timestamp;
            uint256 endTime = startTime + duration;

            auction = Auction({
                verbId: verbId,
                amount: 0,
                startTime: startTime,
                endTime: endTime,
                bidder: payable(0),
                settled: false
            });

            emit AuctionCreated(verbId, startTime, endTime);
        } catch {
            _pause();
        }
    }

    /**
     * @notice Settle an auction, finalizing the bid and paying out to the owner. Pays out to the creator and the owner based on the creatorRateBps and entropyRateBps.
     * @dev If there are no bids, the Token is burned.
     */
    function _settleAuction() internal {
        IAuctionHouse.Auction memory _auction = auction;

        //slither-disable-next-line incorrect-equality
        if (_auction.startTime == 0) revert AUCTION_NOT_BEGUN();
        if (_auction.settled) revert AUCTION_ALREADY_SETTLED();

        //slither-disable-next-line timestamp
        if (block.timestamp < _auction.endTime) revert AUCTION_NOT_COMPLETED();

        auction.settled = true;

        uint256 creatorTokensEmitted = 0;
        // Check if contract balance is greater than reserve price
        if (_auction.amount < reservePrice) {
            // If contract balance is less than reserve price, refund to the last bidder
            if (_auction.bidder != address(0)) {
                _safeTransferETHWithFallback(_auction.bidder, _auction.amount);
            }

            // And then burn the token
            revolutionToken.burn(_auction.verbId);
        } else {
            //If no one has bid, burn the token
            if (_auction.bidder == address(0))
                revolutionToken.burn(_auction.verbId);
                //If someone has bid, transfer the token to the winning bidder
            else revolutionToken.transferFrom(address(this), _auction.bidder, _auction.verbId);

            if (_auction.amount > 0) {
                // Ether going to owner of the auction
                uint256 auctioneerPayment = (_auction.amount * (10_000 - creatorRateBps)) / 10_000;

                //Total amount of ether going to creator
                uint256 creatorsShare = _auction.amount - auctioneerPayment;

                uint256 numCreators = revolutionToken.getArtPieceById(_auction.verbId).creators.length;
                address deployer = revolutionToken.getArtPieceById(_auction.verbId).sponsor;

                //Build arrays for revolutionPointsEmitter.buyToken
                uint256[] memory vrgdaSplits = new uint256[](numCreators);
                address[] memory vrgdaReceivers = new address[](numCreators);

                //Transfer auction amount to the DAO
                _safeTransferETHWithFallback(owner(), auctioneerPayment);

                uint256 ethPaidToCreators = 0;

                //Transfer creator's share to the creator, for each creator, and build arrays for revolutionPointsEmitter.buyToken
                if (creatorsShare > 0) {
                    //Get the creators of the Verb
                    ICultureIndex.CreatorBps[] memory creators = revolutionToken
                        .getArtPieceById(_auction.verbId)
                        .creators;

                    //Calculate the amount to be paid to the creators
                    uint entropyRateAmount = creatorsShare * entropyRateBps;

                    //If the amount to be spent on governance for creators is less than the minimum purchase amount for points
                    if ((creatorsShare - (entropyRateAmount / 10_000)) <= revolutionPointsEmitter.minPurchaseAmount()) {
                        //Set the amount to the full creators share, so creators are paid fully in ETH
                        entropyRateAmount = creatorsShare * 10_000;
                    }

                    for (uint256 i = 0; i < numCreators; i++) {
                        vrgdaReceivers[i] = creators[i].creator;
                        vrgdaSplits[i] = creators[i].bps;

                        //Calculate paymentAmount for specific creator based on BPS splits - same as multiplying by creatorDirectPayment
                        uint256 paymentAmount = (entropyRateAmount * creators[i].bps) / (10_000 * 10_000);
                        ethPaidToCreators += paymentAmount;

                        //Transfer creator's share to the creator
                        _safeTransferETHWithFallback(creators[i].creator, paymentAmount);
                    }
                }

                //Buy token from RevolutionPointsEmitter for all the creators
                if (creatorsShare > ethPaidToCreators) {
                    creatorTokensEmitted = revolutionPointsEmitter.buyToken{ value: creatorsShare - ethPaidToCreators }(
                        vrgdaReceivers,
                        vrgdaSplits,
                        IRevolutionPointsEmitter.ProtocolRewardAddresses({
                            builder: address(0),
                            purchaseReferral: address(0),
                            deployer: deployer
                        })
                    );
                }
            }
        }

        emit AuctionSettled(_auction.verbId, _auction.bidder, _auction.amount, creatorTokensEmitted);
    }

    /// @notice Transfer ETH/WETH from the contract
    /// @param _to The recipient address
    /// @param _amount The amount transferring
    function _safeTransferETHWithFallback(address _to, uint256 _amount) private {
        // Ensure the contract has enough ETH to transfer
        if (address(this).balance < _amount) revert("Insufficient balance");

        // Used to store if the transfer succeeded
        bool success;

        assembly {
            // Transfer ETH to the recipient
            // Limit the call to 50,000 gas
            success := call(50000, _to, _amount, 0, 0, 0, 0)
        }

        // If the transfer failed:
        if (!success) {
            // Wrap as WETH
            IWETH(WETH).deposit{ value: _amount }();

            // Transfer WETH instead
            bool wethSuccess = IWETH(WETH).transfer(_to, _amount);

            // Ensure successful transfer
            if (!wethSuccess) revert("WETH transfer failed");
        }
    }

    ///                                                          ///
    ///                        AUCTION UPGRADE                   ///
    ///                                                          ///

    /// @notice Ensures the caller is authorized to upgrade the contract and the new implementation is valid
    /// @dev This function is called in `upgradeTo` & `upgradeToAndCall`
    /// @param _newImpl The new implementation address
    function _authorizeUpgrade(address _newImpl) internal view override onlyOwner whenPaused {
        // Ensure the new implementation is registered by the Builder DAO
        if (!manager.isRegisteredUpgrade(_getImplementation(), _newImpl)) revert INVALID_UPGRADE(_newImpl);
    }
}
