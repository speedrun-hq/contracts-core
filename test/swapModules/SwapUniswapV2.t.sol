// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Test, console2} from "forge-std/Test.sol";
import {SwapUniswapV2} from "../../src/swapModules/SwapUniswapV2.sol";
import {IUniswapV2Router02} from "../../src/interfaces/IUniswapV2Router02.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}

contract MockUniswapV2Router is IUniswapV2Router02 {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256, /*amountOutMin*/
        address[] calldata path,
        address to,
        uint256 /*deadline*/
    ) external returns (uint256[] memory amounts) {
        // Mock 1:1 swap for testing
        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        IERC20(path[path.length - 1]).transfer(to, amountIn);

        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = amountIn;
    }

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256, /*amountInMax*/
        address[] calldata path,
        address to,
        uint256 /*deadline*/
    ) external returns (uint256[] memory amounts) {
        // Mock 1:1 swap for testing
        IERC20(path[0]).transferFrom(msg.sender, address(this), amountOut);
        IERC20(path[path.length - 1]).transfer(to, amountOut);

        amounts = new uint256[](2);
        amounts[0] = amountOut;
        amounts[1] = amountOut;
    }

    function getAmountsIn(uint256 amountOut, address[] calldata path)
        external
        pure
        returns (uint256[] memory amounts)
    {
        // Mock 1:1 swap for testing (amountIn = amountOut)
        amounts = new uint256[](path.length);
        for (uint256 i = 0; i < path.length; i++) {
            amounts[i] = amountOut;
        }
        return amounts;
    }

    function swapExactETHForTokens(uint256, address[] calldata, address, uint256)
        external
        payable
        returns (uint256[] memory)
    {
        // Not used in tests
        revert("Not implemented");
    }

    function swapTokensForExactETH(
        uint256, /*amountOut*/
        uint256, /*amountInMax*/
        address[] calldata, /*path*/
        address, /*to*/
        uint256 /*deadline*/
    ) external pure returns (uint256[] memory) {
        // Not used in tests
        revert("Not implemented");
    }

    function swapExactTokensForETH(uint256, uint256, address[] calldata, address, uint256)
        external
        pure
        returns (uint256[] memory)
    {
        // Not used in tests
        revert("Not implemented");
    }

    function swapETHForExactTokens(uint256, address[] calldata, address, uint256)
        external
        payable
        returns (uint256[] memory)
    {
        // Not used in tests
        revert("Not implemented");
    }
}

contract SwapUniswapV2Test is Test {
    SwapUniswapV2 public swapUniswapV2;
    MockUniswapV2Router public mockRouter;
    MockERC20 public wzeta;
    MockERC20 public inputToken;
    MockERC20 public outputToken;
    MockERC20 public gasToken;
    address public user;
    uint256 public constant AMOUNT = 1000 ether;
    uint256 public constant GAS_FEE = 100 ether;

    function setUp() public {
        // Deploy mock contracts
        mockRouter = new MockUniswapV2Router();
        wzeta = new MockERC20("Wrapped ZETA", "WZETA");
        inputToken = new MockERC20("Input Token", "INPUT");
        outputToken = new MockERC20("Output Token", "OUTPUT");
        gasToken = new MockERC20("Gas Token", "GAS");

        // Deploy SwapUniswapV2
        swapUniswapV2 = new SwapUniswapV2(address(mockRouter), address(wzeta));

        // Setup user
        user = makeAddr("user");
        inputToken.mint(user, AMOUNT);
        vm.prank(user);
        inputToken.approve(address(swapUniswapV2), AMOUNT);

        // Mint tokens to router for swaps
        wzeta.mint(address(mockRouter), AMOUNT);
        outputToken.mint(address(mockRouter), AMOUNT);
        gasToken.mint(address(mockRouter), AMOUNT);
    }

    function test_DeployInvalidRouterAddress() public {
        vm.expectRevert("Invalid swap router address");
        new SwapUniswapV2(address(0), address(wzeta));
    }

    function test_DeployInvalidWzetaAddress() public {
        vm.expectRevert("Invalid WZETA address");
        new SwapUniswapV2(address(mockRouter), address(0));
    }

    function test_Swap() public {
        uint256 initialBalance = inputToken.balanceOf(user);
        uint256 expectedOutput = AMOUNT - GAS_FEE; // 1:1 swap with gas fee deduction

        vm.prank(user);
        uint256 amountOut =
            swapUniswapV2.swap(address(inputToken), address(outputToken), AMOUNT, address(gasToken), GAS_FEE);

        assertEq(amountOut, expectedOutput, "Incorrect output amount");
        assertEq(inputToken.balanceOf(user), initialBalance - AMOUNT, "Input tokens not transferred from user");
        assertEq(inputToken.balanceOf(address(swapUniswapV2)), 0, "Input tokens should not remain in swap contract");
        assertEq(outputToken.balanceOf(user), expectedOutput, "Output tokens not received by user");
        assertEq(gasToken.balanceOf(user), GAS_FEE, "Gas tokens not received by swap contract");
    }

    function test_SwapWithZeroAmount() public {
        vm.prank(user);
        vm.expectRevert();
        swapUniswapV2.swap(address(inputToken), address(outputToken), 0, address(gasToken), GAS_FEE);
    }

    function test_SwapWithZeroGasFee() public {
        uint256 initialBalance = inputToken.balanceOf(user);
        uint256 expectedOutput = AMOUNT; // 1:1 swap with no gas fee deduction

        vm.prank(user);
        uint256 amountOut = swapUniswapV2.swap(address(inputToken), address(outputToken), AMOUNT, address(gasToken), 0);

        assertEq(amountOut, expectedOutput, "Incorrect output amount");
        assertEq(inputToken.balanceOf(user), initialBalance - AMOUNT, "Input tokens not transferred from user");
        assertEq(inputToken.balanceOf(address(swapUniswapV2)), 0, "Input tokens should not remain in swap contract");
        assertEq(outputToken.balanceOf(user), expectedOutput, "Output tokens not received by user");
        assertEq(gasToken.balanceOf(address(swapUniswapV2)), 0, "Gas tokens should not be received");
    }

    function test_SwapWithIgnoredTokenName() public {
        uint256 initialBalance = inputToken.balanceOf(user);
        uint256 expectedOutput = AMOUNT - GAS_FEE; // 1:1 swap with gas fee deduction

        vm.prank(user);
        uint256 amountOut =
            swapUniswapV2.swap(address(inputToken), address(outputToken), AMOUNT, address(gasToken), GAS_FEE, "ignored");

        assertEq(amountOut, expectedOutput, "Incorrect output amount");
        assertEq(inputToken.balanceOf(user), initialBalance - AMOUNT, "Input tokens not transferred from user");
        assertEq(inputToken.balanceOf(address(swapUniswapV2)), 0, "Input tokens should not remain in swap contract");
        assertEq(outputToken.balanceOf(user), expectedOutput, "Output tokens not received by user");
        assertEq(gasToken.balanceOf(user), GAS_FEE, "Gas tokens not received by swap contract");
    }
}
