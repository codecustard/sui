/// Core type definitions for SUI blockchain operations.
///
/// This module contains all the fundamental types used throughout the SUI library
/// for representing addresses, transactions, commands, and other blockchain primitives.

module {
  /// SUI blockchain address.
  ///
  /// A SUI address is a 32-byte identifier represented as a hexadecimal string
  /// with "0x" prefix. Addresses are used to identify accounts, objects, and
  /// smart contracts on the SUI blockchain.
  ///
  /// Example: "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
  public type SuiAddress = Text;

  /// SUI object identifier.
  ///
  /// Object IDs uniquely identify objects on the SUI blockchain. They follow
  /// the same format as SUI addresses (32-byte hex strings with "0x" prefix).
  public type ObjectID = Text;

  /// Transaction digest identifier.
  ///
  /// A unique identifier for a transaction, typically represented as a
  /// base64-encoded or hex-encoded hash of the transaction data.
  public type TransactionDigest = Text;

  /// Cryptographic signature.
  ///
  /// Digital signature data, typically base64-encoded, used to authorize
  /// transactions on the SUI blockchain.
  public type Signature = Text;

  // Forward declare complex types for dependencies
  public type ObjectRef = {
    objectId: ObjectID;
    version: Nat64;
    digest: Text;
  };

  // SUI SDK CallArg - for transaction inputs
  public type CallArg = {
    #Pure: [Nat8];           // SUI SDK: Pure with bytes
    #Object: ObjectRef;      // SUI SDK: Object with ObjectArg
  };

  // SUI SDK Argument - for command arguments
  public type Argument = {
    #GasCoin: ();           // SUI SDK: GasCoin: null
    #Input: Nat;            // SUI SDK: Input: bcs.u16()
    #Result: Nat;           // SUI SDK: Result: bcs.u16()
    #NestedResult: (Nat, Nat); // SUI SDK: NestedResult: bcs.tuple([u16, u16])
  };

  // Legacy type for backward compatibility
  public type LegacyCallArg = {
    #Pure: [Nat8];
    #Object: ObjectRef;
    #ObjVec: [ObjectRef];
    #Result: Nat;
    #NestedResult: (Nat, Nat);
    #Receiving: ObjectRef;
    #UnresolvedPure: [Nat8];
    #GasCoin: ();
  };

  public type GasData = {
    payment: [ObjectRef];
    owner: SuiAddress;
    price: Nat64;
    budget: Nat64;
  };

  public type Command = {
    #MoveCall: {
      package: ObjectID;
      moduleName: Text;
      functionName: Text;
      typeArguments: [Text];
      arguments: [Argument];  // Commands use Argument, not CallArg
    };
    #TransferObjects: {
      objects: [Argument];    // Commands use Argument, not CallArg
      address: Argument;      // Commands use Argument, not CallArg
    };
    #SplitCoins: {
      coin: Argument;         // Commands use Argument, not CallArg
      amounts: [Argument];    // Commands use Argument, not CallArg
    };
    #MergeCoins: {
      destination: Argument;  // Commands use Argument, not CallArg
      sources: [Argument];    // Commands use Argument, not CallArg
    };
    #Publish: {
      modules: [Text];
      dependencies: [ObjectID];
    };
    #MakeMoveVec: {
      type_: ?Text;
      elements: [Argument];   // Commands use Argument, not CallArg
    };
    #Upgrade: {
      modules: [Text];
      dependencies: [ObjectID];
      package: ObjectID;
      ticket: Argument;       // Commands use Argument, not CallArg
    };
  };

  public type TransactionKind = {
    #ProgrammableTransaction: {
      inputs: [CallArg];
      commands: [Command];
    };
  };

  public type TransactionExpiration = {
    #None;
    #Epoch: Nat64;
  };

  public type TransactionData = {
    version: Nat8;
    sender: SuiAddress;
    gasData: GasData;
    kind: TransactionKind;
    expiration: TransactionExpiration;
  };

  public type Transaction = {
    data: TransactionData;
    txSignatures: [Signature];
  };

  /// Intent for transaction signing.
  ///
  /// Based on SUI's Intent structure used for transaction signing.
  /// The intent specifies what type of data is being signed.
  public type Intent = {
    scope: Nat8;     // 0 = TransactionData
    version: Nat8;   // 0 = current version
    app_id: Nat8;    // 0 = PersonalMessage
  };

  /// Intent message wrapper for transaction data.
  ///
  /// SUI requires all transaction data to be wrapped in an IntentMessage
  /// before BCS serialization and signing.
  public type IntentMessage = {
    intent: Intent;
    value: TransactionData;
  };

  public type SignatureScheme = {
    #ED25519;
    #Secp256k1;
    #Secp256r1;
  };

  public type KeyPair = {
    publicKey: [Nat8];
    privateKey: [Nat8];
    scheme: SignatureScheme;
  };

  public type SuiCoin = {
    coinType: Text;
    coinObjectId: ObjectID;
    version: Nat64;
    digest: Text;
    balance: Nat64;
    previousTransaction: TransactionDigest;
  };

}