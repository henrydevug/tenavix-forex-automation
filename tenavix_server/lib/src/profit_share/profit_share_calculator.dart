/// Pure, deterministic performance-fee calculation in integer minor units.
///
/// Money is represented as [BigInt] minor units (for example, cents for USD).
/// This avoids binary floating-point rounding in financial calculations.
/// Persistence, broker-event authentication and transaction locking belong to
/// the repository/service layer and are intentionally not implemented here.
class ProfitShareCalculator {
  static const int defaultShareBasisPoints = 2000; // 20.00%
  static const int basisPointDenominator = 10000;

  const ProfitShareCalculator();

  ProfitShareResult applyClosedDeal({
    required BigInt cumulativeNetProfitBefore,
    required BigInt highWaterMarkBefore,
    required BigInt netClosedDeal,
    int shareBasisPoints = defaultShareBasisPoints,
  }) {
    if (highWaterMarkBefore.isNegative) {
      throw ArgumentError.value(
        highWaterMarkBefore,
        'highWaterMarkBefore',
        'High-water mark cannot be negative.',
      );
    }
    if (shareBasisPoints <= 0 || shareBasisPoints > basisPointDenominator) {
      throw ArgumentError.value(
        shareBasisPoints,
        'shareBasisPoints',
        'Share rate must be between 1 and 10000 basis points.',
      );
    }

    final cumulativeAfter = cumulativeNetProfitBefore + netClosedDeal;
    final eligibleProfit = cumulativeAfter > highWaterMarkBefore
        ? cumulativeAfter - highWaterMarkBefore
        : BigInt.zero;
    final numerator = eligibleProfit * BigInt.from(shareBasisPoints);
    final denominator = BigInt.from(basisPointDenominator);

    // Round half up to the nearest minor currency unit.
    final fee = (numerator + (denominator ~/ BigInt.from(2))) ~/ denominator;
    final hwmAfter = cumulativeAfter > highWaterMarkBefore
        ? cumulativeAfter
        : highWaterMarkBefore;

    return ProfitShareResult(
      cumulativeNetProfit: cumulativeAfter,
      highWaterMarkBefore: highWaterMarkBefore,
      highWaterMarkAfter: hwmAfter,
      eligibleProfit: eligibleProfit,
      shareBasisPoints: shareBasisPoints,
      feeAmount: fee,
    );
  }
}

class ProfitShareResult {
  final BigInt cumulativeNetProfit;
  final BigInt highWaterMarkBefore;
  final BigInt highWaterMarkAfter;
  final BigInt eligibleProfit;
  final int shareBasisPoints;
  final BigInt feeAmount;

  const ProfitShareResult({
    required this.cumulativeNetProfit,
    required this.highWaterMarkBefore,
    required this.highWaterMarkAfter,
    required this.eligibleProfit,
    required this.shareBasisPoints,
    required this.feeAmount,
  });

  BigInt get traderShare => eligibleProfit - feeAmount;
}
