// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { Test } from "forge-std/Test.sol";
import { RevolutionPoints } from "../../src/RevolutionPoints.sol";
import { RevolutionBuilderTest } from "../RevolutionBuilder.t.sol";
import { VRGDAC } from "../../src/libs/VRGDAC.sol";
import { toDaysWadUnsafe, unsafeWadDiv, wadLn, wadExp, wadMul } from "../../src/libs/SignedWadMath.sol";
import { console2 } from "forge-std/console2.sol";

contract PointsTestSuite is RevolutionBuilderTest {
    event Log(string, uint);

    function setUp() public override {
        super.setUp();
        super.setMockParams();

        super.setPointsParams("Revolution Governance", "GOV");

        super.deployMock();
    }

    function test_noNegatives(int256 amount, int256 perTimeUnit, int256 targetPrice, int256 priceDecayPercent) public {
        perTimeUnit = bound(perTimeUnit, 1 * 1e18, 1_000_000 * 1e18);
        targetPrice = bound(targetPrice, 1 * 1e10, 1_000 * 1e18);
        priceDecayPercent = bound(priceDecayPercent, 1e18 / 1000, 1e18 / 2);

        amount = bound(
            amount,
            int(revolutionPointsEmitter.minPurchaseAmount()),
            int(revolutionPointsEmitter.maxPurchaseAmount())
        );

        VRGDAC vrgdac = new VRGDAC(targetPrice, priceDecayPercent, perTimeUnit);
        int256 x = vrgdac.yToX({ timeSinceStart: 2000000000000000000, sold: 1000000000000000000, amount: amount });

        console2.log((x));
        console2.log(uint256(x));
        console2.log(uint256(x) / 1e18);

        assertGe(x, 0, "x should be greater than or equal to zero");
    }

    function test_yToX_NoPurchasesAfterLongTime(
        int256 amount,
        int256 randomTime,
        int256 sold,
        int256 perTimeUnit,
        int256 targetPrice,
        int256 priceDecayPercent
    ) public {
        targetPrice = bound(targetPrice, 1 * 1e10, 1_000 * 1e18);
        perTimeUnit = bound(perTimeUnit, 1 * 1e18, 1_000_000 * 1e18);
        randomTime = bound(randomTime, 10 days, 7665 days);
        priceDecayPercent = bound(priceDecayPercent, 1e18 / 1000, 1e18 / 2);

        amount = bound(
            amount,
            int(revolutionPointsEmitter.minPurchaseAmount()),
            int(revolutionPointsEmitter.maxPurchaseAmount())
        );

        // setup vrgda
        VRGDAC vrgdac = new VRGDAC(targetPrice, priceDecayPercent, perTimeUnit);

        int256 nDays = randomTime / 1 days;
        int256 timeSinceStart = toDaysWadUnsafe(uint(randomTime));

        //bound sold to perTimeUnit * nDays < 50% undersold
        sold = bound(sold, (perTimeUnit * nDays * 5) / 10, perTimeUnit * nDays);

        int256 e_x_param = (wadLn(1e18 - priceDecayPercent) * (timeSinceStart - unsafeWadDiv(sold, perTimeUnit))) /
            1e18; // when this overflows, we just want to floor / max it

        // call y to x ensure no revert
        int256 x = vrgdac.yToX({ timeSinceStart: timeSinceStart, sold: sold, amount: amount });

        // ensure x is not negative even though there haven't been any sales in forever
        assertGe(x, 0, "x should be greater than or equal to zero");
    }

    function test_yToX_ManyPurchasesAfterLongTime(
        int256 amount,
        int256 randomTime,
        int256 sold,
        int256 perTimeUnit,
        int256 targetPrice,
        int256 priceDecayPercent
    ) public {
        targetPrice = bound(targetPrice, 1 * 1e10, 1_000 * 1e18);
        perTimeUnit = bound(perTimeUnit, 1 * 1e18, 1_000_000 * 1e18);
        randomTime = bound(randomTime, 10 days, 7665 days);
        priceDecayPercent = bound(priceDecayPercent, 1e18 / 1000, 1e18 / 2);
        amount = bound(
            amount,
            int(revolutionPointsEmitter.minPurchaseAmount()),
            int(revolutionPointsEmitter.maxPurchaseAmount())
        );

        // setup vrgda
        VRGDAC vrgdac = new VRGDAC(targetPrice, priceDecayPercent, perTimeUnit);

        int256 nDays = randomTime / 1 days;
        int256 timeSinceStart = toDaysWadUnsafe(uint(randomTime));

        //bound sold to perTimeUnit * nDays < 50% oversold
        sold = bound(sold, perTimeUnit * nDays, (perTimeUnit * nDays * 15) / 10);

        int256 wadExpParameter = (wadLn(1e18 - priceDecayPercent) *
            (timeSinceStart - unsafeWadDiv(sold, perTimeUnit))) / 1e18; // when this overflows, we just want to floor / max it

        // call y to x ensure no revert
        int256 x = vrgdac.yToX({ timeSinceStart: timeSinceStart, sold: sold, amount: amount });
    }
}
