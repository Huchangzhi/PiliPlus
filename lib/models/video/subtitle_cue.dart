class SubtitleCue implements Comparable<SubtitleCue> {
  const SubtitleCue({
    required this.start,
    required this.end,
    required this.text,
  });

  final Duration start;
  final Duration end;
  final String text;

  bool contains(Duration position) =>
      position >= start && position < end;

  @override
  int compareTo(SubtitleCue other) => start.compareTo(other.start);
}
