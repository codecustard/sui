/// Utility functions for SUI blockchain operations.
///
/// This module provides common utility functions for string manipulation,
/// hashing, and hexadecimal encoding/decoding operations used throughout
/// the SUI library.

import Text "mo:base/Text";
import Iter "mo:base/Iter";
import Char "mo:base/Char";
import Hex "mo:hex";

module {
  /// Convert text to uppercase.
  ///
  /// Transforms all lowercase ASCII characters (a-z) to their uppercase
  /// equivalents (A-Z). Non-alphabetic characters remain unchanged.
  ///
  /// Example:
  /// ```motoko
  /// let result = Utils.toUpperCase("hello world");
  /// // result == "HELLO WORLD"
  /// ```
  ///
  /// @param text The input text to convert
  /// @return The text with all lowercase letters converted to uppercase
  public func toUpperCase(text : Text) : Text {
    let chars = text.chars();
    let upperChars = Iter.map(chars, func(c : Char) : Char {
      if (c >= 'a' and c <= 'z') {
        Char.fromNat32(Char.toNat32(c) - 32)
      } else {
        c
      }
    });
    Text.fromIter(upperChars)
  };

  /// Convert text to lowercase.
  ///
  /// Transforms all uppercase ASCII characters (A-Z) to their lowercase
  /// equivalents (a-z). Non-alphabetic characters remain unchanged.
  ///
  /// Example:
  /// ```motoko
  /// let result = Utils.toLowerCase("HELLO WORLD");
  /// // result == "hello world"
  /// ```
  ///
  /// @param text The input text to convert
  /// @return The text with all uppercase letters converted to lowercase
  public func toLowerCase(text : Text) : Text {
    let chars = text.chars();
    let lowerChars = Iter.map(chars, func(c : Char) : Char {
      if (c >= 'A' and c <= 'Z') {
        Char.fromNat32(Char.toNat32(c) + 32)
      } else {
        c
      }
    });
    Text.fromIter(lowerChars)
  };

  /// Check if text starts with a given prefix.
  ///
  /// Returns true if the input text begins with the specified prefix string.
  /// Empty prefix always returns true.
  ///
  /// Example:
  /// ```motoko
  /// let hasPrefix = Utils.startsWith("0x1234", "0x");
  /// // hasPrefix == true
  /// ```
  ///
  /// @param text The text to check
  /// @param prefix The prefix to look for
  /// @return True if text starts with prefix, false otherwise
  public func startsWith(text : Text, prefix : Text) : Bool {
    Text.startsWith(text, #text(prefix))
  };

  /// Simple hash function for text strings.
  ///
  /// Computes a 32-bit hash value for the input text using a polynomial
  /// rolling hash algorithm (similar to Java's String.hashCode()).
  ///
  /// Example:
  /// ```motoko
  /// let hash = Utils.hashText("hello");
  /// // Returns a 32-bit hash value
  /// ```
  ///
  /// @param text The text to hash
  /// @return A 32-bit hash value
  public func hashText(text : Text) : Nat32 {
    var hash : Nat32 = 0;
    for (char in text.chars()) {
      hash := hash * 31 + Char.toNat32(char);
    };
    hash
  };

  /// Convert byte array to hexadecimal string with "0x" prefix.
  ///
  /// Converts an array of bytes to a hexadecimal string representation
  /// with lowercase letters and "0x" prefix. Empty arrays return "0x".
  ///
  /// Example:
  /// ```motoko
  /// let bytes : [Nat8] = [0x12, 0x34, 0xab];
  /// let hex = Utils.bytesToHex(bytes);
  /// // hex == "0x1234ab"
  /// ```
  ///
  /// @param bytes The byte array to convert
  /// @return Hexadecimal string with "0x" prefix
  public func bytesToHex(bytes : [Nat8]) : Text {
    if (bytes.size() == 0) {
      "0x"  // Always return 0x for empty arrays
    } else {
      Hex.toTextFormat(bytes, Hex.COMPACT_PREFIX)
    }
  };

  /// Convert byte array to compact hexadecimal string without prefix.
  ///
  /// Converts an array of bytes to a hexadecimal string representation
  /// with lowercase letters and no prefix. Empty arrays return empty string.
  ///
  /// Example:
  /// ```motoko
  /// let bytes : [Nat8] = [0x12, 0x34, 0xab];
  /// let hex = Utils.bytesToHexCompact(bytes);
  /// // hex == "1234ab"
  /// ```
  ///
  /// @param bytes The byte array to convert
  /// @return Compact hexadecimal string without prefix
  public func bytesToHexCompact(bytes : [Nat8]) : Text {
    Hex.toTextFormat(bytes, Hex.COMPACT)
  };

  /// Convert byte array to uppercase hexadecimal string.
  ///
  /// Converts an array of bytes to a hexadecimal string representation
  /// with uppercase letters and no prefix.
  ///
  /// Example:
  /// ```motoko
  /// let bytes : [Nat8] = [0x12, 0x34, 0xab];
  /// let hex = Utils.bytesToHexUpper(bytes);
  /// // hex == "1234AB"
  /// ```
  ///
  /// @param bytes The byte array to convert
  /// @return Uppercase hexadecimal string without prefix
  public func bytesToHexUpper(bytes : [Nat8]) : Text {
    Hex.toTextFormat(bytes, Hex.COMPACT_UPPER)
  };

  /// Convert hexadecimal string to byte array.
  ///
  /// Parses a hexadecimal string (with or without "0x" prefix) and
  /// converts it to an array of bytes. Returns null if the input
  /// contains invalid hexadecimal characters.
  ///
  /// Example:
  /// ```motoko
  /// let bytes = Utils.hexToBytes("0x1234ab");
  /// // bytes == ?[0x12, 0x34, 0xab]
  ///
  /// let invalid = Utils.hexToBytes("xyz");
  /// // invalid == null
  /// ```
  ///
  /// @param hex The hexadecimal string to parse
  /// @return Optional byte array, null if parsing fails
  public func hexToBytes(hex : Text) : ?[Nat8] {
    switch (Hex.toArray(hex)) {
      case (#ok(bytes)) ?bytes;
      case (#err(_)) null;
    }
  };
}