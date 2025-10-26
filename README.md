# SUI Motoko Library

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A comprehensive SUI blockchain library for Internet Computer (IC) built in Motoko. This library provides essential tools for working with SUI addresses, transactions, and blockchain operations within the IC ecosystem.

## Features

- **Address Management**: Generate, validate, and normalize SUI addresses using BLAKE2b-256
- **Transaction Building**: Create and manage SUI transactions (transfers, move calls, etc.)
- **Transaction Signing**: Sign transactions using ICP threshold ECDSA (Secp256k1)
- **BCS Encoding**: Full Binary Canonical Serialization support for SUI transactions
- **Wallet Integration**: Complete wallet implementation with ICP Chain Fusion
- **Type Definitions**: Complete type system for SUI blockchain objects
- **SUI Network Integration**: Query balances and submit transactions to SUI RPC
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
- `Command` - Transaction command variants (MoveCall, TransferObjects, SplitCoins, MergeCoins)
- `SignatureScheme` - Signature schemes (ED25519, Secp256k1, Secp256r1)
- And many more...

### Address (`src/address.mo`)
Address validation and manipulation:
- `isValidAddress()` - Validate SUI address format (32-byte hex with "0x" prefix)
- `normalizeAddress()` - Normalize address format
- `publicKeyToAddress()` - Generate SUI address from public key using BLAKE2b-256
- `hexToBytes()` / `bytesToHex()` - Hex conversion utilities

### Transaction (`src/transaction.mo`)
Transaction creation and BCS serialization:
- `TransactionBuilder` - Fluent API for building complex transactions
- `createTransferTransaction()` - Create object transfer transactions
- `createMoveCallTransaction()` - Create Move function call transactions
- `createSuiTransferTransaction()` - Create SUI coin transfer transactions
- `serializeTransaction()` - BCS serialization for SUI network
- `encodeU64ToBCS()` - Encode Nat64 values to BCS format
- `encodeAddressToBCS()` - Encode addresses to BCS format (32 bytes)
- `decodeBase64ToBytes()` - Decode base64 strings to bytes

### Wallet (`src/wallet.mo`)
Complete wallet implementation with ICP Chain Fusion:
- `Wallet` class - Full-featured SUI wallet using ICP threshold ECDSA
- `generateAddress()` - Generate SUI addresses using ICP's threshold ECDSA
- `signTransaction()` - Sign transactions with Secp256k1 and proper recovery ID
- `getBalance()` - Query SUI coin balances from the network
- `sendTransaction()` - Complete flow: create, sign, and submit transactions
- `createTransferTransaction()` - Build transfer transactions with real coin objects
- Factory functions: `createMainnetWallet()`, `createTestnetWallet()`, `createDevnetWallet()`

### Validation (`src/validation.mo`)
Input validation utilities:
- Address validation and normalization
- Object ID validation
- Hex string parsing

### Utils (`src/utils.mo`)
Utility functions:
- `bytesToHex()` / `hexToBytes()` - Hex conversion
- `hashText()` - Simple text hashing
- String manipulation functions (toUpperCase, toLowerCase, startsWith)

## Usage Examples

### Validating Addresses

```motoko
import Address "mo:sui/address";

public func validateAddress(address : Text) : Bool {
  Address.isValidAddress(address)
}
```

### Creating and Signing Transactions with Wallet

```motoko
import Wallet "mo:sui/wallet";
import Types "mo:sui/types";

actor SuiExample {
  // Create a wallet for testnet
  let wallet = Wallet.createTestnetWallet("test_key_1");

  // Generate a SUI address
  public func generateMyAddress() : async Wallet.Result<Wallet.AddressInfo> {
    await wallet.generateAddress(?"0")  // Derivation path "0"
  };

  // Check balance
  public func checkBalance(address : Types.SuiAddress) : async Wallet.Result<Wallet.Balance> {
    await wallet.getBalance(address)
  };

  // Send SUI coins
  public func sendSUI(
    from : Types.SuiAddress,
    to : Types.SuiAddress,
    amount : Nat64  // Amount in MIST (1 SUI = 1_000_000_000 MIST)
  ) : async Wallet.Result<Wallet.TransactionResult> {
    await wallet.sendTransaction(
      from,
      to,
      amount,
      ?10_000_000,  // Gas budget: 10M MIST (0.01 SUI)
      ?"0"          // Derivation path
    )
  };
}
```

### Building Custom Transactions

```motoko
import Transaction "mo:sui/transaction";
import Types "mo:sui/types";

// Create a complex transaction using the builder
public func buildComplexTransaction(sender : Types.SuiAddress) : Types.TransactionData {
  let builder = Transaction.TransactionBuilder();

  // Add inputs
  let amountBytes = Transaction.encodeU64ToBCS(1_000_000_000);  // 1 SUI
  let amountIdx = builder.addInput(amountBytes);

  let recipientBytes = Transaction.encodeAddressToBCS("0xabcd...");
  let recipientIdx = builder.addInput(recipientBytes);

  // Add commands
  ignore builder.moveCall(
    "0x2",  // SUI framework package
    "coin",
    "transfer",
    ["0x2::sui::SUI"],
    [#Input(amountIdx), #Input(recipientIdx)]
  );

  // Build final transaction
  let gasData : Types.GasData = {
    payment = [];
    owner = sender;
    price = 1000;
    budget = 10_000_000;
  };

  builder.build(sender, gasData)
}
```

### BCS Encoding Examples

```motoko
import Transaction "mo:sui/transaction";

// Encode a Nat64 amount for SUI transactions
let amount : Nat64 = 1_000_000_000;  // 1 SUI in MIST
let encodedAmount = Transaction.encodeU64ToBCS(amount);

// Encode a SUI address (32 bytes)
let address = "0x1234567890abcdef1234567890abcdef12345678";
let encodedAddress = Transaction.encodeAddressToBCS(address);

// Decode base64 digest
let base64Digest = "SGVsbG8gV29ybGQ=";
let digestBytes = Transaction.decodeBase64ToBytes(base64Digest);
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
├── types.mo        # Type definitions for SUI blockchain
├── address.mo      # Address generation and validation
├── transaction.mo  # Transaction building and BCS serialization
├── wallet.mo       # Wallet implementation with ICP threshold ECDSA
├── validation.mo   # Input validation utilities
├── utils.mo        # Utility functions
└── sui_backend/
    └── main.mo     # Example canister with demo functions
examples/
└── sui_example_basic.mo  # Basic usage examples
test/
├── lib.test.mo          # Library tests
├── address.test.mo      # Address utility tests
├── transaction.test.mo  # Transaction building tests
├── wallet.test.mo       # Wallet functionality tests
├── validation.test.mo   # Validation tests
└── utils.test.mo        # Utility tests
```

## Key Implementation Details

### Transaction Signing Flow

1. **Transaction Building**: Use `TransactionBuilder` or helper functions to create transaction data
2. **BCS Serialization**: Transaction data is serialized to bytes using Binary Canonical Serialization
3. **Hashing**: Transaction bytes are hashed using Keccak-256 (SHA-3)
4. **Signing**: Hash is signed using ICP's threshold ECDSA with Secp256k1 curve
5. **Recovery ID**: Computed and added to signature for public key recovery
6. **Formatting**: Signature is formatted as `[scheme_flag | signature | recovery_id]` and base64-encoded
7. **Submission**: Signed transaction is submitted to SUI RPC endpoint

### ECDSA Integration

This library uses Internet Computer's **threshold ECDSA** feature for signing:
- **No private keys stored**: Keys are managed by ICP subnet
- **Threshold security**: Signature requires cooperation of subnet nodes
- **Secp256k1 curve**: Compatible with SUI blockchain requirements
- **Deterministic signatures**: Ensures consistent signature generation

### BCS Encoding

Full Binary Canonical Serialization support:
- **ULEB128 encoding**: For variable-length integers and array lengths
- **U64 encoding**: Little-endian 8-byte encoding for amounts
- **Address encoding**: 32-byte fixed-length encoding
- **Base64 decoding**: For digests from SUI RPC responses

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
