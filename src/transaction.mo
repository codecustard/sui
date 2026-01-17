import Result "mo:base/Result";
import Array "mo:base/Array";
import Buffer "mo:base/Buffer";
import Nat8 "mo:base/Nat8";
import Nat32 "mo:base/Nat32";
import Nat64 "mo:base/Nat64";
import Text "mo:base/Text";
import Char "mo:base/Char";
import Iter "mo:base/Iter";
import BaseX "mo:base-x-encoder";
import Types "types";

module {
  public type TransactionData = Types.TransactionData;
  public type Transaction = Types.Transaction;
  public type TransactionKind = Types.TransactionKind;
  public type CallArg = Types.CallArg;
  public type Argument = Types.Argument;
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

    /// Create an Input argument from an input index
    public func input(index : Nat) : Argument {
      #Input(index)
    };

    /// Create a Result argument from a command result index
    public func result(index : Nat) : Argument {
      #Result(index)
    };

    /// Create a NestedResult argument from command and nested indices
    public func nestedResult(commandIndex : Nat, resultIndex : Nat) : Argument {
      #NestedResult(commandIndex, resultIndex)
    };

    /// Create a GasCoin argument (equivalent to tx.gas in SUI SDK)
    public func gas() : Argument {
      #GasCoin()
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
      arguments : [Argument]
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
    public func transferObjects(objects : [Argument], recipient : Argument) : Nat {
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
    public func splitCoins(coin : Argument, amounts : [Argument]) : Nat {
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
    public func mergeCoins(destination : Argument, sources : [Argument]) : Nat {
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
    let recipientBytes = encodeBCSAddress(recipient);
    let recipientIdx = builder.addInput(recipientBytes);
    let recipientArg = #Result(recipientIdx);

    // Add objects to transfer - first add them as inputs, then reference them
    let objectArgs = Array.map<ObjectRef, Argument>(objectRefs, func(ref) {
      let inputIdx = builder.addObjectInput(ref);
      builder.input(inputIdx)
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

    // Add arguments as inputs first, then create Argument references
    let argumentRefs = Array.map<CallArg, Argument>(arguments, func(arg) {
      switch (arg) {
        case (#Pure(bytes)) {
          let inputIdx = builder.addInput(bytes);
          builder.input(inputIdx)
        };
        case (#Object(objRef)) {
          let inputIdx = builder.addObjectInput(objRef);
          builder.input(inputIdx)
        };
      }
    });

    // Add the move call command
    ignore builder.moveCall(package, moduleName, functionName, typeArguments, argumentRefs);

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

    // Add the coin object as input
    let coinInputIndex = builder.addObjectInput(coinObjectRef);

    // Add recipient address as input using proper BCS encoding
    let recipientBytes = encodeBCSAddress(recipient);
    let recipientInputIndex = builder.addInput(recipientBytes);

    // Add amount as input
    let amountInputIndex = builder.addInput(encodeBCSNat64(amount));

    // Split the coin to get the exact amount
    let splitResultIndex = builder.splitCoins(#Result(coinInputIndex), [#Result(amountInputIndex)]);

    // Transfer the split coin to recipient (use Result to reference the Pure input)
    ignore builder.transferObjects([#NestedResult(splitResultIndex, 0)], #Result(recipientInputIndex));

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
    let coinInputIdx = builder.addObjectInput(coinObjectRef);
    let coinArg = builder.input(coinInputIdx);

    // Convert amounts to Arguments (BCS encoded)
    let amountArgs = Array.map<Nat64, Argument>(amounts, func(amount) {
      let inputIdx = builder.addInput(encodeBCSNat64(amount));
      builder.input(inputIdx)
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

    // Convert object refs to Arguments
    let destinationInputIdx = builder.addObjectInput(destinationCoin);
    let destinationArg = builder.input(destinationInputIdx);

    let sourceArgs = Array.map<ObjectRef, Argument>(sourceCoinRefs, func(ref) {
      let inputIdx = builder.addObjectInput(ref);
      builder.input(inputIdx)
    });

    // Add merge command
    ignore builder.mergeCoins(destinationArg, sourceArgs);

    builder.build(sender, gasData)
  };

  /// Sign transaction data with Ed25519.
  ///
  /// Creates a properly formatted SUI transaction signature.
  /// Note: This is a simplified implementation. In production, use proper Ed25519 library.
  ///
  /// @param transactionData The transaction data to sign
  /// @param privateKey Ed25519 private key (32 bytes)
  /// @param publicKey Ed25519 public key (32 bytes)
  /// @return Signed transaction or error
  public func signTransaction(
    transactionData : TransactionData,
    privateKey : [Nat8],
    publicKey : [Nat8]
  ) : Result.Result<Transaction, Text> {
    // Validate key sizes
    if (privateKey.size() != 32) {
      return #err("Private key must be 32 bytes");
    };
    if (publicKey.size() != 32) {
      return #err("Public key must be 32 bytes");
    };

    // Serialize transaction data for signing
    let txBytes = serializeTransaction(transactionData);

    // Create the message to sign (with SUI's intent prefix)
    let intent : [Nat8] = [0, 0, 0]; // TransactionData intent
    let _messageToSign = Array.append(intent, txBytes);

    // TODO: Replace with actual Ed25519 signature
    // For now, create a placeholder signature with proper format
    let signatureBytes = Array.tabulate<Nat8>(64, func(i) { 0 }); // 64-byte Ed25519 signature

    // SUI signature format: [signature_scheme_flag] + [signature] + [public_key]
    let suiSignature = Array.flatten<Nat8>([
      [0x00 : Nat8], // Ed25519 flag
      signatureBytes,
      publicKey
    ]);

    // Encode signature as base64 for SUI format
    let signatureBase64 = BaseX.toBase64(suiSignature.vals(), #standard({ includePadding = true }));

    #ok({
      data = transactionData;
      txSignatures = [signatureBase64];
    })
  };

  /// Verify transaction signature.
  ///
  /// Validates that the transaction has proper signatures.
  /// Note: This is a basic validation. Full verification would require Ed25519 verification.
  ///
  /// @param transaction The signed transaction to verify
  /// @return True if signatures are present and well-formed
  public func verifyTransaction(transaction : Transaction) : Bool {
    if (transaction.txSignatures.size() == 0) {
      return false;
    };

    // Check each signature format
    for (sig in transaction.txSignatures.vals()) {
      // Verify base64 format
      switch (BaseX.fromBase64(sig)) {
        case (#ok(bytes)) {
          // SUI signatures should be 97 bytes: 1 (flag) + 64 (signature) + 32 (pubkey)
          if (bytes.size() != 97) {
            return false;
          };
          // Check flag is valid (0x00 for Ed25519)
          if (bytes[0] != 0x00) {
            return false;
          };
        };
        case (#err(_)) {
          return false;
        };
      };
    };

    true
  };

  /// Serialize SUI IntentMessage to BCS format.
  ///
  /// Converts an IntentMessage wrapping TransactionData into binary format
  /// suitable for network transmission and signing. This is the correct format
  /// that SUI expects according to the official SDK.
  ///
  /// @param intent_msg The intent message to serialize
  /// @return BCS-encoded transaction bytes
  public func serializeIntentMessage(intent_msg : Types.IntentMessage) : [Nat8] {
    let buffer = Buffer.Buffer<Nat8>(512);

    // Serialize Intent first (3 bytes: scope, version, app_id)
    buffer.add(intent_msg.intent.scope);
    buffer.add(intent_msg.intent.version);
    buffer.add(intent_msg.intent.app_id);

    // Then serialize the TransactionData
    let txDataBytes = serializeTransaction(intent_msg.value);
    for (byte in txDataBytes.vals()) {
      buffer.add(byte);
    };

    Buffer.toArray(buffer)
  };

  /// Create a SUI transaction intent.
  ///
  /// Creates the standard intent used for SUI transactions.
  ///
  /// @return Standard SUI transaction intent
  public func createTransactionIntent() : Types.Intent {
    {
      scope = 0;    // TransactionData = 0
      version = 0;  // Current version = 0 (Intent version, not TransactionData version)
      app_id = 0;   // PersonalMessage = 0
    }
  };

  // Serialize TransactionData to BCS bytes for SUI network
  public func serializeTransaction(tx_data : TransactionData) : [Nat8] {
    let buffer = Buffer.Buffer<Nat8>(512);

    // SUI TransactionData BCS format

    // 0. Version (u8)
    buffer.add(tx_data.version);

    // 1. TransactionKind
    switch (tx_data.kind) {
      case (#ProgrammableTransaction(pt)) {
        buffer.add(0); // Single byte tag for ProgrammableTransaction

        // Serialize inputs
        serializeULEB128(buffer, pt.inputs.size());
        for (input in pt.inputs.vals()) {
          serializeCallArg(buffer, input);
        };

        // Serialize commands
        serializeULEB128(buffer, pt.commands.size());
        for (command in pt.commands.vals()) {
          switch (command) {
            case (#MoveCall(move_call)) {
              buffer.add(0); // SUI SDK: MoveCall = 0

              serializeAddress(buffer, move_call.package);
              serializeString(buffer, move_call.moduleName);
              serializeString(buffer, move_call.functionName);

              // Type arguments
              serializeULEB128(buffer, move_call.typeArguments.size());
              for (type_arg in move_call.typeArguments.vals()) {
                serializeString(buffer, type_arg);
              };

              // Arguments - use serializeArgument for command arguments
              serializeULEB128(buffer, move_call.arguments.size());
              for (arg in move_call.arguments.vals()) {
                serializeArgument(buffer, arg);
              };
            };
            case (#TransferObjects(transfer)) {
              buffer.add(1); // SUI SDK: TransferObjects = 1

              serializeULEB128(buffer, transfer.objects.size());
              for (obj in transfer.objects.vals()) {
                serializeArgument(buffer, obj);
              };
              serializeArgument(buffer, transfer.address);
            };
            case (#SplitCoins(split)) {
              buffer.add(2); // SUI SDK: SplitCoins = 2

              serializeArgument(buffer, split.coin);
              serializeULEB128(buffer, split.amounts.size());
              for (amount in split.amounts.vals()) {
                serializeArgument(buffer, amount);
              };
            };
            case (#MergeCoins(merge)) {
              buffer.add(3); // SUI SDK: MergeCoins = 3

              serializeArgument(buffer, merge.destination);
              serializeULEB128(buffer, merge.sources.size());
              for (source in merge.sources.vals()) {
                serializeArgument(buffer, source);
              };
            };
            case (#Publish(publish)) {
              buffer.add(4); // SUI SDK: Publish = 4
              serializeULEB128(buffer, publish.modules.size());
              for (mod in publish.modules.vals()) {
                serializeString(buffer, mod);
              };
              serializeULEB128(buffer, publish.dependencies.size());
              for (dep in publish.dependencies.vals()) {
                let depBytes = encodeBCSAddress(dep);
                for (b in depBytes.vals()) {
                  buffer.add(b);
                };
              };
            };
            case (#MakeMoveVec(makeVec)) {
              buffer.add(5); // SUI SDK: MakeMoveVec = 5
              // Serialize optional type
              switch (makeVec.type_) {
                case (null) {
                  buffer.add(0); // None variant
                };
                case (?t) {
                  buffer.add(1); // Some variant
                  serializeString(buffer, t);
                };
              };
              serializeULEB128(buffer, makeVec.elements.size());
              for (element in makeVec.elements.vals()) {
                serializeArgument(buffer, element);
              };
            };
            case (#Upgrade(upgrade)) {
              buffer.add(6); // SUI SDK: Upgrade = 6
              serializeULEB128(buffer, upgrade.modules.size());
              for (mod in upgrade.modules.vals()) {
                serializeString(buffer, mod);
              };
              serializeULEB128(buffer, upgrade.dependencies.size());
              for (dep in upgrade.dependencies.vals()) {
                let depBytes = encodeBCSAddress(dep);
                for (b in depBytes.vals()) {
                  buffer.add(b);
                };
              };
              let packageBytes = encodeBCSAddress(upgrade.package);
              for (b in packageBytes.vals()) {
                buffer.add(b);
              };
              serializeArgument(buffer, upgrade.ticket);
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

  /// Encode a Nat64 value as BCS bytes.
  ///
  /// BCS encodes u64 values in little-endian format.
  ///
  /// Encode an ObjectRef as BCS bytes.
  ///
  /// @param obj_ref The ObjectRef to encode
  /// @return BCS-encoded ObjectRef bytes
  public func encodeBCSObjectRef(obj_ref : ObjectRef) : [Nat8] {
    let buffer = Buffer.Buffer<Nat8>(64);
    serializeObjectRef(buffer, obj_ref);
    Buffer.toArray(buffer)
  };

  /// @param value The Nat64 value to encode
  /// @return BCS encoded byte array
  public func encodeBCSNat64(value: Nat64) : [Nat8] {
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

  /// Debug function to examine serialized transaction bytes
  ///
  /// @param tx_data The transaction data to examine
  /// @return Tuple of (first 20 bytes, total length, ascii interpretation of first 10 bytes)
  public func debugSerializeTransaction(tx_data: TransactionData) : ([Nat8], Nat, Text) {
    let bytes = serializeTransaction(tx_data);
    let first20Size = if (bytes.size() < 20) { bytes.size() } else { 20 };
    let asciiSize = if (bytes.size() < 10) { bytes.size() } else { 10 };
    let first20 = Array.tabulate<Nat8>(first20Size, func(i) { bytes[i] });
    let asciiInterpretation = Array.foldLeft<Nat8, Text>(
      Array.tabulate<Nat8>(asciiSize, func(i) { bytes[i] }),
      "",
      func(acc, byte) {
        if (byte >= 32 and byte <= 126) {
          acc # Char.toText(Char.fromNat32(Nat32.fromNat(Nat8.toNat(byte))))
        } else {
          acc # "?"
        }
      }
    );
    (first20, bytes.size(), asciiInterpretation)
  };

  /// Minimal transaction serialization for empty programmable transaction
  public func serializeMinimalTransaction(version: Nat8, sender: SuiAddress) : [Nat8] {
    let buffer = Buffer.Buffer<Nat8>(256);

    // 0. Version
    buffer.add(version);

    // 1. TransactionKind - ProgrammableTransaction with empty inputs/commands
    buffer.add(0); // Tag for ProgrammableTransaction
    buffer.add(0); // Empty inputs (size 0)
    buffer.add(0); // Empty commands (size 0)

    // 2. Sender address (32 bytes)
    let senderBytes = encodeBCSAddress(sender);
    for (byte in senderBytes.vals()) {
      buffer.add(byte);
    };

    // 3. GasData - minimal (empty payment, owner same as sender, minimal price/budget)
    buffer.add(0); // Empty payment array (size 0)

    // Gas owner (32 bytes) - same as sender
    for (byte in senderBytes.vals()) {
      buffer.add(byte);
    };

    // Gas price (u64) - 1000
    let priceBytes = encodeBCSNat64(1000);
    for (byte in priceBytes.vals()) {
      buffer.add(byte);
    };

    // Gas budget (u64) - 1000000
    let budgetBytes = encodeBCSNat64(1000000);
    for (byte in budgetBytes.vals()) {
      buffer.add(byte);
    };

    // 4. Expiration - None
    buffer.add(0); // Tag for None

    Buffer.toArray(buffer)
  };

  /// Minimal transaction serialization with custom gas budget
  public func serializeMinimalTransactionWithGas(version: Nat8, sender: SuiAddress, gasBudget: Nat64) : [Nat8] {
    let buffer = Buffer.Buffer<Nat8>(256);

    // 0. Version
    buffer.add(version);

    // 1. TransactionKind - ProgrammableTransaction with empty inputs/commands
    buffer.add(0); // Tag for ProgrammableTransaction
    buffer.add(0); // Empty inputs (size 0)
    buffer.add(0); // Empty commands (size 0)

    // 2. Sender address (32 bytes)
    let senderBytes = encodeBCSAddress(sender);
    for (byte in senderBytes.vals()) {
      buffer.add(byte);
    };

    // 3. GasData - minimal (empty payment, owner same as sender, custom budget)
    buffer.add(0); // Empty payment array (size 0)

    // Gas owner (32 bytes) - same as sender
    for (byte in senderBytes.vals()) {
      buffer.add(byte);
    };

    // Gas price (u64) - 1000
    let priceBytes = encodeBCSNat64(1000);
    for (byte in priceBytes.vals()) {
      buffer.add(byte);
    };

    // Gas budget (u64) - custom amount
    let budgetBytes = encodeBCSNat64(gasBudget);
    for (byte in budgetBytes.vals()) {
      buffer.add(byte);
    };

    // 4. Expiration - None
    buffer.add(0); // Tag for None

    Buffer.toArray(buffer)
  };

  /// Serialize just the TransactionKind (without sender, gas, expiration)
  ///
  /// @param kind The transaction kind to serialize
  /// @return BCS encoded transaction kind bytes
  public func serializeTransactionKind(kind: TransactionKind) : [Nat8] {
    let buffer = Buffer.Buffer<Nat8>(256);

    switch (kind) {
      case (#ProgrammableTransaction(pt)) {
        buffer.add(0); // Tag for ProgrammableTransaction

        // Serialize inputs
        serializeULEB128(buffer, pt.inputs.size());
        for (input in pt.inputs.vals()) {
          serializeCallArg(buffer, input);
        };

        // Serialize commands
        serializeULEB128(buffer, pt.commands.size());
        for (command in pt.commands.vals()) {
          switch (command) {
            case (#MoveCall(move_call)) {
              buffer.add(0); // Single byte tag for MoveCall
              serializeAddress(buffer, move_call.package);
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
            case (#TransferObjects(transfer)) {
              buffer.add(1); // Single byte tag for TransferObjects
              serializeULEB128(buffer, transfer.objects.size());
              for (obj in transfer.objects.vals()) {
                serializeArgument(buffer, obj);
              };
              serializeArgument(buffer, transfer.address);
            };
            case (#SplitCoins(split)) {
              buffer.add(2); // Single byte tag for SplitCoins
              serializeArgument(buffer, split.coin);
              serializeULEB128(buffer, split.amounts.size());
              for (amount in split.amounts.vals()) {
                serializeArgument(buffer, amount);
              };
            };
            case (#MergeCoins(merge)) {
              buffer.add(3); // Single byte tag for MergeCoins
              serializeArgument(buffer, merge.destination);
              serializeULEB128(buffer, merge.sources.size());
              for (source in merge.sources.vals()) {
                serializeArgument(buffer, source);
              };
            };
            case (#Publish(publish)) {
              buffer.add(4); // Single byte tag for Publish
              serializeULEB128(buffer, publish.modules.size());
              for (mod in publish.modules.vals()) {
                serializeString(buffer, mod);
              };
              serializeULEB128(buffer, publish.dependencies.size());
              for (dep in publish.dependencies.vals()) {
                let depBytes = encodeBCSAddress(dep);
                for (b in depBytes.vals()) {
                  buffer.add(b);
                };
              };
            };
            case (#MakeMoveVec(makeVec)) {
              buffer.add(5); // Single byte tag for MakeMoveVec
              // Serialize optional type
              switch (makeVec.type_) {
                case (null) {
                  buffer.add(0); // None variant
                };
                case (?t) {
                  buffer.add(1); // Some variant
                  serializeString(buffer, t);
                };
              };
              serializeULEB128(buffer, makeVec.elements.size());
              for (element in makeVec.elements.vals()) {
                serializeArgument(buffer, element);
              };
            };
            case (#Upgrade(upgrade)) {
              buffer.add(6); // Single byte tag for Upgrade
              serializeULEB128(buffer, upgrade.modules.size());
              for (mod in upgrade.modules.vals()) {
                serializeString(buffer, mod);
              };
              serializeULEB128(buffer, upgrade.dependencies.size());
              for (dep in upgrade.dependencies.vals()) {
                let depBytes = encodeBCSAddress(dep);
                for (b in depBytes.vals()) {
                  buffer.add(b);
                };
              };
              let packageBytes = encodeBCSAddress(upgrade.package);
              for (b in packageBytes.vals()) {
                buffer.add(b);
              };
              serializeArgument(buffer, upgrade.ticket);
            };
          };
        };
      };
    };


    Buffer.toArray(buffer)
  };

  /// Encode a SUI address as BCS bytes.
  ///
  /// SUI addresses are 32-byte values encoded directly as bytes.
  ///
  /// @param address The address string (with or without 0x prefix)
  /// @return BCS encoded 32-byte array
  public func encodeBCSAddress(address: SuiAddress) : [Nat8] {
    let hex = if (Text.startsWith(address, #text("0x"))) {
      switch (Text.stripStart(address, #text("0x"))) {
        case (?h) h;
        case null "";
      }
    } else {
      address
    };

    let bytes = hexToBytes(hex);

    // Ensure exactly 32 bytes (pad with leading zeros if needed)
    if (bytes.size() >= 32) {
      // Take last 32 bytes if too long
      Array.tabulate<Nat8>(32, func(i) {
        bytes[bytes.size() - 32 + i]
      })
    } else {
      // Pad with leading zeros
      let padding = 32 - bytes.size();
      Array.tabulate<Nat8>(32, func(i) {
        if (i < padding) {
          0
        } else {
          bytes[i - padding]
        }
      })
    }
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

  private func serializeU16(buffer: Buffer.Buffer<Nat8>, value: Nat) {
    buffer.add(Nat8.fromNat(value % 256));
    buffer.add(Nat8.fromNat((value / 256) % 256));
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
      switch (Text.stripStart(address, #text("0x"))) {
        case (?h) h;
        case null "";
      }
    } else {
      address
    };

    // Always ensure we get exactly 32 bytes
    let bytes = hexToBytes(hex);
    if (bytes.size() < 32) {
      // Pad with leading zeros
      let padding_needed = 32 - bytes.size();
      for (i in Iter.range(0, padding_needed - 1)) {
        buffer.add(0);
      };
      for (byte in bytes.vals()) {
        buffer.add(byte);
      };
    } else if (bytes.size() == 32) {
      // Perfect size
      for (byte in bytes.vals()) {
        buffer.add(byte);
      };
    } else {
      // Too long, take last 32 bytes
      for (i in Iter.range(bytes.size() - 32, bytes.size() - 1)) {
        buffer.add(bytes[i]);
      };
    };
  };

  private func serializeObjectRef(buffer: Buffer.Buffer<Nat8>, obj_ref: ObjectRef) {
    // BCS ObjectRef: just serialize the three fields in order (no struct wrapper)
    // Per BCS spec: "There are no structs in BCS; the struct simply defines the order"

    // 1. ObjectID (32 bytes) - raw address bytes
    let obj_id_bytes = encodeBCSAddress(obj_ref.objectId);
    for (byte in obj_id_bytes.vals()) {
      buffer.add(byte);
    };

    // 2. Version (8 bytes LE) - raw u64 bytes
    serializeU64(buffer, obj_ref.version);

    // 3. Digest (32 bytes) - raw digest bytes from base64
    let digest_bytes_raw = switch (BaseX.fromBase64(obj_ref.digest)) {
      case (#ok(bytes)) { bytes };
      case (#err(_)) { Array.tabulate<Nat8>(32, func(_) { 0 }) };
    };

    // Ensure exactly 32 bytes for digest
    let digest_bytes = if (digest_bytes_raw.size() == 33) {
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

    for (byte in digest_bytes.vals()) {
      buffer.add(byte);
    };
  };

  // Serialize CallArg (for transaction inputs) - matches SUI SDK order
  private func serializeCallArg(buffer: Buffer.Buffer<Nat8>, arg: CallArg) {
    switch (arg) {
      case (#Pure(data)) {
        buffer.add(0); // SUI SDK: Pure = 0
        serializeULEB128(buffer, data.size());
        for (byte in data.vals()) {
          buffer.add(byte);
        };
      };
      case (#Object(obj_ref)) {
        buffer.add(1); // SUI SDK: Object = 1
        serializeObjectRef(buffer, obj_ref);
      };
    };
  };

  // Serialize Argument (for command arguments) - matches SUI SDK order
  private func serializeArgument(buffer: Buffer.Buffer<Nat8>, arg: Argument) {
    switch (arg) {
      case (#GasCoin()) {
        buffer.add(0); // SUI SDK: GasCoin = 0
        // GasCoin has no additional data
      };
      case (#Input(index)) {
        buffer.add(1); // SUI SDK: Input = 1
        serializeU16(buffer, index);
      };
      case (#Result(index)) {
        buffer.add(2); // SUI SDK: Result = 2
        serializeU16(buffer, index);
      };
      case (#NestedResult(outer, inner)) {
        buffer.add(3); // SUI SDK: NestedResult = 3
        serializeU16(buffer, outer);
        serializeU16(buffer, inner);
      };
    };
  };

  private func hexToBytes(hex: Text) : [Nat8] {
    // Handle empty hex string
    if (Text.size(hex) == 0) {
      return Array.tabulate<Nat8>(32, func(_) { 0 }); // Return 32 zeros for empty hex
    };

    let chars = Text.toArray(hex);
    let bytes = Buffer.Buffer<Nat8>(0);
    var i = 0;

    // Handle odd number of hex characters by padding with leading zero
    let paddedHex = if (chars.size() % 2 == 1) {
      "0" # hex
    } else {
      hex
    };

    let paddedChars = Text.toArray(paddedHex);

    while (i + 1 < paddedChars.size()) {
      let high = hexCharToNat(paddedChars[i]);
      let low = hexCharToNat(paddedChars[i + 1]);
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
}