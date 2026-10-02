/// Calendar coordinates, not instants: Monday through Sunday, including DST.
List<DateTime> calendarWeek(DateTime day) {
  final monday = DateTime.utc(day.year, day.month, day.day - day.weekday + 1);
  return List.generate(
    7,
    (i) => DateTime.utc(monday.year, monday.month, monday.day + i),
  );
}
