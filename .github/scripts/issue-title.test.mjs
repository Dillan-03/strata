import { test } from 'node:test';
import assert from 'node:assert/strict';
import { classify, guidance } from './issue-title.mjs';

test('accepts the three required prefixes', () => {
  for (const title of ['[Feature] Add skills inspector', '[Bug] Crash on launch', '[Chore] Configure signing']) {
    assert.deepEqual(classify(title), { valid: true, title });
  }
});

test('rejects a prefix without a following title', () => {
  assert.equal(classify('[Feature]').valid, false);
  assert.equal(classify('[Feature] ').corrected, undefined);
});

test('rejects wrong casing but corrects it', () => {
  assert.deepEqual(classify('[feature] Add search'), {
    valid: false,
    corrected: '[Feature] Add search',
    title: '[feature] Add search',
  });
});

test('corrects unambiguous conventional prefixes', () => {
  assert.equal(classify('feat: add search').corrected, '[Feature] add search');
  assert.equal(classify('Bug - login fails').corrected, '[Bug] login fails');
  assert.equal(classify('fix: crash on launch').corrected, '[Bug] crash on launch');
  assert.equal(classify('chore: bump runner').corrected, '[Chore] bump runner');
  assert.equal(classify('(Feature) Overview').corrected, '[Feature] Overview');
});

test('does not guess when the intent is unclear', () => {
  for (const title of ['Add search', 'docs: update readme', 'Search is slow', '']) {
    const result = classify(title);
    assert.equal(result.valid, false);
    assert.equal(result.corrected, undefined);
  }
});

test('guidance lists every prefix and neutralises backticks', () => {
  const text = guidance('bad `title`');
  assert.match(text, /\[Feature\]/);
  assert.match(text, /\[Bug\]/);
  assert.match(text, /\[Chore\]/);
  assert.doesNotMatch(text, /`title`/);
});
