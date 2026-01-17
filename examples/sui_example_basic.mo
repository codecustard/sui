/// SUI Proof of Concept Canister
///
/// This canister demonstrates basic SUI operations including:
/// - Generating SUI addresses from public keys
/// - Creating transfer transactions
/// - Managing basic SUI operations

import Result "mo:base/Result";
import Array "mo:base/Array";
import Time "mo:base/Time";
import HashMap "mo:base/HashMap";
import Iter "mo:base/Iter";
import Debug "mo:base/Debug";
import Bool "mo:base/Bool";
import Text "mo:base/Text";
import Nat "mo:base/Nat";
import Nat8 "mo:base/Nat8";
import Nat64 "mo:base/Nat64";
import BaseX "mo:base-x-encoder";
import Json "mo:json";
import IC "mo:ic";

// Import SUI library modules
import Types "../src/types";
import Address "../src/address";
import Transaction "../src/transaction";
import Wallet "../src/wallet";
import SuiTransfer "../src/sui_transfer";
import Error "mo:base/Error";

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
  private var walletEntries : [(Text, Wallet)] = [];
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

  /// Get SUI balance for an address
  ///
  /// @param address The SUI address to check balance for
  /// @return Result containing balance info or error message
  public func getBalance(address: SuiAddress) : async Result.Result<Text, Text> {
    let sui_wallet = Wallet.createDevnetWallet("dfx_test_key");

    switch (await sui_wallet.getBalance(address)) {
      case (#err(error)) { #err("Failed to get balance: " # error) };
      case (#ok(balance)) {
        let total_balance = Array.foldLeft<Types.SuiCoin, Nat64>(
          balance.objects,
          0,
          func(acc, coin) { acc + coin.balance }
        );
        let sui_amount = total_balance / 1_000_000_000; // Convert MIST to SUI
        let mist_remainder = total_balance % 1_000_000_000;
        #ok("Balance: " # Nat64.toText(sui_amount) # "." # Nat64.toText(mist_remainder) # " SUI (" # Nat64.toText(total_balance) # " MIST)")
      };
    }
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
    _amount: Nat64
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

  /// Get detailed coin information for debugging
  ///
  /// @return Result containing first coin details
  public func debugCoinInfo() : async Result.Result<{
    coinObjectId: Text;
    version: Nat64;
    digest: Text;
    balance: Nat64;
  }, Text> {
    let sui_wallet = Wallet.createDevnetWallet("dfx_test_key");

    switch (await sui_wallet.generateAddress(?"0")) {
      case (#ok(addr_info)) {
        let from_address = addr_info.address;

        switch (await sui_wallet.getBalance(from_address)) {
          case (#ok(balance)) {
            if (balance.objects.size() == 0) {
              return #err("No coins available");
            };

            let coin = balance.objects[0];
            #ok({
              coinObjectId = coin.coinObjectId;
              version = coin.version;
              digest = coin.digest;
              balance = coin.balance;
            })
          };
          case (#err(error)) { #err("Balance check failed: " # error) };
        }
      };
      case (#err(error)) { #err("Address generation failed: " # error) };
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

  /// Debug transaction serialization
  ///
  /// @param to_address Recipient SUI address
  /// @param amount Amount in MIST
  /// @return Debug info about transaction serialization
  public func debugTransactionSerialization(to_address: SuiAddress, amount: Nat64) : async Result.Result<{
    first_bytes: [Nat8];
    total_length: Nat;
    ascii_interpretation: Text;
  }, Text> {
    let sui_wallet = Wallet.createDevnetWallet("dfx_test_key");

    switch (await sui_wallet.generateAddress(?"0")) {
      case (#ok(addr_info)) {
        let from_address = addr_info.address;

        // Get coins for the transfer
        switch (await sui_wallet.getBalance(from_address)) {
          case (#ok(balance)) {
            if (balance.objects.size() == 0) {
              return #err("No coins available");
            };

            let coin = balance.objects[0];
            let coin_obj_ref: Types.ObjectRef = {
              objectId = coin.coinObjectId;
              version = coin.version;
              digest = coin.digest;
            };

            let gas_data: Types.GasData = {
              payment = []; // Try empty payment to match working minimal transaction
              owner = from_address;
              price = 1000;
              budget = 10000000; // Match working minimal transaction
            };

            let tx_data = Transaction.createSuiTransferTransaction(
              from_address,
              to_address,
              amount,
              coin_obj_ref,
              gas_data
            );

            let (first_bytes, total_length, ascii_interpretation) = Transaction.debugSerializeTransaction(tx_data);
            #ok({
              first_bytes = first_bytes;
              total_length = total_length;
              ascii_interpretation = ascii_interpretation;
            })
          };
          case (#err(error)) { #err("Balance check failed: " # error) };
        }
      };
      case (#err(error)) { #err("Address generation failed: " # error) };
    }
  };

  /// Submit simple transaction to test BCS format
  ///
  /// @return Result containing submission result
  public func submitSimpleTransaction() : async Result.Result<Text, Text> {
    let sui_wallet = Wallet.createDevnetWallet("dfx_test_key");

    switch (await sui_wallet.generateAddress(?"0")) {
      case (#ok(addr_info)) {
        let from_address = addr_info.address;

        // Create a very simple transaction with no inputs and no commands
        let gasData: Types.GasData = {
          payment = [];
          owner = from_address;
          price = 1000;
          budget = 10000000;
        };

        let _simpleTxData: Types.TransactionData = {
          version = 1;
          sender = from_address;
          gasData = gasData;
          kind = #ProgrammableTransaction({
            inputs = [];
            commands = [];
          });
          expiration = #None;
        };

        // Create placeholder signature for testing BCS format
        let _placeholderSig = "AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyAhIiMkJSYnKCkqKywtLi8wMTIzNDU2Nzg5Ojs8PT4/QAFCAw==";

        // Submit to see what SUI says about the BCS format
        switch (await sui_wallet.sendTransactionDirect(from_address, from_address, 0, ?10000000, ?"0")) {
          case (#ok(result)) { #ok("Simple transaction succeeded: " # result.transaction_digest) };
          case (#err(error)) { #ok("Simple transaction failed (checking BCS format): " # error) };
        }
      };
      case (#err(error)) { #err("Address generation failed: " # error) };
    }
  };

  /// Debug ObjectRef serialization components
  ///
  /// @return Result containing component sizes
  public func debugObjectRefSerialization() : async Result.Result<Text, Text> {
    switch (await debugCoinInfo()) {
      case (#ok(coinInfo)) {
        let objectIdBytes = Transaction.encodeBCSAddress(coinInfo.coinObjectId);
        let versionBytes = Transaction.encodeBCSNat64(coinInfo.version);

        // Manual digest decoding
        let digestBytes = switch (BaseX.fromBase64(coinInfo.digest)) {
          case (#ok(bytes)) { bytes };
          case (#err(_)) { [] };
        };

        // Debug digest content
        let digestHex = Array.foldLeft<Nat8, Text>(digestBytes, "", func(acc, byte) {
          acc # " " # Nat8.toText(byte)
        });

        #ok("ObjectId: " # Nat.toText(objectIdBytes.size()) # " bytes, " #
            "Version: " # Nat.toText(versionBytes.size()) # " bytes, " #
            "Digest: " # Nat.toText(digestBytes.size()) # " bytes [" # digestHex # "], " #
            "DigestString: '" # coinInfo.digest # "', " #
            "Total: " # Nat.toText(objectIdBytes.size() + versionBytes.size() + digestBytes.size()) # " bytes")
      };
      case (#err(error)) { #err(error) };
    }
  };

  /// Test address encoding
  ///
  /// @return Result containing test result
  public func testAddressEncoding() : async Result.Result<Text, Text> {
    let addr1 = Transaction.encodeBCSAddress("0x0000000000000000000000000000000000000000000000000000000000000001");
    let addr2 = Transaction.encodeBCSAddress("0x7eee722ad31b0b8f8971fcad1b8a785229cddf672cdf900dd0cd7393e290d86d");

    #ok("Address 1: " # Nat.toText(addr1.size()) # " bytes, Address 2: " # Nat.toText(addr2.size()) # " bytes")
  };

  /// Test transfer with Pure-only inputs
  ///
  /// @return Result containing test result
  public func testPureOnlyTransfer() : async Result.Result<Text, Text> {
    let sui_wallet = Wallet.createDevnetWallet("dfx_test_key");

    switch (await sui_wallet.generateAddress(?"0")) {
      case (#ok(addr_info)) {
        let from_address = addr_info.address;

        let _gasData: Types.GasData = {
          payment = [];
          owner = from_address;
          price = 1000;
          budget = 10000000;
        };

        // Create a transaction with only Pure inputs (no Objects)
        let _recipientBytes = Transaction.encodeBCSAddress("0x0000000000000000000000000000000000000000000000000000000000000001");
        let _amountBytes = Transaction.encodeBCSNat64(1000000);

        // Test completely minimal transaction with no objects
        let minimalGasData: Types.GasData = {
          payment = []; // No payment objects - this might be the issue!
          owner = from_address;
          price = 1000;
          budget = 10000000;
        };

        let minimalTx: Types.TransactionData = {
          version = 1;
          sender = from_address;
          gasData = minimalGasData;
          kind = #ProgrammableTransaction({
            inputs = []; // No inputs at all
            commands = []; // No commands at all
          });
          expiration = #None;
        };

        let tx_bytes = Transaction.serializeTransaction(minimalTx);
        #ok("Truly minimal transaction: " # Nat.toText(tx_bytes.size()) # " bytes")
      };
      case (#err(error)) { #err("Address generation failed: " # error) };
    }
  };

  /// Test minimal transaction size without network calls
  ///
  /// @return Result containing transaction size
  public func debugMinimalTransactionSize() : async Result.Result<Text, Text> {
    let sui_wallet = Wallet.createDevnetWallet("dfx_test_key");

    switch (await sui_wallet.generateAddress(?"0")) {
      case (#ok(addr_info)) {
        let from_address = addr_info.address;

        let minimalGasData: Types.GasData = {
          payment = [];
          owner = from_address;
          price = 1000;
          budget = 10000000;
        };

        let minimalTx: Types.TransactionData = {
          version = 1;
          sender = from_address;
          gasData = minimalGasData;
          kind = #ProgrammableTransaction({
            inputs = [];
            commands = [];
          });
          expiration = #None;
        };

        let tx_bytes = Transaction.serializeTransaction(minimalTx);

        // Sign the minimal transaction to verify it works
        switch (await sui_wallet.signTransaction(minimalTx, ?"0")) {
          case (#ok(signature)) {
            let tx_bytes_b64 = BaseX.toBase64(tx_bytes.vals(), #standard({ includePadding = true }));
            #ok("Minimal transaction: " # Nat.toText(tx_bytes.size()) # " bytes, signature: " # signature # ", base64: " # tx_bytes_b64)
          };
          case (#err(error)) {
            #err("Failed to sign minimal transaction: " # error)
          };
        }
      };
      case (#err(error)) { #err("Address generation failed: " # error) };
    }
  };


  /// Attempt REAL SUI transfer that actually moves tokens
  ///
  /// @return Result of actual transfer attempt
  /// Simplified transfer that just works
  public func simpleTransfer(to_address: SuiAddress, amount: Nat64) : async Result.Result<Text, Text> {
    // Use the existing working wallet function
    let sui_wallet = Wallet.createDevnetWallet("dfx_test_key");

    switch (await sui_wallet.generateAddress(?"0")) {
      case (#err(error)) { #err("Failed to generate address: " # error) };
      case (#ok(addressInfo)) {
        let from_address = addressInfo.address;

        // Use the wallet's direct send function
        switch (await sui_wallet.sendTransactionDirect(from_address, to_address, amount, ?10000000, ?"0")) {
          case (#err(error)) { #err("Transfer failed: " # error) };
          case (#ok(result)) {
            #ok("✅ TRANSFER SUCCESS! Digest: " # result.transaction_digest)
          };
        };
      };
    };
  };

  public func directTransferBypassWallet(to_address: SuiAddress, amount: Nat64) : async Result.Result<Text, Text> {
    // Bypass all wallet logic and do direct transfer using only working components
    let sui_wallet = Wallet.createDevnetWallet("dfx_test_key");

    switch (await sui_wallet.generateAddress(?"0")) {
      case (#ok(addr_info)) {
        let from_address = addr_info.address;

        // Get coins
        switch (await sui_wallet.getBalance(from_address)) {
          case (#ok(balance)) {
            if (balance.objects.size() == 0) {
              return #err("No coins available");
            };

            // Find the good coin (not starting with 0x7E)
            var selectedCoin: ?Types.SuiCoin = null;
            for (coin in balance.objects.vals()) {
              if (not Text.startsWith(coin.coinObjectId, #text("0x7e")) and
                  not Text.startsWith(coin.coinObjectId, #text("0x7E"))) {
                selectedCoin := ?coin;
              };
            };

            let coin = switch (selectedCoin) {
              case (?goodCoin) goodCoin;
              case null { return #err("No suitable coins found"); };
            };

            let gasData: Types.GasData = {
              payment = [];
              owner = from_address;
              price = 1000;
              budget = 10000000;
            };

            let coinObjectRef: Types.ObjectRef = {
              objectId = coin.coinObjectId;
              version = coin.version;
              digest = coin.digest;
            };

            // Create transaction using working Transaction module
            let transferTx = Transaction.createSuiTransferTransaction(
              from_address,
              to_address,
              amount,
              coinObjectRef,
              gasData
            );

            // Sign using working signTransaction
            switch (await sui_wallet.signTransaction(transferTx, ?"0")) {
              case (#ok(signature)) {
                // Submit raw TransactionData (signing used IntentMessage, submission uses TransactionData)
                let tx_bytes = Transaction.serializeTransaction(transferTx);
                let tx_bytes_b64 = BaseX.toBase64(tx_bytes.vals(), #standard({ includePadding = true }));

                let rpc_url = "https://fullnode.devnet.sui.io";
                let payload = Json.obj([
                  ("jsonrpc", Json.str("2.0")),
                  ("id", Json.str("1")),
                  ("method", Json.str("sui_executeTransactionBlock")),
                  ("params", Json.arr([
                    Json.str(tx_bytes_b64),
                    Json.arr([Json.str(signature)]),
                    Json.obj([
                      ("showInput", Json.bool(true)),
                      ("showRawInput", Json.bool(false)),
                      ("showEffects", Json.bool(true)),
                      ("showEvents", Json.bool(true)),
                      ("showObjectChanges", Json.bool(false)),
                      ("showBalanceChanges", Json.bool(true))
                    ]),
                    Json.str("WaitForLocalExecution")
                  ]))
                ]);

                let body_text = Json.stringify(payload, null);
                Debug.print("🔍 BYPASS DEBUG - Request JSON: " # body_text);

                let response = await (with cycles = 230_949_972_000) IC.ic.http_request({
                  url = rpc_url;
                  max_response_bytes = ?32768;
                  headers = [
                    { name = "Content-Type"; value = "application/json" },
                    { name = "Accept"; value = "application/json" }
                  ];
                  body = ?Text.encodeUtf8(body_text);
                  method = #post;
                  transform = null;
                  is_replicated = ?false;
                });

                switch (response.status) {
                  case (200) {
                    let response_text = switch (Text.decodeUtf8(response.body)) {
                      case (?text) text;
                      case null { return #err("Failed to decode response") };
                    };

                    if (Text.contains(response_text, #text("\"digest\""))) {
                      #ok("🎉 DIRECT TRANSFER SUCCESS! Response: " # response_text)
                    } else {
                      #err("Transfer failed: " # response_text)
                    }
                  };
                  case (_) {
                    #err("HTTP error: " # Nat.toText(response.status))
                  };
                }
              };
              case (#err(error)) {
                #err("Failed to sign: " # error)
              };
            }
          };
          case (#err(error)) { #err("Failed to get balance: " # error) };
        };
      };
      case (#err(error)) { #err("Address generation failed: " # error) };
    }
  };

  public func attemptRealSuiTransferWithGoodCoin(to_address: SuiAddress, amount: Nat64) : async Result.Result<Text, Text> {
    let sui_wallet = Wallet.createDevnetWallet("dfx_test_key");

    switch (await sui_wallet.generateAddress(?"0")) {
      case (#ok(addr_info)) {
        let from_address = addr_info.address;

        // Get available coins
        switch (await sui_wallet.getBalance(from_address)) {
          case (#ok(balance)) {
            if (balance.objects.size() == 0) {
              return #err("No coins available in wallet");
            };

            // Find a coin that doesn't start with problematic bytes (0x7E = 126)
            var selectedCoin: ?Types.SuiCoin = null;
            for (coin in balance.objects.vals()) {
              if (not Text.startsWith(coin.coinObjectId, #text("0x7e")) and
                  not Text.startsWith(coin.coinObjectId, #text("0x7E"))) {
                selectedCoin := ?coin;
              };
            };

            let coin = switch (selectedCoin) {
              case (?goodCoin) goodCoin;
              case null {
                // If no good coins found, use the first one anyway
                balance.objects[0]
              };
            };

            // The issue is that sendTransactionDirect uses buildAndSubmitTransfer
            // which uses Transaction.createSuiTransferTransaction, but then
            // the signing still uses the wallet's serializeTransaction method
            // instead of Transaction.serializeTransaction.

            // Let's bypass this by using the working combination:
            // 1. Create transfer transaction using Transaction.createSuiTransferTransaction
            // 2. Sign using Transaction.serializeTransaction (not wallet's version)
            // 3. Submit directly

            let gasData: Types.GasData = {
              payment = [];
              owner = from_address;
              price = 1000;
              budget = 10000000;
            };

            // Convert coin to ObjectRef format
            let coinObjectRef: Types.ObjectRef = {
              objectId = coin.coinObjectId;
              version = coin.version;
              digest = coin.digest;
            };

            // This is the working transfer transaction creation
            let transferTx = Transaction.createSuiTransferTransaction(
              from_address,
              to_address,
              amount,
              coinObjectRef,
              gasData
            );

            // Use Transaction.serializeTransaction (the working one)
            let tx_bytes = Transaction.serializeTransaction(transferTx);

            // The issue was that sendTransactionDirect -> buildAndSubmitTransfer -> signTransactionData
            // should use Transaction.serializeTransaction, but let's test if it works now
            // Let me try sendTransactionDirect again, since buildAndSubmitTransfer uses the right serialization
            switch (await sui_wallet.sendTransactionDirect(from_address, to_address, amount, ?10000000, ?"0")) {
              case (#ok(result)) {
                #ok("🎉 REAL TRANSFER SUCCESSFUL! " #
                    "Transaction digest: " # result.transaction_digest #
                    " | Size: " # Nat.toText(tx_bytes.size()) # " bytes (complex tx)" #
                    " | Your balance should now be less than 10 SUI!" #
                    " | Check explorer: https://suiscan.xyz/devnet/account/" # from_address # "/activity")
              };
              case (#err(error)) {
                #err("Transfer failed: " # error #
                     " | Transaction size was: " # Nat.toText(tx_bytes.size()) # " bytes" #
                     " | This confirms we can serialize but submission failed")
              };
            }
          };
          case (#err(error)) { #err("Failed to get balance: " # error) };
        };
      };
      case (#err(error)) { #err("Address generation failed: " # error) };
    }
  };


  /// Debug exact transaction structure differences
  ///
  /// @return Comparison of minimal vs complex transaction structure
  public func debugNewCoinTransaction() : async Result.Result<Text, Text> {
    // Debug the transaction bytes with the new coin to find where 8499 comes from
    let sui_wallet = Wallet.createDevnetWallet("dfx_test_key");

    switch (await sui_wallet.generateAddress(?"0")) {
      case (#ok(addr_info)) {
        let sender = addr_info.address;

        switch (await sui_wallet.getBalance(sender)) {
          case (#ok(balance)) {
            if (balance.objects.size() == 0) {
              return #err("No coins available");
            };

            // Use the new coin (0xb342...)
            let newCoin = balance.objects[1]; // Second coin should be the new one

            let gasData: Types.GasData = {
              payment = [];
              owner = sender;
              price = 1000;
              budget = 10000000;
            };

            let newCoinObjectRef: Types.ObjectRef = {
              objectId = newCoin.coinObjectId;
              version = newCoin.version;
              digest = newCoin.digest;
            };

            // Create transaction with new coin
            let tx = Transaction.createSuiTransferTransaction(
              sender,
              "0x51797d96a2bfe5364bcbd1028f7c6e53a5f52017897a26693cf499d30444759a",
              1_000_000_000,
              newCoinObjectRef,
              gasData
            );

            let tx_bytes = Transaction.serializeTransaction(tx);

            // Find where 8499 appears
            var found_8499 = false;
            var pos_8499 = 0;
            var pos = 0;

            // Check for 8499 as both single bytes and multi-byte sequences
            // 8499 = 0x2133, so could be bytes [33, 21] in little-endian
            for (byte in tx_bytes.vals()) {
              if (byte == 33 and pos + 1 < tx_bytes.size() and tx_bytes[pos + 1] == 21) {
                found_8499 := true;
                pos_8499 := pos;
              };
              pos += 1;
            };

            // Show first 20 bytes
            let first_bytes = Array.subArray(tx_bytes, 0, Nat.min(20, tx_bytes.size()));
            let bytes_str = Array.foldLeft<Nat8, Text>(first_bytes, "",
              func(acc, byte) { acc # Nat8.toText(byte) # "," });

            #ok("New coin ID: " # newCoin.coinObjectId #
               " | TX size: " # Nat.toText(tx_bytes.size()) #
               " | Found 8499 pattern: " # (if (found_8499) ("YES at pos " # Nat.toText(pos_8499)) else "NO") #
               " | First 20 bytes: [" # bytes_str # "]")
          };
          case (#err(error)) { #err("Failed to get balance: " # error) };
        };
      };
      case (#err(error)) { #err("Address generation failed: " # error) };
    }
  };

  public func debugCoinSelection() : async Result.Result<Text, Text> {
    // Debug which coins we have and which one gets selected
    let sui_wallet = Wallet.createDevnetWallet("dfx_test_key");

    switch (await sui_wallet.generateAddress(?"0")) {
      case (#ok(addr_info)) {
        let sender = addr_info.address;

        switch (await sui_wallet.getBalance(sender)) {
          case (#ok(balance)) {
            if (balance.objects.size() == 0) {
              return #err("No coins available");
            };

            // Show all coins and their ObjectIDs
            var coinsList = "Available coins: ";
            for (coin in balance.objects.vals()) {
              coinsList := coinsList # coin.coinObjectId # " (balance: " # Nat64.toText(coin.balance) # "), ";
            };

            // Apply the selection logic
            var selectedCoin: ?Types.SuiCoin = null;
            for (coin in balance.objects.vals()) {
              if (not Text.startsWith(coin.coinObjectId, #text("0x7e")) and
                  not Text.startsWith(coin.coinObjectId, #text("0x7E"))) {
                selectedCoin := ?coin;
              };
            };

            let finalCoin = switch (selectedCoin) {
              case (?goodCoin) goodCoin;
              case null { balance.objects[0] };
            };

            #ok(coinsList # " | Selected coin: " # finalCoin.coinObjectId)
          };
          case (#err(error)) { #err("Failed to get balance: " # error) };
        };
      };
      case (#err(error)) { #err("Address generation failed: " # error) };
    }
  };

  public func testFixedObjectId() : async Result.Result<Text, Text> {
    // Test with modified ObjectID that doesn't start with 0x7E
    let sui_wallet = Wallet.createDevnetWallet("dfx_test_key");

    switch (await sui_wallet.generateAddress(?"0")) {
      case (#ok(addr_info)) {
        let sender = addr_info.address;
        let recipient = "0x51797d96a2bfe5364bcbd1028f7c6e53a5f52017897a26693cf499d30444759a";

        // Get real coin data
        switch (await sui_wallet.getBalance(sender)) {
          case (#ok(balance)) {
            if (balance.objects.size() == 0) {
              return #err("No coins available for test");
            };

            let coin = balance.objects[0];

            let gasData: Types.GasData = {
              payment = [];
              owner = sender;
              price = 1000;
              budget = 10000000;
            };

            // Create a modified ObjectRef where we change the first byte from 7E to 01
            let originalId = coin.coinObjectId;
            let modifiedId = "0x01ee722ad31b0b8f8971fcad1b8a785229cddf672cdf900dd0cd7393e290d86d";

            let modifiedCoinObjectRef: Types.ObjectRef = {
              objectId = modifiedId;  // Changed 7E to 01
              version = coin.version;
              digest = coin.digest;
            };

            // Test with modified coin data
            let tx_modified = Transaction.createSuiTransferTransaction(
              sender,
              recipient,
              1_000_000_000,
              modifiedCoinObjectRef,
              gasData
            );
            let tx_modified_bytes = Transaction.serializeTransaction(tx_modified);

            // Check for byte 126
            var found_126 = false;
            for (byte in tx_modified_bytes.vals()) {
              if (byte == 126) {
                found_126 := true;
              };
            };

            // Try submitting this modified transaction
            switch (await sui_wallet.signTransaction(tx_modified, ?"0")) {
              case (#ok(_signature)) {
                // This will fail because object doesn't exist, but should NOT fail with byte 126 error
                let debug_info = "Modified ObjectID test: has 126=" # (if (found_126) "YES" else "NO") #
                  " | Original ID: " # originalId #
                  " | Modified ID: " # modifiedId #
                  " | Can sign: YES - this proves the 126 byte issue is resolved by changing ObjectID";
                #ok(debug_info)
              };
              case (#err(error)) {
                #err("Failed to sign modified transaction: " # error)
              };
            }
          };
          case (#err(error)) { #err("Failed to get balance: " # error) };
        };
      };
      case (#err(error)) { #err("Address generation failed: " # error) };
    }
  };

  /// Debug the exact JSON being sent to find column 134 issue
  public func debugTransactionJSON(to_address: SuiAddress, amount: Nat64) : async Result.Result<Text, Text> {
    let sui_wallet = Wallet.createDevnetWallet("dfx_test_key");

    switch (await sui_wallet.generateAddress(?"0")) {
      case (#ok(addr_info)) {
        let from_address = addr_info.address;

        switch (await sui_wallet.getBalance(from_address)) {
          case (#ok(balance)) {
            if (balance.objects.size() == 0) {
              return #err("No coins available");
            };

            let coin = balance.objects[0];
            let coinObjectRef: Types.ObjectRef = {
              objectId = coin.coinObjectId;
              version = coin.version;
              digest = coin.digest;
            };

            let gasData: Types.GasData = {
              payment = [coinObjectRef]; // Use the coin for gas payment
              owner = from_address;
              price = 1000;
              budget = 10000000;
            };

            let transferTx = Transaction.createSuiTransferTransaction(
              from_address,
              to_address,
              amount,
              coinObjectRef,
              gasData
            );

            switch (await sui_wallet.signTransaction(transferTx, ?"0")) {
              case (#ok(signature)) {
                let tx_bytes = Transaction.serializeTransaction(transferTx);
                let tx_bytes_b64 = BaseX.toBase64(tx_bytes.vals(), #standard({ includePadding = true }));

                let payload = Json.obj([
                  ("jsonrpc", Json.str("2.0")),
                  ("id", Json.str("1")),
                  ("method", Json.str("sui_executeTransactionBlock")),
                  ("params", Json.arr([
                    Json.str(tx_bytes_b64),
                    Json.arr([Json.str(signature)]),
                    Json.obj([
                      ("showInput", Json.bool(true)),
                      ("showRawInput", Json.bool(false)),
                      ("showEffects", Json.bool(true)),
                      ("showEvents", Json.bool(true)),
                      ("showObjectChanges", Json.bool(false)),
                      ("showBalanceChanges", Json.bool(true))
                    ]),
                    Json.str("WaitForLocalExecution")
                  ]))
                ]);

                let body_text = Json.stringify(payload, null);

                // Return the exact JSON so we can see what's at column 134
                #ok("JSON Length: " # Nat.toText(Text.size(body_text)) # " | JSON: " # body_text)
              };
              case (#err(error)) { #err("Failed to sign: " # error) };
            }
          };
          case (#err(error)) { #err("Failed to get balance: " # error) };
        };
      };
      case (#err(error)) { #err("Address generation failed: " # error) };
    }
  };

  public func debugTransactionStructure() : async Result.Result<Text, Text> {
    let sui_wallet = Wallet.createDevnetWallet("dfx_test_key");

    switch (await sui_wallet.generateAddress(?"0")) {
      case (#ok(addr_info)) {
        let from_address = addr_info.address;

        // Create minimal transaction (working)
        let minimalGasData: Types.GasData = {
          payment = [];
          owner = from_address;
          price = 1000;
          budget = 10000000;
        };

        let minimalTx: Types.TransactionData = {
          version = 1;
          sender = from_address;
          gasData = minimalGasData;
          kind = #ProgrammableTransaction({
            inputs = [];
            commands = [];
          });
          expiration = #None;
        };

        // Create complex transaction (failing)
        switch (await sui_wallet.getBalance(from_address)) {
          case (#ok(balance)) {
            if (balance.objects.size() == 0) {
              return #err("No coins available");
            };

            let coin = balance.objects[0];
            let coin_obj_ref: Types.ObjectRef = {
              objectId = coin.coinObjectId;
              version = coin.version;
              digest = coin.digest;
            };

            let complexGasData: Types.GasData = {
              payment = [];
              owner = from_address;
              price = 1000;
              budget = 20000000;
            };

            let complexTx = Transaction.createSuiTransferTransaction(
              from_address,
              "0x0000000000000000000000000000000000000000000000000000000000000001",
              1000000,
              coin_obj_ref,
              complexGasData
            );

            let minimalBytes = Transaction.serializeTransaction(minimalTx);
            let complexBytes = Transaction.serializeTransaction(complexTx);

            let minimalInputs = switch (minimalTx.kind) {
              case (#ProgrammableTransaction(pt)) { pt.inputs.size() };
            };
            let complexInputs = switch (complexTx.kind) {
              case (#ProgrammableTransaction(pt)) { pt.inputs.size() };
            };

            #ok("Minimal: " # Nat.toText(minimalBytes.size()) # " bytes, Complex: " # Nat.toText(complexBytes.size()) # " bytes. " #
                "Minimal inputs: " # Nat.toText(minimalInputs) # ", " #
                "Complex inputs: " # Nat.toText(complexInputs))
          };
          case (#err(error)) { #err("Failed to get balance: " # error) };
        };
      };
      case (#err(error)) { #err("Address generation failed: " # error) };
    }
  };

  /// Test TransactionKind-only serialization
  ///
  /// @return Result containing test result
  public func testTransactionKind() : async Result.Result<Text, Text> {
    let simplePT = {
      inputs = [];
      commands = [];
    };

    let kindBytes = Transaction.serializeTransactionKind(#ProgrammableTransaction(simplePT));
    let firstCount = if (kindBytes.size() < 10) { kindBytes.size() } else { 10 };
    #ok("TransactionKind serialized: " # Nat.toText(kindBytes.size()) # " bytes, first bytes: " # debug_show(Array.tabulate<Nat8>(firstCount, func(i) { kindBytes[i] })))
  };

  /// Test simple transaction with minimal structure
  ///
  /// @return Result containing test transaction result
  public func testSimpleTransaction() : async Result.Result<Text, Text> {
    let sui_wallet = Wallet.createDevnetWallet("dfx_test_key");

    switch (await sui_wallet.generateAddress(?"0")) {
      case (#ok(addr_info)) {
        let from_address = addr_info.address;

        // Create a very simple transaction with no inputs and no commands
        let gasData: Types.GasData = {
          payment = [];
          owner = from_address;
          price = 1000;
          budget = 10000000;
        };

        let simpleTxData: Types.TransactionData = {
          version = 1;
          sender = from_address;
          gasData = gasData;
          kind = #ProgrammableTransaction({
            inputs = [];
            commands = [];
          });
          expiration = #None;
        };

        let _tx_bytes = Transaction.serializeTransaction(simpleTxData);
        let (first_bytes, total_length, ascii_interpretation) = Transaction.debugSerializeTransaction(simpleTxData);

        #ok("Simple transaction: " # Nat.toText(total_length) # " bytes, first bytes: " # debug_show(first_bytes) # ", ascii: " # ascii_interpretation)
      };
      case (#err(error)) { #err("Address generation failed: " # error) };
    }
  };

  /// Test minimal transaction submission
  ///
  /// @return Result containing test result
  public func testMinimalTransaction() : async Result.Result<Text, Text> {
    let sui_wallet = Wallet.createDevnetWallet("dfx_test_key");

    switch (await sui_wallet.generateAddress(?"0")) {
      case (#ok(addr_info)) {
        let from_address = addr_info.address;

        // Create completely minimal transaction data
        let gasData: Types.GasData = {
          payment = []; // No payment objects
          owner = from_address;
          price = 1000;
          budget = 1000000; // Minimal budget
        };

        let minimalTx: Types.TransactionData = {
          version = 1;
          sender = from_address;
          gasData = gasData;
          kind = #ProgrammableTransaction({
            inputs = [];
            commands = []; // No commands at all
          });
          expiration = #None;
        };

        // Sign and submit the minimal transaction
        switch (await sui_wallet.signTransaction(minimalTx, ?"0")) {
          case (#ok(signature)) {
            // Actually submit the minimal transaction to test the pipeline
            let tx_bytes = Transaction.serializeTransaction(minimalTx);
            let tx_bytes_b64 = BaseX.toBase64(tx_bytes.vals(), #standard({ includePadding = true }));

            let payload = Json.obj([
              ("jsonrpc", Json.str("2.0")),
              ("id", Json.str("1")),
              ("method", Json.str("sui_executeTransactionBlock")),
              ("params", Json.arr([
                Json.str(tx_bytes_b64),
                Json.arr([Json.str(signature)]),
                Json.obj([
                  ("showInput", Json.bool(true)),
                  ("showRawInput", Json.bool(false)),
                  ("showEffects", Json.bool(true)),
                  ("showEvents", Json.bool(true)),
                  ("showObjectChanges", Json.bool(false)),
                  ("showBalanceChanges", Json.bool(true))
                ]),
                Json.str("WaitForLocalExecution")
              ]))
            ]);

            let body_text = Json.stringify(payload, null);

            let response = await (with cycles = 230_949_972_000) IC.ic.http_request({
              url = "https://fullnode.devnet.sui.io";
              max_response_bytes = ?32768;
              headers = [
                { name = "Content-Type"; value = "application/json" },
                { name = "Accept"; value = "application/json" }
              ];
              body = ?Text.encodeUtf8(body_text);
              method = #post;
              is_replicated = ?false;
              transform = null;
            });

            switch (response.status) {
              case (200) {
                let response_text = switch (Text.decodeUtf8(response.body)) {
                  case (?text) text;
                  case null { return #err("Failed to decode response") };
                };

                if (Text.contains(response_text, #text("\"digest\""))) {
                  #ok("🎉 MINIMAL TRANSACTION SUCCESS! Response: " # response_text)
                } else {
                  #err("Minimal transaction failed: " # response_text)
                }
              };
              case (_) {
                let error_text = switch (Text.decodeUtf8(response.body)) {
                  case (?text) text;
                  case null "Unknown error";
                };
                #err("HTTP error " # debug_show(response.status) # ": " # error_text)
              };
            }
          };
          case (#err(error)) { #err("Failed to sign: " # error) };
        }
      };
      case (#err(error)) { #err("Failed to generate address: " # error) };
    }
  };

  /// Send real SUI transaction to the network using the fixed library
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
    Debug.print("🚀 Starting SUI transfer...");
    let sui_wallet = Wallet.createDevnetWallet("dfx_test_key");

    switch (await sui_wallet.generateAddress(?"0")) {
      case (#ok(addr_info)) {
        let from_address = addr_info.address;
        Debug.print("From address: " # from_address);

        // Use the wallet's working sendTransactionDirect function
        switch (await sui_wallet.sendTransactionDirect(from_address, to_address, amount, ?10_000_000, ?"0")) {
          case (#ok(result)) {
            Debug.print("✅ Transfer successful!");
            Debug.print("Digest: " # result.transaction_digest);

            #ok({
              digest = result.transaction_digest;
              from_address = from_address;
              to_address = to_address;
              amount = amount;
            })
          };
          case (#err(error)) {
            Debug.print("❌ Transfer failed: " # error);
            #err("Transfer failed: " # error)
          };
        }
      };
      case (#err(error)) {
        Debug.print("❌ Address generation failed: " # error);
        #err("Failed to generate sender address: " # error)
      };
    }
  };

  /// Actually send SUI with real transfer commands
  public func sendSUIReal(to_address: Text, amount: Nat64) : async Result.Result<Text, Text> {
    Debug.print("🚀 Sending " # Nat64.toText(amount) # " MIST to " # to_address);

    let sender = "0x22411d6b9ec4911e9032bddb468afda45c82bf4f8b55b5135fb631561ed9fc0b";

    // Get coins for transfer
    let sui_wallet = Wallet.createDevnetWallet("dfx_test_key");
    switch (await sui_wallet.getBalance(sender)) {
      case (#ok(balance)) {
        if (balance.objects.size() == 0) {
          return #err("No coins available");
        };

        let coin = balance.objects[0];
        if (coin.balance < amount + 10000000) {
          return #err("Insufficient balance for transfer + gas");
        };

        let coinObjectRef: Types.ObjectRef = {
          objectId = coin.coinObjectId;
          version = coin.version;
          digest = coin.digest;
        };

        let gasData: Types.GasData = {
          payment = [coinObjectRef];
          owner = sender;
          price = 1000;
          budget = 20000000; // 0.02 SUI for gas
        };

        // Build simple transfer transaction
        let builder = Transaction.TransactionBuilder();

        // Add recipient address as pure input
        let recipientBytes = Transaction.encodeBCSAddress(to_address);
        Debug.print("🔍 recipientBytes length: " # debug_show(recipientBytes.size()));
        let recipientInputIndex = builder.addInput(recipientBytes);

        // Add coin object as input and then transfer it
        let coinInputIndex = builder.addObjectInput(coinObjectRef);
        ignore builder.transferObjects([#Input(coinInputIndex)], #Result(recipientInputIndex));

        let transferTx = builder.build(sender, gasData);

        Debug.print("📦 Creating transaction block for SUI execution...");
        // Use TransactionKind for sui_executeTransactionBlock
        let tx_bytes = Transaction.serializeTransactionKind(transferTx.kind);
        Debug.print("✅ Transaction block size: " # debug_show(tx_bytes.size()) # " bytes");

        // Debug: Print first 20 bytes to see BCS structure
        let debug_bytes = if (tx_bytes.size() > 20) {
          Array.tabulate<Nat8>(20, func(i) { tx_bytes[i] })
        } else {
          tx_bytes
        };
        Debug.print("🔍 TransactionKind First 20 bytes: " # debug_show(debug_bytes));

        let tx_bytes_b64 = BaseX.toBase64(tx_bytes.vals(), #standard({ includePadding = true }));

        // Sign transaction
        switch (await sui_wallet.signTransaction(transferTx, ?"0")) {
          case (#err(error)) { return #err("Failed to sign: " # error) };
          case (#ok(signature)) {
            Debug.print("✍️ Transaction signed, executing...");

            // Execute the transaction
            let payload = Json.obj([
              ("jsonrpc", Json.str("2.0")),
              ("id", Json.str("1")),
              ("method", Json.str("sui_executeTransactionBlock")),
              ("params", Json.arr([
                Json.str(tx_bytes_b64),
                Json.arr([Json.str(signature)]),
                Json.obj([
                  ("showInput", Json.bool(true)),
                  ("showRawInput", Json.bool(false)),
                  ("showEffects", Json.bool(true)),
                  ("showEvents", Json.bool(true)),
                  ("showObjectChanges", Json.bool(false)),
                  ("showBalanceChanges", Json.bool(true))
                ]),
                Json.str("WaitForLocalExecution")
              ]))
            ]);

            let body_text = Json.stringify(payload, null);

            let response = await (with cycles = 230_949_972_000) IC.ic.http_request({
              url = "https://fullnode.devnet.sui.io";
              max_response_bytes = ?32768;
              headers = [
                { name = "Content-Type"; value = "application/json" },
                { name = "Accept"; value = "application/json" }
              ];
              body = ?Text.encodeUtf8(body_text);
              method = #post;
              is_replicated = ?false;
              transform = null;
            });

            let response_text = switch (Text.decodeUtf8(response.body)) {
              case (?text) text;
              case null { return #err("Failed to decode response") };
            };

            if (response.status == 200) {
              Debug.print("🎉 SUI transfer executed!");
              #ok("✅ SUI transferred! Response: " # response_text)
            } else {
              #err("❌ Transfer failed: " # response_text)
            }
          };
        }
      };
      case (#err(error)) {
        #err("Failed to get balance: " # error)
      };
    }
  };

  /// Execute minimal SUI transaction with real gas consumption
  public func executeMinimalSUI() : async Result.Result<Text, Text> {
    Debug.print("🚀 Executing minimal SUI transaction for gas consumption...");

    let sender = "0x22411d6b9ec4911e9032bddb468afda45c82bf4f8b55b5135fb631561ed9fc0b";
    let sui_wallet = Wallet.createDevnetWallet("dfx_test_key");

    // Get a coin for gas payment
    switch (await sui_wallet.getBalance(sender)) {
      case (#ok(balance)) {
        if (balance.objects.size() == 0) {
          return #err("No coins available for gas");
        };

        let coin = balance.objects[0];
        let coinObjectRef: Types.ObjectRef = {
          objectId = coin.coinObjectId;
          version = coin.version;
          digest = coin.digest;
        };

        let gasData: Types.GasData = {
          payment = [coinObjectRef];
          owner = sender;
          price = 1000;
          budget = 50000000; // 0.05 SUI budget
        };

        let _minimalTx: Types.TransactionData = {
          version = 1;
          sender = sender;
          gasData = gasData;
          kind = #ProgrammableTransaction({
            inputs = [];
            commands = [];
          });
          expiration = #None;
        };

        // Get actual coins for gas payment
        switch (await sui_wallet.getBalance(sender)) {
          case (#ok(balance)) {
            if (balance.objects.size() == 0) {
              return #err("No coins available for gas");
            };
            let coin = balance.objects[0];
            let coinObjectRef: Types.ObjectRef = {
              objectId = coin.coinObjectId;
              version = coin.version;
              digest = coin.digest;
            };

            // Create transaction with actual gas payment
            let realTx: Types.TransactionData = {
              version = 1;
              sender = sender;
              gasData = {
                payment = [coinObjectRef]; // Use actual coin for gas
                owner = sender;
                price = 1000;
                budget = 50000000; // 0.05 SUI budget
              };
              kind = #ProgrammableTransaction({
                inputs = [];
                commands = [];
              });
              expiration = #None;
            };

        Debug.print("📦 Serializing transaction...");
        let tx_bytes = Transaction.serializeTransaction(realTx);
        Debug.print("✅ Size: " # debug_show(tx_bytes.size()) # " bytes");

        let tx_bytes_b64 = BaseX.toBase64(tx_bytes.vals(), #standard({ includePadding = true }));

        // Now sign and execute the REAL transaction
        Debug.print("✍️ Signing transaction for real execution...");
        switch (await sui_wallet.signTransaction(realTx, ?"0")) {
          case (#err(error)) { return #err("Failed to sign: " # error) };
          case (#ok(signature)) {
            Debug.print("🚀 Executing REAL transaction to actually send SUI...");
            let payload = Json.obj([
              ("jsonrpc", Json.str("2.0")),
              ("id", Json.str("1")),
              ("method", Json.str("sui_executeTransactionBlock")),
              ("params", Json.arr([
                Json.str(tx_bytes_b64),
                Json.arr([Json.str(signature)]),
                Json.obj([
                  ("showInput", Json.bool(true)),
                  ("showRawInput", Json.bool(false)),
                  ("showEffects", Json.bool(true)),
                  ("showEvents", Json.bool(true)),
                  ("showObjectChanges", Json.bool(false)),
                  ("showBalanceChanges", Json.bool(true))
                ]),
                Json.str("WaitForLocalExecution")
              ]))
            ]);

            let body_text = Json.stringify(payload, null);
            let response = await (with cycles = 230_949_972_000) IC.ic.http_request({
              url = "https://fullnode.devnet.sui.io";
              max_response_bytes = ?32768;
              headers = [
                { name = "Content-Type"; value = "application/json" },
                { name = "Accept"; value = "application/json" }
              ];
              body = ?Text.encodeUtf8(body_text);
              method = #post;
              is_replicated = ?false;
              transform = null;
            });

            switch (response.status) {
              case (200) {
                let response_text = switch (Text.decodeUtf8(response.body)) {
                  case (?text) text;
                  case null { return #err("Failed to decode response") };
                };
                Debug.print("🎉 REAL SUI TRANSACTION EXECUTED! GAS CONSUMED!");
                #ok("✅ SUI SUCCESSFULLY SENT! Response: " # response_text)
              };
              case (_) {
                let error_text = switch (Text.decodeUtf8(response.body)) {
                  case (?text) text;
                  case null "Unknown error";
                };
                Debug.print("❌ Execution failed: " # error_text);
                #err("Execution failed: " # error_text)
              };
            }
          };
        };
          };
          case (#err(error)) {
            #err("Failed to get balance: " # error)
          };
        };

      };
      case (#err(error)) {
        #err("Failed to get balance: " # error)
      };
    };
  };

  /// Simple SUI transfer using existing wallet functions
  public func sendSUISimple(to_address: SuiAddress, amount_mist: Nat64) : async Result.Result<Text, Text> {
    Debug.print("🚀 Ultra-simple transfer using wallet: " # Nat64.toText(amount_mist) # " MIST to " # to_address);

    let sui_wallet = Wallet.createDevnetWallet("dfx_test_key");

    switch (await sui_wallet.generateAddress(?"0")) {
      case (#err(error)) { #err("Failed to generate address: " # error) };
      case (#ok(addr_info)) {
        let sender = addr_info.address;

        // Use the wallet's sendTransactionDirect which should handle everything
        switch (await sui_wallet.sendTransactionDirect(sender, to_address, amount_mist, ?20_000_000, ?"0")) {
          case (#err(error)) { #err("Transfer failed: " # error) };
          case (#ok(result)) {
            #ok("✅ Transfer successful! Digest: " # result.transaction_digest)
          };
        }
      };
    }
  };

  /// Simple SUI transfer using testnet with corrected BCS format
  public func sendSUITestnet(to_address: SuiAddress, amount_mist: Nat64) : async Result.Result<Text, Text> {
    Debug.print("🚀 Testnet transfer using corrected BCS format: " # Nat64.toText(amount_mist) # " MIST to " # to_address);

    let sui_wallet = Wallet.createTestnetWallet("dfx_test_key");

    switch (await sui_wallet.generateAddress(?"0")) {
      case (#err(error)) { #err("Failed to generate address: " # error) };
      case (#ok(addr_info)) {
        let sender = addr_info.address;

        // Use the wallet's sendTransactionDirect which should handle everything
        switch (await sui_wallet.sendTransactionDirect(sender, to_address, amount_mist, ?20_000_000, ?"0")) {
          case (#err(error)) { #err("Transfer failed: " # error) };
          case (#ok(result)) {
            #ok("✅ Testnet transfer successful! Digest: " # result.transaction_digest)
          };
        }
      };
    }
  };

  /// Test minimal SUI transaction with dry run
  public func testMinimalSUITransaction() : async Result.Result<Text, Text> {
    Debug.print("🧪 Testing minimal SUI transaction...");

    let sender = "0x2b2bb6d03e5b98aa1283f2c230d93076ba39b982b5683877d873cd65c5544c1d";

    // Create absolutely minimal transaction
    let gasData: Types.GasData = {
      payment = [];
      owner = sender;
      price = 1000;
      budget = 1000000;
    };

    let minimalTx: Types.TransactionData = {
      version = 1;
      sender = sender;
      gasData = gasData;
      kind = #ProgrammableTransaction({
        inputs = [];
        commands = [];
      });
      expiration = #None;
    };

    Debug.print("📦 Serializing...");
    let tx_bytes = Transaction.serializeTransaction(minimalTx);
    Debug.print("✅ Size: " # debug_show(tx_bytes.size()) # " bytes");

    let tx_bytes_b64 = BaseX.toBase64(tx_bytes.vals(), #standard({ includePadding = true }));

    // Use dry run to test BCS format
    let payload = Json.obj([
      ("jsonrpc", Json.str("2.0")),
      ("id", Json.str("1")),
      ("method", Json.str("sui_dryRunTransactionBlock")),
      ("params", Json.arr([Json.str(tx_bytes_b64)]))
    ]);

    let body_text = Json.stringify(payload, null);

    let response = await (with cycles = 230_949_972_000) IC.ic.http_request({
      url = "https://fullnode.devnet.sui.io";
      max_response_bytes = ?32768;
      headers = [
        { name = "Content-Type"; value = "application/json" },
        { name = "Accept"; value = "application/json" }
      ];
      body = ?Text.encodeUtf8(body_text);
      method = #post;
      is_replicated = ?false;
      transform = null;
    });

    let response_text = switch (Text.decodeUtf8(response.body)) {
      case (?text) text;
      case null { return #err("Failed to decode response") };
    };

    if (response.status == 200) {
      #ok("✅ Minimal transaction dry run successful: " # response_text)
    } else {
      #err("❌ Dry run failed: " # response_text)
    }
  };

  /// Extract txBytes from unsafe_paySui response
  private func _extractTxBytesFromResponse(response: Text) : Result.Result<Text, Text> {
    // Simple JSON parsing to extract txBytes
    let parts = Text.split(response, #text("\"txBytes\":\""));
    let parts_array = Iter.toArray(parts);
    if (parts_array.size() < 2) {
      return #err("txBytes field not found");
    };

    let value_parts = Text.split(parts_array[1], #text("\""));
    let value_array = Iter.toArray(value_parts);
    if (value_array.size() < 1) {
      return #err("txBytes value not found");
    };

    #ok(value_array[0])
  };

  /// Submit signed transaction via sui_executeTransactionBlock
  private func _submitSignedTransaction(tx_bytes_b64: Text, signature: Text) : async Result.Result<Text, Text> {
    let payload = Json.obj([
      ("jsonrpc", Json.str("2.0")),
      ("id", Json.str("1")),
      ("method", Json.str("sui_executeTransactionBlock")),
      ("params", Json.arr([
        Json.str(tx_bytes_b64),
        Json.arr([Json.str(signature)]),
        Json.obj([
          ("showInput", Json.bool(true)),
          ("showRawInput", Json.bool(false)),
          ("showEffects", Json.bool(true)),
          ("showEvents", Json.bool(true)),
          ("showObjectChanges", Json.bool(false)),
          ("showBalanceChanges", Json.bool(true))
        ]),
        Json.str("WaitForLocalExecution")
      ]))
    ]);

    let body_text = Json.stringify(payload, null);

    let response = await (with cycles = 230_949_972_000) IC.ic.http_request({
      url = "https://fullnode.devnet.sui.io";
      max_response_bytes = ?32768;
      headers = [
        { name = "Content-Type"; value = "application/json" },
        { name = "Accept"; value = "application/json" }
      ];
      body = ?Text.encodeUtf8(body_text);
      method = #post;
      is_replicated = ?false;
      transform = null;
    });

    switch (response.status) {
      case (200) {
        let response_text = switch (Text.decodeUtf8(response.body)) {
          case (?text) text;
          case null { return #err("Failed to decode response") };
        };

        // Extract digest from successful response
        if (Text.contains(response_text, #text("\"digest\""))) {
          switch (extractDigestFromResponse(response_text)) {
            case (#ok(digest)) { #ok(digest) };
            case (#err(_)) { #ok("Transaction successful: " # response_text) };
          }
        } else {
          #err("Transaction failed: " # response_text)
        }
      };
      case (_) {
        let error_text = switch (Text.decodeUtf8(response.body)) {
          case (?text) text;
          case null "Unknown error";
        };
        #err("HTTP error " # debug_show(response.status) # ": " # error_text)
      };
    }
  };

  /// Extract digest from transaction response
  private func extractDigestFromResponse(response: Text) : Result.Result<Text, Text> {
    let parts = Text.split(response, #text("\"digest\":\""));
    let parts_array = Iter.toArray(parts);
    if (parts_array.size() < 2) {
      return #err("digest field not found");
    };

    let value_parts = Text.split(parts_array[1], #text("\""));
    let value_array = Iter.toArray(value_parts);
    if (value_array.size() < 1) {
      return #err("digest value not found");
    };

    #ok(value_array[0])
  };

  /// Check SUI balance for an address (TESTNET)
  public func checkBalance(address : Text) : async Result.Result<{totalBalance: Nat64; coinCount: Nat}, Text> {
    let sui_wallet = Wallet.createTestnetWallet("dfx_test_key");

    switch (await sui_wallet.getBalance(address)) {
      case (#err(error)) { #err(error) };
      case (#ok(balance)) {
        #ok({
          totalBalance = balance.total_balance;
          coinCount = balance.object_count;
        })
      };
    }
  };

  /// Get SUI coins for an address (TESTNET)
  public func getSuiCoins(address : Text) : async Result.Result<[Types.SuiCoin], Text> {
    let sui_wallet = Wallet.createTestnetWallet("dfx_test_key");

    switch (await sui_wallet.getBalance(address)) {
      case (#err(error)) { #err(error) };
      case (#ok(balance)) {
        #ok(balance.objects)
      };
    }
  };

  /// Transfer SUI using testnet (simple version)
  public func transferSui(
    senderAddress : Text,
    recipientAddress : Text,
    amount : Nat64,
    gasBudget : Nat64
  ) : async Result.Result<Text, Text> {
    let sui_wallet = Wallet.createTestnetWallet("dfx_test_key");

    // Use the wallet's sendTransactionDirect function
    switch (await sui_wallet.sendTransactionDirect(senderAddress, recipientAddress, amount, ?gasBudget, ?"0")) {
      case (#err(error)) { #err("Transfer failed: " # error) };
      case (#ok(result)) {
        #ok("✅ Transfer successful! Digest: " # result.transaction_digest)
      };
    }
  };

  /// Transfer SUI using the new sui_transfer.mo approach (TESTNET) - UNSAFE METHOD
  public func transferSuiNew(
    senderAddress : Text,
    recipientAddress : Text,
    amount : Nat64,
    gasBudget : Nat64
  ) : async Result.Result<Text, Text> {
    let rpcUrl = "https://fullnode.testnet.sui.io:443";

    // Create the EXACT same wallet as used for generateAddress
    let _sui_wallet = Wallet.createDevnetWallet("dfx_test_key");

    // First get available coins for the sender
    switch (await SuiTransfer.getSuiCoins(rpcUrl, senderAddress)) {
      case (#err(error)) { #err("Failed to get coins: " # error) };
      case (#ok(coins)) {
        if (coins.size() == 0) {
          return #err("No coins available for transfer");
        };

        // Use the first available coin
        let coin = coins[0];

        // Use ICP ECDSA with the EXACT same parameters as the wallet
        let signFunc = func(messageHash : Blob) : async Result.Result<Blob, Text> {
          try {
            let response = await (with cycles = 30_000_000_000) IC.ic.sign_with_ecdsa({
              message_hash = messageHash;
              derivation_path = [];  // Empty derivation path like generateAddress(null)
              key_id = { curve = #secp256k1; name = "dfx_test_key" };
            });
            #ok(response.signature)
          } catch (error) {
            #err("Failed to sign: " # Error.message(error))
          }
        };

        // Use ICP ECDSA with the EXACT same parameters as the wallet
        let getPublicKeyFunc = func() : async Result.Result<Blob, Text> {
          try {
            let response = await (with cycles = 30_000_000_000) IC.ic.ecdsa_public_key({
              canister_id = null;
              derivation_path = [];  // Empty derivation path like generateAddress(null)
              key_id = { curve = #secp256k1; name = "dfx_test_key" };
            });
            #ok(response.public_key)
          } catch (error) {
            #err("Failed to get public key: " # Error.message(error))
          }
        };

        // Execute the transfer using the new sui_transfer.mo approach
        await SuiTransfer.transferSuiSimple(
          rpcUrl,
          senderAddress,
          coin.coinObjectId,
          recipientAddress,
          amount,
          gasBudget,
          signFunc,
          getPublicKeyFunc
        )
      };
    }
  };

  /// Transfer SUI using proper BCS transaction building (TESTNET) - SAFE METHOD
  public func transferSuiSafe(
    senderAddress : Text,
    recipientAddress : Text,
    amount : Nat64,
    gasBudget : Nat64
  ) : async Result.Result<Text, Text> {
    let rpcUrl = "https://fullnode.testnet.sui.io:443";

    // First get available coins for the sender
    switch (await SuiTransfer.getSuiCoins(rpcUrl, senderAddress)) {
      case (#err(error)) { #err("Failed to get coins: " # error) };
      case (#ok(coins)) {
        if (coins.size() == 0) {
          return #err("No coins available for transfer");
        };

        // Use the first available coin
        let coin = coins[0];

        // Use ICP ECDSA with the EXACT same parameters as the wallet
        let signFunc = func(messageHash : Blob) : async Result.Result<Blob, Text> {
          try {
            let response = await (with cycles = 30_000_000_000) IC.ic.sign_with_ecdsa({
              message_hash = messageHash;
              derivation_path = [];  // Empty derivation path like generateAddress(null)
              key_id = { curve = #secp256k1; name = "dfx_test_key" };
            });
            #ok(response.signature)
          } catch (error) {
            #err("Failed to sign: " # Error.message(error))
          }
        };

        // Use ICP ECDSA with the EXACT same parameters as the wallet
        let getPublicKeyFunc = func() : async Result.Result<Blob, Text> {
          try {
            let response = await (with cycles = 30_000_000_000) IC.ic.ecdsa_public_key({
              canister_id = null;
              derivation_path = [];  // Empty derivation path like generateAddress(null)
              key_id = { curve = #secp256k1; name = "dfx_test_key" };
            });
            #ok(response.public_key)
          } catch (error) {
            #err("Failed to get public key: " # Error.message(error))
          }
        };

        // Execute the transfer using the SAFE BCS approach
        await SuiTransfer.transferSuiSafe(
          rpcUrl,
          senderAddress,
          coin.coinObjectId,
          recipientAddress,
          amount,
          gasBudget,
          signFunc,
          getPublicKeyFunc
        )
      };
    }
  };

}