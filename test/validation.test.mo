import Debug "mo:base/Debug";
import Validation "../src/validation";

/// Test SUI validation module functions.
///
/// This test focuses specifically on validation functions:
/// address validation, normalization, parsing, and hex conversion.

Debug.print("Testing SUI Validation module...");

// Test valid SUI addresses
let validAddresses = [
  "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
  "0x0000000000000000000000000000000000000000000000000000000000000000",
  "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
  "0x0000000000000000000000000000000000000000000000000000000000000001", // SUI system
  "0x02a212de6a9dfa3a69e22387acfbafbb1a9e591bd9d636e7895dcfc8de05f331", // Real SUI address
];

Debug.print("Testing valid address validation...");
for (addr in validAddresses.vals()) {
  assert Validation.isValidAddress(addr) == true;
  Debug.print("✅ Valid: " # addr);
};

// Test invalid SUI addresses
let invalidAddresses = [
  "invalid_address", // Not hex
  "0x123", // Too short
  "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef12", // Missing 0x
  "0xGGGG567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef12", // Invalid hex
  "", // Empty
  "0x", // Only prefix
  "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234", // Too long (33 bytes)
  "123456789", // No 0x prefix
];

Debug.print("Testing invalid address validation...");
for (addr in invalidAddresses.vals()) {
  assert Validation.isValidAddress(addr) == false;
  Debug.print("✅ Correctly rejected: " # addr);
};

// Test address normalization - valid addresses should stay the same
Debug.print("Testing address normalization...");
let testAddr = "0x0000000000000000000000000000000000000000000000000000000000000001";
switch (Validation.normalizeAddress(testAddr)) {
  case (#ok(normalized)) {
    assert normalized == testAddr;
    Debug.print("✅ Valid address normalization preserves format: " # normalized);
  };
  case (#err(msg)) {
    Debug.print("❌ Normalization failed: " # msg);
    assert false;
  };
};

// Test normalization with short address (should pad with zeros)
switch (Validation.normalizeAddress("0x1")) {
  case (#ok(normalized)) {
    assert normalized == "0x0000000000000000000000000000000000000000000000000000000000000001";
    Debug.print("✅ Short address padded correctly: " # normalized);
  };
  case (#err(msg)) {
    Debug.print("❌ Short address normalization failed: " # msg);
    assert false;
  };
};

// Test normalization failure cases
switch (Validation.normalizeAddress("invalid")) {
  case (#ok(_)) {
    Debug.print("❌ Should have failed invalid address normalization");
    assert false;
  };
  case (#err(msg)) {
    Debug.print("✅ Correctly rejected invalid address: " # msg);
  };
};

// Test hex conversion functions
Debug.print("Testing hex conversion...");
let testBytes : [Nat8] = [0x12, 0x34, 0x56, 0x78];
let hexResult = Validation.bytesToHex(testBytes);
assert hexResult == "0x12345678";
Debug.print("✅ Bytes to hex: " # hexResult);

switch (Validation.hexToBytes("0x12345678")) {
  case (#ok(bytes)) {
    assert bytes == [0x12, 0x34, 0x56, 0x78];
    Debug.print("✅ Hex to bytes round-trip works");
  };
  case (#err(msg)) {
    Debug.print("❌ Hex conversion failed: " # msg);
    assert false;
  };
};

// Test hex conversion without 0x prefix
switch (Validation.hexToBytes("12345678")) {
  case (#ok(bytes)) {
    assert bytes == [0x12, 0x34, 0x56, 0x78];
    Debug.print("✅ Hex conversion works without 0x prefix");
  };
  case (#err(msg)) {
    Debug.print("❌ Hex conversion without prefix failed: " # msg);
    assert false;
  };
};

// Test address parsing
Debug.print("Testing address parsing...");
switch (Validation.parseAddress("0x0000000000000000000000000000000000000000000000000000000000000001")) {
  case (#ok(bytes)) {
    assert bytes.size() == 32;
    assert bytes[31] == 1; // Last byte should be 1
    Debug.print("✅ Address parsing works - got " # debug_show(bytes.size()) # " bytes");
  };
  case (#err(msg)) {
    Debug.print("❌ Address parsing failed: " # msg);
    assert false;
  };
};

// Test parsing invalid address
switch (Validation.parseAddress("0x123")) {
  case (#ok(_)) {
    Debug.print("❌ Should have failed parsing short address");
    assert false;
  };
  case (#err(msg)) {
    Debug.print("✅ Correctly rejected short address: " # msg);
  };
};

// Test object ID validation
Debug.print("Testing object ID validation...");
assert Validation.isValidObjectId(validAddresses[0]) == true;
assert Validation.isValidObjectId("invalid") == false;
assert Validation.isValidObjectId("0x123") == false; // Too short
Debug.print("✅ Object ID validation works");

// Test against real SUI blockchain addresses
Debug.print("Testing against real SUI addresses...");
let realSuiAddresses = [
  // SUI system addresses (these are the actual 32-byte system addresses)
  "0x0000000000000000000000000000000000000000000000000000000000000001", // SUI system
  "0x0000000000000000000000000000000000000000000000000000000000000002", // SUI framework
  "0x0000000000000000000000000000000000000000000000000000000000000003", // SUI display
  "0x0000000000000000000000000000000000000000000000000000000000000006", // Clock object
  "0x1a2b3c4d5e6f7890abcdef1234567890abcdef1234567890abcdef1234567890",
  "0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890",
  "0x02a212de6a9dfa3a69e22387acfbafbb1a9e591bd9d636e7895dcfc8de05f331", // From SUI docs
];

for (addr in realSuiAddresses.vals()) {
  assert Validation.isValidAddress(addr) == true;
  Debug.print("✅ Real SUI address valid: " # addr);
};

Debug.print("🎉 All validation tests passed!");
Debug.print("");
Debug.print("✅ Address format validation enforces 32-byte requirement");
Debug.print("✅ Address normalization handles padding correctly");
Debug.print("✅ Hex conversion works with and without 0x prefix");
Debug.print("✅ Address parsing converts to correct byte arrays");
Debug.print("✅ Object ID validation uses same rules as addresses");
Debug.print("✅ Real SUI blockchain addresses validate correctly");