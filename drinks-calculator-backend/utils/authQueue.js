// utils/authQueue.js
// Password hashing and verification are CPU work.
//
// Even with the native bcrypt — which runs on libuv's threadpool instead of the
// event loop — 500 logins arriving together would occupy every thread, and the
// API would look dead to everyone else (payment polling, /health, dashboards).
// This keeps at most `limit` password operations in flight: the rest wait their
// turn while the rest of the API keeps being served.
//
// Deliberately tiny, dependency-free and free of timers, so the rule is unit
// tested rather than trusted.

/**
 * @param {number} limit how many tasks may run at the same time (min 1)
 * @returns {{run: (task: () => any) => Promise<any>, active: number,
 *            pending: number, limit: number}}
 */
function createQueue(limit) {
  const max = Math.max(1, Math.trunc(Number(limit)) || 1);
  const waiting = [];
  let active = 0;

  function pump() {
    if (active >= max || waiting.length === 0) return;
    const job = waiting.shift();
    active += 1;
    // `Promise.resolve().then(task)` turns a synchronous throw into a rejection
    // and keeps the caller's stack free of our internals.
    Promise.resolve()
      .then(job.task)
      .then(job.resolve, job.reject)
      .finally(() => {
        active -= 1;
        pump();
      });
  }

  /**
   * Run [task] as soon as a slot is free. Rejections propagate to the caller and
   * always release the slot — a wrong password must not leak capacity.
   */
  function run(task) {
    return new Promise((resolve, reject) => {
      waiting.push({ task, resolve, reject });
      pump();
    });
  }

  return {
    run,
    get active() {
      return active;
    },
    get pending() {
      return waiting.length;
    },
    get limit() {
      return max;
    },
  };
}

module.exports = { createQueue };
