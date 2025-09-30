import Debug "mo:base/Debug";
import Utils "../src/utils";

Debug.print("Testing SUI Utils module...");

// Test string case conversion
assert Utils.toUpperCase("hello") == "HELLO";
assert Utils.toUpperCase("Hello") == "HELLO";
assert Utils.toUpperCase("HELLO") == "HELLO";
assert Utils.toUpperCase("") == "";
assert Utils.toUpperCase("123abc") == "123ABC";
Debug.print("✅ toUpperCase tests passed");

assert Utils.toLowerCase("WORLD") == "world";
assert Utils.toLowerCase("World") == "world";
assert Utils.toLowerCase("world") == "world";
assert Utils.toLowerCase("") == "";
assert Utils.toLowerCase("123ABC") == "123abc";
Debug.print("✅ toLowerCase tests passed");

// Test string prefix checking
assert Utils.startsWith("hello world", "hello") == true;
assert Utils.startsWith("hello world", "world") == false;
assert Utils.startsWith("hello world", "") == true;
assert Utils.startsWith("", "hello") == false;
assert Utils.startsWith("test", "test") == true;
assert Utils.startsWith("test", "testing") == false;
Debug.print("✅ startsWith tests passed");

// Test text hashing
let hash1 = Utils.hashText("hello");
let hash2 = Utils.hashText("hello");
let hash3 = Utils.hashText("world");

assert hash1 == hash2; // Same input should give same hash
assert hash1 != hash3; // Different input should give different hash (usually)
assert Utils.hashText("") == 0; // Empty string should hash to 0
Debug.print("✅ hashText tests passed");

// Test bytes to hex conversion
let emptyBytes : [Nat8] = [];
assert Utils.bytesToHex(emptyBytes) == "0x";

let singleByte : [Nat8] = [0x00];
assert Utils.bytesToHex(singleByte) == "0x00";

let maxByte : [Nat8] = [0xff];
assert Utils.bytesToHex(maxByte) == "0xff";

let multiBytes : [Nat8] = [0x12, 0x34, 0xab, 0xcd];
assert Utils.bytesToHex(multiBytes) == "0x1234abcd";

let addressBytes : [Nat8] = [
  0x12, 0x34, 0x56, 0x78, 0x90, 0xab, 0xcd, 0xef,
  0x12, 0x34, 0x56, 0x78, 0x90, 0xab, 0xcd, 0xef,
  0x12, 0x34, 0x56, 0x78, 0x90, 0xab, 0xcd, 0xef,
  0x12, 0x34, 0x56, 0x78, 0x90, 0xab, 0xcd, 0xef
];
let hexResult = Utils.bytesToHex(addressBytes);
assert Utils.startsWith(hexResult, "0x");
assert hexResult.size() == 66; // 0x + 64 hex chars
Debug.print("✅ bytesToHex tests passed");

Debug.print("🎉 All utils tests passed!");