import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// ═══════════════════════════════════════════════════════════════
// 宠物经济系统 — 宠物币、商店、背包、饱腹度、成就
// ═══════════════════════════════════════════════════════════════

/// 食物物品定义
class PetFoodItem {
  final String id;
  final String nameKey; // 国际化 key
  final String descKey; // 国际化 key
  final String assetPath; // 精灵图素材路径
  final int spriteCol; // 精灵图中的列 (0-based)
  final int spriteRow; // 精灵图中的行 (0-based)
  final int price; // 宠物币价格
  final int satietyRestore; // 恢复饱腹度
  final int happinessBoost; // 增加心情值
  final String? specialEffect; // 特殊效果描述

  const PetFoodItem({
    required this.id,
    required this.nameKey,
    required this.descKey,
    this.assetPath = 'assets/pets/Food/MeatSmall.png',
    required this.spriteCol,
    required this.spriteRow,
    required this.price,
    required this.satietyRestore,
    this.happinessBoost = 0,
    this.specialEffect,
  });

  /// 精灵图参数：4列5行，每格 32x32
  static const int sheetCols = 4;
  static const int sheetRows = 5;
  static const double cellSize = 32;
}

/// 商店商品目录
class PetShop {
  PetShop._();
  static final PetShop instance = PetShop._();

  /// 所有可购买的食物（坐标对应 MeatSmall.png 4x5 精灵图）
  ///
  /// 行列布局：
  /// Row 0: 香蕉、苹果、紫葡萄、绿葡萄
  /// Row 1: 菠萝、猕猴桃、樱桃、草莓
  /// Row 2: 胡萝卜、番茄、茄子、南瓜
  /// Row 3: 花菜、洋蒜、辣椒、蘑菇
  /// Row 4: 火腿、鸡腿、鱼、大龙虾
  static const List<PetFoodItem> catalog = [
    // ─── Row 0: 水果（基础） ───
    PetFoodItem(id: 'banana', nameKey: 'petFoodBanana', descKey: 'petFoodBananaDesc', spriteCol: 0, spriteRow: 0, price: 3, satietyRestore: 8, happinessBoost: 3),
    PetFoodItem(id: 'apple', nameKey: 'petFoodApple', descKey: 'petFoodAppleDesc', spriteCol: 1, spriteRow: 0, price: 3, satietyRestore: 8, happinessBoost: 3),
    PetFoodItem(id: 'purple_grape', nameKey: 'petFoodPurpleGrape', descKey: 'petFoodPurpleGrapeDesc', spriteCol: 2, spriteRow: 0, price: 5, satietyRestore: 6, happinessBoost: 8),
    PetFoodItem(id: 'green_grape', nameKey: 'petFoodGreenGrape', descKey: 'petFoodGreenGrapeDesc', spriteCol: 3, spriteRow: 0, price: 5, satietyRestore: 6, happinessBoost: 8),
    // ─── Row 1: 水果（高级） ───
    PetFoodItem(id: 'pineapple', nameKey: 'petFoodPineapple', descKey: 'petFoodPineappleDesc', spriteCol: 0, spriteRow: 1, price: 8, satietyRestore: 12, happinessBoost: 5),
    PetFoodItem(id: 'kiwi', nameKey: 'petFoodKiwi', descKey: 'petFoodKiwiDesc', spriteCol: 1, spriteRow: 1, price: 8, satietyRestore: 10, happinessBoost: 6),
    PetFoodItem(id: 'cherry', nameKey: 'petFoodCherry', descKey: 'petFoodCherryDesc', spriteCol: 2, spriteRow: 1, price: 10, satietyRestore: 5, happinessBoost: 15, specialEffect: 'happy_dance'),
    PetFoodItem(id: 'strawberry', nameKey: 'petFoodStrawberry', descKey: 'petFoodStrawberryDesc', spriteCol: 3, spriteRow: 1, price: 10, satietyRestore: 8, happinessBoost: 12),
    // ─── Row 2: 蔬菜 ───
    PetFoodItem(id: 'carrot', nameKey: 'petFoodCarrot', descKey: 'petFoodCarrotDesc', spriteCol: 0, spriteRow: 2, price: 4, satietyRestore: 12, happinessBoost: 2),
    PetFoodItem(id: 'tomato', nameKey: 'petFoodTomato', descKey: 'petFoodTomatoDesc', spriteCol: 1, spriteRow: 2, price: 4, satietyRestore: 10, happinessBoost: 3),
    PetFoodItem(id: 'eggplant', nameKey: 'petFoodEggplant', descKey: 'petFoodEggplantDesc', spriteCol: 2, spriteRow: 2, price: 4, satietyRestore: 12, happinessBoost: 2),
    PetFoodItem(id: 'pumpkin', nameKey: 'petFoodPumpkin', descKey: 'petFoodPumpkinDesc', spriteCol: 3, spriteRow: 2, price: 6, satietyRestore: 20, happinessBoost: 3),
    // ─── Row 3: 蔬菜（调味） ───
    PetFoodItem(id: 'broccoli', nameKey: 'petFoodBroccoli', descKey: 'petFoodBroccoliDesc', spriteCol: 0, spriteRow: 3, price: 5, satietyRestore: 15, happinessBoost: 2),
    PetFoodItem(id: 'garlic', nameKey: 'petFoodGarlic', descKey: 'petFoodGarlicDesc', spriteCol: 1, spriteRow: 3, price: 3, satietyRestore: 5, happinessBoost: -5, specialEffect: 'crazy'),
    PetFoodItem(id: 'pepper', nameKey: 'petFoodPepper', descKey: 'petFoodPepperDesc', spriteCol: 2, spriteRow: 3, price: 6, satietyRestore: 3, happinessBoost: -3, specialEffect: 'crazy'),
    PetFoodItem(id: 'mushroom', nameKey: 'petFoodMushroom', descKey: 'petFoodMushroomDesc', spriteCol: 3, spriteRow: 3, price: 7, satietyRestore: 12, happinessBoost: 8),
    // ─── Row 4: 肉类（顶级） ───
    PetFoodItem(id: 'ham', nameKey: 'petFoodHam', descKey: 'petFoodHamDesc', spriteCol: 0, spriteRow: 4, price: 15, satietyRestore: 25, happinessBoost: 10),
    PetFoodItem(id: 'chicken', nameKey: 'petFoodChicken', descKey: 'petFoodChickenDesc', spriteCol: 1, spriteRow: 4, price: 20, satietyRestore: 30, happinessBoost: 15),
    PetFoodItem(id: 'fish', nameKey: 'petFoodFish', descKey: 'petFoodFishDesc', spriteCol: 2, spriteRow: 4, price: 25, satietyRestore: 30, happinessBoost: 25, specialEffect: 'happy_dance'),
    PetFoodItem(id: 'lobster', nameKey: 'petFoodLobster', descKey: 'petFoodLobsterDesc', spriteCol: 3, spriteRow: 4, price: 50, satietyRestore: 40, happinessBoost: 40, specialEffect: 'play'),
  ];

  PetFoodItem? getItem(String id) {
    try {
      return catalog.firstWhere((item) => item.id == id);
    } catch (_) {
      return null;
    }
  }
}

/// 背包中的物品条目
class InventoryEntry {
  final String itemId;
  int quantity;

  InventoryEntry({required this.itemId, this.quantity = 0});

  Map<String, dynamic> toJson() => {'itemId': itemId, 'quantity': quantity};
  factory InventoryEntry.fromJson(Map<String, dynamic> json) => InventoryEntry(
        itemId: json['itemId'] as String,
        quantity: json['quantity'] as int? ?? 0,
      );
}

/// 成就定义
class PetAchievement {
  final String id;
  final String nameKey; // 国际化 key
  final String descKey; // 国际化 key
  final String icon; // emoji
  final bool Function(PetEconomyData data) check;

  const PetAchievement({
    required this.id,
    required this.nameKey,
    required this.descKey,
    required this.icon,
    required this.check,
  });
}

/// 所有成就列表
final List<PetAchievement> allAchievements = [
  PetAchievement(id: 'first_coin', nameKey: 'petAchieveFirstCoin', descKey: 'petAchieveFirstCoinDesc', icon: '\u{1F4B0}', check: (data) => data.totalEarned >= 1),
  PetAchievement(id: 'rich_100', nameKey: 'petAchieveRich100', descKey: 'petAchieveRich100Desc', icon: '\u{1F4B5}', check: (data) => data.totalEarned >= 100),
  PetAchievement(id: 'rich_500', nameKey: 'petAchieveRich500', descKey: 'petAchieveRich500Desc', icon: '\u{1F3E6}', check: (data) => data.totalEarned >= 500),
  PetAchievement(id: 'rich_2000', nameKey: 'petAchieveRich2000', descKey: 'petAchieveRich2000Desc', icon: '\u{1F451}', check: (data) => data.totalEarned >= 2000),
  PetAchievement(id: 'first_feed', nameKey: 'petAchieveFirstFeed', descKey: 'petAchieveFirstFeedDesc', icon: '\u{1F41F}', check: (data) => data.totalFeedCount >= 1),
  PetAchievement(id: 'feed_10', nameKey: 'petAchieveFeed10', descKey: 'petAchieveFeed10Desc', icon: '\u{1F372}', check: (data) => data.totalFeedCount >= 10),
  PetAchievement(id: 'feed_50', nameKey: 'petAchieveFeed50', descKey: 'petAchieveFeed50Desc', icon: '\u{1F3C5}', check: (data) => data.totalFeedCount >= 50),
  PetAchievement(id: 'full_belly', nameKey: 'petAchieveFullBelly', descKey: 'petAchieveFullBellyDesc', icon: '\u{1F60B}', check: (data) => data.satiety >= 100),
  PetAchievement(id: 'happy_max', nameKey: 'petAchieveHappyMax', descKey: 'petAchieveHappyMaxDesc', icon: '\u{1F63A}', check: (data) => data.happiness >= 100),
  PetAchievement(id: 'shopper', nameKey: 'petAchieveShopper', descKey: 'petAchieveShopperDesc', icon: '\u{1F381}', check: (data) => data.totalPurchaseCount >= 20),
  PetAchievement(id: 'chat_1m', nameKey: 'petAchieveChat1m', descKey: 'petAchieveChat1mDesc', icon: '\u{1F4AC}', check: (data) => data.totalTokensSpent >= 1000000),
  PetAchievement(id: 'chat_50m', nameKey: 'petAchieveChat50m', descKey: 'petAchieveChat50mDesc', icon: '\u{1F9E0}', check: (data) => data.totalTokensSpent >= 50000000),
  PetAchievement(id: 'chat_100m', nameKey: 'petAchieveChat100m', descKey: 'petAchieveChat100mDesc', icon: '\u{1F916}', check: (data) => data.totalTokensSpent >= 100000000),
];

/// 经济系统持久化数据
class PetEconomyData {
  int coins;
  int totalEarned;
  int totalTokensSpent;
  int totalFeedCount;
  int totalPurchaseCount;
  int satiety; // 0~100
  int happiness; // 0~100
  DateTime lastDecayTime; // 上次自然衰减时间
  List<InventoryEntry> inventory;
  List<String> unlockedAchievements;

  PetEconomyData({
    this.coins = 0,
    this.totalEarned = 0,
    this.totalTokensSpent = 0,
    this.totalFeedCount = 0,
    this.totalPurchaseCount = 0,
    this.satiety = 50,
    this.happiness = 50,
    DateTime? lastDecayTime,
    List<InventoryEntry>? inventory,
    List<String>? unlockedAchievements,
  })  : lastDecayTime = lastDecayTime ?? DateTime.now(),
        inventory = inventory ?? [],
        unlockedAchievements = unlockedAchievements ?? [];

  Map<String, dynamic> toJson() => {
        'coins': coins,
        'totalEarned': totalEarned,
        'totalTokensSpent': totalTokensSpent,
        'totalFeedCount': totalFeedCount,
        'totalPurchaseCount': totalPurchaseCount,
        'satiety': satiety,
        'happiness': happiness,
        'lastDecayTime': lastDecayTime.toIso8601String(),
        'inventory': inventory.map((e) => e.toJson()).toList(),
        'unlockedAchievements': unlockedAchievements,
      };

  factory PetEconomyData.fromJson(Map<String, dynamic> json) {
    return PetEconomyData(
      coins: json['coins'] as int? ?? 0,
      totalEarned: json['totalEarned'] as int? ?? 0,
      totalTokensSpent: json['totalTokensSpent'] as int? ?? 0,
      totalFeedCount: json['totalFeedCount'] as int? ?? 0,
      totalPurchaseCount: json['totalPurchaseCount'] as int? ?? 0,
      satiety: json['satiety'] as int? ?? 50,
      happiness: json['happiness'] as int? ?? 50,
      lastDecayTime: json['lastDecayTime'] != null
          ? DateTime.tryParse(json['lastDecayTime'] as String) ?? DateTime.now()
          : DateTime.now(),
      inventory: (json['inventory'] as List<dynamic>?)
              ?.map((e) => InventoryEntry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      unlockedAchievements:
          (json['unlockedAchievements'] as List<dynamic>?)
                  ?.cast<String>() ??
              [],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// PetEconomy — 经济系统核心服务
// ═══════════════════════════════════════════════════════════════

/// 宠物经济系统单例
///
/// 管理：宠物币钱包、商店购买、背包、饱腹/心情、成就检测
/// 持久化：所有数据存储在 pet_economy.json 中
class PetEconomy extends ChangeNotifier {
  PetEconomy._();
  static final PetEconomy instance = PetEconomy._();

  PetEconomyData _data = PetEconomyData();
  PetEconomyData get data => _data;

  /// 当前宠物币余额
  int get coins => _data.coins;

  /// 饱腹度
  int get satiety => _data.satiety;

  /// 心情值
  int get happiness => _data.happiness;

  /// 背包
  List<InventoryEntry> get inventory => _data.inventory;

  /// 已解锁成就
  List<String> get unlockedAchievements => _data.unlockedAchievements;

  /// 最近解锁的成就（供 UI 弹出通知）
  PetAchievement? _lastUnlockedAchievement;

  /// 最近一次获得的宠物币数（供 UI 弹出通知后消费）
  int _lastReward = 0;
  int consumeLastReward() {
    final r = _lastReward;
    _lastReward = 0;
    return r;
  }
  PetAchievement? consumeLastAchievement() {
    final a = _lastUnlockedAchievement;
    _lastUnlockedAchievement = null;
    return a;
  }

  /// 每日获取上限
  static const int dailyCoinCap = 100;

  /// 今日已获取的币数
  int _todayEarned = 0;
  DateTime _todayDate = DateTime.now();

  // ─── 初始化 ───

  /// 加载持久化数据 + 应用自然衰减
  Future<void> load() async {
    bool isFirstRun = true;
    try {
      final file = await _configFile();
      if (file.existsSync()) {
        final json =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        _data = PetEconomyData.fromJson(json);
        isFirstRun = false;
      }
    } catch (e) {
      debugPrint('[PetEconomy] 加载失败: $e');
    }

    // 首次运行：赠送每种食物各一个
    if (isFirstRun) {
      for (final item in PetShop.catalog) {
        _data.inventory.add(InventoryEntry(itemId: item.id, quantity: 1));
      }
    }

    // 应用离线期间的自然衰减
    _applyDecay();
    _loadTodayEarned();
    await _save();
  }

  // ─── Token → 宠物币兑换 ───

  /// 对话结束后调用，根据 token 消耗量奖励宠物币
  ///
  /// 兑换规则：
  /// - <500 tokens → 1~2 币
  /// - 500~2000 tokens → 3~5 币
  /// - >2000 tokens → 5~10 币
  Future<int> rewardForTokens(int tokenCount) async {
    if (tokenCount <= 0) return 0;

    _data.totalTokensSpent += tokenCount;

    // 检查每日上限
    _checkDayReset();
    if (_todayEarned >= dailyCoinCap) {
      await _save();
      _checkAchievements();
      return 0;
    }

    int reward;
    if (tokenCount < 500) {
      reward = 2 + (tokenCount ~/ 250); // 2~4
    } else if (tokenCount < 2000) {
      reward = 6 + (tokenCount - 500) ~/ 500; // 6~10
    } else {
      reward = 10 + (tokenCount - 2000) ~/ 1000; // 10~20
      if (reward > 20) reward = 20;
    }

    // 不超过每日上限
    final remaining = dailyCoinCap - _todayEarned;
    reward = reward.clamp(0, remaining);

    _data.coins += reward;
    _data.totalEarned += reward;
    _todayEarned += reward;
    _lastReward = reward;

    await _save();
    _checkAchievements();
    notifyListeners();
    return reward;
  }

  // ─── 商店购买 ───

  /// 购买食物，返回是否成功
  Future<bool> buyItem(String itemId) async {
    final item = PetShop.instance.getItem(itemId);
    if (item == null) return false;
    if (_data.coins < item.price) return false;

    _data.coins -= item.price;
    _data.totalPurchaseCount++;

    // 添加到背包
    final existing = _data.inventory.where((e) => e.itemId == itemId);
    if (existing.isNotEmpty) {
      existing.first.quantity++;
    } else {
      _data.inventory.add(InventoryEntry(itemId: itemId, quantity: 1));
    }

    await _save();
    _checkAchievements();
    notifyListeners();
    return true;
  }

  // ─── 投喂 ───

  /// 使用背包中的食物投喂宠物
  /// 返回投喂的食物（供动画使用），null 表示失败
  Future<PetFoodItem?> feedPet(String itemId) async {
    // 检查背包
    final entry = _data.inventory.where((e) => e.itemId == itemId);
    if (entry.isEmpty || entry.first.quantity <= 0) return null;

    final item = PetShop.instance.getItem(itemId);
    if (item == null) return null;

    // 消耗物品
    entry.first.quantity--;
    if (entry.first.quantity <= 0) {
      _data.inventory.removeWhere((e) => e.itemId == itemId);
    }

    // 恢复数值
    _data.satiety = (_data.satiety + item.satietyRestore).clamp(0, 100);
    _data.happiness = (_data.happiness + item.happinessBoost).clamp(0, 100);
    _data.totalFeedCount++;
    _data.lastDecayTime = DateTime.now();

    await _save();
    _checkAchievements();
    notifyListeners();
    return item;
  }

  /// 获取背包中某物品数量
  int getItemCount(String itemId) {
    final entry = _data.inventory.where((e) => e.itemId == itemId);
    return entry.isEmpty ? 0 : entry.first.quantity;
  }

  // ─── 自然衰减 ───

  /// 饱腹度每小时 -5，心情每小时 -3
  void _applyDecay() {
    final now = DateTime.now();
    final hoursPassed =
        now.difference(_data.lastDecayTime).inMinutes / 60.0;
    if (hoursPassed < 1) return;

    final fullHours = hoursPassed.floor();
    _data.satiety = (_data.satiety - fullHours * 5).clamp(0, 100);
    _data.happiness = (_data.happiness - fullHours * 3).clamp(0, 100);
    _data.lastDecayTime = now;
  }

  // ─── 成就 ───

  void _checkAchievements() {
    for (final achievement in allAchievements) {
      if (_data.unlockedAchievements.contains(achievement.id)) continue;
      if (achievement.check(_data)) {
        _data.unlockedAchievements.add(achievement.id);
        _lastUnlockedAchievement = achievement;
        _save();
        notifyListeners();
        break; // 一次只弹出一个
      }
    }
  }

  // ─── 每日重置 ───

  void _checkDayReset() {
    final today = DateTime.now();
    if (today.day != _todayDate.day ||
        today.month != _todayDate.month ||
        today.year != _todayDate.year) {
      _todayEarned = 0;
      _todayDate = today;
    }
  }

  void _loadTodayEarned() {
    // 简化处理：从持久化数据无法精确恢复今日已获取量
    // 重启后重置为 0（对用户有利）
    _todayEarned = 0;
    _todayDate = DateTime.now();
  }

  // ─── 持久化 ───

  static Future<File> _configFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'pet_economy.json'));
  }

  Future<void> _save() async {
    try {
      final file = await _configFile();
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(_data.toJson()),
      );
    } catch (e) {
      debugPrint('[PetEconomy] 保存失败: $e');
    }
  }
}

