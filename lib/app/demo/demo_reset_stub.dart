/// Challenge reset is only supported by the public web evaluator.
///
/// The challenge flag is never enabled for normal native builds, so keeping
/// this fallback inert avoids introducing a native navigation side effect.
void resetDemoExperience() {}
