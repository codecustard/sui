# SUI Library Usage Examples

This document provides practical examples demonstrating the SUI blockchain library's functionality for Internet Computer (ICP) canisters.

## Table of Contents
1. [Address Operations](#address-operations)
2. [Transaction Building](#transaction-building)
3. [Wallet Management](#wallet-management)
4. [BCS Encoding](#bcs-encoding)
5. [Full Integration Example](#full-integration-example)

---

## Address Operations

### Validating a SUI Address

```motoko
import Validation "src/validation";
import Address "src/address";

// Check if an address is valid
let address = "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";
if (Validation.isValidAddress(address)) {
  // Address is valid - 32 bytes with 0x prefix
} else {
  // Invalid address format
};
```

### Normalizing Short Addresses

```motoko
// Short addresses can be normalized to full 64-char format
switch (Validation.normalizeAddress("0x1")) {
  case (#ok(normalized)) {
    // normalized = "0x0000000000000000000000000000000000000000000000000000000000000001"
  };
  case (#err(msg)) {
    // Handle error
  };
};
```

### Converting Public Key to Address

```motoko
import Address "src/address";
import Array "mo:base/Array";
import Nat8 "mo:base/Nat8";

// Ed25519 public key (32 bytes)
let ed25519PubKey = Array.tabulate<Nat8>(32, func(i) { Nat8.fromNat(i) });

switch (Address.publicKeyToAddress(ed25519PubKey, #ED25519)) {
  case (#ok(suiAddress)) {
    // suiAddress is a valid SUI address derived from the public key
  };
  case (#err(msg)) {
    // Handle error
  };
};

// Secp256k1 public key (33 bytes compressed)
let secp256k1PubKey = Array.tabulate<Nat8>(33, func(i) { Nat8.fromNat(i % 256) });

switch (Address.publicKeyToAddress(secp256k1PubKey, #Secp256k1)) {
  case (#ok(suiAddress)) {
    // suiAddress derived from Secp256k1 key
  };
  case (#err(msg)) {
    // Handle error
  };
};
```

---

## Transaction Building

### Simple Transfer Transaction

```motoko
import Transaction "src/transaction";
import Types "src/types";

let senderAddress = "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";
let recipientAddress = "0x0000000000000000000000000000000000000000000000000000000000000001";

// Configure gas settings
let gasData : Types.GasData = {
  payment = [];
  owner = senderAddress;
  price = 1000;      // Gas price per unit
  budget = 10_000_000; // Max gas budget in MIST
};

// Create transfer transaction
let transferTx = Transaction.createTransferTransaction(
  senderAddress,
  recipientAddress,
  [],  // objects to transfer (empty for SUI coin transfer)
  gasData
);
```

### SUI Coin Transfer

```motoko
// Reference to the coin object to transfer from
let coinObjectRef : Types.ObjectRef = {
  objectId = "0xabcdef..."; // Your coin object ID
  version = 1;
  digest = "base64EncodedDigest==";
};

// Transfer 1 SUI (1_000_000_000 MIST)
let suiTransferTx = Transaction.createSuiTransferTransaction(
  senderAddress,
  recipientAddress,
  1_000_000_000,  // 1 SUI in MIST
  coinObjectRef,
  gasData
);
```

### Move Call Transaction

```motoko
// Call a Move function
let moveCallTx = Transaction.createMoveCallTransaction(
  senderAddress,
  "0x0000000000000000000000000000000000000000000000000000000000000002", // package
  "coin",      // module
  "transfer",  // function
  ["0x2::sui::SUI"],  // type arguments
  [],  // arguments
  gasData
);
```

### Using TransactionBuilder

```motoko
// For complex transactions, use the builder API
let builder = Transaction.TransactionBuilder();

// Add inputs
let amountIdx = builder.addInput(Transaction.encodeBCSNat64(500_000_000)); // 0.5 SUI
let coinIdx = builder.addObjectInput(coinObjectRef);
let recipientIdx = builder.addInput(Transaction.encodeBCSAddress(recipientAddress));

// Add commands
// 1. Split coins to get exact amount
ignore builder.splitCoins(#Input(coinIdx), [#Input(amountIdx)]);

// 2. Transfer the split coin to recipient
ignore builder.transferObjects([#Result(0)], #Input(recipientIdx));

// Build final transaction
let complexTx = builder.build(senderAddress, gasData);
```

### Coin Split Transaction

```motoko
// Split a coin into multiple parts
let splitTx = Transaction.createCoinSplitTransaction(
  senderAddress,
  coinObjectRef,
  [100_000_000, 200_000_000, 300_000_000], // Split into 0.1, 0.2, 0.3 SUI
  gasData
);
```

### Coin Merge Transaction

```motoko
let sourceCoin : Types.ObjectRef = {
  objectId = "0x...";
  version = 1;
  digest = "...";
};

// Merge source coins into destination
let mergeTx = Transaction.createCoinMergeTransaction(
  senderAddress,
  coinObjectRef,     // destination
  [sourceCoin],      // sources to merge
  gasData
);
```

---

## Wallet Management

### Creating Wallet Instances

```motoko
import Wallet "src/wallet";

// Create wallets for different networks
let devnetWallet = Wallet.createDevnetWallet("my_key_name");
let testnetWallet = Wallet.createTestnetWallet("my_key_name");
let mainnetWallet = Wallet.createMainnetWallet("my_key_name");

// Custom RPC endpoint
let customWallet = Wallet.createCustomWallet(
  "my_key_name",
  "custom",
  "https://my-rpc-endpoint.com"
);
```

### Generating Addresses (requires ICP environment)

```motoko
// In an actor/canister context
actor {
  public shared func generateNewAddress() : async Result.Result<Wallet.AddressInfo, Text> {
    let wallet = Wallet.createDevnetWallet("dfx_test_key");
    await wallet.generateAddress(?"/0/0")
  };
};
```

---

## BCS Encoding

### Encoding Amounts (Nat64)

```motoko
// BCS encodes u64 values in little-endian format
let amount : Nat64 = 1_000_000_000; // 1 SUI
let encoded = Transaction.encodeBCSNat64(amount);
// Result: [0x00, 0xCA, 0x9A, 0x3B, 0x00, 0x00, 0x00, 0x00] (8 bytes, little-endian)
```

### Encoding Addresses

```motoko
// Addresses are encoded as 32 raw bytes
let address = "0x0000000000000000000000000000000000000000000000000000000000000001";
let encoded = Transaction.encodeBCSAddress(address);
// Result: 32 bytes, with last byte being 0x01
```

### Serializing Transactions

```motoko
// Get BCS-encoded transaction bytes
let txBytes = Transaction.serializeTransaction(txData);

// For debugging, use the debug function
let (first20, totalLen, ascii) = Transaction.debugSerializeTransaction(txData);
```

---

## Full Integration Example

```motoko
import Array "mo:base/Array";
import Nat8 "mo:base/Nat8";
import Result "mo:base/Result";
import Types "src/types";
import Transaction "src/transaction";
import Validation "src/validation";

actor SuiTransferExample {

  // Prepare and sign a SUI transfer
  public func prepareSuiTransfer(
    sender: Text,
    recipient: Text,
    amount: Nat64,
    coinObjectId: Text,
    coinVersion: Nat64,
    coinDigest: Text
  ) : async Result.Result<Text, Text> {

    // Validate addresses
    if (not Validation.isValidAddress(sender)) {
      return #err("Invalid sender address");
    };
    if (not Validation.isValidAddress(recipient)) {
      return #err("Invalid recipient address");
    };

    // Create coin reference
    let coinRef : Types.ObjectRef = {
      objectId = coinObjectId;
      version = coinVersion;
      digest = coinDigest;
    };

    // Gas configuration
    let gasData : Types.GasData = {
      payment = [];
      owner = sender;
      price = 1000;
      budget = 20_000_000;
    };

    // Build transaction
    let txData = Transaction.createSuiTransferTransaction(
      sender,
      recipient,
      amount,
      coinRef,
      gasData
    );

    // Serialize for network
    let txBytes = Transaction.serializeTransaction(txData);

    // Sign (with proper keys in production)
    let privateKey = Array.tabulate<Nat8>(32, func(i) { Nat8.fromNat(i) });
    let publicKey = Array.tabulate<Nat8>(32, func(i) { Nat8.fromNat(i + 32) });

    switch (Transaction.signTransaction(txData, privateKey, publicKey)) {
      case (#ok(signedTx)) {
        // Verify signature
        if (Transaction.verifyTransaction(signedTx)) {
          #ok("Transaction prepared and signed successfully. " #
              "Bytes: " # debug_show(txBytes.size()))
        } else {
          #err("Signature verification failed")
        }
      };
      case (#err(msg)) {
        #err("Signing failed: " # msg)
      };
    }
  };

  // Check if address is valid
  public query func validateAddress(address: Text) : async Bool {
    Validation.isValidAddress(address)
  };

  // Normalize a short address
  public query func normalizeAddress(address: Text) : async Result.Result<Text, Text> {
    Validation.normalizeAddress(address)
  };
};
```

---

## Running Tests

```bash
# Run all tests
mops test

# Build canisters (check only)
dfx build --check

# Deploy to local dfx
dfx start --background --clean
dfx deploy
```

---

## Common Patterns

### Error Handling Pattern

```motoko
// Always handle both success and error cases
switch (someOperation()) {
  case (#ok(result)) {
    // Process successful result
  };
  case (#err(errorMessage)) {
    // Log or propagate error
    Debug.print("Error: " # errorMessage);
  };
};
```

### Gas Budget Guidelines

| Operation | Recommended Budget |
|-----------|-------------------|
| Simple transfer | 10,000,000 MIST |
| Move call | 20,000,000 MIST |
| Complex transaction | 50,000,000 MIST |
| Package publish | 100,000,000 MIST |

---

*For more examples, see the test files in `/test/` directory.*
