# SUI Motoko Library

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A comprehensive SUI blockchain library for Internet Computer (ICP) built in Motoko. This library enables ICP canisters to interact with the SUI blockchain using ICP's threshold ECDSA for secure key management.

## Features

- **Address Generation**: Generate SUI addresses using ICP threshold ECDSA (Secp256k1)
- **SUI Transfers**: Send SUI tokens with proper BCS serialization
- **Balance Queries**: Check balances and list coin objects
- **Transaction Status**: Query transaction confirmation and details
- **Testnet Faucet**: Request testnet SUI tokens programmatically
- **Type Definitions**: Complete type system for SUI blockchain objects

## Table of Contents

- [Installation](#installation)
- [Quick Start](#quick-start)
- [Core Functions](#core-functions)
- [Modules](#modules)
- [Usage Examples](#usage-examples)
- [API Reference](#api-reference)
- [Development](#development)
- [License](#license)

## Installation

### Prerequisites

- [dfx](https://internetcomputer.org/docs/current/developer-docs/setup/install) (IC SDK)
- [mops](https://mops.one/) (Motoko package manager)

### Setup

```bash
git clone <repository-url>
cd sui
mops install
dfx start --background
dfx deploy
```

## Quick Start

### 1. Generate a SUI Address

```bash
dfx canister call sui_example_basic generateAddress '(null)'
```

Returns:
```
(variant { ok = record { address = "0x9c219cda57d9f8cac8bbcd5356f7d416d5286a91605ea6c1465c645e7b054c02"; ... }})
```

### 2. Check Balance

```bash
dfx canister call sui_example_basic getFormattedBalance '("0x9c219cda...")'
```

Returns:
```
(variant { ok = "0.8190 SUI" })
```

### 3. Transfer SUI (Testnet)

```bash
dfx canister call sui_example_basic transferSuiSafe '(
  "0x<sender_address>",
  "0x<recipient_address>",
  1000000 : nat64,
  10000000 : nat64
)'
```

Returns:
```
(variant { ok = "8vvjczwT2PicnDSuj5sjfJxCehZAR5U9ugZ8rqGfHgEG" })
```

### 4. Check Transaction Status

```bash
dfx canister call sui_example_basic getTransactionStatus '("8vvjczwT2PicnDSuj5sjfJxCehZAR5U9ugZ8rqGfHgEG")'
```

Returns:
```
(variant { ok = record { status = "success"; gasUsed = 1_997_880 : nat64; ... }})
```

## Core Functions

| Function | Description |
|----------|-------------|
| `generateAddress(?path)` | Generate SUI address using ICP threshold ECDSA |
| `validateAddress(address)` | Validate SUI address format |
| `checkBalance(address)` | Get balance in MIST with coin count |
| `getFormattedBalance(address)` | Get human-readable balance ("X.XXXX SUI") |
| `getSuiCoins(address)` | List all coin objects for an address |
| `transferSuiSafe(sender, recipient, amount, gasBudget)` | Transfer SUI using BCS serialization (recommended) |
| `transferSuiSimple(sender, recipient, amount, gasBudget)` | Transfer SUI using RPC method |
| `mergeCoins(owner, gasBudget)` | Merge multiple coins into one |
| `getTransactionStatus(digest)` | Get transaction status, gas used, timestamp |
| `requestFaucet(address)` | Request testnet SUI tokens |

## Modules

### sui_transfer.mo
Core transfer functionality with BCS serialization:
- `transferSuiSimple()` - Transfer using `unsafe_transferSui` RPC
- `transferSuiSafe()` - Transfer with proper BCS transaction building
- `mergeCoins()` - Merge multiple coins into one
- `getTransactionStatus()` - Query transaction status
- `getObjectInfo()` - Fetch object data from RPC
- `formatBalance()` - Format MIST to SUI string
- `requestTestnetFaucet()` - Request testnet tokens

### wallet.mo
Wallet management using ICP threshold ECDSA:
- `createTestnetWallet()` / `createMainnetWallet()` / `createDevnetWallet()`
- `generateAddress()` - Generate new SUI address
- `getBalance()` - Query balance from RPC
- `signTransaction()` - Sign with threshold ECDSA

### address.mo
Address utilities:
- `isValidAddress()` - Validate SUI address format
- `normalizeAddress()` - Normalize to full 64-char format
- `publicKeyToAddress()` - Derive address from public key

### transaction.mo
Transaction building:
- `createTransferTransaction()` - Build transfer transaction
- `createMoveCallTransaction()` - Build Move call transaction
- `serializeTransaction()` - BCS serialization

### types.mo
Type definitions:
- `SuiAddress`, `ObjectRef`, `TransactionData`
- `Command`, `Argument`, `CallArg`
- `GasData`, `SignatureScheme`

### validation.mo
Validation utilities:
- Address validation
- Object ID validation
- Hex conversion

## Usage Examples

See [USAGE_EXAMPLES.md](./USAGE_EXAMPLES.md) for detailed examples including:
- Address generation and validation
- SUI transfers on testnet
- Transaction building
- Balance queries
- Error handling patterns

## API Reference

See [API_REFERENCE.md](./API_REFERENCE.md) for complete API documentation.

## Development

### Running Locally

```bash
# Start local replica
dfx start --background

# Deploy canisters
dfx deploy

# Test a function
dfx canister call sui_example_basic generateAddress '(null)'
```

### Project Structure

```
src/
├── lib.mo              # Main library entry point
├── types.mo            # Type definitions
├── address.mo          # Address utilities
├── transaction.mo      # Transaction builder
├── wallet.mo           # Wallet management (ICP ECDSA)
├── sui_transfer.mo     # SUI transfer functions
├── validation.mo       # Validation utilities
├── utils.mo            # Helper functions
└── sui_backend/
    └── main.mo         # Backend canister
examples/
└── sui_example_basic.mo  # Example canister with all functions
test/
└── *.test.mo           # Test files
```

### Running Tests

```bash
mops test
```

### Network Configuration

The example canister uses SUI testnet by default:
- RPC URL: `https://fullnode.testnet.sui.io:443`
- Faucet: `https://faucet.testnet.sui.io/v2/gas`

## Key Concepts

### MIST vs SUI
- 1 SUI = 1,000,000,000 MIST
- All amounts in the API are in MIST
- Use `getFormattedBalance()` for human-readable format

### Gas Budget
- Recommended: 10,000,000 MIST (0.01 SUI) for simple transfers
- The actual gas used is typically ~2,000,000 MIST

### ICP Threshold ECDSA
This library uses ICP's threshold ECDSA (Secp256k1) for:
- Secure key generation without exposing private keys
- Transaction signing within the canister
- Key derivation paths for multiple addresses

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
