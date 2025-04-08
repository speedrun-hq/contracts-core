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

        // Encode intent payload
        bytes memory encoded = PayloadUtils.encodeIntentPayload(
            intentId,
            amount,
            tip,
            targetChain,
            receiverBytes
        );

        // Decode intent payload
        PayloadUtils.IntentPayload memory decoded = PayloadUtils.decodeIntentPayload(encoded);

        // Assert all fields match
        assertEq(decoded.intentId, intentId, "Intent ID mismatch");
        assertEq(decoded.amount, amount, "Amount mismatch");
        assertEq(decoded.tip, tip, "Tip mismatch");
        assertEq(decoded.targetChain, targetChain, "Target chain mismatch");
        assertEq(keccak256(decoded.receiver), keccak256(receiverBytes), "Receiver bytes mismatch");
    }

    function test_EncodeDecodeIntentPayload_ZeroValues() public pure {
        // Create test data with zero values
        bytes32 intentId = bytes32(0);
        uint256 amount = 0;
        uint256 tip = 0;
        uint256 targetChain = 0;
        bytes memory receiverBytes = new bytes(20); // all zeros address

        // Encode intent payload
        bytes memory encoded = PayloadUtils.encodeIntentPayload(
            intentId,
            amount,
            tip,
            targetChain,
            receiverBytes
        );

        // Decode intent payload
        PayloadUtils.IntentPayload memory decoded = PayloadUtils.decodeIntentPayload(encoded);

        // Assert all fields match
        assertEq(decoded.intentId, intentId, "Intent ID mismatch");
        assertEq(decoded.amount, amount, "Amount mismatch");
        assertEq(decoded.tip, tip, "Tip mismatch");
        assertEq(decoded.targetChain, targetChain, "Target chain mismatch");
        assertEq(keccak256(decoded.receiver), keccak256(receiverBytes), "Receiver bytes mismatch");
    }

    function test_EncodeDecodeIntentPayload_LargeValues() public {
        // Create test data with large values
        bytes32 intentId = keccak256("test-intent-with-very-long-data");
        uint256 amount = type(uint256).max;
        uint256 tip = type(uint256).max - 1;
        uint256 targetChain = type(uint256).max - 2;
        address receiver = makeAddr("receiver");
        bytes memory receiverBytes = abi.encodePacked(receiver);

        // Encode intent payload
        bytes memory encoded = PayloadUtils.encodeIntentPayload(
            intentId,
            amount,
            tip,
            targetChain,
            receiverBytes
        );

        // Decode intent payload
        PayloadUtils.IntentPayload memory decoded = PayloadUtils.decodeIntentPayload(encoded);

        // Assert all fields match
        assertEq(decoded.intentId, intentId, "Intent ID mismatch");
        assertEq(decoded.amount, amount, "Amount mismatch");
        assertEq(decoded.tip, tip, "Tip mismatch");
        assertEq(decoded.targetChain, targetChain, "Target chain mismatch");
        assertEq(keccak256(decoded.receiver), keccak256(receiverBytes), "Receiver bytes mismatch");
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
        bytes memory encoded = PayloadUtils.encodeSettlementPayload(
            intentId,
            amount,
            asset,
            receiver,
            tip,
            actualAmount
        );

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
        bytes memory encoded = PayloadUtils.encodeSettlementPayload(
            intentId,
            amount,
            asset,
            receiver,
            tip,
            actualAmount
        );

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
        bytes memory encoded = PayloadUtils.encodeSettlementPayload(
            intentId,
            amount,
            asset,
            receiver,
            tip,
            actualAmount
        );

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
        
        bytes32 index = PayloadUtils.computeFulfillmentIndex(
            intentId,
            asset,
            amount,
            receiver
        );
        
        bytes32 expected = keccak256(abi.encodePacked(
            intentId,
            asset,
            amount,
            receiver
        ));
        
        assertEq(index, expected, "Fulfillment index computation failed");
    }

    function test_ComputeFulfillmentIndex_Uniqueness() public {
        // Test that different inputs produce different indices
        bytes32 intentId1 = keccak256("test-intent-1");
        bytes32 intentId2 = keccak256("test-intent-2");
        address asset = makeAddr("asset");
        uint256 amount = 1000 ether;
        address receiver = makeAddr("receiver");
        
        bytes32 index1 = PayloadUtils.computeFulfillmentIndex(
            intentId1,
            asset,
            amount,
            receiver
        );
        
        bytes32 index2 = PayloadUtils.computeFulfillmentIndex(
            intentId2,
            asset,
            amount,
            receiver
        );
        
        assertFalse(index1 == index2, "Indices should be different for different intent IDs");
        
        bytes32 index3 = PayloadUtils.computeFulfillmentIndex(
            intentId1,
            makeAddr("different-asset"),
            amount,
            receiver
        );
        
        assertFalse(index1 == index3, "Indices should be different for different assets");
        
        bytes32 index4 = PayloadUtils.computeFulfillmentIndex(
            intentId1,
            asset,
            amount + 1,
            receiver
        );
        
        assertFalse(index1 == index4, "Indices should be different for different amounts");
        
        bytes32 index5 = PayloadUtils.computeFulfillmentIndex(
            intentId1,
            asset,
            amount,
            makeAddr("different-receiver")
        );
        
        assertFalse(index1 == index5, "Indices should be different for different receivers");
    }
} 