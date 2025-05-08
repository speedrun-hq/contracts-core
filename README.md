# Speedrun EVM Contracts

[![codecov](https://codecov.io/gh/speedrun-hq/contracts-core/branch/main/graph/badge.svg)](https://codecov.io/gh/speedrun-hq/contracts-core)

This repository holds all the smart contracts for the Speedrun protocol deployed on EVM chains - including ZetaChain.

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

## Mainnet Contract Addresses

**Intent Contract Addresses**

*These are the main user facing contracts, to initiate and fulfil intents on connected chains*

```
base:       0x999fce149FD078DCFaa2C681e060e00F528552f4
arbitrum:   0xD6B0E2a8D115cCA2823c5F80F8416644F3970dD2
eth:        0x951AB2A5417a51eB5810aC44BC1fC716995C1CAB
bnb:        0x68282fa70a32E52711d437b6c5984B714Eec3ED0
polygon:    0x4017717c550E4B6E61048D412a718D6A8078d264
avalanche:  0x9a22A7d337aF1801BEEcDBE7f4f04BbD09F9E5bb
```

**Explorer Links**

- [Base Intent](https://basescan.org/address/0x999fce149FD078DCFaa2C681e060e00F528552f4)
- [Arbitrum Intent](https://arbiscan.io/address/0xd6b0e2a8d115cca2823c5f80f8416644f3970dd2)
- [Ethereum Intent](https://etherscan.io/address/0x951ab2a5417a51eb5810ac44bc1fc716995c1cab)
- [BNB Chain Intent](https://bscscan.com/address/0x68282fa70a32e52711d437b6c5984b714eec3ed0)
- [Polygon Intent](https://polygonscan.com/address/0x4017717c550e4b6e61048d412a718d6a8078d264)
- [Avalanche Intent](https://snowtrace.io/address/0x9a22a7d337af1801beecdbe7f4f04bbd09f9e5bb)
- [ZetaChain Router](https://zetachain.blockscout.com/address/0xcd74f36bad8f842641e67ec390be092a243297d6)
- [Algebra Swap Module](https://zetachain.blockscout.com/address/0x5d71aa0a455b7a714faf6fdf87829f98cbfe5bae)

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
