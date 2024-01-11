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
import { RevolutionBuilderTest } from "../RevolutionBuilder.t.sol";
import { IRevolutionPoints } from "../../src/interfaces/IRevolutionPoints.sol";
import { ERC1967Proxy } from "../../src/libs/proxy/ERC1967Proxy.sol";
import { console2 } from "forge-std/console2.sol";

contract PointsEmitterTest is RevolutionBuilderTest {
    event Log(string, uint);

    // 1,000 tokens per day is the target emission
    uint256 tokensPerTimeUnit = 1_000;

    uint256 expectedVolume = tokensPerTimeUnit * 1e18;

    string public tokenNamePrefix = "Vrb";

    function setUp() public override {
        super.setUp();
        super.setMockParams();

        super.setRevolutionTokenParams("Mock", "MOCK", "https://example.com/token/", tokenNamePrefix);

        int256 oneFullTokenTargetPrice = 1 ether;

        int256 priceDecayPercent = 1e18 / 10;

        super.setPointsEmitterParams(
            oneFullTokenTargetPrice,
            priceDecayPercent,
            int256(1e18 * tokensPerTimeUnit),
            creatorsAddress
        );

        super.deployMock();

        vm.deal(address(0), 100000 ether);
    }

    function getTokenQuoteForEtherHelper(uint256 etherAmount, int256 supply) public returns (int gainedX) {
        // Note: By using toDaysWadUnsafe(block.timestamp - startTime) we are establishing that 1 "unit of time" is 1 day.
        // solhint-disable-next-line not-rely-on-time
        return
            revolutionPointsEmitter.vrgdac().yToX({
                timeSinceStart: toDaysWadUnsafe(block.timestamp - revolutionPointsEmitter.startTime()),
                sold: supply,
                amount: int(etherAmount)
            });
    }
}
