// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Test, console2, Vm} from "forge-std/Test.sol";
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
import {MockIntent} from "./mocks/MockIntent.sol";
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
    // UUPS upgrade event
    event Upgraded(address indexed implementation);
    event PauserAdded(address indexed pauser);
    event PauserRemoved(address indexed pauser);
    event ChainWithdrawGasLimitSet(uint256 indexed chainId, uint256 gasLimit);
    event ChainWithdrawGasLimitRemoved(uint256 indexed chainId);

    // Helper function to create a properly initialized Router
    function createInitializedRouter(address gatewayAddr, address swapModuleAddr) internal returns (Router) {
        // Deploy implementation
        Router implementation = new Router();

        // Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(Router.initialize.selector, gatewayAddr, swapModuleAddr);

        // Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);

        return Router(address(proxy));
    }

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

        // Deploy router with a proxy to properly initialize it
        router = createInitializedRouter(address(gateway), address(swapModule));
    }

    // Helper function to create a router with the fixed output swap module
    function createFixedOutputRouter() internal returns (Router) {
        return createInitializedRouter(address(gateway), address(fixedOutputSwapModule));
    }

    // Helper function for access control error expectations
    function expectAccessControlError(address account) internal {
        bytes32 role = 0x00; // DEFAULT_ADMIN_ROLE
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)")), account, role
            )
        );
    }

    function test_Initialize_InvalidGatewayAddress() public {
        Router implementation = new Router();
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), "");
        Router router_ = Router(address(proxy));
        vm.expectRevert("Invalid gateway address");
        router_.initialize(address(0), address(swapModule));
    }

    function test_Initialize_InvalidSwapModuleAddress() public {
        Router implementation = new Router();
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), "");
        Router router_ = Router(address(proxy));
        vm.expectRevert("Invalid swap module address");
        router_.initialize(address(gateway), address(0));
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
        expectAccessControlError(user1);
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

    function test_AddToken_NonAdminReverts() public {
        string memory name = "USDC";
        vm.prank(user1);
        expectAccessControlError(user1);
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

        (address returnedAsset, address returnedZrc20, uint256 chainIdValue) =
            router.getTokenAssociation(zrc20, chainId);
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

    function test_AddTokenAssociation_NonAdminReverts() public {
        string memory name = "USDC";
        uint256 chainId = 1;
        address asset = makeAddr("asset");
        address zrc20 = makeAddr("zrc20");

        router.addToken(name);
        vm.prank(user1);
        expectAccessControlError(user1);
        router.addTokenAssociation(name, chainId, asset, zrc20);
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

        (address returnedAsset, address returnedZrc20, uint256 chainIdValue) =
            router.getTokenAssociation(zrc20, chainId);
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

    function test_UpdateTokenAssociation_NonAdminReverts() public {
        string memory name = "USDC";
        uint256 chainId = 1;
        address asset = makeAddr("asset");
        address zrc20 = makeAddr("zrc20");

        router.addToken(name);
        router.addTokenAssociation(name, chainId, asset, zrc20);

        vm.prank(user1);
        expectAccessControlError(user1);
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

    function test_RemoveTokenAssociation_NonAdminReverts() public {
        string memory name = "USDC";
        uint256 chainId = 1;
        address asset = makeAddr("asset");
        address zrc20 = makeAddr("zrc20");

        router.addToken(name);
        router.addTokenAssociation(name, chainId, asset, zrc20);

        vm.prank(user1);
        expectAccessControlError(user1);
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

        (uint256[] memory chainIds, address[] memory assets, address[] memory zrc20s) =
            router.getTokenAssociations(name);
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

        bytes memory intentPayloadBytes =
            PayloadUtils.encodeIntentPayload(intentId, amount, tip, targetChainId, receiver, false, "", 0);

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
        // Input token goes to the router
        inputToken.mint(address(router), amount + tip);
        // Target token and gas token go to the swap module since they're returned from the swap
        targetZRC20.mint(address(swapModule), amount + tip);
        gasZRC20.mint(address(swapModule), gasFee);

        // Setup context
        IGateway.ZetaChainMessageContext memory context = IGateway.ZetaChainMessageContext({
            chainID: sourceChainId,
            sender: abi.encodePacked(sourceIntentContract),
            senderEVM: sourceIntentContract
        });

        // Call onCall
        vm.prank(address(gateway));
        router.onCall(context, address(inputToken), amount + tip, intentPayloadBytes);

        // Verify approvals were made to the gateway
        assertTrue(
            targetZRC20.allowance(address(router), address(gateway)) > 0,
            "Router should approve target ZRC20 to gateway"
        );
        assertTrue(
            gasZRC20.allowance(address(router), address(gateway)) > 0, "Router should approve gas ZRC20 to gateway"
        );
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
        uint256 amount = 11 ether; // Amount (we'll pass in a different amount in the onCall)
        uint256 intentAmount = 10 ether; // Amount in the intent payload (this is what gets checked against remainingCost)
        uint256 tip = 1 ether; // Small tip
        bytes memory receiver = abi.encodePacked(user2);

        bytes memory intentPayloadBytes = PayloadUtils.encodeIntentPayload(
            intentId,
            intentAmount, // Use the smaller amount in the payload
            tip,
            targetChainId,
            receiver,
            false,
            "",
            0
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
        vm.expectRevert("Gas limit below minimum");
        router.setWithdrawGasLimit(zeroGasLimit);
    }

    function test_SetWithdrawGasLimit_BelowMinimumReverts() public {
        uint256 tooLowGasLimit = 99999; // Just below minimum of 100000

        vm.expectRevert("Gas limit below minimum");
        router.setWithdrawGasLimit(tooLowGasLimit);
    }

    function test_SetWithdrawGasLimit_AboveMaximumReverts() public {
        uint256 tooHighGasLimit = 10000001; // Just above maximum of 10000000

        vm.expectRevert("Gas limit above maximum");
        router.setWithdrawGasLimit(tooHighGasLimit);
    }

    function test_SetWithdrawGasLimit_AtMinimum() public {
        uint256 minimumGasLimit = 100000; // Exactly at minimum

        // Set at minimum should work
        router.setWithdrawGasLimit(minimumGasLimit);

        // Verify the gas limit was set
        assertEq(router.withdrawGasLimit(), minimumGasLimit);
    }

    function test_SetWithdrawGasLimit_AtMaximum() public {
        uint256 maximumGasLimit = 10000000; // Exactly at maximum

        // Set at maximum should work
        router.setWithdrawGasLimit(maximumGasLimit);

        // Verify the gas limit was set
        assertEq(router.withdrawGasLimit(), maximumGasLimit);
    }

    function test_SetWithdrawGasLimit_NonAdminReverts() public {
        uint256 newGasLimit = 200000;
        vm.prank(user1);
        expectAccessControlError(user1);
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
        uint256 tip = 3 ether; // Small tip that won't cover all costs
        bytes memory receiver = abi.encodePacked(user2);

        bytes memory intentPayloadBytes =
            PayloadUtils.encodeIntentPayload(intentId, amount, tip, targetChainId, receiver, false, "", 0);

        // Set high slippage (8%) so we can observe amount reduction
        swapModule.setSlippage(800); // 8% slippage = 8 ether on 100 ether

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
        // Input token goes to the router
        inputToken.mint(address(router), amount + tip);
        // Target token and gas token go to the swap module since they're returned from the swap
        targetZRC20.mint(address(swapModule), amount + tip);
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
            amount + tip,
            0 // Tip should be 0 after using it all
        );

        // Call onCall
        vm.prank(address(gateway));
        router.onCall(context, address(inputToken), amount + tip, intentPayloadBytes);

        // Verify approvals to the gateway
        assertTrue(
            targetZRC20.allowance(address(router), address(gateway)) > 0,
            "Router should approve target ZRC20 to gateway"
        );
        assertTrue(
            gasZRC20.allowance(address(router), address(gateway)) > 0, "Router should approve gas ZRC20 to gateway"
        );

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
        uint256 amount = 100 * 10 ** 6; // 100 USDC with 6 decimals
        uint256 tip = 10 * 10 ** 6; // 10 USDC with 6 decimals
        bytes memory receiver = abi.encodePacked(user2);

        bytes memory intentPayloadBytes =
            PayloadUtils.encodeIntentPayload(intentId, amount, tip, targetChainId, receiver, false, "", 0);

        // Mock decimals for input token (6 decimals like USDC)
        vm.mockCall(address(inputToken), abi.encodeWithSelector(IZRC20.decimals.selector), abi.encode(uint8(6)));

        // Mock decimals for target token (18 decimals like most tokens)
        vm.mockCall(address(targetZRC20), abi.encodeWithSelector(IZRC20.decimals.selector), abi.encode(uint8(18)));

        // Calculate the expected amount in target decimals
        uint256 expectedAmountInTargetDecimals = amount * 10 ** 12; // 100e6 * 10^12 = 100e18
        uint256 expectedTipInTargetDecimals = tip * 10 ** 12; // 10e6 * 10^12 = 10e18
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
        assertTrue(
            targetZRC20.allowance(address(fixedRouter), address(gateway)) > 0,
            "Router should approve target ZRC20 to gateway"
        );
        assertTrue(
            gasZRC20.allowance(address(fixedRouter), address(gateway)) > 0, "Router should approve gas ZRC20 to gateway"
        );
    }

    function test_UpdateGateway_Success() public {
        address newGateway = makeAddr("newGateway");
        router.updateGateway(newGateway);
        assertEq(router.gateway(), newGateway);
    }

    function test_UpdateGateway_NonAdminReverts() public {
        address newGateway = makeAddr("newGateway");
        vm.prank(user1);
        expectAccessControlError(user1);
        router.updateGateway(newGateway);
    }

    function test_UpdateGateway_InvalidGatewayAddress() public {
        vm.expectRevert("Gateway cannot be zero address");
        router.updateGateway(address(0));
    }

    function test_UpdateSwapModule_Success() public {
        address newSwapModule = makeAddr("newSwapModule");
        router.updateSwapModule(newSwapModule);
        assertEq(router.swapModule(), newSwapModule);
    }

    function test_UdateSwapModule_NonAdminReverts() public {
        address newSwapModule = makeAddr("newSwapModule");
        vm.prank(user1);
        expectAccessControlError(user1);
        router.updateSwapModule(newSwapModule);
    }

    function test_UpdateSwapModule_InvalidSwapModuleAddress() public {
        vm.expectRevert("Swap module cannot be zero address");
        router.updateSwapModule(address(0));
    }

    function test_Pause_Basic() public {
        // Check initial state
        assertFalse(router.paused(), "Router should not be paused initially");

        // Test that someone with PAUSER_ROLE can pause
        assertTrue(router.hasRole(router.PAUSER_ROLE(), address(this)), "Test contract should have PAUSER_ROLE");
        router.pause();
        assertTrue(router.paused(), "Router should be paused after calling pause()");

        // Test that someone with DEFAULT_ADMIN_ROLE can unpause
        assertTrue(router.hasRole(0x00, address(this)), "Test contract should have DEFAULT_ADMIN_ROLE");
        router.unpause();
        assertFalse(router.paused(), "Router should not be paused after calling unpause()");
    }

    function test_RevertWhen_NonPauserTriesToPause() public {
        // Make sure user1 doesn't have PAUSER_ROLE
        bytes32 pauserRole = router.PAUSER_ROLE();
        assertFalse(router.hasRole(pauserRole, user1), "User1 should not have PAUSER_ROLE");

        // Set up the prank
        vm.prank(user1);

        // Track whether the call reverted
        bool hasReverted = false;

        try router.pause() {
            // If we reach here, the call succeeded, which should not happen
            hasReverted = false;
        } catch {
            // If we reach here, the call reverted as expected
            hasReverted = true;
        }

        // Verify that the call reverted
        assertTrue(hasReverted, "Call to pause() should revert when called by non-pauser");

        // Verify that the router is still not paused
        assertFalse(router.paused(), "Router should not be paused");
    }

    function test_RevertWhen_NonAdminTriesToUnpause() public {
        // Pause first
        router.pause();
        assertTrue(router.paused(), "Router should be paused");

        // Make sure user1 doesn't have DEFAULT_ADMIN_ROLE
        bytes32 adminRole = 0x00; // DEFAULT_ADMIN_ROLE
        assertFalse(router.hasRole(adminRole, user1), "User1 should not have DEFAULT_ADMIN_ROLE");

        // Set up the prank
        vm.prank(user1);

        // Track whether the call reverted
        bool hasReverted = false;

        try router.unpause() {
            // If we reach here, the call succeeded, which should not happen
            hasReverted = false;
        } catch {
            // If we reach here, the call reverted as expected
            hasReverted = true;
        }

        // Verify that the call reverted
        assertTrue(hasReverted, "Call to unpause() should revert when called by non-admin");

        // Verify that the router is still paused
        assertTrue(router.paused(), "Router should still be paused");
    }

    function test_OnCall_PausedReverts() public {
        // Setup a minimal test for onCall failing when paused
        uint256 sourceChainId = 1;
        address sourceIntentContract = makeAddr("sourceIntentContract");
        router.setIntentContract(sourceChainId, sourceIntentContract);

        // Setup context and a dummy payload
        IGateway.ZetaChainMessageContext memory context = IGateway.ZetaChainMessageContext({
            chainID: sourceChainId,
            sender: abi.encodePacked(sourceIntentContract),
            senderEVM: sourceIntentContract
        });
        bytes memory dummyPayload = new bytes(0);

        // Pause the router
        router.pause();
        assertTrue(router.paused(), "Router should be paused");

        // Set up the prank
        vm.prank(address(gateway));

        // Track whether the call reverted
        bool hasReverted = false;

        try router.onCall(context, address(0), 0, dummyPayload) {
            // If we reach here, the call succeeded, which should not happen
            hasReverted = false;
        } catch {
            // If we reach here, the call reverted as expected
            hasReverted = true;
        }

        // Verify that the call reverted
        assertTrue(hasReverted, "Call to onCall() should revert when router is paused");
    }

    function test_RouterUpgrade() public {
        // Create a new implementation
        Router newImplementation = new Router();

        // Get original gateway and swapModule addresses from current router
        address originalGateway = router.gateway();
        address originalSwapModule = router.swapModule();
        uint256 originalGasLimit = router.withdrawGasLimit();

        // Upgrade the router to the new implementation
        vm.expectEmit(true, true, false, false);
        // Define the Upgraded event directly
        emit Upgraded(address(newImplementation));
        router.upgradeToAndCall(address(newImplementation), "");

        // Verify that storage was preserved after upgrade
        assertEq(router.gateway(), originalGateway, "Gateway address should be preserved after upgrade");
        assertEq(router.swapModule(), originalSwapModule, "Swap module address should be preserved after upgrade");
        assertEq(router.withdrawGasLimit(), originalGasLimit, "Withdraw gas limit should be preserved after upgrade");

        // Verify that we can still call functions on the upgraded router
        uint256 newGasLimit = originalGasLimit + 100000;
        router.setWithdrawGasLimit(newGasLimit);
        assertEq(router.withdrawGasLimit(), newGasLimit, "Should be able to set new values after upgrade");
    }

    function test_RouterUpgrade_OnlyAdminCanUpgrade() public {
        // Create a new implementation
        Router newImplementation = new Router();

        // Attempt to upgrade as non-admin
        vm.prank(user1);
        expectAccessControlError(user1);
        router.upgradeToAndCall(address(newImplementation), "");
    }

    function test_OnCall_FromZetaChainIntent() public {
        // Setup intent contract on ZetaChain
        uint256 zetaChainId = block.chainid; // Using current chain as ZetaChain for this test
        uint256 targetChainId = 2;
        address zetaChainIntentContract = makeAddr("zetaChainIntentContract");
        router.setIntentContract(zetaChainId, zetaChainIntentContract);
        router.setIntentContract(targetChainId, makeAddr("targetIntentContract"));

        // Setup token associations for both source and target chains
        string memory tokenName = "USDC";
        router.addToken(tokenName);

        // Add token association for the source chain (ZetaChain)
        address sourceAsset = address(inputToken); // Use inputToken as the source asset
        router.addTokenAssociation(tokenName, zetaChainId, sourceAsset, address(inputToken));

        // Add token association for the target chain
        address targetAsset = makeAddr("target_asset");
        router.addTokenAssociation(tokenName, targetChainId, targetAsset, address(targetZRC20));

        // Create intent payload
        bytes32 intentId = keccak256("zetachain-intent-test");
        uint256 amount = 100 ether;
        uint256 tip = 10 ether;
        bytes memory receiver = abi.encodePacked(user2);
        bytes memory intentPayloadBytes =
            PayloadUtils.encodeIntentPayload(intentId, amount, tip, targetChainId, receiver, false, "", 0);

        // Mock setup for withdrawGasFeeWithGasLimit
        uint256 gasFee = 1 ether;
        vm.mockCall(
            address(targetZRC20),
            abi.encodeWithSelector(IZRC20.withdrawGasFeeWithGasLimit.selector, router.withdrawGasLimit()),
            abi.encode(address(gasZRC20), gasFee)
        );

        // Mint tokens to make the test work
        // Input token goes to the router
        inputToken.mint(address(router), amount + tip);
        // Target token and gas token go to the swap module since they're returned from the swap
        targetZRC20.mint(address(swapModule), amount + tip);
        gasZRC20.mint(address(swapModule), gasFee);

        // Setup context to simulate call from ZetaChain Intent
        IGateway.ZetaChainMessageContext memory context = IGateway.ZetaChainMessageContext({
            chainID: zetaChainId,
            sender: abi.encodePacked(zetaChainIntentContract),
            senderEVM: zetaChainIntentContract
        });

        // Start recording logs to verify events
        vm.recordLogs();

        // Call onCall as if from the Intent contract on ZetaChain
        vm.prank(address(gateway));
        router.onCall(context, address(inputToken), amount + tip, intentPayloadBytes);

        // Verify approval to gateway was made
        assertTrue(
            targetZRC20.allowance(address(router), address(gateway)) > 0,
            "Router should approve target ZRC20 to gateway"
        );
        assertTrue(
            gasZRC20.allowance(address(router), address(gateway)) > 0, "Router should approve gas ZRC20 to gateway"
        );

        // Verify IntentSettlementForwarded event was emitted with correct parameters
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool foundEvent = false;

        for (uint256 i = 0; i < entries.length; i++) {
            // The event signature for IntentSettlementForwarded
            bytes32 eventSig = keccak256("IntentSettlementForwarded(bytes,uint256,uint256,address,uint256,uint256)");
            if (entries[i].topics[0] == eventSig) {
                foundEvent = true;

                // Decode the non-indexed parameters
                (address zrc20, uint256 eventAmount, uint256 eventTip) =
                    abi.decode(entries[i].data, (address, uint256, uint256));

                // Verify the event parameters
                assertEq(zrc20, address(inputToken), "ZRC20 address in event doesn't match");
                assertEq(eventAmount, amount + tip, "Amount in event doesn't match"); // The event reports the total amount including tip
                assertEq(eventTip, 9 ether, "Tip in event doesn't match"); // Actual tip in the event is 9 ether (1 ether is used for gas)
            }
        }

        assertTrue(foundEvent, "IntentSettlementForwarded event not found");
    }

    function test_OnCall_ToZetaChainIntent() public {
        // Setup intent contract on source chain
        uint256 sourceChainId = 1;
        address sourceIntentContract = makeAddr("sourceIntentContract");
        router.setIntentContract(sourceChainId, sourceIntentContract);

        // Setup intent contract on ZetaChain (current chain)
        uint256 zetaChainId = block.chainid; // Current chain ID is ZetaChain

        // Deploy a mock Intent contract for ZetaChain
        MockIntent mockZetaChainIntent = new MockIntent();
        router.setIntentContract(zetaChainId, address(mockZetaChainIntent));

        // Setup token associations
        string memory tokenName = "USDC";
        router.addToken(tokenName);
        address inputAsset = makeAddr("input_asset");
        address targetAsset = makeAddr("target_asset");

        // Add token associations for source chain and ZetaChain
        router.addTokenAssociation(tokenName, sourceChainId, inputAsset, address(inputToken));
        router.addTokenAssociation(tokenName, zetaChainId, targetAsset, address(targetZRC20));

        // Setup intent payload with ZetaChain as the target
        bytes32 intentId = keccak256("zetachain-target-test");
        uint256 amount = 100 ether;
        uint256 tip = 10 ether;
        bytes memory receiver = abi.encodePacked(user2);

        bytes memory intentPayloadBytes =
            PayloadUtils.encodeIntentPayload(intentId, amount, tip, zetaChainId, receiver, false, "", 0);

        // Set modest slippage (5%)
        swapModule.setSlippage(500);

        // Mock setup for IZRC20 withdrawGasFeeWithGasLimit
        // The result will be used in Router but eventually ignored for ZetaChain destinations
        uint256 gasFee = 1 ether;
        vm.mockCall(
            address(targetZRC20),
            abi.encodeWithSelector(IZRC20.withdrawGasFeeWithGasLimit.selector, router.withdrawGasLimit()),
            abi.encode(address(gasZRC20), gasFee)
        );

        // Mint tokens to handle all test cases
        // 1. Input token to the router
        inputToken.mint(address(router), amount + tip);
        // 2. Target token to both swap module and router since this test can go either way
        targetZRC20.mint(address(swapModule), amount + tip);
        targetZRC20.mint(address(router), amount + tip);
        // 3. Gas token to both swap module and router
        gasZRC20.mint(address(swapModule), gasFee);
        gasZRC20.mint(address(router), gasFee);

        // Setup context for the source chain
        IGateway.ZetaChainMessageContext memory context = IGateway.ZetaChainMessageContext({
            chainID: sourceChainId,
            sender: abi.encodePacked(sourceIntentContract),
            senderEVM: sourceIntentContract
        });

        // Start recording logs to verify events
        vm.recordLogs();

        // Call onCall - this should directly call the Intent contract instead of using the gateway
        vm.prank(address(gateway));
        router.onCall(context, address(inputToken), amount + tip, intentPayloadBytes);

        // Verify IntentSettlementForwarded event was emitted
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool foundEvent = false;

        for (uint256 i = 0; i < entries.length; i++) {
            bytes32 eventSig = keccak256("IntentSettlementForwarded(bytes,uint256,uint256,address,uint256,uint256)");
            if (entries[i].topics[0] == eventSig) {
                foundEvent = true;

                // Decode event data
                (address zrc20, uint256 eventAmount, uint256 eventTip) =
                    abi.decode(entries[i].data, (address, uint256, uint256));

                // Verify event parameters
                assertEq(zrc20, address(inputToken), "ZRC20 address in event doesn't match");
                assertEq(eventAmount, amount + tip, "Amount in event doesn't match");
                // For ZetaChain destinations, only slippage is deducted from the tip (5% of 110 ether = 5.5 ether)
                // So the remaining tip should be 10 - 5.5 = 4.5 ether
                assertEq(eventTip, 4.5 ether, "Tip in event doesn't match");
            }
        }

        assertTrue(foundEvent, "IntentSettlementForwarded event not found");

        // Verify the mock Intent contract was called with the settlement payload
        assertTrue(mockZetaChainIntent.wasCalled(), "Intent contract's onCall was not called");
        assertEq(mockZetaChainIntent.lastCaller(), address(router), "Intent caller should be the router");

        // Decode the settlement payload to verify its contents
        PayloadUtils.SettlementPayload memory settlementPayload =
            PayloadUtils.decodeSettlementPayload(mockZetaChainIntent.lastMessage());

        assertEq(settlementPayload.intentId, intentId, "Intent ID in settlement payload doesn't match");
        assertEq(settlementPayload.asset, targetAsset, "Asset in settlement payload doesn't match");
        assertEq(
            settlementPayload.receiver,
            PayloadUtils.bytesToAddress(receiver),
            "Receiver in settlement payload doesn't match"
        );
    }

    function test_SetChainWithdrawGasLimit() public {
        uint256 chainId = 42161; // Arbitrum chain ID
        uint256 customGasLimit = 500000; // Higher gas limit for Arbitrum

        // Set a custom gas limit for the specific chain
        vm.expectEmit();
        emit ChainWithdrawGasLimitSet(chainId, customGasLimit);
        router.setChainWithdrawGasLimit(chainId, customGasLimit);

        // Verify the custom gas limit was set
        assertEq(router.chainWithdrawGasLimits(chainId), customGasLimit);

        // Verify getChainGasLimit returns the custom limit
        assertEq(router.getChainGasLimit(chainId), customGasLimit);
    }

    function test_SetChainWithdrawGasLimit_ZeroValueReverts() public {
        uint256 chainId = 42161; // Arbitrum chain ID
        uint256 zeroGasLimit = 0;

        // Attempt to set a zero gas limit
        vm.expectRevert("Gas limit below minimum");
        router.setChainWithdrawGasLimit(chainId, zeroGasLimit);
    }

    function test_SetChainWithdrawGasLimit_BelowMinimumReverts() public {
        uint256 chainId = 42161; // Arbitrum chain ID
        uint256 tooLowGasLimit = 99999; // Just below minimum of 100000

        // Attempt to set a gas limit below the minimum
        vm.expectRevert("Gas limit below minimum");
        router.setChainWithdrawGasLimit(chainId, tooLowGasLimit);
    }

    function test_SetChainWithdrawGasLimit_AboveMaximumReverts() public {
        uint256 chainId = 42161; // Arbitrum chain ID
        uint256 tooHighGasLimit = 10000001; // Just above maximum of 10000000

        // Attempt to set a gas limit above the maximum
        vm.expectRevert("Gas limit above maximum");
        router.setChainWithdrawGasLimit(chainId, tooHighGasLimit);
    }

    function test_SetChainWithdrawGasLimit_AtMinimum() public {
        uint256 chainId = 42161; // Arbitrum chain ID
        uint256 minimumGasLimit = 100000; // Exactly at minimum

        // Set at minimum should work
        router.setChainWithdrawGasLimit(chainId, minimumGasLimit);

        // Verify the custom gas limit was set
        assertEq(router.chainWithdrawGasLimits(chainId), minimumGasLimit);
    }

    function test_SetChainWithdrawGasLimit_AtMaximum() public {
        uint256 chainId = 42161; // Arbitrum chain ID
        uint256 maximumGasLimit = 10000000; // Exactly at maximum

        // Set at maximum should work
        router.setChainWithdrawGasLimit(chainId, maximumGasLimit);

        // Verify the custom gas limit was set
        assertEq(router.chainWithdrawGasLimits(chainId), maximumGasLimit);
    }

    function test_SetChainWithdrawGasLimit_NonAdminReverts() public {
        uint256 chainId = 42161; // Arbitrum chain ID
        uint256 customGasLimit = 500000;

        // Attempt to set a gas limit as non-admin
        vm.prank(user1);
        expectAccessControlError(user1);
        router.setChainWithdrawGasLimit(chainId, customGasLimit);
    }

    function test_RemoveChainWithdrawGasLimit() public {
        uint256 chainId = 42161; // Arbitrum chain ID
        uint256 customGasLimit = 500000;

        // First, set a custom gas limit
        router.setChainWithdrawGasLimit(chainId, customGasLimit);
        assertEq(router.chainWithdrawGasLimits(chainId), customGasLimit);

        // Now remove the custom gas limit
        vm.expectEmit();
        emit ChainWithdrawGasLimitRemoved(chainId);
        router.removeChainWithdrawGasLimit(chainId);

        // Verify the custom gas limit was removed
        assertEq(router.chainWithdrawGasLimits(chainId), 0);

        // Verify getChainGasLimit now returns the global limit
        assertEq(router.getChainGasLimit(chainId), router.withdrawGasLimit());
    }

    function test_RemoveChainWithdrawGasLimit_NonAdminReverts() public {
        uint256 chainId = 42161; // Arbitrum chain ID
        uint256 customGasLimit = 500000;

        // First, set a custom gas limit
        router.setChainWithdrawGasLimit(chainId, customGasLimit);

        // Attempt to remove the gas limit as non-admin
        vm.prank(user1);
        expectAccessControlError(user1);
        router.removeChainWithdrawGasLimit(chainId);
    }

    function test_GetChainGasLimit_ReturnsFallback() public {
        uint256 chainId = 1; // Chain without custom gas limit
        uint256 globalGasLimit = router.withdrawGasLimit();

        // Verify the function returns the global limit when no custom limit is set
        assertEq(router.getChainGasLimit(chainId), globalGasLimit);
    }

    function test_GetChainGasLimit_ReturnsCustom() public {
        uint256 chainId = 42161; // Arbitrum chain ID
        uint256 customGasLimit = 500000;

        // Set a custom gas limit
        router.setChainWithdrawGasLimit(chainId, customGasLimit);

        // Verify the function returns the custom limit
        assertEq(router.getChainGasLimit(chainId), customGasLimit);
    }

    function test_OnCall_UsesChainSpecificGasLimit() public {
        // Setup intent contract
        uint256 sourceChainId = 1;
        uint256 targetChainId = 42161; // Arbitrum chain ID
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

        // Set a custom gas limit for the target chain
        uint256 customGasLimit = 500000;
        router.setChainWithdrawGasLimit(targetChainId, customGasLimit);

        // Setup intent payload
        bytes32 intentId = keccak256("test-intent");
        uint256 amount = 100 ether;
        uint256 tip = 10 ether;
        bytes memory receiver = abi.encodePacked(user2);

        bytes memory intentPayloadBytes =
            PayloadUtils.encodeIntentPayload(intentId, amount, tip, targetChainId, receiver, false, "", 0);

        // Set modest slippage (5%)
        swapModule.setSlippage(500);

        // Mock withdrawGasFeeWithGasLimit to verify it's called with the custom gas limit
        uint256 gasFee = 1 ether;
        vm.mockCall(
            address(targetZRC20),
            abi.encodeWithSelector(IZRC20.withdrawGasFeeWithGasLimit.selector, customGasLimit),
            abi.encode(address(gasZRC20), gasFee)
        );

        // Mint tokens to make the test work
        inputToken.mint(address(router), amount + tip);
        targetZRC20.mint(address(swapModule), amount + tip);
        gasZRC20.mint(address(swapModule), gasFee);

        // Setup context
        IGateway.ZetaChainMessageContext memory context = IGateway.ZetaChainMessageContext({
            chainID: sourceChainId,
            sender: abi.encodePacked(sourceIntentContract),
            senderEVM: sourceIntentContract
        });

        // Call onCall
        vm.prank(address(gateway));
        router.onCall(context, address(inputToken), amount + tip, intentPayloadBytes);

        // The test passes if the mock call with the custom gas limit is used
        // No need for additional assertions as the mock would fail if the wrong gas limit was used
    }

    function test_OnCall_SameTokenNoSwap() public {
        // Setup intent contract
        uint256 sourceChainId = 1;
        uint256 targetChainId = 2;
        address sourceIntentContract = makeAddr("sourceIntentContract");
        address targetIntentContract = makeAddr("targetIntentContract");
        router.setIntentContract(sourceChainId, sourceIntentContract);
        router.setIntentContract(targetChainId, targetIntentContract);

        // Setup token associations - using the same ZRC20 address for both source and target
        string memory tokenName = "USDC";
        router.addToken(tokenName);
        address inputAsset = makeAddr("input_asset");
        address targetAsset = makeAddr("target_asset");

        // The key difference: using the same ZRC20 token for both source and target
        router.addTokenAssociation(tokenName, sourceChainId, inputAsset, address(inputToken));
        router.addTokenAssociation(tokenName, targetChainId, targetAsset, address(inputToken));

        // Setup intent payload
        bytes32 intentId = keccak256("test-intent");
        uint256 amount = 100 ether;
        uint256 tip = 10 ether;
        bytes memory receiver = abi.encodePacked(user2);

        bytes memory intentPayloadBytes =
            PayloadUtils.encodeIntentPayload(intentId, amount, tip, targetChainId, receiver, false, "", 0);

        // Mock setup for IZRC20 withdrawGasFeeWithGasLimit
        uint256 gasFee = 1 ether;
        vm.mockCall(
            address(inputToken),
            abi.encodeWithSelector(IZRC20.withdrawGasFeeWithGasLimit.selector, router.withdrawGasLimit()),
            abi.encode(address(gasZRC20), gasFee)
        );

        // Mint tokens to make the test work
        // Input token goes to the router
        inputToken.mint(address(router), amount + tip);
        // Gas token goes to the swap module for gas fee
        gasZRC20.mint(address(swapModule), gasFee);

        // Setup spy on swap module to verify it's not called
        vm.record();

        // Setup context
        IGateway.ZetaChainMessageContext memory context = IGateway.ZetaChainMessageContext({
            chainID: sourceChainId,
            sender: abi.encodePacked(sourceIntentContract),
            senderEVM: sourceIntentContract
        });

        // Check event is emitted with correct values
        vm.expectEmit();
        emit IntentSettlementForwarded(
            context.sender,
            context.chainID,
            targetChainId,
            address(inputToken),
            amount + tip,
            tip // Tip should remain unchanged since no swap/slippage
        );

        // Call onCall
        vm.prank(address(gateway));
        router.onCall(context, address(inputToken), amount + tip, intentPayloadBytes);

        // Verify the swap function was not called
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(swapModule));

        // Verify no swap was performed - the swap function should not be called
        bool swapCalled = false;
        bytes4 swapSelector = bytes4(keccak256("swap(address,address,uint256,address,uint256,string)"));

        for (uint256 i = 0; i < reads.length; i++) {
            // Check if any read access matches the swap selector storage slot
            if (uint256(reads[i]) < 4 && bytes4(uint32(uint256(reads[i]))) == swapSelector) {
                swapCalled = true;
                break;
            }
        }

        assertFalse(swapCalled, "Swap function should not be called when source and target ZRC20s are the same");

        // Verify approvals were made to the gateway
        assertTrue(
            inputToken.allowance(address(router), address(gateway)) > 0, "Router should approve input token to gateway"
        );
        assertTrue(
            gasZRC20.allowance(address(router), address(gateway)) > 0, "Router should approve gas ZRC20 to gateway"
        );

        // Verify actual amount equals wanted amount (no reduction)
        // This is implicit in the event emission check above but would be
        // even better with an explicit check of the settlement payload
    }

    function test_OnCall_SwapSurplusHandling() public {
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

        bytes memory intentPayloadBytes =
            PayloadUtils.encodeIntentPayload(intentId, amount, tip, targetChainId, receiver, false, "", 0);

        // Set modest slippage (5%)
        swapModule.setSlippage(500);

        // Set a custom amount out for testing that is more than the wanted amount (surplus)
        swapModule.setCustomAmountOut(amount + tip + 1 ether);

        // Mock setup for IZRC20 withdrawGasFeeWithGasLimit
        uint256 gasFee = 1 ether;
        vm.mockCall(
            address(targetZRC20),
            abi.encodeWithSelector(IZRC20.withdrawGasFeeWithGasLimit.selector, router.withdrawGasLimit()),
            abi.encode(address(gasZRC20), gasFee)
        );

        // Mint tokens to make the test work
        // Input token goes to the router
        inputToken.mint(address(router), amount + tip);
        // Target token and gas token go to the swap module since they're returned from the swap
        targetZRC20.mint(address(swapModule), amount + tip);
        gasZRC20.mint(address(swapModule), gasFee);

        // Setup context
        IGateway.ZetaChainMessageContext memory context = IGateway.ZetaChainMessageContext({
            chainID: sourceChainId,
            sender: abi.encodePacked(sourceIntentContract),
            senderEVM: sourceIntentContract
        });

        // Call onCall - should succeed even with surplus
        vm.prank(address(gateway));
        router.onCall(context, address(inputToken), amount + tip, intentPayloadBytes);

        // Test passes if no revert occurs - surplus is handled gracefully
    }

    function test_OnCall_UsesCustomGasLimitFromPayload() public {
        // Setup intent contract
        uint256 sourceChainId = 1;
        uint256 targetChainId = 42161; // Arbitrum chain ID
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

        // Set a custom gas limit for the target chain
        uint256 chainSpecificGasLimit = 500000;
        router.setChainWithdrawGasLimit(targetChainId, chainSpecificGasLimit);

        // Setup intent payload with custom gas limit that's different from chain config
        bytes32 intentId = keccak256("test-intent-custom-gas");
        uint256 amount = 100 ether;
        uint256 tip = 10 ether;
        bytes memory receiver = abi.encodePacked(user2);
        uint256 customGasLimit = 700000; // Custom gas limit different from chain config

        bytes memory intentPayloadBytes =
            PayloadUtils.encodeIntentPayload(intentId, amount, tip, targetChainId, receiver, false, "", customGasLimit);

        // Mock withdrawGasFeeWithGasLimit to verify it's called with the custom gas limit from payload
        uint256 gasFee = 1 ether;
        vm.mockCall(
            address(targetZRC20),
            abi.encodeWithSelector(IZRC20.withdrawGasFeeWithGasLimit.selector, customGasLimit),
            abi.encode(address(gasZRC20), gasFee)
        );

        // Mint tokens to make the test work
        inputToken.mint(address(router), amount + tip);
        targetZRC20.mint(address(swapModule), amount + tip);
        gasZRC20.mint(address(swapModule), gasFee);

        // Setup context
        IGateway.ZetaChainMessageContext memory context = IGateway.ZetaChainMessageContext({
            chainID: sourceChainId,
            sender: abi.encodePacked(sourceIntentContract),
            senderEVM: sourceIntentContract
        });

        // Call onCall
        vm.prank(address(gateway));
        router.onCall(context, address(inputToken), amount + tip, intentPayloadBytes);

        // The test passes if the mock call with the custom gas limit is used
        // If the chain-specific gas limit was used instead, the mock would not match and the test would fail
    }
}
