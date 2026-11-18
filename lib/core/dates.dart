/// Datums-Serialisierung für die Datenbank — genau EINE Definition des
/// YYYY-MM-DD-Formats (Postgres `date`), damit sie nie auseinanderläuft.
String isoDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
