import Debug "mo:base/Debug";
import Array "mo:base/Array";
import Nat8 "mo:base/Nat8";
import Lib "../src/lib";
import Types "../src/types";
import Address "../src/address";
import Transaction "../src/transaction";
import Utils "../src/utils";

// Test basic library functions
Debug.print("Testing basic library functions...");
assert Lib.add(1, 2) == 3;
assert Lib.add(3, 22) == 25;
Debug.print("✅ Basic math functions work");

// Test library metadata
assert Lib.version == "0.1.0";
assert Lib.description == "SUI blockchain library for Internet Computer";
Debug.print("✅ Library metadata correct");

// Test address validation
Debug.print("Testing address validation...");
let validAddress = "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";
let invalidAddress = "invalid_address";
let shortAddress = "0x123";

assert Address.isValidAddress(validAddress) == true;
assert Address.isValidAddress(invalidAddress) == false;
assert Address.isValidAddress(shortAddress) == false;
Debug.print("✅ Address validation works");

// Test address normalization
switch (Address.normalizeAddress(validAddress)) {
  case (#ok(normalized)) {
    assert normalized == validAddress;
    Debug.print("✅ Address normalization works");
  };
  case (#err(_)) {
    assert false; // Should not fail for valid address
  };
};

// Test address parsing
switch (Address.parseAddress(validAddress)) {
  case (#ok(parsed)) {
    assert parsed == validAddress;
    Debug.print("✅ Address parsing works");
  };
  case (#err(_)) {
    assert false; // Should not fail for valid address
  };
};

// Test object ID validation
assert Address.isValidObjectId(validAddress) == true;
Debug.print("✅ Object ID validation works");

// Test utility functions
Debug.print("Testing utility functions...");
assert Utils.toUpperCase("hello") == "HELLO";
assert Utils.toLowerCase("WORLD") == "world";
assert Utils.startsWith("hello world", "hello") == true;
assert Utils.startsWith("hello world", "world") == false;

let testBytes : [Nat8] = [0x12, 0x34, 0xab, 0xcd];
let hexResult = Utils.bytesToHex(testBytes);
assert Utils.startsWith(hexResult, "0x");
Debug.print("✅ Utility functions work");

// Test transaction creation
Debug.print("Testing transaction creation...");
let gasData : Types.GasData = {
  payment = [];
  owner = validAddress;
  price = 1000;
  budget = 10000;
};

let txData = Transaction.createTransferTransaction(
  validAddress,
  "0x0000000000000000000000000000000000000000000000000000000000000001",
  [],
  gasData
);

assert txData.version == 1;
assert txData.sender == validAddress;
assert txData.gasData.price == 1000;
Debug.print("✅ Transfer transaction creation works");

// Test move call transaction
let moveCallTx = Transaction.createMoveCallTransaction(
  validAddress,
  "0x0000000000000000000000000000000000000000000000000000000000000002",
  "coin",
  "transfer",
  ["0x2::sui::SUI"],
  [],
  gasData
);

assert moveCallTx.version == 1;
assert moveCallTx.sender == validAddress;
Debug.print("✅ Move call transaction creation works");

// Test transaction signing (placeholder)
// Use proper 32-byte keys for signing
let privateKey = Array.tabulate<Nat8>(32, func(i) { Nat8.fromNat(i) });
let publicKey = Array.tabulate<Nat8>(32, func(i) { Nat8.fromNat(i + 32) });

switch (Transaction.signTransaction(txData, privateKey, publicKey)) {
  case (#ok(signedTx)) {
    assert signedTx.data.sender == validAddress;
    assert signedTx.txSignatures.size() > 0;
    Debug.print("✅ Transaction signing works");

    // Test transaction verification with properly signed transaction
    assert Transaction.verifyTransaction(signedTx) == true;
    Debug.print("✅ Transaction verification works");
  };
  case (#err(msg)) {
    Debug.print("Signing error: " # msg);
    assert false; // Should not fail with valid keys
  };
};

Debug.print("🎉 All tests passed! SUI library is working correctly.");