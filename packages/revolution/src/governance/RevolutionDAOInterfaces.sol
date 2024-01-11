// SPDX-License-Identifier: BSD-3-Clause

/// @title Revolution DAO Logic interfaces and events

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
// RevolutionDAOInterfaces.sol is a modified version of Compound Lab's GovernorBravoInterfaces.sol:
// https://github.com/compound-finance/compound-protocol/blob/b9b14038612d846b83f8a009a82c38974ff2dcfe/contracts/Governance/GovernorBravoInterfaces.sol
//
// GovernorBravoInterfaces.sol source code Copyright 2020 Compound Labs, Inc. licensed under the BSD-3-Clause license.
// With modifications by Nounders DAO.
//
// Additional conditions of BSD-3-Clause can be found here: https://opensource.org/licenses/BSD-3-Clause
//
// MODIFICATIONS
// RevolutionDAOEvents, RevolutionDAOProxyStorage, RevolutionDAOStorageV1 add support for changes made by Revolution DAO to GovernorBravo.sol
// See RevolutionDAOLogicV1.sol for more details.

import { IDAOExecutor } from "../interfaces/IDAOExecutor.sol";
import { IRevolutionBuilder } from "../interfaces/IRevolutionBuilder.sol";
import { IRevolutionVotingPower } from "../interfaces/IRevolutionVotingPower.sol";

pragma solidity 0.8.22;

contract RevolutionDAOEvents {
    /// @notice An event emitted when a new proposal is created
    event ProposalCreated(
        uint256 id,
        address proposer,
        address[] targets,
        uint256[] values,
        string[] signatures,
        bytes[] calldatas,
        uint256 startBlock,
        uint256 endBlock,
        string description
    );

    /// @notice An event emitted when a new proposal is created, which includes additional information
    event ProposalCreatedWithRequirements(
        uint256 id,
        address proposer,
        address[] targets,
        uint256[] values,
        string[] signatures,
        bytes[] calldatas,
        uint256 startBlock,
        uint256 endBlock,
        uint256 proposalThreshold,
        uint256 quorumVotes,
        string description
    );

    /// @notice An event emitted when a vote has been cast on a proposal
    /// @param voter The address which casted a vote
    /// @param proposalId The proposal id which was voted on
    /// @param support Support value for the vote. 0=against, 1=for, 2=abstain
    /// @param votes Number of votes which were cast by the voter
    /// @param reason The reason given for the vote by the voter
    event VoteCast(address indexed voter, uint256 proposalId, uint8 support, uint256 votes, string reason);

    /// @notice An event emitted when a proposal has been canceled
    event ProposalCanceled(uint256 id);

    /// @notice An event emitted when a proposal has been queued in the DAOExecutor
    event ProposalQueued(uint256 id, uint256 eta);

    /// @notice An event emitted when a proposal has been executed in the DAOExecutor
    event ProposalExecuted(uint256 id);

    /// @notice An event emitted when a proposal has been vetoed by vetoAddress
    event ProposalVetoed(uint256 id);

    /// @notice An event emitted when the voting delay is set
    event VotingDelaySet(uint256 oldVotingDelay, uint256 newVotingDelay);

    /// @notice An event emitted when the voting period is set
    event VotingPeriodSet(uint256 oldVotingPeriod, uint256 newVotingPeriod);

    /// @notice Emitted when implementation is changed
    event NewImplementation(address oldImplementation, address newImplementation);

    /// @notice Emitted when proposal threshold basis points is set
    event ProposalThresholdBPSSet(uint256 oldProposalThresholdBPS, uint256 newProposalThresholdBPS);

    /// @notice Emitted when quorum votes basis points is set
    event QuorumVotesBPSSet(uint256 oldQuorumVotesBPS, uint256 newQuorumVotesBPS);

    /// @notice Emitted when pendingAdmin is changed
    event NewPendingAdmin(address oldPendingAdmin, address newPendingAdmin);

    /// @notice Emitted when pendingAdmin is accepted, which means admin is updated
    event NewAdmin(address oldAdmin, address newAdmin);

    /// @notice Emitted when vetoer is changed
    event NewVetoer(address oldVetoer, address newVetoer);

    /// @notice Emitted when minQuorumVotesBPS is set
    event MinQuorumVotesBPSSet(uint16 oldMinQuorumVotesBPS, uint16 newMinQuorumVotesBPS);

    /// @notice Emitted when maxQuorumVotesBPS is set
    event MaxQuorumVotesBPSSet(uint16 oldMaxQuorumVotesBPS, uint16 newMaxQuorumVotesBPS);

    /// @notice Emitted when quorumCoefficient is set
    event QuorumCoefficientSet(uint32 oldQuorumCoefficient, uint32 newQuorumCoefficient);

    /// @notice Emitted when a voter cast a vote requesting a gas refund.
    event RefundableVote(address indexed voter, uint256 refundAmount, bool refundSent);

    /// @notice Emitted when admin withdraws the DAO's balance.
    event Withdraw(uint256 amount, bool sent);

    /// @notice Emitted when pendingVetoer is changed
    event NewPendingVetoer(address oldPendingVetoer, address newPendingVetoer);
}

contract RevolutionDAOProxyStorage {
    /// @notice Administrator for this contract
    address public admin;

    /// @notice Pending administrator for this contract
    address public pendingAdmin;

    /// @notice Active brains of Governor
    address public implementation;
}

/**
 * @title Storage for Governor Bravo Delegate
 * @notice For future upgrades, do not change RevolutionDAOStorageV1. Create a new
 * contract which implements RevolutionDAOStorageV1 and following the naming convention
 * RevolutionDAOStorageVX.
 */
contract RevolutionDAOStorageV1 is RevolutionDAOProxyStorage {
    ///                                                          ///
    ///                           ERRORS                         ///
    ///                                                          ///

    /// @dev Introduced these errors to reduce contract size, to avoid deployment failure

    /// @dev Reverts if the caller is not the manager.
    error NOT_MANAGER();

    /// @dev Reverts if the provided executor address is invalid (zero address).
    error INVALID_EXECUTOR_ADDRESS();

    /// @dev Reverts if the provided RevolutionVotingPower address is invalid (zero address).
    error INVALID_VOTINGPOWER_ADDRESS();

    /// @dev Reverts if the voting period is outside the allowed range.
    error INVALID_VOTING_PERIOD();

    /// @dev Reverts if the voting delay is outside the allowed range.
    error INVALID_VOTING_DELAY();

    /// @dev Reverts if the proposal threshold basis points are outside the allowed range.
    error INVALID_PROPOSAL_THRESHOLD_BPS();

    /// @dev Reverts if the proposer's votes are below the proposal threshold.
    error PROPOSER_VOTES_BELOW_THRESHOLD();

    /// @dev Reverts if the lengths of proposal arrays (targets, values, signatures, calldatas) do not match.
    error PROPOSAL_FUNCTION_PARITY_MISMATCH();

    /// @dev Reverts if no actions are provided in the proposal.
    error NO_ACTIONS_PROVIDED();

    /// @dev Reverts if the number of actions in the proposal exceeds the maximum allowed.
    error TOO_MANY_ACTIONS();

    /// @dev Reverts if the proposer already has an active proposal.
    error ACTIVE_PROPOSAL_EXISTS();

    /// @dev Reverts if the proposer already has a pending proposal.
    error PENDING_PROPOSAL_EXISTS();

    /// @dev Reverts if the proposal is not in the 'Succeeded' state when attempting to queue.
    error PROPOSAL_NOT_SUCCEEDED();

    /// @dev Reverts if the proposal is not currently in an active state for voting.
    error VOTING_CLOSED();

    /// @dev Reverts if an invalid vote type is provided (vote type must be within a certain range).
    error INVALID_VOTE_TYPE();

    /// @dev Reverts if the voter has already cast a vote for the proposal.
    error VOTER_ALREADY_VOTED();

    /// @dev Reverts if the new minimum quorum votes basis points are outside the allowed bounds.
    error INVALID_MIN_QUORUM_VOTES_BPS();

    /// @dev Reverts if the new minimum quorum votes basis points exceed the maximum quorum votes basis points.
    error MIN_QUORUM_EXCEEDS_MAX();

    /// @dev Reverts if the new maximum quorum votes basis points exceed the upper bound.
    error INVALID_MAX_QUORUM_VOTES_BPS();

    /// @dev Reverts if the minimum quorum votes basis points are greater than the new maximum quorum votes basis points.
    error MAX_QUORUM_EXCEEDS_MIN();

    /// @dev Reverts if the caller is not the pending admin or is the zero address.
    error PENDING_ADMIN_ONLY();

    /// @dev Reverts if the caller is not the admin.
    error ADMIN_ONLY();

    /// @dev Reverts if the caller is not the vetoer.
    error VETOER_ONLY();

    /// @dev Reverts if the vetoer has been burned
    error VETOER_BURNED();

    /// @dev Reverts if the caller is not the pending vetoer.
    error PENDING_VETOER_ONLY();

    /// @dev Reverts if the minimum quorum votes basis points are greater than the maximum quorum votes basis points.
    error MIN_QUORUM_BPS_GREATER_THAN_MAX_QUORUM_BPS();

    /// @dev Reverts if an unsafe cast to uint16 is attempted.
    error UNSAFE_UINT16_CAST();

    /// @dev Reverts if an attempt is made to veto an already executed proposal.
    error CANT_VETO_EXECUTED_PROPOSAL();

    /// @dev Reverts if an attempt is made to cancel an already executed proposal.
    error CANT_CANCEL_EXECUTED_PROPOSAL();

    /// @dev Reverts if the caller is not the proposer and the proposer's votes are still above the proposal threshold.
    error PROPOSER_ABOVE_THRESHOLD();

    /// @dev Reverts if the proposal ID is invalid (greater than the current proposal count).
    error INVALID_PROPOSAL_ID();

    /// @dev Reverts if an identical proposal action is already queued at the same eta.
    error PROPOSAL_ACTION_ALREADY_QUEUED();

    /// @dev Reverts if the proposal is not in the 'Queued' state when attempting to execute.
    error PROPOSAL_NOT_QUEUED();

    /// @dev Reverts if the signatory is the zero address, indicating an invalid signature.
    error INVALID_SIGNATURE();

    ///                                                          ///
    ///                           STATE                          ///
    ///                                                          ///

    /// @notice The contract upgrade manager
    IRevolutionBuilder public immutable manager;

    /// @notice Vetoer who has the ability to veto any proposal
    address public vetoer;

    /// @notice The delay before voting on a proposal may take place, once proposed, in blocks
    uint256 public votingDelay;

    /// @notice The duration of voting on a proposal, in blocks
    uint256 public votingPeriod;

    /// @notice The basis point number of votes required in order for a voter to become a proposer. *DIFFERS from GovernerBravo
    uint256 public proposalThresholdBPS;

    /// @notice The basis point number of votes in support of a proposal required in order for a quorum to be reached and for a vote to succeed. *DIFFERS from GovernerBravo
    uint256 public quorumVotesBPS;

    /// @notice The total number of proposals
    uint256 public proposalCount;

    /// @notice The address of the Revolution DAO Executor DAOExecutor
    IDAOExecutor public timelock;

    /// @notice The RevolutionVotingPower contract
    IRevolutionVotingPower public votingPower;

    /// @notice The official record of all proposals ever proposed
    mapping(uint256 => Proposal) internal _proposals;

    /// @notice The latest proposal for each proposer
    mapping(address => uint256) public latestProposalIds;

    DynamicQuorumParamsCheckpoint[] public quorumParamsCheckpoints;

    /// @notice Pending new vetoer
    address public pendingVetoer;

    ///                                                          ///
    ///                        CONSTANTS                         ///
    ///                                                          ///

    struct Proposal {
        /// @notice Unique id for looking up a proposal
        uint256 id;
        /// @notice Creator of the proposal
        address proposer;
        /// @notice The number of votes needed to create a proposal at the time of proposal creation. *DIFFERS from GovernerBravo
        uint256 proposalThreshold;
        /// @notice The number of votes in support of a proposal required in order for a quorum to be reached and for a vote to succeed at the time of proposal creation. *DIFFERS from GovernerBravo
        uint256 quorumVotes;
        /// @notice The timestamp that the proposal will be available for execution, set once the vote succeeds
        uint256 eta;
        /// @notice the ordered list of target addresses for calls to be made
        address[] targets;
        /// @notice The ordered list of values (i.e. msg.value) to be passed to the calls to be made
        uint256[] values;
        /// @notice The ordered list of function signatures to be called
        string[] signatures;
        /// @notice The ordered list of calldata to be passed to each call
        bytes[] calldatas;
        /// @notice The block at which voting begins: holders must delegate their votes prior to this block
        uint256 startBlock;
        /// @notice The block at which voting ends: votes must be cast prior to this block
        uint256 endBlock;
        /// @notice Current number of votes in favor of this proposal
        uint256 forVotes;
        /// @notice Current number of votes in opposition to this proposal
        uint256 againstVotes;
        /// @notice Current number of votes for abstaining for this proposal
        uint256 abstainVotes;
        /// @notice Flag marking whether the proposal has been canceled
        bool canceled;
        /// @notice Flag marking whether the proposal has been vetoed
        bool vetoed;
        /// @notice Flag marking whether the proposal has been executed
        bool executed;
        /// @notice Receipts of ballots for the entire set of voters
        mapping(address => Receipt) receipts;
        /// @notice The total weighted supply at the time of proposal creation
        uint256 totalWeightedSupply;
        /// @notice The total supply of points at the time of proposal creation
        uint256 revolutionPointsSupply;
        /// @notice The total supply of revolution at the time of proposal creation
        uint256 revolutionTokenSupply;
        /// @notice The block at which this proposal was created
        uint256 creationBlock;
    }

    /// @notice Ballot receipt record for a voter
    struct Receipt {
        /// @notice Whether or not a vote has been cast
        bool hasVoted;
        /// @notice Whether or not the voter supports the proposal or abstains
        uint8 support;
        /// @notice The number of votes the voter had, which were cast
        uint256 votes;
    }

    /// @notice Possible states that a proposal may be in
    enum ProposalState {
        Pending,
        Active,
        Canceled,
        Defeated,
        Succeeded,
        Queued,
        Expired,
        Executed,
        Vetoed
    }

    struct DynamicQuorumParams {
        /// @notice The minimum basis point number of votes in support of a proposal required in order for a quorum to be reached and for a vote to succeed.
        uint16 minQuorumVotesBPS;
        /// @notice The maximum basis point number of votes in support of a proposal required in order for a quorum to be reached and for a vote to succeed.
        uint16 maxQuorumVotesBPS;
        /// @notice The dynamic quorum coefficient
        /// @dev Assumed to be fixed point integer with 6 decimals, i.e 0.2 is represented as 0.2 * 1e6 = 200000
        uint32 quorumCoefficient;
    }

    /// @notice A checkpoint for storing dynamic quorum params from a given block
    struct DynamicQuorumParamsCheckpoint {
        /// @notice The block at which the new values were set
        uint32 fromBlock;
        /// @notice The parameter values of this checkpoint
        DynamicQuorumParams params;
    }

    struct ProposalCondensed {
        /// @notice Unique id for looking up a proposal
        uint256 id;
        /// @notice Creator of the proposal
        address proposer;
        /// @notice The number of votes needed to create a proposal at the time of proposal creation. *DIFFERS from GovernerBravo
        uint256 proposalThreshold;
        /// @notice The minimum number of votes in support of a proposal required in order for a quorum to be reached and for a vote to succeed at the time of proposal creation. *DIFFERS from GovernerBravo
        uint256 quorumVotes;
        /// @notice The timestamp that the proposal will be available for execution, set once the vote succeeds
        uint256 eta;
        /// @notice The block at which voting begins: holders must delegate their votes prior to this block
        uint256 startBlock;
        /// @notice The block at which voting ends: votes must be cast prior to this block
        uint256 endBlock;
        /// @notice Current number of votes in favor of this proposal
        uint256 forVotes;
        /// @notice Current number of votes in opposition to this proposal
        uint256 againstVotes;
        /// @notice Current number of votes for abstaining for this proposal
        uint256 abstainVotes;
        /// @notice Flag marking whether the proposal has been canceled
        bool canceled;
        /// @notice Flag marking whether the proposal has been vetoed
        bool vetoed;
        /// @notice Flag marking whether the proposal has been executed
        bool executed;
        /// @notice The total weighted supply at the time of proposal creation
        uint256 totalWeightedSupply;
        /// @notice The block at which this proposal was created
        uint256 creationBlock;
    }
}

interface RevolutionTokenLike {
    function getPastVotes(address account, uint256 blockNumber) external view returns (uint96);

    function totalSupply() external view returns (uint256);
}

interface PointsLike {
    function getPastVotes(address account, uint256 blockNumber) external view returns (uint96);

    function totalSupply() external view returns (uint256);
}
