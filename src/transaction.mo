import Result "mo:base/Result";
import Array "mo:base/Array";
import Buffer "mo:base/Buffer";
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

    // Add amount as pure input (placeholder - will need proper BCS encoding)
    let amountBytes = []; // TODO: Implement BCS encoding for Nat64
    let amountArg = #Pure(amountBytes);

    // Add recipient as pure input (placeholder - will need proper BCS encoding)
    let recipientBytes = []; // TODO: Implement BCS encoding for address
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

    // Convert amounts to CallArgs (placeholder - will need proper BCS encoding)
    let amountArgs = Array.map<Nat64, CallArg>(amounts, func(_amount) {
      #Pure([]) // TODO: Implement BCS encoding for Nat64
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

  // Sign transaction data (placeholder)
  public func signTransaction(
    transactionData : TransactionData,
    _privateKey : [Nat8],
    _publicKey : [Nat8]
  ) : Result.Result<Transaction, Text> {
    let signature = "placeholder_signature";

    #ok({
      data = transactionData;
      txSignatures = [signature];
    })
  };

  // Verify transaction signature (placeholder)
  public func verifyTransaction(transaction : Transaction) : Bool {
    transaction.txSignatures.size() > 0
  };
}