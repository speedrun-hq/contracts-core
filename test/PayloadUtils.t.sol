// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {PayloadUtils} from "../src/utils/PayloadUtils.sol";

contract PayloadUtilsTest is Test {
    function setUp() public {}

    function test_EncodeDecodeIntentPayload() public {
        // Create test data
        bytes32 intentId = keccak256("test-intent");
        uint256 amount = 1000 ether;
        uint256 tip = 50 ether;
        uint256 targetChain = 42;
        address receiver = makeAddr("receiver");
        bytes memory receiverBytes = abi.encodePacked(receiver);
        bool isCall = false;
        bytes memory data = "";
        uint256 gasLimit = 300000;

        // Encode intent payload
        bytes memory encoded =
            PayloadUtils.encodeIntentPayload(intentId, amount, tip, targetChain, receiverBytes, isCall, data, gasLimit);

        // Decode intent payload
        PayloadUtils.IntentPayload memory decoded = PayloadUtils.decodeIntentPayload(encoded);

        // Assert all fields match
        assertEq(decoded.intentId, intentId, "Intent ID mismatch");
        assertEq(decoded.amount, amount, "Amount mismatch");
        assertEq(decoded.tip, tip, "Tip mismatch");
        assertEq(decoded.targetChain, targetChain, "Target chain mismatch");
        assertEq(keccak256(decoded.receiver), keccak256(receiverBytes), "Receiver bytes mismatch");
        assertEq(decoded.isCall, isCall, "isCall mismatch");
        assertEq(keccak256(decoded.data), keccak256(data), "Data mismatch");
        assertEq(decoded.gasLimit, gasLimit, "Gas limit mismatch");
    }

    function test_EncodeDecodeIntentPayload_ZeroValues() public pure {
        // Create test data with zero values
        bytes32 intentId = bytes32(0);
        uint256 amount = 0;
        uint256 tip = 0;
        uint256 targetChain = 0;
        bytes memory receiverBytes = new bytes(20); // all zeros address
        bool isCall = false;
        bytes memory data = "";
        uint256 gasLimit = 0;

        // Encode intent payload
        bytes memory encoded =
            PayloadUtils.encodeIntentPayload(intentId, amount, tip, targetChain, receiverBytes, isCall, data, gasLimit);

        // Decode intent payload
        PayloadUtils.IntentPayload memory decoded = PayloadUtils.decodeIntentPayload(encoded);

        // Assert all fields match
        assertEq(decoded.intentId, intentId, "Intent ID mismatch");
        assertEq(decoded.amount, amount, "Amount mismatch");
        assertEq(decoded.tip, tip, "Tip mismatch");
        assertEq(decoded.targetChain, targetChain, "Target chain mismatch");
        assertEq(keccak256(decoded.receiver), keccak256(receiverBytes), "Receiver bytes mismatch");
        assertEq(decoded.isCall, isCall, "isCall mismatch");
        assertEq(keccak256(decoded.data), keccak256(data), "Data mismatch");
        assertEq(decoded.gasLimit, gasLimit, "Gas limit mismatch");
    }

    function test_EncodeDecodeIntentPayload_LargeValues() public {
        // Create test data with large values
        bytes32 intentId = keccak256("test-intent-with-very-long-data");
        uint256 amount = type(uint256).max;
        uint256 tip = type(uint256).max - 1;
        uint256 targetChain = type(uint256).max - 2;
        address receiver = makeAddr("receiver");
        bytes memory receiverBytes = abi.encodePacked(receiver);
        bool isCall = true;
        bytes memory data = abi.encodePacked("some-long-data-for-the-call", uint256(123456789));
        uint256 gasLimit = type(uint256).max - 3;

        // Encode intent payload
        bytes memory encoded =
            PayloadUtils.encodeIntentPayload(intentId, amount, tip, targetChain, receiverBytes, isCall, data, gasLimit);

        // Decode intent payload
        PayloadUtils.IntentPayload memory decoded = PayloadUtils.decodeIntentPayload(encoded);

        // Assert all fields match
        assertEq(decoded.intentId, intentId, "Intent ID mismatch");
        assertEq(decoded.amount, amount, "Amount mismatch");
        assertEq(decoded.tip, tip, "Tip mismatch");
        assertEq(decoded.targetChain, targetChain, "Target chain mismatch");
        assertEq(keccak256(decoded.receiver), keccak256(receiverBytes), "Receiver bytes mismatch");
        assertEq(decoded.isCall, isCall, "isCall mismatch");
        assertEq(keccak256(decoded.data), keccak256(data), "Data mismatch");
        assertEq(decoded.gasLimit, gasLimit, "Gas limit mismatch");
    }

    function test_EncodeDecodeIntentPayload_CustomGasLimit() public {
        // Create test data with custom gas limit
        bytes32 intentId = keccak256("test-intent");
        uint256 amount = 1000 ether;
        uint256 tip = 50 ether;
        uint256 targetChain = 42;
        address receiver = makeAddr("receiver");
        bytes memory receiverBytes = abi.encodePacked(receiver);
        bool isCall = true;
        bytes memory data = "0x123456";
        uint256 gasLimit = 500000; // Custom gas limit

        // Encode intent payload
        bytes memory encoded =
            PayloadUtils.encodeIntentPayload(intentId, amount, tip, targetChain, receiverBytes, isCall, data, gasLimit);

        // Decode intent payload
        PayloadUtils.IntentPayload memory decoded = PayloadUtils.decodeIntentPayload(encoded);

        // Assert all fields match, especially the gas limit
        assertEq(decoded.intentId, intentId, "Intent ID mismatch");
        assertEq(decoded.amount, amount, "Amount mismatch");
        assertEq(decoded.tip, tip, "Tip mismatch");
        assertEq(decoded.targetChain, targetChain, "Target chain mismatch");
        assertEq(keccak256(decoded.receiver), keccak256(receiverBytes), "Receiver bytes mismatch");
        assertEq(decoded.isCall, isCall, "isCall mismatch");
        assertEq(keccak256(decoded.data), keccak256(data), "Data mismatch");
        assertEq(decoded.gasLimit, gasLimit, "Gas limit mismatch");
    }

    function test_EncodeDecodeSettlementPayload() public {
        // Create test data
        bytes32 intentId = keccak256("test-settlement");
        uint256 amount = 100 ether;
        address asset = makeAddr("asset");
        address receiver = makeAddr("receiver");
        uint256 tip = 50 ether;
        uint256 actualAmount = 95 ether;

        // Encode settlement payload
        bytes memory encoded =
            PayloadUtils.encodeSettlementPayload(intentId, amount, asset, receiver, tip, actualAmount);

        // Decode settlement payload
        PayloadUtils.SettlementPayload memory decoded = PayloadUtils.decodeSettlementPayload(encoded);

        // Assert all fields match
        assertEq(decoded.intentId, intentId, "Intent ID mismatch");
        assertEq(decoded.amount, amount, "Amount mismatch");
        assertEq(decoded.asset, asset, "Asset mismatch");
        assertEq(decoded.receiver, receiver, "Receiver mismatch");
        assertEq(decoded.tip, tip, "Tip mismatch");
        assertEq(decoded.actualAmount, actualAmount, "Actual amount mismatch");
    }

    function test_EncodeDecodeSettlementPayload_ZeroValues() public pure {
        // Create test data with zero values
        bytes32 intentId = bytes32(0);
        uint256 amount = 0;
        address asset = address(0);
        address receiver = address(0);
        uint256 tip = 0;
        uint256 actualAmount = 0;

        // Encode settlement payload
        bytes memory encoded =
            PayloadUtils.encodeSettlementPayload(intentId, amount, asset, receiver, tip, actualAmount);

        // Decode settlement payload
        PayloadUtils.SettlementPayload memory decoded = PayloadUtils.decodeSettlementPayload(encoded);

        // Assert all fields match
        assertEq(decoded.intentId, intentId, "Intent ID mismatch");
        assertEq(decoded.amount, amount, "Amount mismatch");
        assertEq(decoded.asset, asset, "Asset mismatch");
        assertEq(decoded.receiver, receiver, "Receiver mismatch");
        assertEq(decoded.tip, tip, "Tip mismatch");
        assertEq(decoded.actualAmount, actualAmount, "Actual amount mismatch");
    }

    function test_EncodeDecodeSettlementPayload_LargeValues() public {
        // Create test data with large values
        bytes32 intentId = keccak256("test-settlement-with-very-long-data");
        uint256 amount = type(uint256).max;
        address asset = makeAddr("asset");
        address receiver = makeAddr("receiver");
        uint256 tip = type(uint256).max - 1;
        uint256 actualAmount = type(uint256).max - 2;

        // Encode settlement payload
        bytes memory encoded =
            PayloadUtils.encodeSettlementPayload(intentId, amount, asset, receiver, tip, actualAmount);

        // Decode settlement payload
        PayloadUtils.SettlementPayload memory decoded = PayloadUtils.decodeSettlementPayload(encoded);

        // Assert all fields match
        assertEq(decoded.intentId, intentId, "Intent ID mismatch");
        assertEq(decoded.amount, amount, "Amount mismatch");
        assertEq(decoded.asset, asset, "Asset mismatch");
        assertEq(decoded.receiver, receiver, "Receiver mismatch");
        assertEq(decoded.tip, tip, "Tip mismatch");
        assertEq(decoded.actualAmount, actualAmount, "Actual amount mismatch");
    }

    function test_BytesToAddress_ExactSize() public {
        // Test with address data of exactly 20 bytes
        address expected = makeAddr("recipient");
        bytes memory addressBytes = abi.encodePacked(expected);
        address result = PayloadUtils.bytesToAddress(addressBytes);

        assertEq(result, expected, "Address conversion failed");
    }

    function test_BytesToAddress_LargerSize() public {
        // Test with address data of more than 20 bytes (should take first 20 bytes)
        address expected = makeAddr("recipient");
        bytes memory extraData = abi.encodePacked(expected, "extra data that should be ignored");
        address result = PayloadUtils.bytesToAddress(extraData);

        assertEq(result, expected, "Address conversion with extra data failed");
    }

    function test_BytesToAddress_TooSmall() public {
        // Test with data smaller than 20 bytes
        bytes memory tooSmall = new bytes(10); // Create a 10-byte array

        // Use try/catch to verify revert
        bool reverted = false;
        try this.callBytesToAddress(tooSmall) {
            // Should not reach here
        } catch Error(string memory reason) {
            // Check that it reverts with the expected reason
            assertEq(reason, "Invalid address length", "Incorrect revert reason");
            reverted = true;
        } catch {
            // Should not reach here
            fail();
        }

        assertTrue(reverted, "Function should have reverted");
    }

    // Helper function to call bytesToAddress externally
    function callBytesToAddress(bytes memory data) external pure returns (address) {
        return PayloadUtils.bytesToAddress(data);
    }

    function test_ComputeFulfillmentIndex() public {
        // Test the fulfillment index computation
        bytes32 intentId = keccak256("test-intent");
        address asset = makeAddr("asset");
        uint256 amount = 1000 ether;
        address receiver = makeAddr("receiver");
        bool isCall = false;
        bytes memory data = "";

        bytes32 index = PayloadUtils.computeFulfillmentIndex(intentId, asset, amount, receiver, isCall, data);

        bytes32 expected = keccak256(abi.encodePacked(intentId, asset, amount, receiver, isCall, data));

        assertEq(index, expected, "Fulfillment index computation failed");
    }

    function test_ComputeFulfillmentIndex_Uniqueness() public {
        // Test that different inputs produce different indices
        bytes32 intentId1 = keccak256("test-intent-1");
        bytes32 intentId2 = keccak256("test-intent-2");
        address asset = makeAddr("asset");
        uint256 amount = 1000 ether;
        address receiver = makeAddr("receiver");
        bool isCall = false;
        bytes memory data = "";

        bytes32 index1 = PayloadUtils.computeFulfillmentIndex(intentId1, asset, amount, receiver, isCall, data);

        bytes32 index2 = PayloadUtils.computeFulfillmentIndex(intentId2, asset, amount, receiver, isCall, data);

        assertFalse(index1 == index2, "Indices should be different for different intent IDs");

        bytes32 index3 =
            PayloadUtils.computeFulfillmentIndex(intentId1, makeAddr("different-asset"), amount, receiver, isCall, data);

        assertFalse(index1 == index3, "Indices should be different for different assets");

        bytes32 index4 = PayloadUtils.computeFulfillmentIndex(intentId1, asset, amount + 1, receiver, isCall, data);

        assertFalse(index1 == index4, "Indices should be different for different amounts");

        bytes32 index5 =
            PayloadUtils.computeFulfillmentIndex(intentId1, asset, amount, makeAddr("different-receiver"), isCall, data);

        assertFalse(index1 == index5, "Indices should be different for different receivers");

        // Also test with different isCall and data values
        bytes32 index6 = PayloadUtils.computeFulfillmentIndex(intentId1, asset, amount, receiver, true, data);

        assertFalse(index1 == index6, "Indices should be different for different isCall values");

        bytes32 index7 = PayloadUtils.computeFulfillmentIndex(intentId1, asset, amount, receiver, isCall, "some data");

        assertFalse(index1 == index7, "Indices should be different for different data values");
    }
}
