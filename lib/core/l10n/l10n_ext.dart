import 'package:flutter/widgets.dart';
import '../../l10n/app_localizations.dart';

/// 便捷扩展 — 通过 context.s 获取国际化字符串
///
/// 用法: `context.s.settingsTitle` 代替 `S.of(context).settingsTitle`
extension LocalizationExt on BuildContext {
  S get s => S.of(this);
}

/// 通过 key 动态查找宠物相关国际化文本
///
/// 用于 PetFoodItem.nameKey / PetAchievement.nameKey 等动态 key 的解析
String petL10n(S s, String key) {
  return _petL10nMap(s)[key] ?? key;
}

Map<String, String> _petL10nMap(S s) => {
  // 食物名称
  'petFoodBanana': s.petFoodBanana,
  'petFoodBananaDesc': s.petFoodBananaDesc,
  'petFoodApple': s.petFoodApple,
  'petFoodAppleDesc': s.petFoodAppleDesc,
  'petFoodPurpleGrape': s.petFoodPurpleGrape,
  'petFoodPurpleGrapeDesc': s.petFoodPurpleGrapeDesc,
  'petFoodGreenGrape': s.petFoodGreenGrape,
  'petFoodGreenGrapeDesc': s.petFoodGreenGrapeDesc,
  'petFoodPineapple': s.petFoodPineapple,
  'petFoodPineappleDesc': s.petFoodPineappleDesc,
  'petFoodKiwi': s.petFoodKiwi,
  'petFoodKiwiDesc': s.petFoodKiwiDesc,
  'petFoodCherry': s.petFoodCherry,
  'petFoodCherryDesc': s.petFoodCherryDesc,
  'petFoodStrawberry': s.petFoodStrawberry,
  'petFoodStrawberryDesc': s.petFoodStrawberryDesc,
  'petFoodCarrot': s.petFoodCarrot,
  'petFoodCarrotDesc': s.petFoodCarrotDesc,
  'petFoodTomato': s.petFoodTomato,
  'petFoodTomatoDesc': s.petFoodTomatoDesc,
  'petFoodEggplant': s.petFoodEggplant,
  'petFoodEggplantDesc': s.petFoodEggplantDesc,
  'petFoodPumpkin': s.petFoodPumpkin,
  'petFoodPumpkinDesc': s.petFoodPumpkinDesc,
  'petFoodBroccoli': s.petFoodBroccoli,
  'petFoodBroccoliDesc': s.petFoodBroccoliDesc,
  'petFoodGarlic': s.petFoodGarlic,
  'petFoodGarlicDesc': s.petFoodGarlicDesc,
  'petFoodPepper': s.petFoodPepper,
  'petFoodPepperDesc': s.petFoodPepperDesc,
  'petFoodMushroom': s.petFoodMushroom,
  'petFoodMushroomDesc': s.petFoodMushroomDesc,
  'petFoodHam': s.petFoodHam,
  'petFoodHamDesc': s.petFoodHamDesc,
  'petFoodChicken': s.petFoodChicken,
  'petFoodChickenDesc': s.petFoodChickenDesc,
  'petFoodFish': s.petFoodFish,
  'petFoodFishDesc': s.petFoodFishDesc,
  'petFoodLobster': s.petFoodLobster,
  'petFoodLobsterDesc': s.petFoodLobsterDesc,
  // 成就
  'petAchieveFirstCoin': s.petAchieveFirstCoin,
  'petAchieveFirstCoinDesc': s.petAchieveFirstCoinDesc,
  'petAchieveRich100': s.petAchieveRich100,
  'petAchieveRich100Desc': s.petAchieveRich100Desc,
  'petAchieveRich500': s.petAchieveRich500,
  'petAchieveRich500Desc': s.petAchieveRich500Desc,
  'petAchieveRich2000': s.petAchieveRich2000,
  'petAchieveRich2000Desc': s.petAchieveRich2000Desc,
  'petAchieveFirstFeed': s.petAchieveFirstFeed,
  'petAchieveFirstFeedDesc': s.petAchieveFirstFeedDesc,
  'petAchieveFeed10': s.petAchieveFeed10,
  'petAchieveFeed10Desc': s.petAchieveFeed10Desc,
  'petAchieveFeed50': s.petAchieveFeed50,
  'petAchieveFeed50Desc': s.petAchieveFeed50Desc,
  'petAchieveFullBelly': s.petAchieveFullBelly,
  'petAchieveFullBellyDesc': s.petAchieveFullBellyDesc,
  'petAchieveHappyMax': s.petAchieveHappyMax,
  'petAchieveHappyMaxDesc': s.petAchieveHappyMaxDesc,
  'petAchieveShopper': s.petAchieveShopper,
  'petAchieveShopperDesc': s.petAchieveShopperDesc,
  'petAchieveChat1m': s.petAchieveChat1m,
  'petAchieveChat1mDesc': s.petAchieveChat1mDesc,
  'petAchieveChat50m': s.petAchieveChat50m,
  'petAchieveChat50mDesc': s.petAchieveChat50mDesc,
  'petAchieveChat100m': s.petAchieveChat100m,
  'petAchieveChat100mDesc': s.petAchieveChat100mDesc,
};
