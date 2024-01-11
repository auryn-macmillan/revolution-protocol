// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { Test } from "forge-std/Test.sol";
import { MaxHeapTestSuite } from "./MaxHeap.t.sol"; // Assuming MaxHeap is in a separate file

contract MaxHeapUpdateTestSuite is MaxHeapTestSuite {
    function testInitialInsertAndMax() public {
        maxHeapTester.insert(1, 5);
        maxHeapTester.insert(2, 10);
        maxHeapTester.insert(3, 15);

        (uint256 itemId, uint256 value) = maxHeapTester.getMax();
        assertEq(itemId, 3, "Item ID should be 3 after initial insert");
        assertEq(value, 15, "Value should be 15 after initial insert");
    }

    //from the audit
    function testExtractUpdateError() public {
        // Insert 3 items with value 20 and remove them all
        maxHeapTester.insert(1, 20);
        maxHeapTester.insert(2, 20);
        maxHeapTester.insert(3, 20);

        maxHeapTester.extractMax();
        maxHeapTester.extractMax();
        maxHeapTester.extractMax(); // Because all of 3 items are removed, itemId=1,2,3 should never be extracted after.

        // Insert 2 items with value 10 which is small than 20
        maxHeapTester.insert(4, 10);
        maxHeapTester.insert(5, 21);
        // Update value to cause maxHeapify
        maxHeapTester.updateValue(4, 5);

        // Now the item should be itemId=5, value=10
        // But in fact the max item is itemId=3, value=20 now.
        (uint256 itemId, uint256 value) = maxHeapTester.extractMax(); // itemId=3 will be extracted again

        require(itemId == 5, "Item ID should be 5");
        require(value == 21, "value should be 21");
    }

    function testUpdateValueIncrease() public {
        maxHeapTester.insert(1, 10);
        maxHeapTester.insert(2, 5);
        maxHeapTester.insert(3, 3);

        maxHeapTester.updateValue(1, 20); // Update the value of itemId 1 to 20, which should make it the max

        (uint256 itemId, uint256 value) = maxHeapTester.getMax();
        assertEq(itemId, 1, "Item ID should be 1 after updating to a higher value");
        assertEq(value, 20, "Value should be 20 after updating to a higher value");
    }

    function testUpdateValueDecrease() public {
        maxHeapTester.insert(1, 20);
        maxHeapTester.insert(2, 10);
        maxHeapTester.insert(3, 5);

        maxHeapTester.updateValue(1, 7); // Update the value of itemId 1 to 7, which should no longer make it the max

        (uint256 itemId, uint256 value) = maxHeapTester.getMax();
        assertEq(itemId, 2, "Item ID should be 2 after updating to a lower value");
        assertEq(value, 10, "Value should be 10 after updating to a lower value");
    }

    function testUpdateValueWithHeapify() public {
        maxHeapTester.insert(1, 50);
        maxHeapTester.insert(2, 40);
        maxHeapTester.insert(3, 35);
        maxHeapTester.insert(4, 20);
        maxHeapTester.insert(5, 10);

        maxHeapTester.updateValue(5, 60); // Update the value of itemId 5 to 60, making it the new max

        (uint256 itemId, uint256 value) = maxHeapTester.getMax();
        assertEq(itemId, 5, "Item ID should be 5 after heapify");
        assertEq(value, 60, "Value should be 60 after heapify");
    }
}
