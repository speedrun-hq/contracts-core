# Aerodrome Cross-Chain Swap Integration: Creating Intents

This document explains how to create intents for cross-chain swaps on Aerodrome DEX using the AerodromeInitiator contract.

## Creating an Aerodrome Swap Intent

You can use Foundry's `cast` command to create Aerodrome swap intents from the command line.

### Step 1: Approve Tokens to the Initiator

First, approve the AerodromeInitiator contract to spend your tokens:

```shell
cast send [TOKEN_ADDRESS] "approve(address,uint256)" \
  [AERODROME_INITIATOR_ADDRESS] \
  [AMOUNT+TIP] \
  --rpc-url [SOURCE_RPC_URL] \
  --private-key [YOUR_PRIVATE_KEY]
```

### Step 2: Create the Swap Intent

Call the `initiateAerodromeSwap` function on the AerodromeInitiator contract:

```shell
# Define the parameters for the swap
SOURCE_TOKEN=0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913  # Source chain USDC
TARGET_TOKEN=0x4200000000000000000000000000000000000006  # Base WETH
AMOUNT=1000000  # 1 USDC (6 decimals)
TIP=100000      # 0.1 USDC
SALT=123        # Any unique number
GAS_LIMIT=300000
MIN_AMOUNT_OUT=0  # Be careful with this in production!
DEADLINE=$(($(date +%s) + 3600))  # 1 hour from now
RECEIVER=0xYourAddressHere  # Your address on Base

# Execute the swap intent creation
cast send $AERODROME_INITIATOR_ADDRESS \
  "initiateAerodromeSwap(address,uint256,uint256,uint256,uint256,address[],bool[],uint256,uint256,address)" \
  $SOURCE_TOKEN \
  $AMOUNT \
  $TIP \
  $SALT \
  $GAS_LIMIT \
  "[\"$SOURCE_TOKEN\",\"$TARGET_TOKEN\"]" \
  "[false]" \
  $MIN_AMOUNT_OUT \
  $DEADLINE \
  $RECEIVER \
  --rpc-url $SOURCE_RPC_URL \
  --private-key $PRIVATE_KEY
```

## Complete Example (Ready to Run)

Here's a concrete example with all parameters directly in the command:

```shell
# This command initiates a swap of 1 USDC to WETH on Base
cast send 0x123456789AbCdEf0123456789aBcDeF01234567 \
  "initiateAerodromeSwap(address,uint256,uint256,uint256,uint256,address[],bool[],uint256,uint256,address)" \
  0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913 \
  1000000 \
  100000 \
  12345 \
  300000 \
  "[\"0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913\",\"0x4200000000000000000000000000000000000006\"]" \
  "[false]" \
  0 \
  1718438400 \
  0xaB1234C567dEf890123456789aBcDef012345678 \
  --rpc-url https://zetachain-evm.blockpi.network/v1/rpc/public \
  --private-key 0xYOUR_PRIVATE_KEY_HERE
```

Replace:
- `0x123456789AbCdEf0123456789aBcDeF01234567` with your AerodromeInitiator contract address
- `0xaB1234C567dEf890123456789aBcDef012345678` with your receiving address on Base
- `0xYOUR_PRIVATE_KEY_HERE` with your private key
- `1718438400` with a future timestamp (this example is set to June 15, 2024)

## Parameter Breakdown

- **SOURCE_TOKEN**: The token you're sending (e.g., USDC on ZetaChain)
- **AMOUNT**: Amount of tokens to swap (in the token's smallest unit)
- **TIP**: Incentive for fulfillers to execute your intent
- **SALT**: A unique number to generate a distinct intent ID
- **GAS_LIMIT**: Gas limit for execution on Base
- **PATH**: Array of token addresses for the swap path (must start with SOURCE_TOKEN)
- **STABLE_FLAGS**: Array of booleans indicating if each pool is stable (false) or volatile (true)
- **MIN_AMOUNT_OUT**: Minimum amount to receive after the swap
- **DEADLINE**: Unix timestamp after which the swap will revert
- **RECEIVER**: Address on Base to receive the swapped tokens

## Troubleshooting

### Common Issues

1. **Path and Flags Length Mismatch**: Ensure that `stableFlags.length == path.length - 1`
2. **Token Mismatch**: The first token in the path must match the `asset` parameter
3. **Insufficient Approval**: Ensure you've approved the initiator to spend at least `amount + tip` tokens

