"""食物名标准化。

PRD 把这条策略点名为交付风险：归一过头会把不同的东西并成一条，
归一不足则缓存命中率上不去。下面两组用例就是这条边界。
"""

from __future__ import annotations

import pytest

from app.domain.food_name import clean_display_name, normalize


@pytest.mark.parametrize(
    "written",
    ["米饭", "白米饭", "大米饭", " 白饭 ", "一份米饭", "米饭（熟）", "２份米饭"],
)
def test_same_food_maps_to_one_key(written: str):
    assert normalize(written) == "米饭"


@pytest.mark.parametrize(
    "a, b",
    [
        ("清蒸鱼", "红烧鱼"),  # 做法不同，热量差一截
        ("鸡胸肉", "鸡腿肉"),  # 部位不同
        ("全麦面包", "面包"),  # 原料不同
        ("原味酸奶", "希腊式酸奶"),
    ],
)
def test_different_foods_never_merge(a: str, b: str):
    assert normalize(a) != normalize(b)


def test_bracket_annotations_are_dropped_unless_they_change_nutrition():
    # 「（熟）」只是注释，米饭本来就是熟的。
    assert normalize("米饭（熟）") == "米饭"
    # 「（脱脂）」改变营养值，必须留下来，跟全脂牛奶分开。
    assert normalize("牛奶（脱脂）") != normalize("牛奶")
    assert normalize("花生（生）") != normalize("花生")


def test_aliases_cover_english_and_variants():
    assert normalize("Chicken Breast") == normalize("鸡胸") == "鸡胸肉"
    assert normalize("西蓝花") == normalize("broccoli") == "西兰花"
    assert normalize("水煮蛋") == normalize("煮鸡蛋") == "白煮蛋"


def test_suffix_aliases_merge_cooking_prefixes():
    """「香煎鸡胸」和「香煎鸡胸肉」是同一道菜，不该在缓存里各占一条（N-16）。"""
    assert normalize("香煎鸡胸") == normalize("香煎鸡胸肉")
    assert normalize("蒜蓉西蓝花") == normalize("蒜蓉西兰花")
    # 但做法不同仍然分开。
    assert normalize("水煮鸡胸") != normalize("香煎鸡胸")


def test_display_name_keeps_readable_form():
    assert clean_display_name("  蒜蓉西兰花 ") == "蒜蓉西兰花"
    assert normalize("") == ""
