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

contract EmissionRatesTest is PointsEmitterTest {
    function testBuyTokenWithDifferentRates(uint256 creatorRate, uint256 entropyRate) public {
        // Assume valid rates
        vm.assume(creatorRate <= 10000 && entropyRate <= 10000);

        vm.startPrank(address(executor));
        // Set creator and entropy rates
        revolutionPointsEmitter.setCreatorRateBps(creatorRate);
        revolutionPointsEmitter.setEntropyRateBps(entropyRate);
        assertEq(revolutionPointsEmitter.creatorRateBps(), creatorRate, "Creator rate not set correctly");
        assertEq(revolutionPointsEmitter.entropyRateBps(), entropyRate, "Entropy rate not set correctly");

        // Setup for buying token
        address[] memory recipients = new address[](1);
        recipients[0] = address(1); // recipient address

        uint256[] memory bps = new uint256[](1);
        bps[0] = 10000; // 100% of the tokens to the recipient

        uint256 valueToSend = 1 ether;
        revolutionPointsEmitter.setCreatorsAddress(address(80));
        address creatorsAddress = revolutionPointsEmitter.creatorsAddress();
        uint256 creatorsInitialEthBalance = address(revolutionPointsEmitter.creatorsAddress()).balance;

        uint256 feeAmount = revolutionPointsEmitter.computeTotalReward(valueToSend);

        // Calculate expected ETH sent to creator
        uint256 totalPaymentForCreator = ((valueToSend - feeAmount) * creatorRate) / 10000;
        uint256 expectedCreatorEth = (totalPaymentForCreator * entropyRate) / 10000;

        if (creatorRate == 0 || entropyRate == 10_000) vm.expectRevert(abi.encodeWithSignature("INVALID_PAYMENT()"));
        uint256 expectedCreatorTokens = uint(
            revolutionPointsEmitter.getTokenQuoteForEther(totalPaymentForCreator - expectedCreatorEth)
        );

        // Perform token purchase
        vm.startPrank(address(this));
        uint256 tokensSold = revolutionPointsEmitter.buyToken{ value: valueToSend }(
            recipients,
            bps,
            IRevolutionPointsEmitter.ProtocolRewardAddresses({
                builder: address(0),
                purchaseReferral: address(0),
                deployer: address(0)
            })
        );

        // Verify tokens distributed to creator
        uint256 creatorTokenBalance = revolutionPointsEmitter.balanceOf(revolutionPointsEmitter.creatorsAddress());
        assertEq(creatorTokenBalance, expectedCreatorTokens, "Creator did not receive correct amount of tokens");

        // Verify ETH sent to creator
        uint256 creatorsNewEthBalance = address(revolutionPointsEmitter.creatorsAddress()).balance;
        assertEq(
            creatorsNewEthBalance - creatorsInitialEthBalance,
            expectedCreatorEth,
            "Incorrect ETH amount sent to creator"
        );

        // Verify tokens distributed to recipient
        uint256 recipientTokenBalance = revolutionPointsEmitter.balanceOf(address(1));
        assertEq(recipientTokenBalance, tokensSold, "Recipient did not receive correct amount of tokens");
    }

    function testGetTokenPrice() public {
        vm.startPrank(address(0));

        vm.deal(address(0), 100000 ether);
        vm.stopPrank();

        int256 priceAfterManyPurchases = revolutionPointsEmitter.buyTokenQuote(1e18);
        emit log_int(priceAfterManyPurchases);

        // Simulate the passage of time
        uint256 daysElapsed = 221;
        vm.warp(block.timestamp + daysElapsed * 1 days);

        int256 priceAfterManyDays = revolutionPointsEmitter.buyTokenQuote(1e18);

        emit log_int(priceAfterManyDays);

        // Assert that the price is greater than zero
        assertGt(priceAfterManyDays, 0, "Price should never hit zero");
    }

    function testBuyTokenTotalVal() public {
        vm.startPrank(address(0));

        address[] memory recipients = new address[](1);
        recipients[0] = address(1);

        uint256[] memory bps = new uint256[](1);
        bps[0] = 10_000;

        vm.deal(address(0), 100000 ether);

        vm.stopPrank();
        // set setCreatorsAddress
        vm.prank(address(executor));
        revolutionPointsEmitter.setCreatorsAddress(address(100));

        // change creatorRateBps to 0
        vm.prank(address(executor));
        revolutionPointsEmitter.setCreatorRateBps(0);

        // set entropyRateBps to 0
        vm.prank(address(executor));
        revolutionPointsEmitter.setEntropyRateBps(0);

        vm.startPrank(address(0));

        revolutionPointsEmitter.buyToken{ value: 1e18 }(
            recipients,
            bps,
            IRevolutionPointsEmitter.ProtocolRewardAddresses({
                builder: address(0),
                purchaseReferral: address(0),
                deployer: address(0)
            })
        );

        // save treasury ETH balance
        uint256 treasuryEthBalance = address(revolutionPointsEmitter.owner()).balance;
        // save buyer token balance
        uint256 buyerTokenBalance = revolutionPointsEmitter.balanceOf(address(1));

        console2.log("treasuryEthBalance: ", treasuryEthBalance);
        console2.log("buyerTokenBalance: ", buyerTokenBalance);

        // save protocol fees
        uint256 protocolFees = (1e18 * 250) / 10_000;

        console2.log("protocolFees: ", protocolFees);

        // convert token balances to ETH
        uint256 buyerTokenBalanceEth = uint256(revolutionPointsEmitter.buyTokenQuote(buyerTokenBalance));

        console2.log("buyerTokenBalanceEth: ", buyerTokenBalanceEth);

        console2.log("total: ", treasuryEthBalance + protocolFees + buyerTokenBalanceEth);

        // Sent in ETH should be almost equal (account for precision/rounding) to total ETH plus token value in ETH
        assertGt(1e18 * 2, treasuryEthBalance + protocolFees + buyerTokenBalanceEth, "");
    }

    function testBuyingTwiceAmountIsNotMoreThanTwiceEmittedTokens() public {
        vm.startPrank(address(0));

        address[] memory recipients = new address[](1);
        recipients[0] = address(1);

        uint256[] memory bps = new uint256[](1);
        bps[0] = 10_000;

        revolutionPointsEmitter.buyToken{ value: 1e18 }(
            recipients,
            bps,
            IRevolutionPointsEmitter.ProtocolRewardAddresses({
                builder: address(0),
                purchaseReferral: address(0),
                deployer: address(0)
            })
        );
        uint256 firstAmount = revolutionPointsEmitter.balanceOf(address(1));

        revolutionPointsEmitter.buyToken{ value: 1e18 }(
            recipients,
            bps,
            IRevolutionPointsEmitter.ProtocolRewardAddresses({
                builder: address(0),
                purchaseReferral: address(0),
                deployer: address(0)
            })
        );
        uint256 secondAmountDifference = revolutionPointsEmitter.balanceOf(address(1)) - firstAmount;

        assert(secondAmountDifference <= 2 * revolutionPointsEmitter.totalSupply());
    }

    //if buyToken is called with payment 0, then it should revert with INVALID_PAYMENT()
    function test_revertNoPayment() public {
        vm.startPrank(address(0));

        address[] memory recipients = new address[](1);
        recipients[0] = address(1);

        uint256[] memory bps = new uint256[](1);
        bps[0] = 10_000;

        vm.expectRevert(abi.encodeWithSignature("INVALID_PAYMENT()"));
        revolutionPointsEmitter.buyToken{ value: 0 }(
            recipients,
            bps,
            IRevolutionPointsEmitter.ProtocolRewardAddresses({
                builder: address(0),
                purchaseReferral: address(1),
                deployer: address(0)
            })
        );
    }

    function test_correctEmitted(uint256 creatorRateBps, uint256 entropyRateBps) public {
        // Assume valid rates
        vm.assume(creatorRateBps > 0 && creatorRateBps < 10000 && entropyRateBps < 10000);

        vm.startPrank(revolutionPointsEmitter.owner());
        //set creatorRate and entropyRate
        revolutionPointsEmitter.setCreatorRateBps(creatorRateBps);
        revolutionPointsEmitter.setEntropyRateBps(entropyRateBps);
        vm.stopPrank();

        vm.deal(address(this), 100000 ether);

        emit log_address(revolutionPointsEmitter.creatorsAddress());
        emit log_uint(revolutionPoints.balanceOf(revolutionPointsEmitter.creatorsAddress()));

        //expect balance to start out at 0
        assertEq(revolutionPoints.balanceOf(revolutionPointsEmitter.creatorsAddress()), 0, "Balance should start at 0");

        address[] memory recipients = new address[](1);
        recipients[0] = address(1);

        uint256[] memory bps = new uint256[](1);
        bps[0] = 10_000;

        //expect recipient0 balance to start out at 0
        assertEq(revolutionPoints.balanceOf(address(1)), 0, "Balance should start at 0");

        //get msg value remaining
        uint256 msgValueRemaining = 1 ether - revolutionPointsEmitter.computeTotalReward(1 ether);

        //Share of purchase amount to send to owner
        uint256 toPayOwner = (msgValueRemaining * (10_000 - creatorRateBps)) / 10_000;

        //Ether directly sent to creators
        uint256 creatorDirectPayment = ((msgValueRemaining - toPayOwner) * entropyRateBps) / 10_000;

        //get expected tokens for creators
        int256 expectedAmountForCreators = revolutionPointsEmitter.getTokenQuoteForEther(
            msgValueRemaining - toPayOwner - creatorDirectPayment
        );

        //get expected tokens for recipient0
        int256 expectedAmountForRecipient0 = getTokenQuoteForEtherHelper(toPayOwner, expectedAmountForCreators);

        revolutionPointsEmitter.buyToken{ value: 1 ether }(
            recipients,
            bps,
            IRevolutionPointsEmitter.ProtocolRewardAddresses({
                builder: address(0),
                purchaseReferral: address(0),
                deployer: address(0)
            })
        );

        //log creatorsAddress balance
        emit log_uint(revolutionPoints.balanceOf(revolutionPointsEmitter.creatorsAddress()));

        //assert that creatorsAddress balance is correct
        assertEq(
            uint(revolutionPoints.balanceOf(revolutionPointsEmitter.creatorsAddress())),
            uint(expectedAmountForCreators),
            "Creators should have correct balance"
        );

        //log recipient0 balance
        emit log_uint(revolutionPoints.balanceOf(address(1)));

        // assert that recipient0 balance is correct
        assertEq(
            uint(revolutionPoints.balanceOf(address(1))),
            uint(expectedAmountForRecipient0),
            "Recipient0 should have correct balance"
        );
    }

    function test_BuyingFunctionBreaksAfterAPeriodOfTime(
        uint256 creatorRate,
        uint256 entropyRate,
        uint256 randomTime
    ) public {
        randomTime = bound(randomTime, 300 days, 700 days);
        uint256 currentTime = 1702801400;

        // warp to a more realistic time
        vm.warp(block.timestamp + currentTime);

        // Assume valid rates
        vm.assume(creatorRate <= 10000 && entropyRate <= 10000);

        vm.startPrank(address(executor));
        // Set creator and entropy rates
        revolutionPointsEmitter.setCreatorRateBps(creatorRate);
        revolutionPointsEmitter.setEntropyRateBps(entropyRate);
        assertEq(revolutionPointsEmitter.creatorRateBps(), creatorRate, "Creator rate not set correctly");
        assertEq(revolutionPointsEmitter.entropyRateBps(), entropyRate, "Entropy rate not set correctly");

        // Setup for buying token
        address[] memory recipients = new address[](1);
        recipients[0] = address(1); // recipient address

        uint256[] memory bps = new uint256[](1);
        bps[0] = 10000; // 100% of the tokens to the recipient

        uint256 valueToSend = 1 ether;

        // Perform token purchase
        vm.startPrank(address(this));
        uint256 tokensSold = revolutionPointsEmitter.buyToken{ value: valueToSend }(
            recipients,
            bps,
            IRevolutionPointsEmitter.ProtocolRewardAddresses({
                builder: address(0),
                purchaseReferral: address(0),
                deployer: address(0)
            })
        );
    }
}
