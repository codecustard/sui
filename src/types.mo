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

  public type CallArg = {
    #Pure: [Nat8];
    #Object: ObjectRef;
    #ObjVec: [ObjectRef];
  };

  public type GasData = {
    payment: [ObjectRef];
    owner: SuiAddress;
    price: Nat64;
    budget: Nat64;
  };

  public type Command = {
    #TransferObjects: {
      objects: [CallArg];
      address: CallArg;
    };
    #SplitCoins: {
      coin: CallArg;
      amounts: [CallArg];
    };
    #MergeCoins: {
      destination: CallArg;
      sources: [CallArg];
    };
    #MoveCall: {
      package: ObjectID;
      moduleName: Text;
      functionName: Text;
      typeArguments: [Text];
      arguments: [CallArg];
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