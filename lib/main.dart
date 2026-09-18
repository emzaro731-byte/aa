import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AaBrowserApp());
}

class AaBrowserApp extends StatefulWidget {
  const AaBrowserApp({super.key});
  @override
  State<AaBrowserApp> createState() => _AaBrowserAppState();
}

class _AaBrowserAppState extends State<AaBrowserApp> {
  bool dark = true;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AA Browser',
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      darkTheme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
      ),
      home: BrowserHome(
        dark: dark,
        onThemeChanged: () => setState(() => dark = !dark),
      ),
    );
  }
}

class BrowserTab {
  BrowserTab({required this.controller, required this.url});
  final WebViewController controller;
  String url;
  String title = 'New tab';
}

class BrowserHome extends StatefulWidget {
  const BrowserHome({
    super.key,
    required this.dark,
    required this.onThemeChanged,
  });

  final bool dark;
  final VoidCallback onThemeChanged;

  @override
  State<BrowserHome> createState() => _BrowserHomeState();
}

class _BrowserHomeState extends State<BrowserHome> {
  static const homeUrl = 'https://emzaro731-byte.github.io/aa/';
  final addressController = TextEditingController();
  final List<BrowserTab> tabs = [];
  List<String> history = [];
  List<String> bookmarks = [];
  int activeTab = 0;
  int progress = 100;

  BrowserTab get tab => tabs[activeTab];

  @override
  void initState() {
    super.initState();
    _loadSavedData();
    _newTab();
  }

  Future<void> _loadSavedData() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      history = prefs.getStringList('history') ?? [];
      bookmarks = prefs.getStringList('bookmarks') ?? [];
    });
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('history', history.take(100).toList());
    await prefs.setStringList('bookmarks', bookmarks.take(100).toList());
  }

  void _newTab({String url = homeUrl}) {
    late final WebViewController controller;
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..enableZoom(false)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (value) {
            if (mounted) setState(() => progress = value);
          },
          onPageStarted: (url) {
            if (!mounted) return;
            setState(() {
              tab.url = url;
              addressController.text = url;
            });
          },
          onPageFinished: (url) async {
            final title = await controller.getTitle();
            if (!mounted) return;
            setState(() {
              tab.url = url;
              tab.title = title?.trim().isNotEmpty == true ? title! : 'Web page';
              addressController.text = url;
              progress = 100;
            });
            if (url != 'about:blank' && !history.contains(url)) {
              history.insert(0, url);
              if (history.length > 100) history.removeLast();
              await _saveData();
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(url));

    setState(() {
      tabs.add(BrowserTab(controller: controller, url: url));
      activeTab = tabs.length - 1;
      addressController.text = url;
    });
  }

  String _makeUrl(String input) {
    final value = input.trim();
    if (value.isEmpty) return homeUrl;
    final uri = Uri.tryParse(value);
    if (uri != null &&
        uri.hasScheme &&
        (uri.scheme == 'http' || uri.scheme == 'https')) {
      return value;
    }
    if (value.contains('.') && !value.contains(' ')) {
      return 'https://' + value;
    }
    return 'https://www.google.com/search?q=' + Uri.encodeComponent(value);
  }

  Future<void> _go() async {
    final url = _makeUrl(addressController.text);
    FocusManager.instance.primaryFocus?.unfocus();
    await tab.controller.loadRequest(Uri.parse(url));
  }

  Future<void> _showBookmarks() async {
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: SizedBox(
          height: 420,
          child: Column(
            children: [
              const ListTile(
                leading: Icon(Icons.bookmark),
                title: Text('Bookmarks'),
              ),
              Expanded(
                child: bookmarks.isEmpty
                    ? const Center(child: Text('No bookmarks yet'))
                    : ListView.builder(
                        itemCount: bookmarks.length,
                        itemBuilder: (_, i) => ListTile(
                          leading: const Icon(Icons.public),
                          title: Text(
                            bookmarks[i],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            tab.controller.loadRequest(Uri.parse(bookmarks[i]));
                          },
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              setState(() => bookmarks.removeAt(i));
                              await _saveData();
                            },
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showHistory() async {
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: SizedBox(
          height: 480,
          child: Column(
            children: [
              const ListTile(
                leading: Icon(Icons.history),
                title: Text('History'),
              ),
              Expanded(
                child: history.isEmpty
                    ? const Center(child: Text('No history yet'))
                    : ListView.builder(
                        itemCount: history.length,
                        itemBuilder: (_, i) => ListTile(
                          leading: const Icon(Icons.public),
                          title: Text(
                            history[i],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            tab.controller.loadRequest(Uri.parse(history[i]));
                          },
                        ),
                      ),
              ),
              TextButton.icon(
                onPressed: () async {
                  setState(() => history.clear());
                  await _saveData();
                  if (context.mounted) Navigator.pop(context);
                },
                icon: const Icon(Icons.delete_sweep_outlined),
                label: const Text('Clear history'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showDailyData() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final claimedDate = prefs.getString('daily_claim_date');
    final claimed = claimedDate == today;
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Daily 1 GB'),
        content: Text(
          claimed
              ? 'Today\'s 1 GB bonus has already been claimed. This screen tracks an in-app bonus only; it does not add mobile data to your SIM.'
              : 'Claim your daily 1 GB bonus. This is an in-app reward tracker. Actual mobile data requires a supported telecom/ISP data API or sponsored data partnership.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          if (!claimed)
            FilledButton(
              onPressed: () async {
                await prefs.setString('daily_claim_date', today);
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Daily 1 GB bonus claimed in the app.')),
                  );
                }
              },
              child: const Text('Claim 1 GB'),
            ),
        ],
      ),
    );
  }

  Future<void> _addBookmark() async {
    final url = tab.url;
    if (!bookmarks.contains(url) && url != homeUrl) {
      setState(() => bookmarks.insert(0, url));
      await _saveData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Added to bookmarks')),
        );
      }
    }
  }

  Future<bool> _back() async {
    if (await tab.controller.canGoBack()) {
      await tab.controller.goBack();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final wentBack = await _back();
        if (!wentBack && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              if (progress < 100)
                LinearProgressIndicator(value: progress / 100),
              _buildTopBar(),
              _buildTabs(scheme),
              Expanded(child: WebViewWidget(controller: tab.controller)),
              _buildBottomBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final secure = tab.url.startsWith('https://');
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Home',
            onPressed: () =>
                tab.controller.loadRequest(Uri.parse(homeUrl)),
            icon: const Icon(Icons.home_outlined),
          ),
          Expanded(
            child: TextField(
              controller: addressController,
              textInputAction: TextInputAction.go,
              keyboardType: TextInputType.url,
              onSubmitted: (_) => _go(),
              decoration: InputDecoration(
                hintText: 'Search or enter address',
                prefixIcon: Icon(
                  secure ? Icons.lock_outline : Icons.search,
                  size: 20,
                ),
                suffixIcon: IconButton(
                  onPressed: _go,
                  icon: const Icon(Icons.arrow_forward),
                ),
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'bookmark') _addBookmark();
              if (value == 'bookmarks') _showBookmarks();
              if (value == 'history') _showHistory();
              if (value == 'theme') widget.onThemeChanged();
              if (value == 'daily') _showDailyData();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'bookmark',
                child: ListTile(
                  leading: Icon(Icons.bookmark_add_outlined),
                  title: Text('Add bookmark'),
                ),
              ),
              const PopupMenuItem(
                value: 'bookmarks',
                child: ListTile(
                  leading: Icon(Icons.bookmarks_outlined),
                  title: Text('Bookmarks'),
                ),
              ),
              const PopupMenuItem(
                value: 'history',
                child: ListTile(
                  leading: Icon(Icons.history),
                  title: Text('History'),
                ),
              ),
              const PopupMenuItem(
                value: 'daily',
                child: ListTile(
                  leading: Icon(Icons.data_usage),
                  title: Text('Daily 1 GB'),
                ),
              ),
              PopupMenuItem(
                value: 'theme',
                child: ListTile(
                  leading: Icon(
                    widget.dark ? Icons.light_mode : Icons.dark_mode,
                  ),
                  title: Text(
                    widget.dark ? 'Light mode' : 'Dark mode',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTabs(ColorScheme scheme) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: tabs.length,
              itemBuilder: (_, i) => Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => setState(() {
                    activeTab = i;
                    addressController.text = tabs[i].url;
                  }),
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: i == activeTab
                          ? scheme.secondaryContainer
                          : scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.public, size: 16),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            tabs[i].title,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: () {
                            if (tabs.length == 1) return;
                            setState(() {
                              tabs.removeAt(i);
                              if (activeTab >= tabs.length) {
                                activeTab = tabs.length - 1;
                              } else if (i < activeTab) {
                                activeTab--;
                              }
                              addressController.text = tab.url;
                            });
                          },
                          child: const Icon(Icons.close, size: 16),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'New tab',
            onPressed: () => _newTab(),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Material(
      elevation: 8,
      child: SizedBox(
        height: 58,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            IconButton(
              tooltip: 'Back',
              onPressed: _back,
              icon: const Icon(Icons.arrow_back),
            ),
            IconButton(
              tooltip: 'Forward',
              onPressed: () async {
                if (await tab.controller.canGoForward()) {
                  await tab.controller.goForward();
                }
              },
              icon: const Icon(Icons.arrow_forward),
            ),
            IconButton(
              tooltip: 'Reload',
              onPressed: () => tab.controller.reload(),
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: 'Add bookmark',
              onPressed: _addBookmark,
              icon: const Icon(Icons.bookmark_border),
            ),
            IconButton(
              tooltip: 'History',
              onPressed: _showHistory,
              icon: const Icon(Icons.history),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    addressController.dispose();
    super.dispose();
  }
}
