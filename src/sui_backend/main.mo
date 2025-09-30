import Lib "../lib";
import Types "../types";
import Address "../address";
import Transaction "../transaction";
import Utils "../utils";

persistent actor {
  public query func greet(name : Text) : async Text {
    return "Hello, " # name # "!";
  };

  // Test the SUI library
  public query func testAdd(x : Nat, y : Nat) : async Nat {
    Lib.add(x, y)
  };

  // Validate SUI address
  public query func validateSuiAddress(address : Text) : async Bool {
    Address.isValidAddress(address)
  };

  // Create a sample transaction
  public query func createSampleTransaction(sender : Text) : async ?Types.TransactionData {
    let gasData : Types.GasData = {
      payment = [];
      owner = sender;
      price = 1000;
      budget = 10000;
    };

    let txData = Transaction.createTransferTransaction(
      sender,
      "0x0000000000000000000000000000000000000000000000000000000000000001",
      [],
      gasData
    );

    ?txData
  };

  // Get library info
  public query func getLibraryInfo() : async {version: Text; description: Text} {
    {
      version = Lib.version;
      description = Lib.description;
    }
  };

  // Test utility functions
  public query func testUtilities(text : Text) : async Text {
    Utils.toUpperCase(text)
  };
};
