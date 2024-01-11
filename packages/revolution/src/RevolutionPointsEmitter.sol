// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { PointsEmitterRewards } from "@cobuild/protocol-rewards/src/abstract/PointsEmitter/PointsEmitterRewards.sol";
import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import { IWETH } from "./interfaces/IWETH.sol";
import { VRGDAC } from "./libs/VRGDAC.sol";
import { toDaysWadUnsafe } from "./libs/SignedWadMath.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { RevolutionPoints } from "./RevolutionPoints.sol";
import { IRevolutionPointsEmitter } from "./interfaces/IRevolutionPointsEmitter.sol";

import { IRevolutionBuilder } from "./interfaces/IRevolutionBuilder.sol";

contract RevolutionPointsEmitter is
    IRevolutionPointsEmitter,
    ReentrancyGuardUpgradeable,
    PointsEmitterRewards,
    Ownable2StepUpgradeable,
    PausableUpgradeable
{
    // The address of the WETH contract
    address public WETH;

    // The token that is being minted.
    RevolutionPoints public token;

    // The VRGDA contract
    VRGDAC public vrgdac;

    // solhint-disable-next-line not-rely-on-time
    uint256 public startTime;

    // The split of the purchase that is reserved for the creator of the Verb in basis points
    uint256 public creatorRateBps;

    // The split of (purchase proceeds * creatorRate) that is sent to the creator as ether in basis points
    uint256 public entropyRateBps;

    // The account or contract to pay the creator reward to
    address public creatorsAddress;

    ///                                                          ///
    ///                         IMMUTABLES                       ///
    ///                                                          ///

    /// @notice The contract upgrade manager
    IRevolutionBuilder private immutable manager;

    ///                                                          ///
    ///                         CONSTRUCTOR                      ///
    ///                                                          ///

    /// @param _manager The contract upgrade manager address
    /// @param _protocolRewards The protocol rewards contract address
    /// @param _protocolFeeRecipient The protocol fee recipient address
    constructor(
        address _manager,
        address _protocolRewards,
        address _protocolFeeRecipient
    ) payable PointsEmitterRewards(_protocolRewards, _protocolFeeRecipient) initializer {
        if (_manager == address(0)) revert ADDRESS_ZERO();
        if (_protocolRewards == address(0)) revert ADDRESS_ZERO();
        if (_protocolFeeRecipient == address(0)) revert ADDRESS_ZERO();

        manager = IRevolutionBuilder(_manager);
    }

    ///                                                          ///
    ///                         INITIALIZER                      ///
    ///                                                          ///

    /**
     * @notice Initialize the points emitter
     * @param _initialOwner The initial owner of the points emitter
     * @param _weth The address of the WETH contract
     * @param _revolutionPoints The ERC-20 token contract address
     * @param _vrgdac The VRGDA contract address
     * @param _creatorsAddress The address to pay the creator reward to
     */
    function initialize(
        address _initialOwner,
        address _weth,
        address _revolutionPoints,
        address _vrgdac,
        address _creatorsAddress,
        IRevolutionBuilder.PointsEmitterCreatorParams calldata _creatorParams
    ) external initializer {
        if (msg.sender != address(manager)) revert NOT_MANAGER();
        if (_initialOwner == address(0)) revert ADDRESS_ZERO();
        if (_revolutionPoints == address(0)) revert ADDRESS_ZERO();
        if (_vrgdac == address(0)) revert ADDRESS_ZERO();
        if (_creatorsAddress == address(0)) revert ADDRESS_ZERO();
        if (_weth == address(0)) revert ADDRESS_ZERO();

        if (_creatorParams.creatorRateBps > 10_000) revert INVALID_BPS();
        if (_creatorParams.entropyRateBps > 10_000) revert INVALID_BPS();

        __Pausable_init();
        __ReentrancyGuard_init();

        // Set up ownable
        __Ownable_init(_initialOwner);

        creatorsAddress = _creatorsAddress;
        vrgdac = VRGDAC(_vrgdac);
        token = RevolutionPoints(_revolutionPoints);
        creatorRateBps = _creatorParams.creatorRateBps;
        entropyRateBps = _creatorParams.entropyRateBps;
        WETH = _weth;

        // If we are upgrading, don't reset the start time
        if (startTime == 0) startTime = block.timestamp;
    }

    function _mint(address _to, uint256 _amount) private {
        token.mint(_to, _amount);
    }

    function totalSupply() public view returns (uint) {
        // returns total supply issued so far
        return token.totalSupply();
    }

    function decimals() public view returns (uint8) {
        // returns decimals
        return token.decimals();
    }

    function balanceOf(address _owner) public view returns (uint) {
        // returns balance of address
        return token.balanceOf(_owner);
    }

    /**
     * @notice Pause the contract.
     * @dev This function can only be called by the owner when the
     * contract is unpaused.
     */
    function pause() external override onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause the points emitter.
     * @dev This function can only be called by the owner when the
     * contract is paused.
     */
    function unpause() external override onlyOwner {
        _unpause();
    }

    /**
     * @notice A function to calculate the shares of the purchase that go to the buyer's governance purchase, and the creators
     * @param msgValueRemaining The amount of ether left after protocol rewards are taken out
     * @return buyTokenPaymentShares A struct containing the shares of the purchase that go to the buyer's governance purchase, and the creators
     */
    function _calculateBuyTokenPaymentShares(
        uint256 msgValueRemaining
    ) internal view returns (BuyTokenPaymentShares memory buyTokenPaymentShares) {
        // Calculate share of purchase amount reserved for buyers
        buyTokenPaymentShares.buyersShare = msgValueRemaining - ((msgValueRemaining * creatorRateBps) / 10_000);

        // Calculate ether directly sent to creators
        buyTokenPaymentShares.creatorsDirectPayment =
            (msgValueRemaining * creatorRateBps * entropyRateBps) /
            10_000 /
            10_000;

        // Calculate ether spent on creators governance tokens
        buyTokenPaymentShares.creatorsGovernancePayment =
            ((msgValueRemaining * creatorRateBps) / 10_000) -
            buyTokenPaymentShares.creatorsDirectPayment;
    }

    /**
     * @notice A payable function that allows a user to buy tokens for a list of addresses and a list of basis points to split the token purchase between.
     * @param addresses The addresses to send purchased tokens to.
     * @param basisPointSplits The basis points of the purchase to send to each address.
     * @param protocolRewardsRecipients The addresses to pay the builder, purchaseRefferal, and deployer rewards to
     * @return tokensSoldWad The amount of tokens sold in wad units.
     */
    function buyToken(
        address[] calldata addresses,
        uint[] calldata basisPointSplits,
        ProtocolRewardAddresses calldata protocolRewardsRecipients
    ) public payable nonReentrant whenNotPaused returns (uint256 tokensSoldWad) {
        // Prevent owner and creatorsAddress from buying tokens directly, given they are recipient(s) of the funds
        if (msg.sender == owner() || msg.sender == creatorsAddress) revert FUNDS_RECIPIENT_CANNOT_BUY_TOKENS();

        // Transaction must send ether to buyTokens
        if (msg.value == 0) revert INVALID_PAYMENT();

        // Ensure the same number of addresses and bps
        if (addresses.length != basisPointSplits.length) revert PARALLEL_ARRAYS_REQUIRED();

        // Calculate value left after sharing protocol rewards
        uint256 msgValueRemaining = _handleRewardsAndGetValueToSend(
            msg.value,
            protocolRewardsRecipients.builder,
            protocolRewardsRecipients.purchaseReferral,
            protocolRewardsRecipients.deployer
        );

        BuyTokenPaymentShares memory buyTokenPaymentShares = _calculateBuyTokenPaymentShares(msgValueRemaining);

        // Calculate tokens to emit to creators
        int totalTokensForCreators = buyTokenPaymentShares.creatorsGovernancePayment > 0
            ? getTokenQuoteForEther(buyTokenPaymentShares.creatorsGovernancePayment)
            : int(0);

        // Deposit owner's funds, and eth used to buy creators gov. tokens to owner's account
        _safeTransferETHWithFallback(
            owner(),
            buyTokenPaymentShares.buyersShare + buyTokenPaymentShares.creatorsGovernancePayment
        );

        // Transfer ETH to creators
        if (buyTokenPaymentShares.creatorsDirectPayment > 0) {
            _safeTransferETHWithFallback(creatorsAddress, buyTokenPaymentShares.creatorsDirectPayment);
        }

        // Mint tokens to creators
        if (totalTokensForCreators > 0) {
            _mint(creatorsAddress, uint256(totalTokensForCreators));
        }

        // Stores total bps, ensure it is 10_000 later
        uint256 bpsSum = 0;
        uint256 addressesLength = addresses.length;

        // Tokens to emit to buyers - ENSURE we do this after minting to creators, so that the total supply is correct
        int totalTokensForBuyers = buyTokenPaymentShares.buyersShare > 0
            ? getTokenQuoteForEther(buyTokenPaymentShares.buyersShare)
            : int(0);

        //Mint tokens to buyers
        for (uint256 i = 0; i < addressesLength; i++) {
            if (totalTokensForBuyers > 0) {
                // transfer tokens to address
                _mint(addresses[i], uint256((totalTokensForBuyers * int(basisPointSplits[i])) / 10_000));
            }
            bpsSum = bpsSum + basisPointSplits[i];
        }

        if (bpsSum != 10_000) revert INVALID_BPS_SUM();

        emit PurchaseFinalized(
            msg.sender,
            msg.value,
            buyTokenPaymentShares.buyersShare + buyTokenPaymentShares.creatorsGovernancePayment,
            msg.value - msgValueRemaining,
            uint256(totalTokensForBuyers),
            uint256(totalTokensForCreators),
            buyTokenPaymentShares.creatorsDirectPayment
        );

        return uint256(totalTokensForBuyers);
    }

    /**
     * @notice Returns the amount of wei that would be spent to buy an amount of tokens. Does not take into account the protocol rewards.
     * @param amount the amount of tokens to buy.
     * @return spentY The cost in wei of the token purchase.
     */
    function buyTokenQuote(uint256 amount) public view returns (int spentY) {
        if (amount == 0) revert INVALID_AMOUNT();
        // Note: By using toDaysWadUnsafe(block.timestamp - startTime) we are establishing that 1 "unit of time" is 1 day.
        // solhint-disable-next-line not-rely-on-time
        return
            vrgdac.xToY({
                timeSinceStart: toDaysWadUnsafe(block.timestamp - startTime),
                sold: int(token.totalSupply()),
                amount: int(amount)
            });
    }

    /**
     * @notice Returns the amount of tokens that would be emitted for an amount of wei. Does not take into account the protocol rewards.
     * @param etherAmount the payment amount in wei.
     * @return gainedX The amount of tokens that would be emitted for the payment amount.
     */
    function getTokenQuoteForEther(uint256 etherAmount) public view returns (int gainedX) {
        if (etherAmount == 0) revert INVALID_PAYMENT();
        // Note: By using toDaysWadUnsafe(block.timestamp - startTime) we are establishing that 1 "unit of time" is 1 day.
        // solhint-disable-next-line not-rely-on-time
        return
            vrgdac.yToX({
                timeSinceStart: toDaysWadUnsafe(block.timestamp - startTime),
                sold: int(token.totalSupply()),
                amount: int(etherAmount)
            });
    }

    /**
     * @notice Returns the amount of tokens that would be emitted to a buyer for the payment amount, taking into account the protocol rewards and creator rate.
     * @param paymentAmount the payment amount in wei.
     * @return gainedX The amount of tokens that would be emitted for the payment amount.
     */
    function getTokenQuoteForPayment(uint256 paymentAmount) external view returns (int gainedX) {
        if (paymentAmount == 0) revert INVALID_PAYMENT();
        // Note: By using toDaysWadUnsafe(block.timestamp - startTime) we are establishing that 1 "unit of time" is 1 day.
        // solhint-disable-next-line not-rely-on-time
        return
            vrgdac.yToX({
                timeSinceStart: toDaysWadUnsafe(block.timestamp - startTime),
                sold: int(token.totalSupply()),
                amount: int(((paymentAmount - computeTotalReward(paymentAmount)) * (10_000 - creatorRateBps)) / 10_000)
            });
    }

    /**
     * @notice Set the split of (purchase * creatorRate) that is sent to the creator as ether in basis points.
     * @dev Only callable by the owner.
     * @param _entropyRateBps New entropy rate in basis points.
     */
    function setEntropyRateBps(uint256 _entropyRateBps) external onlyOwner {
        if (_entropyRateBps > 10_000) revert INVALID_BPS();

        emit EntropyRateBpsUpdated(entropyRateBps = _entropyRateBps);
    }

    /**
     * @notice Set the split of the payment that is reserved for creators in basis points.
     * @dev Only callable by the owner.
     * @param _creatorRateBps New creator rate in basis points.
     */
    function setCreatorRateBps(uint256 _creatorRateBps) external onlyOwner {
        if (_creatorRateBps > 10_000) revert INVALID_BPS();

        emit CreatorRateBpsUpdated(creatorRateBps = _creatorRateBps);
    }

    /**
     * @notice Set the creators address to pay the creatorRate to. Can be a contract.
     * @dev Only callable by the owner.
     */
    function setCreatorsAddress(address _creatorsAddress) external override onlyOwner nonReentrant {
        if (_creatorsAddress == address(0)) revert ADDRESS_ZERO();

        emit CreatorsAddressUpdated(creatorsAddress = _creatorsAddress);
    }

    /**
    @notice Transfer ETH/WETH from the contract
    @param _to The recipient address
    @param _amount The amount transferring
    */
    // Assumption + reason for ignoring: Since this function is called in the buyToken public function, but buyToken sends ETH to only owner and creatorsAddress, this function is safe
    // slither-disable-next-line arbitrary-send-eth
    function _safeTransferETHWithFallback(address _to, uint256 _amount) private {
        // Ensure the contract has enough ETH to transfer
        if (address(this).balance < _amount) revert INSUFFICIENT_BALANCE();

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
            if (!wethSuccess) revert WETH_TRANSFER_FAILED();
        }
    }
}
