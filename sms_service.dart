import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:permission_handler/permission_handler.dart';
import 'main.dart'; // Imports your Expense model

class SmsService {
  final SmsQuery _query = SmsQuery();

  Future<List<Expense>> fetchTransactions() async {
    var permission = await Permission.sms.status;
    if (permission.isDenied) {
      await Permission.sms.request();
    }

    if (!await Permission.sms.isGranted) {
      return [];
    }

    List<SmsMessage> messages = await _query.querySms(
      kinds: [SmsQueryKind.inbox],
      count: 50,
    );

    List<Expense> expenses = [];

    for (var msg in messages) {
      final body = msg.body ?? "";
      if (msg.date == null) continue;

      // ✅ FIX 1: Detect Income vs Expense
      bool isCredit = _isIncomeMessage(body);
      bool isDebit = _isExpenseMessage(body);

      if (isCredit || isDebit) {
        double? amount = _parseAmount(body);
        if (amount != null) {
          // ✅ FIX 2: Use SMS Date as Unique ID (Prevents Duplicates)
          String uniqueId = msg.date!.millisecondsSinceEpoch.toString();

          expenses.add(
            Expense(
              id: uniqueId,
              title: _parseMerchant(body) ?? "Bank Transaction",
              amount: amount,
              date: msg.date!,
              originalCategory: isCredit ? "Income" : "Uncategorized",
              isIncome: isCredit, // ✅ Correctly sets Income
            ),
          );
        }
      }
    }

    return expenses;
  }

  // Check for Money COMING IN
  bool _isIncomeMessage(String body) {
    String lower = body.toLowerCase();
    return lower.contains("credited") ||
        lower.contains("received") ||
        lower.contains("deposited");
  }

  // Check for Money GOING OUT
  bool _isExpenseMessage(String body) {
    String lower = body.toLowerCase();
    return lower.contains("debited") ||
        lower.contains("spent") ||
        lower.contains("paid") ||
        lower.contains("sent") ||
        lower.contains("widthdrawn");
  }

  double? _parseAmount(String body) {
    RegExp regExp = RegExp(
      r'(?:Rs\.?|INR)\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)',
      caseSensitive: false,
    );
    Match? match = regExp.firstMatch(body);
    if (match != null) {
      String rawAmount = match.group(1)!.replaceAll(',', '');
      return double.tryParse(rawAmount);
    }
    return null;
  }

  String? _parseMerchant(String body) {
    RegExp regExp = RegExp(
      r'(?:to|at|via|from)\s+([A-Za-z0-9\s]+?)(?:\.|and|on|API|Ref|UPI|is)',
      caseSensitive: false,
    );
    Match? match = regExp.firstMatch(body);
    if (match != null) {
      return match.group(1)?.trim();
    }
    return "Unknown";
  }
}
