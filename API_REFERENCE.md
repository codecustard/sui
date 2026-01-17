# API Reference

Complete API documentation for the SUI Motoko Library.

## Table of Contents

- [sui_example_basic (Canister)](#sui_example_basic-canister)
- [SuiTransfer Module](#suitransfer-module)
- [Wallet Module](#wallet-module)
- [Address Module](#address-module)
- [Validation Module](#validation-module)
- [Types Module](#types-module)

---

## sui_example_basic (Canister)

The example canister exposes these public functions for interacting with SUI testnet.

### generateAddress

Generate a new SUI address using ICP threshold ECDSA.

```motoko
public func generateAddress(derivation_path: ?Text) : async Result.Result<Wallet, Text>
```

**Parameters:**
- `derivation_path` - Optional derivation path (e.g., `"/0/1"`). Pass `null` for default.

**Returns:**
```motoko
record {
  address : Text;           // SUI address (0x...)
  publicKey : Blob;         // Compressed public key (33 bytes)
  scheme : SignatureScheme; // #Secp256k1
  created : Int;            // Timestamp
}
```

**Example:**
```bash
dfx canister call sui_example_basic generateAddress '(null)'
dfx canister call sui_example_basic generateAddress '(opt "/0/1")'
```

---

### validateAddress

Check if a SUI address is valid.

```motoko
public func validateAddress(address: SuiAddress) : async Bool
```

**Parameters:**
- `address` - SUI address to validate

**Returns:** `true` if valid, `false` otherwise

**Example:**
```bash
dfx canister call sui_example_basic validateAddress '("0x9c219cda57d9f8cac8bbcd5356f7d416d5286a91605ea6c1465c645e7b054c02")'
```

---

### checkBalance

Get balance in raw MIST with coin count.

```motoko
public func checkBalance(address : Text) : async Result.Result<{totalBalance: Nat64; coinCount: Nat}, Text>
```

**Parameters:**
- `address` - SUI address

**Returns:**
```motoko
record {
  totalBalance : Nat64;  // Balance in MIST
  coinCount : Nat;       // Number of coin objects
}
```

**Example:**
```bash
dfx canister call sui_example_basic checkBalance '("0x9c219cda...")'
```

---

### getFormattedBalance

Get human-readable balance.

```motoko
public func getFormattedBalance(address : Text) : async Result.Result<Text, Text>
```

**Parameters:**
- `address` - SUI address

**Returns:** Formatted string like `"0.8190 SUI"`

**Example:**
```bash
dfx canister call sui_example_basic getFormattedBalance '("0x9c219cda...")'
```

---

### getSuiCoins

List all coin objects for an address.

```motoko
public func getSuiCoins(address : Text) : async Result.Result<[Types.SuiCoin], Text>
```

**Parameters:**
- `address` - SUI address

**Returns:** Array of coin objects:
```motoko
record {
  coinObjectId : Text;
  balance : Nat64;
  version : Nat64;
  digest : Text;
}
```

---

### transferSuiSafe

Transfer SUI using local BCS serialization (recommended).

```motoko
public func transferSuiSafe(
  senderAddress : Text,
  recipientAddress : Text,
  amount : Nat64,
  gasBudget : Nat64
) : async Result.Result<Text, Text>
```

**Parameters:**
- `senderAddress` - Sender's SUI address
- `recipientAddress` - Recipient's SUI address
- `amount` - Amount in MIST (1 SUI = 1,000,000,000 MIST)
- `gasBudget` - Maximum gas budget in MIST

**Returns:** Transaction digest on success

**Example:**
```bash
dfx canister call sui_example_basic transferSuiSafe '(
  "0x9c219cda...",
  "0x1234abcd...",
  1000000 : nat64,
  10000000 : nat64
)'
```

---

### transferSuiNew

Transfer SUI using RPC method (alternative).

```motoko
public func transferSuiNew(
  senderAddress : Text,
  recipientAddress : Text,
  amount : Nat64,
  gasBudget : Nat64
) : async Result.Result<Text, Text>
```

**Parameters:** Same as `transferSuiSafe`

**Returns:** Transaction digest on success

---

### mergeCoins

Merge multiple coin objects into one.

```motoko
public func mergeCoins(
  ownerAddress : Text,
  gasBudget : Nat64
) : async Result.Result<Text, Text>
```

**Parameters:**
- `ownerAddress` - Address that owns the coins
- `gasBudget` - Maximum gas budget in MIST

**Returns:** Transaction digest on success

**Notes:**
- Requires at least 2 coins
- First coin becomes the destination (and pays gas)
- All other coins are merged into the first

**Example:**
```bash
dfx canister call sui_example_basic mergeCoins '(
  "0x9c219cda...",
  10000000 : nat64
)'
```

---

### getTransactionStatus

Get transaction status by digest.

```motoko
public func getTransactionStatus(digest : Text) : async Result.Result<SuiTransfer.TransactionStatus, Text>
```

**Parameters:**
- `digest` - Transaction digest (base58 string)

**Returns:**
```motoko
record {
  digest : Text;
  status : Text;       // "success" or "failure"
  error : ?Text;       // Error message if failed
  gasUsed : Nat64;     // Gas consumed in MIST
  timestamp : ?Text;   // Unix timestamp in milliseconds
}
```

**Example:**
```bash
dfx canister call sui_example_basic getTransactionStatus '("8vvjczwT2PicnDSuj5sjfJxCehZAR5U9ugZ8rqGfHgEG")'
```

---

### requestFaucet

Request testnet SUI tokens.

```motoko
public func requestFaucet(address : Text) : async Result.Result<Text, Text>
```

**Parameters:**
- `address` - SUI address to fund

**Returns:** Success message or error (rate limited)

**Example:**
```bash
dfx canister call sui_example_basic requestFaucet '("0x9c219cda...")'
```

---

## SuiTransfer Module

Located at `src/sui_transfer.mo`. Core transfer functionality.

### transferSuiSimple

Transfer using `unsafe_transferSui` RPC method.

```motoko
public func transferSuiSimple(
  rpcUrl : Text,
  senderAddress : Text,
  coinObjectId : Text,
  recipientAddress : Text,
  amount : Nat64,
  gasBudget : Nat64,
  signFunc : (Blob) -> async Result.Result<Blob, Text>,
  getPublicKeyFunc : () -> async Result.Result<Blob, Text>
) : async Result.Result<Text, Text>
```

---

### transferSuiSafe

Transfer with proper BCS transaction building.

```motoko
public func transferSuiSafe(
  rpcUrl : Text,
  senderAddress : Text,
  coinObjectId : Text,
  recipientAddress : Text,
  amount : Nat64,
  gasBudget : Nat64,
  signFunc : (Blob) -> async Result.Result<Blob, Text>,
  getPublicKeyFunc : () -> async Result.Result<Blob, Text>
) : async Result.Result<Text, Text>
```

---

### getTransactionStatus

Query transaction status from RPC.

```motoko
public func getTransactionStatus(
  rpcUrl : Text,
  digest : Text
) : async Result.Result<TransactionStatus, Text>
```

---

### getObjectInfo

Fetch object info (version, digest) from RPC.

```motoko
public func getObjectInfo(
  rpcUrl : Text,
  objectId : Text
) : async Result.Result<ObjectRef, Text>
```

---

### formatBalance

Format MIST amount to human-readable SUI string.

```motoko
public func formatBalance(mistAmount : Nat64) : Text
```

**Example:**
```motoko
formatBalance(1_500_000_000)  // Returns "1.5000 SUI"
formatBalance(500_000_000)    // Returns "0.5000 SUI"
```

---

### requestTestnetFaucet

Request tokens from testnet faucet.

```motoko
public func requestTestnetFaucet(
  address : Text
) : async Result.Result<Text, Text>
```

---

### Types

```motoko
public type ObjectRef = {
  objectId : Text;
  version : Nat;
  digest : Text;
};

public type TransactionStatus = {
  digest : Text;
  status : Text;
  error : ?Text;
  gasUsed : Nat64;
  timestamp : ?Text;
};
```

---

## Wallet Module

Located at `src/wallet.mo`. Wallet management using ICP threshold ECDSA.

### Factory Functions

```motoko
public func createDevnetWallet(keyName : Text) : SuiWallet
public func createTestnetWallet(keyName : Text) : SuiWallet
public func createMainnetWallet(keyName : Text) : SuiWallet
public func createCustomWallet(keyName : Text, network : Text, rpcUrl : Text) : SuiWallet
```

### SuiWallet Methods

```motoko
// Generate new address
generateAddress(derivationPath : ?Text) : async Result<AddressInfo, Text>

// Get balance for address
getBalance(address : Text) : async Result<Balance, Text>

// Sign a message hash
signMessage(messageHash : Blob) : async Result<Blob, Text>

// Get public key
getPublicKey() : async Result<Blob, Text>
```

### Types

```motoko
public type AddressInfo = {
  address : Text;
  publicKey : Blob;
  scheme : SignatureScheme;
  created : Int;
};

public type Balance = {
  total_balance : Nat64;
  object_count : Nat;
  objects : [SuiCoin];
};

public type SuiCoin = {
  coinObjectId : Text;
  balance : Nat64;
  version : Nat64;
  digest : Text;
};
```

---

## Address Module

Located at `src/address.mo`. Address utilities.

### publicKeyToAddress

Derive SUI address from public key.

```motoko
public func publicKeyToAddress(
  publicKey : [Nat8],
  scheme : SignatureScheme
) : Result.Result<Text, Text>
```

**Parameters:**
- `publicKey` - Public key bytes (32 for Ed25519, 33 for Secp256k1)
- `scheme` - `#ED25519` or `#Secp256k1`

---

### isValidAddress

Check if address format is valid.

```motoko
public func isValidAddress(address : Text) : Bool
```

---

### normalizeAddress

Normalize short address to full 64-character format.

```motoko
public func normalizeAddress(address : Text) : Result.Result<Text, Text>
```

**Example:**
```motoko
normalizeAddress("0x1")
// Returns: #ok("0x0000000000000000000000000000000000000000000000000000000000000001")
```

---

## Validation Module

Located at `src/validation.mo`. Validation utilities.

### isValidAddress

```motoko
public func isValidAddress(address : Text) : Bool
```

### isValidObjectId

```motoko
public func isValidObjectId(objectId : Text) : Bool
```

### normalizeAddress

```motoko
public func normalizeAddress(address : Text) : Result.Result<Text, Text>
```

### hexToBytes

```motoko
public func hexToBytes(hex : Text) : ?[Nat8]
```

---

## Types Module

Located at `src/types.mo`. Core type definitions.

### Addresses

```motoko
public type SuiAddress = Text;
public type ObjectID = Text;
public type TransactionDigest = Text;
```

### Signature Schemes

```motoko
public type SignatureScheme = {
  #ED25519;
  #Secp256k1;
  #Secp256r1;
  #MultiSig;
  #ZkLoginAuthenticator;
};
```

### Objects

```motoko
public type ObjectRef = {
  objectId : ObjectID;
  version : Nat64;
  digest : Text;
};

public type SuiCoin = {
  coinObjectId : Text;
  balance : Nat64;
  version : Nat64;
  digest : Text;
};
```

### Transactions

```motoko
public type TransactionData = {
  kind : TransactionKind;
  sender : SuiAddress;
  gasData : GasData;
  expiration : TransactionExpiration;
};

public type GasData = {
  payment : [ObjectRef];
  owner : SuiAddress;
  price : Nat64;
  budget : Nat64;
};

public type TransactionExpiration = {
  #None;
  #Epoch : Nat64;
};
```

### Commands

```motoko
public type Command = {
  #TransferObjects : { objects : [Argument]; address : Argument };
  #SplitCoins : { coin : Argument; amounts : [Argument] };
  #MergeCoins : { destination : Argument; sources : [Argument] };
  #MoveCall : {
    package : ObjectID;
    moduleName : Text;
    functionName : Text;
    typeArguments : [Text];
    arguments : [Argument];
  };
  #Publish : { modules : [Text]; dependencies : [ObjectID] };
  #MakeMoveVec : { type_ : ?Text; elements : [Argument] };
  #Upgrade : {
    modules : [Text];
    dependencies : [ObjectID];
    package : ObjectID;
    ticket : Argument;
  };
};

public type Argument = {
  #GasCoin;
  #Input : Nat16;
  #Result : Nat16;
  #NestedResult : (Nat16, Nat16);
};

public type CallArg = {
  #Pure : [Nat8];
  #Object : ObjectArg;
};
```

---

## Constants

### Network URLs

| Network | URL |
|---------|-----|
| Testnet | `https://fullnode.testnet.sui.io:443` |
| Mainnet | `https://fullnode.mainnet.sui.io:443` |
| Devnet | `https://fullnode.devnet.sui.io:443` |

### Conversions

| Unit | Value |
|------|-------|
| 1 SUI | 1,000,000,000 MIST |
| 1 MIST | 0.000000001 SUI |

---

*Last updated: 2025-01-16*
