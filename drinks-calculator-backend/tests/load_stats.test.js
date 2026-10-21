// tests/load_stats.test.js
// The load-test report is only useful if its numbers are trustworthy, so the
// percentile arithmetic is tested rather than eyeballed.
const { percentile, summarise, formatSummary, sortNumbers } = require('../utils/loadStats');

describe('sortNumbers', () => {
  test('drops anything that is not a finite number and sorts ascending', () => {
    expect(sortNumbers([30, '10', null, NaN, 20, Infinity])).toEqual([10, 20, 30]);
  });

  test('tolerates a non-array', () => {
    expect(sortNumbers(undefined)).toEqual([]);
    expect(sortNumbers('nope')).toEqual([]);
  });
});

describe('percentile', () => {
  const sorted = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100];

  test('nearest-rank on ten values', () => {
    expect(percentile(sorted, 50)).toBe(50);
    expect(percentile(sorted, 90)).toBe(90);
    expect(percentile(sorted, 95)).toBe(100); // ceil(9.5) = 10th
    expect(percentile(sorted, 99)).toBe(100);
    expect(percentile(sorted, 0)).toBe(10);
    expect(percentile(sorted, 100)).toBe(100);
  });

  test('empty input is 0, not NaN', () => {
    expect(percentile([], 95)).toBe(0);
    expect(percentile(null, 95)).toBe(0);
  });
});

describe('summarise', () => {
  test('reports every figure the till owner needs', () => {
    const stats = summarise([10, 20, 30, 40, 50, 60, 70, 80, 90, 100]);
    expect(stats).toEqual({
      count: 10, min: 10, mean: 55, p50: 50, p90: 90, p95: 100, p99: 100, max: 100,
    });
  });

  test('one slow request shows in p95 but barely in the mean', () => {
    const stats = summarise([40, 40, 40, 40, 40, 40, 40, 40, 40, 4000]);
    expect(stats.mean).toBe(436);
    expect(stats.p50).toBe(40);
    expect(stats.p95).toBe(4000);
    expect(stats.p99).toBe(4000);
  });

  test('an empty run yields zeros instead of NaN', () => {
    expect(summarise([])).toEqual({
      count: 0, min: 0, mean: 0, p50: 0, p90: 0, p95: 0, p99: 0, max: 0,
    });
  });

  test('rounds to one decimal', () => {
    expect(summarise([10.04, 10.05]).mean).toBe(10.0);
    expect(summarise([1, 2]).mean).toBe(1.5);
  });
});

describe('formatSummary', () => {
  test('one readable line with the label and the percentiles', () => {
    const line = formatSummary('GET /api/drinks', summarise([10, 20]));
    expect(line).toContain('GET /api/drinks');
    expect(line).toContain('n=   2');
    expect(line).toContain('p95=');
    expect(line.trim().endsWith('ms')).toBe(true);
  });
});
