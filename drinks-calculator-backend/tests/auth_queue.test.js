// tests/auth_queue.test.js
// A login storm must never starve the rest of the API, and a wrong password must
// never leak a queue slot.
const { createQueue } = require('../utils/authQueue');

/** A task that stays running until released by the test. */
function deferred() {
  let release;
  const promise = new Promise((resolve) => (release = resolve));
  return { promise, release };
}

const tick = () => new Promise((resolve) => setImmediate(resolve));

describe('createQueue', () => {
  test('runs only `limit` tasks at a time and queues the rest', async () => {
    const queue = createQueue(2);
    const gates = [deferred(), deferred(), deferred()];
    const started = [];

    gates.forEach((gate, index) => {
      queue.run(async () => {
        started.push(index);
        await gate.promise;
        return index;
      });
    });

    await tick();
    expect(started).toEqual([0, 1]);
    expect(queue.active).toBe(2);
    expect(queue.pending).toBe(1);

    gates[0].release();
    await tick();
    expect(started).toEqual([0, 1, 2]);
    expect(queue.active).toBe(2);
    expect(queue.pending).toBe(0);

    gates[1].release();
    gates[2].release();
    await tick();
    expect(queue.active).toBe(0);
  });

  test('returns each task result to its own caller, in order', async () => {
    const queue = createQueue(1);
    const results = await Promise.all([
      queue.run(async () => 'a'),
      queue.run(async () => 'b'),
      queue.run(async () => 'c'),
    ]);
    expect(results).toEqual(['a', 'b', 'c']);
  });

  test('a rejection reaches its caller and frees the slot', async () => {
    const queue = createQueue(1);
    await expect(queue.run(async () => {
      throw new Error('bad password');
    })).rejects.toThrow('bad password');

    await tick();
    expect(queue.active).toBe(0);
    // The slot is usable again immediately.
    await expect(queue.run(async () => 'ok')).resolves.toBe('ok');
  });

  test('a task that throws synchronously is reported as a rejection', async () => {
    const queue = createQueue(1);
    await expect(queue.run(() => {
      throw new Error('sync failure');
    })).rejects.toThrow('sync failure');
  });

  test('limit is clamped to at least 1 (bad configuration cannot deadlock)', async () => {
    expect(createQueue(0).limit).toBe(1);
    expect(createQueue(-5).limit).toBe(1);
    expect(createQueue('nope').limit).toBe(1);
    expect(createQueue(8).limit).toBe(8);
    await expect(createQueue(0).run(async () => 'still runs')).resolves.toBe('still runs');
  });

  test('a burst of 50 jobs is fully drained', async () => {
    const queue = createQueue(8);
    const jobs = Array.from({ length: 50 }, (_, i) =>
      queue.run(async () => {
        await tick();
        return i;
      }));
    const results = await Promise.all(jobs);
    expect(results).toHaveLength(50);
    expect(results[49]).toBe(49);
    await tick();
    expect(queue.active).toBe(0);
    expect(queue.pending).toBe(0);
  });
});
