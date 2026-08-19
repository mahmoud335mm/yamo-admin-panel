/**
 * Concurrency barrier: makes N async operations start within the same
 * micro-window so race conditions are actually exercised.
 */
export function createBarrier(n: number): { wait: () => Promise<void> } {
  let remaining = n;
  let resolveAll!: () => void;
  const all = new Promise<void>((r) => { resolveAll = r; });
  return {
    wait: async () => {
      remaining--;
      if (remaining === 0) resolveAll();
      await all;
    },
  };
}

export async function runInLockstep<T>(
  count: number,
  fn: (i: number) => Promise<T>,
): Promise<PromiseSettledResult<T>[]> {
  const barrier = createBarrier(count);
  const tasks = Array.from({ length: count }, (_, i) => (async () => {
    await barrier.wait();
    return fn(i);
  })());
  return Promise.allSettled(tasks);
}
