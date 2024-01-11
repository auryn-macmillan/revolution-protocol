// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { IRevolutionBuilder } from "./IRevolutionBuilder.sol";

interface IRevolutionPoints {
    ///                                                          ///
    ///                           EVENTS                         ///
    ///                                                          ///

    event MinterUpdated(address minter);

    event MinterLocked();

    ///                                                          ///
    ///                           ERRORS                         ///
    ///                                                          ///

    /// @dev Revert if transfer is attempted. This is a nontransferable token.
    error TRANSFER_NOT_ALLOWED();

    /// @dev Revert if not the manager
    error ONLY_MANAGER();

    /// @dev Revert if 0 address
    error INVALID_ADDRESS_ZERO();

    /// @dev Revert if minter is locked
    error MINTER_LOCKED();

    /// @dev Revert if not minter
    error NOT_MINTER();

    ///                                                          ///
    ///                         FUNCTIONS                        ///
    ///                                                          ///

    function setMinter(address minter) external;

    function lockMinter() external;

    /// @notice Initializes a DAO's ERC-20 governance token contract
    /// @param initialOwner The address of the initial owner
    /// @param minter The address of the minter
    /// @param tokenParams The params of the token
    function initialize(
        address initialOwner,
        address minter,
        IRevolutionBuilder.PointsTokenParams calldata tokenParams
    ) external;
}
