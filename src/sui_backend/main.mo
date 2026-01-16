import Lib "../lib";
import Types "../types";
import Address "../address";
import Transaction "../transaction";
import Utils "../utils";
import SuiTransfer "../sui_transfer";
import Array "mo:base/Array";
import Text "mo:base/Text";
import Nat8 "mo:base/Nat8";
import Nat32 "mo:base/Nat32";
import Nat64 "mo:base/Nat64";
import Char "mo:base/Char";
import Iter "mo:base/Iter";
import Blob "mo:base/Blob";
import Result "mo:base/Result";
import Debug "mo:base/Debug";
import Error "mo:base/Error";
import IC "mo:ic";

persistent actor {
  public query func greet(name : Text) : async Text {
    return "Hello, " # name # "!";
  };

  // Test the SUI library
  public query func testAdd(x : Nat, y : Nat) : async Nat {
    Lib.add(x, y)
  };

  // Validate SUI address
  public query func validateSuiAddress(address : Text) : async Bool {
    Address.isValidAddress(address)
  };

  // Create a sample transaction
  public query func createSampleTransaction(sender : Text) : async ?Types.TransactionData {
    let gasData : Types.GasData = {
      payment = [];
      owner = sender;
      price = 1000;
      budget = 10000;
    };

    let txData = Transaction.createTransferTransaction(
      sender,
      "0x0000000000000000000000000000000000000000000000000000000000000001",
      [],
      gasData
    );

    ?txData
  };

  // Get library info
  public query func getLibraryInfo() : async {version: Text; description: Text} {
    {
      version = Lib.version;
      description = Lib.description;
    }
  };

  // Test utility functions
  public query func testUtilities(text : Text) : async Text {
    Utils.toUpperCase(text)
  };

  // SUI Transfer function using the working implementation approach
  public func transferSui(
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

        // Create signing function using ICP ECDSA
        let signFunc = func(messageHash : Blob) : async Result.Result<Blob, Text> {
          try {
            let response = await (with cycles = 30_000_000_000) IC.ic.sign_with_ecdsa({
              message_hash = messageHash;
              derivation_path = [Text.encodeUtf8("0")];
              key_id = { curve = #secp256k1; name = "test_key_1" };
            });
            #ok(response.signature)
          } catch (error) {
            #err("Failed to sign: " # Error.message(error))
          }
        };

        // Create public key function
        let getPublicKeyFunc = func() : async Result.Result<Blob, Text> {
          try {
            let response = await (with cycles = 30_000_000_000) IC.ic.ecdsa_public_key({
              canister_id = null;
              derivation_path = [Text.encodeUtf8("0")];
              key_id = { curve = #secp256k1; name = "test_key_1" };
            });
            #ok(response.public_key)
          } catch (error) {
            #err("Failed to get public key: " # Error.message(error))
          }
        };

        // Execute the transfer using the working implementation's approach
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

  // Get SUI coins for an address
  public func getSuiCoins(address : Text) : async Result.Result<[SuiTransfer.SuiCoin], Text> {
    let rpcUrl = "https://fullnode.testnet.sui.io:443";
    await SuiTransfer.getSuiCoins(rpcUrl, address)
  };

  // Generate a SUI address using ICP ECDSA
  public func generateSuiAddress(derivationPath : ?Text) : async Result.Result<Text, Text> {
    let path = switch (derivationPath) {
      case (null) { "0" };
      case (?p) { p };
    };

    try {
      // Generate public key using ICP's threshold ECDSA
      let pk_result = await (with cycles = 30_000_000_000) IC.ic.ecdsa_public_key({
        canister_id = null;
        derivation_path = [Text.encodeUtf8(path)];
        key_id = { name = "test_key_1"; curve = #secp256k1 };
      });

      let public_key_bytes = Blob.toArray(pk_result.public_key);

      // Convert to SUI address using secp256k1 scheme
      switch (Address.publicKeyToAddress(public_key_bytes, #Secp256k1)) {
        case (#err(error)) { #err("Failed to generate SUI address: " # error) };
        case (#ok(sui_address)) { #ok(sui_address) };
      };
    } catch (error) {
      #err("ECDSA key generation failed: " # Error.message(error))
    };
  };

  // Check SUI balance for an address
  public func checkBalance(address : Text) : async Result.Result<{totalBalance: Nat64; coinCount: Nat}, Text> {
    switch (await getSuiCoins(address)) {
      case (#err(error)) { #err(error) };
      case (#ok(coins)) {
        var total : Nat64 = 0;
        for (coin in coins.vals()) {
          // Parse balance string to Nat64
          var balance : Nat64 = 0;
          for (c in coin.balance.chars()) {
            if (c >= '0' and c <= '9') {
              let digit = Nat64.fromNat(Nat32.toNat(Char.toNat32(c) - Char.toNat32('0')));
              balance := balance * 10 + digit;
            };
          };
          total := total + balance;
        };
        #ok({
          totalBalance = total;
          coinCount = coins.size();
        })
      };
    }
  };

  // Test BCS serialization of corrected transaction format
  public query func testTransactionSerialization(sender : Text) : async Text {
    let gasData : Types.GasData = {
      payment = [];
      owner = sender;
      price = 1000;
      budget = 10000;
    };

    let txData = Transaction.createTransferTransaction(
      sender,
      "0x0000000000000000000000000000000000000000000000000000000000000001",
      [],
      gasData
    );

    // Serialize the transaction with corrected BCS format
    let serialized = Transaction.serializeTransaction(txData);

    // Convert to hex string for display
    func toHex(b: Nat8) : Text {
      let chars = ['0','1','2','3','4','5','6','7','8','9','a','b','c','d','e','f'];
      let high = Nat8.toNat(b / 16);
      let low = Nat8.toNat(b % 16);
      Char.toText(chars[high]) # Char.toText(chars[low])
    };

    let hexBytes = Array.map<Nat8, Text>(serialized, toHex);

    "BCS Serialized (hex): " # Text.join("", hexBytes.vals())
  };

  /*
  // Test sending a transaction to SUI devnet with corrected BCS format
  public func sendTestTransaction(sender : Text) : async Text {
    let gasData : Types.GasData = {
      payment = [];
      owner = sender;
      price = 1000;
      budget = 10000;
    };

    let txData = Transaction.createTransferTransaction(
      sender,
      "0x0000000000000000000000000000000000000000000000000000000000000001",
      [],
      gasData
    );

    // Serialize with corrected BCS format
    let serialized = Transaction.serializeTransaction(txData);
    let tx_bytes_b64 = Base64.encode(serialized);

    // For testing, use a dummy signature (in real use, this would be signed with private key)
    let dummy_signature = "AQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAo=";

    let body_text = "{
      \"jsonrpc\": \"2.0\",
      \"id\": \"1\",
      \"method\": \"sui_executeTransactionBlock\",
      \"params\": [
        \"" # tx_bytes_b64 # "\",
        [\"" # dummy_signature # "\"],
        {
          \"showInput\": true,
          \"showRawInput\": false,
          \"showEffects\": true,
          \"showEvents\": true,
          \"showObjectChanges\": false,
          \"showBalanceChanges\": true
        },
        \"WaitForLocalExecution\"
      ]
    }";

    Debug.print("Sending transaction with corrected BCS format: " # body_text);

    try {
      let response = await (with cycles = 230_949_972_000) IC.ic.http_request({
        url = "https://fullnode.testnet.sui.io";
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
        case null "Failed to decode response";
      };

      "Response: " # response_text
    } catch (error) {
      "Error: " # debug_show(error)
    }
  };
  */
};
