import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/utils/tax_calculator.dart';

void main() {
  group('menuPrice', () {
    test('adds PPN to the original price', () {
      expect(menuPrice(25000, ppnPercent: 11), 27750);
    });

    test('leaves an exempt product alone', () {
      expect(menuPrice(25000, ppnPercent: 11, ppnExempt: true), 25000);
    });

    test('leaves the price alone when there is no PPN', () {
      expect(menuPrice(25000, ppnPercent: 0), 25000);
    });

    test('never includes service — that is a per-bill Dine In charge', () {
      // Whatever the service rate, the menu figure only carries PPN.
      expect(menuPrice(100000, ppnPercent: 11), 111000);
    });
  });

  group('calculateCharges', () {
    test('builds base, service and PPN up from the original price', () {
      final result = calculateCharges(
        lines: [const TaxableLine(baseTotal: 100000)],
        ppnPercent: 11,
        servicePercent: 5,
        serviceApplies: true,
      );

      expect(result.base, 100000);
      expect(result.service, 5000);
      // 11% of 105.000, not of 100.000.
      expect(result.ppn, 11550);
      expect(result.total, 116550);
    });

    test('charges PPN on base + service, not base alone', () {
      final result = calculateCharges(
        lines: [const TaxableLine(baseTotal: 100000)],
        ppnPercent: 11,
        servicePercent: 5,
        serviceApplies: true,
      );

      // Taxing the bare base would give 11.000 — the 550 shortfall this
      // ordering exists to prevent.
      expect(result.ppn, greaterThan(11000));
      expect(result.ppn, ((result.base + result.service) * 0.11).round());
    });

    test('drops service for take away but keeps PPN', () {
      final result = calculateCharges(
        lines: [const TaxableLine(baseTotal: 100000)],
        ppnPercent: 11,
        servicePercent: 5,
        serviceApplies: false,
      );

      expect(result.service, 0);
      expect(result.ppn, 11000);
      expect(result.total, 111000);
    });

    test('take away total matches the menu price exactly', () {
      // Nothing is added beyond PPN, so what the customer saw on the
      // menu is what they pay.
      const base = 25000;
      final result = calculateCharges(
        lines: [const TaxableLine(baseTotal: base)],
        ppnPercent: 11,
        servicePercent: 5,
        serviceApplies: false,
      );

      expect(result.total, menuPrice(base, ppnPercent: 11));
    });

    test('honours per-line exemptions', () {
      final result = calculateCharges(
        lines: [
          const TaxableLine(baseTotal: 100000),
          const TaxableLine(baseTotal: 100000, ppnExempt: true),
          const TaxableLine(baseTotal: 100000, serviceExempt: true),
        ],
        ppnPercent: 11,
        servicePercent: 5,
        serviceApplies: true,
      );

      expect(result.base, 300000);
      // Only the first two lines carry service.
      expect(result.service, 5000 + 5000);
      // Line 1: 11% of 105.000. Line 2: exempt. Line 3: 11% of 100.000.
      expect(result.ppn, 11550 + 0 + 11000);
    });

    test('components always add back up to the total', () {
      for (final amount in [1, 999, 7777, 33333, 123456, 1000000]) {
        final result = calculateCharges(
          lines: [TaxableLine(baseTotal: amount)],
          ppnPercent: 11,
          servicePercent: 5,
          serviceApplies: true,
        );
        expect(result.base + result.service + result.ppn, result.total,
            reason: 'breakdown drifted for $amount');
      }
    });

    test('adds nothing when both rates are zero', () {
      final result = calculateCharges(
        lines: [const TaxableLine(baseTotal: 12345)],
        ppnPercent: 0,
        servicePercent: 0,
        serviceApplies: true,
      );

      expect(result.base, 12345);
      expect(result.service, 0);
      expect(result.ppn, 0);
      expect(result.total, 12345);
    });
  });

  group('menuPriceNote', () {
    test('names the PPN rate', () {
      expect(menuPriceNote(11), 'Harga sudah termasuk PPN 11%');
    });

    test('says nothing when there is no PPN', () {
      expect(menuPriceNote(0), isNull);
    });

    test('trims a trailing zero from the rate', () {
      expect(formatPercent(11), '11%');
      expect(formatPercent(2.5), '2.5%');
    });
  });
}
