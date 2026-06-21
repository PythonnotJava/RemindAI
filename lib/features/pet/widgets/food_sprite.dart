import 'package:flutter/material.dart';

import '../../../core/pet/pet_economy.dart';

/// 从精灵图中裁切单个食物图标的 Widget
///
/// MeatSmall.png 是 128x160 的 4x5 精灵图，每格 32x32
class FoodSprite extends StatelessWidget {
  final PetFoodItem item;
  final double size;

  const FoodSprite({super.key, required this.item, this.size = 32});

  @override
  Widget build(BuildContext context) {
    final cellSize = PetFoodItem.cellSize;
    final scale = size / cellSize;

    return SizedBox(
      width: size,
      height: size,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          maxWidth: double.infinity,
          maxHeight: double.infinity,
          child: Transform.translate(
            offset: Offset(
              -item.spriteCol * cellSize * scale,
              -item.spriteRow * cellSize * scale,
            ),
            child: Image.asset(
              item.assetPath,
              width: PetFoodItem.sheetCols * cellSize * scale,
              height: PetFoodItem.sheetRows * cellSize * scale,
              filterQuality: FilterQuality.none, // 像素风保持锐利
              fit: BoxFit.fill,
            ),
          ),
        ),
      ),
    );
  }
}
