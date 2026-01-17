import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Debug "mo:base/Debug";
import Error "mo:base/Error";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";
import Nat16 "mo:base/Nat16";
import Nat64 "mo:base/Nat64";
import Result "mo:base/Result";
import Text "mo:base/Text";
import Char "mo:base/Char";
import Nat8 "mo:base/Nat8";
import Nat32 "mo:base/Nat32";
import BaseX "mo:base-x-encoder";
import Json "mo:json";
import IC "mo:ic";
import Utils "utils";
import Blake2b "mo:blake2b";
import Sha256 "mo:sha2/Sha256";
import Bcs "mo:bcs";

module {
  /// Transfer SUI using the simplified unsafe_transferSui RPC method
  /// This is based on the working implementation
  public func transferSuiSimple(
    rpcUrl : Text,
    senderAddress : Text,
    coinObjectId : Text,
    recipientAddress : Text,
    amount : Nat64,
    gasBudget : Nat64,
    signFunc : (messageHash : Blob) -> async Result.Result<Blob, Text>,
    getPublicKeyFunc : () -> async Result.Result<Blob, Text>,
  ) : async Result.Result<Text, Text> {
    try {
      let request_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"unsafe_transferSui\"," #
      "\"params\":[\"" # senderAddress # "\",\"" # coinObjectId # "\",\"" #
      Nat64.toText(gasBudget) # "\",\"" # recipientAddress # "\",\"" # Nat64.toText(amount) # "\"]}";

      Debug.print("Transfer request: " # request_body);

      let response = await (with cycles = 300_000_000) IC.ic.http_request({
        url = rpcUrl;
        max_response_bytes = ?20000;
        headers = [{ name = "Content-Type"; value = "application/json" }];
        body = ?Text.encodeUtf8(request_body);
        method = #post;
        is_replicated = ?false;
        transform = null;
      });

      let body_text = switch (Text.decodeUtf8(response.body)) {
        case (?text) { text };
        case (null) { return #err("Failed to decode response") };
      };

      Debug.print("Transfer response: " # body_text);

      switch (Json.parse(body_text)) {
        case (#ok(json)) {
          switch (Json.get(json, "result")) {
            case (?result) {
              switch (Json.getAsText(result, "txBytes")) {
                case (#ok(txBytesBase64)) {
                  let txBytes = Utils.decodeBase64(txBytesBase64);

                  Debug.print("Transaction bytes size: " # Nat.toText(txBytes.size()));

                  // Create intent message for signing (SUI standard)
                  let intent : [Nat8] = [0, 0, 0]; // TransactionData=0, V0=0, Sui=0
                  let messageToSign = Array.append(intent, txBytes);

                  // SUI requires Blake2b-256 hash of (intent + txBytes)
                  let messageHashBlob = blake2bHash(messageToSign);
                  let messageHashBytes = Blob.toArray(messageHashBlob);
                  Debug.print("Blake2b hash size: " # Nat.toText(messageHashBytes.size()));

                  if (messageHashBytes.size() != 32) {
                    return #err("Blake2b hash is not 32 bytes: " # Nat.toText(messageHashBytes.size()));
                  };

                  // Hash again with SHA256 before signing (per working example)
                  let finalHashBlob = sha256Hash(messageHashBytes);
                  Debug.print("Final SHA256 hash size: " # Nat.toText(Blob.toArray(finalHashBlob).size()));

                  let signature = switch (await signFunc(finalHashBlob)) {
                    case (#ok(sig)) { Blob.toArray(sig) };
                    case (#err(msg)) { return #err("Failed to sign: " # msg) };
                  };

                  Debug.print("Signature size: " # Nat.toText(signature.size()));

                  let publicKey = switch (await getPublicKeyFunc()) {
                    case (#ok(pk)) { Blob.toArray(pk) };
                    case (#err(msg)) {
                      return #err("Failed to get public key: " # msg);
                    };
                  };

                  await executeSuiTransaction(rpcUrl, txBytes, signature, publicKey);
                };
                case (#err(_)) { #err("No txBytes in response: " # body_text) };
              };
            };
            case (null) {
              switch (Json.get(json, "error")) {
                case (?error) {
                  let errorMsg = switch (Json.getAsText(error, "message")) {
                    case (#ok(msg)) { msg };
                    case (#err(_)) { body_text };
                  };
                  #err("SUI RPC error: " # errorMsg);
                };
                case (null) { #err("No result in response: " # body_text) };
              };
            };
          };
        };
        case (#err(_)) { #err("Failed to parse response: " # body_text) };
      };
    } catch (e) {
      #err("Transfer failed: " # Error.message(e));
    };
  };

  /// Execute a signed SUI transaction
  public func executeSuiTransaction(
    rpcUrl : Text,
    txBytes : [Nat8],
    signature : [Nat8],
    publicKey : [Nat8],
  ) : async Result.Result<Text, Text> {
    Debug.print("Executing transaction - signature size: " # Nat.toText(signature.size()) # ", pubkey size: " # Nat.toText(publicKey.size()));

    // SUI expects signatures in this format:
    // flag (1 byte) + signature (64 bytes) + public key (33 bytes)
    // The flag for ECDSA Secp256k1 is 0x01 per SUI documentation
    let flag : Nat8 = 0x01;
    let signatureWithScheme = Array.tabulate<Nat8>(
      1 + signature.size() + publicKey.size(),
      func(i : Nat) : Nat8 {
        if (i == 0) {
          flag
        } else if (i <= signature.size()) {
          signature[i - 1];
        } else {
          publicKey[i - signature.size() - 1]
        };
      },
    );

    Debug.print("Final signature blob size: " # Nat.toText(signatureWithScheme.size()));

    let txBytesBase64 = Utils.encodeBase64(txBytes);
    let signatureBase64 = Utils.encodeBase64(signatureWithScheme);

    Debug.print("Signature base64: " # signatureBase64);

    let request_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"sui_executeTransactionBlock\"," #
    "\"params\":[\"" # txBytesBase64 # "\",[\"" # signatureBase64 # "\"],null,null]}";

    try {
      let response = await (with cycles = 500_000_000) IC.ic.http_request({
        url = rpcUrl;
        max_response_bytes = ?30000;
        headers = [{ name = "Content-Type"; value = "application/json" }];
        body = ?Text.encodeUtf8(request_body);
        method = #post;
        is_replicated = ?false;
        transform = null;
      });

      let body_text = switch (Text.decodeUtf8(response.body)) {
        case (?text) { text };
        case (null) { return #err("Failed to decode response") };
      };

      Debug.print("Execute response: " # body_text);

      switch (Json.parse(body_text)) {
        case (#ok(json)) {
          switch (Json.get(json, "result")) {
            case (?result) {
              switch (Json.getAsText(result, "digest")) {
                case (#ok(digest)) { #ok(digest) };
                case (#err(_)) { #err("No digest in response: " # body_text) };
              };
            };
            case (null) {
              switch (Json.get(json, "error")) {
                case (?error) {
                  let errorMsg = switch (Json.getAsText(error, "message")) {
                    case (#ok(msg)) { msg };
                    case (#err(_)) { body_text };
                  };
                  #err("SUI RPC error: " # errorMsg);
                };
                case (null) { #err("No result in response: " # body_text) };
              };
            };
          };
        };
        case (#err(_)) { #err("Failed to parse response: " # body_text) };
      };
    } catch (e) {
      #err("Execution failed: " # Error.message(e));
    };
  };

  /// Blake2b hash function for SUI message signing
  private func blake2bHash(message : [Nat8]) : Blob {
    // SUI uses Blake2b-256 (32 bytes output)
    let config = {
      digest_length = 32;
      key = null : ?Blob;
      salt = null : ?Blob;
      personal = null : ?Blob;
    };
    let hashResult = Blake2b.hash(Blob.fromArray(message), ?config);
    hashResult
  };

  /// SHA256 hash function
  private func sha256Hash(message : [Nat8]) : Blob {
    // Use proper SHA256 from mo:sha2 library (matching working example)
    Sha256.fromArray(#sha256, message)
  };

  /// Get SUI coins for an address
  public func getSuiCoins(rpcUrl : Text, address : Text) : async Result.Result<[SuiCoin], Text> {
    try {
      Debug.print("Getting coins for address: " # address);
      let request_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"suix_getCoins\",\"params\":[\"" # address # "\",null,null,null]}";

      let response = await (with cycles = 300_000_000) IC.ic.http_request({
        url = rpcUrl;
        max_response_bytes = ?20000;
        headers = [{ name = "Content-Type"; value = "application/json" }];
        body = ?Text.encodeUtf8(request_body);
        method = #post;
        is_replicated = ?false;
        transform = null;
      });

      let body_text = switch (Text.decodeUtf8(response.body)) {
        case (?text) { text };
        case (null) { return #err("Failed to decode response") };
      };

      Debug.print("SUI RPC Response: " # body_text);

      switch (Json.parse(body_text)) {
        case (#ok(json)) {
          switch (Json.get(json, "result")) {
            case (?result) {
              switch (Json.get(result, "data")) {
                case (?dataJson) {
                  var coins : [SuiCoin] = [];

                  let dataArray = switch (dataJson) {
                    case (#array arr) { arr };
                    case _ { return #err("Data field is not an array") };
                  };

                  Debug.print("Parsing " # Nat.toText(dataArray.size()) # " coins from response");

                  for (coinJson in dataArray.vals()) {
                    let coinType = switch (Json.getAsText(coinJson, "coinType")) {
                      case (#ok(ct)) { ct };
                      case (#err(_)) { "" };
                    };
                    let coinObjectId = switch (Json.getAsText(coinJson, "coinObjectId")) {
                      case (#ok(id)) { id };
                      case (#err(_)) { "" };
                    };
                    let version = switch (Json.getAsText(coinJson, "version")) {
                      case (#ok(v)) { v };
                      case (#err(_)) { "0" };
                    };
                    let digest = switch (Json.getAsText(coinJson, "digest")) {
                      case (#ok(d)) { d };
                      case (#err(_)) { "" };
                    };
                    let balance = switch (Json.getAsText(coinJson, "balance")) {
                      case (#ok(b)) { b };
                      case (#err(_)) { "0" };
                    };

                    let coin : SuiCoin = {
                      coinType = coinType;
                      coinObjectId = coinObjectId;
                      version = version;
                      digest = digest;
                      balance = balance;
                    };
                    coins := Array.append(coins, [coin]);
                    Debug.print("Parsed coin: " # coin.coinObjectId # " balance: " # coin.balance);
                  };

                  Debug.print("Total coins parsed: " # Nat.toText(coins.size()));
                  #ok(coins);
                };
                case (null) { #err("No data field in result") };
              };
            };
            case (null) { #err("No result in response") };
          };
        };
        case (#err(_)) { #err("Failed to parse JSON response") };
      };
    } catch (e) {
      #err("HTTP request failed: " # Error.message(e));
    };
  };

  public type SuiCoin = {
    coinType : Text;
    coinObjectId : Text;
    version : Text;
    digest : Text;
    balance : Text;
  };

  /// Transfer SUI using proper BCS transaction building (SAFE METHOD)
  /// This builds a proper SUI transaction with BCS serialization
  public func transferSuiSafe(
    rpcUrl : Text,
    senderAddress : Text,
    coinObjectId : Text,
    recipientAddress : Text,
    amount : Nat64,
    gasBudget : Nat64,
    signFunc : (messageHash : Blob) -> async Result.Result<Blob, Text>,
    getPublicKeyFunc : () -> async Result.Result<Blob, Text>,
  ) : async Result.Result<Text, Text> {
    try {
      // First, fetch the actual coin object data from RPC
      let coinData = switch (await getObjectInfo(rpcUrl, coinObjectId)) {
        case (#ok(data)) { data };
        case (#err(e)) { return #err("Failed to fetch coin data: " # e) };
      };

      Debug.print("Fetched coin data - version: " # Nat.toText(coinData.version) # ", digest: " # coinData.digest);

      // Build a proper SUI transaction using BCS with real coin data
      let txBytes = buildSuiTransaction(
        senderAddress,
        coinData,
        recipientAddress,
        amount,
        gasBudget
      );

      Debug.print("BCS Transaction bytes size: " # Nat.toText(txBytes.size()));

      // Debug: print first 50 bytes in hex
      var hexStr = "First 50 bytes: ";
      var i = 0;
      for (byte in txBytes.vals()) {
        if (i < 50) {
          let high = Nat8.toNat(byte / 16);
          let low = Nat8.toNat(byte % 16);
          let hexChars = "0123456789abcdef";
          hexStr := hexStr # Text.fromChar(Text.toArray(hexChars)[high]) # Text.fromChar(Text.toArray(hexChars)[low]) # " ";
        };
        i += 1;
      };
      Debug.print(hexStr);

      // Create intent message for signing (SUI standard)
      let intent : [Nat8] = [0, 0, 0]; // TransactionData=0, V0=0, Sui=0
      let messageToSign = Array.append(intent, txBytes);

      // SUI requires Blake2b-256 hash of (intent + txBytes)
      let messageHashBlob = blake2bHash(messageToSign);
      let messageHashBytes = Blob.toArray(messageHashBlob);
      Debug.print("Blake2b hash size: " # Nat.toText(messageHashBytes.size()));

      if (messageHashBytes.size() != 32) {
        return #err("Blake2b hash is not 32 bytes: " # Nat.toText(messageHashBytes.size()));
      };

      // Hash again with SHA256 before signing (per working example)
      let finalHashBlob = sha256Hash(messageHashBytes);
      Debug.print("Final SHA256 hash size: " # Nat.toText(Blob.toArray(finalHashBlob).size()));

      let signature = switch (await signFunc(finalHashBlob)) {
        case (#ok(sig)) { Blob.toArray(sig) };
        case (#err(msg)) { return #err("Failed to sign: " # msg) };
      };

      Debug.print("Signature size: " # Nat.toText(signature.size()));

      let publicKey = switch (await getPublicKeyFunc()) {
        case (#ok(pk)) { Blob.toArray(pk) };
        case (#err(msg)) {
          return #err("Failed to get public key: " # msg);
        };
      };

      await executeSuiTransaction(rpcUrl, txBytes, signature, publicKey);
    } catch (e) {
      #err("Transfer failed: " # Error.message(e));
    };
  };

  /// Fetch object info from SUI RPC
  public func getObjectInfo(rpcUrl : Text, objectId : Text) : async Result.Result<ObjectRef, Text> {
    try {
      let request_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"sui_getObject\"," #
        "\"params\":[\"" # objectId # "\",{\"showContent\":false,\"showOwner\":false}]}";

      let response = await (with cycles = 300_000_000) IC.ic.http_request({
        url = rpcUrl;
        max_response_bytes = ?10000;
        headers = [{ name = "Content-Type"; value = "application/json" }];
        body = ?Text.encodeUtf8(request_body);
        method = #post;
        is_replicated = ?false;
        transform = null;
      });

      let body_text = switch (Text.decodeUtf8(response.body)) {
        case (?text) { text };
        case (null) { return #err("Failed to decode response") };
      };

      Debug.print("Object info response: " # body_text);

      switch (Json.parse(body_text)) {
        case (#ok(json)) {
          switch (Json.get(json, "result")) {
            case (?result) {
              switch (Json.get(result, "data")) {
                case (?data) {
                  let version = switch (Json.getAsText(data, "version")) {
                    case (#ok(v)) { textToNat64(v) };
                    case (#err(_)) { 0 : Nat64 };
                  };
                  let digest = switch (Json.getAsText(data, "digest")) {
                    case (#ok(d)) { d };
                    case (#err(_)) { "" };
                  };
                  #ok({
                    objectId = objectId;
                    version = Nat64.toNat(version);
                    digest = digest;
                  });
                };
                case (null) { #err("No data in response") };
              };
            };
            case (null) { #err("No result in response: " # body_text) };
          };
        };
        case (#err(_)) { #err("Failed to parse JSON: " # body_text) };
      };
    } catch (e) {
      #err("HTTP request failed: " # Error.message(e));
    };
  };

  /// Convert text to Nat64
  private func textToNat64(text : Text) : Nat64 {
    var result : Nat64 = 0;
    for (c in text.chars()) {
      if (c >= '0' and c <= '9') {
        let digit = Nat64.fromNat(Nat32.toNat(Char.toNat32(c) - Char.toNat32('0')));
        result := result * 10 + digit;
      };
    };
    result;
  };

  /// Build a proper SUI transaction using BCS serialization
  /// Based on analysis of unsafe_transferSui output:
  /// - Input 0: Pure recipient address (32 bytes)
  /// - Input 1: Pure amount (8 bytes)
  /// - Command 0: SplitCoins(GasCoin, [Input(1)])
  /// - Command 1: TransferObjects([NestedResult(0,0)], Input(0))
  private func buildSuiTransaction(
    senderAddress : Text,
    coinData : ObjectRef,
    recipientAddress : Text,
    amount : Nat64,
    gasBudget : Nat64
  ) : [Nat8] {
    let writer = Bcs.newWriter();

    // TransactionData::V1 variant = 0
    writer.writeULEB(0);

    // === TransactionKind::ProgrammableTransaction = 0 ===
    writer.writeULEB(0);

    // === ProgrammableTransaction.inputs (Vec<CallArg>) ===
    // Based on RPC analysis: 2 inputs - recipient address first, then amount
    writer.writeULEB(2);

    // Input 0: Pure - recipient address (32 bytes)
    writer.writeULEB(0); // CallArg::Pure variant = 0
    let recipientBytes = addressToBytes(recipientAddress);
    writer.writeULEB(recipientBytes.size()); // Length = 32
    writer.writeBytes(recipientBytes);

    // Input 1: Pure - amount (8 bytes for u64)
    writer.writeULEB(0); // CallArg::Pure variant = 0
    let amountBytes = Bcs.serializeU64(amount);
    writer.writeULEB(amountBytes.size()); // Length = 8
    writer.writeBytes(amountBytes);

    // === ProgrammableTransaction.commands (Vec<Command>) ===
    writer.writeULEB(2); // 2 commands

    // Command 0: SplitCoins(GasCoin, [Input(1)])
    // Command::SplitCoins = 2
    writer.writeULEB(2);
    // Argument for coin: GasCoin
    writer.writeULEB(0); // Argument::GasCoin = 0
    // Vec<Argument> amounts: [Input(1)]
    writer.writeULEB(1); // 1 amount
    writer.writeULEB(1); // Argument::Input = 1
    writer.write16(1);   // Input index 1 (amount)

    // Command 1: TransferObjects([Result(0)], Input(0))
    // Command::TransferObjects = 1
    writer.writeULEB(1);
    // Vec<Argument> objects: [Result(0)] - SplitCoins returns single result
    writer.writeULEB(1); // 1 object
    writer.writeULEB(2); // Argument::Result = 2 (not NestedResult!)
    writer.write16(0);   // Command index 0
    // Argument recipient: Input(0)
    writer.writeULEB(1); // Argument::Input = 1
    writer.write16(0);   // Input index 0 (recipient)

    // === Sender address (32 bytes) ===
    let senderBytes = addressToBytes(senderAddress);
    writer.writeBytes(senderBytes);

    // === GasData ===
    // payment: Vec<ObjectRef>
    writer.writeULEB(1); // 1 gas payment object
    serializeObjectRefV2(writer, coinData);

    // owner: SuiAddress (32 bytes)
    writer.writeBytes(senderBytes);

    // price: u64
    writer.write64(1000);

    // budget: u64
    writer.write64(gasBudget);

    // === TransactionExpiration::None = 0 ===
    writer.writeULEB(0);

    writer.toBytes()
  };

  /// Serialize ObjectRef for V2 (proper BCS format)
  private func serializeObjectRefV2(writer : Bcs.Writer.Writer, objRef : ObjectRef) {
    // ObjectID: 32 bytes (no length prefix, fixed size)
    let objectIdBytes = addressToBytes(objRef.objectId);
    writer.writeBytes(objectIdBytes);

    // SequenceNumber (version): u64
    writer.write64(Nat64.fromNat(objRef.version));

    // ObjectDigest: has ULEB128 length prefix + 32 bytes
    // SUI digests are base58 encoded
    let digest_bytes_raw = switch (BaseX.fromBase58(objRef.digest)) {
      case (#ok(bytes)) { bytes };
      case (#err(_)) {
        // Fallback: try base64 in case format varies
        switch (BaseX.fromBase64(objRef.digest)) {
          case (#ok(bytes)) { bytes };
          case (#err(_)) { Array.tabulate<Nat8>(32, func(_) { 0 }) };
        }
      };
    };

    // SUI digests are exactly 32 bytes
    let digestBytes = if (digest_bytes_raw.size() >= 32) {
      Array.tabulate<Nat8>(32, func(i) { digest_bytes_raw[i] })
    } else {
      // Pad to 32 bytes if shorter
      Array.tabulate<Nat8>(32, func(i) {
        if (i < digest_bytes_raw.size()) digest_bytes_raw[i] else 0
      })
    };

    // Write length prefix (32) followed by digest bytes
    writer.writeULEB(32);
    writer.writeBytes(digestBytes);
  };

  /// Convert SUI address string to 32-byte array
  private func addressToBytes(address : Text) : [Nat8] {
    // Remove 0x prefix and convert hex to bytes
    let cleanHex = if (Text.startsWith(address, #text("0x"))) {
      let chars = address.chars();
      ignore chars.next(); // skip '0'
      ignore chars.next(); // skip 'x'
      Text.fromIter(chars)
    } else {
      address
    };

    switch (Utils.hexToBytes(cleanHex)) {
      case (?bytes) {
        // Ensure exactly 32 bytes (pad with zeros if needed)
        if (bytes.size() >= 32) {
          Array.tabulate<Nat8>(32, func(i) {
            if (i < bytes.size()) bytes[i] else 0
          })
        } else {
          let offset = 32 - bytes.size();
          Array.tabulate<Nat8>(32, func(i) {
            if (i >= offset) bytes[i - offset] else 0
          })
        }
      };
      case (null) {
        Array.tabulate<Nat8>(32, func(i) { 0 }) // Fallback to zero address
      };
    }
  };

  /// Object reference type
  public type ObjectRef = {
    objectId : Text;
    version : Nat;
    digest : Text;
  };

  /// Transaction status result
  public type TransactionStatus = {
    digest : Text;
    status : Text;  // "success" or "failure"
    error : ?Text;
    gasUsed : Nat64;
    timestamp : ?Text;
  };

  /// Get transaction status by digest
  public func getTransactionStatus(
    rpcUrl : Text,
    digest : Text
  ) : async Result.Result<TransactionStatus, Text> {
    try {
      let request_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"sui_getTransactionBlock\"," #
        "\"params\":[\"" # digest # "\",{\"showEffects\":true}]}";

      let response = await (with cycles = 600_000_000) IC.ic.http_request({
        url = rpcUrl;
        max_response_bytes = ?50000;
        headers = [{ name = "Content-Type"; value = "application/json" }];
        body = ?Text.encodeUtf8(request_body);
        method = #post;
        is_replicated = ?false;
        transform = null;
      });

      let body_text = switch (Text.decodeUtf8(response.body)) {
        case (?text) text;
        case null { return #err("Failed to decode response") };
      };

      switch (Json.parse(body_text)) {
        case (#err(_)) { #err("Failed to parse JSON response") };
        case (#ok(json)) {
          // Check for error
          switch (Json.get(json, "error")) {
            case (?_) { return #err("RPC error: " # body_text) };
            case (null) {};
          };

          // Parse result using Json helper functions
          switch (Json.get(json, "result")) {
            case (?result) {
              // Get status from effects.status.status
              let status = switch (Json.get(result, "effects")) {
                case (?effects) {
                  switch (Json.get(effects, "status")) {
                    case (?statusObj) {
                      switch (Json.getAsText(statusObj, "status")) {
                        case (#ok(s)) { s };
                        case (#err(_)) { "unknown" };
                      };
                    };
                    case (null) { "unknown" };
                  };
                };
                case (null) { "unknown" };
              };

              // Get error if present
              let error : ?Text = switch (Json.get(result, "effects")) {
                case (?effects) {
                  switch (Json.get(effects, "status")) {
                    case (?statusObj) {
                      switch (Json.getAsText(statusObj, "error")) {
                        case (#ok(e)) { ?e };
                        case (#err(_)) { null };
                      };
                    };
                    case (null) { null };
                  };
                };
                case (null) { null };
              };

              // Get gas used (sum of all gas fields)
              let gasUsed : Nat64 = switch (Json.get(result, "effects")) {
                case (?effects) {
                  switch (Json.get(effects, "gasUsed")) {
                    case (?gasObj) {
                      var total : Nat64 = 0;
                      switch (Json.getAsText(gasObj, "computationCost")) {
                        case (#ok(v)) { total += textToNat64(v) };
                        case (#err(_)) {};
                      };
                      switch (Json.getAsText(gasObj, "storageCost")) {
                        case (#ok(v)) { total += textToNat64(v) };
                        case (#err(_)) {};
                      };
                      switch (Json.getAsText(gasObj, "storageRebate")) {
                        case (#ok(v)) {
                          let rebate = textToNat64(v);
                          if (total > rebate) { total -= rebate } else { total := 0 };
                        };
                        case (#err(_)) {};
                      };
                      total
                    };
                    case (null) { 0 };
                  };
                };
                case (null) { 0 };
              };

              // Get timestamp
              let timestamp : ?Text = switch (Json.getAsText(result, "timestampMs")) {
                case (#ok(t)) { ?t };
                case (#err(_)) { null };
              };

              #ok({
                digest = digest;
                status = status;
                error = error;
                gasUsed = gasUsed;
                timestamp = timestamp;
              })
            };
            case (null) { #err("No result in response") };
          };
        };
      };
    } catch (e) {
      #err("Request failed: " # Error.message(e))
    };
  };

  /// Format balance from MIST to SUI
  public func formatBalance(mistAmount : Nat64) : Text {
    let sui = mistAmount / 1_000_000_000;
    let remainder = mistAmount % 1_000_000_000;

    // Format with up to 4 decimal places
    let decimals = remainder / 100_000;

    if (decimals == 0) {
      Nat64.toText(sui) # " SUI"
    } else {
      Nat64.toText(sui) # "." # padLeft(Nat64.toText(decimals), 4, '0') # " SUI"
    };
  };

  /// Helper to pad string with leading characters
  private func padLeft(text : Text, len : Nat, char : Char) : Text {
    var result = text;
    while (result.size() < len) {
      result := Text.fromChar(char) # result;
    };
    result
  };

  /// Request testnet faucet
  public func requestTestnetFaucet(
    address : Text
  ) : async Result.Result<Text, Text> {
    try {
      let request_body = "{\"FixedAmountRequest\":{\"recipient\":\"" # address # "\"}}";

      let response = await (with cycles = 600_000_000) IC.ic.http_request({
        url = "https://faucet.testnet.sui.io/v2/gas";
        max_response_bytes = ?10000;
        headers = [
          { name = "Content-Type"; value = "application/json" }
        ];
        body = ?Text.encodeUtf8(request_body);
        method = #post;
        is_replicated = ?false;
        transform = null;
      });

      if (response.status == 200 or response.status == 201 or response.status == 202) {
        let body_text = switch (Text.decodeUtf8(response.body)) {
          case (?text) text;
          case null { "Success (no body)" };
        };
        #ok("Faucet request successful: " # body_text)
      } else {
        let error_text = switch (Text.decodeUtf8(response.body)) {
          case (?text) text;
          case null { "Unknown error" };
        };
        #err("Faucet request failed (" # debug_show(response.status) # "): " # error_text)
      };
    } catch (e) {
      #err("Faucet request error: " # Error.message(e))
    };
  };

  /// Merge multiple coins into one
  ///
  /// @param rpcUrl - SUI RPC endpoint URL
  /// @param ownerAddress - Address that owns the coins
  /// @param destinationCoinId - Coin to merge into (also used for gas)
  /// @param sourceCoinIds - Coins to merge from (will be consumed)
  /// @param gasBudget - Maximum gas budget in MIST
  /// @param signFunc - Function to sign transaction hash
  /// @param getPublicKeyFunc - Function to get public key
  /// @return Transaction digest on success
  public func mergeCoins(
    rpcUrl : Text,
    ownerAddress : Text,
    destinationCoinId : Text,
    sourceCoinIds : [Text],
    gasBudget : Nat64,
    signFunc : (messageHash : Blob) -> async Result.Result<Blob, Text>,
    getPublicKeyFunc : () -> async Result.Result<Blob, Text>,
  ) : async Result.Result<Text, Text> {
    try {
      if (sourceCoinIds.size() == 0) {
        return #err("No source coins to merge");
      };

      // Fetch destination coin info for gas
      let destCoinData = switch (await getObjectInfo(rpcUrl, destinationCoinId)) {
        case (#ok(data)) { data };
        case (#err(e)) { return #err("Failed to get destination coin info: " # e) };
      };

      // Fetch source coin info
      var sourceCoinRefs : [ObjectRef] = [];
      for (coinId in sourceCoinIds.vals()) {
        switch (await getObjectInfo(rpcUrl, coinId)) {
          case (#ok(data)) {
            sourceCoinRefs := Array.append(sourceCoinRefs, [data]);
          };
          case (#err(e)) { return #err("Failed to get source coin info: " # e) };
        };
      };

      // Build the merge transaction
      let txBytes = buildMergeTransaction(
        ownerAddress,
        destCoinData,
        sourceCoinRefs,
        gasBudget
      );

      Debug.print("Merge transaction bytes: " # Nat.toText(txBytes.size()));

      // Create intent message: intent (3 bytes) + txBytes
      let intent : [Nat8] = [0, 0, 0]; // TransactionData intent
      let messageToSign = Array.append(intent, txBytes);

      // Hash with Blake2b-256
      let messageHashBlob = blake2bHash(messageToSign);
      let messageHashBytes = Blob.toArray(messageHashBlob);

      // Hash again with SHA256 for signing
      let finalHashBlob = sha256Hash(messageHashBytes);

      let signature = switch (await signFunc(finalHashBlob)) {
        case (#ok(sig)) { Blob.toArray(sig) };
        case (#err(msg)) { return #err("Failed to sign: " # msg) };
      };

      let publicKey = switch (await getPublicKeyFunc()) {
        case (#ok(pk)) { Blob.toArray(pk) };
        case (#err(msg)) { return #err("Failed to get public key: " # msg) };
      };

      await executeSuiTransaction(rpcUrl, txBytes, signature, publicKey);
    } catch (e) {
      #err("Merge failed: " # Error.message(e));
    };
  };

  /// Build a merge coins transaction using BCS
  private func buildMergeTransaction(
    ownerAddress : Text,
    destCoin : ObjectRef,
    sourceCoins : [ObjectRef],
    gasBudget : Nat64
  ) : [Nat8] {
    let writer = Bcs.newWriter();

    // TransactionData::V1 variant = 0
    writer.writeULEB(0);

    // === TransactionKind::ProgrammableTransaction = 0 ===
    writer.writeULEB(0);

    // === ProgrammableTransaction.inputs (Vec<CallArg>) ===
    // We need Object inputs for destination and each source
    let numInputs = 1 + sourceCoins.size(); // destination + sources
    writer.writeULEB(numInputs);

    // Input 0: Object - destination coin (ImmOrOwnedObject)
    writer.writeULEB(1); // CallArg::Object variant = 1
    writer.writeULEB(0); // ObjectArg::ImmOrOwnedObject variant = 0
    serializeObjectRefV2(writer, destCoin);

    // Inputs 1..N: Object - source coins
    for (sourceCoin in sourceCoins.vals()) {
      writer.writeULEB(1); // CallArg::Object variant = 1
      writer.writeULEB(0); // ObjectArg::ImmOrOwnedObject variant = 0
      serializeObjectRefV2(writer, sourceCoin);
    };

    // === ProgrammableTransaction.commands (Vec<Command>) ===
    writer.writeULEB(1); // 1 command

    // Command 0: MergeCoins(destination, sources)
    writer.writeULEB(3); // MergeCoins variant = 3

    // destination: Argument::Input(0)
    writer.writeULEB(1); // Argument::Input variant = 1
    writer.write16(0);   // Input index 0

    // sources: Vec<Argument>
    writer.writeULEB(sourceCoins.size()); // number of sources
    for (i in Iter.range(0, sourceCoins.size() - 1)) {
      writer.writeULEB(1); // Argument::Input variant = 1
      writer.write16(Nat16.fromNat(i + 1)); // Input index 1, 2, 3, ...
    };

    // === sender ===
    let senderBytes = addressToBytes(ownerAddress);
    writer.writeBytes(senderBytes);

    // === GasData ===
    // payment: Vec<ObjectRef> - using destination coin
    writer.writeULEB(1);
    serializeObjectRefV2(writer, destCoin);

    // owner: SuiAddress
    writer.writeBytes(senderBytes);

    // price: u64 = 1000
    writer.write64(1000);

    // budget: u64
    writer.write64(gasBudget);

    // === expiration: TransactionExpiration::None = 0 ===
    writer.writeULEB(0);

    writer.toBytes()
  };
}