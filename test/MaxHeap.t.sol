// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {MaxHeapTest} from "../packages/revolution-contracts/MaxHeap.sol";  // Update this path

contract MaxHeapTestSuite is Test {
    MaxHeapTest public maxHeap;

    function setUp() public {
        maxHeap = new MaxHeapTest(50);
    }

    function testInsert() public {
        setUp();

        // Insert values into the max heap
        maxHeap.insert(1,5);
        maxHeap.insert(2,7);
        maxHeap.insert(3,3);

        // Validate the max value
        (uint256 maxItemId, uint256 maxValue) = maxHeap.getMax();
        assertEq(maxValue, 7, "Max value should be 7");
        assertEq(maxItemId, 2, "Max piece ID should be 2");
    }

    function testRemoveMax() public {
        setUp();

        // Insert and then remove max
        maxHeap.insert(1,5);
        maxHeap.insert(2,7);
        maxHeap.insert(3,3);
        maxHeap.extractMax();

        // Validate the new max value
        (uint256 maxItemId, uint256 maxValue) = maxHeap.getMax();
        assertEq(maxValue, 5, "New max value should be 5");
        assertEq(maxItemId, 1, "New max piece ID should be 1");
    }

    function testHeapify() public {
        setUp();

        // Insert values and manually violate the heap property
        maxHeap.insert(1,5);
        maxHeap.insert(2,7);
        maxHeap.insert(3, 15);
        maxHeap.insert(4, 3);
        //set max to [10,2]
        maxHeap._set(0, 10,2);  // Assume a '_set' function for testing

        // Run heapify from the root
        maxHeap.maxHeapify(0);

        // Validate the max value
        (uint256 maxItemId, uint256 correctedMaxValue) = maxHeap.getMax();
        assertEq(correctedMaxValue, 7, "Max value should be 7");
        assertEq(maxItemId, 2, "Max piece ID should be 2");
    }

    function testInsertDuplicateValues() public {
        setUp();
        maxHeap.insert(1,5);
        maxHeap.insert(2,5);
        maxHeap.insert(3,5);
        (uint256 maxItemId, uint256 maxValue) = maxHeap.getMax();
        assertEq(maxValue, 5, "Max value should still be 5");
        assertEq(maxItemId, 1, "Max piece ID should be 1");
        assertEq(maxHeap.size(), 3, "Size should be 3");
    }

    function testHeapEmptyAfterAllRemoved() public {
        setUp();
        maxHeap.insert(1,5);
        maxHeap.insert(2,7);
        maxHeap.extractMax();
        maxHeap.extractMax();
        assertEq(maxHeap.size(), 0, "Heap should be empty");
    }

    function testHeapProperty() public {
        setUp();
        uint256[] memory values = new uint256[](6);
        values[0] = 4;
        values[1] = 7;
        values[2] = 15;
        values[3] = 9;
        values[4] = 10;
        values[5] = 20;
        for (uint256 i = 0; i < values.length; i++) {
            maxHeap.insert(i, values[i]);
        }
        
        uint256 lastVal = type(uint256).max;  // Start with the maximum uint256 value
        while(maxHeap.size() > 0) {
            (, uint256 voteCount) = maxHeap.extractMax();
            assertTrue(voteCount <= lastVal, "Heap property violated");
            lastVal = voteCount;
        }
    }

    function testHeapifyOnNonRoot() public {
        setUp();
        maxHeap.insert(1,10);
        maxHeap.insert(2,15);
        maxHeap.insert(3,5);
        maxHeap.insert(4,12);
        maxHeap._set(1, 200,4);  // Assume a '_set' function for testing
        maxHeap.maxHeapify(1);
        (uint256 itemId, uint256 val) = maxHeap.heap(1);
        assertEq(val, 10, "Value should be 10 after heapify");
        assertEq(itemId, 1, "Item ID should be 1 after heapify");
    }

    function testCannotInsertWhenFull() public {
        setUp();

        // Fill the heap to its max size
        for(uint i = 0; i < maxHeap.maxsize(); i++) {
            maxHeap.insert(i, i);
        }

        // Try to insert again and expect to fail
        try maxHeap.insert(1,100) {
            fail("Should not be able to insert when heap is full");
        } catch Error(string memory reason) {
            assertEq(reason, "Heap is full");
        }
    }

    function testCannotRemoveMaxWhenEmpty() public {
        setUp();

        // Try to remove max and expect to fail
        try maxHeap.extractMax() {
            fail("Should not be able to remove max when heap is empty");
        } catch Error(string memory reason) {
            assertEq(reason, "Heap is empty");
        }
    }
}
