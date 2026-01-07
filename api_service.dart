import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart'; // 👈 Needed for User ID
import 'package:uuid/uuid.dart'; // 👈 Needed for User ID
import 'main.dart'; // Keep importing your Expense model

class ApiService {
  // ✅ YOUR CLOUD SERVER URL
  static const String baseUrl = "https://kiwi-server-ca2k.onrender.com/api";

  // 🔐 1. GET YOUR UNIQUE USER ID (Creates one if it doesn't exist)
  static Future<String> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    String? userId = prefs.getString('user_id');
    if (userId == null) {
      userId = const Uuid().v4(); // Generate a new random ID
      await prefs.setString('user_id', userId);
    }
    return userId;
  }

  // 📋 2. GET EXPENSES (Only Yours!)
  // 📋 2. GET EXPENSES (Debug Version)
  static Future<List<Expense>> getExpenses() async {
    try {
      final userId = await getUserId();
      print("🔍 Fetching data for User ID: $userId"); // Print the ID

      final response = await http.get(Uri.parse('$baseUrl/expenses/$userId'));

      print("📡 Server Response Code: ${response.statusCode}"); // Print the Status

      if (response.statusCode == 200) {
        List<dynamic> body = jsonDecode(response.body);
        print("📦 Data received: $body"); // Print the actual data
        return body.map((dynamic item) => Expense.fromJson(item)).toList();
      } else {
        print("❌ Server Error: ${response.body}"); // Print the error message
        throw Exception('Failed to load expenses: ${response.statusCode}');
      }
    } catch (e) {
      print("❌ Connection Error: $e");
      return [];
    }
  }

  // ➕ 3. ADD SINGLE EXPENSE (With Privacy Tag)
  static Future<void> addExpense(Expense expense) async {
    try {
      final userId = await getUserId(); 
      print("Attempting to send to: $baseUrl/expenses for user: $userId");

      // We need to add the userId to the JSON before sending
      final Map<String, dynamic> expenseData = expense.toJson();
      expenseData['userId'] = userId; // 🏷️ Tag it!

      final response = await http.post(
        Uri.parse("$baseUrl/expenses"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(expenseData),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        print("✅ Success! Server saved the data.");
      } else {
        print("❌ Server rejected it: ${response.statusCode} - ${response.body}");
      }
    } catch (e) {
      print("❌ Connection Error: $e");
    }
  }

  // 🧠 4. ANALYZE SMS (AI Feature)
  static Future<Map<String, dynamic>> analyzeSms(String smsText) async {
    try {
      // 👇 MAKE SURE THIS URL ENDS WITH "/api/analyze"
final response = await http.post(
  Uri.parse('https://kiwi-server-ca2k.onrender.com/api/analyze'), 
  headers: {"Content-Type": "application/json"},
  body: jsonEncode({"smsText": smsText}),
);;

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('AI Analysis Failed: ${response.body}');
      }
    } catch (e) {
      print("Error analyzing SMS: $e");
      throw Exception("Connection Error");
    }
  }

  // 🗑️ 5. DELETE EXPENSE
  static Future<void> deleteExpense(String id) async {
    try {
      await http.delete(Uri.parse('$baseUrl/expenses/$id'));
    } catch (e) {
      print("Error deleting expense: $e");
    }
  }

  // 🧹 6. CLEAR ALL (Only cleans YOUR data locally first)
  static Future<void> clearAllExpenses() async {
    try {
      List<Expense> all = await getExpenses();
      for (var e in all) {
        await deleteExpense(e.id);
      }
    } catch (e) {
      print("Error clearing data: $e");
    }
  }
  static Future<void> syncExpenses(List<Expense> expenses) async {
    for (var expense in expenses) {
      await addExpense(expense);
    }
  }
}