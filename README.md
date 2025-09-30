# SUI Motoko Library

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A comprehensive SUI blockchain library for Internet Computer (IC) built in Motoko. This library provides essential tools for working with SUI addresses, transactions, and blockchain operations within the IC ecosystem.

## Features

- **Address Management**: Generate, validate, and normalize SUI addresses
- **Transaction Building**: Create and manage SUI transactions (transfers, move calls, etc.)
- **Type Definitions**: Complete type system for SUI blockchain objects
- **Utilities**: Helper functions for common operations

## Table of Contents

- [Installation](#installation)
- [Quick Start](#quick-start)
- [Modules](#modules)
- [Usage Examples](#usage-examples)
- [API Reference](#api-reference)
- [Development](#development)
- [Contributing](#contributing)
- [License](#license)

## Installation

### For Library Usage (Mops)

```bash
# Install Mops if not already installed
npm i -g ic-mops

# Add the SUI package to your project
mops add sui
```

### For Development

```bash
git clone <repository-url>
cd sui
mops install
dfx start --background
dfx deploy
```

## Quick Start

```motoko
import Sui "mo:sui";

// Validate a SUI address
let isValid = Sui.Address.isValidAddress("0x1234567890abcdef1234567890abcdef12345678");

// Create a simple transaction
let gasData = {
  payment = [];
  owner = "0x1234567890abcdef1234567890abcdef12345678";
  price = 1000;
  budget = 10000;
};

let txData = Sui.Transaction.createTransferTransaction(
  "0x1234567890abcdef1234567890abcdef12345678", // sender
  "0xabcdef1234567890abcdef1234567890abcdef12", // recipient
  [],                                            // objects to transfer
  gasData
);
```

## Modules

### Types (`src/types.mo`)
Core type definitions for SUI blockchain objects:
- `SuiAddress` - SUI address type
- `ObjectRef` - Object reference type
- `TransactionData` - Transaction data structure
- `Command` - Transaction command variants
- And many more...

### Address (`src/address.mo`)
Address validation and manipulation:
- `isValidAddress()` - Validate SUI address format
- `normalizeAddress()` - Normalize address format
- `publicKeyToAddress()` - Generate address from public key

### Transaction (`src/transaction.mo`)
Transaction creation and management:
- `createTransferTransaction()` - Create transfer transactions
- `createMoveCallTransaction()` - Create move call transactions
- `signTransaction()` - Sign transactions (placeholder)

### Utils (`src/utils.mo`)
Utility functions:
- `bytesToHex()` - Convert bytes to hex string
- `hashText()` - Simple text hashing
- String manipulation functions

## Usage Examples

### Validating Addresses

```motoko
import Sui "mo:sui";

public func validateAddress(address : Text) : Bool {
  Sui.Address.isValidAddress(address)
}
```

### Creating Transactions

```motoko
import Sui "mo:sui";

public func createSampleTx(sender : Text) : Sui.Types.TransactionData {
  let gasData = {
    payment = [];
    owner = sender;
    price = 1000;
    budget = 10000;
  };

  Sui.Transaction.createTransferTransaction(sender, recipient, [], gasData)
}
```

## Development

### Running Locally

```bash
# Start the replica
dfx start --background

# Deploy canisters
dfx deploy

# Run tests
mops test
```

### Project Structure

```
src/
├── lib.mo          # Main library entry point
├── types.mo        # Type definitions
├── address.mo      # Address utilities
├── transaction.mo  # Transaction builder
├── utils.mo        # Utility functions
└── sui_backend/
    └── main.mo     # Example canister
test/
└── lib.test.mo     # Tests
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
