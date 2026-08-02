/**
 * The risk engine — a number for a human to look at, and nothing more.
 *
 * READ THIS BEFORE CHANGING ANYTHING HERE. `deviceRiskScore` does not gate a
 * single request. It is not consulted by the usage guard, it cannot deny a
 * scan, and no code path in this repository turns a high score into a refusal.
 * That is a product decision, not an oversight:
 *
 *  - The signals are all innocently explicable. A shared classroom iPad has
 *    twenty accounts on one installation. A family tablet has three. A student
 *    who forgot which account they used signs in and out four times in an hour.
 *    A tutor demoing the app creates accounts all day.
 *  - The cost of a false positive is a child who cannot do their homework and a
 *    one-star review. The cost of a false negative is a few cents of OpenAI.
 *    Those are not close.
 *
 * So the score is written to the installation document for monitoring, for
 * dashboards, and for deciding — with a person in the loop — whether a pattern
 * is worth acting on. If a future version ever blocks on it, that must be an
 * explicit, separately-flagged decision with an appeal path, not a quiet change
 * to a threshold in this file.
 *
 * Everything here is pure.
 */

/** What we count on an installation, for scoring. Every field is a plain tally. */
export interface RiskSignals {
  /** Distinct uids ever seen on this installation. */
  accountCount: number;
  /** Distinct ANONYMOUS uids ever seen on this installation. */
  anonymousAccountCount: number;
  /** Sign-in events recorded on this installation. */
  signInCount: number;
  /** Distinct uids seen in the last 24 hours. */
  accountsLastDay: number;
  /** Metered requests in the last hour. */
  requestsLastHour: number;
  /** Milliseconds between the newest two account switches, if there were two. */
  fastestSwitchMs?: number;
  /** How long this installation has existed. New is not suspicious on its own. */
  ageMs: number;
}

/** One thing that pushed the score up, in words a human can act on. */
export interface RiskReason {
  code:
    | "many_accounts"
    | "many_anonymous"
    | "rapid_switching"
    | "churning_sign_ins"
    | "burst_usage"
    | "accounts_faster_than_humans";
  points: number;
  detail: string;
}

export interface RiskAssessment {
  /** 0-100. Higher is more unusual, NOT more guilty. */
  score: number;
  reasons: RiskReason[];
  /** A coarse label for dashboards. */
  band: "normal" | "watch" | "elevated";
}

const MAX_SCORE = 100;

/**
 * Score an installation's history.
 *
 * The shape of each rule is "this is normal up to N, and unusual in proportion
 * to how far past N it goes", capped, so no single signal can max the score on
 * its own. A shared device trips one rule hard and lands mid-band; a scripted
 * farm trips four and lands high — which is the only distinction the score is
 * really being asked to draw.
 */
export function assessRisk(signals: RiskSignals): RiskAssessment {
  const reasons: RiskReason[] = [];
  const add = (code: RiskReason["code"], points: number, detail: string) => {
    if (points > 0) reasons.push({ code, points: Math.round(points), detail });
  };

  // Several accounts on one device is a family or a classroom. Twelve is not.
  add(
    "many_accounts",
    ramp(signals.accountCount, 4, 12, 30),
    `${signals.accountCount} accounts have used this installation`
  );

  // Anonymous accounts are cheap to make, so they are the cheapest thing to
  // farm — weighted a little harder than named ones, from a lower threshold.
  add(
    "many_anonymous",
    ramp(signals.anonymousAccountCount, 3, 10, 25),
    `${signals.anonymousAccountCount} anonymous sessions on this installation`
  );

  // Two or three accounts in a day is a family evening. Eight is a pattern.
  add(
    "rapid_switching",
    ramp(signals.accountsLastDay, 3, 8, 20),
    `${signals.accountsLastDay} different accounts in the last 24 hours`
  );

  add(
    "churning_sign_ins",
    ramp(signals.signInCount, 15, 60, 15),
    `${signals.signInCount} sign-in events on this installation`
  );

  // A human cannot scan sixty problems in an hour. A loop can.
  add(
    "burst_usage",
    ramp(signals.requestsLastHour, 40, 150, 20),
    `${signals.requestsLastHour} metered requests in the last hour`
  );

  // Two accounts inside a minute is not somebody remembering their password.
  if (signals.fastestSwitchMs !== undefined && signals.fastestSwitchMs < 60_000) {
    const seconds = Math.max(1, Math.round(signals.fastestSwitchMs / 1000));
    add(
      "accounts_faster_than_humans",
      20 - Math.min(15, seconds / 4),
      `two accounts within ${seconds}s of each other`
    );
  }

  const score = Math.min(
    MAX_SCORE,
    Math.round(reasons.reduce((sum, r) => sum + r.points, 0))
  );

  return { score, reasons, band: bandFor(score) };
}

/**
 * Zero below [floor], rising linearly to [max] points at [ceiling] and no
 * further. Keeps "a bit over the line" cheap and "far over it" expensive.
 */
function ramp(value: number, floor: number, ceiling: number, max: number): number {
  if (!Number.isFinite(value) || value <= floor) return 0;
  if (ceiling <= floor) return max;
  return Math.min(max, ((value - floor) / (ceiling - floor)) * max);
}

function bandFor(score: number): RiskAssessment["band"] {
  if (score >= 60) return "elevated";
  if (score >= 30) return "watch";
  return "normal";
}
