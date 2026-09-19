"""食物名标准化。

缓存表是「同一食物营养值长期一致」的唯一保障（PRD R-020），而它的键就是这里
产出的标准名。归一过头会把不同的东西并成一条（清蒸鱼 ≠ 红烧鱼），归一不足则
命中率上不去（N-16 目标 ≥ 50%）。所以策略是保守的：

1. 只去掉**不影响营养**的修饰：份量词（一份/大份）、新鲜度词（新鲜）、空白与标点。
2. **保留做法与部位**：清蒸 / 红烧 / 油炸 / 去皮 —— 它们直接改变每 100g 的热量。
3. 括号里的内容默认当注释丢掉（「米饭（熟）」就是米饭），除非里面有会改变营养的
   限定词（脱脂 / 带皮 / 生…），那就并进名字里当成另一种食物。
4. 别名走显式白名单（ALIASES），宁可漏合并，也不错合并。

新别名只能往 ALIASES 里加，不要在调用方随手改名字。
"""

from __future__ import annotations

import re
import unicodedata

#: 显式别名表：左边归一到右边。只收「确定是同一种东西」的写法。
ALIASES: dict[str, str] = {
    "白米饭": "米饭",
    "大米饭": "米饭",
    "米飯": "米饭",
    "白饭": "米饭",
    "鸡胸": "鸡胸肉",
    "鸡胸脯": "鸡胸肉",
    "鸡胸脯肉": "鸡胸肉",
    "鸡蛋白": "蛋清",
    "鸡蛋清": "蛋清",
    "鸡蛋黄": "蛋黄",
    "水煮蛋": "白煮蛋",
    "煮鸡蛋": "白煮蛋",
    "全麦吐司": "全麦面包",
    "全麦土司": "全麦面包",
    "西蓝花": "西兰花",
    "花椰菜": "西兰花",
    "牛油果": "鳄梨",
    "酸奶": "原味酸奶",
    "希腊酸奶": "希腊式酸奶",
    "蛋白粉": "乳清蛋白粉",
    "chicken breast": "鸡胸肉",
    "white rice": "米饭",
    "broccoli": "西兰花",
}

#: 后缀别名：整名相同的写法差异靠 ALIASES，带做法前缀的（香煎鸡胸 / 手撕鸡胸）靠这张表。
#: 只收「换个后缀仍是同一种食材」的情况，别放会改变营养的词。
SUFFIX_ALIASES: dict[str, str] = {
    "鸡胸": "鸡胸肉",
    "西蓝花": "西兰花",
    "土司": "吐司",
}

#: 份量 / 无营养含义的修饰词，可安全去掉。
_NOISE_WORDS = (
    "一份",
    "两份",
    "半份",
    "小份",
    "中份",
    "大份",
    "一碗",
    "一杯",
    "一块",
    "一个",
    "少量",
    "适量",
    "新鲜",
    "美味",
    "自制",
)

#: 括号里带这些词就不是注释，是另一种东西，必须保留。
_BRACKET_KEEPERS = (
    "生",
    "半生",
    "带皮",
    "去皮",
    "带骨",
    "去骨",
    "油炸",
    "油浸",
    "加糖",
    "无糖",
    "全脂",
    "脱脂",
    "低脂",
)

_BRACKET = re.compile(r"[（(【\[]([^）)】\]]*)[）)】\]]")
_PUNCT = re.compile(r"[\s　·•・,，.。;；:：!！?？\"'“”‘’()（）\[\]【】{}<>《》/\\|~～\-—_+*#@&]+")
_LEADING_QUANTITY = re.compile(r"^\d+(\.\d+)?\s*(份|个|碗|杯|块|片|只|根|颗|g|克|ml|毫升)")


def clean_display_name(raw: str) -> str:
    """给人看的名字：只做最轻的清理，保留原本的写法。"""
    name = unicodedata.normalize("NFKC", raw or "").strip()
    name = re.sub(r"\s+", " ", name)
    return name[:64]


def _resolve_bracket(match: re.Match[str]) -> str:
    inner = match.group(1)
    return inner if any(word in inner for word in _BRACKET_KEEPERS) else ""


def _squash(raw: str) -> str:
    """去噪但不查别名 —— 别名表的键值也要走同一道工序才能对上。"""
    name = unicodedata.normalize("NFKC", raw or "").strip().lower()
    name = _LEADING_QUANTITY.sub("", name)
    name = _BRACKET.sub(_resolve_bracket, name)
    for word in _NOISE_WORDS:
        name = name.replace(word, "")
    # 标点和空白只做分隔用，统一抹掉（中文之间不需要空格，英文短语靠别名表兜）。
    return _PUNCT.sub("", name)


#: 归一后的别名索引，键值两侧都过一遍 _squash，避免 "chicken breast" 这类带空格的键漏掉。
_ALIAS_INDEX: dict[str, str] = {_squash(k): _squash(v) for k, v in ALIASES.items()}


def normalize(raw: str) -> str:
    """缓存键：同一种食物的不同写法必须落到同一个字符串上。"""
    name = _squash(raw)
    if not name:
        return ""
    # 别名在去噪之后查，"新鲜西蓝花" 也能归到 "西兰花"。
    name = _ALIAS_INDEX.get(name, name)
    for suffix, replacement in SUFFIX_ALIASES.items():
        if name.endswith(suffix) and name != suffix:
            name = name[: -len(suffix)] + replacement
            break
    return name


def normalize_query(raw: str) -> str:
    """搜索用的归一：与 normalize 同口径，方便按前缀 / 包含匹配缓存表。"""
    return normalize(raw)
