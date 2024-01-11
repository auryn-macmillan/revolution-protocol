// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { Test } from "forge-std/Test.sol";
import { CultureIndex } from "../../src/culture-index/CultureIndex.sol";
import { MockERC20 } from "../mock/MockERC20.sol";
import { ICultureIndex, ICultureIndexEvents } from "../../src/interfaces/ICultureIndex.sol";
import { RevolutionPoints } from "../../src/RevolutionPoints.sol";
import { CultureIndexTestSuite } from "./CultureIndex.t.sol";
import { ERC721CheckpointableUpgradeable } from "../../src/base/ERC721CheckpointableUpgradeable.sol";

/**
 * @title CultureIndexTest
 * @dev Test contract for CultureIndex
 */
contract CultureIndexVotingSignaturesTest is CultureIndexTestSuite {
    address offchainVoter;
    uint256 offchainVoterPk;

    address funVoterGuy;
    uint256 funVoterGuyPk;

    function setUp() public override {
        super.setUp();

        (address offchainVoter0, uint256 offchainVoterPk0) = makeAddrAndKey("offchainVoter");

        offchainVoter = offchainVoter0;
        offchainVoterPk = offchainVoterPk0;

        (address funVoterGuy0, uint256 funVoterGuyPk0) = makeAddrAndKey("funVoterGuy");

        funVoterGuy = funVoterGuy0;
        funVoterGuyPk = funVoterGuyPk0;
    }

    function getDomainSeparator() internal view virtual returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                    keccak256(abi.encodePacked(cultureIndex.name(), " CultureIndex")),
                    keccak256(bytes("1")),
                    block.chainid,
                    address(cultureIndex)
                )
            );
    }

    function testRevert_InvalidVoteForManyWithSigToAddress() public {
        uint256[] memory pieceIds = new uint256[](1);
        pieceIds[0] = createDefaultArtPiece();

        uint256 nonce = cultureIndex.nonces(offchainVoter);
        uint256 deadline = block.timestamp + 1 days;

        bytes32 voteHash = keccak256(
            abi.encode(cultureIndex.VOTE_TYPEHASH(), address(0), keccak256(abi.encodePacked(pieceIds)), nonce, deadline)
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", getDomainSeparator(), voteHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(offchainVoterPk, digest);

        vm.expectRevert(abi.encodeWithSignature("ADDRESS_ZERO()"));
        cultureIndex.voteForManyWithSig(address(0), pieceIds, deadline, v, r, s);
    }

    function test_VoteForManyWithSig() public {
        vm.stopPrank();

        //mint offchainVoterWeight to offchainVoter
        uint256 offchainVoterWeight = 100;
        vm.startPrank(address(revolutionPointsEmitter));
        revolutionPoints.mint(offchainVoter, offchainVoterWeight);
        vm.stopPrank();

        vm.startPrank(address(this));
        vm.roll(vm.getBlockNumber() + 1);

        uint256[] memory pieceIds = new uint256[](1);
        pieceIds[0] = createDefaultArtPiece();

        uint256 nonce = cultureIndex.nonces(offchainVoter);
        uint256 deadline = block.timestamp + 1 days;

        bytes32 voteHash = keccak256(
            abi.encode(
                cultureIndex.VOTE_TYPEHASH(),
                offchainVoter,
                keccak256(abi.encodePacked(pieceIds)),
                nonce,
                deadline
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", getDomainSeparator(), voteHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(offchainVoterPk, digest);

        uint256 beforeVoteWeight = cultureIndex.totalVoteWeights(pieceIds[0]);
        ICultureIndex.Vote memory voteBefore = cultureIndex.getVote(pieceIds[0], offchainVoter);

        //ensure voteBefore is empty
        assertEq(voteBefore.voterAddress, address(0));
        assertEq(voteBefore.weight, 0);

        vm.expectEmit(true, true, true, true);
        emit ICultureIndexEvents.VoteCast(
            pieceIds[0],
            offchainVoter,
            offchainVoterWeight,
            beforeVoteWeight + offchainVoterWeight
        );
        cultureIndex.voteForManyWithSig(offchainVoter, pieceIds, deadline, v, r, s);

        assertEq(cultureIndex.totalVoteWeights(pieceIds[0]), beforeVoteWeight + offchainVoterWeight);

        //make sure vote.voterAddress and vote.weight are set correctly
        ICultureIndex.Vote memory voteAfter = cultureIndex.getVote(pieceIds[0], offchainVoter);
        assertEq(voteAfter.voterAddress, offchainVoter);
        assertEq(voteAfter.weight, offchainVoterWeight);
    }

    function testRevert_SigExpired() public {
        uint256[] memory pieceIds = new uint256[](1);
        pieceIds[0] = createDefaultArtPiece();

        uint256 nonce = cultureIndex.nonces(offchainVoter);
        uint256 deadline = block.timestamp + 1 days;

        bytes32 voteHash = keccak256(
            abi.encode(
                cultureIndex.VOTE_TYPEHASH(),
                offchainVoter,
                keccak256(abi.encodePacked(pieceIds)),
                nonce,
                deadline
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", getDomainSeparator(), voteHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(offchainVoterPk, digest);

        vm.warp(deadline + 1);

        vm.expectRevert(abi.encodeWithSignature("SIGNATURE_EXPIRED()"));
        cultureIndex.voteForManyWithSig(offchainVoter, pieceIds, deadline, v, r, s);
    }

    function testRevert_InvalidNonce() public {
        uint256[] memory pieceIds = new uint256[](1);
        pieceIds[0] = createDefaultArtPiece();

        uint256 nonce = cultureIndex.nonces(offchainVoter) + 1;
        uint256 deadline = block.timestamp + 1 days;

        bytes32 voteHash = keccak256(abi.encode(cultureIndex.VOTE_TYPEHASH(), offchainVoter, nonce, deadline));

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", getDomainSeparator(), voteHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(offchainVoterPk, digest);

        vm.expectRevert(abi.encodeWithSignature("INVALID_SIGNATURE()"));
        cultureIndex.voteForManyWithSig(offchainVoter, pieceIds, deadline, v, r, s);
    }

    function testRevert_InvalidReplay() public {
        vm.stopPrank();
        // mint offchainVoterWeight to offchainVoter
        uint256 offchainVoterWeight = 100;
        vm.startPrank(address(revolutionPointsEmitter));
        revolutionPoints.mint(offchainVoter, offchainVoterWeight);

        vm.roll(vm.getBlockNumber() + 1);

        uint256[] memory pieceIds = new uint256[](1);
        pieceIds[0] = createDefaultArtPiece();

        uint256 nonce = cultureIndex.nonces(offchainVoter);
        uint256 deadline = block.timestamp + 1 days;

        vm.startPrank(address(offchainVoter));
        bytes32 voteHash = keccak256(
            abi.encode(
                cultureIndex.VOTE_TYPEHASH(),
                offchainVoter,
                keccak256(abi.encodePacked(pieceIds)),
                nonce,
                deadline
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", getDomainSeparator(), voteHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(offchainVoterPk, digest);

        cultureIndex.voteForManyWithSig(offchainVoter, pieceIds, deadline, v, r, s);

        vm.expectRevert(abi.encodeWithSignature("INVALID_SIGNATURE()"));
        cultureIndex.voteForManyWithSig(offchainVoter, pieceIds, deadline, v, r, s);
    }

    function testRevert_InvalidSigner() public {
        uint256[] memory pieceIds = new uint256[](1);
        pieceIds[0] = createDefaultArtPiece();

        (address notoffchainVoter, uint256 notoffchainVoterPk) = makeAddrAndKey("notBuilder");

        uint256 nonce = cultureIndex.nonces(offchainVoter);
        uint256 deadline = block.timestamp + 1 days;

        bytes32 voteHash = keccak256(
            abi.encode(
                cultureIndex.VOTE_TYPEHASH(),
                notoffchainVoter,
                keccak256(abi.encodePacked(pieceIds)),
                nonce,
                deadline
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", getDomainSeparator(), voteHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(notoffchainVoterPk, digest);

        vm.expectRevert(abi.encodeWithSignature("INVALID_SIGNATURE()"));
        cultureIndex.voteForManyWithSig(offchainVoter, pieceIds, deadline, v, r, s);
    }

    function testRevert_InvalidVotes() public {
        vm.stopPrank();
        //mint tokens finally
        vm.startPrank(address(revolutionPointsEmitter));
        revolutionPoints.mint(offchainVoter, 100);

        vm.roll(vm.getBlockNumber() + 1);

        uint256[] memory pieceIds = new uint256[](1);
        pieceIds[0] = createDefaultArtPiece();

        vm.roll(vm.getBlockNumber() + 2);

        uint256 nonce = cultureIndex.nonces(offchainVoter);
        uint256 deadline = block.timestamp + 1 days;

        uint256[] memory invalidPieceIds = new uint256[](1);
        invalidPieceIds[0] = pieceIds[0] + 1;

        bytes32 voteHash = keccak256(
            abi.encode(
                cultureIndex.VOTE_TYPEHASH(),
                offchainVoter,
                keccak256(abi.encodePacked(invalidPieceIds)),
                nonce,
                deadline
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", getDomainSeparator(), voteHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(offchainVoterPk, digest);

        vm.expectRevert(abi.encodeWithSignature("INVALID_PIECE_ID()"));
        cultureIndex.voteForManyWithSig(offchainVoter, invalidPieceIds, deadline, v, r, s);

        // vote correctly but expect "Weight must be greater than minVoteWeight"
        nonce = cultureIndex.nonces(funVoterGuy);
        deadline = block.timestamp + 1 days;

        voteHash = keccak256(
            abi.encode(
                cultureIndex.VOTE_TYPEHASH(),
                funVoterGuy,
                keccak256(abi.encodePacked(pieceIds)),
                nonce,
                deadline
            )
        );

        digest = keccak256(abi.encodePacked("\x19\x01", getDomainSeparator(), voteHash));

        (v, r, s) = vm.sign(funVoterGuyPk, digest);

        vm.expectRevert(abi.encodeWithSignature("WEIGHT_TOO_LOW()"));
        cultureIndex.voteForManyWithSig(funVoterGuy, pieceIds, deadline, v, r, s);

        //vote with offchainVoter
        nonce = cultureIndex.nonces(offchainVoter);
        deadline = block.timestamp + 1 days;

        voteHash = keccak256(
            abi.encode(
                cultureIndex.VOTE_TYPEHASH(),
                offchainVoter,
                keccak256(abi.encodePacked(pieceIds)),
                nonce,
                deadline
            )
        );

        digest = keccak256(abi.encodePacked("\x19\x01", getDomainSeparator(), voteHash));

        (v, r, s) = vm.sign(offchainVoterPk, digest);

        cultureIndex.voteForManyWithSig(offchainVoter, pieceIds, deadline, v, r, s);

        //vote again with same address and expect "Already voted"
        nonce = cultureIndex.nonces(offchainVoter);
        deadline = block.timestamp + 1 days;

        voteHash = keccak256(
            abi.encode(
                cultureIndex.VOTE_TYPEHASH(),
                offchainVoter,
                keccak256(abi.encodePacked(pieceIds)),
                nonce,
                deadline
            )
        );

        digest = keccak256(abi.encodePacked("\x19\x01", getDomainSeparator(), voteHash));

        (v, r, s) = vm.sign(offchainVoterPk, digest);

        vm.expectRevert(abi.encodeWithSignature("ALREADY_VOTED()"));
        cultureIndex.voteForManyWithSig(offchainVoter, pieceIds, deadline, v, r, s);

        // dropTopVotedPiece
        vm.startPrank(address(revolutionToken));
        cultureIndex.dropTopVotedPiece();

        // vote again with different address and expect "Piece has already been dropped"
        (address notoffchainVoter, uint256 notoffchainVoterPk) = makeAddrAndKey("notBuilder");

        nonce = cultureIndex.nonces(notoffchainVoter);
        deadline = block.timestamp + 1 days;

        voteHash = keccak256(
            abi.encode(
                cultureIndex.VOTE_TYPEHASH(),
                notoffchainVoter,
                keccak256(abi.encodePacked(pieceIds)),
                nonce,
                deadline
            )
        );

        digest = keccak256(abi.encodePacked("\x19\x01", getDomainSeparator(), voteHash));

        (v, r, s) = vm.sign(notoffchainVoterPk, digest);

        vm.expectRevert(abi.encodeWithSignature("ALREADY_DROPPED()"));
        cultureIndex.voteForManyWithSig(notoffchainVoter, pieceIds, deadline, v, r, s);
    }
}
