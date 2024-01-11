// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { IRevolutionBuilder } from "./IRevolutionBuilder.sol";
import { IRewardSplits } from "@cobuild/protocol-rewards/src/abstract/RewardSplits.sol";

interface IRevolutionPointsEmitter is IRewardSplits {
    ///                                                          ///
    ///                           ERRORS                         ///
    ///                                                          ///

    /// @dev Reverts if the function caller is not the manager.
    error NOT_MANAGER();

    /// @dev Reverts if address 0 is passed but not allowed
    error ADDRESS_ZERO();

    /// @dev Reverts if invalid BPS is passed
    error INVALID_BPS();

    /// @dev Reverts if BPS does not add up to 10_000
    error INVALID_BPS_SUM();

    /// @dev Reverts if payment amount is 0
    error INVALID_PAYMENT();

    /// @dev Reverts if amount is 0
    error INVALID_AMOUNT();

    /// @dev Reverts if there is an array length mismatch
    error PARALLEL_ARRAYS_REQUIRED();

    /// @dev Reverts if the buyToken sender is the owner or creatorsAddress
    error FUNDS_RECIPIENT_CANNOT_BUY_TOKENS();

    /// @dev Reverts if insufficient balance to transfer
    error INSUFFICIENT_BALANCE();

    /// @dev Reverts if the WETH transfer fails
    error WETH_TRANSFER_FAILED();

    struct ProtocolRewardAddresses {
        address builder;
        address purchaseReferral;
        address deployer;
    }

    struct BuyTokenPaymentShares {
        uint256 buyersShare;
        uint256 creatorsDirectPayment;
        uint256 creatorsGovernancePayment;
    }

    function buyToken(
        address[] calldata addresses,
        uint[] calldata bps,
        ProtocolRewardAddresses calldata protocolRewardsRecipients
    ) external payable returns (uint);

    function WETH() external view returns (address);

    function totalSupply() external view returns (uint);

    function balanceOf(address owner) external view returns (uint);

    function setCreatorRateBps(uint256 creatorRateBps) external;

    function setEntropyRateBps(uint256 entropyRateBps) external;

    function getTokenQuoteForPayment(uint256 paymentAmount) external returns (int);

    function setCreatorsAddress(address creators) external;

    function pause() external;

    function unpause() external;

    event CreatorsAddressUpdated(address creators);

    event CreatorRateBpsUpdated(uint256 rateBps);

    event EntropyRateBpsUpdated(uint256 rateBps);

    event PurchaseFinalized(
        address indexed buyer,
        uint256 payment,
        uint256 ownerAmount,
        uint256 protocolRewardsAmount,
        uint256 buyerTokensEmitted,
        uint256 creatorTokensEmitted,
        uint256 creatorDirectPayment
    );

    /**
     * @notice Initialize the points emitter
     * @param initialOwner The initial owner of the points emitter
     * @param weth The address of the WETH contract.
     * @param revolutionPoints The ERC-20 token contract address
     * @param vrgdac The VRGDA contract address
     * @param creatorsAddress The address of the creators
     * @param creatorParams The creator and entropy rate parameters
     */
    function initialize(
        address initialOwner,
        address weth,
        address revolutionPoints,
        address vrgdac,
        address creatorsAddress,
        IRevolutionBuilder.PointsEmitterCreatorParams calldata creatorParams
    ) external;
}
