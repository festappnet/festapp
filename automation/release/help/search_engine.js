/* Shared by browser search and retrieval tests. No service or model dependency. */
(() => {
  const normalize = value => String(value).toLowerCase().normalize('NFD').replace(/\p{M}/gu, '')
    .replace(/e[\s-]?mail/g, 'email').replace(/[^\p{L}\p{N}]+/gu, ' ').trim();
  const stop = new Set('a an and are as at be by can co do does for how i in is it jak je jsem kde kdy me mi mohu muj muzu my na nebo o of on or po please pro prosim se si s ta ten the to u v ve what where with z ze'.split(' '));
  const terms = value => normalize(value).split(/\s+/).filter(word => word && !stop.has(word));
  const stem = word => {
    if (word.length <= 5) return word;
    return word.replace(/(?:ami|emi|ovi|ove|ych|ich|ech|emu|ing|ed|ou|em|um|it|at|y|a|i|e|u|o|s)$/, '');
  };
  const concept = word => {
    if (/^(vstupen|list(?:ek|ky|ku)|ticket)/.test(word)) return 'ticket';
    if (/^(objednav|order)/.test(word)) return 'order';
    if (/^(platb|placen|zaplac|uhrad|payment)/.test(word)) return 'payment';
    if (/^(cen[ayoueik]|pric|cost)/.test(word)) return 'price';
    if (/^(doruc|nedoruc|nepris|delivery|deliver|receiv|missing)/.test(word)) return 'delivery';
    if (/^(email|mail)$/.test(word)) return 'email';
    if (/^(sedadl|misten|sezeni|seats?|seating)/.test(word)) return 'seat';
    if (/^(skener|scanner|skenov|scanning)/.test(word)) return 'scanner';
    if (/^(odes|posl|posil|zasl|resend|sending|send)/.test(word)) return 'send';
    if (/^(prihlas|registr)/.test(word)) return 'registration';
    return stem(word);
  };
  function oneEdit(a, b) {
    if (Math.abs(a.length - b.length) > 1) return false;
    let i = 0;
    while (i < a.length && a[i] === b[i]) i++;
    if (i === a.length) return b.length - i <= 1;
    if (a.length === b.length) {
      if (a.slice(i + 1) === b.slice(i + 1)) return true;
      return a[i] === b[i + 1] && a[i + 1] === b[i] && a.slice(i + 2) === b.slice(i + 2);
    }
    return a.length > b.length ? a.slice(i + 1) === b.slice(i) : a.slice(i) === b.slice(i + 1);
  }
  function wordScore(word, query) {
    if (word === query) return 1;
    if (concept(word) === concept(query)) return .96;
    const a = stem(word), b = stem(query);
    if (b.length >= 3 && a.startsWith(b)) return .85;
    if (a.length >= 4 && b.startsWith(a)) return .8;
    if (a.length >= 4 && b.length >= 4 && oneEdit(a, b)) return .65;
    return 0;
  }
  const field = text => [...new Set(terms(text))];
  function prepare(entries) {
    const vocabulary = new Set();
    const records = entries.map(entry => {
      const fields = [
        {words: field(entry.title), weight: 14},
        {words: field((entry.aliases || []).join(' ')), weight: 10},
        {words: field(entry.description), weight: 3},
      ];
      const sections = entry.sections.map(section => ({...section,
        headingWords: field(section.heading), bodyWords: field(section.text)}));
      for (const f of fields) for (const word of f.words) vocabulary.add(word);
      for (const section of sections) for (const word of [...section.headingWords, ...section.bodyWords]) vocabulary.add(word);
      return {...entry, fields, sections};
    });
    return {records, vocabulary: [...vocabulary]};
  }
  function snippet(text, queryTerms) {
    const matches = [...text.matchAll(/[\p{L}\p{N}]+/gu)];
    const match = matches.find(m => queryTerms.some(term => wordScore(normalize(m[0]), term) >= .8));
    let start = Math.max(0, (match?.index || 0) - 65);
    if (start) {const boundary = text.indexOf(' ', start); if (boundary >= 0 && boundary < start + 25) start = boundary + 1;}
    let end = Math.min(text.length, start + 230);
    if (end < text.length) {const boundary = text.lastIndexOf(' ', end); if (boundary > end - 25) end = boundary;}
    return (start ? '…' : '') + text.slice(start, end).trim() + (end < text.length ? '…' : '');
  }
  function search(index, value, category = '') {
    const query = String(value).trim().slice(0, 200);
    const queryTerms = [...new Set(terms(query))].slice(0, 10);
    const scoped = index.records.filter(record => !category || record.category === category);
    if (!normalize(query) && category) return {results: scoped.map(record => ({...record, href: record.url, snippet: record.description, score: 0})), relaxed: false};
    if (normalize(query).length < 2 || !queryTerms.length) return {results: [], relaxed: false};
    const scores = queryTerms.map(term => new Map(index.vocabulary.map(word => [word, wordScore(word, term)])));
    const strength = (words, term) => Math.max(0, ...words.map(word => scores[term].get(word) || 0));
    const frequency = queryTerms.map((_, term) => index.records.filter(record =>
      record.fields.some(f => strength(f.words, term)) || record.sections.some(s => strength(s.headingWords, term) || strength(s.bodyWords, term))).length);
    const idf = frequency.map(count => 1 + Math.log(1 + (index.records.length - count + .5) / (count + .5)));
    const ranked = scoped.map(record => {
      const coverage = new Set(); let score = 0;
      for (const f of record.fields) queryTerms.forEach((_, i) => {
        const quality = strength(f.words, i);
        if (quality) {coverage.add(i); score += quality * f.weight * idf[i];}
      });
      let best = record.sections[0], bestScore = -1;
      for (const section of record.sections) {
        let sectionScore = 0;
        queryTerms.forEach((_, i) => {
          const heading = strength(section.headingWords, i), body = strength(section.bodyWords, i);
          if (heading || body) coverage.add(i);
          sectionScore += (heading * 6 + body) * idf[i];
        });
        if (sectionScore > bestScore) {best = section; bestScore = sectionScore;}
      }
      const phrase = normalize(query);
      if (normalize(record.title).includes(phrase)) score += 24;
      if ((record.aliases || []).some(alias => normalize(alias).includes(phrase))) score += 18;
      score += Math.max(0, bestScore);
      const text = best?.text || record.description;
      return {...record, score, coverage: coverage.size,
        href: record.url + (best?.anchor && bestScore > 0 ? '#' + best.anchor : ''),
        snippet: snippet(text, queryTerms)};
    }).filter(record => record.coverage > 0);
    const exact = ranked.filter(record => record.coverage === queryTerms.length);
    const relaxed = !exact.length;
    const results = (exact.length ? exact : ranked.filter(record => record.coverage >= Math.ceil(queryTerms.length * .6)))
      .sort((a, b) => b.coverage - a.coverage || b.score - a.score || a.title.localeCompare(b.title));
    return {results, relaxed: relaxed && results.length > 0};
  }
  globalThis.FestappHelpSearchEngine = {normalize, terms, wordScore, prepare, search};
})();
