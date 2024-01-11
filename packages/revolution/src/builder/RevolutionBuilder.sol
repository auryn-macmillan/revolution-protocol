// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

/// @title The Revolution builder contract

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
// RevolutionBuilder.sol is a modified version of Nouns Builder's Manager.sol:
// https://github.com/ourzora/nouns-protocol/blob/82e00ed34dd9b7c9e1ac5eea29f7f713d1084e68/src/manager/Manager.sol
//
// Manager.sol source code under the MIT license.

import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

import { RevolutionBuilderStorageV1 } from "./storage/RevolutionBuilderStorageV1.sol";
import { IRevolutionBuilder } from "../interfaces/IRevolutionBuilder.sol";
import { IRevolutionToken } from "../interfaces/IRevolutionToken.sol";
import { IRevolutionVotingPower } from "../interfaces/IRevolutionVotingPower.sol";
import { IDescriptor } from "../interfaces/IDescriptor.sol";
import { IAuctionHouse } from "../interfaces/IAuctionHouse.sol";
import { IDAOExecutor } from "../interfaces/IDAOExecutor.sol";
import { IRevolutionDAO } from "../interfaces/IRevolutionDAO.sol";
import { ICultureIndex } from "../interfaces/ICultureIndex.sol";
import { IMaxHeap } from "../interfaces/IMaxHeap.sol";
import { IRevolutionPointsEmitter } from "../interfaces/IRevolutionPointsEmitter.sol";
import { IRevolutionPoints } from "../interfaces/IRevolutionPoints.sol";
import { VRGDAC } from "../libs/VRGDAC.sol";

import { ERC1967Proxy } from "../libs/proxy/ERC1967Proxy.sol";
import { UUPS } from "../libs/proxy/UUPS.sol";
import { RevolutionDAOProxyV1 } from "../governance/RevolutionDAOProxyV1.sol";

import { VersionedContract } from "../version/VersionedContract.sol";
import { IVersionedContract } from "../interfaces/IVersionedContract.sol";

/// @title RevolutionBuilder
/// @notice The Revolution DAO deployer and upgrade manager
contract RevolutionBuilder is
    IRevolutionBuilder,
    VersionedContract,
    UUPS,
    Ownable2StepUpgradeable,
    RevolutionBuilderStorageV1
{
    ///                                                          ///
    ///                          IMMUTABLES                      ///
    ///                                                          ///

    /// @notice The token implementation address
    address public immutable revolutionTokenImpl;

    /// @notice The descriptor implementation address
    address public immutable descriptorImpl;

    /// @notice The auction house implementation address
    address public immutable auctionImpl;

    /// @notice The executor implementation address
    address public immutable executorImpl;

    /// @notice The dao implementation address
    address public immutable daoImpl;

    /// @notice The revolutionPointsEmitter implementation address
    address public immutable revolutionPointsEmitterImpl;

    /// @notice The cultureIndex implementation address
    address public immutable cultureIndexImpl;

    /// @notice The revolutionPoints implementation address
    address public immutable revolutionPointsImpl;

    /// @notice The maxHeap implementation address
    address public immutable maxHeapImpl;

    /// @notice the revolutionVotingPower implementation address
    address public immutable revolutionVotingPowerImpl;

    ///                                                          ///
    ///                          CONSTRUCTOR                     ///
    ///                                                          ///

    constructor(
        address _revolutionTokenImpl,
        address _descriptorImpl,
        address _auctionImpl,
        address _executorImpl,
        address _daoImpl,
        address _cultureIndexImpl,
        address _revolutionPointsImpl,
        address _revolutionPointsEmitterImpl,
        address _maxHeapImpl,
        address _revolutionVotingPowerImpl
    ) payable initializer {
        revolutionTokenImpl = _revolutionTokenImpl;
        descriptorImpl = _descriptorImpl;
        auctionImpl = _auctionImpl;
        executorImpl = _executorImpl;
        daoImpl = _daoImpl;
        cultureIndexImpl = _cultureIndexImpl;
        revolutionPointsImpl = _revolutionPointsImpl;
        revolutionPointsEmitterImpl = _revolutionPointsEmitterImpl;
        maxHeapImpl = _maxHeapImpl;
        revolutionVotingPowerImpl = _revolutionVotingPowerImpl;
    }

    ///                                                          ///
    ///                          INITIALIZER                     ///
    ///                                                          ///

    /// @notice Initializes ownership of the manager contract
    /// @param _newOwner The owner address to set (will be transferred to the Revolution DAO once its deployed)
    function initialize(address _newOwner) external initializer {
        // Ensure an owner is specified
        require(_newOwner != address(0), "Owner address cannot be 0x0");

        // Set the contract owner
        __Ownable_init(_newOwner);
    }

    ///                                                          ///
    ///                           DAO DEPLOY                     ///
    ///                                                          ///

    /// @notice Helper function to deploys initial DAO proxy contracts
    /// @param _govParams The governance settings
    function _setupInitialProxies(GovParams calldata _govParams) internal returns (InitialProxySetup memory) {
        // Deploy the DAO's ERC-721 governance token
        address revolutionToken = address(new ERC1967Proxy(revolutionTokenImpl, ""));
        // Use the token address to precompute the DAO's remaining addresses
        bytes32 salt = bytes32(uint256(uint160(revolutionToken)) << 96);

        address executor = address(new ERC1967Proxy{ salt: salt }(executorImpl, ""));
        address revolutionVotingPower = address(new ERC1967Proxy{ salt: salt }(revolutionVotingPowerImpl, ""));

        // Use RevolutionDAOProxyV1 to initialize the DAO
        address dao = address(
            new RevolutionDAOProxyV1{ salt: salt }(executor, revolutionVotingPower, _govParams, daoImpl, executor)
        );

        return
            InitialProxySetup({
                revolutionToken: revolutionToken,
                executor: executor,
                revolutionVotingPower: revolutionVotingPower,
                dao: dao,
                salt: salt
            });
    }

    /// @notice Deploys a DAO with custom token, auction, emitter, revolution points, and governance settings
    /// @param _initialOwner The initial owner address
    /// @param _weth The WETH address
    /// @param _revolutionTokenParams The ERC-721 token settings
    /// @param _auctionParams The auction settings
    /// @param _govParams The governance settings
    /// @param _cultureIndexParams The culture index settings
    /// @param _revolutionPointsParams The ERC-20 token settings
    /// @param _revolutionVotingPowerParams The voting power settings
    function deploy(
        address _initialOwner,
        address _weth,
        RevolutionTokenParams calldata _revolutionTokenParams,
        AuctionParams calldata _auctionParams,
        GovParams calldata _govParams,
        CultureIndexParams calldata _cultureIndexParams,
        RevolutionPointsParams calldata _revolutionPointsParams,
        RevolutionVotingPowerParams calldata _revolutionVotingPowerParams
    ) external returns (DAOAddresses memory) {
        require(_initialOwner != address(0), "Initial owner cannot be 0x0");

        InitialProxySetup memory initialSetup = _setupInitialProxies(_govParams);

        address revolutionToken = initialSetup.revolutionToken;

        // Deploy the VRGDAC contract
        address vrgdac = address(
            new VRGDAC(
                _revolutionPointsParams.emitterParams.vrgdaParams.targetPrice,
                _revolutionPointsParams.emitterParams.vrgdaParams.priceDecayPercent,
                _revolutionPointsParams.emitterParams.vrgdaParams.tokensPerTimeUnit
            )
        );

        // Deploy the remaining DAO contracts
        daoAddressesByToken[initialSetup.revolutionToken] = DAOAddresses({
            revolutionPointsEmitter: address(
                new ERC1967Proxy{ salt: initialSetup.salt }(revolutionPointsEmitterImpl, "")
            ),
            revolutionPoints: address(new ERC1967Proxy{ salt: initialSetup.salt }(revolutionPointsImpl, "")),
            descriptor: address(new ERC1967Proxy{ salt: initialSetup.salt }(descriptorImpl, "")),
            auction: address(new ERC1967Proxy{ salt: initialSetup.salt }(auctionImpl, "")),
            cultureIndex: address(new ERC1967Proxy{ salt: initialSetup.salt }(cultureIndexImpl, "")),
            maxHeap: address(new ERC1967Proxy{ salt: initialSetup.salt }(maxHeapImpl, "")),
            revolutionVotingPower: initialSetup.revolutionVotingPower,
            revolutionToken: revolutionToken,
            executor: initialSetup.executor,
            dao: initialSetup.dao
        });

        // Initialize each instance with the provided settings
        IMaxHeap(daoAddressesByToken[revolutionToken].maxHeap).initialize({
            initialOwner: initialSetup.executor,
            admin: daoAddressesByToken[revolutionToken].cultureIndex
        });

        IRevolutionVotingPower(daoAddressesByToken[revolutionToken].revolutionVotingPower).initialize({
            initialOwner: initialSetup.executor,
            revolutionPoints: daoAddressesByToken[revolutionToken].revolutionPoints,
            revolutionPointsVoteWeight: _revolutionVotingPowerParams.revolutionPointsVoteWeight,
            revolutionToken: daoAddressesByToken[revolutionToken].revolutionToken,
            revolutionTokenVoteWeight: _revolutionVotingPowerParams.revolutionTokenVoteWeight
        });

        IRevolutionToken(revolutionToken).initialize({
            minter: daoAddressesByToken[revolutionToken].auction,
            descriptor: daoAddressesByToken[revolutionToken].descriptor,
            initialOwner: initialSetup.executor,
            cultureIndex: daoAddressesByToken[revolutionToken].cultureIndex,
            revolutionTokenParams: _revolutionTokenParams
        });

        IDescriptor(daoAddressesByToken[revolutionToken].descriptor).initialize({
            initialOwner: initialSetup.executor,
            tokenNamePrefix: _revolutionTokenParams.tokenNamePrefix
        });

        ICultureIndex(daoAddressesByToken[revolutionToken].cultureIndex).initialize({
            votingPower: daoAddressesByToken[revolutionToken].revolutionVotingPower,
            initialOwner: initialSetup.executor,
            dropperAdmin: daoAddressesByToken[revolutionToken].revolutionToken,
            cultureIndexParams: _cultureIndexParams,
            maxHeap: daoAddressesByToken[revolutionToken].maxHeap
        });

        IAuctionHouse(daoAddressesByToken[revolutionToken].auction).initialize({
            revolutionToken: daoAddressesByToken[revolutionToken].revolutionToken,
            revolutionPointsEmitter: daoAddressesByToken[revolutionToken].revolutionPointsEmitter,
            initialOwner: initialSetup.executor,
            auctionParams: _auctionParams,
            weth: _weth
        });

        //make owner of the points the executor
        IRevolutionPoints(daoAddressesByToken[revolutionToken].revolutionPoints).initialize({
            initialOwner: initialSetup.executor,
            minter: daoAddressesByToken[revolutionToken].revolutionPointsEmitter,
            tokenParams: _revolutionPointsParams.tokenParams
        });

        IRevolutionPointsEmitter(daoAddressesByToken[revolutionToken].revolutionPointsEmitter).initialize({
            revolutionPoints: daoAddressesByToken[revolutionToken].revolutionPoints,
            initialOwner: initialSetup.executor,
            weth: _weth,
            vrgdac: vrgdac,
            creatorsAddress: _revolutionPointsParams.emitterParams.creatorsAddress,
            creatorParams: _revolutionPointsParams.emitterParams.creatorParams
        });

        IDAOExecutor(daoAddressesByToken[revolutionToken].executor).initialize({
            admin: initialSetup.dao,
            timelockDelay: _govParams.timelockDelay
        });

        emit RevolutionDeployed({
            revolutionPointsEmitter: daoAddressesByToken[revolutionToken].revolutionPointsEmitter,
            revolutionPoints: daoAddressesByToken[revolutionToken].revolutionPoints,
            cultureIndex: daoAddressesByToken[revolutionToken].cultureIndex,
            descriptor: daoAddressesByToken[revolutionToken].descriptor,
            auction: daoAddressesByToken[revolutionToken].auction,
            maxHeap: daoAddressesByToken[revolutionToken].maxHeap,
            revolutionVotingPower: initialSetup.revolutionVotingPower,
            revolutionToken: revolutionToken,
            executor: initialSetup.executor,
            dao: initialSetup.dao
        });

        return daoAddressesByToken[revolutionToken];
    }

    ///                                                          ///
    ///                         DAO ADDRESSES                    ///
    ///                                                          ///

    /// @notice A DAO's contract addresses from its token
    /// @param _token The ERC-721 token address
    /// @return revolutionToken ERC-721 token deployed address
    /// @return descriptor Descriptor deployed address
    /// @return auction Auction deployed address
    /// @return executor Executor deployed address
    /// @return dao DAO deployed address
    /// @return cultureIndex CultureIndex deployed address
    /// @return revolutionPoints ERC-20 token deployed address
    /// @return revolutionPointsEmitter ERC-20 points emitter deployed address
    /// @return maxHeap MaxHeap deployed address
    /// @return revolutionVotingPower RevolutionVotingPower deployed address
    function getAddresses(
        address _token
    )
        public
        view
        returns (
            address revolutionToken,
            address descriptor,
            address auction,
            address executor,
            address dao,
            address cultureIndex,
            address revolutionPoints,
            address revolutionPointsEmitter,
            address maxHeap,
            address revolutionVotingPower
        )
    {
        DAOAddresses storage addresses = daoAddressesByToken[_token];

        descriptor = addresses.descriptor;
        auction = addresses.auction;
        revolutionToken = addresses.revolutionToken;
        executor = addresses.executor;
        dao = addresses.dao;

        cultureIndex = addresses.cultureIndex;
        revolutionPoints = addresses.revolutionPoints;
        revolutionPointsEmitter = addresses.revolutionPointsEmitter;
        maxHeap = addresses.maxHeap;
        revolutionVotingPower = addresses.revolutionVotingPower;
    }

    ///                                                          ///
    ///                          DAO UPGRADES                    ///
    ///                                                          ///

    /// @notice If an implementation is registered by the Revolution DAO as an optional upgrade
    /// @param _baseImpl The base implementation address
    /// @param _upgradeImpl The upgrade implementation address
    function isRegisteredUpgrade(address _baseImpl, address _upgradeImpl) external view returns (bool) {
        return isUpgrade[_baseImpl][_upgradeImpl];
    }

    /// @notice Called by the Revolution DAO to offer implementation upgrades for created DAOs
    /// @param _baseImpl The base implementation address
    /// @param _upgradeImpl The upgrade implementation address
    function registerUpgrade(address _baseImpl, address _upgradeImpl) external onlyOwner {
        isUpgrade[_baseImpl][_upgradeImpl] = true;

        emit UpgradeRegistered(_baseImpl, _upgradeImpl);
    }

    /// @notice Called by the Revolution DAO to remove an upgrade
    /// @param _baseImpl The base implementation address
    /// @param _upgradeImpl The upgrade implementation address
    function removeUpgrade(address _baseImpl, address _upgradeImpl) external onlyOwner {
        delete isUpgrade[_baseImpl][_upgradeImpl];

        emit UpgradeRemoved(_baseImpl, _upgradeImpl);
    }

    /// @notice Safely get the contract version of a target contract.
    /// @dev Assume `target` is a contract
    /// @return Contract version if found, empty string if not.
    function _safeGetVersion(address target) internal view returns (string memory) {
        try IVersionedContract(target).contractVersion() returns (string memory version) {
            return version;
        } catch {
            return "";
        }
    }

    function getDAOVersions(address token) external view returns (DAOVersionInfo memory) {
        (
            address revolutionToken,
            address descriptor,
            address auction,
            address executor,
            address dao,
            address cultureIndex,
            address revolutionPoints,
            address revolutionPointsEmitter,
            address maxHeap,
            address revolutionVotingPower
        ) = getAddresses(token);
        return
            DAOVersionInfo({
                revolutionToken: _safeGetVersion(revolutionToken),
                descriptor: _safeGetVersion(descriptor),
                auction: _safeGetVersion(auction),
                executor: _safeGetVersion(executor),
                dao: _safeGetVersion(dao),
                revolutionPoints: _safeGetVersion(revolutionPoints),
                cultureIndex: _safeGetVersion(cultureIndex),
                revolutionPointsEmitter: _safeGetVersion(revolutionPointsEmitter),
                maxHeap: _safeGetVersion(maxHeap),
                revolutionVotingPower: _safeGetVersion(revolutionVotingPower)
            });
    }

    function getLatestVersions() external view returns (DAOVersionInfo memory) {
        return
            DAOVersionInfo({
                revolutionToken: _safeGetVersion(revolutionTokenImpl),
                descriptor: _safeGetVersion(descriptorImpl),
                auction: _safeGetVersion(auctionImpl),
                executor: _safeGetVersion(executorImpl),
                dao: _safeGetVersion(daoImpl),
                cultureIndex: _safeGetVersion(cultureIndexImpl),
                revolutionPoints: _safeGetVersion(revolutionPointsImpl),
                revolutionPointsEmitter: _safeGetVersion(revolutionPointsEmitterImpl),
                maxHeap: _safeGetVersion(maxHeapImpl),
                revolutionVotingPower: _safeGetVersion(revolutionVotingPowerImpl)
            });
    }

    ///                                                          ///
    ///                         MANAGER UPGRADE                  ///
    ///                                                          ///

    /// @notice Ensures the caller is authorized to upgrade the contract
    /// @dev This function is called in `upgradeTo` & `upgradeToAndCall`
    /// @param _newImpl The new implementation address
    function _authorizeUpgrade(address _newImpl) internal override onlyOwner {}
}
