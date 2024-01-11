// SPDX-License-Identifier: BSD-3-Clause

/// @title The Revolution DAO proxy contract for V1

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

// RevolutionDAOProxyV1.sol is a modified version of NounsDAOProxyV2.sol, tailored for Revolution DAO V1.

// LICENSE
// NounsDAOProxy.sol is a modified version of Compound Lab's GovernorBravoDelegator.sol:
// https://github.com/compound-finance/compound-protocol/blob/b9b14038612d846b83f8a009a82c38974ff2dcfe/contracts/Governance/GovernorBravoDelegator.sol
//
// GovernorBravoDelegator.sol source code Copyright 2020 Compound Labs, Inc. licensed under the BSD-3-Clause license.
// With modifications by Nounders DAO.
//
// Additional conditions of BSD-3-Clause can be found here: https://opensource.org/licenses/BSD-3-Clause
//
//
// NounsDAOProxy.sol uses parts of Open Zeppelin's Proxy.sol:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5c8746f56b4bed8cc9e0e044f5f69ab2f9428ce1/contracts/proxy/Proxy.sol
//
// Proxy.sol source code licensed under MIT License.
//
// MODIFICATIONS
// The fallback() and receive() functions of Proxy.sol have been used to allow Solidity > 0.6.0 compatibility

pragma solidity ^0.8.22;

import "./RevolutionDAOInterfaces.sol";
import { IRevolutionBuilder } from "../interfaces/IRevolutionBuilder.sol";

contract RevolutionDAOProxyV1 is RevolutionDAOStorageV1, RevolutionDAOEvents {
    ///                                                          ///
    ///                           ERRORS                         ///
    ///                                                          ///

    /// @notice Revert with invalid implementation address
    error INVALID_IMPLEMENTATION();

    constructor(
        address _executor,
        address _votingPower,
        IRevolutionBuilder.GovParams memory _govParams,
        address _implementation,
        address _admin
    ) {
        // Admin set to msg.sender for initialization
        admin = msg.sender;

        delegateTo(
            _implementation,
            abi.encodeWithSignature(
                "initialize(address,address,(uint256,uint256,uint256,uint256,address,string,(uint16,uint16,uint32)))",
                _executor,
                _votingPower,
                _govParams
            )
        );

        _setImplementation(_implementation);

        admin = _admin;
    }

    /**
     * @notice Called by the admin to update the implementation of the delegator
     * @param _implementation The address of the new implementation for delegation
     */
    function _setImplementation(address _implementation) public {
        if (msg.sender != admin) revert ADMIN_ONLY();
        if (_implementation == address(0)) revert INVALID_IMPLEMENTATION();

        address oldImplementation = implementation;
        implementation = _implementation;

        emit NewImplementation(oldImplementation, implementation);
    }

    /**
     * @notice Internal method to delegate execution to another contract
     * @dev It returns to the external caller whatever the implementation returns or forwards reverts
     * @param callee The contract to delegatecall
     * @param data The raw data to delegatecall
     */
    function delegateTo(address callee, bytes memory data) internal {
        (bool success, bytes memory returnData) = callee.delegatecall(data);
        assembly {
            if eq(success, 0) {
                revert(add(returnData, 0x20), returndatasize())
            }
        }
    }

    /**
     * @dev Delegates execution to an implementation contract.
     * It returns to the external caller whatever the implementation returns
     * or forwards reverts.
     */
    function _fallback() internal {
        // delegate all other functions to current implementation
        (bool success, ) = implementation.delegatecall(msg.data);

        assembly {
            let free_mem_ptr := mload(0x40)
            returndatacopy(free_mem_ptr, 0, returndatasize())

            switch success
            case 0 {
                revert(free_mem_ptr, returndatasize())
            }
            default {
                return(free_mem_ptr, returndatasize())
            }
        }
    }

    /**
     * @dev Fallback function that delegates calls to the `implementation`. Will run if no other
     * function in the contract matches the call data.
     */
    fallback() external payable {
        _fallback();
    }

    /**
     * @dev Fallback function that delegates calls to `implementation`. Will run if call data
     * is empty.
     */
    receive() external payable {
        _fallback();
    }
}
