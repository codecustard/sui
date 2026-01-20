/// SUI Example Canister
///
/// Clean API for SUI blockchain operations on ICP:
/// - Address generation using threshold ECDSA
/// - Balance queries and coin management
/// - SUI transfers with proper BCS serialization
/// - Transaction status queries
/// - Testnet faucet requests

import Result "mo:base/Result";
import Array "mo:base/Array";
import Time "mo:base/Time";
import HashMap "mo:base/HashMap";
import Iter "mo:base/Iter";
import Text "mo:base/Text";
import Nat64 "mo:base/Nat64";
import Nat8 "mo:base/Nat8";
import Error "mo:base/Error";
import IC "mo:ic";

import Types "../src/types";
import Address "../src/address";
import Wallet "../src/wallet";
import SuiTransfer "../src/sui_transfer";

persistent actor SuiExample {
  // Type aliases
  public type SuiAddress = Types.SuiAddress;
  public type SignatureScheme = Types.SignatureScheme;
  public type SuiCoin = Types.SuiCoin;
  public type TransactionStatus = SuiTransfer.TransactionStatus;

  // Wallet info returned by generateAddress
  public type WalletInfo = {
    address : SuiAddress;
    publicKey : [Nat8];
    scheme : SignatureScheme;
    created : Int;
  };

  // State for caching generated wallets
  private var walletEntries : [(Text, WalletInfo)] = [];
  private transient var wallets = HashMap.fromIter<Text, WalletInfo>(
    walletEntries.vals(),
    walletEntries.size(),
    Text.equal,
    Text.hash
  );

  system func preupgrade() {
    walletEntries := Iter.toArray(wallets.entries());
  };

  system func postupgrade() {
    walletEntries := [];
  };

  // ============================================
  // ADDRESS OPERATIONS
  // ============================================

  /// Generate a new SUI address using ICP threshold ECDSA
  public func generateAddress(derivationPath : ?Text) : async Result.Result<WalletInfo, Text> {
    let suiWallet = Wallet.createTestnetWallet("dfx_test_key");

    switch (await suiWallet.generateAddress(derivationPath)) {
      case (#ok(addrInfo)) {
        let wallet : WalletInfo = {
          address = addrInfo.address;
          publicKey = addrInfo.public_key;
          scheme = addrInfo.scheme;
          created = Time.now();
        };
        wallets.put(wallet.address, wallet);
        #ok(wallet)
      };
      case (#err(e)) { #err(e) };
    };
  };

  /// Validate a SUI address format
  public func validateAddress(address : SuiAddress) : async Bool {
    Address.isValidAddress(address)
  };

  // ============================================
  // BALANCE OPERATIONS
  // ============================================

  /// Get balance in MIST with coin count
  public func checkBalance(address : Text) : async Result.Result<{ totalBalance : Nat64; coinCount : Nat }, Text> {
    let suiWallet = Wallet.createTestnetWallet("dfx_test_key");

    switch (await suiWallet.getBalance(address)) {
      case (#err(e)) { #err(e) };
      case (#ok(balance)) {
        #ok({
          totalBalance = balance.total_balance;
          coinCount = balance.object_count;
        })
      };
    };
  };

  /// Get human-readable balance (e.g., "1.5000 SUI")
  public func getFormattedBalance(address : Text) : async Result.Result<Text, Text> {
    switch (await checkBalance(address)) {
      case (#err(e)) { #err(e) };
      case (#ok(balance)) {
        #ok(SuiTransfer.formatBalance(balance.totalBalance))
      };
    };
  };

  /// List all coin objects for an address
  public func getSuiCoins(address : Text) : async Result.Result<[SuiCoin], Text> {
    let suiWallet = Wallet.createTestnetWallet("dfx_test_key");

    switch (await suiWallet.getBalance(address)) {
      case (#err(e)) { #err(e) };
      case (#ok(balance)) { #ok(balance.objects) };
    };
  };

  /// Get balances for multiple addresses in a single batch request
  ///
  /// Uses JSON-RPC batch requests for efficiency - one HTTP call for all addresses.
  /// @param addresses - Array of SUI addresses to query (max 50)
  /// @return Batch result with individual balance results and success/failure counts
  public func getBalances(addresses : [Text]) : async Result.Result<Wallet.BatchBalanceResult, Text> {
    let suiWallet = Wallet.createTestnetWallet("dfx_test_key");
    await suiWallet.getBalances(addresses, null)
  };

  /// Get balances with custom max address limit
  public func getBalancesWithLimit(addresses : [Text], maxAddresses : Nat) : async Result.Result<Wallet.BatchBalanceResult, Text> {
    let suiWallet = Wallet.createTestnetWallet("dfx_test_key");
    let config : Wallet.BatchConfig = { maxAddresses = ?maxAddresses };
    await suiWallet.getBalances(addresses, ?config)
  };

  // ============================================
  // TRANSFER OPERATIONS
  // ============================================

  /// Transfer SUI using BCS serialization (recommended)
  ///
  /// This method builds the transaction locally with proper BCS encoding.
  /// @param senderAddress - Sender's SUI address
  /// @param recipientAddress - Recipient's SUI address
  /// @param amount - Amount in MIST (1 SUI = 1,000,000,000 MIST)
  /// @param gasBudget - Maximum gas budget in MIST
  /// @return Transaction digest on success
  public func transferSuiSafe(
    senderAddress : Text,
    recipientAddress : Text,
    amount : Nat64,
    gasBudget : Nat64
  ) : async Result.Result<Text, Text> {
    let rpcUrl = "https://fullnode.testnet.sui.io:443";
    let suiWallet = Wallet.createTestnetWallet("dfx_test_key");

    // Get coins for sender
    let coins = switch (await suiWallet.getBalance(senderAddress)) {
      case (#err(e)) { return #err("Failed to get balance: " # e) };
      case (#ok(balance)) { balance.objects };
    };

    if (coins.size() == 0) {
      return #err("No coins available for sender");
    };

    let coin = coins[0];

    // Check sufficient balance
    if (coin.balance < amount + gasBudget) {
      return #err("Insufficient balance. Have: " # Nat64.toText(coin.balance) #
                  " MIST, need: " # Nat64.toText(amount + gasBudget) # " MIST");
    };

    // Sign function using ICP threshold ECDSA
    let signFunc = func(messageHash : Blob) : async Result.Result<Blob, Text> {
      try {
        let response = await (with cycles = 30_000_000_000) IC.ic.sign_with_ecdsa({
          message_hash = messageHash;
          derivation_path = [];
          key_id = { curve = #secp256k1; name = "dfx_test_key" };
        });
        #ok(response.signature)
      } catch (e) {
        #err("Failed to sign: " # Error.message(e))
      }
    };

    let getPublicKeyFunc = func() : async Result.Result<Blob, Text> {
      try {
        let response = await (with cycles = 30_000_000_000) IC.ic.ecdsa_public_key({
          canister_id = null;
          derivation_path = [];
          key_id = { curve = #secp256k1; name = "dfx_test_key" };
        });
        #ok(response.public_key)
      } catch (e) {
        #err("Failed to get public key: " # Error.message(e))
      }
    };

    await SuiTransfer.transferSuiSafe(
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

  /// Transfer SUI using RPC method (alternative)
  ///
  /// Uses the unsafe_transferSui RPC method. Simpler but relies on RPC
  /// to build the transaction.
  public func transferSuiSimple(
    senderAddress : Text,
    recipientAddress : Text,
    amount : Nat64,
    gasBudget : Nat64
  ) : async Result.Result<Text, Text> {
    let rpcUrl = "https://fullnode.testnet.sui.io:443";
    let suiWallet = Wallet.createTestnetWallet("dfx_test_key");

    // Get coins for sender
    let coins = switch (await suiWallet.getBalance(senderAddress)) {
      case (#err(e)) { return #err("Failed to get balance: " # e) };
      case (#ok(balance)) { balance.objects };
    };

    if (coins.size() == 0) {
      return #err("No coins available for sender");
    };

    let coin = coins[0];

    let signFunc = func(messageHash : Blob) : async Result.Result<Blob, Text> {
      try {
        let response = await (with cycles = 30_000_000_000) IC.ic.sign_with_ecdsa({
          message_hash = messageHash;
          derivation_path = [];
          key_id = { curve = #secp256k1; name = "dfx_test_key" };
        });
        #ok(response.signature)
      } catch (e) {
        #err("Failed to sign: " # Error.message(e))
      }
    };

    let getPublicKeyFunc = func() : async Result.Result<Blob, Text> {
      try {
        let response = await (with cycles = 30_000_000_000) IC.ic.ecdsa_public_key({
          canister_id = null;
          derivation_path = [];
          key_id = { curve = #secp256k1; name = "dfx_test_key" };
        });
        #ok(response.public_key)
      } catch (e) {
        #err("Failed to get public key: " # Error.message(e))
      }
    };

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

  // ============================================
  // COIN MANAGEMENT
  // ============================================

  /// Merge multiple coins into one
  ///
  /// Consolidates fragmented coin objects. Useful when you have many small coins.
  /// @param ownerAddress - Address that owns the coins
  /// @param gasBudget - Maximum gas budget in MIST
  /// @return Transaction digest on success
  public func mergeCoins(
    ownerAddress : Text,
    gasBudget : Nat64
  ) : async Result.Result<Text, Text> {
    let rpcUrl = "https://fullnode.testnet.sui.io:443";
    let suiWallet = Wallet.createTestnetWallet("dfx_test_key");

    // Get all coins for the address
    let coins = switch (await suiWallet.getBalance(ownerAddress)) {
      case (#err(e)) { return #err("Failed to get coins: " # e) };
      case (#ok(balance)) { balance.objects };
    };

    if (coins.size() < 2) {
      return #err("Need at least 2 coins to merge. Found: " # Nat64.toText(Nat64.fromNat(coins.size())));
    };

    let signFunc = func(messageHash : Blob) : async Result.Result<Blob, Text> {
      try {
        let response = await (with cycles = 30_000_000_000) IC.ic.sign_with_ecdsa({
          message_hash = messageHash;
          derivation_path = [];
          key_id = { curve = #secp256k1; name = "dfx_test_key" };
        });
        #ok(response.signature)
      } catch (e) {
        #err("Failed to sign: " # Error.message(e))
      }
    };

    let getPublicKeyFunc = func() : async Result.Result<Blob, Text> {
      try {
        let response = await (with cycles = 30_000_000_000) IC.ic.ecdsa_public_key({
          canister_id = null;
          derivation_path = [];
          key_id = { curve = #secp256k1; name = "dfx_test_key" };
        });
        #ok(response.public_key)
      } catch (e) {
        #err("Failed to get public key: " # Error.message(e))
      }
    };

    // Get coin object IDs (skip the first one which will be the destination)
    let sourceCoinIds = Array.tabulate<Text>(
      coins.size() - 1,
      func(i : Nat) : Text { coins[i + 1].coinObjectId }
    );

    await SuiTransfer.mergeCoins(
      rpcUrl,
      ownerAddress,
      coins[0].coinObjectId,  // destination (also used for gas)
      sourceCoinIds,
      gasBudget,
      signFunc,
      getPublicKeyFunc
    )
  };

  /// Split a coin into multiple coins with specified amounts
  ///
  /// Creates new coins from an existing coin. Useful for preparing coins
  /// for multiple transfers or airdrops.
  /// @param ownerAddress - Address that owns the coin
  /// @param amounts - Array of amounts for each new coin (in MIST)
  /// @param gasBudget - Maximum gas budget in MIST
  /// @return Transaction digest on success
  public func splitCoins(
    ownerAddress : Text,
    amounts : [Nat64],
    gasBudget : Nat64
  ) : async Result.Result<Text, Text> {
    let rpcUrl = "https://fullnode.testnet.sui.io:443";
    let suiWallet = Wallet.createTestnetWallet("dfx_test_key");

    // Get coins for the address
    let coins = switch (await suiWallet.getBalance(ownerAddress)) {
      case (#err(e)) { return #err("Failed to get coins: " # e) };
      case (#ok(balance)) { balance.objects };
    };

    if (coins.size() == 0) {
      return #err("No coins available");
    };

    // Check sufficient balance
    var totalNeeded : Nat64 = gasBudget;
    for (amount in amounts.vals()) {
      totalNeeded += amount;
    };

    if (coins[0].balance < totalNeeded) {
      return #err("Insufficient balance. Have: " # Nat64.toText(coins[0].balance) #
                  " MIST, need: " # Nat64.toText(totalNeeded) # " MIST");
    };

    let signFunc = func(messageHash : Blob) : async Result.Result<Blob, Text> {
      try {
        let response = await (with cycles = 30_000_000_000) IC.ic.sign_with_ecdsa({
          message_hash = messageHash;
          derivation_path = [];
          key_id = { curve = #secp256k1; name = "dfx_test_key" };
        });
        #ok(response.signature)
      } catch (e) {
        #err("Failed to sign: " # Error.message(e))
      }
    };

    let getPublicKeyFunc = func() : async Result.Result<Blob, Text> {
      try {
        let response = await (with cycles = 30_000_000_000) IC.ic.ecdsa_public_key({
          canister_id = null;
          derivation_path = [];
          key_id = { curve = #secp256k1; name = "dfx_test_key" };
        });
        #ok(response.public_key)
      } catch (e) {
        #err("Failed to get public key: " # Error.message(e))
      }
    };

    await SuiTransfer.splitCoins(
      rpcUrl,
      ownerAddress,
      coins[0].coinObjectId,
      amounts,
      gasBudget,
      signFunc,
      getPublicKeyFunc
    )
  };

  // ============================================
  // TRANSACTION QUERIES
  // ============================================

  /// Get transaction status by digest
  ///
  /// @param digest - Transaction digest (base58 string)
  /// @return Transaction status including success/failure, gas used, timestamp
  public func getTransactionStatus(digest : Text) : async Result.Result<TransactionStatus, Text> {
    let rpcUrl = "https://fullnode.testnet.sui.io:443";
    await SuiTransfer.getTransactionStatus(rpcUrl, digest)
  };

  // ============================================
  // TESTNET UTILITIES
  // ============================================

  /// Request testnet SUI from faucet
  ///
  /// Note: The faucet has rate limits. Wait between requests.
  public func requestFaucet(address : Text) : async Result.Result<Text, Text> {
    await SuiTransfer.requestTestnetFaucet(address)
  };
}
