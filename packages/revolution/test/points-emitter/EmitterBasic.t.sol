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
    function testCannotBuyAsOwner() public {
        vm.startPrank(revolutionPointsEmitter.owner());

        vm.deal(revolutionPointsEmitter.owner(), 100000 ether);

        address[] memory recipients = new address[](1);
        recipients[0] = address(1);

        uint256[] memory bps = new uint256[](1);
        bps[0] = 10_000;

        vm.expectRevert(abi.encodeWithSignature("FUNDS_RECIPIENT_CANNOT_BUY_TOKENS()"));
        revolutionPointsEmitter.buyToken{ value: 1e18 }(
            recipients,
            bps,
            IRevolutionPointsEmitter.ProtocolRewardAddresses({
                builder: address(0),
                purchaseReferral: address(0),
                deployer: address(0)
            })
        );
    }

    function testCannotBuyAsCreators() public {
        vm.startPrank(revolutionPointsEmitter.creatorsAddress());

        vm.deal(revolutionPointsEmitter.creatorsAddress(), 100000 ether);

        address[] memory recipients = new address[](1);
        recipients[0] = address(1);

        uint256[] memory bps = new uint256[](1);
        bps[0] = 10_000;

        vm.expectRevert(abi.encodeWithSignature("FUNDS_RECIPIENT_CANNOT_BUY_TOKENS()"));
        revolutionPointsEmitter.buyToken{ value: 1e18 }(
            recipients,
            bps,
            IRevolutionPointsEmitter.ProtocolRewardAddresses({
                builder: address(0),
                purchaseReferral: address(0),
                deployer: address(0)
            })
        );
    }

    function testTransferTokenContractOwnership() public {
        // makes a points emitter with one revolution points contract
        // makes a second with the same one
        // ensures that the second cannot mint and calling buyGovernance fails
        // transfers ownership to the second
        // ensures that the second can mint and calling buyGovernance succeeds

        address owner = address(0x123);

        RevolutionProtocolRewards protocolRewards = new RevolutionProtocolRewards();

        address governanceToken = address(new ERC1967Proxy(revolutionPointsImpl, ""));

        address emitter1 = address(new ERC1967Proxy(revolutionPointsEmitterImpl, ""));

        vm.startPrank(address(manager));
        IRevolutionPointsEmitter(emitter1).initialize({
            initialOwner: owner,
            weth: address(weth),
            revolutionPoints: address(governanceToken),
            vrgdac: address(revolutionPointsEmitter.vrgdac()),
            creatorsAddress: creatorsAddress,
            creatorParams: IRevolutionBuilder.PointsEmitterCreatorParams({
                creatorRateBps: 1_000,
                entropyRateBps: 5_000
            })
        });

        IRevolutionPoints(governanceToken).initialize({
            initialOwner: address(executor),
            minter: address(emitter1),
            tokenParams: IRevolutionBuilder.PointsTokenParams({ name: "Revolution Governance", symbol: "GOV" })
        });

        vm.deal(address(21), 100000 ether);

        address[] memory recipients = new address[](1);
        recipients[0] = address(1);

        uint256[] memory bps = new uint256[](1);
        bps[0] = 10_000;

        vm.startPrank(address(21));
        IRevolutionPointsEmitter(emitter1).buyToken{ value: 1e18 }(
            recipients,
            bps,
            IRevolutionPointsEmitter.ProtocolRewardAddresses({
                builder: address(0),
                purchaseReferral: address(0),
                deployer: address(0)
            })
        );

        address emitter2 = address(new ERC1967Proxy(revolutionPointsEmitterImpl, ""));

        vm.startPrank(address(manager));
        IRevolutionPointsEmitter(emitter2).initialize({
            initialOwner: owner,
            weth: address(weth),
            revolutionPoints: address(governanceToken),
            vrgdac: address(revolutionPointsEmitter.vrgdac()),
            creatorsAddress: creatorsAddress,
            creatorParams: IRevolutionBuilder.PointsEmitterCreatorParams({
                creatorRateBps: 1_000,
                entropyRateBps: 5_000
            })
        });

        vm.startPrank(address(executor));
        RevolutionPoints(governanceToken).transferOwnership(address(emitter2));

        vm.startPrank(address(emitter2));
        //accept ownership transfer
        RevolutionPoints(governanceToken).acceptOwnership();

        //set the minter to the new emitter
        RevolutionPoints(governanceToken).setMinter(address(emitter2));

        vm.startPrank(address(48));
        vm.deal(address(48), 100000 ether);
        IRevolutionPointsEmitter(emitter2).buyToken{ value: 1e18 }(
            recipients,
            bps,
            IRevolutionPointsEmitter.ProtocolRewardAddresses({
                builder: address(0),
                purchaseReferral: address(0),
                deployer: address(0)
            })
        );

        //assert that the emitter2 is the owner
        assertEq(RevolutionPoints(governanceToken).owner(), address(emitter2));
    }

    function testBuyingLaterIsBetter() public {
        vm.startPrank(address(0));

        int256 initAmount = revolutionPointsEmitter.getTokenQuoteForEther(1e18);

        int256 firstPrice = revolutionPointsEmitter.buyTokenQuote(1e19);

        // solhint-disable-next-line not-rely-on-time
        vm.warp(block.timestamp + (10 days));

        int256 secondPrice = revolutionPointsEmitter.buyTokenQuote(1e19);

        emit log_int(firstPrice);
        emit log_int(secondPrice);

        int256 laterAmount = revolutionPointsEmitter.getTokenQuoteForEther(1e18);

        assertGt(laterAmount, initAmount, "Later amount should be greater than initial amount");

        assertLt(secondPrice, firstPrice, "Second price should be less than first price");
    }

    function testBuyToken() public {
        vm.startPrank(address(0));

        address[] memory recipients = new address[](1);
        recipients[0] = address(1);

        uint256[] memory bps = new uint256[](1);
        bps[0] = 10_000;

        vm.deal(address(0), 100000 ether);

        emit log_address(address(0));

        revolutionPointsEmitter.buyToken{ value: 1e18 }(
            recipients,
            bps,
            IRevolutionPointsEmitter.ProtocolRewardAddresses({
                builder: address(0),
                purchaseReferral: address(0),
                deployer: address(0)
            })
        );

        emit Log("Balance: ", revolutionPointsEmitter.balanceOf(address(1)));
    }

    function testBuyTokenPriceIncreases() public {
        vm.startPrank(address(0));

        address[] memory firstRecipients = new address[](1);
        firstRecipients[0] = address(1);

        address[] memory secondRecipients = new address[](1);
        secondRecipients[0] = address(2);

        uint256[] memory bps = new uint256[](1);
        bps[0] = 10_000;

        revolutionPointsEmitter.buyToken{ value: 1e18 }(
            firstRecipients,
            bps,
            IRevolutionPointsEmitter.ProtocolRewardAddresses({
                builder: address(0),
                purchaseReferral: address(0),
                deployer: address(0)
            })
        );

        revolutionPointsEmitter.buyToken{ value: 1e18 }(
            secondRecipients,
            bps,
            IRevolutionPointsEmitter.ProtocolRewardAddresses({
                builder: address(0),
                purchaseReferral: address(0),
                deployer: address(0)
            })
        );

        // should get more expensive
        assertGt(revolutionPointsEmitter.balanceOf(address(1)), revolutionPointsEmitter.balanceOf(address(2)));
    }

    function testSetCreatorsAddress() public {
        // Setting Creators Address by Owner
        address newCreatorsAddress = address(0x123);
        vm.prank(address(executor));
        revolutionPointsEmitter.setCreatorsAddress(newCreatorsAddress);
        assertEq(
            revolutionPointsEmitter.creatorsAddress(),
            newCreatorsAddress,
            "Owner should be able to set creators address"
        );

        // Attempting to set Creators Address by Non-Owner
        address nonOwner = address(0x4156);
        vm.startPrank(nonOwner);
        try revolutionPointsEmitter.setCreatorsAddress(nonOwner) {
            fail("Non-owner should not be able to set creators address");
        } catch {}
        vm.stopPrank();
    }

    function test_purchaseBounds(int256 amount) public {
        vm.assume(
            amount <= int(revolutionPointsEmitter.minPurchaseAmount()) ||
                amount >= int(revolutionPointsEmitter.maxPurchaseAmount())
        );

        vm.expectRevert();
        revolutionPointsEmitter.buyToken{ value: uint256(amount) }(
            new address[](1),
            new uint256[](1),
            IRevolutionPointsEmitter.ProtocolRewardAddresses({
                builder: address(0),
                purchaseReferral: address(1),
                deployer: address(0)
            })
        );
    }

    function testBuyTokenReentrancy() public {
        // Deploy the malicious owner contract
        MaliciousOwner maliciousOwner = new MaliciousOwner(address(revolutionPointsEmitter));

        address governanceToken = address(new ERC1967Proxy(revolutionPointsImpl, ""));

        address emitter2 = address(new ERC1967Proxy(revolutionPointsEmitterImpl, ""));

        vm.startPrank(address(manager));
        IRevolutionPointsEmitter(emitter2).initialize({
            initialOwner: address(maliciousOwner),
            weth: address(weth),
            revolutionPoints: address(governanceToken),
            vrgdac: address(revolutionPointsEmitter.vrgdac()),
            creatorsAddress: creatorsAddress,
            creatorParams: IRevolutionBuilder.PointsEmitterCreatorParams({
                creatorRateBps: 1_000,
                entropyRateBps: 5_000
            })
        });

        IRevolutionPoints(governanceToken).initialize({
            initialOwner: address(executor),
            minter: address(emitter2),
            tokenParams: IRevolutionBuilder.PointsTokenParams({ name: "Revolution Governance", symbol: "GOV" })
        });

        vm.deal(address(this), 100000 ether);

        //buy tokens and see if malicious owner can reenter
        address[] memory recipients = new address[](1);
        recipients[0] = address(1);
        uint256[] memory bps = new uint256[](1);
        bps[0] = 10_000;
        vm.expectRevert();
        IRevolutionPointsEmitter(emitter2).buyToken{ value: 1e18 }(
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

contract MaliciousOwner {
    RevolutionPointsEmitter revolutionPointsEmitter;
    bool public reentryAttempted;

    constructor(address _emitter) {
        revolutionPointsEmitter = RevolutionPointsEmitter(_emitter);
        reentryAttempted = false;
    }

    // Fallback function to enable re-entrance to PointsEmitter
    function call() external payable {
        reentryAttempted = true;
        address[] memory recipients = new address[](1);
        recipients[0] = address(this);
        uint256[] memory bps = new uint256[](1);
        bps[0] = 10_000;

        // Attempt to re-enter PointsEmitter
        revolutionPointsEmitter.buyToken{ value: msg.value }(
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
