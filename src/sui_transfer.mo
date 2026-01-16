import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Debug "mo:base/Debug";
import Error "mo:base/Error";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";
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
      let txBytes = buildSuiTransactionV2(
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

  /// Dry run a transaction to validate BCS format (for debugging)
  public func dryRunTransaction(
    rpcUrl : Text,
    senderAddress : Text,
    coinObjectId : Text,
    recipientAddress : Text,
    amount : Nat64,
    gasBudget : Nat64
  ) : async Result.Result<Text, Text> {
    try {
      // First, fetch the actual coin object data from RPC
      let coinData = switch (await getObjectInfo(rpcUrl, coinObjectId)) {
        case (#ok(data)) { data };
        case (#err(e)) { return #err("Failed to fetch coin data: " # e) };
      };

      Debug.print("Coin data - version: " # Nat.toText(coinData.version) # ", digest: " # coinData.digest);

      // Build full transaction matching RPC format
      let txBytes = buildSuiTransactionV2(senderAddress, coinData, recipientAddress, amount, gasBudget);

      let txBytesBase64 = Utils.encodeBase64(txBytes);

      Debug.print("Minimal Transaction bytes size: " # Nat.toText(txBytes.size()));
      Debug.print("Transaction base64: " # txBytesBase64);

      // Dry run to validate
      let request_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"sui_dryRunTransactionBlock\"," #
        "\"params\":[\"" # txBytesBase64 # "\"]}";

      Debug.print("Dry run request: " # request_body);

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

      #ok("Dry run result (our size: " # Nat.toText(txBytes.size()) # " bytes): " # body_text)
    } catch (e) {
      #err("Dry run failed: " # Error.message(e))
    };
  };

  /// Compare our BCS with the working unsafe_transferSui approach
  public func compareBcsWithRpc(
    rpcUrl : Text,
    senderAddress : Text,
    coinObjectId : Text,
    recipientAddress : Text,
    amount : Nat64,
    gasBudget : Nat64
  ) : async Result.Result<Text, Text> {
    try {
      // Get txBytes from unsafe_transferSui
      let request_body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"unsafe_transferSui\"," #
        "\"params\":[\"" # senderAddress # "\",\"" # coinObjectId # "\",\"" #
        Nat64.toText(gasBudget) # "\",\"" # recipientAddress # "\",\"" # Nat64.toText(amount) # "\"]}";

      let response = await (with cycles = 500_000_000) IC.ic.http_request({
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

      switch (Json.parse(body_text)) {
        case (#ok(json)) {
          switch (Json.get(json, "result")) {
            case (?result) {
              switch (Json.getAsText(result, "txBytes")) {
                case (#ok(txBytesBase64)) {
                  let rpcTxBytes = Utils.decodeBase64(txBytesBase64);

                  // Now build our minimal transaction
                  let coinData = switch (await getObjectInfo(rpcUrl, coinObjectId)) {
                    case (#ok(data)) { data };
                    case (#err(e)) { return #err("Failed to fetch coin data: " # e) };
                  };

                  let ourTxBytes = buildSuiTransactionV2(senderAddress, coinData, recipientAddress, amount, gasBudget);
                  let ourTxBase64 = Utils.encodeBase64(ourTxBytes);

                  // Compare sizes
                  var comparison = "RPC txBytes size: " # Nat.toText(rpcTxBytes.size()) # " bytes\n";
                  comparison := comparison # "Our txBytes size: " # Nat.toText(ourTxBytes.size()) # " bytes\n";
                  comparison := comparison # "RPC base64: " # txBytesBase64 # "\n";
                  comparison := comparison # "Our base64: " # ourTxBase64 # "\n";

                  // Show first 20 bytes of each
                  comparison := comparison # "RPC first 20 bytes: ";
                  var i = 0;
                  for (b in rpcTxBytes.vals()) {
                    if (i < 20) {
                      comparison := comparison # Nat8.toText(b) # " ";
                    };
                    i += 1;
                  };
                  comparison := comparison # "\nOur first 20 bytes: ";
                  i := 0;
                  for (b in ourTxBytes.vals()) {
                    if (i < 20) {
                      comparison := comparison # Nat8.toText(b) # " ";
                    };
                    i += 1;
                  };

                  #ok(comparison)
                };
                case (#err(_)) { #err("No txBytes in response: " # body_text) };
              };
            };
            case (null) { #err("No result in response: " # body_text) };
          };
        };
        case (#err(_)) { #err("Failed to parse response: " # body_text) };
      };
    } catch (e) {
      #err("Compare failed: " # Error.message(e))
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
  private func buildSuiTransaction(
    senderAddress : Text,
    coinObjectId : Text,
    recipientAddress : Text,
    amount : Nat64,
    gasBudget : Nat64
  ) : [Nat8] {
    let writer = Bcs.newWriter();

    // 0. Version (u8)
    writer.write8(1); // TransactionData version

    // 1. TransactionKind - ProgrammableTransaction
    writer.writeULEB(0); // ProgrammableTransaction variant

    // Inputs section
    writer.writeULEB(3); // 3 inputs: recipient address + amount + coin object

    // Input 0: Pure recipient address (32 bytes)
    writer.writeULEB(0); // Pure variant
    let recipientBytes = addressToBytes(recipientAddress);
    writer.writeULEB(recipientBytes.size());
    writer.writeBytes(recipientBytes);

    // Input 1: Pure amount (8 bytes for u64)
    writer.writeULEB(0); // Pure variant
    let amountBytes = Bcs.serializeU64(amount);
    writer.writeULEB(amountBytes.size());
    writer.writeBytes(amountBytes);

    // Input 2: Object coin reference
    writer.writeULEB(1); // Object variant
    let coinRef = parseCoinObjectRef(coinObjectId);
    serializeObjectRef(writer, coinRef);

    // Commands section
    writer.writeULEB(2); // 2 commands: SplitCoins + TransferObjects

    // Command 0: SplitCoins
    writer.writeULEB(2); // SplitCoins variant
    // Coin argument: Input(2) - reference to coin object input
    writer.writeULEB(1); // Input variant
    writer.write16(2); // Input index 2 (coin object)
    // Amounts: [Input(1)]
    writer.writeULEB(1); // 1 amount
    writer.writeULEB(1); // Input variant
    writer.write16(1); // Input index 1 (amount)

    // Command 1: TransferObjects
    writer.writeULEB(1); // TransferObjects variant
    // Objects: [NestedResult(0, 0)]
    writer.writeULEB(1); // 1 object
    writer.writeULEB(3); // NestedResult variant
    writer.write16(0); // Command index 0
    writer.write16(0); // Result index 0
    // Recipient: Input(0)
    writer.writeULEB(1); // Input variant
    writer.write16(0); // Input index 0

    // Sender (32 bytes)
    let senderBytes = addressToBytes(senderAddress);
    writer.writeBytes(senderBytes);

    // Gas data
    writer.writeULEB(1); // 1 gas object
    serializeObjectRef(writer, coinRef); // Use same coin as gas payment
    writer.writeBytes(senderBytes); // Gas owner (same as sender)
    writer.write64(1000); // Gas price
    writer.write64(gasBudget); // Gas budget

    // Expiration: None
    writer.write8(0); // None variant

    writer.toBytes()
  };

  /// Build a MINIMAL transaction for BCS structure testing
  /// This creates an empty ProgrammableTransaction to verify the basic format
  private func buildMinimalTransaction(
    senderAddress : Text,
    coinData : ObjectRef,
    gasBudget : Nat64
  ) : [Nat8] {
    let writer = Bcs.newWriter();

    // TransactionData::V1 variant = 0
    writer.writeULEB(0);

    // TransactionKind::ProgrammableTransaction = 0
    writer.writeULEB(0);

    // ProgrammableTransaction.inputs: Vec<CallArg> (empty)
    writer.writeULEB(0);

    // ProgrammableTransaction.commands: Vec<Command> (empty)
    writer.writeULEB(0);

    // sender: SuiAddress (32 bytes)
    let senderBytes = addressToBytes(senderAddress);
    writer.writeBytes(senderBytes);

    // GasData.payment: Vec<ObjectRef>
    writer.writeULEB(1); // 1 gas payment object
    // ObjectRef: objectId (32 bytes) + version (u64) + digest (32 bytes)
    let objectIdBytes = addressToBytes(coinData.objectId);
    writer.writeBytes(objectIdBytes);
    writer.write64(Nat64.fromNat(coinData.version));
    // Digest - base58 decode
    let digestBytes = switch (BaseX.fromBase58(coinData.digest)) {
      case (#ok(bytes)) {
        if (bytes.size() >= 32) {
          Array.tabulate<Nat8>(32, func(i) { bytes[i] })
        } else {
          Array.tabulate<Nat8>(32, func(i) {
            if (i < bytes.size()) bytes[i] else 0
          })
        }
      };
      case (#err(_)) { Array.tabulate<Nat8>(32, func(_) { 0 }) };
    };
    writer.writeBytes(digestBytes);

    // GasData.owner: SuiAddress
    writer.writeBytes(senderBytes);

    // GasData.price: u64
    writer.write64(1000);

    // GasData.budget: u64
    writer.write64(gasBudget);

    // TransactionExpiration::None = 0
    writer.writeULEB(0);

    writer.toBytes()
  };

  /// Build a proper SUI transaction using BCS serialization (V2 - matching RPC format)
  /// Based on analysis of unsafe_transferSui output:
  /// - Input 0: Pure recipient address (32 bytes)
  /// - Input 1: Pure amount (8 bytes)
  /// - Command 0: SplitCoins(GasCoin, [Input(1)])
  /// - Command 1: TransferObjects([NestedResult(0,0)], Input(0))
  private func buildSuiTransactionV2(
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
          let padded = Array.tabulate<Nat8>(32, func(i) { 0 });
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

  /// Parse coin object reference (simplified)
  private func parseCoinObjectRef(coinObjectId : Text) : ObjectRef {
    {
      objectId = coinObjectId;
      version = 1; // Simplified - should fetch from RPC
      digest = "placeholder"; // Simplified - should fetch from RPC
    }
  };

  /// Serialize object reference using BCS
  private func serializeObjectRef(writer : {writeBytes : ([Nat8]) -> (); write64 : (Nat64) -> ()}, objRef : ObjectRef) {
    let objectIdBytes = addressToBytes(objRef.objectId);
    writer.writeBytes(objectIdBytes);
    writer.write64(Nat64.fromNat(objRef.version));

    // Proper digest serialization - decode from base64
    let digest_bytes_raw = switch (BaseX.fromBase64(objRef.digest)) {
      case (#ok(bytes)) { bytes };
      case (#err(_)) { Array.tabulate<Nat8>(32, func(_) { 0 }) };
    };

    // Ensure exactly 32 bytes for digest (handle SUI's 33-byte digests)
    let digestBytes = if (digest_bytes_raw.size() == 33) {
      // Remove first byte if 33 bytes (common in SUI)
      Array.tabulate<Nat8>(32, func(i) { digest_bytes_raw[i + 1] })
    } else if (digest_bytes_raw.size() == 32) {
      digest_bytes_raw
    } else if (digest_bytes_raw.size() > 32) {
      Array.tabulate<Nat8>(32, func(i) { digest_bytes_raw[i] })
    } else {
      // Pad to 32 bytes
      Array.tabulate<Nat8>(32, func(i) {
        if (i < digest_bytes_raw.size()) {
          digest_bytes_raw[i]
        } else {
          0
        }
      })
    };

    writer.writeBytes(digestBytes);
  };

  /// Object reference type
  public type ObjectRef = {
    objectId : Text;
    version : Nat;
    digest : Text;
  };
}