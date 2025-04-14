// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {SwapAlgebra} from "../../src/swapModules/SwapAlgebra.sol";
import {IUniswapV2Router02} from "../../src/interfaces/IUniswapV2Router02.sol";
import {IAlgebraFactory} from "../../src/interfaces/IAlgebraFactory.sol";
import {IAlgebraPool} from "../../src/interfaces/IAlgebraPool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

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

        amounts = new uint256[](path.length);
        for (uint256 i = 0; i < path.length; i++) {
            amounts[i] = amountIn;
        }
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

        amounts = new uint256[](path.length);
        for (uint256 i = 0; i < path.length; i++) {
            amounts[i] = amountOut;
        }
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

    // Unused functions required by the interface
    function swapExactETHForTokens(uint256, address[] calldata, address, uint256)
        external
        payable
        returns (uint256[] memory)
    {
        revert("Not implemented");
    }

    function swapTokensForExactETH(uint256, uint256, address[] calldata, address, uint256)
        external
        pure
        returns (uint256[] memory)
    {
        revert("Not implemented");
    }

    function swapExactTokensForETH(uint256, uint256, address[] calldata, address, uint256)
        external
        pure
        returns (uint256[] memory)
    {
        revert("Not implemented");
    }

    function swapETHForExactTokens(uint256, address[] calldata, address, uint256)
        external
        payable
        returns (uint256[] memory)
    {
        revert("Not implemented");
    }
}

contract MockAlgebraPool is IAlgebraPool {
    address public token0;
    address public token1;
    address private immutable factory;

    constructor(address _token0, address _token1, address _factory) {
        token0 = _token0;
        token1 = _token1;
        factory = _factory;
    }

    function swap(
        address recipient, 
        bool zeroToOne, 
        int256 amountRequired, 
        uint160 limitSqrtPrice, 
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1) {
        // Determine which token is being swapped in
        address tokenOut = zeroToOne ? token1 : token0;

        // Calculate the amount in (positive) and out (negative)
        uint256 amountIn = uint256(amountRequired);

        // Mock 1:1 swap for testing
        if (zeroToOne) {
            amount0 = int256(amountIn); // Positive (tokens in)
            amount1 = -int256(amountIn); // Negative (tokens out)
        } else {
            amount0 = -int256(amountIn); // Negative (tokens out)
            amount1 = int256(amountIn); // Positive (tokens in)
        }

        // Call the callback to get the input tokens
        SwapAlgebra(msg.sender).algebraSwapCallback(amount0, amount1, data);

        // Check output token balance
        uint256 outTokenBalance = IERC20(tokenOut).balanceOf(address(this));
        require(outTokenBalance >= amountIn, "Insufficient output token balance");

        // Transfer output tokens to the recipient
        IERC20(tokenOut).transfer(recipient, amountIn);
    }
}

contract MockAlgebraFactory is IAlgebraFactory {
    mapping(address => mapping(address => address)) private _pools;

    function poolByPair(address tokenA, address tokenB) external view returns (address pool) {
        return _getPool(tokenA, tokenB);
    }

    function createPool(address tokenA, address tokenB) external returns (address pool) {
        require(tokenA != tokenB, "Identical tokens");
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "Zero address");
        require(_pools[token0][token1] == address(0), "Pool already exists");

        pool = address(new MockAlgebraPool(token0, token1, address(this)));
        _pools[token0][token1] = pool;
        _pools[token1][token0] = pool; // Also store the reverse direction

        return pool;
    }

    function _getPool(address tokenA, address tokenB) internal view returns (address) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        return _pools[token0][token1];
    }

    // Helper function for tests to set a pool
    function setPool(address tokenA, address tokenB, address pool) external {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        _pools[token0][token1] = pool;
        _pools[token1][token0] = pool;
    }
}

contract SwapAlgebraTest is Test {
    SwapAlgebra public swapAlgebra;
    MockUniswapV2Router public mockUniswapV2Router;
    MockAlgebraFactory public mockAlgebraFactory;
    MockAlgebraPool public mockAlgebraPool;
    MockERC20 public wzeta;
    MockERC20 public inputToken;
    MockERC20 public outputToken;
    MockERC20 public gasToken;
    MockERC20 public intermediaryToken;
    address public user;
    uint256 public constant AMOUNT = 1000 ether;
    uint256 public constant GAS_FEE = 100 ether;
    string public constant TOKEN_NAME = "TEST_TOKEN";

    function setUp() public {
        // Deploy mock contracts
        mockUniswapV2Router = new MockUniswapV2Router();
        mockAlgebraFactory = new MockAlgebraFactory();

        wzeta = new MockERC20("Wrapped ZETA", "WZETA");
        inputToken = new MockERC20("Input Token", "INPUT");
        outputToken = new MockERC20("Output Token", "OUTPUT");
        gasToken = new MockERC20("Gas Token", "GAS");
        intermediaryToken = new MockERC20("Intermediary Token", "INTER");

        // Create the Algebra pool for direct swap
        mockAlgebraPool = new MockAlgebraPool(address(inputToken), address(outputToken), address(mockAlgebraFactory));

        // Register the pool with the factory
        mockAlgebraFactory.setPool(address(inputToken), address(outputToken), address(mockAlgebraPool));

        // Deploy SwapAlgebra
        swapAlgebra = new SwapAlgebra(address(mockAlgebraFactory), address(mockUniswapV2Router), address(wzeta));

        // Setup user
        user = makeAddr("user");
        inputToken.mint(user, AMOUNT * 10);
        vm.prank(user);
        inputToken.approve(address(swapAlgebra), AMOUNT * 10);

        // Mint tokens to the mock contracts for swaps
        wzeta.mint(address(mockUniswapV2Router), AMOUNT * 10);
        gasToken.mint(address(mockUniswapV2Router), AMOUNT * 10);
        outputToken.mint(address(mockAlgebraPool), AMOUNT * 10);

        // Also mint some intermediary tokens for potential intermediary swaps
        intermediaryToken.mint(address(this), AMOUNT * 10);
    }

    function test_SwapWithGasFee() public {
        uint256 initialBalance = inputToken.balanceOf(user);
        uint256 expectedOutput = AMOUNT - GAS_FEE; // 1:1 swap with gas fee deduction

        vm.prank(user);
        uint256 amountOut =
            swapAlgebra.swap(address(inputToken), address(outputToken), AMOUNT, address(gasToken), GAS_FEE);

        assertEq(amountOut, expectedOutput, "Incorrect output amount");
        assertEq(inputToken.balanceOf(user), initialBalance - AMOUNT, "Input tokens not transferred from user");
        assertEq(outputToken.balanceOf(user), expectedOutput, "Output tokens not received by user");
        assertEq(gasToken.balanceOf(user), GAS_FEE, "Gas tokens not received by user");
    }

    function test_SwapWithoutGasFee() public {
        uint256 initialBalance = inputToken.balanceOf(user);
        uint256 expectedOutput = AMOUNT; // 1:1 swap with no gas fee

        vm.prank(user);
        uint256 amountOut = swapAlgebra.swap(address(inputToken), address(outputToken), AMOUNT, address(gasToken), 0);

        assertEq(amountOut, expectedOutput, "Incorrect output amount");
        assertEq(inputToken.balanceOf(user), initialBalance - AMOUNT, "Input tokens not transferred from user");
        assertEq(outputToken.balanceOf(user), expectedOutput, "Output tokens not received by user");
        assertEq(gasToken.balanceOf(user), 0, "No gas tokens should be received");
    }

    function test_SwapWithInputTokenAsGasToken() public {
        // Setup: user has gas tokens
        gasToken.mint(user, AMOUNT);
        vm.prank(user);
        gasToken.approve(address(swapAlgebra), AMOUNT);

        // Create the Algebra pool for gas token to output token
        MockAlgebraPool gasToOutputPool =
            new MockAlgebraPool(address(gasToken), address(outputToken), address(mockAlgebraFactory));

        // Register the pool with the factory
        mockAlgebraFactory.setPool(address(gasToken), address(outputToken), address(gasToOutputPool));

        // Mint output tokens to the pool
        outputToken.mint(address(gasToOutputPool), AMOUNT);

        uint256 initialBalance = gasToken.balanceOf(user);
        uint256 gasFeeAmount = 100 ether;
        uint256 expectedOutput = AMOUNT - gasFeeAmount; // 1:1 swap with gas fee deduction

        vm.prank(user);
        uint256 amountOut =
            swapAlgebra.swap(address(gasToken), address(outputToken), AMOUNT, address(gasToken), gasFeeAmount);

        assertEq(amountOut, expectedOutput, "Incorrect output amount");
        assertEq(gasToken.balanceOf(user), initialBalance - AMOUNT + gasFeeAmount, "Gas tokens not correctly handled");
        assertEq(outputToken.balanceOf(user), expectedOutput, "Output tokens not received by user");
    }

    function test_SwapThroughIntermediary() public {
        // Remove the direct pool
        mockAlgebraFactory.setPool(address(inputToken), address(outputToken), address(0));

        // Create pools with intermediary token
        MockAlgebraPool inToInterPool =
            new MockAlgebraPool(address(inputToken), address(intermediaryToken), address(mockAlgebraFactory));

        MockAlgebraPool interToOutPool =
            new MockAlgebraPool(address(intermediaryToken), address(outputToken), address(mockAlgebraFactory));

        // Register the pools with the factory
        mockAlgebraFactory.setPool(address(inputToken), address(intermediaryToken), address(inToInterPool));
        mockAlgebraFactory.setPool(address(intermediaryToken), address(outputToken), address(interToOutPool));

        console2.log("Initial Setup:");
        console2.log("inToInterPool address:", address(inToInterPool));
        console2.log("interToOutPool address:", address(interToOutPool));

        // IMPORTANT: Mint ALL tokens to ALL places they're needed
        // The first pool needs BOTH tokens for proper operation
        inputToken.mint(address(inToInterPool), AMOUNT * 2);
        intermediaryToken.mint(address(inToInterPool), AMOUNT * 2);

        // The second pool also needs BOTH tokens
        intermediaryToken.mint(address(interToOutPool), AMOUNT * 2);
        outputToken.mint(address(interToOutPool), AMOUNT * 2);

        // Gas token for UniswapV2Router
        gasToken.mint(address(mockUniswapV2Router), AMOUNT);

        // IMPORTANT FIX: Mint input tokens directly to the swap contract
        // This is because the tokens flow: user -> swapModule -> pool -> swapModule -> user
        // In a real environment, the swapModule would have tokens from the user
        inputToken.mint(address(swapAlgebra), AMOUNT);
        // Also mint intermediary tokens to swap contract for the second pool transfer
        // Mint 10x more intermediary tokens to ensure there's enough for the second swap
        intermediaryToken.mint(address(swapAlgebra), AMOUNT * 10);

        console2.log("Token Balances After Minting:");
        console2.log("inputToken in inToInterPool:", inputToken.balanceOf(address(inToInterPool)));
        console2.log("intermediaryToken in inToInterPool:", intermediaryToken.balanceOf(address(inToInterPool)));
        console2.log("intermediaryToken in interToOutPool:", intermediaryToken.balanceOf(address(interToOutPool)));
        console2.log("outputToken in interToOutPool:", outputToken.balanceOf(address(interToOutPool)));
        console2.log("inputToken in swapAlgebra:", inputToken.balanceOf(address(swapAlgebra)));
        console2.log("intermediaryToken in swapAlgebra:", intermediaryToken.balanceOf(address(swapAlgebra)));
        console2.log("gasToken in mockUniswapV2Router:", gasToken.balanceOf(address(mockUniswapV2Router)));

        // Set the intermediary token for the token name
        swapAlgebra.setIntermediaryToken(TOKEN_NAME, address(intermediaryToken));

        console2.log("Intermediary token set:", intermediaryToken.symbol());

        uint256 initialBalance = inputToken.balanceOf(user);
        uint256 expectedOutput = AMOUNT - GAS_FEE; // 1:1 swap with gas fee deduction

        console2.log("User initial balance:", initialBalance / 1e18, "ETH");
        console2.log("Expected output:", expectedOutput / 1e18, "ETH");

        vm.prank(user);
        uint256 amountOut =
            swapAlgebra.swap(address(inputToken), address(outputToken), AMOUNT, address(gasToken), GAS_FEE, TOKEN_NAME);

        console2.log("Swap completed with amountOut:", amountOut / 1e18, "ETH");

        assertEq(amountOut, expectedOutput, "Incorrect output amount");
        assertEq(inputToken.balanceOf(user), initialBalance - AMOUNT, "Input tokens not transferred from user");
        assertEq(outputToken.balanceOf(user), expectedOutput, "Output tokens not received by user");
        assertEq(gasToken.balanceOf(user), GAS_FEE, "Gas tokens not received by user");
    }

    function test_RevertWhenNoIntermediarySet() public {
        // Remove the direct pool
        mockAlgebraFactory.setPool(address(inputToken), address(outputToken), address(0));

        vm.prank(user);
        vm.expectRevert("No intermediary token set for this token name");
        swapAlgebra.swap(address(inputToken), address(outputToken), AMOUNT, address(gasToken), GAS_FEE, TOKEN_NAME);
    }

    function test_RevertWhenPoolsDoNotExist() public {
        // Remove the direct pool
        mockAlgebraFactory.setPool(address(inputToken), address(outputToken), address(0));

        // Set the intermediary token but don't create the pools
        swapAlgebra.setIntermediaryToken(TOKEN_NAME, address(intermediaryToken));

        vm.prank(user);
        vm.expectRevert("Required Algebra pools do not exist");
        swapAlgebra.swap(address(inputToken), address(outputToken), AMOUNT, address(gasToken), GAS_FEE, TOKEN_NAME);
    }
}
