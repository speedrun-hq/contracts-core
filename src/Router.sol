// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IUniswapV3Router.sol";
import "./interfaces/IGateway.sol";
import "./interfaces/IZRC20.sol";
import "./interfaces/ISwap.sol";
import "./interfaces/IRouter.sol";
import "./interfaces/IIntent.sol";
import "./utils/PayloadUtils.sol";

/**
 * @title Router
 * @dev Routes CCTX and handles ZRC20 swaps on ZetaChain
 */
contract Router is IRouter, Initializable, UUPSUpgradeable, AccessControlUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;

    // Role definitions
    // Removed ADMIN_ROLE and using only DEFAULT_ADMIN_ROLE
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // Default gas limit for withdraw operations
    uint256 private constant DEFAULT_WITHDRAW_GAS_LIMIT = 300000;

    // Current gas limit for withdraw operations (can be modified by admin)
    uint256 public withdrawGasLimit;

    // Gateway contract address
    address public gateway;
    // Swap module address
    address public swapModule;

    // Mapping from chain ID to intent contract address
    mapping(uint256 => address) public intentContracts;

    // Mapping from token name to whether it exists
    mapping(string => bool) private _supportedTokens;
    // Mapping from ZRC20 address to token name
    mapping(address => string) public zrc20ToTokenName;
    // Mapping from token name and chain ID to asset address
    mapping(string => mapping(uint256 => address)) private _tokenAssets;
    // Mapping from token name and chain ID to ZRC20 address
    mapping(string => mapping(uint256 => address)) private _tokenZrc20s;
    // List of supported token names
    string[] public tokenNames;
    // List of chain IDs for each token
    mapping(string => uint256[]) private _tokenChainIds;

    // Per-chain gas limits for withdraw operations (optional, overrides global withdrawGasLimit)
    mapping(uint256 => uint256) public chainWithdrawGasLimits;

    // Event emitted when an intent contract is set
    event IntentContractSet(uint256 indexed chainId, address indexed intentContract);
    // Event emitted when a new token is added
    event TokenAdded(string indexed name);
    // Event emitted when a token association is added
    event TokenAssociationAdded(string indexed name, uint256 indexed chainId, address asset, address zrc20);
    // Event emitted when a token association is updated
    event TokenAssociationUpdated(string indexed name, uint256 indexed chainId, address asset, address zrc20);
    // Event emitted when a token association is removed
    event TokenAssociationRemoved(string indexed name, uint256 indexed chainId);
    // Event emitted when an intent settlement is forwarded
    event IntentSettlementForwarded(
        bytes indexed sender,
        uint256 indexed sourceChain,
        uint256 indexed targetChain,
        address zrc20,
        uint256 amount,
        uint256 tip
    );
    // Event emitted when the gateway is updated
    event GatewayUpdated(address indexed oldGateway, address indexed newGateway);
    // Event emitted when the swap module is updated
    event SwapModuleUpdated(address indexed oldSwapModule, address indexed newSwapModule);
    // Event emitted when the global withdraw gas limit is updated
    event WithdrawGasLimitUpdated(uint256 oldGasLimit, uint256 newGasLimit);
    // Event emitted when a chain-specific withdraw gas limit is set
    event ChainWithdrawGasLimitSet(uint256 indexed chainId, uint256 gasLimit);
    // Event emitted when a chain-specific withdraw gas limit is removed
    event ChainWithdrawGasLimitRemoved(uint256 indexed chainId);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract
     * @param _gateway The address of the gateway contract
     * @param _swapModule The address of the swap module contract
     */
    function initialize(address _gateway, address _swapModule) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __Pausable_init();

        require(_gateway != address(0), "Invalid gateway address");
        require(_swapModule != address(0), "Invalid swap module address");

        // Set up admin role
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);

        gateway = _gateway;
        swapModule = _swapModule;
        withdrawGasLimit = DEFAULT_WITHDRAW_GAS_LIMIT;
    }

    /**
     * @dev Function that authorizes an upgrade, can only be called by an account with the admin role
     * @param newImplementation Address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    /**
     * @dev Pauses the contract, preventing onCall operations
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @dev Unpauses the contract, allowing onCall operations
     * Only DEFAULT_ADMIN_ROLE can unpause
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @dev Updates the gateway address
     * @param _gateway New gateway address
     */
    function updateGateway(address _gateway) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_gateway != address(0), "Gateway cannot be zero address");
        address oldGateway = gateway;
        gateway = _gateway;
        emit GatewayUpdated(oldGateway, _gateway);
    }

    /**
     * @dev Updates the swap module address
     * @param _swapModule New swap module address
     */
    function updateSwapModule(address _swapModule) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_swapModule != address(0), "Swap module cannot be zero address");
        address oldSwapModule = swapModule;
        swapModule = _swapModule;
        emit SwapModuleUpdated(oldSwapModule, _swapModule);
    }

    /**
     * @dev Calculates the expected amount when converting between tokens with different decimal places
     * @param amountIn The input amount with the source token's decimal precision
     * @param decimalsIn The decimal places of the source token
     * @param decimalsOut The decimal places of the destination token
     * @return The expected amount with the destination token's decimal precision
     */
    function calculateExpectedAmount(uint256 amountIn, uint8 decimalsIn, uint8 decimalsOut)
        public
        pure
        returns (uint256)
    {
        // If decimals are the same, no conversion needed
        if (decimalsIn == decimalsOut) {
            return amountIn;
        }

        // If destination has more decimals, multiply
        if (decimalsOut > decimalsIn) {
            uint256 scalingFactor = 10 ** (decimalsOut - decimalsIn);
            return amountIn * scalingFactor;
        }

        // If destination has fewer decimals, divide
        uint256 divisor = 10 ** (decimalsIn - decimalsOut);

        // Round down by default (matches typical token behavior)
        return amountIn / divisor;
    }

    modifier onlyGatewayOrIntent() {
        // Allow calls from gateway or registered intent contracts
        require(
            msg.sender == gateway || intentContracts[block.chainid] == msg.sender,
            "Only gateway or intent contract can call this function"
        );
        _;
    }

    /**
     * @dev Handles incoming messages from the gateway or direct calls from Intent on ZetaChain
     * @param context The message context containing sender and chain information
     * @param zrc20 The ZRC20 token address
     * @param amountWithTip The amount of tokens with tip
     * @param payload The encoded message containing intent payload
     */
    function onCall(
        IGateway.ZetaChainMessageContext calldata context,
        address zrc20,
        uint256 amountWithTip,
        bytes calldata payload
    ) external override onlyGatewayOrIntent whenNotPaused {
        // Verify the call is coming from a registered intent contract
        require(intentContracts[context.chainID] == context.senderEVM, "Call must be from intent contract");

        // Decode intent payload
        PayloadUtils.IntentPayload memory intentPayload = PayloadUtils.decodeIntentPayload(payload);

        // Get token association for target chain
        (address targetAsset, address targetZRC20,) = getTokenAssociation(zrc20, intentPayload.targetChain);

        // Get intent contract on target chain
        address intentContract = intentContracts[intentPayload.targetChain];
        require(intentContract != address(0), "Intent contract not set for target chain");

        // Get decimals for source and target tokens
        uint8 sourceDecimals = IZRC20(zrc20).decimals();
        uint8 targetDecimals = IZRC20(targetZRC20).decimals();

        // Convert amounts to target token decimal representation
        (uint256 wantedAmount, uint256 wantedTip, uint256 wantedAmountWithTip) =
            _convertAmountsForDecimals(intentPayload.amount, amountWithTip, sourceDecimals, targetDecimals);

        // Get the appropriate gas limit for the target chain
        uint256 gasLimit = _getChainGasLimit(intentPayload.targetChain);

        // Get gas fee info from target ZRC20
        (address gasZRC20, uint256 gasFee) = IZRC20(targetZRC20).withdrawGasFeeWithGasLimit(gasLimit);

        // Approve swap module to spend tokens
        IERC20(zrc20).approve(swapModule, amountWithTip);

        // Perform swap through swap module
        uint256 amountWithTipOut =
            ISwap(swapModule).swap(zrc20, targetZRC20, amountWithTip, gasZRC20, gasFee, zrc20ToTokenName[zrc20]);

        // Calculate slippage difference and adjust tip accordingly
        uint256 slippageAndFeeCost = wantedAmountWithTip - amountWithTipOut;

        // Initialize tip and actual amount
        uint256 tipAfterSwap;
        uint256 actualAmount = wantedAmount;

        // Check if tip covers the slippage and fee costs
        if (wantedTip > slippageAndFeeCost) {
            // Tip covers all costs, subtract from tip only
            tipAfterSwap = wantedTip - slippageAndFeeCost;
        } else {
            // Tip doesn't cover costs, use it all and reduce the amount
            tipAfterSwap = 0;
            // Calculate how much remaining slippage to cover from the amount
            uint256 remainingCost = slippageAndFeeCost - wantedTip;
            // Ensure the amount is greater than the remaining cost, otherwise fail
            require(wantedAmount > remainingCost, "Amount insufficient to cover costs after tip");
            // Reduce the actual amount by the remaining cost
            actualAmount = wantedAmount - remainingCost;
        }

        // Convert receiver from bytes to address
        address receiverAddress = PayloadUtils.bytesToAddress(intentPayload.receiver);

        // Encode settlement payload
        bytes memory settlementPayload = PayloadUtils.encodeSettlementPayload(
            intentPayload.intentId,
            wantedAmount, // amount for index computation
            targetAsset,
            receiverAddress,
            tipAfterSwap,
            actualAmount // actual amount to transfer after all costs
        );

        // Check if target chain is the current chain (ZetaChain)
        if (intentPayload.targetChain == block.chainid) {
            // Process settlement directly on ZetaChain
            _processChainsSettlementOnZetaChain(intentContract, targetZRC20, amountWithTipOut, settlementPayload);
        } else {
            // Process settlement for connected chains
            _processChainsSettlementOnConnectedChain(
                intentContract,
                targetZRC20,
                gasZRC20,
                amountWithTipOut,
                gasFee,
                settlementPayload,
                receiverAddress,
                gasLimit
            );
        }

        emit IntentSettlementForwarded(
            context.sender, context.chainID, intentPayload.targetChain, zrc20, amountWithTip, tipAfterSwap
        );
    }

    /**
     * @dev Internal function to process settlement directly on ZetaChain
     * @param intentContract The target Intent contract address
     * @param zrc20 The ZRC20 token address
     * @param amount The amount to transfer
     * @param settlementPayload The encoded settlement payload
     */
    function _processChainsSettlementOnZetaChain(
        address intentContract,
        address zrc20,
        uint256 amount,
        bytes memory settlementPayload
    ) internal {
        // Transfer tokens to the target Intent contract
        IERC20(zrc20).approve(intentContract, amount);

        // Create a MessageContext
        IIntent.MessageContext memory intentContext = IIntent.MessageContext({sender: address(this)});

        // Call the intent contract directly
        IIntent(intentContract).onCall(intentContext, settlementPayload);
    }

    /**
     * @dev Internal function to process settlement for connected chains
     * @param intentContract The target Intent contract address
     * @param targetZRC20 The target ZRC20 token address
     * @param gasZRC20 The gas ZRC20 token address
     * @param amount The amount to transfer
     * @param gasFee The gas fee to pay
     * @param settlementPayload The encoded settlement payload
     * @param receiverAddress The receiver address in case of revert
     * @param gasLimit The gas limit to use for the transaction
     */
    function _processChainsSettlementOnConnectedChain(
        address intentContract,
        address targetZRC20,
        address gasZRC20,
        uint256 amount,
        uint256 gasFee,
        bytes memory settlementPayload,
        address receiverAddress,
        uint256 gasLimit
    ) internal {
        // Prepare call options with provided gas limit
        IGateway.CallOptions memory callOptions = IGateway.CallOptions({gasLimit: gasLimit, isArbitraryCall: false});

        // Prepare revert options
        IGateway.RevertOptions memory revertOptions = IGateway.RevertOptions({
            revertAddress: receiverAddress, // should never happen: in case of failure, funds are reverted to receiver on ZetaChain
            callOnRevert: false,
            abortAddress: address(0),
            revertMessage: "",
            onRevertGasLimit: 0
        });

        // Approve gateway to spend tokens
        IERC20(targetZRC20).approve(gateway, amount);
        IERC20(gasZRC20).approve(gateway, gasFee);

        // Call gateway to withdraw and call intent contract
        IGateway(gateway).withdrawAndCall(
            abi.encodePacked(intentContract), amount, targetZRC20, settlementPayload, callOptions, revertOptions
        );
    }

    /**
     * @dev Helper function to convert amounts between different token decimal representations
     * @param amount The original amount
     * @param amountWithTip The original amount with tip
     * @param sourceDecimals The source token's decimal places
     * @param targetDecimals The target token's decimal places
     * @return wantedAmount The adjusted amount in target decimal representation
     * @return wantedTip The adjusted tip in target decimal representation
     * @return wantedAmountWithTip The adjusted total amount in target decimal representation
     */
    function _convertAmountsForDecimals(
        uint256 amount,
        uint256 amountWithTip,
        uint8 sourceDecimals,
        uint8 targetDecimals
    ) private pure returns (uint256 wantedAmount, uint256 wantedTip, uint256 wantedAmountWithTip) {
        // Convert the individual amount and the total amount with tip
        wantedAmount = calculateExpectedAmount(amount, sourceDecimals, targetDecimals);
        wantedAmountWithTip = calculateExpectedAmount(amountWithTip, sourceDecimals, targetDecimals);

        // Calculate tip as the difference to maintain the invariant:
        // wantedAmount + wantedTip == wantedAmountWithTip
        if (wantedAmountWithTip > wantedAmount) {
            wantedTip = wantedAmountWithTip - wantedAmount;
        } else {
            // Edge case handling if there's some rounding issue
            wantedTip = 0;
            // Ensure the invariant holds even in edge cases
            wantedAmountWithTip = wantedAmount;
        }

        return (wantedAmount, wantedTip, wantedAmountWithTip);
    }

    /**
     * @dev Sets the intent contract address for a specific chain
     * @param chainId The chain ID to set the intent contract for
     * @param intentContract The address of the intent contract
     */
    function setIntentContract(uint256 chainId, address intentContract) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(intentContract != address(0), "Invalid intent contract address");
        intentContracts[chainId] = intentContract;
        emit IntentContractSet(chainId, intentContract);
    }

    /**
     * @dev Gets the intent contract address for a specific chain
     * @param chainId The chain ID to get the intent contract for
     * @return The address of the intent contract
     */
    function getIntentContract(uint256 chainId) public view returns (address) {
        return intentContracts[chainId];
    }

    /**
     * @dev Adds a new supported token
     * @param name The name of the token (e.g., "USDC")
     */
    function addToken(string calldata name) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(bytes(name).length > 0, "Token name cannot be empty");
        require(!_supportedTokens[name], "Token already exists");

        _supportedTokens[name] = true;
        tokenNames.push(name);
        emit TokenAdded(name);
    }

    /**
     * @dev Adds a new token association
     * @param name The name of the token
     * @param chainId The chain ID where the asset exists
     * @param asset The ERC20 address on the source chain
     * @param zrc20 The ZRC20 address on ZetaChain
     */
    function addTokenAssociation(string calldata name, uint256 chainId, address asset, address zrc20)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(_supportedTokens[name], "Token does not exist");
        require(asset != address(0), "Invalid asset address");
        require(zrc20 != address(0), "Invalid ZRC20 address");
        require(_tokenAssets[name][chainId] == address(0), "Association already exists");

        _tokenAssets[name][chainId] = asset;
        _tokenZrc20s[name][chainId] = zrc20;
        _tokenChainIds[name].push(chainId);
        zrc20ToTokenName[zrc20] = name;

        emit TokenAssociationAdded(name, chainId, asset, zrc20);
    }

    /**
     * @dev Updates an existing token association
     * @param name The name of the token
     * @param chainId The chain ID where the asset exists
     * @param asset The new ERC20 address on the source chain
     * @param zrc20 The new ZRC20 address on ZetaChain
     */
    function updateTokenAssociation(string calldata name, uint256 chainId, address asset, address zrc20)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(_supportedTokens[name], "Token does not exist");
        require(asset != address(0), "Invalid asset address");
        require(zrc20 != address(0), "Invalid ZRC20 address");
        require(_tokenAssets[name][chainId] != address(0), "Association does not exist");

        _tokenAssets[name][chainId] = asset;
        _tokenZrc20s[name][chainId] = zrc20;
        zrc20ToTokenName[zrc20] = name;

        emit TokenAssociationUpdated(name, chainId, asset, zrc20);
    }

    /**
     * @dev Removes a token association
     * @param name The name of the token
     * @param chainId The chain ID to remove the association for
     */
    function removeTokenAssociation(string calldata name, uint256 chainId) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_supportedTokens[name], "Token does not exist");
        require(_tokenAssets[name][chainId] != address(0), "Association does not exist");

        delete _tokenAssets[name][chainId];
        delete _tokenZrc20s[name][chainId];

        // Remove chainId from the array
        uint256[] storage chainIds = _tokenChainIds[name];
        for (uint256 i = 0; i < chainIds.length; i++) {
            if (chainIds[i] == chainId) {
                chainIds[i] = chainIds[chainIds.length - 1];
                chainIds.pop();
                break;
            }
        }

        emit TokenAssociationRemoved(name, chainId);
    }

    /**
     * @dev Gets the token association for a specific chain
     * @param zrc20 The ZRC20 address on ZetaChain
     * @param chainId The chain ID to get the association for
     * @return asset The ERC20 address on the source chain
     * @return zrc20Addr The ZRC20 address on ZetaChain
     * @return chainIdValue The chain ID where the asset exists
     */
    function getTokenAssociation(address zrc20, uint256 chainId)
        public
        view
        returns (address asset, address zrc20Addr, uint256 chainIdValue)
    {
        string memory name = zrc20ToTokenName[zrc20];
        require(_supportedTokens[name], "Token does not exist");
        require(_tokenAssets[name][chainId] != address(0), "Association does not exist");

        return (_tokenAssets[name][chainId], _tokenZrc20s[name][chainId], chainId);
    }

    /**
     * @dev Gets all token associations for a specific token
     * @param name The name of the token
     * @return chainIds Array of chain IDs
     * @return assets Array of asset addresses
     * @return zrc20s Array of ZRC20 addresses
     */
    function getTokenAssociations(string calldata name)
        public
        view
        returns (uint256[] memory chainIds, address[] memory assets, address[] memory zrc20s)
    {
        require(_supportedTokens[name], "Token does not exist");

        chainIds = _tokenChainIds[name];
        uint256 length = chainIds.length;

        assets = new address[](length);
        zrc20s = new address[](length);

        for (uint256 i = 0; i < length; i++) {
            uint256 chainId = chainIds[i];
            assets[i] = _tokenAssets[name][chainId];
            zrc20s[i] = _tokenZrc20s[name][chainId];
        }
    }

    /**
     * @dev Gets all supported token names
     * @return Array of token names
     */
    function getSupportedTokens() public view returns (string[] memory) {
        return tokenNames;
    }

    /**
     * @dev Checks if a token exists
     * @param name The name of the token
     * @return Whether the token exists
     */
    function isTokenSupported(string calldata name) public view returns (bool) {
        return _supportedTokens[name];
    }

    /**
     * @dev Updates the withdraw gas limit
     * @param newGasLimit The new gas limit to set
     */
    function setWithdrawGasLimit(uint256 newGasLimit) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newGasLimit > 0, "Gas limit cannot be zero");
        uint256 oldGasLimit = withdrawGasLimit;
        withdrawGasLimit = newGasLimit;
        emit WithdrawGasLimitUpdated(oldGasLimit, newGasLimit);
    }

    /**
     * @dev Sets a custom gas limit for a specific chain
     * @param chainId The chain ID to set the gas limit for
     * @param gasLimit The gas limit to set
     */
    function setChainWithdrawGasLimit(uint256 chainId, uint256 gasLimit) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(gasLimit > 0, "Gas limit cannot be zero");
        chainWithdrawGasLimits[chainId] = gasLimit;
        emit ChainWithdrawGasLimitSet(chainId, gasLimit);
    }

    /**
     * @dev Removes a custom gas limit for a specific chain
     * @param chainId The chain ID to remove the gas limit for
     */
    function removeChainWithdrawGasLimit(uint256 chainId) public onlyRole(DEFAULT_ADMIN_ROLE) {
        delete chainWithdrawGasLimits[chainId];
        emit ChainWithdrawGasLimitRemoved(chainId);
    }

    /**
     * @dev Gets the effective gas limit for a specific chain
     * @param chainId The chain ID to get the gas limit for
     * @return The gas limit to use for the specified chain
     */
    function getChainGasLimit(uint256 chainId) public view returns (uint256) {
        return _getChainGasLimit(chainId);
    }

    /**
     * @dev Internal function to get the appropriate gas limit for a specific chain
     * @param chainId The chain ID to get the gas limit for
     * @return The gas limit to use for the specified chain
     */
    function _getChainGasLimit(uint256 chainId) internal view returns (uint256) {
        // If a chain-specific gas limit is set, use it
        uint256 chainGasLimit = chainWithdrawGasLimits[chainId];
        if (chainGasLimit > 0) {
            return chainGasLimit;
        }

        // Otherwise use the global withdraw gas limit
        return withdrawGasLimit;
    }
}
