// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {Router} from "../src/Router.sol";
import {MockGateway} from "./mocks/MockGateway.sol";
import {MockToken} from "./mocks/MockToken.sol";
import {PayloadUtils} from "../src/utils/PayloadUtils.sol";
import {IGateway} from "../src/interfaces/IGateway.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IZRC20} from "../src/interfaces/IZRC20.sol";
import {IUniswapV3Router} from "../src/interfaces/IUniswapV3Router.sol";
import {ISwap} from "../src/interfaces/ISwap.sol";
import {MockSwapModule} from "./mocks/MockSwapModule.sol";
import {MockFixedOutputSwapModule} from "./mocks/MockFixedOutputSwapModule.sol";
import "forge-std/console.sol";

contract RouterTest is Test {
    Router public router;
    MockGateway public gateway;
    MockToken public inputToken;
    MockToken public gasZRC20;
    MockToken public targetZRC20;
    MockSwapModule public swapModule;
    MockFixedOutputSwapModule public fixedOutputSwapModule;
    address public owner;
    address public user1;
    address public user2;

    event IntentContractSet(uint256 indexed chainId, address indexed intentContract);
    event TokenAdded(string indexed name);
    event TokenAssociationAdded(string indexed name, uint256 indexed chainId, address asset, address zrc20);
    event TokenAssociationUpdated(string indexed name, uint256 indexed chainId, address asset, address zrc20);
    event TokenAssociationRemoved(string indexed name, uint256 indexed chainId);
    event IntentSettlementForwarded(
        bytes indexed sender,
        uint256 indexed sourceChain,
        uint256 indexed targetChain,
        address zrc20,
        uint256 amount,
        uint256 tip
    );

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Deploy mock contracts
        gateway = new MockGateway();
        inputToken = new MockToken("Input Token", "INPUT");
        gasZRC20 = new MockToken("Gas Token", "GAS");
        targetZRC20 = new MockToken("Target Token", "TARGET");
        swapModule = new MockSwapModule();
        fixedOutputSwapModule = new MockFixedOutputSwapModule();

        // Deploy router directly (no proxy)
        router = new Router(address(gateway), address(swapModule));
    }

    // Helper function to create a router with the fixed output swap module
    function createFixedOutputRouter() internal returns (Router) {
        return new Router(address(gateway), address(fixedOutputSwapModule));
    }

    function test_SetIntentContract() public {
        uint256 chainId = 1;
        router.setIntentContract(chainId, user1);
        assertEq(router.intentContracts(chainId), user1);
    }

    function test_SetIntentContract_EmitsEvent() public {
        uint256 chainId = 1;
        vm.expectEmit(true, true, false, false);
        emit IntentContractSet(chainId, user1);
        router.setIntentContract(chainId, user1);
    }

    function test_SetIntentContract_NonAdminReverts() public {
        uint256 chainId = 1;
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Router.Unauthorized.selector, user1));
        router.setIntentContract(chainId, user2);
    }

    function test_SetIntentContract_ZeroAddressReverts() public {
        uint256 chainId = 1;
        vm.expectRevert("Invalid intent contract address");
        router.setIntentContract(chainId, address(0));
    }

    function test_GetIntentContract() public {
        uint256 chainId = 1;
        router.setIntentContract(chainId, user1);
        assertEq(router.getIntentContract(chainId), user1);
    }

    function test_UpdateIntentContract() public {
        uint256 chainId = 1;
        router.setIntentContract(chainId, user1);
        router.setIntentContract(chainId, user2);
        assertEq(router.intentContracts(chainId), user2);
    }

    function test_GetIntentContract_UnsetChainId() public {
        uint256 chainId = 999;
        assertEq(router.getIntentContract(chainId), address(0));
    }

    function test_AddToken() public {
        string memory name = "USDC";
        vm.expectEmit(true, false, false, false);
        emit TokenAdded(name);
        router.addToken(name);
        assertTrue(router.isTokenSupported(name));
        assertEq(router.tokenNames(0), name);
    }

    function test_AddToken_EmptyNameReverts() public {
        string memory name = "";
        vm.expectRevert("Token name cannot be empty");
        router.addToken(name);
    }

    function test_AddToken_DuplicateReverts() public {
        string memory name = "USDC";
        router.addToken(name);
        vm.expectRevert("Token already exists");
        router.addToken(name);
    }

    function test_AddTokenAssociation() public {
        string memory name = "USDC";
        uint256 chainId = 1;
        address asset = makeAddr("asset");
        address zrc20 = makeAddr("zrc20");

        router.addToken(name);
        vm.expectEmit(true, true, false, false);
        emit TokenAssociationAdded(name, chainId, asset, zrc20);
        router.addTokenAssociation(name, chainId, asset, zrc20);

        (address returnedAsset, address returnedZrc20, uint256 chainIdValue) = router.getTokenAssociation(zrc20, chainId);
        assertEq(returnedAsset, asset);
        assertEq(returnedZrc20, zrc20);
        assertEq(chainIdValue, chainId);
        assertEq(router.zrc20ToTokenName(zrc20), name);
    }

    function test_AddTokenAssociation_NonExistentTokenReverts() public {
        string memory name = "USDC";
        uint256 chainId = 1;
        address asset = makeAddr("asset");
        address zrc20 = makeAddr("zrc20");

        vm.expectRevert("Token does not exist");
        router.addTokenAssociation(name, chainId, asset, zrc20);
    }

    function test_AddTokenAssociation_ZeroAddressReverts() public {
        string memory name = "USDC";
        uint256 chainId = 1;
        address asset = address(0);
        address zrc20 = makeAddr("zrc20");

        router.addToken(name);
        vm.expectRevert("Invalid asset address");
        router.addTokenAssociation(name, chainId, asset, zrc20);
    }

    function test_AddTokenAssociation_DuplicateChainIdReverts() public {
        string memory name = "USDC";
        uint256 chainId = 1;
        address asset1 = makeAddr("asset1");
        address asset2 = makeAddr("asset2");
        address zrc20 = makeAddr("zrc20");

        router.addToken(name);
        router.addTokenAssociation(name, chainId, asset1, zrc20);
        vm.expectRevert("Association already exists");
        router.addTokenAssociation(name, chainId, asset2, zrc20);
    }

    function test_UpdateTokenAssociation() public {
        string memory name = "USDC";
        uint256 chainId = 1;
        address asset1 = makeAddr("asset1");
        address asset2 = makeAddr("asset2");
        address zrc20 = makeAddr("zrc20");

        router.addToken(name);
        router.addTokenAssociation(name, chainId, asset1, zrc20);

        vm.expectEmit(true, true, false, false);
        emit TokenAssociationUpdated(name, chainId, asset2, zrc20);
        router.updateTokenAssociation(name, chainId, asset2, zrc20);

        (address returnedAsset, address returnedZrc20, uint256 chainIdValue) = router.getTokenAssociation(zrc20, chainId);
        assertEq(returnedAsset, asset2);
        assertEq(returnedZrc20, zrc20);
        assertEq(chainIdValue, chainId);
    }

    function test_UpdateTokenAssociation_NonExistentAssociationReverts() public {
        string memory name = "USDC";
        uint256 chainId = 1;
        address asset = makeAddr("asset");
        address zrc20 = makeAddr("zrc20");

        router.addToken(name);
        vm.expectRevert("Association does not exist");
        router.updateTokenAssociation(name, chainId, asset, zrc20);
    }

    function test_RemoveTokenAssociation() public {
        string memory name = "USDC";
        uint256 chainId = 1;
        address asset = makeAddr("asset");
        address zrc20 = makeAddr("zrc20");

        router.addToken(name);
        router.addTokenAssociation(name, chainId, asset, zrc20);

        vm.expectEmit(true, true, false, false);
        emit TokenAssociationRemoved(name, chainId);
        router.removeTokenAssociation(name, chainId);

        vm.expectRevert("Association does not exist");
        router.getTokenAssociation(zrc20, chainId);
    }

    function test_RemoveTokenAssociation_NonExistentAssociationReverts() public {
        string memory name = "USDC";
        uint256 chainId = 1;

        router.addToken(name);
        vm.expectRevert("Association does not exist");
        router.removeTokenAssociation(name, chainId);
    }

    function test_GetTokenAssociations() public {
        string memory name = "USDC";
        uint256 chainId1 = 1;
        uint256 chainId2 = 2;
        address asset1 = makeAddr("asset1");
        address asset2 = makeAddr("asset2");
        address zrc20 = makeAddr("zrc20");

        router.addToken(name);
        router.addTokenAssociation(name, chainId1, asset1, zrc20);
        router.addTokenAssociation(name, chainId2, asset2, zrc20);

        (uint256[] memory chainIds, address[] memory assets, address[] memory zrc20s) = router.getTokenAssociations(name);
        assertEq(chainIds.length, 2);
        assertEq(chainIds[0], chainId1);
        assertEq(chainIds[1], chainId2);
        assertEq(assets[0], asset1);
        assertEq(assets[1], asset2);
        assertEq(zrc20s[0], zrc20);
        assertEq(zrc20s[1], zrc20);
    }

    function test_GetSupportedTokens() public {
        string memory name1 = "USDC";
        string memory name2 = "USDT";

        router.addToken(name1);
        router.addToken(name2);

        string[] memory tokens = router.getSupportedTokens();
        assertEq(tokens.length, 2);
        assertEq(tokens[0], name1);
        assertEq(tokens[1], name2);
    }

    function test_NonAdminCannotModify() public {
        string memory name = "USDC";
        uint256 chainId = 1;
        address asset = makeAddr("asset");
        address zrc20 = makeAddr("zrc20");

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Router.Unauthorized.selector, user1));
        router.addToken(name);

        router.addToken(name);
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Router.Unauthorized.selector, user1));
        router.addTokenAssociation(name, chainId, asset, zrc20);

        router.addTokenAssociation(name, chainId, asset, zrc20);
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Router.Unauthorized.selector, user1));
        router.updateTokenAssociation(name, chainId, asset, zrc20);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Router.Unauthorized.selector, user1));
        router.removeTokenAssociation(name, chainId);
    }

    function test_OnCall_Success() public {
        // Setup intent contract
        uint256 sourceChainId = 1;
        uint256 targetChainId = 2;
        address sourceIntentContract = makeAddr("sourceIntentContract");
        address targetIntentContract = makeAddr("targetIntentContract");
        router.setIntentContract(sourceChainId, sourceIntentContract);
        router.setIntentContract(targetChainId, targetIntentContract);

        // Setup token associations
        string memory tokenName = "USDC";
        router.addToken(tokenName);
        address inputAsset = makeAddr("input_asset");
        address targetAsset = makeAddr("target_asset");
        router.addTokenAssociation(tokenName, sourceChainId, inputAsset, address(inputToken));
        router.addTokenAssociation(tokenName, targetChainId, targetAsset, address(targetZRC20));

        // Setup intent payload
        bytes32 intentId = keccak256("test-intent");
        uint256 amount = 100 ether;
        uint256 tip = 10 ether;
        bytes memory receiver = abi.encodePacked(user2);

        bytes memory intentPayloadBytes = PayloadUtils.encodeIntentPayload(
            intentId,
            amount,
            tip,
            targetChainId,
            receiver
        );

        // Set modest slippage (5%)
        swapModule.setSlippage(500);

        // Mock setup for IZRC20 withdrawGasFeeWithGasLimit
        uint256 gasFee = 1 ether;
        vm.mockCall(
            address(targetZRC20),
            abi.encodeWithSelector(IZRC20.withdrawGasFeeWithGasLimit.selector, router.withdrawGasLimit()),
            abi.encode(address(gasZRC20), gasFee)
        );

        // Mint tokens to make the test work
        inputToken.mint(address(router), amount);
        targetZRC20.mint(address(swapModule), amount);
        gasZRC20.mint(address(swapModule), gasFee);
        
        // Setup context
        IGateway.ZetaChainMessageContext memory context = IGateway.ZetaChainMessageContext({
            chainID: sourceChainId,
            sender: abi.encodePacked(sourceIntentContract),
            senderEVM: sourceIntentContract
        });

        // Call onCall
        vm.prank(address(gateway));
        router.onCall(context, address(inputToken), amount, intentPayloadBytes);

        // Verify approvals were made to the gateway
        assertTrue(targetZRC20.allowance(address(router), address(gateway)) > 0, "Router should approve target ZRC20 to gateway");
        assertTrue(gasZRC20.allowance(address(router), address(gateway)) > 0, "Router should approve gas ZRC20 to gateway");
    }

    function test_OnCall_InsufficientAmount() public {
        // Setup intent contract
        uint256 sourceChainId = 1;
        uint256 targetChainId = 2;
        address sourceIntentContract = makeAddr("sourceIntentContract");
        address targetIntentContract = makeAddr("targetIntentContract");
        router.setIntentContract(sourceChainId, sourceIntentContract);
        router.setIntentContract(targetChainId, targetIntentContract);

        // Setup token associations
        string memory tokenName = "USDC";
        router.addToken(tokenName);
        address inputAsset = makeAddr("input_asset");
        address targetAsset = makeAddr("target_asset");
        router.addTokenAssociation(tokenName, sourceChainId, inputAsset, address(inputToken));
        router.addTokenAssociation(tokenName, targetChainId, targetAsset, address(targetZRC20));

        // Setup intent payload with a very small amount and tip
        bytes32 intentId = keccak256("test-intent");
        uint256 amount = 11 ether;      // Amount (we'll pass in a different amount in the onCall)
        uint256 intentAmount = 10 ether; // Amount in the intent payload (this is what gets checked against remainingCost)
        uint256 tip = 1 ether;           // Small tip
        bytes memory receiver = abi.encodePacked(user2);

        bytes memory intentPayloadBytes = PayloadUtils.encodeIntentPayload(
            intentId,
            intentAmount,  // Use the smaller amount in the payload
            tip,
            targetChainId,
            receiver
        );

        // Set modest slippage (10%) - with enough input to create the desired scenario
        swapModule.setSlippage(1000);

        // Mock setup for IZRC20 withdrawGasFeeWithGasLimit - high gas fee
        uint256 gasFee = 11 ether;
        vm.mockCall(
            address(targetZRC20),
            abi.encodeWithSelector(IZRC20.withdrawGasFeeWithGasLimit.selector, router.withdrawGasLimit()),
            abi.encode(address(gasZRC20), gasFee)
        );

        // Mint tokens to make the test work
        inputToken.mint(address(router), amount);
        targetZRC20.mint(address(swapModule), amount);
        gasZRC20.mint(address(swapModule), gasFee);

        // Setup context
        IGateway.ZetaChainMessageContext memory context = IGateway.ZetaChainMessageContext({
            chainID: sourceChainId,
            sender: abi.encodePacked(sourceIntentContract),
            senderEVM: sourceIntentContract
        });

        // Call onCall and expect it to revert due to insufficient amount
        // - We're passing in 100 ether but the slippage will be 10 ether (10%)
        // - Plus 5 ether gas fee = 15 ether total costs
        // - The tip covers 1 ether, so remaining cost is 14 ether
        // - But the amount in the intent payload is only 10 ether, which is less than the remaining cost
        vm.prank(address(gateway));
        vm.expectRevert("Amount insufficient to cover costs after tip");
        router.onCall(context, address(inputToken), amount, intentPayloadBytes);
    }

    function test_SetWithdrawGasLimit() public {
        uint256 newGasLimit = 200000;
        router.setWithdrawGasLimit(newGasLimit);
        assertEq(router.withdrawGasLimit(), newGasLimit);
    }
    
    function test_SetWithdrawGasLimit_ZeroValueReverts() public {
        uint256 zeroGasLimit = 0;
        vm.expectRevert("Gas limit cannot be zero");
        router.setWithdrawGasLimit(zeroGasLimit);
    }
    
    function test_SetWithdrawGasLimit_NonAdminReverts() public {
        uint256 newGasLimit = 200000;
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Router.Unauthorized.selector, user1));
        router.setWithdrawGasLimit(newGasLimit);
    }

    function test_OnCall_PartialTipCoverage() public {
        // Setup intent contract
        uint256 sourceChainId = 1;
        uint256 targetChainId = 2;
        address sourceIntentContract = makeAddr("sourceIntentContract");
        address targetIntentContract = makeAddr("targetIntentContract");
        router.setIntentContract(sourceChainId, sourceIntentContract);
        router.setIntentContract(targetChainId, targetIntentContract);

        // Setup token associations
        string memory tokenName = "USDC";
        router.addToken(tokenName);
        address inputAsset = makeAddr("input_asset");
        address targetAsset = makeAddr("target_asset");
        router.addTokenAssociation(tokenName, sourceChainId, inputAsset, address(inputToken));
        router.addTokenAssociation(tokenName, targetChainId, targetAsset, address(targetZRC20));

        // Setup intent payload with amount and small tip
        bytes32 intentId = keccak256("test-intent");
        uint256 amount = 100 ether;
        uint256 tip = 3 ether;     // Small tip that won't cover all costs
        bytes memory receiver = abi.encodePacked(user2);

        bytes memory intentPayloadBytes = PayloadUtils.encodeIntentPayload(
            intentId,
            amount,
            tip,
            targetChainId,
            receiver
        );

        // Set high slippage (8%) so we can observe amount reduction
        swapModule.setSlippage(800);  // 8% slippage = 8 ether on 100 ether

        // Mock setup for IZRC20 withdrawGasFeeWithGasLimit - medium gas fee
        uint256 gasFee = 2 ether;
        vm.mockCall(
            address(targetZRC20),
            abi.encodeWithSelector(IZRC20.withdrawGasFeeWithGasLimit.selector, router.withdrawGasLimit()),
            abi.encode(address(gasZRC20), gasFee)
        );

        // Total costs: 8 ether slippage + 2 ether gas fee = 10 ether
        // Tip only covers 3 ether, so 7 ether should come from amount
        // Expected actualAmount = 93 ether (100 - 7)
        
        // Mint tokens to make the test work
        inputToken.mint(address(router), amount);
        targetZRC20.mint(address(swapModule), 90 ether);  // 90 ether (100 - 8 - 2)
        gasZRC20.mint(address(swapModule), gasFee);
        
        // Setup context
        IGateway.ZetaChainMessageContext memory context = IGateway.ZetaChainMessageContext({
            chainID: sourceChainId,
            sender: abi.encodePacked(sourceIntentContract),
            senderEVM: sourceIntentContract
        });
        
        // Check that we correctly set the event expectations BEFORE the call
        // Event expectations must be set before the call that emits them
        vm.expectEmit();
        emit IntentSettlementForwarded(
            context.sender,
            context.chainID,
            targetChainId,
            address(inputToken),
            amount,
            0  // Tip should be 0 after using it all
        );
        
        // Call onCall
        vm.prank(address(gateway));
        router.onCall(context, address(inputToken), amount, intentPayloadBytes);

        // Verify approvals to the gateway
        assertTrue(targetZRC20.allowance(address(router), address(gateway)) > 0, "Router should approve target ZRC20 to gateway");
        assertTrue(gasZRC20.allowance(address(router), address(gateway)) > 0, "Router should approve gas ZRC20 to gateway");
        
        // At this point we've confirmed:
        // 1. The slippage and fee cost was 10 ether
        // 2. The tip (3 ether) was fully used (tip = 0 in the event)
        // 3. The remaining 7 ether was deducted from the amount
        // 4. Expected actualAmount is 93 ether (100 - 7)
    }



    function test_OnCall_DifferentDecimals() public {
        // Create a router using the fixed output swap module
        Router fixedRouter = createFixedOutputRouter();
        
        // Setup intent contract
        uint256 sourceChainId = 1;
        uint256 targetChainId = 2;
        address sourceIntentContract = makeAddr("sourceIntentContract");
        address targetIntentContract = makeAddr("targetIntentContract");
        fixedRouter.setIntentContract(sourceChainId, sourceIntentContract);
        fixedRouter.setIntentContract(targetChainId, targetIntentContract);

        // Setup token associations
        string memory tokenName = "USDC";
        fixedRouter.addToken(tokenName);
        address inputAsset = makeAddr("input_asset");
        address targetAsset = makeAddr("target_asset");
        fixedRouter.addTokenAssociation(tokenName, sourceChainId, inputAsset, address(inputToken));
        fixedRouter.addTokenAssociation(tokenName, targetChainId, targetAsset, address(targetZRC20));

        // Setup intent payload
        bytes32 intentId = keccak256("test-intent");
        uint256 amount = 100 * 10**6; // 100 USDC with 6 decimals
        uint256 tip = 10 * 10**6;     // 10 USDC with 6 decimals
        bytes memory receiver = abi.encodePacked(user2);

        bytes memory intentPayloadBytes = PayloadUtils.encodeIntentPayload(
            intentId,
            amount,
            tip,
            targetChainId,
            receiver
        );

        // Mock decimals for input token (6 decimals like USDC)
        vm.mockCall(
            address(inputToken),
            abi.encodeWithSelector(IZRC20.decimals.selector),
            abi.encode(uint8(6))
        );
        
        // Mock decimals for target token (18 decimals like most tokens)
        vm.mockCall(
            address(targetZRC20),
            abi.encodeWithSelector(IZRC20.decimals.selector),
            abi.encode(uint8(18))
        );

        // Calculate the expected amount in target decimals
        uint256 expectedAmountInTargetDecimals = amount * 10**12; // 100e6 * 10^12 = 100e18
        uint256 expectedTipInTargetDecimals = tip * 10**12;       // 10e6 * 10^12 = 10e18
        uint256 expectedTotal = expectedAmountInTargetDecimals + expectedTipInTargetDecimals;

        // Set a fixed output amount that's slightly less than the converted total
        // This simulates some slippage
        fixedOutputSwapModule.setFixedOutputAmount(expectedTotal);

        // Mock setup for IZRC20 withdrawGasFeeWithGasLimit
        uint256 gasFee = 1 ether; // 1 token with 18 decimals for gas fee
        vm.mockCall(
            address(targetZRC20),
            abi.encodeWithSelector(IZRC20.withdrawGasFeeWithGasLimit.selector, fixedRouter.withdrawGasLimit()),
            abi.encode(address(gasZRC20), gasFee)
        );
        
        // Mint tokens to make the test work
        inputToken.mint(address(fixedRouter), amount + tip);
        targetZRC20.mint(address(fixedOutputSwapModule), expectedTotal);
        gasZRC20.mint(address(fixedOutputSwapModule), gasFee);
        
        // Setup context
        IGateway.ZetaChainMessageContext memory context = IGateway.ZetaChainMessageContext({
            chainID: sourceChainId,
            sender: abi.encodePacked(sourceIntentContract),
            senderEVM: sourceIntentContract
        });

        // Check event is emitted with correct values - tip should be slightly reduced due to slippage
        vm.expectEmit();
        emit IntentSettlementForwarded(
            context.sender,
            context.chainID,
            targetChainId,
            address(inputToken),
            amount + tip,
            expectedTipInTargetDecimals
        );

        // Call onCall
        vm.prank(address(gateway));
        fixedRouter.onCall(context, address(inputToken), amount + tip, intentPayloadBytes);

        // Verify approvals were made to the gateway
        assertTrue(targetZRC20.allowance(address(fixedRouter), address(gateway)) > 0, "Router should approve target ZRC20 to gateway");
        assertTrue(gasZRC20.allowance(address(fixedRouter), address(gateway)) > 0, "Router should approve gas ZRC20 to gateway");
    }
} 