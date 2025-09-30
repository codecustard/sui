import Result "mo:base/Result";
import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Nat "mo:base/Nat";
import Hex "mo:hex";
import Blake2b "mo:blake2b";
import Types "types";
import Validation "validation";

module {
  public type SuiAddress = Types.SuiAddress;
  public type SignatureScheme = Types.SignatureScheme;

  private let SUI_ADDRESS_LENGTH : Nat = 32; // 32 bytes = 256 bits

  // Re-export validation functions for compatibility
  public let isValidAddress = Validation.isValidAddress;
  public let normalizeAddress = Validation.normalizeAddress;
  public let isValidObjectId = Validation.isValidObjectId;
  public let parseAddress = Validation.parseAddress;
  public let hexToBytes = Validation.hexToBytes;
  public let bytesToHex = Validation.bytesToHex;

  /// Convert bytes to SUI address format.
  ///
  /// Takes a 32-byte array and converts it to a SUI address string.
  ///
  /// @param bytes The 32-byte array to convert
  /// @return Result containing SUI address or error message
  public func bytesToAddress(bytes : [Nat8]) : Result.Result<SuiAddress, Text> {
    if (bytes.size() != SUI_ADDRESS_LENGTH) {
      #err("Invalid byte array length for SUI address")
    } else {
      #ok(Hex.toTextFormat(bytes, Hex.COMPACT_PREFIX))
    }
  };

  /// Generate SUI address from public key using BLAKE2b-256.
  ///
  /// This implements the official SUI address derivation algorithm:
  /// 1. Prepend signature scheme flag (1 byte) to public key
  /// 2. Hash the combined data using BLAKE2b-256
  /// 3. Use the hash as the 32-byte SUI address
  ///
  /// Signature scheme flags:
  /// - Ed25519: 0x00
  /// - Secp256k1: 0x01
  /// - Secp256r1: 0x02
  /// - MultiSig: 0x03
  ///
  /// @param publicKey The public key bytes (32 bytes for Ed25519, 33 for compressed secp256k1/r1)
  /// @param scheme The signature scheme used
  /// @return Result containing the derived SUI address or error message
  public func publicKeyToAddress(publicKey : [Nat8], scheme : SignatureScheme) : Result.Result<SuiAddress, Text> {
    // Get the signature scheme flag
    let schemeFlag : Nat8 = switch (scheme) {
      case (#ED25519) 0x00;
      case (#Secp256k1) 0x01;
      case (#Secp256r1) 0x02;
    };

    // Validate public key length based on scheme
    let expectedLength = switch (scheme) {
      case (#ED25519) 32;  // Ed25519 public keys are 32 bytes
      case (#Secp256k1) 33; // Compressed secp256k1 public keys are 33 bytes
      case (#Secp256r1) 33; // Compressed secp256r1 public keys are 33 bytes
    };

    if (publicKey.size() != expectedLength) {
      return #err("Invalid public key length for signature scheme. Expected " #
                  Nat.toText(expectedLength) # " bytes, got " # Nat.toText(publicKey.size()));
    };

    // Combine scheme flag with public key
    let flaggedKey = Array.tabulate<Nat8>(publicKey.size() + 1, func(i) {
      if (i == 0) { schemeFlag } else { publicKey[i - 1] }
    });

    // Hash using BLAKE2b-256 (32-byte output)
    let inputBlob = Blob.fromArray(flaggedKey);
    let config = {
      digest_length = SUI_ADDRESS_LENGTH; // 32 bytes
      key = null;
      salt = null;
      personal = null;
    };

    let hashBlob = Blake2b.hash(inputBlob, ?config);
    let hashBytes = Blob.toArray(hashBlob);

    // Convert to SUI address format
    bytesToAddress(hashBytes)
  };
}