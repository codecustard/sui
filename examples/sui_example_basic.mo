/// SUI Proof of Concept Canister
///
/// This canister demonstrates basic SUI operations including:
/// - Generating SUI addresses from public keys
/// - Creating transfer transactions
/// - Managing basic SUI operations

import Result "mo:base/Result";
import Array "mo:base/Array";
import Principal "mo:base/Principal";
import Time "mo:base/Time";
import HashMap "mo:base/HashMap";
import Iter "mo:base/Iter";
import Debug "mo:base/Debug";
import Text "mo:base/Text";

// Import SUI library modules
import Types "../src/types";
import Address "../src/address";
import Transaction "../src/transaction";
import Wallet "../src/wallet";
import Validation "../src/validation";

persistent actor SuiPOC {
  // Type aliases for convenience
  public type SuiAddress = Types.SuiAddress;
  public type TransactionData = Types.TransactionData;
  public type KeyPair = Types.KeyPair;
  public type SignatureScheme = Types.SignatureScheme;

  // Simple wallet structure to store generated addresses
  public type Wallet = {
    address: SuiAddress;
    publicKey: [Nat8];
    scheme: SignatureScheme;
    created: Int;
  };

  // State variables
  private stable var walletEntries : [(Text, Wallet)] = [];
  private transient var wallets = HashMap.fromIter<Text, Wallet>(walletEntries.vals(), walletEntries.size(), Text.equal, Text.hash);

  // System upgrade functions
  system func preupgrade() {
    walletEntries := Iter.toArray(wallets.entries());
  };

  system func postupgrade() {
    walletEntries := [];
  };

  /// Generate a new SUI address using ICP threshold ECDSA
  ///
  /// @param derivation_path Optional derivation path for the key (e.g., "0", "1", "0/1/2")
  /// @return Result containing the generated SUI address and wallet info
  public func generateAddress(derivation_path: ?Text) : async Result.Result<Wallet, Text> {
    // Use dfx_test_key internally - hidden from user
    let sui_wallet = Wallet.createDevnetWallet("dfx_test_key");

    switch (await sui_wallet.generateAddress(derivation_path)) {
      case (#ok(addr_info)) {
        let wallet : Wallet = {
          address = addr_info.address;
          publicKey = addr_info.public_key;
          scheme = addr_info.scheme;
          created = Time.now();
        };

        // Store wallet for later reference
        wallets.put(addr_info.address, wallet);

        #ok(wallet)
      };
      case (#err(error)) {
        #err("Failed to generate address: " # error)
      };
    }
  };

  /// Validate a SUI address
  ///
  /// @param address The SUI address to validate
  /// @return True if the address is valid, false otherwise
  public func validateAddress(address: SuiAddress) : async Bool {
    Address.isValidAddress(address)
  };

  /// Create a simple SUI transfer transaction
  ///
  /// @param sender The sender's SUI address
  /// @param recipient The recipient's SUI address
  /// @param amount The amount to transfer (in SUI units)
  /// @return Result containing the transaction data or error message
  public func createTransferTransaction(
    sender: SuiAddress,
    recipient: SuiAddress,
    amount: Nat64
  ) : async Result.Result<TransactionData, Text> {
    // Validate addresses first
    if (not Address.isValidAddress(sender)) {
      return #err("Invalid sender address");
    };

    if (not Address.isValidAddress(recipient)) {
      return #err("Invalid recipient address");
    };

    // Create basic gas data (placeholder values for POC)
    let gasData : Types.GasData = {
      payment = [];
      owner = sender;
      price = 1000; // 1000 MIST per gas unit
      budget = 10000; // 10,000 MIST budget
    };

    // Create a simple transfer transaction
    // Note: In a real implementation, you would need actual coin objects to transfer
    let txData = Transaction.createTransferTransaction(sender, recipient, [], gasData);
    #ok(txData)
  };

  /// Get wallet information for a given address
  ///
  /// @param address The SUI address to look up
  /// @return Optional wallet information
  public query func getWallet(address: SuiAddress) : async ?Wallet {
    wallets.get(address)
  };

  /// List all generated wallets
  ///
  /// @return Array of all wallet information
  public query func listWallets() : async [Wallet] {
    Iter.toArray(wallets.vals())
  };

  /// Get basic canister information
  ///
  /// @return Canister info including version and capabilities
  public query func getInfo() : async {
    name: Text;
    version: Text;
    capabilities: [Text];
    walletCount: Nat;
  } {
    {
      name = "SUI POC Canister";
      version = "0.1.0";
      capabilities = [
        "Generate SUI addresses",
        "Validate SUI addresses",
        "Create transfer transactions",
        "Store wallet information"
      ];
      walletCount = wallets.size();
    }
  };

  /// Demo function that creates a wallet using ICP threshold ECDSA
  ///
  /// This function demonstrates address generation using ICP's threshold ECDSA API.
  /// Key management is handled internally for user convenience.
  ///
  /// @return Result containing demo wallet or error
  public func createDemoWallet() : async Result.Result<Wallet, Text> {
    // Generate address with derivation path 0
    await generateAddress(?"0")
  };

  /// Demo function that creates and validates a transfer transaction
  ///
  /// @return Result containing transaction demo info or error
  public func demoTransfer() : async Result.Result<{
    sender: SuiAddress;
    recipient: SuiAddress;
    transaction: TransactionData;
  }, Text> {
    // First create demo wallets using different derivation paths
    switch (await createDemoWallet()) {
      case (#ok(senderWallet)) {
        // Create another demo wallet with different derivation path
        switch (await generateAddress(?"1")) {
          case (#ok(recipientWallet)) {
            // Create transfer transaction
            switch (await createTransferTransaction(senderWallet.address, recipientWallet.address, 1000000)) {
              case (#ok(txData)) {
                #ok({
                  sender = senderWallet.address;
                  recipient = recipientWallet.address;
                  transaction = txData;
                })
              };
              case (#err(error)) { #err(error) };
            }
          };
          case (#err(error)) { #err("Failed to create recipient wallet: " # error) };
        }
      };
      case (#err(error)) { #err("Failed to create sender wallet: " # error) };
    }
  };

  /// Demo function that shows wallet functionality using ICP ECDSA
  ///
  /// @return Result containing comprehensive wallet demo or error
  public func demoWalletOperations() : async Result.Result<{
    wallet_info: Wallet;
    balance_info: Text;
    transaction_created: Bool;
  }, Text> {
    let sui_wallet = Wallet.createDevnetWallet("dfx_test_key");

    // Generate address
    switch (await sui_wallet.generateAddress(?"0")) {
      case (#ok(addr_info)) {
        let wallet_info : Wallet = {
          address = addr_info.address;
          publicKey = addr_info.public_key;
          scheme = addr_info.scheme;
          created = Time.now();
        };

        // Get balance (placeholder)
        switch (await sui_wallet.getBalance(addr_info.address)) {
          case (#ok(balance)) {
            // Build a transaction
            switch (await sui_wallet.buildTransaction(addr_info.address, addr_info.address, 1000000, ?10000000)) {
              case (#ok(_tx_data)) {
                #ok({
                  wallet_info = wallet_info;
                  balance_info = "Balance: " # debug_show(balance.total_balance) # " MIST";
                  transaction_created = true;
                })
              };
              case (#err(_error)) {
                #ok({
                  wallet_info = wallet_info;
                  balance_info = "Balance fetch succeeded";
                  transaction_created = false;
                })
              };
            }
          };
          case (#err(error)) {
            #ok({
              wallet_info = wallet_info;
              balance_info = "Balance fetch failed: " # error;
              transaction_created = false;
            })
          };
        }
      };
      case (#err(error)) { #err("Failed to generate address: " # error) };
    }
  };

  /// Send real SUI transaction to the network
  ///
  /// @param to_address Recipient SUI address
  /// @param amount Amount in MIST (1 SUI = 1,000,000,000 MIST)
  /// @return Result containing transaction result or error
  public func sendSUI(to_address: SuiAddress, amount: Nat64) : async Result.Result<{
    digest: Text;
    from_address: SuiAddress;
    to_address: SuiAddress;
    amount: Nat64;
  }, Text> {
    let sui_wallet = Wallet.createDevnetWallet("dfx_test_key");

    // Generate sender address
    switch (await sui_wallet.generateAddress(?"0")) {
      case (#ok(addr_info)) {
        let from_address = addr_info.address;

        // Send the transaction using direct unsafe_pay method
        switch (await sui_wallet.sendTransactionDirect(from_address, to_address, amount, ?20000000, ?"0")) {
          case (#ok(result)) {
            #ok({
              digest = result.transaction_digest;
              from_address = from_address;
              to_address = to_address;
              amount = amount;
            })
          };
          case (#err(error)) { #err(error) };
        };
      };
      case (#err(error)) { #err("Failed to generate sender address: " # error) };
    }
  };
}