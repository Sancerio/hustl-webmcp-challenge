import 'learn_article.dart';

/// Markdown body for the recovery & readiness explainer. Kept as a top-level
/// raw string so the registry below stays scannable.
const String _recoveryAndReadinessBody = r'''
## What the recovery ring means

The big percentage in the ring is your recovery score, from 0 to 100. It's our best read on how rested and ready your body is today, built from three signals: your heart rate variability, your resting heart rate, and how well you slept.

Higher is better. A bigger number means your body is showing strong signs of being recovered. A lower number is a nudge that you might need an easier day.

When the app is still new to you, you'll see "building your baseline (n/14)" instead of a number. That's normal — we wait until we've learned your personal patterns before showing a score, so it actually means something for you.

## Your four readiness bands

The ring's color and label tell you what kind of day it is for training:

- **Charged** — You're well recovered. Great day to push if you're feeling it.
- **Ready** — You're in a good spot. Solid day to train as planned.
- **Steady** — A bit below your usual. Train, but maybe keep it moderate — listen to how you feel.
- **Recharge** — Your body's asking for a lighter day. Consider easy movement, mobility, or rest. You'll bounce back.

These are suggestions, not rules. You always know your body best.

## Why the confidence label changes

Next to your score you'll see a confidence label. It reflects how much we've learned about your normal:

- **Building confidence** — We haven't started collecting your data yet.
- **Rough estimate** — Early days, or we're missing one of the key signals. We keep the bands wide so we don't call a bad day on thin information.
- **Medium confidence** — We've got about a week of data and enough signals to read you more closely.
- **High confidence** — Two weeks in with all three signals. This is the most precise read, with narrower bands.

The more consistently you wear your device, the sharper your scores get.

## Recovery score vs. readiness band

They're closely related, with one twist:

- Your **recovery score** is the core number — how rested you are based on HRV, resting heart rate, and sleep.
- Your **readiness band** takes that score and also factors in your recent training load, then sorts you into one of the four bands above.

So readiness is recovery with your workout history in the mix. A heavy training stretch can pull your band down even when you feel okay.

## What to do with it

Glance at your band, then trust how you feel. Charged or Ready? Go for it. Steady? Ease off a touch. Recharge? Take the lighter day — resting today is what makes tomorrow strong. And keep wearing your device, because the more we learn, the more your scores work for you.''';

/// Slug for the recovery & readiness explainer. Exposed so call-sites build the
/// `/learn/<slug>` route without re-typing the literal.
const String recoveryAndReadinessSlug = 'recovery-and-readiness';

/// Markdown body for the RIR (reps in reserve) explainer, opened from the set
/// keyboard's "?".
const String _understandingRirBody = r'''
## What RIR means

RIR stands for **reps in reserve** — how many more reps you could have done at the end of a set before hitting failure. It's the simplest way to gauge, and log, how hard a set actually felt.

If you stopped a set and felt like you had two solid reps left in the tank, that's **RIR 2**. If you genuinely couldn't have done another rep with good form, that's **RIR 0** — failure.

## The scale

We use a 0–6+ scale, colour-coded from brutal to easy:

- **RIR 0–1 (red)** — at or near failure. Nothing, or almost nothing, left.
- **RIR 2–3 (amber)** — hard. A couple of good reps still in reserve.
- **RIR 4–5 (green)** — moderate. Comfortably short of failure.
- **RIR 6+ (teal)** — easy. Plenty left in the tank.

The lower the number, the harder the set. Anything beyond six reps in reserve we just call **6+** — once a set is that easy, the exact count stops mattering.

## Why it's useful

Logging RIR lets you train at the right intensity over time. Most effective training lives in the **RIR 0–3** range — hard, but mostly stopping a rep or two short of failure so you can recover and repeat the quality work.

Tracking it also helps you autoregulate: on a strong day you might push a set to RIR 1, and on a flat day hold the same weight at RIR 3. Same load, honest effort, and a record of how it actually went.

## How to log it

Open the number keyboard on a set, then tap the RIR you felt. It's **optional** — add it on the sets where effort matters to you, and leave it off the rest. Tap your choice again to clear it.

## RIR vs. RPE

If you've used RPE (rate of perceived exertion) before, RIR is just the flip side of the same idea: **RIR = 10 − RPE**. RPE 8 is the same effort as RIR 2 — two reps left. We show RIR because "reps left in the tank" is a more concrete thing to feel and remember.''';

/// Slug for the RIR explainer. Exposed so call-sites build the `/learn/<slug>`
/// route without re-typing the literal.
const String understandingRirSlug = 'understanding-rir';

/// The const registry of in-app Learn articles, keyed by slug.
const Map<String, LearnArticle> _articlesBySlug = {
  recoveryAndReadinessSlug: LearnArticle(
    slug: recoveryAndReadinessSlug,
    title: 'How recovery & readiness work',
    summary:
        'What the recovery ring means, your four readiness bands, why the '
        'confidence label changes, and how to use it.',
    body: _recoveryAndReadinessBody,
  ),
  understandingRirSlug: LearnArticle(
    slug: understandingRirSlug,
    title: 'Understanding RIR',
    summary:
        'What reps in reserve means, the 0–6+ scale, why it’s useful, and how '
        'to log it.',
    body: _understandingRirBody,
  ),
};

/// Look up a Learn article by slug, or `null` if no article matches.
LearnArticle? learnArticleBySlug(String slug) => _articlesBySlug[slug];
