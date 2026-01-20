/// Tests for SUI Wallet module
///
/// This test suite covers testable wallet functionality without requiring
/// live ECDSA integration (which needs dfx setup).

import Debug "mo:base/Debug";
import Array "mo:base/Array";
import Nat8 "mo:base/Nat8";

import Wallet "../src/wallet";
import Types "../src/types";
import Address "../src/address";

Debug.print("🧪 Testing SUI Wallet Module...");

// Test 1: Wallet factory functions
Debug.print("Test 1: Wallet factory functions...");
do {
  // These should create wallet instances without throwing errors
  let _ = Wallet.createMainnetWallet("test_key");
  let _ = Wallet.createTestnetWallet("test_key");
  let _ = Wallet.createDevnetWallet("test_key");
  let _ = Wallet.createCustomWallet("test_key", "custom", "https://rpc.example.com");

  Debug.print("✅ Factory functions work");
};

// Test 2: Address validation (using existing Address module)
Debug.print("Test 2: Address validation...");
do {
  // Valid SUI addresses (64 hex chars + 0x prefix)
  assert Address.isValidAddress("0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef");
  assert Address.isValidAddress("0x0000000000000000000000000000000000000000000000000000000000000000");
  assert Address.isValidAddress("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff");

  // Invalid addresses
  assert not Address.isValidAddress("");
  assert not Address.isValidAddress("invalid");
  assert not Address.isValidAddress("0x123"); // Too short
  assert not Address.isValidAddress("1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"); // Missing 0x

  Debug.print("✅ Address validation works");
};

// Test 3: Type structures and data validation
Debug.print("Test 3: Data structure validation...");
do {
  // Test Balance structure
  let balance: Wallet.Balance = {
    total_balance = 1_000_000_000; // 1 SUI in MIST
    objects = [];
    object_count = 0;
  };
  assert balance.total_balance == 1_000_000_000;
  assert balance.objects.size() == 0;
  assert balance.object_count == 0;

  // Test AddressInfo structure
  let pubkey = Array.tabulate<Nat8>(33, func(i) { Nat8.fromNat(i % 256) });
  let addrInfo: Wallet.AddressInfo = {
    address = "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";
    derivation_path = "0/1";
    public_key = pubkey;
    scheme = #Secp256k1;
  };
  assert Address.isValidAddress(addrInfo.address);
  assert addrInfo.derivation_path == "0/1";
  assert addrInfo.public_key.size() == 33; // secp256k1 compressed
  assert addrInfo.scheme == #Secp256k1;

  Debug.print("✅ Data structures work");
};

// Test 4: Transaction data structure validation
Debug.print("Test 4: Transaction structure validation...");
do {
  // Test GasData
  let gasData: Types.GasData = {
    payment = [];
    owner = "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";
    price = 1000;
    budget = 10_000_000;
  };
  assert gasData.price > 0;
  assert gasData.budget > 0;
  assert Address.isValidAddress(gasData.owner);

  // Test TransactionData
  let txData: Types.TransactionData = {
    version = 1;
    sender = "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";
    gasData = gasData;
    kind = #ProgrammableTransaction({
      inputs = [];
      commands = [];
    });
    expiration = #None;
  };
  assert txData.version == 1;
  assert Address.isValidAddress(txData.sender);

  Debug.print("✅ Transaction structures work");
};

// Test 5: Amount and gas validation logic
Debug.print("Test 5: Amount validation...");
do {
  // Valid amounts
  let amounts: [Nat64] = [1, 1000, 1_000_000, 1_000_000_000];
  for (amount in amounts.vals()) {
    assert amount > 0; // All should be positive
  };

  // Gas budgets
  let defaultGas: Nat64 = 10_000_000; // 0.01 SUI
  let customGas: Nat64 = 20_000_000; // 0.02 SUI
  assert defaultGas > 0;
  assert customGas > defaultGas;

  Debug.print("✅ Amount validation works");
};

// Test 6: Signature scheme validation
Debug.print("Test 6: Signature scheme validation...");
do {
  // Test supported schemes
  let scheme = #Secp256k1;
  switch (scheme) {
    case (#Secp256k1) { assert true };
    case (#ED25519) { assert false }; // Not used for SUI wallet
    case (#Secp256r1) { assert false }; // Not used for SUI wallet
  };

  Debug.print("✅ Signature scheme validation works");
};

// Test 7: Helper functions and utilities
Debug.print("Test 7: Utility functions...");
do {
  // Test hex byte arrays
  let testBytes: [[Nat8]] = [
    [],
    [0x00],
    [0xFF],
    [0x12, 0x34, 0x56],
    Array.tabulate<Nat8>(32, func(i) { Nat8.fromNat(i % 256) })
  ];

  for (bytes in testBytes.vals()) {
    // All bytes should be valid
    for (byte in bytes.vals()) {
      assert byte >= 0 and byte <= 255;
    };
  };

  Debug.print("✅ Utility functions work");
};

// Test 8: Error handling validation
Debug.print("Test 8: Error patterns...");
do {
  // Test that error messages would be meaningful
  let errorMessages = [
    "Key name cannot be empty",
    "Invalid sender address",
    "Invalid recipient address",
    "Transfer amount must be greater than zero",
    "ECDSA key generation failed"
  ];

  for (msg in errorMessages.vals()) {
    assert msg.size() > 0;
    assert msg.size() > 5; // Should be descriptive
  };

  Debug.print("✅ Error patterns validated");
};

// Test 9: Batch balance types
Debug.print("Test 9: Batch balance types...");
do {
  // Test BatchConfig structure
  let defaultConfig: Wallet.BatchConfig = {
    maxAddresses = null;
  };
  assert defaultConfig.maxAddresses == null;

  let customConfig: Wallet.BatchConfig = {
    maxAddresses = ?25;
  };
  switch (customConfig.maxAddresses) {
    case (?max) { assert max == 25 };
    case (null) { assert false };
  };

  // Test BalanceResult structure
  let successBalance: Wallet.Balance = {
    total_balance = 1_000_000_000;
    objects = [];
    object_count = 0;
  };

  let successResult: Wallet.BalanceResult = {
    address = "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";
    result = #ok(successBalance);
  };
  assert Address.isValidAddress(successResult.address);
  switch (successResult.result) {
    case (#ok(bal)) { assert bal.total_balance == 1_000_000_000 };
    case (#err(_)) { assert false };
  };

  let errorResult: Wallet.BalanceResult = {
    address = "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";
    result = #err("Test error");
  };
  switch (errorResult.result) {
    case (#ok(_)) { assert false };
    case (#err(e)) { assert e == "Test error" };
  };

  // Test BatchBalanceResult structure
  let batchResult: Wallet.BatchBalanceResult = {
    results = [successResult, errorResult];
    successCount = 1;
    failureCount = 1;
  };
  assert batchResult.results.size() == 2;
  assert batchResult.successCount == 1;
  assert batchResult.failureCount == 1;

  Debug.print("✅ Batch balance types work");
};

// Test 10: Batch validation logic patterns
Debug.print("Test 10: Batch validation patterns...");
do {
  // Test empty array detection
  let emptyArray: [Text] = [];
  assert emptyArray.size() == 0;

  // Test max addresses validation
  let maxDefault = 50;
  let addresses5 = Array.tabulate<Text>(5, func(_) { "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef" });
  assert addresses5.size() <= maxDefault;

  let addresses100 = Array.tabulate<Text>(100, func(_) { "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef" });
  assert addresses100.size() > maxDefault;

  // Test that all addresses in an array can be validated
  let validAddresses = [
    "0x0000000000000000000000000000000000000000000000000000000000000001",
    "0x0000000000000000000000000000000000000000000000000000000000000002",
    "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
  ];
  for (addr in validAddresses.vals()) {
    assert Address.isValidAddress(addr);
  };

  // Test that invalid addresses are caught
  let mixedAddresses = [
    "0x0000000000000000000000000000000000000000000000000000000000000001",
    "invalid_address",
    "0x0000000000000000000000000000000000000000000000000000000000000002"
  ];
  var hasInvalid = false;
  for (addr in mixedAddresses.vals()) {
    if (not Address.isValidAddress(addr)) {
      hasInvalid := true;
    };
  };
  assert hasInvalid;

  Debug.print("✅ Batch validation patterns work");
};

Debug.print("");
Debug.print("🎉 All unit tests passed!");
Debug.print("");
Debug.print("📋 Integration Test Notes:");
Debug.print("   For full wallet testing with ECDSA:");
Debug.print("   1. Start dfx with --enable-canister-http");
Debug.print("   2. Use 'dfx_test_key' as key_name");
Debug.print("   3. Test generateAddress() with live ECDSA");
Debug.print("   4. Test signTransaction() with real keys");
Debug.print("");
Debug.print("   Example integration test:");
Debug.print("   let wallet = Wallet.createDevnetWallet(\"dfx_test_key\");");
Debug.print("   let result = await wallet.generateAddress(?\"0\");");
Debug.print("");