// SPDX-License-Identifier: GPL-3.0

/// @title The Revolution ERC-721 token

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

import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import { UUPS } from "./libs/proxy/UUPS.sol";
import { VersionedContract } from "./version/VersionedContract.sol";

import { ERC721CheckpointableUpgradeable } from "./base/ERC721CheckpointableUpgradeable.sol";
import { IDescriptorMinimal } from "./interfaces/IDescriptorMinimal.sol";
import { ICultureIndex } from "./interfaces/ICultureIndex.sol";
import { IRevolutionToken } from "./interfaces/IRevolutionToken.sol";
import { IRevolutionBuilder } from "./interfaces/IRevolutionBuilder.sol";

contract RevolutionToken is
    IRevolutionToken,
    VersionedContract,
    UUPS,
    Ownable2StepUpgradeable,
    ReentrancyGuardUpgradeable,
    ERC721CheckpointableUpgradeable
{
    // An address who has permissions to mint Revolution Tokens
    address public minter;

    // The Revolution Token URI descriptor
    IDescriptorMinimal public descriptor;

    // The CultureIndex contract
    ICultureIndex public cultureIndex;

    // Whether the minter can be updated
    bool public isMinterLocked;

    // Whether the CultureIndex can be updated
    bool public isCultureIndexLocked;

    // Whether the descriptor can be updated
    bool public isDescriptorLocked;

    // The internal verb ID tracker
    uint256 private _currentVerbId;

    // IPFS content hash of contract-level metadata
    string private _contractURIHash;

    // The CultureIndex art pieces mapping (verbId => artPiece ID)
    mapping(uint256 => uint256) public artPieces;

    ///                                                          ///
    ///                          MODIFIERS                       ///
    ///                                                          ///

    /**
     * @notice Require that the minter has not been locked.
     */
    modifier whenMinterNotLocked() {
        if (isMinterLocked) revert MINTER_LOCKED();
        _;
    }

    /**
     * @notice Require that the CultureIndex has not been locked.
     */
    modifier whenCultureIndexNotLocked() {
        if (isCultureIndexLocked) revert CULTURE_INDEX_LOCKED();
        _;
    }

    /**
     * @notice Require that the descriptor has not been locked.
     */
    modifier whenDescriptorNotLocked() {
        if (isDescriptorLocked) revert DESCRIPTOR_LOCKED();
        _;
    }

    /**
     * @notice Require that the sender is the minter.
     */
    modifier onlyMinter() {
        if (msg.sender != minter) revert NOT_MINTER();
        _;
    }

    ///                                                          ///
    ///                         IMMUTABLES                       ///
    ///                                                          ///

    /// @notice The contract upgrade manager
    IRevolutionBuilder private immutable manager;

    ///                                                          ///
    ///                         CONSTRUCTOR                      ///
    ///                                                          ///

    /// @param _manager The contract upgrade manager address
    constructor(address _manager) payable initializer {
        manager = IRevolutionBuilder(_manager);
    }

    ///                                                          ///
    ///                         INITIALIZER                      ///
    ///                                                          ///

    /// @notice Initializes a DAO's ERC-721 token contract
    /// @param _minter The address of the minter
    /// @param _initialOwner The address of the initial owner
    /// @param _descriptor The address of the token URI descriptor
    /// @param _cultureIndex The address of the CultureIndex contract
    /// @param _revolutionTokenParams The name, symbol, and contract metadata of the token
    function initialize(
        address _minter,
        address _initialOwner,
        address _descriptor,
        address _cultureIndex,
        IRevolutionBuilder.RevolutionTokenParams calldata _revolutionTokenParams
    ) external initializer {
        if (msg.sender != address(manager)) revert ONLY_MANAGER_CAN_INITIALIZE();

        if (_minter == address(0)) revert ADDRESS_ZERO();
        if (_initialOwner == address(0)) revert ADDRESS_ZERO();

        // Initialize the reentrancy guard
        __ReentrancyGuard_init();

        // Setup ownable
        __Ownable_init(_initialOwner);

        // Initialize the ERC-721 token
        __ERC721_init(_revolutionTokenParams.name, _revolutionTokenParams.symbol);
        _contractURIHash = _revolutionTokenParams.contractURIHash;

        // Set the contracts
        minter = _minter;
        descriptor = IDescriptorMinimal(_descriptor);
        cultureIndex = ICultureIndex(_cultureIndex);
    }

    /**
     * @notice The IPFS URI of contract-level metadata.
     */
    function contractURI() public view returns (string memory) {
        return string(abi.encodePacked("ipfs://", _contractURIHash));
    }

    /**
     * @notice Set the _contractURIHash.
     * @dev Only callable by the owner.
     */
    function setContractURIHash(string memory newContractURIHash) external onlyOwner {
        _contractURIHash = newContractURIHash;
    }

    /**
     * @notice Mint a Verb to the minter.
     * @dev Call _mintTo with the to address(es).
     */
    function mint() public override onlyMinter nonReentrant returns (uint256) {
        return _mintTo(minter);
    }

    /**
     * @notice Burn a verb.
     */
    function burn(uint256 verbId) public override onlyMinter nonReentrant {
        _burn(verbId);
        emit VerbBurned(verbId);
    }

    /**
     * @notice A distinct Uniform Resource Identifier (URI) for a given asset.
     * @dev See {IERC721Metadata-tokenURI}.
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        if (ownerOf(tokenId) == address(0)) revert();
        return descriptor.tokenURI(tokenId, cultureIndex.getPieceById(artPieces[tokenId]).metadata);
    }

    /**
     * @notice Similar to `tokenURI`, but always serves a base64 encoded data URI
     * with the JSON contents directly inlined.
     */
    function dataURI(uint256 tokenId) public view override returns (string memory) {
        if (ownerOf(tokenId) == address(0)) revert();
        return descriptor.dataURI(tokenId, cultureIndex.getPieceById(artPieces[tokenId]).metadata);
    }

    /**
     * @notice Set the token minter.
     * @dev Only callable by the owner when not locked.
     */
    function setMinter(address _minter) external override onlyOwner nonReentrant whenMinterNotLocked {
        if (_minter == address(0)) revert ADDRESS_ZERO();
        minter = _minter;

        emit MinterUpdated(_minter);
    }

    /**
     * @notice Lock the minter.
     * @dev This cannot be reversed and is only callable by the owner when not locked.
     */
    function lockMinter() external override onlyOwner whenMinterNotLocked {
        isMinterLocked = true;

        emit MinterLocked();
    }

    /**
     * @notice Set the token URI descriptor.
     * @dev Only callable by the owner when not locked.
     */
    function setDescriptor(
        IDescriptorMinimal _descriptor
    ) external override onlyOwner nonReentrant whenDescriptorNotLocked {
        descriptor = _descriptor;

        emit DescriptorUpdated(_descriptor);
    }

    /**
     * @notice Lock the descriptor.
     * @dev This cannot be reversed and is only callable by the owner when not locked.
     */
    function lockDescriptor() external override onlyOwner whenDescriptorNotLocked {
        isDescriptorLocked = true;

        emit DescriptorLocked();
    }

    /**
     * @notice Set the token CultureIndex.
     * @dev Only callable by the owner when not locked.
     */
    function setCultureIndex(ICultureIndex _cultureIndex) external onlyOwner whenCultureIndexNotLocked nonReentrant {
        cultureIndex = _cultureIndex;

        emit CultureIndexUpdated(_cultureIndex);
    }

    /**
     * @notice Lock the CultureIndex
     * @dev This cannot be reversed and is only callable by the owner when not locked.
     */
    function lockCultureIndex() external override onlyOwner whenCultureIndexNotLocked {
        isCultureIndexLocked = true;

        emit CultureIndexLocked();
    }

    /**
     * @notice Fetch an art piece by its ID.
     * @param verbId The ID of the art piece.
     * @return The ArtPiece struct associated with the given ID.
     */
    function getArtPieceById(uint256 verbId) external view returns (ICultureIndex.ArtPiece memory) {
        if (verbId >= _currentVerbId) revert INVALID_PIECE_ID();
        return cultureIndex.getPieceById(artPieces[verbId]);
    }

    /**
     * @notice Mint a Verb with `verbId` to the provided `to` address. Pulls the top voted art piece from the CultureIndex.
     */
    function _mintTo(address to) internal returns (uint256) {
        // Use try/catch to handle potential failure
        try cultureIndex.dropTopVotedPiece() returns (ICultureIndex.ArtPieceCondensed memory artPiece) {
            uint256 verbId = _currentVerbId++;

            artPieces[verbId] = artPiece.pieceId;

            _mint(to, verbId);

            emit VerbCreated(verbId, artPiece);

            return verbId;
        } catch {
            revert("dropTopVotedPiece failed");
        }
    }

    ///                                                          ///
    ///                         TOKEN UPGRADE                    ///
    ///                                                          ///

    /// @notice Ensures the caller is authorized to upgrade the contract and that the new implementation is valid
    /// @dev This function is called in `upgradeTo` & `upgradeToAndCall`
    /// @param _newImpl The new implementation address
    function _authorizeUpgrade(address _newImpl) internal view override onlyOwner {
        // Ensure the implementation is valid
        if (!manager.isRegisteredUpgrade(_getImplementation(), _newImpl)) revert INVALID_UPGRADE(_newImpl);
    }
}
