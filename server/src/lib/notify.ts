import { sendBackgroundPush, type PushTarget } from "./apns.ts";
import { forgetPushTokens, pushTargets } from "./countdowns.ts";

/**
 * Tells members' devices the countdown changed. Pass `targets` when the member list is about to
 * be deleted (unpublishing), so the devices still hear about it.
 */
export async function notifyMembers(slug: string, targets?: PushTarget[]) {
  const outcomes = await sendBackgroundPush(targets ?? (await pushTargets(slug)), slug);
  await forgetPushTokens([...outcomes].filter(([, outcome]) => outcome === "gone").map(([token]) => token));
}
