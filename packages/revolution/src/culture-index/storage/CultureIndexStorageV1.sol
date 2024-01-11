// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { ICultureIndex } from "../../interfaces/ICultureIndex.sol";
import { IRevolutionVotingPower } from "../../interfaces/IRevolutionVotingPower.sol";
import { MaxHeap } from "../MaxHeap.sol";

/// @notice CultureIndex Storage V1
/// @author rocketman
/// @notice The CultureIndex storage contract
contract CultureIndexStorageV1 {
    /// @notice An account's nonce for gasless votes
    mapping(address => uint256) public nonces;

    // The MaxHeap data structure used to keep track of the top-voted piece
    MaxHeap public maxHeap;

    // The RevolutionVotingPower contract used to get the voting power of an account
    IRevolutionVotingPower public votingPower;

    /// @notice The minimum vote weight required in order to vote
    uint256 public minVoteWeight;

    /// @notice The basis point number of votes in support of a art piece required in order for a quorum to be reached and for an art piece to be dropped.
    uint256 public quorumVotesBPS;

    /// @notice The name of the culture index
    string public name;

    /// @notice A description of the culture index - can include rules or guidelines
    string public description;

    // The list of all pieces
    mapping(uint256 => ICultureIndex.ArtPiece) public pieces;

    // The internal piece ID tracker
    uint256 public _currentPieceId;

    // The mapping of all votes for a piece
    mapping(uint256 => mapping(address => ICultureIndex.Vote)) public votes;

    // The total voting weight for a piece
    mapping(uint256 => uint256) public totalVoteWeights;

    // The address that is allowed to drop art pieces
    address public dropperAdmin;
}
