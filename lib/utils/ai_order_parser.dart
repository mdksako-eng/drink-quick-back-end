// utils/ai_order_parser.dart
// Turns natural language (typed or spoken) and AI replies into concrete order
// lines that can be pushed to the calculator. Pure Dart — unit-testable.
import '../models/drink_model.dart';

/// One requested line of an order, before it is matched to a real drink.
class OrderRequestLine {
  final String name;
  final int quantity;

  const OrderRequestLine({required this.name, this.quantity = 1});

  @override
  String toString() => '$quantity x $name';
}

/// A line matched against the inventory.
class MatchedOrderLine {
  final Drink drink;
  final int quantity;

  const MatchedOrderLine({required this.drink, required this.quantity});
}

class AIOrderParser {
  /// Spoken/written numbers → values ("two beers", "a beer", "3x cola").
  static const Map<String, int> _wordNumbers = {
    'a': 1, 'an': 1, 'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5,
    'six': 6, 'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10, 'eleven': 11,
    'twelve': 12, 'fifteen': 15, 'twenty': 20, 'half a dozen': 6, 'dozen': 12,
  };

  /// Words that are never part of a drink name.
  static const List<String> _fillerWords = [
    'please', 'for', 'me', 'the', 'of', 'a', 'an', 'and', 'order', 'add',
    'buy', 'get', 'give', 'i', 'want', 'would', 'like', 'some', 'to', 'my',
    'also', 'then', 'with', 'plus', 'bottles', 'bottle', 'cans', 'can',
    'glasses', 'glass', 'pieces', 'piece', 'units', 'unit', 'cold', 'x',
  ];

  /// Leading command words that are not part of a drink name.
  static final RegExp _commandPrefix = RegExp(
      r'^(?:please\s+)?(?:(?:i\s+)?(?:want|need|would\s+like|like)\s+'
      r'|order\s+|add\s+|buy\s+|get\s+|give\s+me\s+|give\s+|take\s+'
      r'|bring\s+|some\s+)+');

  /// Parses one or more order lines out of a phrase.
  ///
  /// "order 2 beer and 1 soda"      → [2 x beer, 1 x soda]
  /// "add three mutzig please"      → [3 x mutzig]
  /// "give me a beer"               → [1 x beer]
  ///
  /// Pass [inventory] so drink names that begin with a number ("33 Export")
  /// are not mistaken for a huge quantity.
  static List<OrderRequestLine> parseOrderLines(String text,
      {List<Drink>? inventory}) {
    if (text.trim().isEmpty) return const [];

    // Split on conjunctions / separators, but not inside a drink name.
    final parts = text
        .toLowerCase()
        .split(RegExp(r'\s*(?:,|;|\band\b|\bplus\b|\balso\b|\bthen\b)\s*'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();

    final lines = <OrderRequestLine>[];
    for (final rawPart in parts) {
      // Drop leading command words: "order 2 beer" → "2 beer".
      var part = rawPart.replaceFirst(_commandPrefix, '').trim();
      if (part.isEmpty) continue;

      final extracted = _extractQuantity(part);
      var qty = extracted.$1;
      var name = _cleanName(extracted.$2);

      // "33 export" is a drink, not 33 units — if the whole phrase strongly
      // matches an inventory item, treat it as the name with quantity 1.
      if (inventory != null && extracted.$3) {
        final full = _cleanName(part);
        if (full.isNotEmpty && matchScore(full, inventory) >= 0.9) {
          name = full;
          qty = 1;
        }
      }

      if (name.isEmpty || _isCommandOnly(name)) continue;
      lines.add(OrderRequestLine(name: name, quantity: qty));
    }
    return lines;
  }

  /// Extracts the quantity: returns (quantity, remaining text, fromNumber).
  static (int, String, bool) _extractQuantity(String part) {
    // "3x" / "3 x" / "x3"
    final xMatch = RegExp(r'(\d+)\s*x\b|\bx\s*(\d+)').firstMatch(part);
    if (xMatch != null) {
      final value = int.tryParse(xMatch.group(1) ?? xMatch.group(2) ?? '1') ?? 1;
      return (
        _clampQty(value),
        part.replaceRange(xMatch.start, xMatch.end, ' '),
        false
      );
    }

    // Leading digits: "2 beer"
    final leadingDigit = RegExp(r'^\s*(\d+)\b').firstMatch(part);
    if (leadingDigit != null) {
      return (
        _clampQty(int.tryParse(leadingDigit.group(1)!) ?? 1),
        part.replaceRange(leadingDigit.start, leadingDigit.end, ' '),
        true
      );
    }

    // Word numbers: "two beers" / "a beer"
    for (final entry in _wordNumbers.entries) {
      final pattern = RegExp('\\b${RegExp.escape(entry.key)}\\b');
      if (pattern.hasMatch(part)) {
        return (_clampQty(entry.value), part.replaceFirst(pattern, ' '), false);
      }
    }

    // Trailing digits after the name: "beer 2"
    final trailingDigit = RegExp(r'(\d+)\s*$').firstMatch(part);
    if (trailingDigit != null) {
      return (
        _clampQty(int.tryParse(trailingDigit.group(1)!) ?? 1),
        part.replaceRange(trailingDigit.start, trailingDigit.end, ' '),
        false
      );
    }

    return (1, part, false);
  }

  static int _clampQty(int value) => value < 1 ? 1 : (value > 99 ? 99 : value);

  /// Strips filler words so "add two cold beers please" → "beers".
  static String _cleanName(String part) {
    final words = part
        .split(RegExp(r'\s+'))
        .map((w) => w.replaceAll(RegExp(r"[^a-z0-9'\-]"), ''))
        .where((w) => w.isNotEmpty && !_fillerWords.contains(w))
        .toList();
    return words.join(' ').trim();
  }

  static bool _isCommandOnly(String name) {
    const commands = {
      'checkout', 'check out', 'finalize', 'finalise', 'complete', 'pay',
      'preview', 'receipt', 'clear', 'reset', 'cancel', 'stock', 'price',
      'help', 'summary', 'done', 'yes', 'no', 'ok', 'okay'
    };
    return commands.contains(name);
  }

  /// Best fuzzy score (0..1) of [query] against the inventory names.
  static double matchScore(String query, List<Drink> drinks) {
    final q = _normalize(query);
    if (q.isEmpty || drinks.isEmpty) return 0.0;

    var bestScore = 0.0;
    for (final drink in drinks) {
      final name = _normalize(drink.name);
      if (name.isEmpty) continue;

      double score;
      if (name == q) {
        score = 1.0;
      } else if (name.startsWith(q) || q.startsWith(name)) {
        score = 0.9;
      } else if (name.contains(q)) {
        score = 0.8;
      } else if (q.length >= 3 && _levenshtein(name, q) <= 2) {
        score = 0.6;
      } else {
        // Token overlap: "beer cold" vs "cold beer"
        final qTokens = q.split(' ').toSet();
        final nameTokens = name.split(' ').toSet();
        final overlap = qTokens.intersection(nameTokens).length;
        score = overlap == 0
            ? 0.0
            : 0.5 + (overlap / (qTokens.length + nameTokens.length - overlap)) * 0.3;
      }

      if (score > bestScore) bestScore = score;
    }
    return bestScore;
  }

  /// Matches a requested name against the inventory with fuzzy tolerance, so
  /// "mutzi" or "mutzing" still finds "Mutzig".
  static Drink? matchDrink(String query, List<Drink> drinks) {
    final q = _normalize(query);
    if (q.isEmpty || drinks.isEmpty) return null;

    Drink? best;
    var bestScore = 0.0;

    for (final drink in drinks) {
      final name = _normalize(drink.name);
      if (name.isEmpty) continue;

      double score;
      if (name == q) {
        score = 1.0;
      } else if (name.startsWith(q) || q.startsWith(name)) {
        score = 0.9;
      } else if (name.contains(q)) {
        score = 0.8;
      } else if (q.length >= 3 && _levenshtein(name, q) <= 2) {
        score = 0.6;
      } else {
        // Token overlap: "beer cold" vs "cold beer"
        final qTokens = q.split(' ').toSet();
        final nameTokens = name.split(' ').toSet();
        final overlap = qTokens.intersection(nameTokens).length;
        score = overlap == 0
            ? 0.0
            : 0.5 + (overlap / (qTokens.length + nameTokens.length - overlap)) * 0.3;
      }

      if (score > bestScore) {
        bestScore = score;
        best = drink;
      }
    }

    return bestScore >= 0.5 ? best : null;
  }

  /// Resolves parsed request lines into concrete drinks (skipping unknown ones).
  static List<MatchedOrderLine> matchLines(
      List<OrderRequestLine> lines, List<Drink> drinks) {
    final matched = <MatchedOrderLine>[];
    for (final line in lines) {
      final drink = matchDrink(line.name, drinks);
      if (drink == null) continue;
      final existing =
          matched.indexWhere((m) => m.drink.id == drink.id);
      if (existing != -1) {
        matched[existing] = MatchedOrderLine(
          drink: drink,
          quantity: matched[existing].quantity + line.quantity,
        );
      } else {
        matched.add(MatchedOrderLine(drink: drink, quantity: line.quantity));
      }
    }
    return matched;
  }

  /// Reads the machine-readable order block an AI reply may contain:
  ///
  ///   ORDER_JSON: [{"name":"Beer","qty":2},{"name":"Soda","qty":1}]
  ///
  /// Also tolerates ```json fences and `item` as an alias for `name`.
  static List<OrderRequestLine> extractOrderLines(String aiResponse) {
    final match = RegExp(
      r'ORDER_JSON\s*:?\s*(\[[\s\S]*?\])',
      caseSensitive: false,
    ).firstMatch(aiResponse.replaceAll('```json', '').replaceAll('```', ''));
    if (match == null) return const [];

    final raw = match.group(1);
    if (raw == null) return const [];

    final lines = <OrderRequestLine>[];
    // Tolerant, dependency-free scan of the JSON objects.
    for (final object in RegExp(r'\{[^}]*\}').allMatches(raw)) {
      final body = object.group(0)!;
      final name = _jsonValue(body, ['name', 'item', 'drink']);
      if (name == null || name.trim().isEmpty) continue;
      final qty = int.tryParse(
              _jsonValue(body, ['qty', 'quantity', 'count']) ?? '1') ??
          1;
      lines.add(OrderRequestLine(name: name.trim(), quantity: _clampQty(qty)));
    }
    return lines;
  }

  /// Removes the ORDER_JSON block from a reply before showing it to the user.
  static String stripOrderBlock(String aiResponse) {
    return aiResponse
        .replaceAll(
            RegExp(r'ORDER_JSON\s*:?\s*\[[\s\S]*?\]', caseSensitive: false), '')
        .trim();
  }

  static String? _jsonValue(String body, List<String> keys) {
    for (final key in keys) {
      final match =
          RegExp('"$key"\\s*:\\s*"?([^",}]+)"?', caseSensitive: false)
              .firstMatch(body);
      if (match != null) return match.group(1)?.trim();
    }
    return null;
  }

  static String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Classic edit distance — good enough for short drink names.
  static int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    final previous = List<int>.generate(b.length + 1, (i) => i);
    final current = List<int>.filled(b.length + 1, 0);

    for (var i = 1; i <= a.length; i++) {
      current[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        current[j] = [
          current[j - 1] + 1,
          previous[j] + 1,
          previous[j - 1] + cost,
        ].reduce((x, y) => x < y ? x : y);
      }
      for (var j = 0; j <= b.length; j++) {
        previous[j] = current[j];
      }
    }
    return previous[b.length];
  }
}