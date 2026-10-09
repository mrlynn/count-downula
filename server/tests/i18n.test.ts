import assert from "node:assert/strict";
import { test } from "node:test";
import { LOCALES, listOf, pickLocale, t, type Key } from "../src/lib/i18n.ts";
import { recapText } from "../src/lib/recapText.ts";
import { headline } from "../src/lib/time.ts";

test("the browser's language picks the page's", () => {
  assert.equal(pickLocale(null), "en");
  assert.equal(pickLocale("de-CH,de;q=0.9,en;q=0.8"), "de");
  assert.equal(pickLocale("en-US,en;q=0.9,ja;q=0.8"), "en");
  assert.equal(pickLocale("pt-PT"), "pt-BR", "European Portuguese reads the Brazilian draft");
  assert.equal(pickLocale("ko, fr;q=0.5"), "fr", "Falls through to the next language we have");
  assert.equal(pickLocale("ja;q=0, es"), "es", "q=0 means not wanted");
  assert.equal(pickLocale("zh-Hans"), "en");
});

test("plurals follow each language's rules", () => {
  assert.equal(t("en", "countingDown", { n: 1 }), "1 person is counting down");
  assert.equal(t("en", "countingDown", { n: 1204 }), "1,204 people are counting down");
  assert.equal(t("fr", "notesInCoffin", { n: 0 }), "0 mot dans le cercueil", "French treats zero as singular");
  assert.equal(t("de", "notesInCoffin", { n: 0 }), "0 Nachrichten im Sarg");
  assert.equal(t("ja", "countingDown", { n: 1 }), "1人がカウントダウン中");
  assert.equal(t("de", "together", { n: 1204 }), "1.204 haben gemeinsam runtergezählt", "Numbers are written the local way");
});

test("every language keeps English's placeholders", () => {
  const placeholders = (s: string) => [...s.matchAll(/\{(\w+)\}/g)].map((m) => m[1]).sort().join(",");
  const forms = (locale: (typeof LOCALES)[number], key: Key) => {
    // Plural messages: try both forms.
    const one = t(locale, key, { n: 1, date: "{date}", name: "{name}", names: "{names}", span: "{span}" });
    const many = t(locale, key, { n: 5, date: "{date}", name: "{name}", names: "{names}", span: "{span}" });
    return [one, many];
  };
  const keys = Object.keys((t as unknown as { length: number }) && {}) as Key[];
  void keys;
  for (const key of ["since", "calledIt", "cryptOf", "offBy", "guessedClosest", "toGoOn", "categoryTitle"] as Key[]) {
    const english = forms("en", key).map(placeholders);
    for (const locale of LOCALES) assert.deepEqual(forms(locale, key).map(placeholders), english, `${locale} ${key}`);
  }
});

test("recaps and headlines speak the viewer's language", () => {
  const words = recapText({ counted: { days: 142, hours: 3408 }, people: 23, notes: 41, closest: ["Dana", "Sam"] }, false, "de");
  assert.equal(words.counted, "142 Tage gezählt");
  assert.equal(words.people, `Wir 23 · 41 Nachrichten im Sarg · ${listOf("de", ["Dana", "Sam"])} lag am nächsten dran`);
  const now = new Date("2026-10-09T12:00:00Z");
  const ja = headline(now, new Date("2026-10-24T15:00:00Z"), "event", "Asia/Tokyo", "ja");
  assert.equal(ja.value, "あと15日");
  assert.match(ja.caption, /10月25日まで/);
  assert.equal(headline(now, new Date("2026-10-01T00:00:00Z"), "event", "UTC", "es").value, "¡Ya llegó!");
});
