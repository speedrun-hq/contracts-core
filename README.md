# Speedrun Contracts

This repository holds all the smart contracts for the Speedrun protocol.

Currently the repo only implements Solidity contracts but it will also source code for other smart contract languages like Solana in the future.

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

## Administration

The Speedrun protocol uses role-based access control for administrative functions. Both the `Intent` and `Router` contracts implement OpenZeppelin's `AccessControlUpgradeable` for permission management.

### Common Roles

- **`DEFAULT_ADMIN_ROLE`**: Main administrator role that can grant/revoke other roles and perform critical operations
- **`PAUSER_ROLE`**: Role responsible for pausing contract functions in emergency situations

### Intent Contract Administration

| Role | Function | Description |
|------|----------|-------------|
| `DEFAULT_ADMIN_ROLE` | `upgradeToAndCall` | Upgrade implementation contract (UUPS pattern) |
| `DEFAULT_ADMIN_ROLE` | `unpause` | Unpauses the contract operations |
| `DEFAULT_ADMIN_ROLE` | `updateGateway` | Updates the gateway contract address |
| `DEFAULT_ADMIN_ROLE` | `updateRouter` | Updates the router contract address on ZetaChain |
| `PAUSER_ROLE` | `pause` | Pauses `initiate` and `fulfill` functions. Note: `onCall` remains active even when paused to ensure settlements from ZetaChain are processed |

### Router Contract Administration

| Role | Function | Description |
|------|----------|-------------|
| `DEFAULT_ADMIN_ROLE` | `upgradeToAndCall` | Upgrade implementation contract (UUPS pattern) |
| `DEFAULT_ADMIN_ROLE` | `unpause` | Unpauses the contract operations |
| `DEFAULT_ADMIN_ROLE` | `updateGateway` | Updates the gateway contract address |
| `DEFAULT_ADMIN_ROLE` | `updateSwapModule` | Updates the swap module address |
| `DEFAULT_ADMIN_ROLE` | `setIntentContract` | Sets the Intent contract address for a specific chain |
| `DEFAULT_ADMIN_ROLE` | `addToken` | Adds a new supported token to the system |
| `DEFAULT_ADMIN_ROLE` | `addTokenAssociation` | Associates a token with its addresses on different chains |
| `DEFAULT_ADMIN_ROLE` | `updateTokenAssociation` | Updates an existing token association |
| `DEFAULT_ADMIN_ROLE` | `removeTokenAssociation` | Removes a token association for a specific chain |
| `DEFAULT_ADMIN_ROLE` | `setWithdrawGasLimit` | Updates the gas limit for withdraw operations |
| `PAUSER_ROLE` | `pause` | Pauses the `onCall` function which prevents processing new cross-chain transactions |

## License

MIT
