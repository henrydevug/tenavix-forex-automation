import 'package:test/test.dart';
import 'package:tenavix_server/src/profit_share/profit_share_calculator.dart';

void main() {
  const calculator = ProfitShareCalculator();

  group('ProfitShareCalculator', () {
    test('charges 20 percent on new realized profit', () {
      final result = calculator.applyClosedDeal(
        cumulativeNetProfitBefore: BigInt.zero,
        highWaterMarkBefore: BigInt.zero,
        netClosedDeal: BigInt.from(100000),
      );

      expect(result.eligibleProfit, BigInt.from(100000));
      expect(result.feeAmount, BigInt.from(20000));
      expect(result.traderShare, BigInt.from(80000));
      expect(result.highWaterMarkAfter, BigInt.from(100000));
    });

    test('does not charge again while recovering a loss', () {
      final result = calculator.applyClosedDeal(
        cumulativeNetProfitBefore: BigInt.from(100000),
        highWaterMarkBefore: BigInt.from(100000),
        netClosedDeal: BigInt.from(-50000),
      );

      expect(result.cumulativeNetProfit, BigInt.from(50000));
      expect(result.eligibleProfit, BigInt.zero);
      expect(result.feeAmount, BigInt.zero);
      expect(result.highWaterMarkAfter, BigInt.from(100000));
    });

    test('charges only the new profit after recovering the loss', () {
      final result = calculator.applyClosedDeal(
        cumulativeNetProfitBefore: BigInt.from(50000),
        highWaterMarkBefore: BigInt.from(100000),
        netClosedDeal: BigInt.from(70000),
      );

      expect(result.cumulativeNetProfit, BigInt.from(120000));
      expect(result.eligibleProfit, BigInt.from(20000));
      expect(result.feeAmount, BigInt.from(4000));
      expect(result.highWaterMarkAfter, BigInt.from(120000));
    });

    test('supports a loss that takes cumulative profit below zero', () {
      final result = calculator.applyClosedDeal(
        cumulativeNetProfitBefore: BigInt.from(10000),
        highWaterMarkBefore: BigInt.from(10000),
        netClosedDeal: BigInt.from(-30000),
      );

      expect(result.cumulativeNetProfit, BigInt.from(-20000));
      expect(result.eligibleProfit, BigInt.zero);
      expect(result.feeAmount, BigInt.zero);
      expect(result.highWaterMarkAfter, BigInt.from(10000));
    });

    test('rounds fee half up to a minor currency unit', () {
      final result = calculator.applyClosedDeal(
        cumulativeNetProfitBefore: BigInt.zero,
        highWaterMarkBefore: BigInt.zero,
        netClosedDeal: BigInt.from(3),
      );

      expect(result.feeAmount, BigInt.from(1));
    });

    test('rejects invalid fee rates', () {
      expect(
        () => calculator.applyClosedDeal(
          cumulativeNetProfitBefore: BigInt.zero,
          highWaterMarkBefore: BigInt.zero,
          netClosedDeal: BigInt.from(100),
          shareBasisPoints: 10001,
        ),
        throwsArgumentError,
      );
    });
  });
}
