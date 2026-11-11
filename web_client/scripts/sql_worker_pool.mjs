// Work-conserving bounded scheduler. A resource family cannot occupy two workers.
export async function runWorkers(items, concurrency, execute, resource = () => null, exclusive = () => false) {
  const pending = items.map((item,index) => ({item,index}));
  const results = new Array(items.length);
  const active = new Map();
  const held = new Set();
  const claimsFor = item => {const claim=resource(item);return claim===null?[]:Array.isArray(claim)?claim:[claim];};
  while (pending.length || active.size) {
    while (active.size < concurrency) {
      if([...active.values()].some(task=>task.exclusive)) break;
      const next = pending.findIndex(({item}) => (!exclusive(item)||active.size===0)&&claimsFor(item).every(claim=>!held.has(claim)));
      if (next < 0) break;
      const {item,index} = pending.splice(next,1)[0];
      const claim = claimsFor(item);
      for(const key of claim) held.add(key);
      const task = Promise.resolve().then(() => execute(item)).then(
        result => ({index,result}), error => ({index,error}));
      active.set(index,{task,claim,exclusive:exclusive(item)});
    }
    const completed = await Promise.race([...active.values()].map(({task}) => task));
    const {claim} = active.get(completed.index);
    active.delete(completed.index);
    for(const key of claim) held.delete(key);
    if (completed.error) {
      // Drain owned work before propagating; callers can then close the pool.
      await Promise.all([...active.values()].map(({task})=>task));
      throw completed.error;
    }
    results[completed.index] = completed.result;
  }
  return results;
}
