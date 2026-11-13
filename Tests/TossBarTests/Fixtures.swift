import Foundation

enum Fixtures {
    /// One domestic and one US holding. Total profit is 700,000 KRW plus 232 USD.
    static let holdingsJSON = #"""
    {
      "totalPurchaseAmount": {"krw": "5000000", "usd": "1000"},
      "marketValue": {
        "amount": {"krw": "5700000", "usd": "1232"},
        "amountAfterCost": {"krw": "5680000", "usd": "1228"}
      },
      "profitLoss": {
        "amount": {"krw": "700000", "usd": "232"},
        "amountAfterCost": {"krw": "680000", "usd": "123.52"},
        "rate": "0.1179",
        "rateAfterCost": "0.0983"
      },
      "dailyProfitLoss": {"amount": {"krw": "-50000", "usd": "12"}, "rate": "-0.0041"},
      "items": [
        {
          "symbol": "005930", "name": "삼성전자", "marketCountry": "KR", "currency": "KRW",
          "quantity": "100", "lastPrice": "57000", "averagePurchasePrice": "50000",
          "marketValue": {"purchaseAmount": "5000000", "amount": "5700000", "amountAfterCost": "5680000"},
          "profitLoss": {"amount": "700000", "amountAfterCost": "680000", "rate": "0.14", "rateAfterCost": "0.136"},
          "dailyProfitLoss": {"amount": "-50000", "rate": "-0.0087"},
          "cost": {"commission": "8550"}
        },
        {
          "symbol": "AAPL", "name": "애플", "marketCountry": "US", "currency": "USD",
          "quantity": "8", "lastPrice": "154", "averagePurchasePrice": "125",
          "marketValue": {"purchaseAmount": "1000", "amount": "1232", "amountAfterCost": "1228"},
          "profitLoss": {"amount": "232", "amountAfterCost": "123.52", "rate": "0.232", "rateAfterCost": "0.1235"},
          "dailyProfitLoss": {"amount": "12", "rate": "0.0098"},
          "cost": {"commission": "1.23", "tax": "107.25"}
        }
      ]
    }
    """#
}
