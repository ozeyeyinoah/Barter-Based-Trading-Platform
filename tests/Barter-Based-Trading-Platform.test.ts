import { Clarinet, Tx, Chain, Account, types } from '@hirosystems/clarinet-sdk';
import { describe, it, expect, beforeEach } from 'vitest';

const contracts = {
  barterPlatform: 'Barter-Based-Trading-Platform'
};

describe('Barter Trading Platform with Analytics & Reputation System', () => {
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

  describe('Reputation System Features', () => {
    it('should allow users to rate each other', () => {
      const block = chain.mineBlock([
        Tx.contractCall(
          contracts.barterPlatform,
          'rate-user',
          [
            types.principal(bob.address),
            types.uint(5),
            types.ascii('Excellent trader, highly recommended!'),
            types.bool(false)
          ],
          alice.address
        )
      ]);

      expect(block.receipts).toHaveLength(1);
      expect(block.receipts[0].result).toStrictEqual(types.ok(types.bool(true)));
    });

    it('should prevent users from rating themselves', () => {
      const block = chain.mineBlock([
        Tx.contractCall(
          contracts.barterPlatform,
          'rate-user',
          [
            types.principal(alice.address),
            types.uint(5),
            types.ascii('I am great!'),
            types.bool(false)
          ],
          alice.address
        )
      ]);

      expect(block.receipts).toHaveLength(1);
      expect(block.receipts[0].result).toStrictEqual(types.err(types.uint(601))); // ERR-SELF-RATING-NOT-ALLOWED
    });

    it('should prevent duplicate ratings from same user', () => {
      // First rating
      chain.mineBlock([
        Tx.contractCall(
          contracts.barterPlatform,
          'rate-user',
          [
            types.principal(bob.address),
            types.uint(4),
            types.ascii('Good trader'),
            types.bool(false)
          ],
          alice.address
        )
      ]);

      // Second rating from same user
      const block = chain.mineBlock([
        Tx.contractCall(
          contracts.barterPlatform,
          'rate-user',
          [
            types.principal(bob.address),
            types.uint(3),
            types.ascii('Changed my mind'),
            types.bool(false)
          ],
          alice.address
        )
      ]);

      expect(block.receipts).toHaveLength(1);
      expect(block.receipts[0].result).toStrictEqual(types.err(types.uint(602))); // ERR-RATING-ALREADY-EXISTS
    });

    it('should enforce rating range validation', () => {
      const block = chain.mineBlock([
        Tx.contractCall(
          contracts.barterPlatform,
          'rate-user',
          [
            types.principal(bob.address),
            types.uint(6), // Invalid - out of range
            types.ascii('Rating too high'),
            types.bool(false)
          ],
          alice.address
        )
      ]);

      expect(block.receipts).toHaveLength(1);
      expect(block.receipts[0].result).toStrictEqual(types.err(types.uint(600))); // ERR-RATING-OUT-OF-RANGE
    });

    it('should retrieve user reputation summary', () => {
      // Rate a user first
      chain.mineBlock([
        Tx.contractCall(
          contracts.barterPlatform,
          'rate-user',
          [
            types.principal(bob.address),
            types.uint(5),
            types.ascii('Excellent trader'),
            types.bool(false)
          ],
          alice.address
        )
      ]);

      const result = chain.callReadOnlyFn(
        contracts.barterPlatform,
        'get-user-reputation-summary',
        [types.principal(bob.address)],
        alice.address
      );

      expect(result.result).toContain('total-ratings');
      expect(result.result).toContain('average-rating');
      expect(result.result).toContain('reputation-level');
      expect(result.result).toContain('is-verified');
    });

    it('should calculate reputation level correctly', () => {
      const result = chain.callReadOnlyFn(
        contracts.barterPlatform,
        'calculate-reputation-level',
        [types.uint(45), types.uint(10)], // 4.5 average with 10 ratings
        alice.address
      );

      expect(result.result).toStrictEqual(types.ok(types.uint(4))); // REPUTATION-GOLD
    });

    it('should return reputation level names', () => {
      const result = chain.callReadOnlyFn(
        contracts.barterPlatform,
        'get-reputation-level-name',
        [types.uint(4)], // REPUTATION-GOLD
        alice.address
      );

      expect(result.result).toStrictEqual(types.ok(types.ascii('Gold')));
    });

    it('should allow updating existing ratings', () => {
      // Create initial rating
      chain.mineBlock([
        Tx.contractCall(
          contracts.barterPlatform,
          'rate-user',
          [
            types.principal(bob.address),
            types.uint(3),
            types.ascii('Average trader'),
            types.bool(false)
          ],
          alice.address
        )
      ]);

      // Update the rating
      const block = chain.mineBlock([
        Tx.contractCall(
          contracts.barterPlatform,
          'update-rating',
          [
            types.principal(bob.address),
            types.uint(5),
            types.ascii('Actually excellent after more trades!')
          ],
          alice.address
        )
      ]);

      expect(block.receipts).toHaveLength(1);
      expect(block.receipts[0].result).toStrictEqual(types.ok(types.bool(true)));
    });

    it('should allow admin to verify users', () => {
      const block = chain.mineBlock([
        Tx.contractCall(
          contracts.barterPlatform,
          'verify-user',
          [types.principal(alice.address)],
          deployer.address // Admin
        )
      ]);

      expect(block.receipts).toHaveLength(1);
      expect(block.receipts[0].result).toStrictEqual(types.ok(types.bool(true)));
    });

    it('should prevent non-admin from verifying users', () => {
      const block = chain.mineBlock([
        Tx.contractCall(
          contracts.barterPlatform,
          'verify-user',
          [types.principal(bob.address)],
          alice.address // Not admin
        )
      ]);

      expect(block.receipts).toHaveLength(1);
      expect(block.receipts[0].result).toStrictEqual(types.err(types.uint(100))); // ERR-NOT-AUTHORIZED
    });

    it('should allow admin to toggle reputation system', () => {
      const block = chain.mineBlock([
        Tx.contractCall(
          contracts.barterPlatform,
          'toggle-reputation-system',
          [],
          deployer.address
        )
      ]);

      expect(block.receipts).toHaveLength(1);
      expect(block.receipts[0].result).toStrictEqual(types.ok(types.bool(false))); // System disabled
    });

    it('should check reputation system status', () => {
      const result = chain.callReadOnlyFn(
        contracts.barterPlatform,
        'is-reputation-system-enabled',
        [],
        alice.address
      );

      expect(result.result).toStrictEqual(types.bool(true));
    });

    it('should get reputation statistics', () => {
      const result = chain.callReadOnlyFn(
        contracts.barterPlatform,
        'get-reputation-statistics',
        [],
        alice.address
      );

      expect(result.result).toContain('total-reputation-points');
      expect(result.result).toContain('system-enabled');
      expect(result.result).toContain('current-admin');
    });

    it('should check user eligibility based on reputation level', () => {
      const result = chain.callReadOnlyFn(
        contracts.barterPlatform,
        'check-user-eligibility',
        [types.principal(alice.address), types.uint(2)], // Bronze level minimum
        alice.address
      );

      expect(result.result).toStrictEqual(types.ok(types.bool(false))); // New user, novice level
    });

    it('should handle bulk rating operations', () => {
      const block = chain.mineBlock([
        Tx.contractCall(
          contracts.barterPlatform,
          'bulk-rate-users',
          [
            types.list([
              types.tuple({
                user: types.principal(alice.address),
                rating: types.uint(5),
                feedback: types.ascii('Great trader')
              }),
              types.tuple({
                user: types.principal(bob.address),
                rating: types.uint(4),
                feedback: types.ascii('Good trader')
              })
            ])
          ],
          deployer.address
        )
      ]);

      expect(block.receipts).toHaveLength(1);
      expect(block.receipts[0].result).toStrictEqual(types.ok(types.uint(2))); // Number of ratings processed
    });

    it('should get top rated users', () => {
      const result = chain.callReadOnlyFn(
        contracts.barterPlatform,
        'get-top-rated-users',
        [types.uint(5)],
        alice.address
      );

      expect(result.result).toStrictEqual(types.ok(types.list([])));
    });

    it('should allow admin to set reputation config', () => {
      const block = chain.mineBlock([
        Tx.contractCall(
          contracts.barterPlatform,
          'set-reputation-config',
          [
            types.ascii('min-threshold'),
            types.uint(4)
          ],
          deployer.address
        )
      ]);

      expect(block.receipts).toHaveLength(1);
      expect(block.receipts[0].result).toStrictEqual(types.ok(types.bool(true)));
    });

    it('should retrieve user badges', () => {
      const result = chain.callReadOnlyFn(
        contracts.barterPlatform,
        'get-user-badge',
        [types.principal(alice.address), types.ascii('verified-trader')],
        alice.address
      );

      // Badge might not exist for new user, but function should not error
      expect(result.result).toBeDefined();
    });

    it('should enforce feedback length limits', () => {
      // Create a very long feedback string (over 512 characters)
      const longFeedback = 'A'.repeat(600);
      
      const block = chain.mineBlock([
        Tx.contractCall(
          contracts.barterPlatform,
          'rate-user',
          [
            types.principal(bob.address),
            types.uint(5),
            types.ascii(longFeedback),
            types.bool(false)
          ],
          alice.address
        )
      ]);

      expect(block.receipts).toHaveLength(1);
      expect(block.receipts[0].result).toStrictEqual(types.err(types.uint(605))); // ERR-FEEDBACK-TOO-LONG
    });

    it('should prevent rating when system is disabled', () => {
      // Disable reputation system
      chain.mineBlock([
        Tx.contractCall(
          contracts.barterPlatform,
          'toggle-reputation-system',
          [],
          deployer.address
        )
      ]);

      // Try to rate user
      const block = chain.mineBlock([
        Tx.contractCall(
          contracts.barterPlatform,
          'rate-user',
          [
            types.principal(bob.address),
            types.uint(5),
            types.ascii('Should not work'),
            types.bool(false)
          ],
          alice.address
        )
      ]);

      expect(block.receipts).toHaveLength(1);
      expect(block.receipts[0].result).toStrictEqual(types.err(types.uint(607))); // ERR-REPUTATION-SYSTEM-DISABLED
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
