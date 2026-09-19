"""Provider 横评（PRD R-019 / R-020，以及 PRD「风险」里那条建议）。

拿一组标注过的餐食照片，把几个 Provider 各跑一遍，出一张可比的表：
识别率、误报率、份量偏差、JSON 稳定性、重复识别一致性、延迟、token 用量。
**默认 Provider 该选谁，用这张表决定，不靠感觉。**

用法（server/ 目录下）：

    # 先造一份自测数据集，确认脚本本身是通的（不联网、不花钱）
    python scripts/eval_providers.py --make-sample eval/sample
    python scripts/eval_providers.py --dataset eval/sample --provider mock --repeat 3

    # 真正的横评：20~30 张真实中餐照片 + 人工标注
    python scripts/eval_providers.py --dataset eval/zh-meals \\
        --provider openai:gpt-4o-mini \\
        --provider openai:qwen-vl-max@https://dashscope.aliyuncs.com/compatible-mode/v1 \\
        --repeat 3 --out eval/report.md

数据集长这样：

    eval/zh-meals/
      labels.json      [{"photo": "001.jpg", "items": [{"name": "杂粮饭", "grams": 150}]}]
      001.jpg
      ...

标注只需要「有哪些食物 + 各多少克」。营养值不用标：那是缓存表的职责，
识别环节只要名字对得上、份量估得准（R-020 保证同一食物的营养值长期一致）。
"""

from __future__ import annotations

import argparse
import asyncio
import json
import statistics
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path

SERVER_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(SERVER_ROOT))

from app.domain.food_name import normalize  # noqa: E402
from app.services.recognition import (  # noqa: E402
    FoodRecognizer,
    RawItem,
    RecognitionError,
)


# ---------------------------------------------------------------- 数据集


@dataclass(frozen=True)
class LabeledPhoto:
    path: Path
    items: dict[str, int]  # 标准化食物名 -> 克数

    @property
    def name(self) -> str:
        return self.path.name


def load_dataset(directory: Path) -> list[LabeledPhoto]:
    labels_file = directory / "labels.json"
    if not labels_file.exists():
        raise SystemExit(f"找不到标注文件：{labels_file}")

    raw = json.loads(labels_file.read_text(encoding="utf-8"))
    photos: list[LabeledPhoto] = []
    for entry in raw:
        path = directory / entry["photo"]
        if not path.exists():
            raise SystemExit(f"标注里写了 {entry['photo']}，但文件不存在")
        items = {normalize(i["name"]): int(i["grams"]) for i in entry["items"]}
        photos.append(LabeledPhoto(path=path, items=items))
    if not photos:
        raise SystemExit("数据集是空的")
    return photos


# ---------------------------------------------------------------- 一次识别


@dataclass
class RunResult:
    photo: str
    ok: bool
    latency_ms: int
    items: list[RawItem] = field(default_factory=list)
    error: str = ""
    prompt_tokens: int = 0
    completion_tokens: int = 0


async def run_once(
    recognizer: FoodRecognizer, photo: LabeledPhoto, content_type: str
) -> RunResult:
    image = photo.path.read_bytes()
    started = time.perf_counter()
    try:
        result = await recognizer.recognize(image, content_type)
    except RecognitionError as exc:
        return RunResult(
            photo=photo.name,
            ok=False,
            latency_ms=int((time.perf_counter() - started) * 1000),
            error=str(exc),
        )
    except Exception as exc:  # Provider 抛了别的东西，一样算这次失败
        return RunResult(
            photo=photo.name,
            ok=False,
            latency_ms=int((time.perf_counter() - started) * 1000),
            error=f"{type(exc).__name__}: {exc}",
        )

    return RunResult(
        photo=photo.name,
        ok=True,
        latency_ms=int((time.perf_counter() - started) * 1000),
        items=list(result.items),
        prompt_tokens=result.prompt_tokens,
        completion_tokens=result.completion_tokens,
    )


# ---------------------------------------------------------------- 打分


@dataclass
class Scorecard:
    provider: str
    runs: int = 0
    failures: int = 0
    labeled_total: int = 0
    matched_total: int = 0
    predicted_total: int = 0
    gram_errors: list[float] = field(default_factory=list)
    latencies: list[int] = field(default_factory=list)
    prompt_tokens: int = 0
    completion_tokens: int = 0
    # 同一张图多次识别，标准化名字集合的重合度（R-020 想要的稳定性）。
    consistency: list[float] = field(default_factory=list)
    misses: dict[str, int] = field(default_factory=dict)
    false_positives: dict[str, int] = field(default_factory=dict)

    @property
    def recall(self) -> float:
        return self.matched_total / self.labeled_total if self.labeled_total else 0.0

    @property
    def precision(self) -> float:
        return self.matched_total / self.predicted_total if self.predicted_total else 0.0

    @property
    def gram_mape(self) -> float:
        return statistics.mean(self.gram_errors) if self.gram_errors else 0.0

    @property
    def json_ok_rate(self) -> float:
        return (self.runs - self.failures) / self.runs if self.runs else 0.0

    @property
    def mean_consistency(self) -> float:
        return statistics.mean(self.consistency) if self.consistency else 1.0

    def latency(self, percentile: float) -> int:
        if not self.latencies:
            return 0
        ordered = sorted(self.latencies)
        index = min(len(ordered) - 1, int(len(ordered) * percentile))
        return ordered[index]


def score(
    provider: str,
    photos: list[LabeledPhoto],
    results: dict[str, list[RunResult]],
) -> Scorecard:
    card = Scorecard(provider=provider)

    for photo in photos:
        runs = results[photo.name]
        name_sets: list[set[str]] = []

        for run in runs:
            card.runs += 1
            card.latencies.append(run.latency_ms)
            card.prompt_tokens += run.prompt_tokens
            card.completion_tokens += run.completion_tokens
            if not run.ok:
                card.failures += 1
                continue

            predicted = {normalize(item.name): item for item in run.items}
            name_sets.append(set(predicted))

            card.labeled_total += len(photo.items)
            card.predicted_total += len(predicted)

            for label, grams in photo.items.items():
                item = predicted.get(label)
                if item is None:
                    card.misses[label] = card.misses.get(label, 0) + 1
                    continue
                card.matched_total += 1
                if grams > 0:
                    card.gram_errors.append(abs(item.estimated_grams - grams) / grams)

            for name in predicted.keys() - photo.items.keys():
                card.false_positives[name] = card.false_positives.get(name, 0) + 1

        # 多跑几次才谈得上一致性。
        if len(name_sets) > 1:
            base = name_sets[0]
            for other in name_sets[1:]:
                union = base | other
                card.consistency.append(len(base & other) / len(union) if union else 1.0)

    return card


# ---------------------------------------------------------------- 报告


def top(counter: dict[str, int], limit: int = 5) -> str:
    if not counter:
        return "—"
    ordered = sorted(counter.items(), key=lambda kv: -kv[1])[:limit]
    return "、".join(f"{name}×{count}" for name, count in ordered)


def render(cards: list[Scorecard], photos: int, repeat: int) -> str:
    lines = [
        "# Provider 横评",
        "",
        f"数据集 {photos} 张照片，每张跑 {repeat} 次。",
        "",
        "| Provider | 识别率 | 准确率 | 份量平均偏差 | 返回可用率 | 重复一致性 | 延迟 P50 | 延迟 P95 | tokens/次 |",
        "|---|---|---|---|---|---|---|---|---|",
    ]
    for card in cards:
        tokens = (
            (card.prompt_tokens + card.completion_tokens) / card.runs
            if card.runs
            else 0
        )
        lines.append(
            f"| {card.provider} "
            f"| {card.recall:.1%} "
            f"| {card.precision:.1%} "
            f"| {card.gram_mape:.1%} "
            f"| {card.json_ok_rate:.1%} "
            f"| {card.mean_consistency:.1%} "
            f"| {card.latency(0.5)} ms "
            f"| {card.latency(0.95)} ms "
            f"| {tokens:.0f} |"
        )

    lines += ["", "## 漏识别与误识别", ""]
    for card in cards:
        lines += [
            f"**{card.provider}**",
            "",
            f"- 最常漏掉：{top(card.misses)}",
            f"- 最常多认：{top(card.false_positives)}",
            f"- 调用失败：{card.failures} / {card.runs}",
            "",
        ]

    lines += [
        "## 怎么读这张表",
        "",
        "- **识别率**：标注里的食物有多少被认出来（按标准化食物名比对）。漏认要用户自己补，最伤体验。",
        "- **准确率**：认出来的东西有多少是真在盘子里的。多认一样要用户手动删。",
        "- **份量平均偏差**：认对的那些，克数估得离谱不离谱。PRD 允许用户改份量，但偏差太大就没有省事的意义。",
        "- **返回可用率**：JSON 解析 + 字段校验都过得去的比例。这一项低于 95% 基本不能用（R-019）。",
        "- **重复一致性**：同一张图跑多次，认出来的食物集合有多稳。不稳的话缓存表会被各种别名撑爆（R-020）。",
        "",
    ]
    return "\n".join(lines)


# ---------------------------------------------------------------- Provider


def build_recognizer(spec: str) -> tuple[str, FoodRecognizer]:
    """`mock` / `openai:模型名` / `openai:模型名@base_url`。"""
    kind, _, rest = spec.partition(":")
    model, _, base_url = rest.partition("@")

    if kind == "mock":
        from app.services.recognition.mock import MockRecognizer

        return "mock", MockRecognizer()

    if kind in {"openai", "openai_compatible"}:
        from app.services.recognition.openai_provider import OpenAIRecognizer

        recognizer = OpenAIRecognizer(
            model=model or None,
            base_url=base_url or None,
        )
        return f"openai:{model or 'default'}", recognizer

    raise SystemExit(f"不认识的 Provider：{spec}")


CONTENT_TYPES = {
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".png": "image/png",
    ".webp": "image/webp",
}


async def evaluate(
    spec: str, photos: list[LabeledPhoto], repeat: int
) -> tuple[Scorecard, dict[str, list[RunResult]]]:
    label, recognizer = build_recognizer(spec)
    results: dict[str, list[RunResult]] = {}

    for photo in photos:
        content_type = CONTENT_TYPES.get(photo.path.suffix.lower(), "image/jpeg")
        runs = []
        for _ in range(repeat):
            runs.append(await run_once(recognizer, photo, content_type))
        results[photo.name] = runs
        ok = sum(1 for r in runs if r.ok)
        print(f"  {label} {photo.name}: {ok}/{repeat} 次成功", flush=True)

    return score(label, photos, results), results


# ---------------------------------------------------------------- 自测数据集


def make_sample(directory: Path) -> None:
    """造一份跑得通的假数据集：只为验证脚本本身，不是真实评测。

    mock Provider 按图片字节的 sha256 选一组固定结果，所以这里反过来
    用它的输出当标注 —— 跑出来必然 100%，看的是「脚本能不能跑完并出表」。
    """
    from app.services.recognition.mock import _PLATES  # noqa: PLC0415
    import hashlib

    directory.mkdir(parents=True, exist_ok=True)
    labels = []
    for index in range(len(_PLATES)):
        # 找一段字节，让 mock 正好命中第 index 组。
        seed = 0
        while True:
            payload = f"fitmeal-sample-{index}-{seed}".encode()
            if int(hashlib.sha256(payload).hexdigest(), 16) % len(_PLATES) == index:
                break
            seed += 1

        name = f"{index + 1:03d}.jpg"
        (directory / name).write_bytes(payload)
        labels.append(
            {
                "photo": name,
                "items": [
                    {"name": item.name, "grams": item.estimated_grams}
                    for item in _PLATES[index]
                ],
            }
        )

    (directory / "labels.json").write_text(
        json.dumps(labels, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(f"自测数据集已写到 {directory}（{len(labels)} 张）")


# ---------------------------------------------------------------- 入口


async def main_async(args: argparse.Namespace) -> int:
    photos = load_dataset(Path(args.dataset))
    print(f"数据集 {len(photos)} 张，每张跑 {args.repeat} 次")

    cards = []
    details = {}
    for spec in args.provider:
        card, results = await evaluate(spec, photos, args.repeat)
        cards.append(card)
        details[card.provider] = {
            photo: [
                {
                    "ok": run.ok,
                    "latency_ms": run.latency_ms,
                    "error": run.error,
                    "items": [
                        {"name": i.name, "grams": i.estimated_grams} for i in run.items
                    ],
                }
                for run in runs
            ]
            for photo, runs in results.items()
        }

    report = render(cards, len(photos), args.repeat)
    print()
    print(report)

    if args.out:
        out = Path(args.out)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(report, encoding="utf-8")
        detail_path = out.with_suffix(".json")
        detail_path.write_text(
            json.dumps(details, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        print(f"报告：{out}\n明细：{detail_path}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="识别 Provider 横评")
    parser.add_argument("--dataset", help="数据集目录（含 labels.json）")
    parser.add_argument(
        "--provider",
        action="append",
        default=[],
        help="可重复：mock / openai:模型名 / openai:模型名@base_url",
    )
    parser.add_argument("--repeat", type=int, default=3, help="每张图跑几次")
    parser.add_argument("--out", help="报告输出路径（.md）")
    parser.add_argument("--make-sample", help="造一份自测数据集到该目录后退出")
    args = parser.parse_args()

    if args.make_sample:
        make_sample(Path(args.make_sample))
        return 0
    if not args.dataset or not args.provider:
        parser.error("需要 --dataset 和至少一个 --provider")
    return asyncio.run(main_async(args))


if __name__ == "__main__":
    raise SystemExit(main())
