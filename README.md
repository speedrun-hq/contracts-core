# Speedrun Contracts

This repository holds all the smart contracts for the Speedrun protocol.

# EVM Contracts

Contains the Solidity contracts for intent-based bridge platform implementation.

## Intent Contract Interface

### Initiate Intent
```solidity
function initiate(
  address asset,
  uint256 amount,
  uint256 targetChain,
  bytes calldata receiver,
  uint256 tip,
  uint256 salt
) external
```

Creates a new intent for cross-chain transfer:
- `asset`: Address of the token to transfer
- `amount`: Amount of tokens to transfer
- `targetChain`: Chain ID of the destination chain
- `receiver`: Address of the receiver on the target chain (in bytes format)
- `tip`: Amount of tokens to pay as fee for the cross-chain transfer
- `salt`: Random value to ensure uniqueness of the intent ID

### Fulfill Intent
```solidity
function fulfill(
  bytes32 intentId,
  uint256 amount,
  address asset,
  address receiver
) external
```

Fulfills an existing intent:
- `intentId`: Identifier of the intent to fulfill
- `amount`: Actual amount of tokens being transferred (may differ from intent's amount)
- `asset`: Address of the token being transferred
- `receiver`: Address of the recipient on the target chain

## Architecture

[Learn more about the contract architecture](./evm/architecture.md)

## Development

### Prerequisites
- Foundry
- Solidity 0.8.26
- Node.js (for dependencies)

### Setup
1. Install dependencies:
```bash
npm install
```

2. Install Foundry:
```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

### Build
```bash
forge build
```

### Test
```bash
forge test
```

## Deployment

[Deploy the smart contracts](./evm/deployment.md)

## Mainnet Contract

TODO: deploy and verify new addresses

## License

MIT
