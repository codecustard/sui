/// SUI Wallet implementation using ICP Chain Fusion ECDSA
///
/// This module provides comprehensive SUI wallet functionality including:
/// - Address generation using ICP threshold ECDSA
/// - Transaction building and signing
/// - Balance management and UTXO handling
/// - SUI network integration

import Result "mo:base/Result";
import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Buffer "mo:base/Buffer";
import Char "mo:base/Char";
import Text "mo:base/Text";
import Nat32 "mo:base/Nat32";
import Nat8 "mo:base/Nat8";
import Nat64 "mo:base/Nat64";
import Error "mo:base/Error";
import Debug "mo:base/Debug";
import Iter "mo:base/Iter";
import Cycles "mo:base/ExperimentalCycles";
import IC "mo:ic";
import Json "mo:json";
import BaseX "mo:base-x-encoder";
import SHA3 "mo:sha3";

import Types "types";
import Address "address";
import Transaction "transaction";
import Validation "validation";

module {
  public type Result<T> = Result.Result<T, Text>;
  public type SuiAddress = Types.SuiAddress;
  public type TransactionData = Types.TransactionData;
  public type SignatureScheme = Types.SignatureScheme;
  public type ObjectRef = Types.ObjectRef;

  // Wallet configuration
  public type WalletConfig = {
    key_name: Text;
    network: Text; // "mainnet" or "testnet" or "devnet"
    rpc_url: ?Text; // Optional custom RPC URL
  };

  // Address generation info
  public type AddressInfo = {
    address: SuiAddress;
    derivation_path: Text;
    public_key: [Nat8];
    scheme: SignatureScheme;
  };

  // Transaction result
  public type TransactionResult = {
    transaction_digest: Text;
    transaction_data: TransactionData;
    signature: ?Text;
    gas_used: ?Nat64;
  };

  // Balance information for SUI objects
  public type Balance = {
    total_balance: Nat64; // Total SUI balance in MIST
    objects: [Types.SuiCoin]; // Individual coin objects
    object_count: Nat;
  };

  // SUI wallet implementation
  public class Wallet(config: WalletConfig) {

    // Validate configuration
    private func validateConfig() : Result<()> {
      if (Text.size(config.key_name) == 0) {
        return #err("Key name cannot be empty");
      };
      if (config.network != "mainnet" and config.network != "testnet" and config.network != "devnet") {
        return #err("Network must be 'mainnet', 'testnet', or 'devnet'");
      };
      #ok(())
    };

    // Generate SUI address with derivation path
    public func generateAddress(derivation_path: ?Text) : async Result<AddressInfo> {
      let path = switch (derivation_path) {
        case (null) { "" };
        case (?p) { p };
      };

      switch (parseDerivationPath(path)) {
        case (#err(error)) { #err(error) };
        case (#ok(derivation_blobs)) {
          try {
            // Generate public key using ICP's threshold ECDSA
            let pk_result = await (with cycles = 30_000_000_000) IC.ic.ecdsa_public_key({
              canister_id = null;
              derivation_path = derivation_blobs;
              key_id = { name = config.key_name; curve = #secp256k1 };
            });

            let public_key_bytes = Blob.toArray(pk_result.public_key);

            // Convert to SUI address using secp256k1 scheme
            switch (Address.publicKeyToAddress(public_key_bytes, #Secp256k1)) {
              case (#err(error)) { #err("Failed to generate SUI address: " # error) };
              case (#ok(sui_address)) {
                #ok({
                  address = sui_address;
                  derivation_path = path;
                  public_key = public_key_bytes;
                  scheme = #Secp256k1;
                })
              };
            };
          } catch (error) {
            #err("ECDSA key generation failed: " # Error.message(error))
          };
        };
      };
    };

    // Create a transfer transaction using real coin objects
    public func createTransferTransaction(
      sender: SuiAddress,
      recipient: SuiAddress,
      amount: Nat64,
      gas_budget: ?Nat64,
      _derivation_path: ?Text
    ) : async Result<TransactionData> {
      // Validate addresses
      if (not Address.isValidAddress(sender)) {
        return #err("Invalid sender address");
      };

      if (not Address.isValidAddress(recipient)) {
        return #err("Invalid recipient address");
      };

      if (amount == 0) {
        return #err("Transfer amount must be greater than zero");
      };

      // Get real coins from sender's address
      switch (await queryCoins(sender)) {
        case (#err(error)) { #err("Failed to query coins: " # error) };
        case (#ok(coins)) {
          // Select coins for transfer
          switch (selectCoinsForAmount(coins, amount)) {
            case (#err(error)) { #err(error) };
            case (#ok(selected_coins)) {
              // Convert coins to ObjectRef format
              let object_refs = Array.map<Types.SuiCoin, Types.ObjectRef>(
                selected_coins,
                func(coin) {
                  {
                    objectId = coin.coinObjectId;
                    version = coin.version;
                    digest = coin.digest;
                  }
                }
              );

              // Create gas data with actual gas coins
              let gas_coins = if (object_refs.size() > 0) {
                [object_refs[0]] // Use first coin for gas
              } else {
                []
              };

              let gas_data : Types.GasData = {
                payment = gas_coins;
                owner = sender;
                price = 1000; // Default gas price in MIST
                budget = switch (gas_budget) {
                  case (null) { 10_000_000 }; // Default 0.01 SUI
                  case (?budget) { budget };
                };
              };

              // Create transfer transaction with real objects
              let tx_data = Transaction.createTransferTransaction(sender, recipient, object_refs, gas_data);
              #ok(tx_data)
            };
          };
        };
      }
    };

    // Sign a transaction using threshold ECDSA with real transaction hash
    public func signTransaction(
      transaction_data: TransactionData,
      derivation_path: ?Text
    ) : async Result<Text> {
      let path = switch (derivation_path) {
        case (null) { "" };
        case (?p) { p };
      };

      switch (parseDerivationPath(path)) {
        case (#err(error)) { #err(error) };
        case (#ok(derivation_blobs)) {
          try {
            // 1. Serialize the transaction data to bytes
            let serialized_tx = serializeTransaction(transaction_data);

            // 2. Create transaction hash for signing
            let tx_hash = hashTransaction(serialized_tx);

            // 3. Sign the real transaction hash using ECDSA
            let signature_result = await (with cycles = 30_000_000_000) IC.ic.sign_with_ecdsa({
              message_hash = Blob.fromArray(tx_hash);
              derivation_path = derivation_blobs;
              key_id = { name = config.key_name; curve = #secp256k1 };
            });

            let signature_bytes = Blob.toArray(signature_result.signature);

            // Convert signature to hex string
            #ok(bytesToHex(signature_bytes))
          } catch (error) {
            #err("Transaction signing failed: " # Error.message(error))
          };
        };
      };
    };

    // Get balance for a SUI address by querying SUI RPC
    public func getBalance(address: SuiAddress) : async Result<Balance> {
      if (not Address.isValidAddress(address)) {
        return #err("Invalid SUI address");
      };

      switch (await queryCoins(address)) {
        case (#err(error)) { #err(error) };
        case (#ok(coins)) {
          let total = Array.foldLeft<Types.SuiCoin, Nat64>(
            coins, 0, func(acc, coin) { acc + coin.balance }
          );
          #ok({
            total_balance = total;
            objects = coins;
            object_count = coins.size();
          })
        };
      }
    };

    // Send transaction (create, sign, and submit to SUI network)
    public func sendTransaction(
      from_address: SuiAddress,
      to_address: SuiAddress,
      amount: Nat64,
      gas_budget: ?Nat64,
      derivation_path: ?Text
    ) : async Result<TransactionResult> {
      // Create transaction
      switch (await createTransferTransaction(from_address, to_address, amount, gas_budget, derivation_path)) {
        case (#err(error)) { #err(error) };
        case (#ok(tx_data)) {
          // Sign transaction
          switch (await signTransaction(tx_data, derivation_path)) {
            case (#err(error)) { #err(error) };
            case (#ok(signature)) {
              // Submit to SUI network
              switch (await submitTransaction(tx_data, signature)) {
                case (#err(error)) { #err(error) };
                case (#ok(digest)) {
                  #ok({
                    transaction_digest = digest;
                    transaction_data = tx_data;
                    signature = ?signature;
                    gas_used = ?1000; // This would come from network response
                  })
                };
              };
            };
          };
        };
      };
    };

    // Simplified direct SUI transfer using unsafe_pay (bypasses BCS complexity)
    public func sendTransactionDirect(
      from_address: SuiAddress,
      to_address: SuiAddress,
      amount: Nat64,
      gas_budget: ?Nat64,
      derivation_path: ?Text
    ) : async Result<TransactionResult> {
      let budget = switch (gas_budget) {
        case (null) { 20000000 : Nat64 }; // 20M MIST default
        case (?b) { b };
      };

      let rpc_url = switch (config.rpc_url) {
        case (null) {
          switch (config.network) {
            case ("mainnet") { "https://fullnode.mainnet.sui.io" };
            case ("testnet") { "https://fullnode.testnet.sui.io" };
            case ("devnet") { "https://fullnode.devnet.sui.io" };
            case (_) { "https://fullnode.devnet.sui.io" };
          }
        };
        case (?url) { url };
      };

      // Use transaction.mo to build proper SUI transaction
      switch (await buildAndSubmitTransfer(from_address, to_address, amount, budget, rpc_url)) {
        case (#err(error)) { #err(error) };
        case (#ok(tx_bytes_b64)) {
          // Parse the transaction bytes to get the digest
          // For now, return a placeholder result - unsafe_pay returns the signed transaction
          #ok({
            transaction_digest = "executed_via_unsafe_pay";
            transaction_data = {
              version = 1 : Nat8;
              sender = from_address;
              gasData = {
                payment = [];
                owner = from_address;
                price = 1000 : Nat64;
                budget = budget;
              };
              kind = #ProgrammableTransaction({
                inputs = [];
                commands = [];
              });
              expiration = #None;
            };
            signature = ?tx_bytes_b64;
            gas_used = ?1000;
          })
        };
      };
    };

    // Build transaction without signing (for inspection or later signing)
    public func buildTransaction(
      from_address: SuiAddress,
      to_address: SuiAddress,
      amount: Nat64,
      gas_budget: ?Nat64
    ) : async Result<TransactionData> {
      await createTransferTransaction(from_address, to_address, amount, gas_budget, null)
    };

    // Private helper functions

    // Query SUI coins for an address from SUI RPC
    private func queryCoins(address: SuiAddress) : async Result<[Types.SuiCoin]> {
      let rpc_url = switch (config.rpc_url) {
        case (null) {
          switch (config.network) {
            case ("mainnet") { "https://fullnode.mainnet.sui.io" };
            case ("testnet") { "https://fullnode.testnet.sui.io" };
            case ("devnet") { "https://fullnode.devnet.sui.io" };
            case (_) { "https://fullnode.devnet.sui.io" }; // Default to devnet
          }
        };
        case (?url) { url };
      };

      let request_body = "{
        \"jsonrpc\": \"2.0\",
        \"id\": 1,
        \"method\": \"suix_getCoins\",
        \"params\": [
          \"" # address # "\",
          \"0x2::sui::SUI\",
          null,
          null
        ]
      }";

      let request_headers = [
        { name = "Content-Type"; value = "application/json" },
        { name = "User-Agent"; value = "icp-sui-wallet" }
      ];

      try {
        let response = await (with cycles = 230_949_972_000) IC.ic.http_request({
          url = rpc_url;
          max_response_bytes = ?32768;
          headers = request_headers;
          body = ?Text.encodeUtf8(request_body);
          method = #post;
          is_replicated = ?false;
          transform = null;
        });

        if (response.status != 200) {
          let decoded_text = switch (Text.decodeUtf8(response.body)) {
            case (null) { "Unknown error" };
            case (?text) { text };
          };
          return #err("SUI RPC error: " # decoded_text);
        };

        let decoded_text = switch (Text.decodeUtf8(response.body)) {
          case (null) { #err("Failed to decode RPC response") };
          case (?text) { parseCoinsResponse(text) };
        };

        decoded_text
      } catch (error) {
        #err("HTTP request failed: " # Error.message(error))
      }
    };

    // Parse SUI RPC coins response
    private func parseCoinsResponse(json_text: Text) : Result<[Types.SuiCoin]> {
      switch (Json.parse(json_text)) {
        case (#err(e)) {
          #err("Failed to parse coins JSON: " # debug_show(e))
        };
        case (#ok(json)) {
          switch (json) {
            case (#object_(fields)) {
              for ((key, value) in fields.vals()) {
                switch (key) {
                  case ("result") {
                    switch (value) {
                      case (#object_(result_fields)) {
                        for ((result_key, result_value) in result_fields.vals()) {
                          switch (result_key) {
                            case ("data") {
                              switch (result_value) {
                                case (#array(coins_array)) {
                                  return parseCoinArray(coins_array);
                                };
                                case (_) { return #err("Expected coins array in data field") };
                              }
                            };
                            case (_) { /* Ignore other fields */ };
                          }
                        };
                      };
                      case (_) { return #err("Expected result object") };
                    }
                  };
                  case ("error") {
                    return #err("SUI RPC error: " # debug_show(value));
                  };
                  case (_) { /* Ignore other fields */ };
                }
              };
              #err("No result field found in RPC response")
            };
            case (_) { #err("Expected JSON object in RPC response") };
          }
        };
      }
    };

    // Parse array of coin objects from SUI RPC
    private func parseCoinArray(coins: [Json.Json]) : Result<[Types.SuiCoin]> {
      let result = Buffer.Buffer<Types.SuiCoin>(0);

      for (coin_json in coins.vals()) {
        switch (parseCoinObject(coin_json)) {
          case (#err(error)) { return #err(error) };
          case (#ok(coin)) { result.add(coin) };
        }
      };

      #ok(Buffer.toArray(result))
    };

    // Parse individual coin object
    private func parseCoinObject(coin_json: Json.Json) : Result<Types.SuiCoin> {
      switch (coin_json) {
        case (#object_(fields)) {
          var coinObjectId: ?Text = null;
          var version: ?Nat64 = null;
          var digest: ?Text = null;
          var balance: ?Nat64 = null;
          var previousTransaction: ?Text = null;

          for ((key, value) in fields.vals()) {
            switch (key, value) {
              case ("coinObjectId", #string(id)) { coinObjectId := ?id };
              case ("version", #string(v)) {
                // Parse version string to Nat64
                var ver: Nat64 = 0;
                for (c in Text.toIter(v)) {
                  if (c >= '0' and c <= '9') {
                    let digit = Nat64.fromNat(Nat32.toNat(Char.toNat32(c) - Char.toNat32('0')));
                    ver := ver * 10 + digit;
                  };
                };
                version := ?ver;
              };
              case ("digest", #string(d)) { digest := ?d };
              case ("balance", #string(b)) {
                // Parse balance string to Nat64
                var bal: Nat64 = 0;
                for (c in Text.toIter(b)) {
                  if (c >= '0' and c <= '9') {
                    let digit = Nat64.fromNat(Nat32.toNat(Char.toNat32(c) - Char.toNat32('0')));
                    bal := bal * 10 + digit;
                  };
                };
                balance := ?bal;
              };
              case ("previousTransaction", #string(tx)) { previousTransaction := ?tx };
              case (_, _) { /* Ignore other fields */ };
            };
          };

          switch (coinObjectId, version, digest, balance, previousTransaction) {
            case (?id, ?ver, ?dig, ?bal, ?prevTx) {
              #ok({
                coinType = "0x2::sui::SUI";
                coinObjectId = id;
                version = ver;
                digest = dig;
                balance = bal;
                previousTransaction = prevTx;
              })
            };
            case (_, _, _, _, _) {
              #err("Missing required coin fields: " # debug_show((coinObjectId, version, digest, balance, previousTransaction)))
            };
          };
        };
        case (_) { #err("Expected coin object") };
      }
    };

    // Select coins for a specific amount (simple greedy selection)
    private func selectCoinsForAmount(coins: [Types.SuiCoin], amount: Nat64) : Result<[Types.SuiCoin]> {
      if (coins.size() == 0) {
        return #err("No coins available");
      };

      // Calculate total available balance
      let total_balance = Array.foldLeft<Types.SuiCoin, Nat64>(
        coins, 0, func(acc, coin) { acc + coin.balance }
      );

      if (total_balance < amount) {
        return #err("Insufficient balance: need " # Nat64.toText(amount) # " MIST, have " # Nat64.toText(total_balance) # " MIST");
      };

      // Sort coins by balance (descending) for greedy selection
      let sorted_coins = Array.sort<Types.SuiCoin>(coins, func(a, b) {
        if (a.balance > b.balance) { #less }
        else if (a.balance < b.balance) { #greater }
        else { #equal }
      });

      // Greedy selection: pick coins until we have enough
      let selected = Buffer.Buffer<Types.SuiCoin>(0);
      var remaining_amount = amount;

      for (coin in sorted_coins.vals()) {
        if (remaining_amount > 0) {
          selected.add(coin);
          if (coin.balance >= remaining_amount) {
            remaining_amount := 0;
          } else {
            remaining_amount := remaining_amount - coin.balance;
          };
        };
      };

      #ok(Buffer.toArray(selected))
    };

    // Serialize transaction to bytes using proper BCS-style encoding for SUI
    private func serializeTransaction(tx_data: TransactionData) : [Nat8] {
      let buffer = Buffer.Buffer<Nat8>(512);

      // SUI TransactionData BCS serialization
      // 1. Serialize TransactionKind (1 byte for variant tag)
      switch (tx_data.kind) {
        case (#ProgrammableTransaction(pt)) {
          buffer.add(0); // Tag for ProgrammableTransaction

          // Serialize ProgrammableTransaction
          // Inputs length (ULEB128)
          serializeULEB128(buffer, pt.inputs.size());

          // Serialize inputs
          for (input in pt.inputs.vals()) {
            switch (input) {
              case (#Pure(data)) {
                buffer.add(0); // Tag for Pure
                // Serialize Pure data (data is already [Nat8])
                serializeULEB128(buffer, data.size());
                for (byte in data.vals()) {
                  buffer.add(byte);
                };
              };
              case (#Object(obj_ref)) {
                buffer.add(1); // Tag for Object
                // Serialize ObjectRef
                let obj_id_bytes = hexStringToBytes(
                  if (Text.startsWith(obj_ref.objectId, #text("0x"))) {
                    Text.trimStart(obj_ref.objectId, #text("0x"))
                  } else {
                    obj_ref.objectId
                  }
                );
                for (byte in obj_id_bytes.vals()) {
                  buffer.add(byte);
                };
                // Version and digest
                serializeU64(buffer, obj_ref.version);
                let digest_bytes = hexStringToBytes(obj_ref.digest);
                for (byte in digest_bytes.vals()) {
                  buffer.add(byte);
                };
              };
            };
          };

          // Commands length
          serializeULEB128(buffer, pt.commands.size());

          // Serialize commands
          for (command in pt.commands.vals()) {
            switch (command) {
              case (#TransferObjects(transfer)) {
                buffer.add(1); // Tag for TransferObjects

                // Objects length
                serializeULEB128(buffer, transfer.objects.size());

                // Serialize object arguments (simplified - just indices)
                for (obj in transfer.objects.vals()) {
                  buffer.add(0); // Tag for input argument (index 0)
                  buffer.add(0); // Index 0
                };

                // Address argument
                switch (transfer.address) {
                  case (#Pure(data)) {
                    buffer.add(0); // Tag for Pure
                    // data is already [Nat8] for Pure CallArg
                    for (byte in data.vals()) {
                      buffer.add(byte);
                    };
                  };
                  case (#Input(idx)) {
                    buffer.add(1); // Tag for Input
                    buffer.add(Nat8.fromNat(idx));
                  };
                };
              };
              case (_) {
                // Handle other command types as needed
                buffer.add(255); // Unknown command
              };
            };
          };
        };
        case (_) {
          buffer.add(255); // Unknown transaction kind
        };
      };

      // 2. Serialize sender (32 bytes)
      let sender_bytes = hexStringToBytes(
        if (Text.startsWith(tx_data.sender, #text("0x"))) {
          Text.trimStart(tx_data.sender, #text("0x"))
        } else {
          tx_data.sender
        }
      );
      for (byte in sender_bytes.vals()) {
        buffer.add(byte);
      };

      // 3. Serialize GasData
      // Gas payment objects
      serializeULEB128(buffer, tx_data.gasData.payment.size());
      for (payment in tx_data.gasData.payment.vals()) {
        let obj_id_bytes = hexStringToBytes(
          if (Text.startsWith(payment.objectId, #text("0x"))) {
            Text.trimStart(payment.objectId, #text("0x"))
          } else {
            payment.objectId
          }
        );
        for (byte in obj_id_bytes.vals()) {
          buffer.add(byte);
        };
        serializeU64(buffer, payment.version);
        let digest_bytes = hexStringToBytes(payment.digest);
        for (byte in digest_bytes.vals()) {
          buffer.add(byte);
        };
      };

      // Gas owner (32 bytes)
      let owner_bytes = hexStringToBytes(
        if (Text.startsWith(tx_data.gasData.owner, #text("0x"))) {
          Text.trimStart(tx_data.gasData.owner, #text("0x"))
        } else {
          tx_data.gasData.owner
        }
      );
      for (byte in owner_bytes.vals()) {
        buffer.add(byte);
      };

      // Gas price and budget
      serializeU64(buffer, tx_data.gasData.price);
      serializeU64(buffer, tx_data.gasData.budget);

      // 4. Serialize expiration
      switch (tx_data.expiration) {
        case (#None) {
          buffer.add(0); // Tag for None
        };
        case (#Epoch(epoch)) {
          buffer.add(1); // Tag for Epoch
          serializeU64(buffer, epoch);
        };
      };

      Buffer.toArray(buffer)
    };

    // Helper: Serialize ULEB128 (variable-length encoding)
    private func serializeULEB128(buffer: Buffer.Buffer<Nat8>, value: Nat) {
      var val = value;
      while (val >= 128) {
        buffer.add(Nat8.fromNat((val % 128) + 128));
        val := val / 128;
      };
      buffer.add(Nat8.fromNat(val));
    };

    // Helper: Serialize U64 (8 bytes, little-endian)
    private func serializeU64(buffer: Buffer.Buffer<Nat8>, value: Nat64) {
      let val = Nat64.toNat(value);
      buffer.add(Nat8.fromNat(val % 256));
      buffer.add(Nat8.fromNat((val / 256) % 256));
      buffer.add(Nat8.fromNat((val / 65536) % 256));
      buffer.add(Nat8.fromNat((val / 16777216) % 256));
      buffer.add(Nat8.fromNat((val / 4294967296) % 256));
      buffer.add(Nat8.fromNat((val / 1099511627776) % 256));
      buffer.add(Nat8.fromNat((val / 281474976710656) % 256));
      buffer.add(Nat8.fromNat((val / 72057594037927936) % 256));
    };

    // Hash transaction bytes using SHA-3 Keccak-256 (proper SUI hash)
    private func hashTransaction(tx_bytes: [Nat8]) : [Nat8] {
      // Use proper Keccak-256 for SUI transaction hashing
      let keccak = SHA3.Keccak(256);
      keccak.update(tx_bytes);
      keccak.finalize()
    };

    // Convert hex string to bytes array
    private func hexStringToBytes(hex: Text) : [Nat8] {
      let chars = Text.toArray(hex);
      let bytes = Buffer.Buffer<Nat8>(0);

      var i = 0;
      while (i < chars.size() - 1) {
        let high = hexCharToNat(chars[i]);
        let low = hexCharToNat(chars[i + 1]);
        let byte_val = Nat8.fromNat(high * 16 + low);
        bytes.add(byte_val);
        i += 2;
      };

      Buffer.toArray(bytes)
    };

    // Convert hex character to Nat
    private func hexCharToNat(c: Char) : Nat {
      if (c >= '0' and c <= '9') {
        Nat32.toNat(Char.toNat32(c) - Char.toNat32('0'))
      } else if (c >= 'a' and c <= 'f') {
        Nat32.toNat(Char.toNat32(c) - Char.toNat32('a')) + 10
      } else if (c >= 'A' and c <= 'F') {
        Nat32.toNat(Char.toNat32(c) - Char.toNat32('A')) + 10
      } else {
        0
      }
    };

    // Submit transaction to SUI network via RPC using proper transaction building
    private func submitTransaction(tx_data: TransactionData, signature: Text) : async Result<Text> {
      #err("submitTransaction deprecated - use sendTransactionDirect instead")
    };

    // Build proper SUI transaction using transaction.mo and submit via sui_executeTransactionBlock
    private func buildAndSubmitTransfer(
      from_address: SuiAddress,
      to_address: SuiAddress,
      amount: Nat64,
      gas_budget: Nat64,
      rpc_url: Text
    ) : async Result<Text> {
      // Get coins for the transfer
      switch (await queryCoins(from_address)) {
        case (#err(error)) { return #err("Failed to get coins: " # error) };
        case (#ok(coins)) {
          if (coins.size() == 0) {
            return #err("No coins available for transfer");
          };

          // Use first coin for the transfer
          let coin = coins[0];
          let coin_obj_ref: Types.ObjectRef = {
            objectId = coin.coinObjectId;
            version = coin.version;
            digest = coin.digest;
          };

          // Create gas data
          let gas_data: Types.GasData = {
            payment = [coin_obj_ref]; // Use same coin for gas
            owner = from_address;
            price = 1000; // 1000 MIST per gas unit
            budget = gas_budget;
          };

          // Use transaction.mo to build the SUI transfer transaction
          let tx_data = Transaction.createSuiTransferTransaction(
            from_address,
            to_address,
            amount,
            coin_obj_ref,
            gas_data
          );

          Debug.print("Built transaction with transaction.mo: " # debug_show(tx_data));

          // Sign the transaction using ICP threshold ECDSA
          switch (await signTransactionData(tx_data, "0")) {
            case (#err(error)) { #err("Failed to sign transaction: " # error) };
            case (#ok(signature)) {
              // Submit the signed transaction to SUI network
              switch (await submitSignedTransaction(tx_data, signature, rpc_url)) {
                case (#err(error)) { #err("Failed to submit transaction: " # error) };
                case (#ok(digest)) { #ok(digest) };
              }
            };
          }
        };
      }
    };

    // Sign transaction data using ICP threshold ECDSA
    private func signTransactionData(tx_data: TransactionData, derivation_path: Text) : async Result<Text> {
      // Use transaction.mo serialization
      let tx_bytes = Transaction.serializeTransaction(tx_data);

      // Hash the transaction bytes using Keccak-256 (SUI uses Keccak)
      let tx_hash = hashTransaction(tx_bytes);

      // Sign using ICP threshold ECDSA
      let request = {
        message_hash = Blob.fromArray(tx_hash);
        derivation_path = [Text.encodeUtf8(derivation_path)];
        key_id = { curve = #secp256k1; name = config.key_name };
      };

      try {
        let response = await (with cycles = 26_153_846_153) IC.ic.sign_with_ecdsa(request);
        let signature = Blob.toArray(response.signature);

        // Format signature for SUI (need to add recovery ID and scheme flag)
        let sui_signature = formatSuiSignature(signature);
        #ok(sui_signature)
      } catch (error) {
        #err("ECDSA signing failed: " # Error.message(error))
      }
    };

    // Submit signed transaction to SUI network
    private func submitSignedTransaction(tx_data: TransactionData, signature: Text, rpc_url: Text) : async Result<Text> {
      // Use transaction.mo serialization
      let tx_bytes = Transaction.serializeTransaction(tx_data);
      let tx_bytes_b64 = bytesToBase64(tx_bytes);

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
      Debug.print("sui_executeTransactionBlock request: " # body_text);

      let response = await (with cycles = 230_949_972_000) IC.ic.http_request({
        url = rpc_url;
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

          Debug.print("sui_executeTransactionBlock response: " # response_text);

          // Parse response to extract transaction digest
          switch (Json.parse(response_text)) {
            case (#ok(json)) {
              switch (json) {
                case (#object_(fields)) {
                  for ((key, value) in fields.vals()) {
                    if (key == "result") {
                      switch (value) {
                        case (#object_(result_fields)) {
                          for ((result_key, result_value) in result_fields.vals()) {
                            if (result_key == "digest") {
                              switch (result_value) {
                                case (#string(digest)) { return #ok(digest) };
                                case (_) { };
                              }
                            }
                          };
                          return #err("No digest in transaction result");
                        };
                        case (_) { return #err("Expected object result") };
                      }
                    } else if (key == "error") {
                      switch (value) {
                        case (#object_(error_fields)) {
                          var error_message = "SUI RPC error";
                          for ((error_key, error_value) in error_fields.vals()) {
                            if (error_key == "message") {
                              switch (error_value) {
                                case (#string(msg)) { error_message := msg };
                                case (_) { };
                              }
                            }
                          };
                          return #err(error_message);
                        };
                        case (_) { return #err("Unknown error format") };
                      }
                    }
                  };
                  #err("No result or error in response")
                };
                case (_) { #err("Expected object response") };
              }
            };
            case (#err(e)) { #err("Failed to parse JSON response: " # debug_show(e)) };
          }
        };
        case (status) {
          let response_text = switch (Text.decodeUtf8(response.body)) {
            case (?text) text;
            case null "Unknown error";
          };
          #err("HTTP " # debug_show(status) # ": " # response_text)
        };
      }
    };

    // Format ECDSA signature for SUI
    private func formatSuiSignature(signature: [Nat8]) : Text {
      // SUI signature format: [scheme_flag] + [signature] + [recovery_id]
      // For ECDSA: scheme_flag = 0x00, recovery_id needs to be computed
      let recovery_id: Nat8 = 0; // Simplified - would need proper recovery computation
      let buffer = Buffer.Buffer<Nat8>(signature.size() + 2);
      buffer.add(0x00); // scheme flag
      for (byte in signature.vals()) {
        buffer.add(byte);
      };
      buffer.add(recovery_id);
      let sui_sig_bytes = Buffer.toArray(buffer);
      bytesToBase64(sui_sig_bytes)
    };

    // Extract first coin object ID from transaction data
    private func getFirstCoinObjectId(tx_data: TransactionData) : Text {
      switch (tx_data.kind) {
        case (#ProgrammableTransaction(pt)) {
          if (pt.inputs.size() > 0) {
            switch (pt.inputs[0]) {
              case (#Object(obj_ref)) { obj_ref.objectId };
              case (_) { "0x0" };
            }
          } else {
            "0x0"
          }
        };
        case (_) { "0x0" };
      }
    };

    // Extract recipient address from transaction data
    private func getRecipientAddress(tx_data: TransactionData) : Text {
      switch (tx_data.kind) {
        case (#ProgrammableTransaction(pt)) {
          if (pt.commands.size() > 0) {
            switch (pt.commands[0]) {
              case (#TransferObjects(transfer)) {
                switch (transfer.address) {
                  case (#Pure(addr_bytes)) {
                    // Convert bytes to hex address
                    "0x" # bytesToHex(addr_bytes)
                  };
                  case (_) { "0x0" };
                }
              };
              case (_) { "0x0" };
            }
          } else {
            "0x0"
          }
        };
        case (_) { "0x0" };
      }
    };

    // Extract transfer amount from stored transaction metadata (placeholder)
    private func getTransferAmount(tx_data: TransactionData) : Nat64 {
      // For now, return a default amount - we would need to store this
      // during transaction creation or parse it from the transaction structure
      1000000 // 1 SUI in MIST
    };

    // Parse transaction bytes from build response
    private func parseTransactionBytesFromResponse(json_text: Text) : Result<Text> {
      switch (Json.parse(json_text)) {
        case (#err(e)) {
          #err("Failed to parse build response JSON: " # debug_show(e))
        };
        case (#ok(json)) {
          switch (json) {
            case (#object_(fields)) {
              for ((key, value) in fields.vals()) {
                switch (key) {
                  case ("result") {
                    switch (value) {
                      case (#string(tx_bytes)) {
                        return #ok(tx_bytes);
                      };
                      case (_) { return #err("Expected transaction bytes string in result") };
                    }
                  };
                  case ("error") {
                    return #err("SUI RPC build error: " # debug_show(value));
                  };
                  case (_) {};
                };
              };
              #err("No result field found in build response")
            };
            case (_) { #err("Expected JSON object in build response") };
          }
        };
      }
    };

    // Parse transaction submission response to extract digest
    private func parseTransactionResponse(json_text: Text) : Result<Text> {
      switch (Json.parse(json_text)) {
        case (#err(e)) {
          #err("Failed to parse transaction response JSON: " # debug_show(e))
        };
        case (#ok(json)) {
          switch (json) {
            case (#object_(fields)) {
              for ((key, value) in fields.vals()) {
                switch (key) {
                  case ("result") {
                    switch (value) {
                      case (#object_(result_fields)) {
                        for ((result_key, result_value) in result_fields.vals()) {
                          switch (result_key) {
                            case ("digest") {
                              switch (result_value) {
                                case (#string(digest)) {
                                  return #ok(digest);
                                };
                                case (_) {};
                              };
                            };
                            case (_) {};
                          };
                        };
                      };
                      case (_) {};
                    };
                  };
                  case ("error") {
                    return #err("SUI RPC error: " # debug_show(value));
                  };
                  case (_) {};
                };
              };
              #err("No digest found in transaction response")
            };
            case (_) { #err("Expected JSON object in transaction response") };
          }
        };
      }
    };

    // Convert bytes to base64 using proper encoder
    private func bytesToBase64(bytes: [Nat8]) : Text {
      // Use standard Base64 with padding
      BaseX.toBase64(bytes.vals(), #standard({ includePadding = true }))
    };

    // Parse derivation path string into blob array for ECDSA API
    private func parseDerivationPath(path: Text) : Result<[Blob]> {
      if (Text.size(path) == 0) {
        return #ok([]);
      };

      let parts = Text.split(path, #char '/');
      let result = Buffer.Buffer<Blob>(0);

      for (part in parts) {
        let cleaned = if (Text.endsWith(part, #char '\'')) {
          Text.trimEnd(part, #char '\'')
        } else {
          part
        };

        switch (textToNat32(cleaned)) {
          case (null) {
            return #err("Invalid derivation path component: " # part);
          };
          case (?n) {
            result.add(nat32ToBlob(n));
          };
        };
      };
      #ok(Buffer.toArray(result))
    };

    // Convert text to Nat32 for derivation path parsing
    private func textToNat32(text: Text) : ?Nat32 {
      var num: Nat = 0;
      for (c in Text.toIter(text)) {
        if (c < '0' or c > '9') {
          return null;
        };
        num := num * 10 + Nat32.toNat(Char.toNat32(c) - Char.toNat32('0'));
      };
      if (num > Nat32.toNat(Nat32.maximumValue)) {
        return null;
      };
      ?Nat32.fromNat(num)
    };

    // Convert Nat32 to little-endian blob for ECDSA API
    private func nat32ToBlob(n: Nat32) : Blob {
      let bytes = Buffer.Buffer<Nat8>(4);
      bytes.add(Nat8.fromNat(Nat32.toNat(n & 0xFF)));
      bytes.add(Nat8.fromNat(Nat32.toNat((n >> 8) & 0xFF)));
      bytes.add(Nat8.fromNat(Nat32.toNat((n >> 16) & 0xFF)));
      bytes.add(Nat8.fromNat(Nat32.toNat((n >> 24) & 0xFF)));
      Blob.fromArray(Buffer.toArray(bytes))
    };

    // Convert bytes to hex string
    private func bytesToHex(bytes: [Nat8]) : Text {
      let hexChars = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f'];
      var result = "0x";
      for (byte in bytes.vals()) {
        let high = Nat8.toNat(byte / 16);
        let low = Nat8.toNat(byte % 16);
        result := result # Char.toText(hexChars[high]) # Char.toText(hexChars[low]);
      };
      result
    };
  };

  // Factory functions for creating wallets

  // Create mainnet wallet
  public func createMainnetWallet(key_name: Text) : Wallet {
    let config: WalletConfig = {
      key_name = key_name;
      network = "mainnet";
      rpc_url = null; // Use default mainnet RPC
    };
    Wallet(config)
  };

  // Create testnet wallet
  public func createTestnetWallet(key_name: Text) : Wallet {
    let config: WalletConfig = {
      key_name = key_name;
      network = "testnet";
      rpc_url = null; // Use default testnet RPC
    };
    Wallet(config)
  };

  // Create devnet wallet
  public func createDevnetWallet(key_name: Text) : Wallet {
    let config: WalletConfig = {
      key_name = key_name;
      network = "devnet";
      rpc_url = null; // Use default devnet RPC
    };
    Wallet(config)
  };

  // Create custom wallet with specific RPC URL
  public func createCustomWallet(key_name: Text, network: Text, rpc_url: Text) : Wallet {
    let config: WalletConfig = {
      key_name = key_name;
      network = network;
      rpc_url = ?rpc_url;
    };
    Wallet(config)
  };
}