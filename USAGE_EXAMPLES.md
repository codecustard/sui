# SUI Library Usage Examples

Practical examples for interacting with the SUI blockchain from ICP canisters.

## Table of Contents

1. [Quick Start (CLI)](#quick-start-cli)
2. [Address Operations](#address-operations)
3. [Balance Queries](#balance-queries)
4. [SUI Transfers](#sui-transfers)
5. [Coin Management](#coin-management)
6. [Transaction Status](#transaction-status)
7. [Testnet Faucet](#testnet-faucet)
8. [Motoko Integration](#motoko-integration)
9. [Error Handling](#error-handling)

---

## Quick Start (CLI)

These examples use `dfx canister call` to interact with the deployed canister.

### Generate Address

```bash
dfx canister call sui_example_basic generateAddress '(null)'
```

Output:
```
(variant {
  ok = record {
    created = 1_768_616_660_443_507_000 : int;
    publicKey = blob "\02\a3\72\da...";
    scheme = variant { Secp256k1 };
    address = "0x9c219cda57d9f8cac8bbcd5356f7d416d5286a91605ea6c1465c645e7b054c02";
  }
})
```

### Check Balance (Formatted)

```bash
dfx canister call sui_example_basic getFormattedBalance '("0x9c219cda57d9f8cac8bbcd5356f7d416d5286a91605ea6c1465c645e7b054c02")'
```

Output:
```
(variant { ok = "0.8190 SUI" })
```

### Transfer SUI

```bash
dfx canister call sui_example_basic transferSuiSafe '(
  "0x9c219cda57d9f8cac8bbcd5356f7d416d5286a91605ea6c1465c645e7b054c02",
  "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
  1000000 : nat64,
  10000000 : nat64
)'
```

Parameters:
- Sender address
- Recipient address
- Amount in MIST (1000000 = 0.001 SUI)
- Gas budget in MIST (10000000 = 0.01 SUI)

Output:
```
(variant { ok = "8vvjczwT2PicnDSuj5sjfJxCehZAR5U9ugZ8rqGfHgEG" })
```

### Check Transaction Status

```bash
dfx canister call sui_example_basic getTransactionStatus '("8vvjczwT2PicnDSuj5sjfJxCehZAR5U9ugZ8rqGfHgEG")'
```

Output:
```
(variant {
  ok = record {
    status = "success";
    error = null;
    timestamp = opt "1768616686913";
    digest = "8vvjczwT2PicnDSuj5sjfJxCehZAR5U9ugZ8rqGfHgEG";
    gasUsed = 1_997_880 : nat64;
  }
})
```

---

## Address Operations

### Validate Address

```bash
dfx canister call sui_example_basic validateAddress '("0x9c219cda57d9f8cac8bbcd5356f7d416d5286a91605ea6c1465c645e7b054c02")'
```

Output:
```
(true)
```

### Generate with Derivation Path

```bash
# Generate address with custom derivation path
dfx canister call sui_example_basic generateAddress '(opt "/0/1")'
```

---

## Balance Queries

### Raw Balance (MIST)

```bash
dfx canister call sui_example_basic checkBalance '("0x9c219cda57d9f8cac8bbcd5356f7d416d5286a91605ea6c1465c645e7b054c02")'
```

Output:
```
(variant {
  ok = record {
    coinCount = 1 : nat;
    totalBalance = 819_010_600 : nat64
  }
})
```

### Formatted Balance (SUI)

```bash
dfx canister call sui_example_basic getFormattedBalance '("0x9c219cda57d9f8cac8bbcd5356f7d416d5286a91605ea6c1465c645e7b054c02")'
```

Output:
```
(variant { ok = "0.8190 SUI" })
```

### List Coin Objects

```bash
dfx canister call sui_example_basic getSuiCoins '("0x9c219cda57d9f8cac8bbcd5356f7d416d5286a91605ea6c1465c645e7b054c02")'
```

Output:
```
(variant {
  ok = vec {
    record {
      coinObjectId = "0xabc123...";
      balance = 819_010_600 : nat64;
      version = 12345 : nat64;
      digest = "xyz789...";
    }
  }
})
```

---

## SUI Transfers

### Using transferSuiSafe (Recommended)

This method builds the transaction locally with proper BCS serialization:

```bash
dfx canister call sui_example_basic transferSuiSafe '(
  "0x9c219cda57d9f8cac8bbcd5356f7d416d5286a91605ea6c1465c645e7b054c02",
  "0x0000000000000000000000000000000000000000000000000000000000000001",
  500000000 : nat64,
  10000000 : nat64
)'
```

**Why use transferSuiSafe?**
- Builds transaction locally (no `unsafe_*` RPC methods)
- Proper BCS serialization
- Full control over transaction structure

### Using transferSuiNew (Alternative)

This method uses the SUI RPC's `unsafe_transferSui` method:

```bash
dfx canister call sui_example_basic transferSuiNew '(
  "0x9c219cda57d9f8cac8bbcd5356f7d416d5286a91605ea6c1465c645e7b054c02",
  "0x0000000000000000000000000000000000000000000000000000000000000001",
  500000000 : nat64,
  10000000 : nat64
)'
```

### Amount Reference

| Amount (MIST) | Amount (SUI) |
|---------------|--------------|
| 1,000,000 | 0.001 SUI |
| 10,000,000 | 0.01 SUI |
| 100,000,000 | 0.1 SUI |
| 1,000,000,000 | 1 SUI |

---

## Coin Management

### Merge Coins

Consolidate multiple coin objects into one (reduces fragmentation):

```bash
dfx canister call sui_example_basic mergeCoins '(
  "0x9c219cda57d9f8cac8bbcd5356f7d416d5286a91605ea6c1465c645e7b054c02",
  10000000 : nat64
)'
```

Parameters:
- Owner address (must have 2+ coins)
- Gas budget in MIST

Output (success):
```
(variant { ok = "TRANSACTION_DIGEST" })
```

Output (not enough coins):
```
(variant { err = "Need at least 2 coins to merge. Found: 1" })
```

**When to use:**
- After receiving many small payments
- Before a large transfer (avoids multi-coin complexity)
- To simplify coin management

---

## Transaction Status

### Get Transaction Details

```bash
dfx canister call sui_example_basic getTransactionStatus '("YOUR_TRANSACTION_DIGEST")'
```

### Status Values

| Status | Meaning |
|--------|---------|
| `"success"` | Transaction executed successfully |
| `"failure"` | Transaction failed (check `error` field) |

### View on Explorer

After getting a transaction digest, view it on SUI Explorer:
```
https://suiscan.xyz/testnet/tx/<DIGEST>
```

---

## Testnet Faucet

### Request Testnet SUI

```bash
dfx canister call sui_example_basic requestFaucet '("0x9c219cda57d9f8cac8bbcd5356f7d416d5286a91605ea6c1465c645e7b054c02")'
```

**Note:** The faucet has rate limits. If you see "Too Many Requests", wait and try again.

---

## Motoko Integration

### Basic Canister Setup

```motoko
import Result "mo:base/Result";
import SuiTransfer "../src/sui_transfer";
import Wallet "../src/wallet";
import Types "../src/types";

actor MyCanister {

  // Generate a new SUI address
  public func getMyAddress() : async Result.Result<Text, Text> {
    let wallet = Wallet.createTestnetWallet("dfx_test_key");
    switch (await wallet.generateAddress(null)) {
      case (#ok(info)) { #ok(info.address) };
      case (#err(e)) { #err(e) };
    }
  };

  // Check balance
  public func myBalance(address : Text) : async Result.Result<Text, Text> {
    let wallet = Wallet.createTestnetWallet("dfx_test_key");
    switch (await wallet.getBalance(address)) {
      case (#ok(balance)) {
        #ok(SuiTransfer.formatBalance(balance.total_balance))
      };
      case (#err(e)) { #err(e) };
    }
  };

  // Transfer SUI
  public func sendSui(
    sender : Text,
    recipient : Text,
    amount : Nat64
  ) : async Result.Result<Text, Text> {
    let wallet = Wallet.createTestnetWallet("dfx_test_key");

    // Get coins
    let coins = switch (await wallet.getBalance(sender)) {
      case (#ok(b)) { b.objects };
      case (#err(e)) { return #err(e) };
    };

    if (coins.size() == 0) {
      return #err("No coins available");
    };

    let coin = coins[0];
    let rpcUrl = "https://fullnode.testnet.sui.io:443";

    // Sign function using ICP threshold ECDSA
    let signFunc = func(messageHash : Blob) : async Result.Result<Blob, Text> {
      await wallet.signMessage(messageHash)
    };

    let getPublicKeyFunc = func() : async Result.Result<Blob, Text> {
      await wallet.getPublicKey()
    };

    await SuiTransfer.transferSuiSafe(
      rpcUrl,
      sender,
      coin.coinObjectId,
      recipient,
      amount,
      10_000_000, // gas budget
      signFunc,
      getPublicKeyFunc
    )
  };
}
```

### Using the Wallet Module

```motoko
import Wallet "../src/wallet";

// Create wallet for different networks
let devnetWallet = Wallet.createDevnetWallet("my_key");
let testnetWallet = Wallet.createTestnetWallet("my_key");
let mainnetWallet = Wallet.createMainnetWallet("my_key");

// Custom RPC endpoint
let customWallet = Wallet.createCustomWallet(
  "my_key",
  "custom",
  "https://my-rpc.example.com"
);
```

### Direct SuiTransfer Module Usage

```motoko
import SuiTransfer "../src/sui_transfer";
import Result "mo:base/Result";

// Format balance
let formatted = SuiTransfer.formatBalance(1_500_000_000);
// Returns: "1.5000 SUI"

// Get transaction status
let status = await SuiTransfer.getTransactionStatus(
  "https://fullnode.testnet.sui.io:443",
  "TRANSACTION_DIGEST"
);

// Request faucet
let faucetResult = await SuiTransfer.requestTestnetFaucet(
  "0x9c219cda..."
);
```

---

## Error Handling

### Common Errors and Solutions

| Error | Cause | Solution |
|-------|-------|----------|
| `"Insufficient balance"` | Not enough SUI | Check balance, request from faucet |
| `"Invalid address"` | Malformed address | Ensure 64 hex chars with 0x prefix |
| `"No coins available"` | Address has no coin objects | Fund the address first |
| `"Too Many Requests"` | Faucet rate limit | Wait and retry |
| `"cycles are required"` | Insufficient cycles | Increase cycles in HTTP call |

### Error Handling Pattern

```motoko
switch (await someOperation()) {
  case (#ok(result)) {
    // Handle success
    Debug.print("Success: " # debug_show(result));
  };
  case (#err(errorMessage)) {
    // Handle error
    Debug.print("Error: " # errorMessage);
    // Optionally return error to caller
    return #err(errorMessage);
  };
};
```

---

## Gas Budget Guidelines

| Operation | Recommended Budget (MIST) | Typical Usage |
|-----------|--------------------------|---------------|
| Simple transfer | 10,000,000 | ~2,000,000 |
| Move call | 20,000,000 | ~5,000,000 |
| Complex tx | 50,000,000 | varies |

**Tip:** The gas budget is the maximum you're willing to pay. Unused gas is returned.

---

## Network URLs

| Network | RPC URL |
|---------|---------|
| Testnet | `https://fullnode.testnet.sui.io:443` |
| Mainnet | `https://fullnode.mainnet.sui.io:443` |
| Devnet | `https://fullnode.devnet.sui.io:443` |

---

*Last updated: 2025-01-16*
