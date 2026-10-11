import { describe, expect, it } from 'vitest';
import { balances, splitEqually, validateCustomSplit } from './money';
describe('money', () => {
  it('keeps every cent', () => expect(splitEqually(10_000, ['a', 'b', 'c']).map((split) => split.amountMinor)).toEqual([3334, 3333, 3333]));
  it('rejects invalid custom totals', () => expect(() => validateCustomSplit(100, [{ memberId: 'a', amountMinor: 99 }])).toThrow());
  it('settlements adjust balances without rewriting expenses', () => {
    expect(balances([{ fromMemberId: 'a', toMemberId: 'b', amountMinor: 120 }, { fromMemberId: 'b', toMemberId: 'a', amountMinor: 20 }])).toEqual(new Map([['a', -100], ['b', 100]]));
  });
});
