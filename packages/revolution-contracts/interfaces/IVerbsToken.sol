// SPDX-License-Identifier: GPL-3.0

/// @title Interface for VerbsToken

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
import { IVerbsDescriptorMinimal } from "./IVerbsDescriptorMinimal.sol";

interface IVerbsToken is IERC721 {
    event VerbCreated(uint256 indexed tokenId);

    event VerbBurned(uint256 indexed tokenId);

    event MinterUpdated(address minter);

    event MinterLocked();

    event DescriptorUpdated(IVerbsDescriptorMinimal descriptor);

    event DescriptorLocked();

    function mint() external returns (uint256);

    function burn(uint256 tokenId) external;

    function dataURI(uint256 tokenId) external returns (string memory);

    function setMinter(address minter) external;

    function lockMinter() external;

    function setDescriptor(IVerbsDescriptorMinimal descriptor) external;

    function lockDescriptor() external;
}
