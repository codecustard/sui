import Result "mo:base/Result";
import Array "mo:base/Array";
import Buffer "mo:base/Buffer";
import Nat8 "mo:base/Nat8";
import Nat32 "mo:base/Nat32";
import Nat64 "mo:base/Nat64";
import Text "mo:base/Text";
import Char "mo:base/Char";
import Iter "mo:base/Iter";
import Types "types";

module {
  public type TransactionData = Types.TransactionData;
  public type Transaction = Types.Transaction;
  public type CallArg = Types.CallArg;
  public type ObjectRef = Types.ObjectRef;
  public type GasData = Types.GasData;
  public type SuiAddress = Types.SuiAddress;
  public type ObjectID = Types.ObjectID;
  public type Command = Types.Command;

  /// Transaction Builder for constructing SUI programmable transactions.
  ///
  /// This provides a clean interface for building complex SUI transactions
  /// with multiple commands in the correct order.
  public class TransactionBuilder() {
    private let inputs = Buffer.Buffer<CallArg>(8);
    private let commands = Buffer.Buffer<Command>(8);

    /// Add a pure input (raw bytes) to the transaction.
    ///
    /// @param data The byte data to add as input
    /// @return Index of the added input for use in commands
    public func addInput(data : [Nat8]) : Nat {
      inputs.add(#Pure(data));
      inputs.size() - 1
    };

    /// Add an object input to the transaction.
    ///
    /// @param objectRef Reference to the object to use
    /// @return Index of the added input for use in commands
    public func addObjectInput(objectRef : ObjectRef) : Nat {
      inputs.add(#Object(objectRef));
      inputs.size() - 1
    };

    /// Add a move call command.
    ///
    /// @param package Package object ID containing the module
    /// @param moduleName Name of the module
    /// @param functionName Name of the function to call
    /// @param typeArguments Type arguments for the function
    /// @param arguments Argument indices from inputs
    /// @return Index of the command
    public func moveCall(
      package : ObjectID,
      moduleName : Text,
      functionName : Text,
      typeArguments : [Text],
      arguments : [CallArg]
    ) : Nat {
      commands.add(#MoveCall({
        package = package;
        moduleName = moduleName;
        functionName = functionName;
        typeArguments = typeArguments;
        arguments = arguments;
      }));
      commands.size() - 1
    };

    /// Transfer objects to an address.
    ///
    /// @param objects Object arguments to transfer
    /// @param recipient Address argument for recipient
    /// @return Index of the command
    public func transferObjects(objects : [CallArg], recipient : CallArg) : Nat {
      commands.add(#TransferObjects({
        objects = objects;
        address = recipient;
      }));
      commands.size() - 1
    };

    /// Split coins into specified amounts.
    ///
    /// @param coin Coin argument to split
    /// @param amounts Amount arguments for each split
    /// @return Index of the command
    public func splitCoins(coin : CallArg, amounts : [CallArg]) : Nat {
      commands.add(#SplitCoins({
        coin = coin;
        amounts = amounts;
      }));
      commands.size() - 1
    };

    /// Merge coins into a destination coin.
    ///
    /// @param destination Destination coin argument
    /// @param sources Source coin arguments to merge
    /// @return Index of the command
    public func mergeCoins(destination : CallArg, sources : [CallArg]) : Nat {
      commands.add(#MergeCoins({
        destination = destination;
        sources = sources;
      }));
      commands.size() - 1
    };

    /// Build the final transaction data.
    ///
    /// @param sender Address of the transaction sender
    /// @param gasData Gas configuration for the transaction
    /// @return Complete transaction data ready for signing
    public func build(sender : SuiAddress, gasData : GasData) : TransactionData {
      {
        version = 1 : Nat8;
        sender = sender;
        gasData = gasData;
        kind = #ProgrammableTransaction({
          inputs = Buffer.toArray(inputs);
          commands = Buffer.toArray(commands);
        });
        expiration = #None;
      }
    };
  };

  /// Create a simple transfer transaction using the builder.
  ///
  /// Transfers objects from sender to recipient.
  ///
  /// @param sender Address of the transaction sender
  /// @param recipient Address of the recipient
  /// @param objectRefs Objects to transfer
  /// @param gasData Gas configuration
  /// @return Complete transaction data
  public func createTransferTransaction(
    sender : SuiAddress,
    recipient : SuiAddress,
    objectRefs : [ObjectRef],
    gasData : GasData
  ) : TransactionData {
    let builder = TransactionBuilder();

    // Add recipient address as input
    let recipientIdx = builder.addInput([]); // Pure input for address
    let recipientArg = #Pure([]); // Will be replaced with proper address encoding

    // Add objects to transfer
    let objectArgs = Array.map<ObjectRef, CallArg>(objectRefs, func(ref) {
      #Object(ref)
    });

    // Add transfer command
    ignore builder.transferObjects(objectArgs, recipientArg);

    builder.build(sender, gasData)
  };

  /// Create a move call transaction using the builder.
  ///
  /// Calls a Move function in a specified package and module.
  ///
  /// @param sender Address of the transaction sender
  /// @param package Package object ID containing the module
  /// @param moduleName Name of the module
  /// @param functionName Name of the function to call
  /// @param typeArguments Type arguments for the function
  /// @param arguments Arguments for the function call
  /// @param gasData Gas configuration
  /// @return Complete transaction data
  public func createMoveCallTransaction(
    sender : SuiAddress,
    package : ObjectID,
    moduleName : Text,
    functionName : Text,
    typeArguments : [Text],
    arguments : [CallArg],
    gasData : GasData
  ) : TransactionData {
    let builder = TransactionBuilder();

    // Add the move call command
    ignore builder.moveCall(package, moduleName, functionName, typeArguments, arguments);

    builder.build(sender, gasData)
  };

  /// Create a SUI coin transfer transaction.
  ///
  /// Transfers SUI coins from sender to recipient using the SUI framework.
  ///
  /// @param sender Address of the transaction sender
  /// @param recipient Address of the recipient
  /// @param amount Amount of SUI to transfer (in MIST)
  /// @param coinObjectRef Reference to the SUI coin object to use
  /// @param gasData Gas configuration
  /// @return Complete transaction data
  public func createSuiTransferTransaction(
    sender : SuiAddress,
    recipient : SuiAddress,
    amount : Nat64,
    coinObjectRef : ObjectRef,
    gasData : GasData
  ) : TransactionData {
    let builder = TransactionBuilder();

    // Add coin object as input
    let coinArg = #Object(coinObjectRef);

    // Add amount as pure input with proper BCS encoding
    let amountBytes = encodeU64ToBCS(amount);
    let amountArg = #Pure(amountBytes);

    // Add recipient as pure input with proper BCS encoding
    let recipientBytes = encodeAddressToBCS(recipient);
    let recipientArg = #Pure(recipientBytes);

    // Call the SUI transfer function
    ignore builder.moveCall(
      "0x0000000000000000000000000000000000000000000000000000000000000002", // SUI framework
      "pay",
      "split_and_transfer",
      ["0x2::sui::SUI"],
      [coinArg, amountArg, recipientArg]
    );

    builder.build(sender, gasData)
  };

  /// Create a coin split transaction.
  ///
  /// Splits a coin into multiple coins with specified amounts.
  ///
  /// @param sender Address of the transaction sender
  /// @param coinObjectRef Reference to the coin object to split
  /// @param amounts Array of amounts to split into
  /// @param gasData Gas configuration
  /// @return Complete transaction data
  public func createCoinSplitTransaction(
    sender : SuiAddress,
    coinObjectRef : ObjectRef,
    amounts : [Nat64],
    gasData : GasData
  ) : TransactionData {
    let builder = TransactionBuilder();

    // Add coin object as input
    let coinArg = #Object(coinObjectRef);

    // Convert amounts to CallArgs with proper BCS encoding
    let amountArgs = Array.map<Nat64, CallArg>(amounts, func(amount) {
      #Pure(encodeU64ToBCS(amount))
    });

    // Add split command
    ignore builder.splitCoins(coinArg, amountArgs);

    builder.build(sender, gasData)
  };

  /// Create a coin merge transaction.
  ///
  /// Merges multiple coins into a single destination coin.
  ///
  /// @param sender Address of the transaction sender
  /// @param destinationCoin Reference to the destination coin
  /// @param sourceCoinRefs References to source coins to merge
  /// @param gasData Gas configuration
  /// @return Complete transaction data
  public func createCoinMergeTransaction(
    sender : SuiAddress,
    destinationCoin : ObjectRef,
    sourceCoinRefs : [ObjectRef],
    gasData : GasData
  ) : TransactionData {
    let builder = TransactionBuilder();

    // Convert object refs to CallArgs
    let destinationArg = #Object(destinationCoin);
    let sourceArgs = Array.map<ObjectRef, CallArg>(sourceCoinRefs, func(ref) {
      #Object(ref)
    });

    // Add merge command
    ignore builder.mergeCoins(destinationArg, sourceArgs);

    builder.build(sender, gasData)
  };

  /// Sign transaction data using ICP threshold ECDSA.
  ///
  /// NOTE: This function is deprecated. For actual transaction signing,
  /// use the Wallet class from the wallet.mo module, which provides
  /// proper integration with ICP's threshold ECDSA and SUI network.
  ///
  /// Example:
  /// ```motoko
  /// import Wallet "wallet";
  ///
  /// let wallet = Wallet.createDevnetWallet("test_key_1");
  /// let signature = await wallet.signTransaction(tx_data, ?"0");
  /// ```
  ///
  /// @param transactionData The transaction data to sign
  /// @param _privateKey Unused - kept for API compatibility
  /// @param _publicKey Unused - kept for API compatibility
  /// @return Error directing to use Wallet class
  public func signTransaction(
    transactionData : TransactionData,
    _privateKey : [Nat8],
    _publicKey : [Nat8]
  ) : Result.Result<Transaction, Text> {
    #err("signTransaction is deprecated. Use Wallet.signTransaction() from wallet.mo for proper ICP threshold ECDSA signing.")
  };

  /// Verify transaction signature.
  ///
  /// NOTE: Basic verification only. For production use, implement
  /// proper ECDSA signature verification with secp256k1.
  ///
  /// @param transaction The transaction to verify
  /// @return True if transaction has at least one signature
  public func verifyTransaction(transaction : Transaction) : Bool {
    transaction.txSignatures.size() > 0
  };

  // Serialize TransactionData to BCS bytes for SUI network
  public func serializeTransaction(tx_data : TransactionData) : [Nat8] {
    let buffer = Buffer.Buffer<Nat8>(512);

    // SUI TransactionData BCS format:
    // 1. TransactionKind
    switch (tx_data.kind) {
      case (#ProgrammableTransaction(pt)) {
        buffer.add(0); // Tag for ProgrammableTransaction

        // Serialize inputs
        serializeULEB128(buffer, pt.inputs.size());
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
              serializeObjectRef(buffer, obj_ref);
            };
            case (#ObjVec(obj_refs)) {
              buffer.add(2); // Tag for ObjVec
              serializeULEB128(buffer, obj_refs.size());
              for (obj_ref in obj_refs.vals()) {
                serializeObjectRef(buffer, obj_ref);
              };
            };
          };
        };

        // Serialize commands
        serializeULEB128(buffer, pt.commands.size());
        for (command in pt.commands.vals()) {
          switch (command) {
            case (#MoveCall(move_call)) {
              buffer.add(0); // Tag for MoveCall

              // Package (32 bytes)
              serializeAddress(buffer, move_call.package);

              // Module name
              serializeString(buffer, move_call.moduleName);

              // Function name
              serializeString(buffer, move_call.functionName);

              // Type arguments
              serializeULEB128(buffer, move_call.typeArguments.size());
              for (type_arg in move_call.typeArguments.vals()) {
                serializeString(buffer, type_arg);
              };

              // Arguments
              serializeULEB128(buffer, move_call.arguments.size());
              for (arg in move_call.arguments.vals()) {
                serializeCallArg(buffer, arg);
              };
            };
            case (#TransferObjects(transfer)) {
              buffer.add(1); // Tag for TransferObjects

              serializeULEB128(buffer, transfer.objects.size());
              for (obj in transfer.objects.vals()) {
                serializeCallArg(buffer, obj);
              };
              serializeCallArg(buffer, transfer.address);
            };
            case (#SplitCoins(split)) {
              buffer.add(2); // Tag for SplitCoins

              serializeCallArg(buffer, split.coin);
              serializeULEB128(buffer, split.amounts.size());
              for (amount in split.amounts.vals()) {
                serializeCallArg(buffer, amount);
              };
            };
            case (#MergeCoins(merge)) {
              buffer.add(3); // Tag for MergeCoins

              serializeCallArg(buffer, merge.destination);
              serializeULEB128(buffer, merge.sources.size());
              for (source in merge.sources.vals()) {
                serializeCallArg(buffer, source);
              };
            };
          };
        };
      };
    };

    // 2. Sender (32 bytes)
    serializeAddress(buffer, tx_data.sender);

    // 3. GasData
    serializeULEB128(buffer, tx_data.gasData.payment.size());
    for (payment in tx_data.gasData.payment.vals()) {
      serializeObjectRef(buffer, payment);
    };
    serializeAddress(buffer, tx_data.gasData.owner);
    serializeU64(buffer, tx_data.gasData.price);
    serializeU64(buffer, tx_data.gasData.budget);

    // 4. Expiration
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

  // Helper functions for BCS serialization
  private func serializeULEB128(buffer: Buffer.Buffer<Nat8>, value: Nat) {
    var val = value;
    while (val >= 128) {
      buffer.add(Nat8.fromNat((val % 128) + 128));
      val := val / 128;
    };
    buffer.add(Nat8.fromNat(val));
  };

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

  private func serializeString(buffer: Buffer.Buffer<Nat8>, str: Text) {
    let bytes = Text.encodeUtf8(str);
    let size = bytes.size();
    serializeULEB128(buffer, size);
    for (byte in bytes.vals()) {
      buffer.add(byte);
    };
  };

  private func serializeAddress(buffer: Buffer.Buffer<Nat8>, address: Text) {
    let hex = if (Text.startsWith(address, #text("0x"))) {
      Text.stripStart(address, #text("0x"))
    } else {
      ?address
    };
    switch (hex) {
      case (?h) {
        let bytes = hexToBytes(h);
        // Ensure 32 bytes (pad with zeros if needed)
        let padding_needed = 32 - bytes.size();
        for (i in Iter.range(0, padding_needed - 1)) {
          buffer.add(0);
        };
        for (byte in bytes.vals()) {
          buffer.add(byte);
        };
      };
      case null {
        // Invalid hex, add 32 zeros
        for (i in Iter.range(0, 31)) {
          buffer.add(0);
        };
      };
    };
  };

  private func serializeObjectRef(buffer: Buffer.Buffer<Nat8>, obj_ref: ObjectRef) {
    serializeAddress(buffer, obj_ref.objectId);
    serializeU64(buffer, obj_ref.version);

    // Digest - can be base64 or hex encoded
    let digest_bytes = if (Text.startsWith(obj_ref.digest, #text("0x"))) {
      switch (Text.stripStart(obj_ref.digest, #text("0x"))) {
        case (?hex) { hexToBytes(hex) };
        case null { [] };
      }
    } else {
      // Assume base64 encoded digest
      decodeBase64ToBytes(obj_ref.digest)
    };

    // Ensure 32 bytes for digest
    let padding_needed = if (digest_bytes.size() >= 32) { 0 } else { 32 - digest_bytes.size() };
    for (i in Iter.range(0, padding_needed - 1)) {
      buffer.add(0);
    };
    for (byte in digest_bytes.vals()) {
      buffer.add(byte);
    };
  };

  private func serializeCallArg(buffer: Buffer.Buffer<Nat8>, arg: CallArg) {
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
        serializeObjectRef(buffer, obj_ref);
      };
      case (#ObjVec(obj_refs)) {
        buffer.add(2); // Tag for ObjVec
        serializeULEB128(buffer, obj_refs.size());
        for (obj_ref in obj_refs.vals()) {
          serializeObjectRef(buffer, obj_ref);
        };
      };
    };
  };

  private func hexToBytes(hex: Text) : [Nat8] {
    let chars = Text.toArray(hex);
    let bytes = Buffer.Buffer<Nat8>(0);
    var i = 0;
    while (i < chars.size() - 1) {
      let high = hexCharToNat(chars[i]);
      let low = hexCharToNat(chars[i + 1]);
      bytes.add(Nat8.fromNat(high * 16 + low));
      i += 2;
    };
    Buffer.toArray(bytes)
  };

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

  /// Encode a Nat64 value to BCS format (little-endian 8 bytes)
  public func encodeU64ToBCS(value: Nat64) : [Nat8] {
    let val = Nat64.toNat(value);
    [
      Nat8.fromNat(val % 256),
      Nat8.fromNat((val / 256) % 256),
      Nat8.fromNat((val / 65536) % 256),
      Nat8.fromNat((val / 16777216) % 256),
      Nat8.fromNat((val / 4294967296) % 256),
      Nat8.fromNat((val / 1099511627776) % 256),
      Nat8.fromNat((val / 281474976710656) % 256),
      Nat8.fromNat((val / 72057594037927936) % 256)
    ]
  };

  /// Encode a SUI address to BCS format (32 bytes)
  public func encodeAddressToBCS(address: Text) : [Nat8] {
    let hex = if (Text.startsWith(address, #text("0x"))) {
      Text.stripStart(address, #text("0x"))
    } else {
      ?address
    };

    let bytes = switch (hex) {
      case (?h) { hexToBytes(h) };
      case null { [] };
    };

    // Ensure 32 bytes (pad with leading zeros if needed)
    let buffer = Buffer.Buffer<Nat8>(32);
    let padding_needed = if (bytes.size() >= 32) { 0 } else { 32 - bytes.size() };

    for (i in Iter.range(0, padding_needed - 1)) {
      buffer.add(0);
    };
    for (byte in bytes.vals()) {
      buffer.add(byte);
    };

    Buffer.toArray(buffer)
  };

  /// Decode base64 string to bytes
  public func decodeBase64ToBytes(b64: Text) : [Nat8] {
    // Simple base64 decoder for standard base64
    let chars = Text.toArray(b64);
    let result = Buffer.Buffer<Nat8>(0);

    // Base64 character to value mapping
    func base64CharToValue(c: Char) : ?Nat8 {
      if (c >= 'A' and c <= 'Z') {
        ?Nat8.fromNat(Nat32.toNat(Char.toNat32(c) - Char.toNat32('A')))
      } else if (c >= 'a' and c <= 'z') {
        ?Nat8.fromNat(Nat32.toNat(Char.toNat32(c) - Char.toNat32('a')) + 26)
      } else if (c >= '0' and c <= '9') {
        ?Nat8.fromNat(Nat32.toNat(Char.toNat32(c) - Char.toNat32('0')) + 52)
      } else if (c == '+') {
        ?62
      } else if (c == '/') {
        ?63
      } else if (c == '=') {
        ?0  // Padding
      } else {
        null
      }
    };

    var i = 0;
    while (i < chars.size()) {
      if (i + 3 < chars.size()) {
        let v1 = switch (base64CharToValue(chars[i])) { case (?v) v; case null 0 };
        let v2 = switch (base64CharToValue(chars[i+1])) { case (?v) v; case null 0 };
        let v3 = switch (base64CharToValue(chars[i+2])) { case (?v) v; case null 0 };
        let v4 = switch (base64CharToValue(chars[i+3])) { case (?v) v; case null 0 };

        // Decode 4 base64 chars to 3 bytes
        let b1 = (v1 << 2) | (v2 >> 4);
        let b2 = ((v2 & 0x0F) << 4) | (v3 >> 2);
        let b3 = ((v3 & 0x03) << 6) | v4;

        result.add(b1);
        if (chars[i+2] != '=') { result.add(b2) };
        if (chars[i+3] != '=') { result.add(b3) };
      };
      i += 4;
    };

    Buffer.toArray(result)
  };
}