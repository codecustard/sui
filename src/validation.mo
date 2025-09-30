/// SUI address and data validation module.
///
/// This module provides validation functions for SUI blockchain data structures,
/// including addresses, object IDs, and other format validations.
///

import Text "mo:base/Text";
import Result "mo:base/Result";
import Array "mo:base/Array";
import Hex "mo:hex";
import Types "types";

module {
  public type SuiAddress = Types.SuiAddress;

  private let SUI_ADDRESS_LENGTH : Nat = 32; // 32 bytes = 256 bits
  private let HEX_PREFIX = "0x";

  /// Validate SUI address format.
  ///
  /// Checks that the address:
  /// - Starts with "0x" prefix
  /// - Contains valid hexadecimal characters
  /// - Is exactly 32 bytes (64 hex characters) long
  ///
  /// @param address The address string to validate
  /// @return True if the address is valid SUI format, false otherwise
  public func isValidAddress(address : Text) : Bool {
    if (not Text.startsWith(address, #text(HEX_PREFIX))) {
      return false;
    };

    // Remove 0x prefix for hex library
    let hexPart = switch (Text.stripStart(address, #text(HEX_PREFIX))) {
      case (?hex) hex;
      case null return false;
    };

    switch (Hex.toArray(hexPart)) {
      case (#ok(bytes)) {
        bytes.size() == SUI_ADDRESS_LENGTH
      };
      case (#err(_)) {
        false
      };
    }
  };

  /// Normalize SUI address format.
  ///
  /// Ensures the address has proper 0x prefix and is padded to full 32 bytes.
  /// Short addresses are left-padded with zeros.
  ///
  /// @param address The address to normalize
  /// @return Result containing normalized address or error message
  public func normalizeAddress(address : Text) : Result.Result<SuiAddress, Text> {
    // Remove 0x prefix if present
    let hexPart = if (Text.startsWith(address, #text(HEX_PREFIX))) {
      switch (Text.stripStart(address, #text(HEX_PREFIX))) {
        case (?hex) hex;
        case null return #err("Invalid hex format");
      }
    } else {
      address
    };

    switch (Hex.toArray(hexPart)) {
      case (#ok(bytes)) {
        if (bytes.size() <= SUI_ADDRESS_LENGTH) {
          // Pad with leading zeros if necessary
          let paddedBytes = if (bytes.size() == SUI_ADDRESS_LENGTH) {
            bytes
          } else {
            let padding = SUI_ADDRESS_LENGTH - bytes.size();
            Array.tabulate<Nat8>(SUI_ADDRESS_LENGTH, func(i) {
              if (i < padding) {
                0
              } else {
                bytes[i - padding]
              }
            })
          };

          #ok(Hex.toTextFormat(paddedBytes, Hex.COMPACT_PREFIX))
        } else {
          #err("Address too long")
        }
      };
      case (#err(msg)) {
        #err("Invalid hex format: " # msg)
      };
    }
  };

  /// Validate SUI object ID format.
  ///
  /// Object IDs in SUI use the same format as addresses (32-byte hex strings).
  ///
  /// @param objectId The object ID to validate
  /// @return True if valid object ID format, false otherwise
  public func isValidObjectId(objectId : Text) : Bool {
    isValidAddress(objectId) // Same format as addresses
  };

  /// Parse and validate SUI address, returning bytes.
  ///
  /// Validates the address format and converts it to byte array.
  ///
  /// @param address The address string to parse
  /// @return Result containing byte array or error message
  public func parseAddress(address : Text) : Result.Result<[Nat8], Text> {
    if (not isValidAddress(address)) {
      return #err("Invalid SUI address format");
    };

    hexToBytes(address)
  };

  /// Convert hex string to byte array.
  ///
  /// Handles both prefixed (0x) and non-prefixed hex strings.
  ///
  /// @param hex The hex string to convert
  /// @return Result containing byte array or error message
  public func hexToBytes(hex : Text) : Result.Result<[Nat8], Text> {
    // Remove 0x prefix if present
    let hexPart = if (Text.startsWith(hex, #text(HEX_PREFIX))) {
      switch (Text.stripStart(hex, #text(HEX_PREFIX))) {
        case (?h) h;
        case null return #err("Invalid hex format");
      }
    } else {
      hex
    };

    Hex.toArray(hexPart)
  };

  /// Convert byte array to hex string.
  ///
  /// Always includes 0x prefix in the output.
  ///
  /// @param bytes The byte array to convert
  /// @return Hex string with 0x prefix
  public func bytesToHex(bytes : [Nat8]) : Text {
    Hex.toTextFormat(bytes, Hex.COMPACT_PREFIX)
  };
}