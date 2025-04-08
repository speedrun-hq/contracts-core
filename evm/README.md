# EVM Contracts

This directory contains the Solidity contracts for intent-based bridge platform implementation.

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

[Learn more about the contract architecture](./architecture.md)

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

[Deploy the smart contracts](./deployment.md)

## Mainnet Contract

ZetaChain router: `0xBE9fA6C741bc9623f67806d9120493abE6962Bb9`

| Chain   | Intent Contract |
|-----------|----------|
| Ethereum  | `0x0ec6599Bc62Ad5FF3e72493DEc1318BbB2899D1B`        |
| BNB Chain | `0x0ec6599Bc62Ad5FF3e72493DEc1318BbB2899D1B`       |
| Polygon   | `0x0ec6599Bc62Ad5FF3e72493DEc1318BbB2899D1B`      |
| Base      | `0xAd505e8d97FB872EBdF575a5FC0Dc141e5f786ad`     |
| Avalanche | `0x0ec6599Bc62Ad5FF3e72493DEc1318BbB2899D1B`    |
| Arbitrum  | `0x951AB2A5417a51eB5810aC44BC1fC716995C1CAB`    |


## License

MIT
