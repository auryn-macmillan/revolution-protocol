// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { Test } from "forge-std/Test.sol";

import { IRevolutionBuilder } from "../src/interfaces/IRevolutionBuilder.sol";
import { RevolutionBuilder } from "../src/builder/RevolutionBuilder.sol";
import { RevolutionToken, IRevolutionToken } from "../src/RevolutionToken.sol";
import { Descriptor } from "../src/Descriptor.sol";
import { IAuctionHouse, AuctionHouse } from "../src/AuctionHouse.sol";
import { RevolutionDAOLogicV1 } from "../src/governance/RevolutionDAOLogicV1.sol";
import { DAOExecutor } from "../src/governance/DAOExecutor.sol";
import { CultureIndex } from "../src/culture-index/CultureIndex.sol";
import { RevolutionPoints } from "../src/RevolutionPoints.sol";
import { RevolutionVotingPower } from "../src/RevolutionVotingPower.sol";
import { RevolutionPointsEmitter } from "../src/RevolutionPointsEmitter.sol";
import { MaxHeap } from "../src/culture-index/MaxHeap.sol";
import { RevolutionDAOStorageV1 } from "../src/governance/RevolutionDAOInterfaces.sol";
import { RevolutionProtocolRewards } from "@cobuild/protocol-rewards/src/RevolutionProtocolRewards.sol";
import { RevolutionBuilderTypesV1 } from "../src/builder/types/RevolutionBuilderTypesV1.sol";

import { ERC1967Proxy } from "../src/libs/proxy/ERC1967Proxy.sol";
import { MockERC721 } from "./mock/MockERC721.sol";
import { MockERC1155 } from "./mock/MockERC1155.sol";
import { MockWETH } from "./mock/MockWETH.sol";

contract RevolutionBuilderTest is Test {
    ///                                                          ///
    ///                          BASE SETUP                      ///
    ///                                                          ///

    IRevolutionBuilder internal manager;

    address internal managerImpl0;
    address internal managerImpl;
    address internal revolutionTokenImpl;
    address internal descriptorImpl;
    address internal auctionImpl;
    address internal executorImpl;
    address internal daoImpl;
    address internal revolutionPointsImpl;
    address internal revolutionPointsEmitterImpl;
    address internal cultureIndexImpl;
    address internal maxHeapImpl;
    address internal revolutionVotingPowerImpl;

    address internal nounsDAO;
    address internal revolutionDAO;
    address internal creatorsAddress;
    address internal founder;
    address internal founder2;
    address internal weth;
    address internal protocolRewards;
    address internal vrgdac;

    MockERC721 internal mock721;
    MockERC1155 internal mock1155;

    function setUp() public virtual {
        weth = address(new MockWETH());

        mock721 = new MockERC721();
        mock1155 = new MockERC1155();

        nounsDAO = vm.addr(0xA11CE);
        revolutionDAO = vm.addr(0xB0B);

        protocolRewards = address(new RevolutionProtocolRewards());

        founder = vm.addr(0xCAB);
        founder2 = vm.addr(0xDAD);

        creatorsAddress = vm.addr(0xCAFEBABE);

        vm.label(revolutionDAO, "REVOLUTION_DAO");
        vm.label(nounsDAO, "NOUNS_DAO");

        vm.label(founder, "FOUNDER");
        vm.label(founder2, "FOUNDER_2");

        managerImpl0 = address(
            new RevolutionBuilder(
                address(0),
                address(0),
                address(0),
                address(0),
                address(0),
                address(0),
                address(0),
                address(0),
                address(0),
                address(0)
            )
        );
        manager = RevolutionBuilder(
            address(new ERC1967Proxy(managerImpl0, abi.encodeWithSignature("initialize(address)", revolutionDAO)))
        );

        revolutionTokenImpl = address(new RevolutionToken(address(manager)));
        descriptorImpl = address(new Descriptor(address(manager)));
        auctionImpl = address(new AuctionHouse(address(manager)));
        executorImpl = address(new DAOExecutor(address(manager)));
        daoImpl = address(new RevolutionDAOLogicV1(address(manager)));
        revolutionPointsImpl = address(new RevolutionPoints(address(manager)));
        revolutionPointsEmitterImpl = address(
            new RevolutionPointsEmitter(address(manager), address(protocolRewards), revolutionDAO)
        );
        cultureIndexImpl = address(new CultureIndex(address(manager)));
        maxHeapImpl = address(new MaxHeap(address(manager)));
        revolutionVotingPowerImpl = address(new RevolutionVotingPower(address(manager)));

        managerImpl = address(
            new RevolutionBuilder(
                revolutionTokenImpl,
                descriptorImpl,
                auctionImpl,
                executorImpl,
                daoImpl,
                cultureIndexImpl,
                revolutionPointsImpl,
                revolutionPointsEmitterImpl,
                maxHeapImpl,
                revolutionVotingPowerImpl
            )
        );

        vm.prank(revolutionDAO);
        manager.upgradeTo(managerImpl);
    }

    ///                                                          ///
    ///                     DAO CUSTOMIZATION UTILS              ///
    ///                                                          ///

    IRevolutionBuilder.RevolutionTokenParams internal revolutionTokenParams;
    IRevolutionBuilder.AuctionParams internal auctionParams;
    IRevolutionBuilder.GovParams internal govParams;
    IRevolutionBuilder.CultureIndexParams internal cultureIndexParams;
    IRevolutionBuilder.RevolutionPointsParams internal revolutionPointsParams;
    IRevolutionBuilder.RevolutionVotingPowerParams internal revolutionVotingPowerParams;

    function setMockRevolutionTokenParams() internal virtual {
        setRevolutionTokenParams("Mock Token", "MOCK", "Qmew7TdyGnj6YRUjQR68sUJN3239MYXRD8uxowxF6rGK8j", "Mock");
    }

    function setRevolutionTokenParams(
        string memory _name,
        string memory _symbol,
        string memory _contractURI,
        string memory _tokenNamePrefix
    ) internal virtual {
        revolutionTokenParams = IRevolutionBuilder.RevolutionTokenParams({
            name: _name,
            symbol: _symbol,
            contractURIHash: _contractURI,
            tokenNamePrefix: _tokenNamePrefix
        });
    }

    function setMockRevolutionVotingPowerParams() internal virtual {
        setRevolutionVotingPowerParams(1000, 1);
    }

    function setRevolutionVotingPowerParams(
        uint256 _revolutionTokenVoteWeight,
        uint256 _revolutionPointsVoteWeight
    ) internal virtual {
        revolutionVotingPowerParams = IRevolutionBuilder.RevolutionVotingPowerParams({
            revolutionTokenVoteWeight: _revolutionTokenVoteWeight,
            revolutionPointsVoteWeight: _revolutionPointsVoteWeight
        });
    }

    function setMockAuctionParams() internal virtual {
        setAuctionParams(15 minutes, 1 ether, 24 hours, 5, 1000, 1000, 1000);
    }

    function setAuctionParams(
        uint256 _timeBuffer,
        uint256 _reservePrice,
        uint256 _duration,
        uint8 _minBidIncrementPercentage,
        uint256 _creatorRateBps,
        uint256 _entropyRateBps,
        uint256 _minCreatorRateBps
    ) internal virtual {
        auctionParams = IRevolutionBuilder.AuctionParams({
            timeBuffer: _timeBuffer,
            reservePrice: _reservePrice,
            duration: _duration,
            minBidIncrementPercentage: _minBidIncrementPercentage,
            creatorRateBps: _creatorRateBps,
            entropyRateBps: _entropyRateBps,
            minCreatorRateBps: _minCreatorRateBps
        });
    }

    function setMockGovParams() internal virtual {
        setGovParams(2 days, 1 seconds, 1 weeks, 50, founder, 1000, 1000, 1000, "Vrbs DAO");
    }

    function setGovParams(
        uint256 _timelockDelay,
        uint256 _votingDelay,
        uint256 _votingPeriod,
        uint256 _proposalThresholdBPS,
        address _vetoer,
        uint16 _minQuorumVotesBPS,
        uint16 _maxQuorumVotesBPS,
        uint16 _quorumCoefficient,
        string memory _daoName
    ) internal virtual {
        govParams = IRevolutionBuilder.GovParams({
            timelockDelay: _timelockDelay,
            votingDelay: _votingDelay,
            votingPeriod: _votingPeriod,
            proposalThresholdBPS: _proposalThresholdBPS,
            vetoer: _vetoer,
            dynamicQuorumParams: RevolutionDAOStorageV1.DynamicQuorumParams({
                minQuorumVotesBPS: _minQuorumVotesBPS,
                maxQuorumVotesBPS: _maxQuorumVotesBPS,
                quorumCoefficient: _quorumCoefficient
            }),
            daoName: _daoName
        });
    }

    function setMockCultureIndexParams() internal virtual {
        setCultureIndexParams("Vrbs", "Our community Vrbs. Must be 32x32.", 100 * 1e18, 1000, 0);
    }

    function setCultureIndexParams(
        string memory _name,
        string memory _description,
        uint256 _revolutionTokenVoteWeight,
        uint256 _quorumVotesBPS,
        uint256 _minVoteWeight
    ) internal virtual {
        cultureIndexParams = IRevolutionBuilder.CultureIndexParams({
            name: _name,
            description: _description,
            revolutionTokenVoteWeight: _revolutionTokenVoteWeight,
            quorumVotesBPS: _quorumVotesBPS,
            minVoteWeight: _minVoteWeight
        });
    }

    function setMockPointsParams() internal virtual {
        setPointsParams("Mock Token", "MOCK");
    }

    function setPointsParams(string memory _name, string memory _symbol) internal virtual {
        revolutionPointsParams = revolutionPointsParams = IRevolutionBuilder.RevolutionPointsParams({
            emitterParams: revolutionPointsParams.emitterParams,
            tokenParams: IRevolutionBuilder.PointsTokenParams({ name: _name, symbol: _symbol })
        });
    }

    function setMockPointsEmitterParams() internal virtual {
        setPointsEmitterParams(1 ether, 1e18 / 10, 1_000 * 1e18, creatorsAddress);
    }

    function setPointsEmitterParams(
        int256 _targetPrice,
        int256 _priceDecayPercent,
        int256 _tokensPerTimeUnit,
        address _creatorsAddress
    ) internal virtual {
        revolutionPointsParams = IRevolutionBuilder.RevolutionPointsParams({
            tokenParams: revolutionPointsParams.tokenParams,
            emitterParams: IRevolutionBuilder.PointsEmitterParams({
                vrgdaParams: IRevolutionBuilder.VRGDAParams({
                    targetPrice: _targetPrice,
                    priceDecayPercent: _priceDecayPercent,
                    tokensPerTimeUnit: _tokensPerTimeUnit
                }),
                creatorParams: IRevolutionBuilder.PointsEmitterCreatorParams({
                    creatorRateBps: 1000,
                    entropyRateBps: 4_000
                }),
                creatorsAddress: _creatorsAddress
            })
        });
    }

    ///                                                          ///
    ///                       DAO DEPLOY UTILS                   ///
    ///                                                          ///

    RevolutionToken internal revolutionToken;
    Descriptor internal descriptor;
    AuctionHouse internal auction;
    DAOExecutor internal executor;
    RevolutionDAOLogicV1 internal dao;
    CultureIndex internal cultureIndex;
    RevolutionPoints internal revolutionPoints;
    RevolutionPointsEmitter internal revolutionPointsEmitter;
    MaxHeap internal maxHeap;
    RevolutionVotingPower internal revolutionVotingPower;

    function setMockParams() internal virtual {
        setMockRevolutionTokenParams();
        setMockAuctionParams();
        setMockGovParams();
        setMockCultureIndexParams();
        setMockPointsParams();
        setMockPointsEmitterParams();
        setMockRevolutionVotingPowerParams();
    }

    function deployMock() internal virtual {
        deploy(
            founder,
            weth,
            revolutionTokenParams,
            auctionParams,
            govParams,
            cultureIndexParams,
            revolutionPointsParams,
            revolutionVotingPowerParams
        );
    }

    function deploy(
        address _initialOwner,
        address _weth,
        IRevolutionBuilder.RevolutionTokenParams memory _RevolutionTokenParams,
        IRevolutionBuilder.AuctionParams memory _auctionParams,
        IRevolutionBuilder.GovParams memory _govParams,
        IRevolutionBuilder.CultureIndexParams memory _cultureIndexParams,
        IRevolutionBuilder.RevolutionPointsParams memory _pointsParams,
        IRevolutionBuilder.RevolutionVotingPowerParams memory _revolutionVotingPowerParams
    ) internal virtual {
        RevolutionBuilderTypesV1.DAOAddresses memory _addresses = manager.deploy(
            _initialOwner,
            _weth,
            _RevolutionTokenParams,
            _auctionParams,
            _govParams,
            _cultureIndexParams,
            _pointsParams,
            _revolutionVotingPowerParams
        );

        revolutionToken = RevolutionToken(_addresses.revolutionToken);
        descriptor = Descriptor(_addresses.descriptor);
        auction = AuctionHouse(_addresses.auction);
        executor = DAOExecutor(payable(_addresses.executor));
        dao = RevolutionDAOLogicV1(payable(_addresses.dao));
        cultureIndex = CultureIndex(_addresses.cultureIndex);
        revolutionPoints = RevolutionPoints(_addresses.revolutionPoints);
        revolutionPointsEmitter = RevolutionPointsEmitter(_addresses.revolutionPointsEmitter);
        maxHeap = MaxHeap(_addresses.maxHeap);
        revolutionVotingPower = RevolutionVotingPower(_addresses.revolutionVotingPower);

        vm.label(address(revolutionToken), "ERC721TOKEN");
        vm.label(address(descriptor), "DESCRIPTOR");
        vm.label(address(auction), "AUCTION");
        vm.label(address(executor), "EXECUTOR");
        vm.label(address(dao), "DAO");
        vm.label(address(cultureIndex), "CULTURE_INDEX");
        vm.label(address(revolutionPoints), "Points");
        vm.label(address(revolutionPointsEmitter), "POINTS_EMITTER");
        vm.label(address(maxHeap), "MAX_HEAP");
        vm.label(address(revolutionVotingPower), "VOTING_POWER");
    }

    ///                                                          ///
    ///                           USER UTILS                     ///
    ///                                                          ///

    function createUser(uint256 _privateKey) internal virtual returns (address) {
        return vm.addr(_privateKey);
    }

    address[] internal otherUsers;

    function createUsers(uint256 _numUsers, uint256 _balance) internal virtual {
        otherUsers = new address[](_numUsers);

        unchecked {
            for (uint256 i; i < _numUsers; ++i) {
                address user = vm.addr(i + 1);

                vm.deal(user, _balance);

                otherUsers[i] = user;
            }
        }
    }

    function createTokens(uint256 _numTokens) internal {
        uint256 reservePrice = auction.reservePrice();
        uint256 duration = auction.duration();

        unchecked {
            for (uint256 i; i < _numTokens; ++i) {
                (uint256 tokenId, , , , , ) = auction.auction();

                vm.prank(otherUsers[i]);
                auction.createBid{ value: reservePrice }(tokenId, otherUsers[i]);

                vm.warp(block.timestamp + duration);

                auction.settleCurrentAndCreateNewAuction();
            }
        }
    }

    function createVoters(uint256 _numVoters, uint256 _balance) internal {
        createUsers(_numVoters, _balance);

        createTokens(_numVoters);
    }
}
