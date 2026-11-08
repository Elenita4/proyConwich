String _two(int value) => value.toString().padLeft(2, '0');

String sqlDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${_two(value.month)}-${_two(value.day)}';

String sqlDateTime(DateTime value) =>
    '${sqlDate(value)} ${_two(value.hour)}:${_two(value.minute)}:${_two(value.second)}';

String sqlNow() => sqlDateTime(DateTime.now());

DateTime parseSqlDate(String value) {
  final parts = value.split('-');
  return DateTime(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
}

DateTime? parseSqlDateTime(String? value) {
  if (value == null || value.isEmpty) return null;
  return DateTime.tryParse(value.replaceFirst(' ', 'T'));
}

String formatMoney(double value) => 'Bs ${value.toStringAsFixed(2)}';

String formatDateShort(DateTime value) =>
    '${_two(value.day)}/${_two(value.month)}/${value.year}';

String formatDateTimeShort(DateTime value) =>
    '${formatDateShort(value)} ${_two(value.hour)}:${_two(value.minute)}';
