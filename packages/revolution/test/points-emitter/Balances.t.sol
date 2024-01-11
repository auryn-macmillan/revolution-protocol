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
    //test that the pointsEmitter has no balance after someone buys tokens
    function test_PointsEmitterBalance(uint256 creatorRateBps, uint256 entropyRateBps) public {
        // Assume valid rates
        vm.assume(creatorRateBps > 0 && creatorRateBps <= 10000 && entropyRateBps > 0 && entropyRateBps <= 10000);

        vm.startPrank(revolutionPointsEmitter.owner());
        //set creatorRate and entropyRate
        revolutionPointsEmitter.setCreatorRateBps(creatorRateBps);
        revolutionPointsEmitter.setEntropyRateBps(entropyRateBps);
        vm.stopPrank();

        //expect pointsEmitter balance to start out at 0
        assertEq(address(revolutionPointsEmitter).balance, 0, "Balance should start at 0");

        address[] memory recipients = new address[](1);
        recipients[0] = address(1);

        uint256[] memory bps = new uint256[](1);
        bps[0] = 10_000;

        revolutionPointsEmitter.buyToken{ value: 1 ether }(
            recipients,
            bps,
            IRevolutionPointsEmitter.ProtocolRewardAddresses({
                builder: address(0),
                purchaseReferral: address(0),
                deployer: address(0)
            })
        );

        //assert that pointsEmitter balance is correct
        assertEq(uint(address(revolutionPointsEmitter).balance), 0, "PointsEmitter should have correct balance");
    }

    //test that owner receives correct amount of ether
    function test_OwnerBalance(uint256 creatorRateBps, uint256 entropyRateBps) public {
        // Assume valid rates
        vm.assume(creatorRateBps > 0 && creatorRateBps <= 10000 && entropyRateBps > 0 && entropyRateBps <= 10000);

        vm.startPrank(revolutionPointsEmitter.owner());
        //set creatorRate and entropyRate
        revolutionPointsEmitter.setCreatorRateBps(creatorRateBps);
        revolutionPointsEmitter.setEntropyRateBps(entropyRateBps);
        vm.stopPrank();

        //expect owner balance to start out at 0
        assertEq(address(revolutionPointsEmitter.owner()).balance, 0, "Balance should start at 0");

        address[] memory recipients = new address[](1);
        recipients[0] = address(1);

        uint256[] memory bps = new uint256[](1);
        bps[0] = 10_000;

        //get msg value remaining
        uint256 msgValueRemaining = 1 ether - revolutionPointsEmitter.computeTotalReward(1 ether);

        // Calculate share of purchase amount reserved for creators
        uint256 creatorsShare = (msgValueRemaining * creatorRateBps) / 10_000;

        // Calculate share of purchase amount reserved for buyers
        uint256 buyersShare = msgValueRemaining - creatorsShare;

        // Calculate ether directly sent to creators
        uint256 creatorDirectPayment = (creatorsShare * entropyRateBps) / 10_000;

        revolutionPointsEmitter.buyToken{ value: 1 ether }(
            recipients,
            bps,
            IRevolutionPointsEmitter.ProtocolRewardAddresses({
                builder: address(0),
                purchaseReferral: address(1),
                deployer: address(0)
            })
        );

        //assert that owner balance is correct
        assertEq(
            uint(address(revolutionPointsEmitter.owner()).balance),
            uint(buyersShare + creatorsShare - creatorDirectPayment),
            "Owner should have correct balance"
        );
    }

    function test_GetTokenAmountForMultiPurchaseGeneral(uint256 payment) public {
        vm.assume(payment > revolutionPointsEmitter.minPurchaseAmount());
        vm.assume(payment < revolutionPointsEmitter.maxPurchaseAmount());
        vm.startPrank(address(0));

        uint256 SOME_MAX_EXPECTED_VALUE = uint256(wadDiv(int256(payment), 1 ether)) * 1e18 * tokensPerTimeUnit;

        int256 slightlyMore = revolutionPointsEmitter.getTokenQuoteForEther((payment * 101) / 100);

        // Call the function with the typical payment amount
        int256 tokenAmount = revolutionPointsEmitter.getTokenQuoteForEther(payment);

        emit log_int(tokenAmount);

        // Assert that the token amount is reasonable (not zero or unexpectedly high)
        assertGt(tokenAmount, 0, "Token amount should be greater than zero");
        assertLt(
            tokenAmount,
            int256(SOME_MAX_EXPECTED_VALUE),
            "Token amount should be less than some max expected value"
        );
        assertLt(tokenAmount, slightlyMore, "Token amount should be less than slightly more");

        //buy 10 ether of tokens
        address[] memory recipients = new address[](1);
        recipients[0] = address(1);
        uint256[] memory bps = new uint256[](1);
        bps[0] = 10_000;

        //ensure that enough volume was bought for the day, so purchase expectedVolume amount first
        revolutionPointsEmitter.buyToken{ value: expectedVolume }(
            recipients,
            bps,
            IRevolutionPointsEmitter.ProtocolRewardAddresses({
                builder: address(0),
                purchaseReferral: address(0),
                deployer: address(0)
            })
        );

        revolutionPointsEmitter.buyToken{ value: payment }(
            recipients,
            bps,
            IRevolutionPointsEmitter.ProtocolRewardAddresses({
                builder: address(0),
                purchaseReferral: address(0),
                deployer: address(0)
            })
        );

        int256 newTokenAmount = revolutionPointsEmitter.getTokenQuoteForEther(payment);

        // Assert that the new token amount is less than the previous tokenAmount
        assertLt(newTokenAmount, tokenAmount, "Token amount should be less than previous token amount");

        vm.stopPrank();
    }

    function test_GetTokenAmountForMultiPurchaseEdgeCases() public {
        vm.startPrank(address(0));

        // Edge Case 1: Very Small Payment
        uint256 smallPayment = 0.00001 ether;
        int256 smallPaymentTokenAmount = revolutionPointsEmitter.getTokenQuoteForEther(smallPayment);
        assertGt(smallPaymentTokenAmount, 0, "Token amount for small payment should be greater than zero");
        emit log_int(smallPaymentTokenAmount);

        // A days worth of payment amount
        int256 dailyPaymentTokenAmount = revolutionPointsEmitter.getTokenQuoteForEther(expectedVolume);
        assertLt(
            uint256(dailyPaymentTokenAmount),
            tokensPerTimeUnit * 1e18,
            "Token amount for daily payment should be less than tokens per day"
        );
        emit log_string("Daily Payment Token Amount: ");
        emit log_int(dailyPaymentTokenAmount);

        // Edge Case 2: Very Large Payment
        // An unusually large payment amount
        int256 largePaymentTokenAmount = revolutionPointsEmitter.getTokenQuoteForEther(expectedVolume * 100);
        //spending 100x the expected amount per day should get you < 25x the tokens
        uint256 SOME_REALISTIC_UPPER_BOUND = 25 * tokensPerTimeUnit * 1e18;
        assertLt(
            uint256(largePaymentTokenAmount),
            SOME_REALISTIC_UPPER_BOUND,
            "Token amount for large payment should be less than some realistic upper bound"
        );
        emit log_string("Large Payment Token Amount: ");
        emit log_int(largePaymentTokenAmount);

        uint256 largestPayment = expectedVolume * 1_000; // An unusually large payment amount
        int256 largestPaymentTokenAmount = revolutionPointsEmitter.getTokenQuoteForEther(largestPayment);
        //spending 1000x the daily amount should get you less than 50x the tokens
        assertLt(
            uint256(largestPaymentTokenAmount),
            50 * tokensPerTimeUnit * 1e18,
            "Token amount for largest payment should be less than some realistic upper bound"
        );

        emit log_string("Largest Payment Token Amount: ");
        emit log_int(largestPaymentTokenAmount);

        vm.stopPrank();
    }
}
