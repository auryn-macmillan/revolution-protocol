// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import "../governance/RevolutionDAOInterfaces.sol";
import { IRevolutionBuilder } from "./IRevolutionBuilder.sol";

interface IRevolutionDAO {
    /**
     * @notice Used to initialize the contract during delegator contructor
     * @param executor The address of the DAOExecutor
     * @param votingPower The address of the RevolutionVotingPower contract
     * @param govParams The initial governance parameters
     */
    function initialize(
        address executor,
        address votingPower,
        IRevolutionBuilder.GovParams calldata govParams
    ) external;
}
