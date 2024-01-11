// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { Test } from "forge-std/Test.sol";
import { unsafeWadDiv, toDaysWadUnsafe } from "../../src/libs/SignedWadMath.sol";
import { RevolutionPointsEmitter } from "../../src/RevolutionPointsEmitter.sol";
import { IRevolutionPointsEmitter } from "../../src/interfaces/IRevolutionPointsEmitter.sol";
import { RevolutionPoints } from "../../src/RevolutionPoints.sol";
import { RevolutionProtocolRewards } from "@cobuild/protocol-rewards/src/RevolutionProtocolRewards.sol";
import { wadDiv } from "../../src/libs/SignedWadMath.sol";
import { IRevolutionBuilder } from "../../src/interfaces/IRevolutionBuilder.sol";
import { PointsEmitterTest } from "./PointsEmitter.t.sol";
import { IRevolutionPoints } from "../../src/interfaces/IRevolutionPoints.sol";
import { ERC1967Proxy } from "../../src/libs/proxy/ERC1967Proxy.sol";
import { console2 } from "forge-std/console2.sol";

contract PointsEmitterBasicTest is PointsEmitterTest {
    // test multiple payouts
    function testPercentagePayouts(uint firstBps) public {
        vm.assume(firstBps < 10000);
        vm.assume(firstBps > 0);
        vm.startPrank(address(0));

        uint creatorRateBps = revolutionPointsEmitter.creatorRateBps();
        uint entropyRateBps = revolutionPointsEmitter.entropyRateBps();

        address[] memory recipients = new address[](2);
        recipients[0] = address(1);
        recipients[1] = address(2);

        uint256[] memory bps = new uint256[](2);
        bps[0] = firstBps;
        bps[1] = 10_000 - firstBps;

        // estimate tokens to be emitted
        uint msgValueRemaining = 1e18 - revolutionPointsEmitter.computeTotalReward(1e18);
        uint creatorsShare = (msgValueRemaining * creatorRateBps) / 10_000;
        uint buyersShare = msgValueRemaining - creatorsShare;
        uint creatorsGovernancePayment = creatorsShare - (creatorsShare * entropyRateBps) / 10_000;
        int expectedCreatorsAmount = revolutionPointsEmitter.getTokenQuoteForEther(creatorsGovernancePayment);

        int expectedBuyerAmount = getTokenQuoteForEtherHelper(buyersShare, expectedCreatorsAmount);

        int expectedAmount = expectedCreatorsAmount + expectedBuyerAmount;

        revolutionPointsEmitter.buyToken{ value: 1e18 }(
            recipients,
            bps,
            IRevolutionPointsEmitter.ProtocolRewardAddresses({
                builder: address(0),
                purchaseReferral: address(0),
                deployer: address(0)
            })
        );
        //assert address balances are correct
        //multiply bps by expectedBuyerAmount and assert
        assertEq(
            revolutionPointsEmitter.balanceOf(address(1)),
            (firstBps * uint256(expectedBuyerAmount)) / 10_000,
            "First recipient should have correct balance"
        );
        assertEq(
            revolutionPointsEmitter.balanceOf(address(2)),
            ((10_000 - firstBps) * uint256(expectedBuyerAmount)) / 10_000,
            "Second recipient should have correct balance"
        );

        // //assert owner balance is correct
        assertEq(
            address(revolutionPointsEmitter.owner()).balance,
            1e18 - revolutionPointsEmitter.computeTotalReward(1e18) - (creatorsShare * entropyRateBps) / 10_000,
            "Owner should have payment - totalReward in balance"
        );
    }

    //if buyToken is called with mismatched length arrays, then it should revert with PARALLEL_ARRAYS_REQUIRED()
    function test_revertMismatchedLengthArrays() public {
        vm.startPrank(address(0));

        address[] memory recipients = new address[](2);
        recipients[0] = address(1);
        recipients[1] = address(2);

        uint256[] memory bps = new uint256[](1);
        bps[0] = 10_000;

        vm.expectRevert(abi.encodeWithSignature("PARALLEL_ARRAYS_REQUIRED()"));
        revolutionPointsEmitter.buyToken{ value: 1e18 }(
            recipients,
            bps,
            IRevolutionPointsEmitter.ProtocolRewardAddresses({
                builder: address(1),
                purchaseReferral: address(1),
                deployer: address(0)
            })
        );
    }

    // Test to ensure the total basis points add up to 100%
    function testTotalBasisPoints() public {
        vm.startPrank(address(0));

        uint256 creatorRateBps = revolutionPointsEmitter.creatorRateBps();
        uint256 entropyRateBps = revolutionPointsEmitter.entropyRateBps();

        address[] memory recipients = new address[](2);
        recipients[0] = address(1);
        recipients[1] = address(2);

        // Test case with correct total of 10,000 basis points (100%)
        uint256[] memory correctBps = new uint256[](2);
        correctBps[0] = 5000; // 50%
        correctBps[1] = 5000; // 50%

        uint256 msgValueRemaining = 1e18 - revolutionPointsEmitter.computeTotalReward(1e18);
        // Calculate share of purchase amount reserved for buyers
        uint256 buyersShare = msgValueRemaining - ((msgValueRemaining * creatorRateBps) / 10_000);

        // Calculate ether directly sent to creators
        uint256 creatorsDirectPayment = (msgValueRemaining * creatorRateBps * entropyRateBps) / 10_000 / 10_000;

        // Calculate ether spent on creators governance tokens
        uint256 creatorsGovernancePayment = ((msgValueRemaining * creatorRateBps) / 10_000) - creatorsDirectPayment;

        emit log_uint(buyersShare);
        emit log_uint(creatorsGovernancePayment);

        int expectedCreatorsAmount = revolutionPointsEmitter.getTokenQuoteForEther(creatorsGovernancePayment);

        int expectedBuyerAmount = getTokenQuoteForEtherHelper(buyersShare, expectedCreatorsAmount);

        int expectedAmount = expectedCreatorsAmount + expectedBuyerAmount;

        assertGt(expectedAmount, 0, "Token purchase should have a positive amount");

        // Attempting a valid token purchase
        uint emittedWad = revolutionPointsEmitter.buyToken{ value: 1e18 }(
            recipients,
            correctBps,
            IRevolutionPointsEmitter.ProtocolRewardAddresses({
                builder: address(0),
                purchaseReferral: address(0),
                deployer: address(0)
            })
        );
        int totalSupplyAfterValidPurchase = int(revolutionPointsEmitter.totalSupply());
        assertEq(totalSupplyAfterValidPurchase, expectedAmount, "Supply should match the expected amount");
        // //emitted should match expected
        assertEq(int(emittedWad), expectedBuyerAmount, "Emitted amount should match expected amount");
        // //emitted should match supply
        assertEq(
            int(emittedWad) + int(revolutionPoints.balanceOf(revolutionPointsEmitter.creatorsAddress())),
            totalSupplyAfterValidPurchase,
            "Emitted amount should match total supply"
        );

        //expect owner to have payment - totalReward - creatorsDirectPayment in balance
        assertEq(
            address(revolutionPointsEmitter.owner()).balance,
            1e18 - revolutionPointsEmitter.computeTotalReward(1e18) - creatorsDirectPayment,
            "Owner should have payment - totalReward in balance"
        );

        // Test case with incorrect total of basis points
        uint256[] memory incorrectBps = new uint256[](2);
        incorrectBps[0] = 4000; // 40%
        incorrectBps[1] = 4000; // 40%

        // Expecting the transaction to revert due to incorrect total basis points
        vm.expectRevert(abi.encodeWithSignature("INVALID_BPS_SUM()"));
        revolutionPointsEmitter.buyToken{ value: 1e18 }(
            recipients,
            incorrectBps,
            IRevolutionPointsEmitter.ProtocolRewardAddresses({
                builder: address(0),
                purchaseReferral: address(0),
                deployer: address(0)
            })
        );

        vm.stopPrank();
    }

    //ensure when creating new points emitter, that INVALID_BPS is thrown if > 10_000
    function test_bpsInitialization() public {
        address owner = address(0x123);

        RevolutionProtocolRewards protocolRewards = new RevolutionProtocolRewards();

        address governanceToken = address(new ERC1967Proxy(revolutionPointsImpl, ""));

        address emitter1 = address(new ERC1967Proxy(revolutionPointsEmitterImpl, ""));

        address vrgdac = address(revolutionPointsEmitter.vrgdac());

        vm.startPrank(address(manager));
        vm.expectRevert(abi.encodeWithSignature("INVALID_BPS()"));
        IRevolutionPointsEmitter(emitter1).initialize({
            initialOwner: owner,
            weth: address(weth),
            revolutionPoints: address(governanceToken),
            vrgdac: vrgdac,
            creatorsAddress: creatorsAddress,
            creatorParams: IRevolutionBuilder.PointsEmitterCreatorParams({
                creatorRateBps: 100_000,
                entropyRateBps: 50_000
            })
        });
    }
}
