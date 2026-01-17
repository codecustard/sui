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
import Nat "mo:base/Nat";
import Nat32 "mo:base/Nat32";
import Nat8 "mo:base/Nat8";
import Nat64 "mo:base/Nat64";
import Error "mo:base/Error";
import Debug "mo:base/Debug";
import IC "mo:ic";
import Json "mo:json";
import BaseX "mo:base-x-encoder";

import Types "types";
import Address "address";
import Transaction "transaction";
import Blake2b "mo:blake2b";
import Sha256 "mo:sha2/Sha256";

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

              // For SUI transfers, we need a separate coin for gas or use the transfer coin for gas too
              // Use the coin itself for gas payment (SUI standard approach)
              let gas_data : Types.GasData = {
                payment = object_refs; // Use the coins for gas payment
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
            // 1. Get public key first
            let pk_result = await (with cycles = 30_000_000_000) IC.ic.ecdsa_public_key({
              canister_id = null;
              derivation_path = derivation_blobs;
              key_id = { name = config.key_name; curve = #secp256k1 };
            });
            let public_key_bytes = Blob.toArray(pk_result.public_key);

            // 2. Serialize the transaction data to bytes using IntentMessage (required by SUI)
            let intent = Transaction.createTransactionIntent();
            let intent_msg : Types.IntentMessage = {
              intent = intent;
              value = transaction_data;
            };
            let serialized_tx = Transaction.serializeIntentMessage(intent_msg);

            // 3. Create transaction hash for signing
            let tx_hash = hashTransaction(serialized_tx);

            // 4. Sign the real transaction hash using ECDSA
            let signature_result = await (with cycles = 30_000_000_000) IC.ic.sign_with_ecdsa({
              message_hash = Blob.fromArray(tx_hash);
              derivation_path = derivation_blobs;
              key_id = { name = config.key_name; curve = #secp256k1 };
            });

            let signature_bytes = Blob.toArray(signature_result.signature);

            // 5. Format signature with public key for SUI
            #ok(formatSuiSignatureWithPubkey(signature_bytes, public_key_bytes))
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
      _derivation_path: ?Text
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
        \"id\": \"1\",
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

      Debug.print("Making HTTP request to: " # rpc_url);
      Debug.print("Request body: " # request_body);

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

        Debug.print("HTTP response status: " # debug_show(response.status));

        if (response.status != 200) {
          let decoded_text = switch (Text.decodeUtf8(response.body)) {
            case (null) { "Unknown error" };
            case (?text) { text };
          };
          return #err("SUI RPC error: " # decoded_text);
        };

        let decoded_text = switch (Text.decodeUtf8(response.body)) {
          case (null) {
            Debug.print("Failed to decode UTF8 response");
            #err("Failed to decode RPC response")
          };
          case (?text) {
            Debug.print("RPC response: " # text);
            parseCoinsResponse(text)
          };
        };

        decoded_text
      } catch (error) {
        #err("HTTP request failed: " # Error.message(error))
      }
    };

    // Parse SUI RPC coins response
    private func parseCoinsResponse(json_text: Text) : Result<[Types.SuiCoin]> {
      Debug.print("Parsing coins response...");
      switch (Json.parse(json_text)) {
        case (#err(e)) {
          Debug.print("JSON parse error: " # debug_show(e));
          #err("Failed to parse coins JSON: " # debug_show(e))
        };
        case (#ok(json)) {
          Debug.print("JSON parsed successfully");
          switch (json) {
            case (#object_(fields)) {
              Debug.print("Processing object fields...");
              for ((key, value) in fields.vals()) {
                Debug.print("Processing key: " # key);
                switch (key) {
                  case ("result") {
                    Debug.print("Found result field");
                    switch (value) {
                      case (#object_(result_fields)) {
                        Debug.print("Processing result object");
                        for ((result_key, result_value) in result_fields.vals()) {
                          Debug.print("Processing result key: " # result_key);
                          switch (result_key) {
                            case ("data") {
                              Debug.print("Found data field");
                              switch (result_value) {
                                case (#array(coins_array)) {
                                  Debug.print("Found coins array with " # debug_show(coins_array.size()) # " coins");
                                  let parseResult = parseCoinArray(coins_array);
                                  Debug.print("Coin parsing result: " # debug_show(parseResult));
                                  return parseResult;
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
      Debug.print("parseCoinArray called with " # debug_show(coins.size()) # " coins");
      let result = Buffer.Buffer<Types.SuiCoin>(0);

      for (coin_json in coins.vals()) {
        Debug.print("Processing coin object...");
        switch (parseCoinObject(coin_json)) {
          case (#err(error)) {
            Debug.print("Error parsing coin: " # error);
            return #err(error)
          };
          case (#ok(coin)) {
            Debug.print("Successfully parsed coin: " # coin.coinObjectId);
            result.add(coin)
          };
        }
      };

      Debug.print("parseCoinArray completed successfully");
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
    private func _serializeTransaction(tx_data: TransactionData) : [Nat8] {
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
                serializeULEB128(buffer, data.size());
                for (byte in data.vals()) {
                  buffer.add(byte);
                };
              };
              case (#Object(obj_ref)) {
                buffer.add(1); // Tag for Object
                let obj_id_bytes = Transaction.encodeBCSAddress(obj_ref.objectId);
                for (byte in obj_id_bytes.vals()) {
                  buffer.add(byte);
                };
                serializeU64(buffer, obj_ref.version);
                let digest_bytes = switch (BaseX.fromBase64(obj_ref.digest)) {
                  case (#ok(bytes)) {
                    if (bytes.size() >= 32) {
                      Array.tabulate<Nat8>(32, func(i) { bytes[i] })
                    } else {
                      Array.append(bytes, Array.tabulate<Nat8>(32 - bytes.size(), func(_) { 0 }))
                    }
                  };
                  case (#err(_)) Array.tabulate<Nat8>(32, func(_) { 0 });
                };
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
                serializeULEB128(buffer, transfer.objects.size());
                for (obj in transfer.objects.vals()) {
                  serializeArgument(buffer, obj);
                };
                serializeArgument(buffer, transfer.address);
              };
              case (#SplitCoins(split)) {
                buffer.add(2); // Tag for SplitCoins
                serializeArgument(buffer, split.coin);
                serializeULEB128(buffer, split.amounts.size());
                for (amount in split.amounts.vals()) {
                  serializeArgument(buffer, amount);
                };
              };
              case (#MergeCoins(merge)) {
                buffer.add(3); // Tag for MergeCoins
                serializeArgument(buffer, merge.destination);
                serializeULEB128(buffer, merge.sources.size());
                for (source in merge.sources.vals()) {
                  serializeArgument(buffer, source);
                };
              };
              case (#MoveCall(move_call)) {
                buffer.add(0); // Tag for MoveCall
                let obj_id_bytes = hexStringToBytes(
                  if (Text.startsWith(move_call.package, #text("0x"))) {
                    Text.trimStart(move_call.package, #text("0x"))
                  } else {
                    move_call.package
                  }
                );
                for (byte in obj_id_bytes.vals()) {
                  buffer.add(byte);
                };
                serializeString(buffer, move_call.moduleName);
                serializeString(buffer, move_call.functionName);
                serializeULEB128(buffer, move_call.typeArguments.size());
                for (type_arg in move_call.typeArguments.vals()) {
                  serializeString(buffer, type_arg);
                };
                serializeULEB128(buffer, move_call.arguments.size());
                for (arg in move_call.arguments.vals()) {
                  serializeArgument(buffer, arg);
                };
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

    // Hash transaction bytes using Blake2b + SHA256 (proper SUI hash)
    private func hashTransaction(tx_bytes: [Nat8]) : [Nat8] {
      // First hash with Blake2b-256
      let blake2bHash = Blake2b.digest(Blob.fromArray(tx_bytes));
      // Then hash the Blake2b result with SHA256
      let sha256Hash = Sha256.fromArray(#sha256, Blob.toArray(blake2bHash));
      Blob.toArray(sha256Hash)
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
    private func submitTransaction(_tx_data: TransactionData, _signature: Text) : async Result<Text> {
      #err("submitTransaction deprecated - use sendTransactionDirect instead")
    };

    // Build proper SUI transaction using transaction.mo and submit via sui_executeTransactionBlock
    private func buildAndSubmitTransfer(
      from_address: SuiAddress,
      to_address: SuiAddress,
      amount: Nat64,
      _gas_budget: Nat64,
      rpc_url: Text
    ) : async Result<Text> {
      // Get coins for the transfer
      Debug.print("Getting coins for address: " # from_address);
      switch (await queryCoins(from_address)) {
        case (#err(error)) {
          Debug.print("Failed to get coins: " # error);
          return #err("Failed to get coins: " # error)
        };
        case (#ok(coins)) {
          Debug.print("Successfully got " # debug_show(coins.size()) # " coins");
          if (coins.size() == 0) {
            return #err("No coins available for transfer");
          };

          // Select the first available coin (removed problematic filtering)
          let coin = coins[0];
          Debug.print("Using coin: " # coin.coinObjectId);
          let coin_obj_ref: Types.ObjectRef = {
            objectId = coin.coinObjectId;
            version = coin.version;
            digest = coin.digest;
          };
          Debug.print("Created coin object reference");

          // FINAL APPROACH: Manual SUI transfer API call instead of transaction submission
          Debug.print("Using SUI transfer API directly...");

          // Instead of submitting a transaction, call SUI's transfer API directly
          // This bypasses all BCS serialization issues
          return await directSuiTransfer(from_address, to_address, amount, coin_obj_ref.objectId, rpc_url);
        };
      }
    };

    // Direct SUI transfer using proper transaction building instead of unsafe_pay
    private func directSuiTransfer(
      from_address: SuiAddress,
      to_address: SuiAddress,
      amount: Nat64,
      coin_object_id: Text,
      rpc_url: Text
    ) : async Result<Text> {
      Debug.print("directSuiTransfer called");
      Debug.print("From: " # from_address);
      Debug.print("To: " # to_address);
      Debug.print("Amount: " # Nat64.toText(amount));
      Debug.print("Coin: " # coin_object_id);

      // Get the coin details we need
      switch (await queryCoins(from_address)) {
        case (#err(error)) { #err("Failed to query coins: " # error) };
        case (#ok(coins)) {
          if (coins.size() == 0) {
            return #err("No coins available");
          };

          let coin = coins[0];
          let coin_obj_ref: Types.ObjectRef = {
            objectId = coin.coinObjectId;
            version = coin.version;
            digest = coin.digest;
          };

          // Create gas data using the coin itself for gas payment
          let gas_data: Types.GasData = {
            payment = [coin_obj_ref]; // Use the transfer coin for gas
            owner = from_address;
            price = 1000;
            budget = 20000000;
          };

          // Create proper SUI transfer transaction
          let tx_data = Transaction.createSuiTransferTransaction(
            from_address,
            to_address,
            amount,
            coin_obj_ref,
            gas_data
          );

          // Sign the transaction
          switch (await signTransaction(tx_data, ?"0")) {
            case (#err(error)) { #err("Failed to sign transaction: " # error) };
            case (#ok(signature)) {
              // Submit the transaction
              let tx_bytes = Transaction.serializeTransaction(tx_data);
              let tx_bytes_b64 = bytesToBase64(tx_bytes);

              // Use proper JSON building to avoid formatting issues
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

              let submit_body = Json.stringify(payload, null);

              let response = await (with cycles = 230_949_972_000) IC.ic.http_request({
                url = rpc_url;
                max_response_bytes = ?32768;
                headers = [
                  { name = "Content-Type"; value = "application/json" },
                  { name = "Accept"; value = "application/json" }
                ];
                body = ?Text.encodeUtf8(submit_body);
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

                  Debug.print("Transaction response: " # response_text);

                  // Parse response to extract transaction digest
                  switch (parseTransactionResponse(response_text)) {
                    case (#ok(digest)) { #ok(digest) };
                    case (#err(_error)) { #err("Transaction failed: " # response_text) };
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
          };
        };
      }
    };

    // Sign transaction bytes and submit to network
    private func _signAndSubmitTransactionBytes(
      tx_bytes_b64: Text,
      _sender_address: SuiAddress,
      rpc_url: Text
    ) : async Result<Text> {
      // Decode the transaction bytes
      let tx_bytes = switch (base64ToBytes(tx_bytes_b64)) {
        case (#err(error)) { return #err("Failed to decode tx bytes: " # error) };
        case (#ok(bytes)) { bytes };
      };

      // Hash the transaction bytes for signing
      let tx_hash = hashTransaction(tx_bytes);

      // Sign using ICP threshold ECDSA
      let request = {
        message_hash = Blob.fromArray(tx_hash);
        derivation_path = [Text.encodeUtf8("0")];
        key_id = { curve = #secp256k1; name = config.key_name };
      };

      try {
        let response = await (with cycles = 26_153_846_153) IC.ic.sign_with_ecdsa(request);
        let signature = Blob.toArray(response.signature);

        // Format signature for SUI
        let sui_signature = formatSuiSignature(signature);
        Debug.print("Signature created, submitting transaction...");

        // Submit the signed transaction
        let submit_body = "{
          \"jsonrpc\": \"2.0\",
          \"id\": \"1\",
          \"method\": \"sui_executeTransactionBlock\",
          \"params\": [
            \"" # tx_bytes_b64 # "\",
            [\"" # sui_signature # "\"],
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

        Debug.print("Submitting transaction: " # submit_body);

        let submit_response = await (with cycles = 230_949_972_000) IC.ic.http_request({
          url = rpc_url;
          max_response_bytes = ?32768;
          headers = [
            { name = "Content-Type"; value = "application/json" },
            { name = "Accept"; value = "application/json" }
          ];
          body = ?Text.encodeUtf8(submit_body);
          method = #post;
          is_replicated = ?false;
          transform = null;
        });

        let submit_response_text = switch (Text.decodeUtf8(submit_response.body)) {
          case (null) { return #err("Failed to decode submit response") };
          case (?text) { text };
        };

        Debug.print("Submit response: " # submit_response_text);

        if (submit_response.status != 200) {
          return #err("Transaction submission failed: " # submit_response_text);
        };

        // Parse response to extract transaction digest
        parseTransactionResponse(submit_response_text)
      } catch (error) {
        #err("ECDSA signing failed: " # Error.message(error))
      }
    };

    // Convert base64 to bytes
    private func base64ToBytes(b64: Text) : Result<[Nat8]> {
      switch (BaseX.fromBase64(b64)) {
        case (#ok(bytes)) { #ok(bytes) };
        case (#err(error)) { #err("Base64 decode failed: " # debug_show(error)) };
      }
    };

    // Sign transaction data using ICP threshold ECDSA
    private func _signTransactionData(tx_data: TransactionData, derivation_path: Text) : async Result<Text> {
      // Use transaction.mo IntentMessage serialization (required by SUI)
      let intent = Transaction.createTransactionIntent();
      let intent_msg : Types.IntentMessage = {
        intent = intent;
        value = tx_data;
      };
      let tx_bytes = Transaction.serializeIntentMessage(intent_msg);

      // Hash the transaction bytes using Keccak-256 (SUI uses Keccak)
      let tx_hash = hashTransaction(tx_bytes);

      // Get the public key for this derivation path
      switch (parseDerivationPath(derivation_path)) {
        case (#err(error)) { #err(error) };
        case (#ok(derivation_blobs)) {
          try {
            // Get public key
            let pk_result = await (with cycles = 30_000_000_000) IC.ic.ecdsa_public_key({
              canister_id = null;
              derivation_path = derivation_blobs;
              key_id = { name = config.key_name; curve = #secp256k1 };
            });
            let public_key_bytes = Blob.toArray(pk_result.public_key);

            // Sign using ICP threshold ECDSA
            let request = {
              message_hash = Blob.fromArray(tx_hash);
              derivation_path = derivation_blobs;
              key_id = { curve = #secp256k1; name = config.key_name };
            };

            let response = await (with cycles = 26_153_846_153) IC.ic.sign_with_ecdsa(request);
            let signature = Blob.toArray(response.signature);

            // Format signature for SUI with public key
            let sui_signature = formatSuiSignatureWithPubkey(signature, public_key_bytes);
            #ok(sui_signature)
          } catch (error) {
            #err("ECDSA signing failed: " # Error.message(error))
          }
        };
      }
    };

    // Submit signed transaction to SUI network
    private func _submitSignedTransaction(tx_data: TransactionData, signature: Text, rpc_url: Text) : async Result<Text> {
      // Submit raw TransactionData (signing used IntentMessage, submission uses TransactionData)
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

    // Format ECDSA signature for SUI with public key (correct format)
    private func formatSuiSignatureWithPubkey(signature: [Nat8], public_key: [Nat8]) : Text {
      Debug.print("Raw signature size: " # Nat.toText(signature.size()));
      Debug.print("Public key size: " # Nat.toText(public_key.size()));

      // SUI signature format according to docs: flag(1) + signature(64) + pubkey(33) = 98 bytes total

      // Ensure we have exactly 64-byte signature (raw r,s format)
      let raw_signature = if (signature.size() == 64) {
        signature // Already correct
      } else if (signature.size() > 64) {
        // Take last 64 bytes (r,s values)
        Array.subArray<Nat8>(signature, signature.size() - 64, 64)
      } else {
        // Pad if too short (shouldn't happen)
        let padding = 64 - signature.size();
        Array.append<Nat8>(Array.tabulate<Nat8>(padding, func(_) { 0 }), signature)
      };

      // Ensure we have compressed public key (33 bytes)
      let compressed_pubkey = if (public_key.size() == 33) {
        public_key // Already compressed
      } else if (public_key.size() == 65) {
        // Compress uncompressed key: take x-coord, prefix with parity
        let x_coord = Array.subArray<Nat8>(public_key, 1, 32);
        let y_coord = Array.subArray<Nat8>(public_key, 33, 32);
        let y_is_odd = (y_coord[31] % 2) == 1;
        let prefix : Nat8 = if (y_is_odd) { 0x03 } else { 0x02 };
        Array.append<Nat8>([prefix], x_coord)
      } else {
        public_key // Use as-is and hope for the best
      };

      Debug.print("Processed signature size: " # Nat.toText(raw_signature.size()));
      Debug.print("Compressed pubkey size: " # Nat.toText(compressed_pubkey.size()));

      // Build final signature: scheme_flag + signature + pubkey
      let buffer = Buffer.Buffer<Nat8>(98); // Exactly 98 bytes
      buffer.add(0x01); // ECDSA secp256k1 scheme flag

      for (byte in raw_signature.vals()) {
        buffer.add(byte);
      };

      for (byte in compressed_pubkey.vals()) {
        buffer.add(byte);
      };

      let sui_sig_bytes = Buffer.toArray(buffer);
      Debug.print("Final signature size: " # Nat.toText(sui_sig_bytes.size()));

      bytesToBase64(sui_sig_bytes)
    };

    // Convert DER encoded signature to raw r,s format for SUI
    private func _derToRawSignature(der_sig: [Nat8]) : [Nat8] {
      if (der_sig.size() < 6) {
        return der_sig; // Invalid DER, return as is
      };

      // DER format: 0x30 [total_len] 0x02 [r_len] [r] 0x02 [s_len] [s]
      if (der_sig[0] != 0x30 or der_sig[2] != 0x02) {
        return der_sig; // Not DER format, return as is
      };

      let r_len = der_sig[3];
      let r_start = 4;
      let s_len_pos = r_start + Nat8.toNat(r_len) + 1; // Skip r + 0x02

      if (s_len_pos >= der_sig.size()) {
        return der_sig; // Invalid format
      };

      let s_len = der_sig[s_len_pos];
      let s_start = s_len_pos + 1;

      // Extract r and s, ensure 32 bytes each
      let r_raw = Array.subArray<Nat8>(der_sig, r_start, Nat8.toNat(r_len));
      let s_raw = Array.subArray<Nat8>(der_sig, s_start, Nat8.toNat(s_len));

      // Pad to 32 bytes if shorter, trim if longer
      let r_padded = padOrTrimTo32Bytes(r_raw);
      let s_padded = padOrTrimTo32Bytes(s_raw);

      Array.append<Nat8>(r_padded, s_padded)
    };

    // Pad or trim byte array to exactly 32 bytes
    private func padOrTrimTo32Bytes(bytes: [Nat8]) : [Nat8] {
      if (bytes.size() == 32) {
        bytes
      } else if (bytes.size() < 32) {
        // Pad with leading zeros
        let padding = 32 - bytes.size();
        Array.append<Nat8>(Array.tabulate<Nat8>(padding, func(_) { 0 }), bytes)
      } else {
        // Trim leading bytes (remove extra padding)
        Array.subArray<Nat8>(bytes, bytes.size() - 32, 32)
      }
    };

    // Sign transaction bytes directly (for SUI-generated txBytes)
    public func signTransactionBytes(
      tx_bytes_b64: Text,
      derivation_path: ?Text
    ) : async Result<Text> {
      Debug.print("=== Starting signTransactionBytes ===");
      let path = switch (derivation_path) {
        case (null) { "" };
        case (?p) { p };
      };

      switch (parseDerivationPath(path)) {
        case (#err(error)) { #err(error) };
        case (#ok(derivation_blobs)) {
          try {
            // Decode base64 transaction bytes
            let tx_bytes = switch (BaseX.fromBase64(tx_bytes_b64)) {
              case (#err(error)) { return #err("Failed to decode txBytes: " # error) };
              case (#ok(bytes)) { bytes };
            };

            // Get public key
            let pk_result = await (with cycles = 30_000_000_000) IC.ic.ecdsa_public_key({
              canister_id = null;
              derivation_path = derivation_blobs;
              key_id = { name = config.key_name; curve = #secp256k1 };
            });
            let public_key_bytes = Blob.toArray(pk_result.public_key);

            // Create SUI intent message for signing (required format)
            // Intent: [scope, version, app_id] = [TransactionData=0, V0=0, Sui=0]
            let intent_bytes : [Nat8] = [0x00, 0x00, 0x00]; // 3 bytes: scope, version, app_id
            let intent_message = Array.append(intent_bytes, tx_bytes);

            // Hash with Blake2b + SHA256 sequence (proper SUI hashing)
            let tx_hash = hashTransaction(intent_message);

            // Sign using ICP threshold ECDSA
            let signature_result = await (with cycles = 30_000_000_000) IC.ic.sign_with_ecdsa({
              message_hash = Blob.fromArray(tx_hash);
              derivation_path = derivation_blobs;
              key_id = { name = config.key_name; curve = #secp256k1 };
            });

            let signature_bytes = Blob.toArray(signature_result.signature);

            Debug.print("Signature size: " # Nat.toText(signature_bytes.size()));
            Debug.print("Public key size: " # Nat.toText(public_key_bytes.size()));

            // Format signature with public key for SUI
            let formatted_sig = formatSuiSignatureWithPubkey(signature_bytes, public_key_bytes);
            Debug.print("Final signature length: " # Nat.toText(formatted_sig.size()));
            #ok(formatted_sig)
          } catch (error) {
            #err("Transaction signing failed: " # Error.message(error))
          };
        };
      };
    };

    // Extract first coin object ID from transaction data
    private func _getFirstCoinObjectId(tx_data: TransactionData) : Text {
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
    private func _getRecipientAddress(tx_data: TransactionData) : Text {
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
    private func _getTransferAmount(_tx_data: TransactionData) : Nat64 {
      // For now, return a default amount - we would need to store this
      // during transaction creation or parse it from the transaction structure
      1000000 // 1 SUI in MIST
    };

    // Parse transaction bytes from build response
    private func _parseTransactionBytesFromResponse(json_text: Text) : Result<Text> {
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

  // Helper function to serialize ULEB128
  private func serializeULEB128(buffer: Buffer.Buffer<Nat8>, value: Nat) {
    var val = value;
    while (val >= 128) {
      buffer.add(Nat8.fromNat((val % 128) + 128));
      val := val / 128;
    };
    buffer.add(Nat8.fromNat(val));
  };

  // Helper function to serialize U64
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

  // Helper function to convert hex string to bytes
  private func hexStringToBytes(hex: Text) : [Nat8] {
    let chars = Text.toArray(hex);
    let bytes = Buffer.Buffer<Nat8>(0);
    var i = 0;
    while (i + 1 < chars.size()) {
      let highChar = chars[i];
      let lowChar = chars[i + 1];
      let high = charToHex(highChar);
      let low = charToHex(lowChar);
      bytes.add(Nat8.fromNat(high * 16 + low));
      i += 2;
    };
    Buffer.toArray(bytes)
  };

  // Helper function to convert hex character to number
  private func charToHex(c: Char) : Nat {
    switch (c) {
      case ('0') 0; case ('1') 1; case ('2') 2; case ('3') 3; case ('4') 4;
      case ('5') 5; case ('6') 6; case ('7') 7; case ('8') 8; case ('9') 9;
      case ('a' or 'A') 10; case ('b' or 'B') 11; case ('c' or 'C') 12;
      case ('d' or 'D') 13; case ('e' or 'E') 14; case ('f' or 'F') 15;
      case (_) 0;
    }
  };

  // Helper function to serialize Argument
  private func serializeArgument(buffer: Buffer.Buffer<Nat8>, arg: Types.Argument) {
    switch (arg) {
      case (#GasCoin()) {
        buffer.add(0); // Tag for GasCoin
      };
      case (#Input(idx)) {
        buffer.add(1); // Tag for Input
        serializeULEB128(buffer, idx);
      };
      case (#Result(idx)) {
        buffer.add(2); // Tag for Result
        serializeULEB128(buffer, idx);
      };
      case (#NestedResult(outer, inner)) {
        buffer.add(3); // Tag for NestedResult
        serializeULEB128(buffer, outer);
        serializeULEB128(buffer, inner);
      };
    };
  };

  // Helper function to serialize CallArg
  private func _serializeCallArg(buffer: Buffer.Buffer<Nat8>, arg: Types.CallArg) {
    switch (arg) {
      case (#Pure(data)) {
        buffer.add(0); // Tag for Pure
        serializeULEB128(buffer, data.size());
        for (byte in data.vals()) {
          buffer.add(byte);
        };
      };
      case (#Object(obj_ref)) {
        buffer.add(1); // Tag for Object
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
        serializeU64(buffer, obj_ref.version);
        let digest_bytes = hexStringToBytes(obj_ref.digest);
        for (byte in digest_bytes.vals()) {
          buffer.add(byte);
        };
      };
    };
  };

  // Helper function to serialize string
  private func serializeString(buffer: Buffer.Buffer<Nat8>, str: Text) {
    let bytes = Text.encodeUtf8(str);
    let size = bytes.size();
    serializeULEB128(buffer, size);
    for (byte in bytes.vals()) {
      buffer.add(byte);
    };
  };
}