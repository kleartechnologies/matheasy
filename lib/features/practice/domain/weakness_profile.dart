import 'package:flutter/foundation.dart';

import 'practice_skill.dart';
import 'practice_topic.dart';

/// A single weakness signal — how much a learner needs work on [skill].
@immutable
class WeaknessScore {
  const WeaknessScore({
    required this.skill,
    required this.score,
    required this.reason,
  });

  final PracticeSkill skill;

  /// 0–1, higher = weaker / more in need of practice.
  final double score;

  /// A short, human-readable justification (e.g. "48% accuracy").
  final String reason;

  PracticeTopic get topic => skill.topic;
}

/// The learner's ranked weaknesses — the input the adaptive engine uses to steer
/// practice toward what needs the most work (Pro-only).
@immutable
class WeaknessProfile {
  const WeaknessProfile({this.skills = const [], this.topics = const []});

  static const WeaknessProfile empty = WeaknessProfile();

  /// Weak skills, weakest first.
  final List<WeaknessScore> skills;

  /// Weak topics, weakest first (derived from [skills] + topic accuracy).
  final List<PracticeTopic> topics;

  /// Whether there's enough history to have a real signal (vs. a cold start).
  bool get hasSignal => skills.isNotEmpty;

  /// The single weakest skill, if any.
  WeaknessScore? get weakest => skills.isEmpty ? null : skills.first;
}
