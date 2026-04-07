class UserProfile {
  final String name;
  final DateTime dateOfBirth;
  final String? timeOfBirth;
  final String placeOfBirth;

  const UserProfile({
    required this.name,
    required this.dateOfBirth,
    this.timeOfBirth,
    required this.placeOfBirth,
  });

  String get dobFormatted {
    final day = dateOfBirth.day.toString().padLeft(2, '0');
    final month = dateOfBirth.month.toString().padLeft(2, '0');
    final year = dateOfBirth.year.toString();
    return '$day/$month/$year';
  }

  String get profileSummary {
    final buffer = StringBuffer();
    if (name.isNotEmpty) buffer.writeln('Name: $name');
    buffer.writeln('Date of Birth: $dobFormatted');
    if (timeOfBirth != null && timeOfBirth!.isNotEmpty) {
      buffer.writeln('Time of Birth: $timeOfBirth');
    }
    buffer.writeln('Place of Birth: $placeOfBirth');
    return buffer.toString();
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'dateOfBirth': dateOfBirth.toIso8601String(),
    'timeOfBirth': timeOfBirth,
    'placeOfBirth': placeOfBirth,
  };
}
