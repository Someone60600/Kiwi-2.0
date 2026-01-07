import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart' as fl;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:telephony/telephony.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:image_picker/image_picker.dart';

// --- NOTIFICATION SETUP ---
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> initNotifications() async {
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initializationSettings =
      InitializationSettings(android: initializationSettingsAndroid);

  await flutterLocalNotificationsPlugin.initialize(initializationSettings);
  tz.initializeTimeZones();
}

// --- API SERVICE (Local Logic Implementation) ---
class ApiService {
  static const String _storageKey = 'expenses_data_v1';

  static Future<List<Expense>> getExpenses() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString(_storageKey);
    if (data == null) return [];
    try {
      final List<dynamic> jsonList = jsonDecode(data);
      return jsonList.map((e) => Expense.fromJson(e)).toList();
    } catch (e) {
      return [];
    }
  }

  static Future<void> addExpense(Expense expense) async {
    final prefs = await SharedPreferences.getInstance();
    List<Expense> currentList = await getExpenses();
    
    // Check if updating or adding
    int index = currentList.indexWhere((e) => e.id == expense.id);
    if (index != -1) {
      currentList[index] = expense;
    } else {
      currentList.add(expense);
    }
    
    await prefs.setString(
        _storageKey, jsonEncode(currentList.map((e) => e.toJson()).toList()));
  }

  static Future<void> deleteExpense(String id) async {
    final prefs = await SharedPreferences.getInstance();
    List<Expense> currentList = await getExpenses();
    currentList.removeWhere((e) => e.id == id);
    await prefs.setString(
        _storageKey, jsonEncode(currentList.map((e) => e.toJson()).toList()));
  }

  static Future<void> clearAllExpenses() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }
}

// --- MAIN ENTRY POINT ---
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initNotifications();
  
  final prefs = await SharedPreferences.getInstance();
  final bool isLoggedIn = prefs.getBool('is_logged_in') ?? false;
  final bool isDark = prefs.getBool('is_dark') ?? false;
  final String currency = prefs.getString('currency') ?? '₹';
  final double budget = prefs.getDouble('monthly_budget') ?? 10000.0;
  final String avatar =
      prefs.getString('user_avatar') ?? 'https://i.pravatar.cc/300?img=12';

  runApp(
    KiwiApp(
      startScreen: isLoggedIn
          ? const MainNavigationScreen()
          : const LoginScreen(),
      isDark: isDark,
      currency: currency,
      budget: budget,
      avatar: avatar,
    ),
  );
}

// --- 1. MAIN APP WIDGET ---
class KiwiApp extends StatefulWidget {
  final Widget startScreen;
  final bool isDark;
  final String currency;
  final double budget;
  final String avatar;

  const KiwiApp({
    super.key,
    required this.startScreen,
    required this.isDark,
    required this.currency,
    required this.budget,
    required this.avatar,
  });

  // FIX: Renamed private state to public 'KiwiAppState' to solve API error
  static KiwiAppState? of(BuildContext context) =>
      context.findAncestorStateOfType<KiwiAppState>();

  static const Color primaryColor = Color(0xFF33691E);
  static const Color accentColor = Color(0xFFACDEB0);
  static const Color bgColorLight = Color(0xFFF2F9F1);
  static const Color bgColorDark = Color(0xFF121212);

  @override
  State<KiwiApp> createState() => KiwiAppState();
}

// FIX: Made class public (removed underscore)
class KiwiAppState extends State<KiwiApp> {
  late bool _isDark;
  late String _currency;
  late double _budget;
  late String _avatar;
  Map<String, double> _categoryBudgets = {};

  @override
  void initState() {
    super.initState();
    _isDark = widget.isDark;
    _currency = widget.currency;
    _budget = widget.budget;
    _avatar = widget.avatar;
    _loadCategoryBudgets();
  }

  Future<void> _loadCategoryBudgets() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString('category_budgets');
    if (data != null) {
      setState(() {
        _categoryBudgets = Map<String, double>.from(jsonDecode(data));
      });
    }
  }

  void updateCategoryBudget(String category, double amount) async {
    setState(() => _categoryBudgets[category] = amount);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('category_budgets', jsonEncode(_categoryBudgets));
  }

  void toggleTheme() async {
    setState(() => _isDark = !_isDark);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_dark', _isDark);
  }

  void changeCurrency(String newCurrency) async {
    setState(() => _currency = newCurrency);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('currency', _currency);
  }

  void updateBudget(double newBudget) async {
    setState(() => _budget = newBudget);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('monthly_budget', _budget);
  }

  void changeAvatar(String newPath) async {
    setState(() => _avatar = newPath);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_avatar', _avatar);
  }

  String get currency => _currency;
  double get budget => _budget;
  bool get isDark => _isDark;
  String get avatar => _avatar;
  Map<String, double> get categoryBudgets => _categoryBudgets;

  ImageProvider getAvatarProvider() {
    if (_avatar.startsWith('http')) {
      return NetworkImage(_avatar);
    } else {
      return FileImage(File(_avatar));
    }
  }

  @override
  Widget build(BuildContext context) {
    var pageTransitions = const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: ZoomPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    );

    return MaterialApp(
      title: 'KIWI Expense Tracker',
      debugShowCheckedModeBanner: false,
      themeMode: _isDark ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: KiwiApp.bgColorLight,
        pageTransitionsTheme: pageTransitions,
        colorScheme: ColorScheme.fromSeed(
          seedColor: KiwiApp.accentColor,
          primary: KiwiApp.primaryColor,
          secondary: KiwiApp.accentColor,
          surface: Colors.white,
          onSurface: Colors.black,
        ),
        textTheme: GoogleFonts.poppinsTextTheme(),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.black,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: KiwiApp.bgColorDark,
        pageTransitionsTheme: pageTransitions,
        colorScheme: ColorScheme.dark(
          primary: KiwiApp.accentColor,
          secondary: KiwiApp.primaryColor,
          surface: const Color(0xFF1E1E1E),
          onSurface: Colors.white,
        ),
        textTheme: GoogleFonts.poppinsTextTheme(ThemeData.dark().textTheme),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
        ),
      ),
      home: widget.startScreen,
    );
  }
}

// --- 2. DATA MODELS ---
class Expense {
  final String id;
  final String title;
  final double amount;
  final DateTime date;
  final String originalCategory;
  final bool isIncome;

  Expense({
    required this.id,
    required this.title,
    required this.amount,
    required this.date,
    required this.originalCategory,
    this.isIncome = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'amount': amount,
    'date': date.toIso8601String(),
    'originalCategory': originalCategory,
    'isIncome': isIncome,
    'type': isIncome ? 'income' : 'expense',
  };

  factory Expense.fromJson(Map<String, dynamic> json) {
    return Expense(
      id: json['_id'] ?? json['id'] ?? '',
      title: json['title'] ?? json['merchant'] ?? 'Unknown',
      amount: (json['amount'] ?? 0).toDouble().abs(),
      date: DateTime.parse(json['date']),
      originalCategory: json['category'] ?? json['originalCategory'] ?? 'Other',
      isIncome: json['isIncome'] ?? (json['type'] == 'income'),
    );
  }
}

enum MessageType { text, expense, settlement }

class GroupMessage {
  final String sender;
  final String content;
  final double amount;
  final MessageType type;
  final DateTime timestamp;
  bool isSettled;

  GroupMessage({
    required this.sender,
    required this.content,
    this.amount = 0.0,
    required this.type,
    required this.timestamp,
    this.isSettled = false,
  });

  Map<String, dynamic> toJson() => {
    'sender': sender,
    'content': content,
    'amount': amount,
    'type': type.index,
    'timestamp': timestamp.toIso8601String(),
    'isSettled': isSettled,
  };
  factory GroupMessage.fromJson(Map<String, dynamic> json) => GroupMessage(
    sender: json['sender'],
    content: json['content'],
    amount: (json['amount'] ?? 0).toDouble(),
    type: MessageType.values[json['type']],
    timestamp: DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
    isSettled: json['isSettled'] ?? false,
  );
}

class Group {
  final String id;
  final String name;
  final List<String> members;
  final List<GroupMessage> messages;

  Group({
    required this.id,
    required this.name,
    required this.members,
    required this.messages,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'members': members,
    'messages': messages.map((m) => m.toJson()).toList(),
  };
  factory Group.fromJson(Map<String, dynamic> json) => Group(
    id: json['id'] ?? '0',
    name: json['name'] ?? 'Group',
    members: List<String>.from(json['members'] ?? []),
    messages: (json['messages'] as List? ?? [])
        .map((m) => GroupMessage.fromJson(m))
        .toList(),
  );

  double getMyNetBalance() {
    double balance = 0;
    for (var msg in messages) {
      if (msg.type == MessageType.expense && !msg.isSettled) {
        double share = msg.amount / (members.isEmpty ? 1 : members.length);
        if (msg.sender == "You") {
          balance += (msg.amount - share);
        } else {
          balance -= share;
        }
      }
    }
    return balance;
  }
}

// --- 3. HELPER FUNCTIONS ---
Color _getColorForCategory(String category) {
  switch (category) {
    case 'Income': return const Color(0xFF4CAF50);
    case 'Food': return const Color(0xFFACDEB0);
    case 'Transport': return const Color(0xFF337EF7);
    case 'Entertainment': return const Color(0xFFF6CB89);
    case 'Shopping': return const Color(0xFFCDADE9);
    case 'Health': return const Color(0xFFEFA29A);
    default: return const Color(0xFF90A4AE);
  }
}

IconData _getIconForCategory(String category) {
  switch (category) {
    case 'Income': return Icons.attach_money;
    case 'Food': return Icons.fastfood;
    case 'Transport': return Icons.directions_bus;
    case 'Entertainment': return Icons.movie;
    case 'Health': return Icons.medical_services;
    case 'Shopping': return Icons.shopping_bag;
    default: return Icons.category;
  }
}

// --- 4. LOGIN SCREEN ---
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});
  void _doLogin(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_logged_in', true);
    if (context.mounted)
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const MainNavigationScreen()),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Hero(
                tag: 'app_logo',
                child: Container(
                  height: 120,
                  width: 120,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    shape: BoxShape.circle,
                    boxShadow: [
                      const BoxShadow(color: Colors.black12, blurRadius: 10),
                    ],
                  ),
                  child: Icon(
                    Icons.account_balance_wallet,
                    size: 60,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 40),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    const BoxShadow(color: Colors.black12, blurRadius: 10),
                  ],
                ),
                child: Column(
                  children: [
                    Text(
                      "Welcome Back!",
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 30),
                    const TextField(
                      decoration: InputDecoration(
                        labelText: "Email",
                        prefixIcon: Icon(Icons.email),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const TextField(
                      decoration: InputDecoration(
                        labelText: "Password",
                        prefixIcon: Icon(Icons.lock),
                      ),
                      obscureText: true,
                    ),
                    const SizedBox(height: 30),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primary,
                          foregroundColor: Theme.of(
                            context,
                          ).colorScheme.onPrimary,
                        ),
                        onPressed: () => _doLogin(context),
                        child: const Text(
                          "Login",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- 5. MAIN NAVIGATION ---
class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});
  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _selectedIndex = 0;
  List<Expense> _expenses = [];
  List<Group> _groups = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _sortExpenses() {
    // Sort Newest First
    _expenses.sort((a, b) => b.date.compareTo(a.date));
  }

  Future<void> _loadData() async {
    try {
      List<Expense> serverExpenses = await ApiService.getExpenses();
      setState(() {
        _expenses = serverExpenses;
        _sortExpenses();
        if (_groups.isEmpty) {
          _groups = [
            Group(
              id: '1',
              name: 'PGmates',
              members: ['You', 'Sakshi'],
              messages: [],
            ),
          ];
        }
      });
    } catch (e) {
      debugPrint("Error loading data from server: $e");
    }
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('expenses_key', jsonEncode(_expenses.map((e) => e.toJson()).toList()));
    await prefs.setString('groups_key', jsonEncode(_groups.map((e) => e.toJson()).toList()));
  }

  // --- UPDATED BULK SYNC (Regex Logic - No AI) ---
  void _syncSmsExpenses() async {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Scanning Inbox...")));
    
    final Telephony telephony = Telephony.instance;
    bool? permissionsGranted = await telephony.requestPhoneAndSmsPermissions;
    if (permissionsGranted != true) return;

    List<SmsMessage> messages = await telephony.getInboxSms(
      columns: [SmsColumn.BODY, SmsColumn.DATE],
      sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
    );

    int addedCount = 0;
    
    for (var msg in messages.take(50)) {
       String body = (msg.body ?? "").toLowerCase();
       if(body.contains("debited") || body.contains("spent") || body.contains("sent") || body.contains("credited") || body.contains("received")) {
          
          // 1. Amount Extraction (Regex)
          RegExp amountRegex = RegExp(r'(?:rs\.?|inr|₹)\s*([\d,]+(?:\.\d{2})?)', caseSensitive: false);
          Match? amountMatch = amountRegex.firstMatch(msg.body!);
          if (amountMatch == null) continue;

          String cleanAmount = amountMatch.group(1)!.replaceAll(',', '');
          double amount = double.tryParse(cleanAmount) ?? 0.0;
          if (amount == 0) continue;

          // 2. Income vs Expense
          bool isIncome = body.contains("credited") || body.contains("received") || body.contains("deposit");

          // 3. Merchant/Title
          String merchant = "Unknown";
          RegExp merchantRegex = RegExp(r'(?:at|to|via|from)\s+([a-zA-Z0-9\s]+)', caseSensitive: false);
          Match? merchantMatch = merchantRegex.firstMatch(msg.body!);
          if (merchantMatch != null) {
            merchant = merchantMatch.group(1)!.trim();
          } else {
             List<String> words = msg.body!.split(' ');
             if (words.length > 2) merchant = "${words[0]} ${words[1]}";
          }

          DateTime smsDate = DateTime.fromMillisecondsSinceEpoch(msg.date ?? DateTime.now().millisecondsSinceEpoch);

          // 4. Duplicate Check (Amount + Date + Type)
          bool exists = _expenses.any((e) => 
              e.amount == amount && 
              e.isIncome == isIncome &&
              e.date.year == smsDate.year && 
              e.date.month == smsDate.month && 
              e.date.day == smsDate.day
          );

          if (!exists) {
            final newExpense = Expense(
              id: DateTime.now().millisecondsSinceEpoch.toString() + addedCount.toString(),
              title: merchant,
              amount: amount,
              date: smsDate,
              originalCategory: "Other",
              isIncome: isIncome,
            );
            
            await ApiService.addExpense(newExpense);
            addedCount++;
          }
       }
    }

    if (addedCount > 0) {
      await _loadData();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Fetched $addedCount new transactions!"), backgroundColor: Colors.green),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No new bank SMS found.")),
      );
    }
  }

  Future<void> _clearAllData() async {
    await ApiService.clearAllExpenses();
    setState(() { _expenses.clear(); });
    _saveData();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("All history deleted."), backgroundColor: Colors.redAccent));
  }

  // --- UPDATED FUNCTION: INSTANT UI UPDATE (Optimistic) ---
  void _addOrUpdateExpense(Expense expense, {bool? split, String? groupId}) async {
    // 1. OPTIMISTIC UPDATE: Update the UI immediately without waiting for server
    setState(() {
      final index = _expenses.indexWhere((e) => e.id == expense.id);
      if (index != -1) {
        _expenses[index] = expense; // Edit existing
      } else {
        _expenses.insert(0, expense); // Add new to top
      }
      _sortExpenses(); // Keep list sorted

      // Update Group Logic locally immediately
      if ((split ?? false) && groupId != null && !expense.isIncome) {
        final groupIndex = _groups.indexWhere((g) => g.id == groupId);
        if (groupIndex != -1) {
          final newMsg = GroupMessage(
            sender: "You",
            content: expense.title,
            amount: expense.amount,
            type: MessageType.expense,
            timestamp: DateTime.now(),
          );
          _groups[groupIndex].messages.add(newMsg);
        }
      }
    });

    _saveData(); // Update local cache instantly

    // 2. BACKGROUND SYNC: Send to server silently
    try {
      await ApiService.addExpense(expense);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Sync failed, check connection: $e"), backgroundColor: Colors.orange)
        );
      }
    }
  }

  void _addNewGroup(String name, List<String> members) {
    final fullMembers = ['You', ...members];
    final newGroup = Group(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      members: fullMembers,
      messages: [GroupMessage(sender: 'System', content: 'Group created', type: MessageType.text, timestamp: DateTime.now())],
    );
    setState(() => _groups.add(newGroup));
    _saveData();
  }

  void _removeExpense(int index) async {
    final expenseToDelete = _expenses[index];
    await ApiService.deleteExpense(expenseToDelete.id);
    setState(() => _expenses.removeAt(index));
    _saveData();
  }

  void _sendMessage(String groupId, String text) {
    final groupIndex = _groups.indexWhere((g) => g.id == groupId);
    if (groupIndex != -1) {
      setState(() => _groups[groupIndex].messages.add(
        GroupMessage(sender: "You", content: text, type: MessageType.text, timestamp: DateTime.now()),
      ));
      _saveData();
    }
  }

  void _settleExpense(String groupId, int messageIndex) {
    final groupIndex = _groups.indexWhere((g) => g.id == groupId);
    if (groupIndex != -1) {
      setState(() {
        _groups[groupIndex].messages[messageIndex].isSettled = true;
        _groups[groupIndex].messages.add(
          GroupMessage(sender: "System", content: "You settled your share!", type: MessageType.settlement, timestamp: DateTime.now()),
        );
      });
      _saveData();
    }
  }

  void _onAddButtonPressed() => Navigator.push(
    context,
    MaterialPageRoute(builder: (context) => AddExpenseScreen(onAddExpense: _addOrUpdateExpense, groups: _groups)),
  );

  @override
  Widget build(BuildContext context) {
    final appState = KiwiApp.of(context);
    final List<Widget> screens = [
      DailyOverviewScreen(expenses: _expenses, onDelete: _removeExpense, onEdit: (e) => _addOrUpdateExpense(e)),
      TrendsScreen(expenses: _expenses),
      CalendarScreen(expenses: _expenses, onEdit: (e) => _addOrUpdateExpense(e)),
      GroupListScreen(groups: _groups, onSendMessage: _sendMessage, onSettle: _settleExpense, onCreateGroup: _addNewGroup),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text("Kiwi", style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
        elevation: 0,
        actions: [
          IconButton(icon: Icon(Icons.sync, color: Theme.of(context).colorScheme.primary), onPressed: _syncSmsExpenses, tooltip: "Bulk Sync SMS"),
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: GestureDetector(
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => ProfileScreen(expenses: _expenses, onClearData: _clearAllData, onLogout: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.clear();
                  if (context.mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginScreen()));
                })));
              },
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Theme.of(context).colorScheme.primary, width: 2)),
                child: CircleAvatar(backgroundColor: Colors.grey.shade200, radius: 16, backgroundImage: appState?.getAvatarProvider()),
              ),
            ),
          ),
        ],
      ),
      body: screens[_selectedIndex],
      // FIX: Added 'heroTag: null' to prevent crash with duplicate heroes
      floatingActionButton: SizedBox(
        height: 65, width: 65,
        child: Hero(tag: 'add_fab', child: FloatingActionButton(heroTag: null, onPressed: _onAddButtonPressed, backgroundColor: const Color(0xFFDCE775), elevation: 4, shape: const CircleBorder(), child: const Icon(Icons.add, size: 32, color: Color(0xFF33691E)))),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(), notchMargin: 8.0, color: Theme.of(context).colorScheme.surface, surfaceTintColor: Colors.transparent,
        child: SizedBox(height: 60, child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [_buildNavItem(0, Icons.home_filled), _buildNavItem(1, Icons.bar_chart), const SizedBox(width: 40), _buildNavItem(2, Icons.calendar_month), _buildNavItem(3, Icons.group)])),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon) {
    return IconButton(onPressed: () => setState(() => _selectedIndex = index), icon: Icon(icon, color: _selectedIndex == index ? Theme.of(context).colorScheme.primary : Colors.grey, size: 28));
  }
}

// --- 6. SCREENS ---

class DailyOverviewScreen extends StatefulWidget {
  final List<Expense> expenses;
  final Function(int) onDelete;
  final Function(Expense) onEdit;

  const DailyOverviewScreen({
    super.key,
    required this.expenses,
    required this.onDelete,
    required this.onEdit,
  });
  @override
  State<DailyOverviewScreen> createState() => _DailyOverviewScreenState();
}

class _DailyOverviewScreenState extends State<DailyOverviewScreen> {
  String _searchQuery = "";
  @override
  Widget build(BuildContext context) {
    final appState = KiwiApp.of(context);
    final currency = appState?.currency ?? '₹';
    final budget = appState?.budget ?? 10000.0;

    double totalIncome = widget.expenses
        .where((e) => e.isIncome)
        .fold(0, (sum, item) => sum + item.amount);
    double totalExpense = widget.expenses
        .where((e) => !e.isIncome)
        .fold(0, (sum, item) => sum + item.amount);
    double balance = totalIncome - totalExpense;
    double progress = (totalExpense / budget).clamp(0.0, 1.0);

    final filteredExpenses = widget.expenses
        .where(
          (e) => e.title.toLowerCase().contains(_searchQuery.toLowerCase()),
        )
        .toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF33691E), Color(0xFFACDEB0)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.green.withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              children: [
                const Text(
                  "Total Balance",
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 5),
                Text(
                  "$currency${balance.toStringAsFixed(2)}",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(
                            color: Colors.white24,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.arrow_downward,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Income",
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              "$currency${totalIncome.toStringAsFixed(2)}",
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(
                            color: Colors.white24,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.arrow_upward,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Expense",
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              "$currency${totalExpense.toStringAsFixed(2)}",
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Budget",
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  Text(
                    "$currency${totalExpense.toStringAsFixed(0)} / $currency${budget.toStringAsFixed(0)}",
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.grey[200],
                color: progress > 0.9 ? Colors.red : const Color(0xFF33691E),
                minHeight: 8,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          ),
          const SizedBox(height: 15),
          TextField(
            decoration: InputDecoration(
              hintText: "Search...",
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
            onChanged: (val) => setState(() => _searchQuery = val),
          ),
          const SizedBox(height: 15),
          Expanded(
            child: filteredExpenses.isEmpty
                ? const Center(
                    child: Text(
                      "No transactions found",
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    itemCount: filteredExpenses.length,
                    itemBuilder: (context, index) {
                      final realIndex = widget.expenses.indexOf(
                        filteredExpenses[index],
                      );
                      final expense = filteredExpenses[index];
                      return _SlideInItem(
                        index: index,
                        child: Dismissible(
                          key: Key(expense.id),
                          background: Container(
                            color: Colors.red,
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            margin: const EdgeInsets.only(bottom: 15),
                            child: const Icon(
                              Icons.delete,
                              color: Colors.white,
                            ),
                          ),
                          direction: DismissDirection.endToStart,
                          onDismissed: (direction) =>
                              widget.onDelete(realIndex),
                          child: GestureDetector(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => AddExpenseScreen(
                                  onAddExpense: (e, {split, groupId}) =>
                                      widget.onEdit(e),
                                  expenseToEdit: expense,
                                ),
                              ),
                            ),
                            child: ExpenseItem(
                              icon: _getIconForCategory(
                                expense.originalCategory,
                              ),
                              title: expense.title,
                              amount:
                                  "${expense.isIncome ? '+' : '-'}$currency${expense.amount.abs().toStringAsFixed(2)}",
                              isIncome: expense.isIncome,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class CalendarScreen extends StatefulWidget {
  final List<Expense> expenses;
  final Function(Expense) onEdit;
  const CalendarScreen({
    super.key,
    required this.expenses,
    required this.onEdit,
  });

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  List<Expense> _getExpensesForDay(DateTime day) {
    return widget.expenses.where((e) => isSameDay(e.date, day)).toList();
  }

  double _getDaySpend(DateTime day) {
    return widget.expenses
        .where((e) => isSameDay(e.date, day) && !e.isIncome)
        .fold(0.0, (sum, e) => sum + e.amount);
  }

  double _getMaxSpendForMonth(DateTime focusedDay) {
    double max = 0;
    final start = focusedDay.subtract(const Duration(days: 15));
    final end = focusedDay.add(const Duration(days: 15));
    for (int i = 0; i < 30; i++) {
      final day = start.add(Duration(days: i));
      double dailyTotal = _getDaySpend(day);
      if (dailyTotal > max) max = dailyTotal;
    }
    return max == 0 ? 1 : max;
  }

  @override
  Widget build(BuildContext context) {
    final currency = KiwiApp.of(context)?.currency ?? '₹';

    List<Expense> selectedExpenses = _selectedDay != null
        ? _getExpensesForDay(_selectedDay!)
        : [];
    selectedExpenses.sort((a, b) => b.date.compareTo(a.date));

    final maxSpend = _getMaxSpendForMonth(_focusedDay);

    return Column(
      children: [
        TableCalendar(
          firstDay: DateTime.utc(2020, 1, 1),
          lastDay: DateTime.utc(2030, 12, 31),
          focusedDay: _focusedDay,
          calendarFormat: _calendarFormat,
          onFormatChanged: (format) {
            setState(() {
              _calendarFormat = format;
            });
          },
          selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
          onDaySelected: (selectedDay, focusedDay) {
            setState(() {
              _selectedDay = selectedDay;
              _focusedDay = focusedDay;
            });
          },
          eventLoader: _getExpensesForDay,
          calendarStyle: CalendarStyle(
            isTodayHighlighted: true,
            todayDecoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
              shape: BoxShape.circle,
            ),
            selectedDecoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              shape: BoxShape.circle,
            ),
          ),
          headerStyle: const HeaderStyle(
            formatButtonVisible: true,
            titleCentered: true,
          ),

          calendarBuilders: CalendarBuilders(
            markerBuilder: (context, day, events) {
              final spend = _getDaySpend(day);
              if (spend == 0) return null;
              double intensity = (spend / maxSpend).clamp(0.2, 1.0);
              return Positioned(
                bottom: 1,
                child: Container(
                  width: 35,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withOpacity(intensity),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            },
          ),
        ),
        const Divider(),
        Expanded(
          child: selectedExpenses.isEmpty
              ? const Center(
                  child: Text(
                    "No transactions for this day",
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  itemCount: selectedExpenses.length,
                  padding: const EdgeInsets.all(20),
                  itemBuilder: (context, index) {
                    final expense = selectedExpenses[index];
                    return GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => AddExpenseScreen(
                            onAddExpense: (e, {split, groupId}) =>
                                widget.onEdit(e),
                            expenseToEdit: expense,
                          ),
                        ),
                      ),
                      child: ExpenseItem(
                        icon: _getIconForCategory(expense.originalCategory),
                        title: expense.title,
                        amount:
                            "${expense.isIncome ? '+' : '-'}$currency${expense.amount.toStringAsFixed(2)}",
                        isIncome: expense.isIncome,
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class CategoryBudgetScreen extends StatefulWidget {
  final List<Expense> expenses;
  const CategoryBudgetScreen({super.key, required this.expenses});

  @override
  State<CategoryBudgetScreen> createState() => _CategoryBudgetScreenState();
}

class _CategoryBudgetScreenState extends State<CategoryBudgetScreen> {
  final Map<String, IconData> _categories = {
    "Food": Icons.fastfood,
    "Transport": Icons.directions_bus,
    "Entertainment": Icons.movie,
    "Health": Icons.medical_services,
    "Shopping": Icons.shopping_bag,
    "Other": Icons.category,
  };

  void _showEditDialog(String category, double currentLimit) {
    final controller = TextEditingController(text: currentLimit.toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Set Budget for $category"),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: "Limit Amount"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                KiwiApp.of(context)?.updateCategoryBudget(
                  category,
                  double.parse(controller.text),
                );
                setState(() {});
                Navigator.pop(ctx);
              }
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = KiwiApp.of(context);
    final currency = appState?.currency ?? '₹';
    final categoryBudgets = appState?.categoryBudgets ?? {};

    return Scaffold(
      appBar: AppBar(title: const Text("Category Budgets")),
      body: ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: _categories.length,
        separatorBuilder: (ctx, i) => const SizedBox(height: 20),
        itemBuilder: (context, index) {
          String cat = _categories.keys.elementAt(index);
          double limit = categoryBudgets[cat] ?? 0.0;
          double spent = widget.expenses
              .where((e) => e.originalCategory == cat && !e.isIncome)
              .fold(0, (sum, e) => sum + e.amount);
          double progress = limit > 0 ? (spent / limit).clamp(0.0, 1.0) : 0.0;

          return Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.grey.withOpacity(0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _categories[cat],
                          color: _getColorForCategory(cat),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          cat,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.edit,
                        size: 20,
                        color: Colors.grey,
                      ),
                      onPressed: () => _showEditDialog(cat, limit),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.grey[200],
                  color: progress > 0.9
                      ? Colors.red
                      : _getColorForCategory(cat),
                  minHeight: 10,
                  borderRadius: BorderRadius.circular(5),
                ),
                const SizedBox(height: 5),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "$currency${spent.toStringAsFixed(0)} spent",
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                    Text(
                      limit > 0
                          ? "Limit: $currency${limit.toStringAsFixed(0)}"
                          : "No Limit",
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SlideInItem extends StatefulWidget {
  final int index;
  final Widget child;
  const _SlideInItem({required this.index, required this.child});
  @override
  State<_SlideInItem> createState() => _SlideInItemState();
}

class _SlideInItemState extends State<_SlideInItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _offsetAnim;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _offsetAnim = Tween<Offset>(
      begin: const Offset(0.5, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    Future.delayed(Duration(milliseconds: widget.index * 50), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _offsetAnim,
      child: FadeTransition(opacity: _controller, child: widget.child),
    );
  }
}

class GroupListScreen extends StatefulWidget {
  final List<Group> groups;
  final Function(String, String) onSendMessage;
  final Function(String, int) onSettle;
  final Function(String, List<String>) onCreateGroup;
  const GroupListScreen({
    super.key,
    required this.groups,
    required this.onSendMessage,
    required this.onSettle,
    required this.onCreateGroup,
  });
  @override
  State<GroupListScreen> createState() => _GroupListScreenState();
}

class _GroupListScreenState extends State<GroupListScreen> {
  void _showCreateDialog() {
    final nameController = TextEditingController();
    final memberController = TextEditingController();
    List<String> members = [];
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("Create Group"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: "Group Name"),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: memberController,
                decoration: InputDecoration(
                  labelText: "Add Member",
                  suffixIcon: IconButton(
                    icon: const Icon(
                      Icons.add_circle,
                      color: Color(0xFF33691E),
                    ),
                    onPressed: () {
                      if (memberController.text.isNotEmpty) {
                        setDialogState(() {
                          members.add(memberController.text);
                          memberController.clear();
                        });
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 5,
                children: members
                    .map(
                      (m) => Chip(
                        label: Text(m),
                        backgroundColor: const Color(0xFFDCEDC8),
                        onDeleted: () =>
                            setDialogState(() => members.remove(m)),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () {
                if (nameController.text.isNotEmpty && members.isNotEmpty) {
                  widget.onCreateGroup(nameController.text, members);
                  Navigator.pop(ctx);
                }
              },
              child: const Text("Create"),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currency = KiwiApp.of(context)?.currency ?? '₹';
    double totalToGet = 0;
    double totalToPay = 0;
    for (var group in widget.groups) {
      double net = group.getMyNetBalance();
      if (net > 0) totalToGet += net;
      if (net < 0) totalToPay += net.abs();
    }
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Groups",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              IconButton(
                onPressed: _showCreateDialog,
                icon: const Icon(
                  Icons.add_circle,
                  size: 32,
                  color: Color(0xFF33691E),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildSummaryBox(
                  "You get",
                  "$currency${totalToGet.toStringAsFixed(0)}",
                  Colors.green,
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: _buildSummaryBox(
                  "You pay",
                  "$currency${totalToPay.toStringAsFixed(0)}",
                  Colors.red,
                ),
              ),
            ],
          ),
          const SizedBox(height: 30),
          Expanded(
            child: ListView.builder(
              itemCount: widget.groups.length,
              itemBuilder: (context, index) {
                final group = widget.groups[index];
                double net = group.getMyNetBalance();
                return _SlideInItem(
                  index: index,
                  child: Card(
                    elevation: 0,
                    color: Theme.of(context).colorScheme.surface,
                    margin: const EdgeInsets.only(bottom: 15),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(15),
                      leading: const CircleAvatar(
                        radius: 25,
                        backgroundColor: Color(0xFFACDEB0),
                        child: Icon(Icons.group, color: Color(0xFF33691E)),
                      ),
                      title: Text(
                        group.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      subtitle: Text(
                        net == 0
                            ? "Settled up"
                            : (net > 0
                                ? "You get $currency${net.toStringAsFixed(0)}"
                                : "You owe $currency${net.abs().toStringAsFixed(0)}"),
                        style: TextStyle(
                          color: net == 0
                              ? Colors.grey
                              : (net > 0 ? Colors.green : Colors.red),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => GroupChatScreen(
                            group: group,
                            onSendMessage: widget.onSendMessage,
                            onSettle: widget.onSettle,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryBox(String label, String amount, Color color) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 5),
          Text(
            amount,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class GroupChatScreen extends StatefulWidget {
  final Group group;
  final Function(String, String) onSendMessage;
  final Function(String, int) onSettle;
  const GroupChatScreen({
    super.key,
    required this.group,
    required this.onSendMessage,
    required this.onSettle,
  });
  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients)
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
  }

  @override
  Widget build(BuildContext context) {
    final currency = KiwiApp.of(context)?.currency ?? '₹';
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.group.name),
        backgroundColor: Theme.of(context).colorScheme.surface,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(20),
              itemCount: widget.group.messages.length,
              itemBuilder: (context, index) {
                final msg = widget.group.messages[index];
                final isMe = msg.sender == "You";
                if (msg.type == MessageType.expense)
                  return _buildExpenseBubble(msg, index, isMe, currency);
                if (msg.type == MessageType.settlement)
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(
                        msg.content,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  );
                return Align(
                  alignment: isMe
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isMe
                          ? const Color(0xFFF6CB89)
                          : Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!isMe)
                          Text(
                            msg.sender,
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.green[800],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        Text(
                          msg.content,
                          style: TextStyle(
                            color: isMe
                                ? Colors.black
                                : Theme.of(context).textTheme.bodyMedium?.color,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(15),
            color: Theme.of(context).colorScheme.surface,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _msgController,
                    decoration: InputDecoration(
                      hintText: "Type...",
                      filled: true,
                      fillColor: const Color(0xFFF1F8E9),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: Color(0xFF33691E)),
                  onPressed: () {
                    if (_msgController.text.isNotEmpty) {
                      widget.onSendMessage(
                        widget.group.id,
                        _msgController.text,
                      );
                      _msgController.clear();
                      Future.delayed(
                        const Duration(milliseconds: 100),
                        _scrollToBottom,
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpenseBubble(
    GroupMessage msg,
    int index,
    bool isMe,
    String currency,
  ) {
    return Align(
      alignment: Alignment.center,
      child: Container(
        width: 250,
        margin: const EdgeInsets.symmetric(vertical: 15),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: msg.isSettled ? Colors.green : Colors.grey.withOpacity(0.3),
          ),
          boxShadow: [const BoxShadow(color: Colors.black12, blurRadius: 5)],
        ),
        child: Column(
          children: [
            Text(
              msg.content,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              "paid by ${msg.sender}",
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(isMe ? "You paid" : "Your share"),
                Text(
                  "$currency${(msg.amount / widget.group.members.length).toStringAsFixed(2)}",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isMe ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ),
            if (!isMe && !msg.isSettled)
              ElevatedButton(
                onPressed: () => widget.onSettle(widget.group.id, index),
                child: const Text("Settle"),
              ),
            if (msg.isSettled)
              const Text(
                "SETTLED",
                style: TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// --- ADD EXPENSE SCREEN (Manual Only - No AI Button) ---
class AddExpenseScreen extends StatefulWidget {
  final Function(Expense, {bool? split, String? groupId}) onAddExpense;
  final List<Group> groups;
  final Expense? expenseToEdit;

  const AddExpenseScreen({
    super.key,
    required this.onAddExpense,
    this.groups = const [],
    this.expenseToEdit
  });

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  String _selectedCategory = "Food";
  bool _splitWithGroup = false;
  String? _selectedGroupId;
  bool _isIncome = false;

  final Map<String, IconData> _categories = {
    "Food": Icons.fastfood,
    "Transport": Icons.directions_bus,
    "Entertainment": Icons.movie,
    "Health": Icons.medical_services,
    "Shopping": Icons.shopping_bag,
    "Other": Icons.category,
  };

  @override
  void initState() {
    super.initState();
    if (widget.expenseToEdit != null) {
      final e = widget.expenseToEdit!;
      _amountController.text = e.amount.toString();
      _noteController.text = e.title;
      _isIncome = e.isIncome;
      if (_categories.containsKey(e.originalCategory)) {
        _selectedCategory = e.originalCategory;
      }
    }
    // Default to first group if available
    if (_selectedGroupId == null && widget.groups.isNotEmpty) {
      _selectedGroupId = widget.groups.first.id;
    }
  }

  void _submitData() {
    final enteredAmount = double.tryParse(_amountController.text);
    if (enteredAmount == null || enteredAmount <= 0) return;

    // Determine Title and Category
    String finalTitle = _noteController.text.trim().isNotEmpty
        ? _noteController.text.trim()
        : (_isIncome ? "Income" : _selectedCategory);

    String finalCat = _isIncome ? "Income" : _selectedCategory;

    final String id = widget.expenseToEdit?.id ?? DateTime.now().millisecondsSinceEpoch.toString();
    final DateTime date = widget.expenseToEdit?.date ?? DateTime.now();

    widget.onAddExpense(
      Expense(
        id: id,
        title: finalTitle,
        amount: enteredAmount,
        date: date,
        originalCategory: finalCat,
        isIncome: _isIncome // Ensure this is passed correctly
      ),
      split: _splitWithGroup,
      groupId: _selectedGroupId,
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.expenseToEdit == null ? "Add Transaction" : "Edit Transaction")
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            // TOGGLE BUTTONS (Only visible for new transactions)
            if (widget.expenseToEdit == null)
              Row(children: [
                Expanded(child: GestureDetector(
                    onTap: () => setState(() => _isIncome = false),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: !_isIncome ? Colors.red[100] : Colors.grey[200],
                        borderRadius: BorderRadius.circular(10)
                      ),
                      child: const Center(child: Text("Expense", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)))
                    ))),
                const SizedBox(width: 10),
                Expanded(child: GestureDetector(
                    onTap: () => setState(() => _isIncome = true),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _isIncome ? Colors.green[100] : Colors.grey[200],
                        borderRadius: BorderRadius.circular(10)
                      ),
                      child: const Center(child: Text("Income", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)))
                    ))),
              ]),
            const SizedBox(height: 20),

            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Amount", prefixIcon: Icon(Icons.wallet))
            ),
            const SizedBox(height: 20),

            // HIDE Category Dropdown if Income
            if (!_isIncome) ...[
              DropdownButton<String>(
                value: _selectedCategory,
                isExpanded: true,
                items: _categories.keys.map((String value) => DropdownMenuItem<String>(value: value, child: Text(value))).toList(),
                onChanged: (newValue) => setState(() => _selectedCategory = newValue!),
              ),
              const SizedBox(height: 20),
            ],

            TextField(
              controller: _noteController,
              decoration: const InputDecoration(labelText: "Add Note", prefixIcon: Icon(Icons.edit_note))
            ),
            const SizedBox(height: 20),

            // HIDE Split option if Income
            if (!_isIncome && widget.expenseToEdit == null) ...[
              SwitchListTile(
                title: const Text("Split with Group?"),
                value: _splitWithGroup,
                activeThumbColor: const Color(0xFF33691E),
                onChanged: (val) => setState(() => _splitWithGroup = val)
              ),
              if (_splitWithGroup && widget.groups.isNotEmpty)
                DropdownButton<String>(
                  value: _selectedGroupId,
                  isExpanded: true,
                  items: widget.groups.map((g) => DropdownMenuItem(value: g.id, child: Text(g.name))).toList(),
                  onChanged: (val) => setState(() => _selectedGroupId = val),
                ),
            ],

            const Spacer(),

            Hero(
              tag: 'add_fab',
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  backgroundColor: _isIncome ? Colors.green : const Color(0xFFDCE775),
                  foregroundColor: _isIncome ? Colors.white : const Color(0xFF33691E)
                ),
                onPressed: _submitData,
                child: Text(
                  widget.expenseToEdit == null
                      ? (_isIncome ? "Add Income" : "Save Expense")
                      : "Update Transaction"
                ),
              )
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}

class TrendsScreen extends StatefulWidget {
  final List<Expense> expenses;
  const TrendsScreen({super.key, required this.expenses});
  @override
  State<TrendsScreen> createState() => _TrendsScreenState();
}

class _TrendsScreenState extends State<TrendsScreen> {
  bool isDaily = true;
  int touchedIndex = -1;
  @override
  Widget build(BuildContext context) {
    final currency = KiwiApp.of(context)?.currency ?? '₹';
    final expenseList = widget.expenses.where((e) => !e.isIncome).toList();
    List<double> weeklySpending = List.filled(7, 0.0);
    for (var expense in expenseList) {
      weeklySpending[expense.date.weekday - 1] += expense.amount;
    }
    Map<String, double> categoryTotals = {};
    double totalMonthSpend = 0;
    for (var expense in expenseList) {
      categoryTotals[expense.originalCategory] =
          (categoryTotals[expense.originalCategory] ?? 0) + expense.amount;
      totalMonthSpend += expense.amount;
    }
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: SingleChildScrollView(
        child: Column(
          children: [
            const Text(
              "Trends",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(25),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => isDaily = true),
                      child: _TabButton(text: "Daily", isSelected: isDaily),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => isDaily = false),
                      child: _TabButton(text: "Monthly", isSelected: !isDaily),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            isDaily
                ? RepaintBoundary(
                    child: SizedBox(
                      height: 300,
                      child: fl.BarChart(
                        fl.BarChartData(
                          barTouchData: fl.BarTouchData(
                            touchTooltipData: fl.BarTouchTooltipData(
                              tooltipBgColor: const Color(0xFF263238),
                              getTooltipItem:
                                  (group, groupIndex, rod, rodIndex) {
                                return fl.BarTooltipItem(
                                  '$currency${rod.toY.toInt()}',
                                  const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                );
                              },
                            ),
                          ),
                          titlesData: fl.FlTitlesData(
                            topTitles: const fl.AxisTitles(
                              sideTitles: fl.SideTitles(showTitles: false),
                            ),
                            rightTitles: const fl.AxisTitles(
                              sideTitles: fl.SideTitles(showTitles: false),
                            ),
                            leftTitles: fl.AxisTitles(
                              sideTitles: fl.SideTitles(
                                showTitles: true,
                                reservedSize: 40,
                                getTitlesWidget: (value, meta) {
                                  if (value == 0)
                                    return const SizedBox.shrink();
                                  return Text(
                                    '${value.toInt()}',
                                    style: const TextStyle(
                                      color: Colors.grey,
                                      fontSize: 10,
                                    ),
                                  );
                                },
                              ),
                            ),
                            bottomTitles: fl.AxisTitles(
                              sideTitles: fl.SideTitles(
                                showTitles: true,
                                interval: 1,
                                getTitlesWidget: (val, meta) {
                                  const days = [
                                    'M',
                                    'T',
                                    'W',
                                    'T',
                                    'F',
                                    'S',
                                    'S',
                                  ];
                                  if (val.toInt() < 7 && val.toInt() >= 0)
                                    return Text(
                                      days[val.toInt()],
                                      style: const TextStyle(
                                        color: Colors.grey,
                                      ),
                                    );
                                  return const Text('');
                                },
                              ),
                            ),
                          ),
                          gridData: const fl.FlGridData(show: false),
                          borderData: fl.FlBorderData(show: false),
                          barGroups: [
                            for (int i = 0; i < 7; i++)
                              fl.BarChartGroupData(
                                x: i,
                                barRods: [
                                  fl.BarChartRodData(
                                    toY: weeklySpending[i],
                                    color: const Color(0xFF33691E),
                                    width: 15,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  )
                : Column(
                    children: [
                      RepaintBoundary(
                        child: SizedBox(
                          height: 250,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    "Total",
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 14,
                                    ),
                                  ),
                                  Text(
                                    "$currency${totalMonthSpend.toStringAsFixed(0)}",
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 24,
                                    ),
                                  ),
                                ],
                              ),
                              fl.PieChart(
                                fl.PieChartData(
                                  pieTouchData: fl.PieTouchData(
                                    touchCallback:
                                        (
                                          fl.FlTouchEvent event,
                                          pieTouchResponse,
                                        ) {
                                      setState(() {
                                        if (!event
                                                .isInterestedForInteractions ||
                                            pieTouchResponse == null ||
                                            pieTouchResponse
                                                    .touchedSection ==
                                                null) {
                                          touchedIndex = -1;
                                          return;
                                        }
                                        touchedIndex = pieTouchResponse
                                            .touchedSection!
                                            .touchedSectionIndex;
                                      });
                                    },
                                  ),
                                  sectionsSpace: 6,
                                  centerSpaceRadius: 50,
                                  sections: _generatePieSections(
                                    categoryTotals,
                                    context,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 30),
                      Wrap(
                        spacing: 15,
                        runSpacing: 15,
                        alignment: WrapAlignment.center,
                        children: categoryTotals.keys
                            .map(
                              (category) => _buildLegendItem(
                                context,
                                category,
                                categoryTotals[category]!,
                                currency,
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(
    BuildContext context,
    String category,
    double amount,
    String currency,
  ) {
    final color = _getColorForCategory(category);
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CategoryDetailsScreen(
            category: category,
            allExpenses: widget.expenses,
          ),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.withOpacity(0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(radius: 5, backgroundColor: color),
            const SizedBox(width: 8),
            Text(category, style: const TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(width: 5),
            Text(
              "$currency${amount.toStringAsFixed(0)}",
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  List<fl.PieChartSectionData> _generatePieSections(
    Map<String, double> categoryTotals,
    BuildContext context,
  ) {
    List<fl.PieChartSectionData> sections = [];
    int index = 0;
    categoryTotals.forEach((key, value) {
      final isTouched = index == touchedIndex;
      final opacity = (touchedIndex != -1 && !isTouched) ? 0.3 : 1.0;
      final color = _getColorForCategory(key).withOpacity(opacity);
      sections.add(
        fl.PieChartSectionData(
          color: color,
          value: value,
          title: '',
          radius: isTouched ? 40 : 35,
          // 🟢 FIXED: Removed invalid borderRadius, using sectionsSpace in parent PieChartData instead
          badgeWidget: isTouched ? _buildBadge(value, context) : null,
          badgePositionPercentageOffset: 1.5,
        ),
      );
      index++;
    });
    return sections;
  }

  Widget _buildBadge(double value, BuildContext context) {
    final currency = KiwiApp.of(context)?.currency ?? '₹';
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          const BoxShadow(
            color: Colors.black12,
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        "$currency${value.toStringAsFixed(0)}",
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 12,
          color: Colors.black,
        ),
      ),
    );
  }
}

class CategoryDetailsScreen extends StatelessWidget {
  final String category;
  final List<Expense> allExpenses;
  const CategoryDetailsScreen({
    super.key,
    required this.category,
    required this.allExpenses,
  });
  @override
  Widget build(BuildContext context) {
    final currency = KiwiApp.of(context)?.currency ?? '₹';
    final categoryExpenses = allExpenses
        .where((e) => e.originalCategory == category && !e.isIncome)
        .toList();
    categoryExpenses.sort((a, b) => b.date.compareTo(a.date));
    return Scaffold(
      appBar: AppBar(
        title: Text(
          category,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      ),
      body: categoryExpenses.isEmpty
          ? const Center(child: Text("No expenses found"))
          : ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: categoryExpenses.length,
              itemBuilder: (context, index) {
                final expense = categoryExpenses[index];
                return _SlideInItem(
                  index: index,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 15),
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: _getColorForCategory(
                            category,
                          ).withOpacity(0.2),
                          child: Icon(
                            _getIconForCategory(category),
                            color: _getColorForCategory(category),
                          ),
                        ),
                        const SizedBox(width: 15),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                expense.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              Text(
                                DateFormat('MMM dd, yyyy').format(expense.date),
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          "$currency${expense.amount.toStringAsFixed(2)}",
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Color(0xFF33691E),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class ReportService {
  static Future<void> generatePdf(
    List<Expense> allExpenses,
    String currency,
    DateTime start,
    DateTime end,
  ) async {
    final pdf = pw.Document();
    final font = pw.Font.courier();
    final fontBold = pw.Font.courierBold();

    final PdfColor greenDark = PdfColor.fromInt(0xFF33691E);
    final PdfColor greenLight = PdfColor.fromInt(0xFFDCEDC8);
    final PdfColor redDark = PdfColor.fromInt(0xFFB71C1C);
    final PdfColor redLight = PdfColor.fromInt(0xFFFFEBEE);
    final PdfColor blueDark = PdfColor.fromInt(0xFF0D47A1);
    final PdfColor blueLight = PdfColor.fromInt(0xFFE3F2FD);
    final PdfColor greyColor = PdfColor.fromInt(0xFF757575);
    final PdfColor whiteColor = PdfColor.fromInt(0xFFFFFFFF);

    final rangeStart = DateTime(start.year, start.month, start.day);
    final rangeEnd = DateTime(end.year, end.month, end.day, 23, 59, 59);

    final expenses = allExpenses.where((e) {
      return e.date.isAfter(rangeStart.subtract(const Duration(seconds: 1))) &&
          e.date.isBefore(rangeEnd);
    }).toList();

    expenses.sort((a, b) => b.date.compareTo(a.date));

    double totalIncome = expenses
        .where((e) => e.isIncome)
        .fold(0, (sum, e) => sum + e.amount);
    double totalExpense = expenses
        .where((e) => !e.isIncome)
        .fold(0, (sum, e) => sum + e.amount);
    double balance = totalIncome - totalExpense;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Kiwi Statement',
                      style: pw.TextStyle(
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                        color: greenDark,
                      ),
                    ),
                    pw.Text(
                      '${DateFormat('MMM dd, yyyy').format(rangeStart)} - ${DateFormat('MMM dd, yyyy').format(rangeEnd)}',
                      style: pw.TextStyle(color: greyColor),
                    ),
                  ],
                ),
                pw.PdfLogo(),
              ],
            ),
          ),
          pw.SizedBox(height: 20),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
            children: [
              _buildPdfSummaryCard(
                'Income',
                '$currency${totalIncome.toStringAsFixed(2)}',
                greenLight,
                greenDark,
              ),
              _buildPdfSummaryCard(
                'Expense',
                '$currency${totalExpense.toStringAsFixed(2)}',
                redLight,
                redDark,
              ),
              _buildPdfSummaryCard(
                'Balance',
                '$currency${balance.toStringAsFixed(2)}',
                blueLight,
                blueDark,
              ),
            ],
          ),
          pw.SizedBox(height: 30),
          pw.Text(
            "Transaction History",
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 10),
          expenses.isEmpty
              ? pw.Center(
                  child: pw.Text(
                    "No transactions found in this period.",
                    style: pw.TextStyle(color: greyColor),
                  ),
                )
              : pw.Table.fromTextArray(
                  headers: ['Date', 'Title', 'Category', 'Amount'],
                  headerStyle: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    color: whiteColor,
                  ),
                  headerDecoration: pw.BoxDecoration(color: greenDark),
                  rowDecoration: pw.BoxDecoration(
                    border: pw.Border(bottom: pw.BorderSide(color: greyColor)),
                  ),
                  data: expenses
                      .map(
                        (e) => [
                          DateFormat('MMM dd').format(e.date),
                          e.title,
                          e.originalCategory,
                          '${e.isIncome ? '+' : '-'}$currency${e.amount.toStringAsFixed(2)}',
                        ],
                      )
                      .toList(),
                  cellAlignment: pw.Alignment.centerLeft,
                  cellAlignments: {3: pw.Alignment.centerRight},
                ),
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Kiwi_Statement.pdf',
    );
  }

  static pw.Widget _buildPdfSummaryCard(
    String title,
    String amount,
    PdfColor bgColor,
    PdfColor textColor,
  ) {
    return pw.Container(
      width: 100,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: bgColor,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        children: [
          pw.Text(title, style: pw.TextStyle(color: textColor, fontSize: 10)),
          pw.Text(
            amount,
            style: pw.TextStyle(
              color: textColor,
              fontWeight: pw.FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}

// --- MISSING WIDGET CLASSES DEFINITIONS (Added back to fix undefined errors) ---

class _TabButton extends StatelessWidget {
  final String text;
  final bool isSelected;
  const _TabButton({required this.text, required this.isSelected});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFFFF59D) : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Center(
        child: Text(
          text,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isSelected ? Colors.black : Colors.grey,
          ),
        ),
      ),
    );
  }
}

class ExpenseItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String amount;
  final bool isIncome;
  const ExpenseItem({
    super.key,
    required this.icon,
    required this.title,
    required this.amount,
    this.isIncome = false,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          Icon(icon, color: isIncome ? Colors.green : Colors.brown),
          const SizedBox(width: 15),
          Expanded(
            child: Row(
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          Text(
            amount,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: isIncome ? Colors.green : Colors.redAccent,
            ),
          ),
        ],
      ),
    );
  }
}