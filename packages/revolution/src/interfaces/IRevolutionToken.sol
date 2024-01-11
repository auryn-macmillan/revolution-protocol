// SPDX-License-Identifier: GPL-3.0

/// @title Interface for RevolutionToken

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

pragma solidity ^0.8.22;

import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IDescriptorMinimal } from "./IDescriptorMinimal.sol";
import { ICultureIndex } from "./ICultureIndex.sol";
import { IRevolutionBuilder } from "./IRevolutionBuilder.sol";

interface IRevolutionToken is IERC721 {
    ///                                                          ///
    ///                           ERRORS                         ///
    ///                                                          ///

    /// @dev Reverts if the verb ID is invalid (greater than the current verb ID).
    error INVALID_PIECE_ID();

    /// @dev Reverts if the number of creators for an art piece exceeds the maximum allowed.
    error TOO_MANY_CREATORS();

    /// @dev Reverts if the minter is locked.
    error MINTER_LOCKED();

    /// @dev Reverts if the CultureIndex is locked.
    error CULTURE_INDEX_LOCKED();

    /// @dev Reverts if the descriptor is locked.
    error DESCRIPTOR_LOCKED();

    /// @dev Reverts if the sender is not the minter.
    error NOT_MINTER();

    /// @dev Reverts if the caller is not the manager.
    error ONLY_MANAGER_CAN_INITIALIZE();

    /// @dev Reverts if an address is the zero address.
    error ADDRESS_ZERO();

    ///                                                          ///
    ///                           EVENTS                         ///
    ///                                                          ///

    event VerbCreated(uint256 indexed tokenId, ICultureIndex.ArtPieceCondensed artPiece);

    event VerbBurned(uint256 indexed tokenId);

    event MinterUpdated(address minter);

    event MinterLocked();

    event DescriptorUpdated(IDescriptorMinimal descriptor);

    event DescriptorLocked();

    event CultureIndexUpdated(ICultureIndex cultureIndex);

    event CultureIndexLocked();

    ///                                                          ///
    ///                         FUNCTIONS                        ///
    ///                                                          ///

    function mint() external returns (uint256);

    function burn(uint256 tokenId) external;

    function dataURI(uint256 tokenId) external returns (string memory);

    function setMinter(address minter) external;

    function lockMinter() external;

    function setDescriptor(IDescriptorMinimal descriptor) external;

    function lockDescriptor() external;

    function lockCultureIndex() external;

    function getArtPieceById(uint256 tokenId) external view returns (ICultureIndex.ArtPiece memory);

    /// @notice Initializes a DAO's ERC-721 token contract
    /// @param minter The address of the minter
    /// @param initialOwner The address of the initial owner
    /// @param descriptor The address of the token URI descriptor
    /// @param cultureIndex The address of the CultureIndex contract
    /// @param revolutionTokenParams The name, symbol, and contract metadata of the token
    function initialize(
        address minter,
        address initialOwner,
        address descriptor,
        address cultureIndex,
        IRevolutionBuilder.RevolutionTokenParams memory revolutionTokenParams
    ) external;
}
