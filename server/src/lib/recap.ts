// After zero: what a shared countdown adds up to. The page, its preview image and the app's recap
// card all read from this, so they say the same thing.
import { contributions } from "./coffin.ts";
import { memberCount, type CountdownDoc } from "./countdowns.ts";
import { guesses, rankGuesses } from "./pool.ts";
import { countedSpan, isFinished, type Recap } from "./recapText.ts";

export { countedSpan, isFinished, recapText, type Recap } from "./recapText.ts";

/** Loads the recap for a finished countdown, or null while it's still counting. */
export async function loadRecap(doc: CountdownDoc, now = new Date()): Promise<Recap | null> {
  if (!isFinished(doc, now)) return null;
  const isPublic = doc.visibility === "public";
  const [members, notes, closest] = await Promise.all([
    memberCount(doc.slug),
    isPublic ? 0 : (await contributions()).countDocuments({ slug: doc.slug, removedAt: { $exists: false } }),
    doc.pool?.answer
      ? (await guesses()).find({ slug: doc.slug }).toArray().then((all) =>
          rankGuesses(all, doc.pool!.answer, null).filter((g) => g.place === 1).map((g) => g.name))
      : Promise.resolve([] as string[]),
  ]);
  return {
    ...(isPublic ? {} : { counted: countedSpan(doc.createdAt, doc.targetDate) }),
    people: isPublic ? members : members + 1,
    notes,
    closest,
  };
}
