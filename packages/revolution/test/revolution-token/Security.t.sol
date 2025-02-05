// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { Test } from "forge-std/Test.sol";
import { RevolutionToken } from "../../src/RevolutionToken.sol";
import { ICultureIndex, ICultureIndexEvents } from "../../src/interfaces/ICultureIndex.sol";
import { IRevolutionToken } from "../../src/interfaces/IRevolutionToken.sol";
import { IDescriptorMinimal } from "../../src/interfaces/IDescriptorMinimal.sol";
import { ICultureIndex } from "../../src/interfaces/ICultureIndex.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { CultureIndex } from "../../src/culture-index/CultureIndex.sol";
import { MockERC20 } from "../mock/MockERC20.sol";
import { Descriptor } from "../../src/Descriptor.sol";
import "../utils/Base64Decode.sol";
import "../utils/JsmnSolLib.sol";
import { RevolutionTokenTestSuite } from "./RevolutionToken.t.sol";

/// @title RevolutionTokenTest
/// @dev The test suite for the RevolutionToken contract
contract TokenSecurityTest is RevolutionTokenTestSuite {
    /// @dev Tests the creator array limit for minting
    function testCreatorArrayLimit() public {
        // Create an art piece with creators more than the limit (assuming the limit is 100)
        ICultureIndex.CreatorBps[] memory creators = new ICultureIndex.CreatorBps[](101);
        for (uint i = 0; i < 101; i++) {
            creators[i] = ICultureIndex.CreatorBps({
                creator: address(uint160(i + 1)), // Just a series of different addresses
                bps: 10 // Arbitrary basis points for each creator
            });
        }

        ICultureIndex.ArtPieceMetadata memory metadata = ICultureIndex.ArtPieceMetadata({
            name: "Overpopulated",
            description: "An art piece with too many creators",
            mediaType: ICultureIndex.MediaType.IMAGE,
            image: "ipfs://overpopulated",
            text: "",
            animationUrl: ""
        });

        // Attempt to create the piece and expect it to fail due to too many creators
        bool exceededCreatorLimit = false;
        try cultureIndex.createPiece(metadata, creators) {
            fail("Should fail: creator array exceeds the limit");
        } catch {
            exceededCreatorLimit = true;
        }

        assertTrue(exceededCreatorLimit, "Should not allow creation of a piece with too many creators");
    }

    /// @dev Tests the reentrancy guard on the mint function
    function testReentrancyOnMint() public {
        createDefaultArtPiece();

        // Simulate a reentrancy attack by calling mint within a call to mint
        address attacker = address(new ReentrancyAttackContract(address(revolutionToken)));
        vm.startPrank(attacker);

        bool reentrancyOccurred = false;
        try ReentrancyAttackContract(attacker).attack() {
            fail("Should fail: reentrancy should be guarded");
        } catch {
            reentrancyOccurred = true;
        }

        vm.stopPrank();

        assertTrue(reentrancyOccurred, "Reentrancy guard should prevent minting in the same call stack");
    }

    /// @dev Tests approval checks for transfer functions
    function testApprovalChecks() public {
        vm.stopPrank();
        vm.startPrank(address(auction));

        createDefaultArtPiece();
        vm.roll(vm.getBlockNumber() + 1);

        uint256 tokenId = revolutionToken.mint();

        address spender = address(0xABC);
        address to = address(0xDEF);

        // Attempt to transfer without approval as owner
        revolutionToken.transferFrom(address(auction), to, tokenId);

        vm.startPrank(to);

        // Approve spender and attempt to transfer as spender
        revolutionToken.approve(spender, tokenId);
        vm.stopPrank();

        vm.startPrank(spender);

        bool transferWithApprovalFailed = false;
        try revolutionToken.transferFrom(to, address(this), tokenId) {
            // Transfer should succeed
        } catch {
            transferWithApprovalFailed = true;
        }
        vm.stopPrank();

        assertFalse(transferWithApprovalFailed, "Transfer with approval should succeed");
    }

    function testPrivilegeEscalation() public {
        vm.stopPrank();
        address unauthorizedAddress = address(0xDead);
        vm.startPrank(unauthorizedAddress);

        // These should all fail when called by an unauthorized address
        vm.expectRevert();
        revolutionToken.setMinter(unauthorizedAddress);

        vm.expectRevert();
        revolutionToken.lockMinter();

        vm.expectRevert();
        revolutionToken.setDescriptor(IDescriptorMinimal(unauthorizedAddress));

        vm.expectRevert();
        revolutionToken.lockDescriptor();

        vm.expectRevert();
        revolutionToken.setCultureIndex(ICultureIndex(unauthorizedAddress));

        vm.expectRevert();
        revolutionToken.lockCultureIndex();
    }

    function testReentrancyOtherFunctions() public {
        createDefaultArtPiece();
        address attacker = address(new ReentrancyAttackContractGeneral(address(revolutionToken)));

        // Simulate a reentrancy attack for burn
        vm.expectRevert(abi.encodeWithSignature("NOT_MINTER()"));
        ReentrancyAttackContractGeneral(attacker).attackBurn();
    }

    function testBasisPointsSum() public {
        bool reverted = false;

        // Total basis points not equal to 10000 should revert
        ICultureIndex.CreatorBps[] memory creators = new ICultureIndex.CreatorBps[](2);
        creators[0] = ICultureIndex.CreatorBps({ creator: address(0x1), bps: 5000 });
        creators[1] = ICultureIndex.CreatorBps({ creator: address(0x2), bps: 4000 });

        try cultureIndex.createPiece(createDefaultMetadata(), creators) {
            fail("Should fail: Total basis points do not sum up to 10000");
        } catch {
            reverted = true;
        }
        assertTrue(reverted, "Transaction should revert if total basis points do not sum up to 10000");
    }

    function testZeroAddressInCreatorArray() public {
        bool reverted = false;

        // Creator array containing a zero address should revert
        ICultureIndex.CreatorBps[] memory creators = new ICultureIndex.CreatorBps[](1);
        creators[0] = ICultureIndex.CreatorBps({ creator: address(0), bps: 10000 });

        try cultureIndex.createPiece(createDefaultMetadata(), creators) {
            fail("Should fail: Creator array contains zero address");
        } catch {
            reverted = true;
        }
        assertTrue(reverted, "Transaction should revert if creator array contains zero address");
    }

    function testEventEmission() public {
        address creatorAddress = address(0x1);
        ICultureIndex.CreatorBps[] memory creators = new ICultureIndex.CreatorBps[](1);
        creators[0] = ICultureIndex.CreatorBps({ creator: creatorAddress, bps: 10_000 });

        // Check that the PieceCreated event was emitted with correct parameters
        vm.expectEmit(true, true, true, true);
        emit ICultureIndexEvents.PieceCreated(
            0,
            address(executor),
            ICultureIndex.ArtPieceMetadata({
                name: "Mona Lisa",
                description: "A masterpiece",
                image: "ipfs://legends",
                animationUrl: "",
                text: "",
                mediaType: ICultureIndex.MediaType.IMAGE
            }),
            creators
        );

        createDefaultArtPiece();
    }

    function testFunctionalityUnderMaximumLoad() public {
        bool reverted = false;

        // Create an art piece with the maximum allowed number of creators
        ICultureIndex.CreatorBps[] memory creators = new ICultureIndex.CreatorBps[](cultureIndex.MAX_NUM_CREATORS());

        for (uint256 i = 0; i < creators.length; i++) {
            creators[i] = ICultureIndex.CreatorBps({
                creator: address(uint160(i + 1)),
                bps: 10_000 / cultureIndex.MAX_NUM_CREATORS()
            });
        }

        try cultureIndex.createPiece(createDefaultMetadata(), creators) {
            // This should succeed if under maximum load
        } catch {
            reverted = true;
            fail("Should not fail: creator array is at maximum allowed length");
        }
        assertFalse(reverted, "Should handle the maximum number of creators without reverting");
    }

    /// @dev Tests the _mintTo function for failure in dropTopVotedPiece and ensures verbId is not incremented
    function testMintToDropTopVotedPieceFailure() public {
        // Create a default art piece to have something to mint
        createDefaultArtPiece();
        vm.roll(vm.getBlockNumber() + 1);

        // Mock the CultureIndex to simulate dropTopVotedPiece failure
        address cultureIndexMock = address(new CultureIndexMock());
        revolutionToken.setCultureIndex(ICultureIndex(cultureIndexMock));

        // Store current verbId before test
        uint256 supplyBefore = 0;

        bool dropTopVotedPieceFailed = false;
        try revolutionToken.mint() {
            fail("dropTopVotedPiece failure should have caused _mintTo to revert");
        } catch {
            dropTopVotedPieceFailed = true;
        }

        // Verify verbId has not incremented after failure
        uint256 totalSupply = revolutionToken.totalSupply();
        assertEq(supplyBefore, totalSupply, "verbId should not increment after failure");

        assertTrue(dropTopVotedPieceFailed, "_mintTo should revert if dropTopVotedPiece fails");
    }
}

// Helper mock contract to simulate reentrancy for other functions
contract ReentrancyAttackContractGeneral {
    RevolutionToken private revolutionToken;

    constructor(address _revolutionToken) {
        revolutionToken = RevolutionToken(_revolutionToken);
    }

    function attackBurn() public {
        uint256 tokenId = revolutionToken.mint();
        revolutionToken.burn(tokenId); // Attempt to re-enter here
    }

    // Implement fallback or receive function that calls burn again
}

// Mock CultureIndex to simulate failure in dropTopVotedPiece
contract CultureIndexMock {
    function dropTopVotedPiece() external pure returns (ICultureIndex.ArtPiece memory) {
        revert("Mocked failure");
    }

    // Implement other methods of ICultureIndex as needed, potentially as no-ops
}

// Helper mock contract to simulate reentrancy attack
contract ReentrancyAttackContract {
    RevolutionToken private revolutionToken;

    constructor(address _revolutionToken) {
        revolutionToken = RevolutionToken(_revolutionToken);
    }

    function attack() public {
        revolutionToken.mint();
        revolutionToken.mint(); // This should fail if reentrancy guard is in place
    }
}
