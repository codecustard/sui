/// Main SUI library module.
///
/// This is the main entry point for the SUI blockchain library for Internet Computer.
/// It provides basic library metadata and utility functions for testing and validation.
///
/// For specific functionality, import the individual modules:
/// - `Types` - Core SUI blockchain type definitions
/// - `Address` - SUI address validation and conversion utilities
/// - `Transaction` - Transaction building and signing functions
/// - `Utils` - General utility functions for hex encoding, hashing, etc.

module {
  /// Current version of the SUI library.
  ///
  /// Follows semantic versioning (semver) format: MAJOR.MINOR.PATCH
  public let version = "0.1.0";

  /// Human-readable description of the SUI library.
  ///
  /// Describes the purpose and target platform of this library.
  public let description = "SUI blockchain library for Internet Computer";

  /// Simple addition function for testing library integration.
  ///
  /// This function is primarily used for testing that the library
  /// can be imported and basic functions can be called successfully.
  ///
  /// Example:
  /// ```motoko
  /// import Lib "mo:sui/lib";
  ///
  /// let result = Lib.add(5, 3);
  /// // result == 8
  /// ```
  ///
  /// @param x First number to add
  /// @param y Second number to add
  /// @return Sum of x and y
  public func add(x : Nat, y : Nat) : Nat {
    x + y
  };
}