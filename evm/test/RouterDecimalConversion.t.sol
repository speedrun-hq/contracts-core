// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import "../src/Router.sol";

/**
 * @title RouterDecimalConversionTest
 * @dev Tests the decimal conversion function in Router contract
 */
contract RouterDecimalConversionTest is Test {
    Router public router;

    function setUp() public {
        // Create a router with address(1) and address(2) as placeholders for gateway and swap module
        router = new Router(address(1), address(2));
    }

    /**
     * @dev Tests conversion when source and target decimals are the same
     */
    function testSameDecimals() public {
        uint256 amount = 1000000; // 1.0 tokens with 6 decimals
        uint8 decimalsIn = 6;
        uint8 decimalsOut = 6;
        
        uint256 result = callCalculateExpectedAmount(amount, decimalsIn, decimalsOut);
        
        assertEq(result, amount, "When decimals are the same, amount should not change");
    }

    /**
     * @dev Helper function to call router's calculateExpectedAmount function
     */
    function callCalculateExpectedAmount(
        uint256 amountIn,
        uint8 decimalsIn,
        uint8 decimalsOut
    ) private view returns (uint256) {
        // Call the function directly using the low-level call
        (bool success, bytes memory data) = address(router).staticcall(
            abi.encodeWithSignature(
                "calculateExpectedAmount(uint256,uint8,uint8)",
                amountIn,
                decimalsIn,
                decimalsOut
            )
        );
        
        require(success, "Call to calculateExpectedAmount failed");
        return abi.decode(data, (uint256));
    }

    /**
     * @dev Tests conversion when target has more decimals than source
     */
    function testMoreDecimalsOutput() public {
        // Test case 1: 6 to 18 decimals (common USDC scenario)
        uint256 amount1 = 1000000; // 1.0 USDC with 6 decimals
        uint8 decimalsIn1 = 6;
        uint8 decimalsOut1 = 18;
        
        uint256 expected1 = 1000000000000000000; // 1.0 with 18 decimals
        uint256 result1 = callCalculateExpectedAmount(amount1, decimalsIn1, decimalsOut1);
        
        assertEq(result1, expected1, "6 to 18 decimal conversion failed");
        
        // Test case 2: 8 to 18 decimals (BTC-like to ETH-like)
        uint256 amount2 = 12345678; // 0.12345678 BTC with 8 decimals
        uint8 decimalsIn2 = 8;
        uint8 decimalsOut2 = 18;
        
        uint256 expected2 = 123456780000000000; // 0.12345678 with 18 decimals
        uint256 result2 = callCalculateExpectedAmount(amount2, decimalsIn2, decimalsOut2);
        
        assertEq(result2, expected2, "8 to 18 decimal conversion failed");
        
        // Test case 3: 0 to 18 decimals (edge case)
        uint256 amount3 = 5; // 5 tokens with 0 decimals
        uint8 decimalsIn3 = 0;
        uint8 decimalsOut3 = 18;
        
        uint256 expected3 = 5000000000000000000; // 5.0 with 18 decimals
        uint256 result3 = callCalculateExpectedAmount(amount3, decimalsIn3, decimalsOut3);
        
        assertEq(result3, expected3, "0 to 18 decimal conversion failed");
    }

    /**
     * @dev Tests conversion when target has fewer decimals than source
     */
    function testFewerDecimalsOutput() public {
        // Test case 1: 18 to 6 decimals (ETH-like to USDC-like)
        uint256 amount1 = 1000000000000000000; // 1.0 with 18 decimals
        uint8 decimalsIn1 = 18;
        uint8 decimalsOut1 = 6;
        
        uint256 expected1 = 1000000; // 1.0 with 6 decimals
        uint256 result1 = callCalculateExpectedAmount(amount1, decimalsIn1, decimalsOut1);
        
        assertEq(result1, expected1, "18 to 6 decimal conversion failed");
        
        // Test case 2: 18 to 8 decimals (ETH-like to BTC-like)
        uint256 amount2 = 1234567890000000000; // 1.23456789 with 18 decimals
        uint8 decimalsIn2 = 18;
        uint8 decimalsOut2 = 8;
        
        uint256 expected2 = 123456789; // 1.23456789 with 8 decimals
        uint256 result2 = callCalculateExpectedAmount(amount2, decimalsIn2, decimalsOut2);
        
        assertEq(result2, expected2, "18 to 8 decimal conversion failed");
        
        // Test case 3: 18 to 0 decimals (edge case with rounding)
        uint256 amount3 = 5500000000000000000; // 5.5 with 18 decimals
        uint8 decimalsIn3 = 18;
        uint8 decimalsOut3 = 0;
        
        uint256 expected3 = 5; // 5 tokens with 0 decimals (truncated)
        uint256 result3 = callCalculateExpectedAmount(amount3, decimalsIn3, decimalsOut3);
        
        assertEq(result3, expected3, "18 to 0 decimal conversion failed (should truncate)");
    }

    /**
     * @dev Tests rounding behavior when reducing decimals
     */
    function testRoundingBehavior() public {
        // Test different rounding scenarios when reducing precision
        
        // Just below threshold (1.9999 -> 1)
        uint256 amount1 = 1999999999999999999; // 1.999999999999999999 with 18 decimals
        uint8 decimalsIn1 = 18;
        uint8 decimalsOut1 = 0;
        
        uint256 expected1 = 1; // Rounds down to 1
        uint256 result1 = callCalculateExpectedAmount(amount1, decimalsIn1, decimalsOut1);
        
        assertEq(result1, expected1, "Should round down to 1");
        
        // Exact threshold (2.0 -> 2)
        uint256 amount2 = 2000000000000000000; // 2.0 with 18 decimals
        uint8 decimalsIn2 = 18;
        uint8 decimalsOut2 = 0;
        
        uint256 expected2 = 2; // Exactly 2
        uint256 result2 = callCalculateExpectedAmount(amount2, decimalsIn2, decimalsOut2);
        
        assertEq(result2, expected2, "Should be exactly 2");
        
        // Just above threshold (2.0000...1 -> 2)
        uint256 amount3 = 2000000000000000001; // 2.000000000000000001 with 18 decimals
        uint8 decimalsIn3 = 18;
        uint8 decimalsOut3 = 0;
        
        uint256 expected3 = 2; // Still 2, fraction is truncated
        uint256 result3 = callCalculateExpectedAmount(amount3, decimalsIn3, decimalsOut3);
        
        assertEq(result3, expected3, "Should truncate and remain 2");
    }

    /**
     * @dev Tests for potential overflow when increasing decimals
     */
    function testLargeNumberConversion() public {
        // Test a large number that would overflow when multiplied by 10^18
        uint256 largeAmount = 115792089237316195423570985008687907853269984665640564039458; // Close to uint256 max / 10^18
        uint8 decimalsIn = 0;
        uint8 decimalsOut = 18;
        
        // This should revert due to overflow when multiplying by 10^18
        vm.expectRevert();
        callCalculateExpectedAmount(largeAmount, decimalsIn, decimalsOut);
    }
} 