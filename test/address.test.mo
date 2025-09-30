import Debug "mo:base/Debug";
import Address "../src/address";

/// Test SUI Address generation module.
///
/// This test focuses on address generation functions:
/// publicKeyToAddress, bytesToAddress, and signature scheme handling.

Debug.print("Testing SUI Address generation module...");

// Test public key to address conversion with proper 32-byte Ed25519 key
let samplePublicKey : [Nat8] = [
  0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
  0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x10,
  0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18,
  0x19, 0x1a, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f, 0x20
];
switch (Address.publicKeyToAddress(samplePublicKey, #ED25519)) {
  case (#ok(address)) {
    assert Address.isValidAddress(address);
  };
  case (#err(_)) {
    assert false; // Should not fail for valid 32-byte Ed25519 key
  };
};
Debug.print("✅ Public key to address conversion tests passed");

// Test different signature schemes
Debug.print("Testing signature schemes...");

// Test Secp256k1 (33 bytes)
let secp256k1Key : [Nat8] = [
  0x02, // Compressed key prefix
  0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
  0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x10,
  0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18,
  0x19, 0x1a, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f, 0x20
];

switch (Address.publicKeyToAddress(secp256k1Key, #Secp256k1)) {
  case (#ok(address)) {
    assert Address.isValidAddress(address);
    Debug.print("✅ Secp256k1 address generation: " # address);
  };
  case (#err(msg)) {
    Debug.print("❌ Secp256k1 failed: " # msg);
    assert false;
  };
};

// Test Secp256r1 (33 bytes)
switch (Address.publicKeyToAddress(secp256k1Key, #Secp256r1)) {
  case (#ok(address)) {
    assert Address.isValidAddress(address);
    Debug.print("✅ Secp256r1 address generation: " # address);
  };
  case (#err(msg)) {
    Debug.print("❌ Secp256r1 failed: " # msg);
    assert false;
  };
};

// Test Ed25519 address generation output
switch (Address.publicKeyToAddress(samplePublicKey, #ED25519)) {
  case (#ok(address)) {
    Debug.print("✅ Ed25519 address generation: " # address);
  };
  case (#err(msg)) {
    Debug.print("❌ Ed25519 failed: " # msg);
  };
};

// Test invalid key lengths
let shortKey : [Nat8] = [0x01, 0x02, 0x03]; // Too short
switch (Address.publicKeyToAddress(shortKey, #ED25519)) {
  case (#ok(_)) {
    Debug.print("❌ Should have rejected short key");
    assert false;
  };
  case (#err(msg)) {
    Debug.print("✅ Correctly rejected short key: " # msg);
  };
};

Debug.print("✅ All signature scheme tests passed");

// Test bytesToAddress function
Debug.print("Testing bytesToAddress function...");
let testBytes32 : [Nat8] = [
  0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
  0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x10,
  0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18,
  0x19, 0x1a, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f, 0x20
];

switch (Address.bytesToAddress(testBytes32)) {
  case (#ok(address)) {
    assert Address.isValidAddress(address);
    Debug.print("✅ bytesToAddress works: " # address);
  };
  case (#err(msg)) {
    Debug.print("❌ bytesToAddress failed: " # msg);
    assert false;
  };
};

// Test bytesToAddress with wrong length
let shortBytes : [Nat8] = [0x01, 0x02, 0x03];
switch (Address.bytesToAddress(shortBytes)) {
  case (#ok(_)) {
    Debug.print("❌ Should have rejected short byte array");
    assert false;
  };
  case (#err(msg)) {
    Debug.print("✅ Correctly rejected short bytes: " # msg);
  };
};

Debug.print("🎉 All address generation tests passed!");
Debug.print("");
Debug.print("✅ BLAKE2b-based publicKeyToAddress works for all signature schemes");
Debug.print("✅ Address generation enforces proper public key lengths");
Debug.print("✅ bytesToAddress converts 32-byte arrays to valid addresses");