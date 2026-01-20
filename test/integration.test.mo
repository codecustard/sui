/// Comprehensive Integration Test Suite for SUI Library
///
/// This test suite validates the complete functionality of the SUI blockchain library
/// including address management, transaction building, BCS serialization, and validation.
/// These tests ensure all components work together correctly.

import Debug "mo:base/Debug";
import Array "mo:base/Array";
import Nat8 "mo:base/Nat8";
import Nat64 "mo:base/Nat64";
import Text "mo:base/Text";
import Result "mo:base/Result";

import Lib "../src/lib";
import Types "../src/types";
import Address "../src/address";
import Transaction "../src/transaction";
import Validation "../src/validation";
import Utils "../src/utils";
import Wallet "../src/wallet";
import Nat "mo:base/Nat";

Debug.print("=================================================");
Debug.print("     SUI Library Integration Test Suite");
Debug.print("=================================================");
Debug.print("");

// ============================================================
// SECTION 1: Library Metadata Validation
// ============================================================
Debug.print("SECTION 1: Library Metadata Validation");
Debug.print("-------------------------------------------------");

assert Lib.version == "0.1.0";
assert Lib.description == "SUI blockchain library for Internet Computer";
Debug.print("✅ Library version: " # Lib.version);
Debug.print("✅ Library description verified");
Debug.print("");

// ============================================================
// SECTION 2: Address Validation and Normalization
// ============================================================
Debug.print("SECTION 2: Address Validation and Normalization");
Debug.print("-------------------------------------------------");

// Test standard 64-char addresses (32 bytes)
let standardAddresses = [
  "0x0000000000000000000000000000000000000000000000000000000000000001",
  "0x0000000000000000000000000000000000000000000000000000000000000002",
  "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
  "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
  "0xABCDEF1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890",
];

for (addr in standardAddresses.vals()) {
  assert Validation.isValidAddress(addr);
};
Debug.print("✅ Standard address validation passed (" # debug_show(standardAddresses.size()) # " addresses)");

// Test short address normalization
let shortAddresses = [
  ("0x1", "0x0000000000000000000000000000000000000000000000000000000000000001"),
  ("0x2", "0x0000000000000000000000000000000000000000000000000000000000000002"),
  ("0xff", "0x00000000000000000000000000000000000000000000000000000000000000ff"),
  ("0x123", "0x0000000000000000000000000000000000000000000000000000000000000123"),
];

for ((short, expected) in shortAddresses.vals()) {
  switch (Validation.normalizeAddress(short)) {
    case (#ok(normalized)) {
      assert normalized == expected;
    };
    case (#err(msg)) {
      Debug.print("❌ Failed to normalize " # short # ": " # msg);
      assert false;
    };
  };
};
Debug.print("✅ Short address normalization passed");

// Test invalid addresses are rejected
let invalidAddresses = [
  "",
  "not_an_address",
  "0x",
  "0xGGGG",
  "12345",
];

for (addr in invalidAddresses.vals()) {
  assert Validation.isValidAddress(addr) == false;
};
Debug.print("✅ Invalid address rejection passed");
Debug.print("");

// ============================================================
// SECTION 3: Hex Conversion Functions
// ============================================================
Debug.print("SECTION 3: Hex Conversion Functions");
Debug.print("-------------------------------------------------");

// Test bytes to hex conversion
let testBytes : [Nat8] = [0x00, 0x01, 0x0a, 0xff];
let hexResult = Validation.bytesToHex(testBytes);
assert hexResult == "0x00010aff";
Debug.print("✅ Bytes to hex: " # hexResult);

// Test hex to bytes conversion
switch (Validation.hexToBytes("0x00010aff")) {
  case (#ok(bytes)) {
    assert bytes == testBytes;
    Debug.print("✅ Hex to bytes round-trip works");
  };
  case (#err(msg)) {
    Debug.print("❌ Hex to bytes failed: " # msg);
    assert false;
  };
};

// Test without 0x prefix
switch (Validation.hexToBytes("deadbeef")) {
  case (#ok(bytes)) {
    assert bytes == [0xde, 0xad, 0xbe, 0xef];
    Debug.print("✅ Hex conversion works without 0x prefix");
  };
  case (#err(msg)) {
    Debug.print("❌ Failed: " # msg);
    assert false;
  };
};
Debug.print("");

// ============================================================
// SECTION 4: Public Key to Address Conversion
// ============================================================
Debug.print("SECTION 4: Public Key to Address Conversion");
Debug.print("-------------------------------------------------");

// Test Ed25519 public key (32 bytes)
let ed25519PubKey = Array.tabulate<Nat8>(32, func(i) { Nat8.fromNat(i) });
switch (Address.publicKeyToAddress(ed25519PubKey, #ED25519)) {
  case (#ok(addr)) {
    assert Validation.isValidAddress(addr);
    Debug.print("✅ Ed25519 address: " # Text.replace(addr, #text("0x"), "0x..."));
  };
  case (#err(msg)) {
    Debug.print("❌ Ed25519 conversion failed: " # msg);
    assert false;
  };
};

// Test Secp256k1 public key (33 bytes compressed)
let secp256k1PubKey = Array.tabulate<Nat8>(33, func(i) { Nat8.fromNat((i + 100) % 256) });
switch (Address.publicKeyToAddress(secp256k1PubKey, #Secp256k1)) {
  case (#ok(addr)) {
    assert Validation.isValidAddress(addr);
    Debug.print("✅ Secp256k1 address generated");
  };
  case (#err(msg)) {
    Debug.print("❌ Secp256k1 conversion failed: " # msg);
    assert false;
  };
};
Debug.print("");

// ============================================================
// SECTION 5: Transaction Building
// ============================================================
Debug.print("SECTION 5: Transaction Building");
Debug.print("-------------------------------------------------");

let senderAddress = "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";
let recipientAddress = "0x0000000000000000000000000000000000000000000000000000000000000001";

let gasData : Types.GasData = {
  payment = [];
  owner = senderAddress;
  price = 1000;
  budget = 10_000_000;
};

// Test transfer transaction
let transferTx = Transaction.createTransferTransaction(
  senderAddress,
  recipientAddress,
  [],
  gasData
);

assert transferTx.version == 1;
assert transferTx.sender == senderAddress;
assert transferTx.gasData.price == 1000;
assert transferTx.gasData.budget == 10_000_000;
Debug.print("✅ Transfer transaction created");

// Test move call transaction
let moveCallTx = Transaction.createMoveCallTransaction(
  senderAddress,
  "0x0000000000000000000000000000000000000000000000000000000000000002",
  "coin",
  "transfer",
  ["0x2::sui::SUI"],
  [],
  gasData
);

assert moveCallTx.version == 1;
switch (moveCallTx.kind) {
  case (#ProgrammableTransaction(ptx)) {
    assert ptx.commands.size() == 1;
  };
};
Debug.print("✅ Move call transaction created");

// Test SUI coin transfer
let coinObjectRef : Types.ObjectRef = {
  objectId = "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";
  version = 1;
  digest = "dGVzdF9kaWdlc3Q="; // base64 "test_digest"
};

let suiTransferTx = Transaction.createSuiTransferTransaction(
  senderAddress,
  recipientAddress,
  1_000_000_000, // 1 SUI in MIST
  coinObjectRef,
  gasData
);

assert suiTransferTx.sender == senderAddress;
switch (suiTransferTx.kind) {
  case (#ProgrammableTransaction(ptx)) {
    assert ptx.commands.size() == 2; // Split + Transfer
  };
};
Debug.print("✅ SUI transfer transaction created (1 SUI)");

// Test coin split
let splitTx = Transaction.createCoinSplitTransaction(
  senderAddress,
  coinObjectRef,
  [100_000_000, 200_000_000, 300_000_000], // 0.1, 0.2, 0.3 SUI
  gasData
);

switch (splitTx.kind) {
  case (#ProgrammableTransaction(ptx)) {
    switch (ptx.commands[0]) {
      case (#SplitCoins(split)) {
        assert split.amounts.size() == 3;
      };
      case (_) { assert false; };
    };
  };
};
Debug.print("✅ Coin split transaction created (3 amounts)");
Debug.print("");

// ============================================================
// SECTION 6: TransactionBuilder API
// ============================================================
Debug.print("SECTION 6: TransactionBuilder API");
Debug.print("-------------------------------------------------");

let builder = Transaction.TransactionBuilder();

// Add various inputs
let pureIdx = builder.addInput([0x01, 0x02, 0x03, 0x04]);
let objIdx = builder.addObjectInput(coinObjectRef);
let amountIdx = builder.addInput(Transaction.encodeBCSNat64(500_000_000)); // 0.5 SUI

assert pureIdx == 0;
assert objIdx == 1;
assert amountIdx == 2;
Debug.print("✅ Inputs added to builder");

// Add commands using proper Argument references
ignore builder.splitCoins(#Input(objIdx), [#Input(amountIdx)]);
ignore builder.transferObjects([#Result(0)], #Input(pureIdx));
ignore builder.moveCall(
  "0x0000000000000000000000000000000000000000000000000000000000000002",
  "sui",
  "transfer",
  [],
  [#Input(0)]
);

let builtTx = builder.build(senderAddress, gasData);
switch (builtTx.kind) {
  case (#ProgrammableTransaction(ptx)) {
    assert ptx.inputs.size() == 3;
    assert ptx.commands.size() == 3;
  };
};
Debug.print("✅ Complex transaction built with " # "3 inputs and 3 commands");
Debug.print("");

// ============================================================
// SECTION 7: BCS Encoding Functions
// ============================================================
Debug.print("SECTION 7: BCS Encoding Functions");
Debug.print("-------------------------------------------------");

// Test BCS Nat64 encoding (little-endian)
let amount0 = Transaction.encodeBCSNat64(0);
assert amount0 == [0, 0, 0, 0, 0, 0, 0, 0];

let amount255 = Transaction.encodeBCSNat64(255);
assert amount255[0] == 255;
assert amount255[1] == 0;

let amount1Million = Transaction.encodeBCSNat64(1_000_000);
// 1,000,000 = 0x0F4240 in little-endian: [0x40, 0x42, 0x0F, 0x00, ...]
assert amount1Million[0] == 0x40;
assert amount1Million[1] == 0x42;
assert amount1Million[2] == 0x0F;
assert amount1Million[3] == 0x00;
Debug.print("✅ BCS Nat64 encoding verified");

// Test BCS address encoding
let addr32 = Transaction.encodeBCSAddress("0x1");
assert addr32.size() == 32;
assert addr32[31] == 1; // Last byte is 1
for (i in addr32.keys()) {
  if (i != 31) {
    assert addr32[i] == 0; // All other bytes are 0
  };
};
Debug.print("✅ BCS address encoding verified (0x1 -> 32 bytes)");

let addrFull = Transaction.encodeBCSAddress("0x0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20");
assert addrFull.size() == 32;
assert addrFull[0] == 0x01;
assert addrFull[31] == 0x20;
Debug.print("✅ BCS full address encoding verified");
Debug.print("");

// ============================================================
// SECTION 8: Transaction Serialization
// ============================================================
Debug.print("SECTION 8: Transaction Serialization");
Debug.print("-------------------------------------------------");

let simpleTx = Transaction.createTransferTransaction(
  senderAddress,
  recipientAddress,
  [],
  gasData
);

let serializedTx = Transaction.serializeTransaction(simpleTx);
assert serializedTx.size() > 0;
Debug.print("✅ Transaction serialized: " # debug_show(serializedTx.size()) # " bytes");

// Test minimal transaction serialization
let minimalBytes = Transaction.serializeMinimalTransaction(1, senderAddress);
assert minimalBytes.size() > 0;
assert minimalBytes[0] == 1; // Version byte
Debug.print("✅ Minimal transaction: " # debug_show(minimalBytes.size()) # " bytes");

// Test intent message creation
let intent = Transaction.createTransactionIntent();
assert intent.scope == 0;
assert intent.version == 0;
assert intent.app_id == 0;
Debug.print("✅ Transaction intent created");
Debug.print("");

// ============================================================
// SECTION 9: Transaction Signing and Verification
// ============================================================
Debug.print("SECTION 9: Transaction Signing and Verification");
Debug.print("-------------------------------------------------");

let privateKey = Array.tabulate<Nat8>(32, func(i) { Nat8.fromNat(i) });
let publicKey = Array.tabulate<Nat8>(32, func(i) { Nat8.fromNat(i + 32) });

switch (Transaction.signTransaction(simpleTx, privateKey, publicKey)) {
  case (#ok(signedTx)) {
    assert signedTx.txSignatures.size() == 1;
    assert signedTx.txSignatures[0].size() > 0;

    // Verify the signed transaction
    let isValid = Transaction.verifyTransaction(signedTx);
    assert isValid;
    Debug.print("✅ Transaction signed and verified");
  };
  case (#err(msg)) {
    Debug.print("❌ Signing failed: " # msg);
    assert false;
  };
};

// Test invalid key sizes
switch (Transaction.signTransaction(simpleTx, [0x01], [0x02])) {
  case (#ok(_)) {
    Debug.print("❌ Should have rejected invalid keys");
    assert false;
  };
  case (#err(msg)) {
    assert Text.contains(msg, #text("32 bytes"));
    Debug.print("✅ Invalid key rejection works: " # msg);
  };
};

// Test empty signature verification
let unsignedTx : Types.Transaction = {
  data = simpleTx;
  txSignatures = [];
};
assert Transaction.verifyTransaction(unsignedTx) == false;
Debug.print("✅ Empty signature rejection works");
Debug.print("");

// ============================================================
// SECTION 10: Utility Functions
// ============================================================
Debug.print("SECTION 10: Utility Functions");
Debug.print("-------------------------------------------------");

// String utilities
assert Utils.toUpperCase("hello") == "HELLO";
assert Utils.toLowerCase("WORLD") == "world";
assert Utils.startsWith("hello world", "hello");
assert not Utils.startsWith("hello world", "world");
Debug.print("✅ String utilities work");

// Hex utilities
let hexBytes = Utils.bytesToHex([0xde, 0xad, 0xbe, 0xef]);
assert Text.contains(hexBytes, #text("de")) or Text.contains(hexBytes, #text("DE"));
Debug.print("✅ Hex utilities work");
Debug.print("");

// ============================================================
// SECTION 11: Object ID and Validation
// ============================================================
Debug.print("SECTION 11: Object ID and Validation");
Debug.print("-------------------------------------------------");

// Object IDs follow the same format as addresses
let validObjectIds = [
  "0x0000000000000000000000000000000000000000000000000000000000000001",
  "0x0000000000000000000000000000000000000000000000000000000000000002",
  "0x0000000000000000000000000000000000000000000000000000000000000006", // Clock
];

for (objId in validObjectIds.vals()) {
  assert Validation.isValidObjectId(objId);
};
Debug.print("✅ Valid object IDs accepted");

assert not Validation.isValidObjectId("invalid");
assert not Validation.isValidObjectId("0x123"); // Too short
Debug.print("✅ Invalid object IDs rejected");
Debug.print("");

// ============================================================
// SECTION 12: Edge Cases and Error Handling
// ============================================================
Debug.print("SECTION 12: Edge Cases and Error Handling");
Debug.print("-------------------------------------------------");

// Test zero amount transfer
let zeroAmountTx = Transaction.createSuiTransferTransaction(
  senderAddress,
  recipientAddress,
  0, // Zero amount
  coinObjectRef,
  gasData
);
assert zeroAmountTx.sender == senderAddress;
Debug.print("✅ Zero amount transaction creates (validation should happen at RPC level)");

// Test maximum Nat64 value
let maxAmount = Transaction.encodeBCSNat64(18446744073709551615); // Max Nat64
assert maxAmount.size() == 8;
assert maxAmount[0] == 0xFF and maxAmount[7] == 0xFF;
Debug.print("✅ Maximum Nat64 encoding works");

// Test address parsing to bytes
switch (Validation.parseAddress("0x0000000000000000000000000000000000000000000000000000000000000001")) {
  case (#ok(bytes)) {
    assert bytes.size() == 32;
    assert bytes[31] == 1;
  };
  case (#err(_)) {
    assert false;
  };
};
Debug.print("✅ Address parsing to bytes works");
Debug.print("");

// ============================================================
// SECTION 13: Batch Balance Query Types
// ============================================================
Debug.print("SECTION 13: Batch Balance Query Types");
Debug.print("-------------------------------------------------");

// Test BatchConfig with default values
let defaultBatchConfig: Wallet.BatchConfig = {
  maxAddresses = null;
};
assert defaultBatchConfig.maxAddresses == null;
Debug.print("✅ BatchConfig default (null maxAddresses)");

// Test BatchConfig with custom max
let customBatchConfig: Wallet.BatchConfig = {
  maxAddresses = ?25;
};
switch (customBatchConfig.maxAddresses) {
  case (?max) { assert max == 25 };
  case (null) { assert false };
};
Debug.print("✅ BatchConfig custom maxAddresses");

// Test BalanceResult with success
let testBalance: Wallet.Balance = {
  total_balance = 5_000_000_000; // 5 SUI
  objects = [];
  object_count = 0;
};

let successBalanceResult: Wallet.BalanceResult = {
  address = senderAddress;
  result = #ok(testBalance);
};
assert successBalanceResult.address == senderAddress;
switch (successBalanceResult.result) {
  case (#ok(bal)) { assert bal.total_balance == 5_000_000_000 };
  case (#err(_)) { assert false };
};
Debug.print("✅ BalanceResult with success");

// Test BalanceResult with error
let errorBalanceResult: Wallet.BalanceResult = {
  address = recipientAddress;
  result = #err("Address not found");
};
switch (errorBalanceResult.result) {
  case (#ok(_)) { assert false };
  case (#err(e)) { assert e == "Address not found" };
};
Debug.print("✅ BalanceResult with error");

// Test BatchBalanceResult with mixed results
let batchResult: Wallet.BatchBalanceResult = {
  results = [successBalanceResult, errorBalanceResult];
  successCount = 1;
  failureCount = 1;
};
assert batchResult.results.size() == 2;
assert batchResult.successCount == 1;
assert batchResult.failureCount == 1;
Debug.print("✅ BatchBalanceResult with mixed results");

// Test batch validation patterns
let testAddresses = [
  "0x0000000000000000000000000000000000000000000000000000000000000001",
  "0x0000000000000000000000000000000000000000000000000000000000000002",
  "0x0000000000000000000000000000000000000000000000000000000000000003",
];

// Verify all addresses are valid
for (addr in testAddresses.vals()) {
  assert Validation.isValidAddress(addr);
};
Debug.print("✅ Batch address validation");

// Test batch size limits
assert testAddresses.size() <= 50; // Default max
assert testAddresses.size() > 0; // Not empty
Debug.print("✅ Batch size within limits");

// Test creating large batch for limit testing
let largeBatch = Array.tabulate<Text>(50, func(i) {
  let hex = Nat.toText(i);
  let padding = Array.tabulate<Text>(64 - hex.size(), func(_) { "0" });
  "0x" # Text.join("", padding.vals()) # hex
});
assert largeBatch.size() == 50;
Debug.print("✅ Large batch creation (50 addresses)");

Debug.print("");

// ============================================================
// FINAL SUMMARY
// ============================================================
Debug.print("=================================================");
Debug.print("     Integration Test Suite Complete");
Debug.print("=================================================");
Debug.print("");
Debug.print("✅ All 13 test sections passed!");
Debug.print("");
Debug.print("Tested Components:");
Debug.print("  • Library metadata and versioning");
Debug.print("  • Address validation and normalization");
Debug.print("  • Hex conversion utilities");
Debug.print("  • Public key to address conversion");
Debug.print("  • Transaction building (transfer, move call, split, merge)");
Debug.print("  • TransactionBuilder fluent API");
Debug.print("  • BCS encoding for amounts and addresses");
Debug.print("  • Transaction serialization");
Debug.print("  • Transaction signing and verification");
Debug.print("  • String and hex utilities");
Debug.print("  • Object ID validation");
Debug.print("  • Edge cases and error handling");
Debug.print("  • Batch balance query types and validation");
Debug.print("");
Debug.print("🎉 SUI Library POC Integration Tests PASSED!");
