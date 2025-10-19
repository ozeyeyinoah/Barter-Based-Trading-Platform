import { Clarinet, Tx, Chain, Account, types } from '@hirosystems/clarinet-sdk';
import { describe, it, expect, beforeEach } from 'vitest';

const contracts = {
  barterPlatform: 'Barter-Based-Trading-Platform'
};

describe('Barter Trading Platform with Analytics', () => {
  let chain: Chain;
  let accounts: Map<string, Account>;
  let deployer: Account;
  let alice: Account;
  let bob: Account;

  beforeEach(() => {
    const result = Clarinet.getSimnet();
    chain = result.chain;
    accounts = result.accounts;
    deployer = accounts.get('deployer')!;
    alice = accounts.get('wallet_1')!;
    bob = accounts.get('wallet_2')!;
  });

  describe('Basic Trading Functionality', () => {
    it('should allow creating a basic trade', () => {
      const block = chain.mineBlock([
        Tx.contractCall(
          contracts.barterPlatform,
          'create-trade',
          [
            types.principal(bob.address),
            types.ascii('iPhone 14'),
            types.ascii('MacBook Pro')
          ],
          alice.address
        )
      ]);

      expect(block.receipts).toHaveLength(1);
      expect(block.receipts[0].result).toStrictEqual(types.ok(types.uint(0)));
    });

    it('should allow accepting a trade', () => {
      // First create a trade
      chain.mineBlock([
        Tx.contractCall(
          contracts.barterPlatform,
          'create-trade',
          [
            types.principal(bob.address),
            types.ascii('iPhone 14'),
            types.ascii('MacBook Pro')
          ],
          alice.address
        )
      ]);

      // Accept the trade
      const block = chain.mineBlock([
        Tx.contractCall(
          contracts.barterPlatform,
          'accept-trade',
          [types.uint(0)],
          bob.address
        )
      ]);

      expect(block.receipts).toHaveLength(1);
      expect(block.receipts[0].result).toStrictEqual(types.ok(types.bool(true)));
    });

    it('should allow completing a trade', () => {
      // Create and accept trade
      chain.mineBlock([
        Tx.contractCall(
          contracts.barterPlatform,
          'create-trade',
          [
            types.principal(bob.address),
            types.ascii('iPhone 14'),
            types.ascii('MacBook Pro')
          ],
          alice.address
        )
      ]);

      chain.mineBlock([
        Tx.contractCall(
          contracts.barterPlatform,
          'accept-trade',
          [types.uint(0)],
          bob.address
        )
      ]);

      // Complete the trade
      const block = chain.mineBlock([
        Tx.contractCall(
          contracts.barterPlatform,
          'complete-trade',
          [types.uint(0)],
          alice.address
        )
      ]);

      expect(block.receipts).toHaveLength(1);
      expect(block.receipts[0].result).toStrictEqual(types.ok(types.bool(true)));
    });
  });

  describe('Analytics Features', () => {
    it('should allow creating trade with analytics', () => {
      const block = chain.mineBlock([
        Tx.contractCall(
          contracts.barterPlatform,
          'create-trade-with-analytics',
          [
            types.principal(bob.address),
            types.ascii('iPhone 14'),
            types.ascii('MacBook Pro')
          ],
          alice.address
        )
      ]);

      expect(block.receipts).toHaveLength(1);
      expect(block.receipts[0].result).toStrictEqual(types.ok(types.uint(0)));
    });

    it('should allow completing trade with analytics', () => {
      // Create trade with analytics
      chain.mineBlock([
        Tx.contractCall(
          contracts.barterPlatform,
          'create-trade-with-analytics',
          [
            types.principal(bob.address),
            types.ascii('iPhone 14'),
            types.ascii('MacBook Pro')
          ],
          alice.address
        )
      ]);

      // Accept the trade
      chain.mineBlock([
        Tx.contractCall(
          contracts.barterPlatform,
          'accept-trade',
          [types.uint(0)],
          bob.address
        )
      ]);

      // Complete with analytics
      const block = chain.mineBlock([
        Tx.contractCall(
          contracts.barterPlatform,
          'complete-trade-with-analytics',
          [types.uint(0)],
          alice.address
        )
      ]);

      expect(block.receipts).toHaveLength(1);
      expect(block.receipts[0].result).toStrictEqual(types.ok(types.bool(true)));
    });

    it('should retrieve platform overview', () => {
      const result = chain.callReadOnlyFn(
        contracts.barterPlatform,
        'get-platform-overview',
        [],
        alice.address
      );

      expect(result.result).toContain('total-trades');
      expect(result.result).toContain('analytics-enabled');
    });

    it('should retrieve user trade summary', () => {
      // Create a trade first
      chain.mineBlock([
        Tx.contractCall(
          contracts.barterPlatform,
          'create-trade-with-analytics',
          [
            types.principal(bob.address),
            types.ascii('iPhone 14'),
            types.ascii('MacBook Pro')
          ],
          alice.address
        )
      ]);

      const result = chain.callReadOnlyFn(
        contracts.barterPlatform,
        'get-user-trade-summary',
        [types.principal(alice.address)],
        alice.address
      );

      expect(result.result).toContain('total-initiated');
      expect(result.result).toContain('total-completed');
    });

    it('should toggle analytics', () => {
      const block = chain.mineBlock([
        Tx.contractCall(
          contracts.barterPlatform,
          'toggle-analytics',
          [],
          deployer.address
        )
      ]);

      expect(block.receipts).toHaveLength(1);
      expect(block.receipts[0].result).toStrictEqual(types.ok(types.bool(false)));
    });

    it('should record daily metrics', () => {
      const block = chain.mineBlock([
        Tx.contractCall(
          contracts.barterPlatform,
          'record-daily-metrics',
          [],
          deployer.address
        )
      ]);

      expect(block.receipts).toHaveLength(1);
      expect(block.receipts[0].result).toStrictEqual(types.ok(types.bool(true)));
    });

    it('should check if analytics is enabled', () => {
      const result = chain.callReadOnlyFn(
        contracts.barterPlatform,
        'is-analytics-enabled',
        [],
        alice.address
      );

      expect(result.result).toStrictEqual(types.bool(true));
    });
  });

  describe('Error Handling', () => {
    it('should prevent creating trade with same counterparty', () => {
      const block = chain.mineBlock([
        Tx.contractCall(
          contracts.barterPlatform,
          'create-trade',
          [
            types.principal(alice.address),
            types.ascii('iPhone 14'),
            types.ascii('MacBook Pro')
          ],
          alice.address
        )
      ]);

      expect(block.receipts).toHaveLength(1);
      expect(block.receipts[0].result).toStrictEqual(types.err(types.uint(102))); // ERR-INVALID-STATE
    });

    it('should prevent unauthorized trade acceptance', () => {
      // Create trade
      chain.mineBlock([
        Tx.contractCall(
          contracts.barterPlatform,
          'create-trade',
          [
            types.principal(bob.address),
            types.ascii('iPhone 14'),
            types.ascii('MacBook Pro')
          ],
          alice.address
        )
      ]);

      // Try to accept from wrong account
      const block = chain.mineBlock([
        Tx.contractCall(
          contracts.barterPlatform,
          'accept-trade',
          [types.uint(0)],
          alice.address // Should be bob
        )
      ]);

      expect(block.receipts).toHaveLength(1);
      expect(block.receipts[0].result).toStrictEqual(types.err(types.uint(100))); // ERR-NOT-AUTHORIZED
    });
  });
});
