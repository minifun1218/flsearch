"""横评脚本本身的测试。

真实横评要有真实照片和人工标注，跑不进 CI；能在 CI 里守住的是**算分对不对**——
识别率、准确率、份量偏差、失败率这几个数字是选默认 Provider 的依据，
算错了比没有更糟。
"""

from __future__ import annotations

import asyncio
import json
import sys
from pathlib import Path

import pytest

SERVER_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(SERVER_ROOT))
sys.path.insert(0, str(SERVER_ROOT / "scripts"))

import eval_providers as harness  # noqa: E402
from eval_providers import RunResult  # noqa: E402

from app.services.recognition import (  # noqa: E402
    RawItem,
    RecognitionError,
    RecognitionResult,
)


@pytest.fixture
def sample(tmp_path: Path) -> Path:
    harness.make_sample(tmp_path / "ds")
    return tmp_path / "ds"


def test_sample_dataset_is_loadable(sample: Path):
    photos = harness.load_dataset(sample)
    assert len(photos) == 3
    assert all(photo.items for photo in photos)


def test_mock_scores_perfectly_on_its_own_output(sample: Path):
    photos = harness.load_dataset(sample)
    card, _ = asyncio.run(harness.evaluate("mock", photos, repeat=2))

    assert card.recall == 1.0
    assert card.precision == 1.0
    assert card.gram_mape == 0.0
    assert card.json_ok_rate == 1.0
    # 同一张图两次结果一样 —— mock 本来就该是确定性的。
    assert card.mean_consistency == 1.0
    assert card.failures == 0


def test_wrong_labels_show_up_as_misses_and_gram_error(sample: Path):
    labels_file = sample / "labels.json"
    labels = json.loads(labels_file.read_text(encoding="utf-8"))
    # 第一张：把一样食物换成盘子里没有的，另一样的克数标成两倍。
    labels[0]["items"][0]["name"] = "红烧肉"
    labels[0]["items"][1]["grams"] *= 2
    labels_file.write_text(json.dumps(labels, ensure_ascii=False), encoding="utf-8")

    photos = harness.load_dataset(sample)
    card, _ = asyncio.run(harness.evaluate("mock", photos, repeat=1))

    assert card.recall < 1.0
    assert card.precision < 1.0
    assert "红烧肉" in card.misses
    # 标成两倍 → 偏差 50%，摊到全部匹配项上应该是个正数。
    assert card.gram_mape > 0


def test_provider_failures_land_in_the_availability_column(sample: Path, monkeypatch):
    class Flaky:
        name = "flaky"

        def __init__(self) -> None:
            self.calls = 0

        async def recognize(self, image: bytes, content_type: str):
            self.calls += 1
            if self.calls % 2 == 0:
                raise RecognitionError("识别结果不是合法 JSON")
            return RecognitionResult(items=[RawItem("杂粮饭", 150, 152.0, 3.4, 32.0, 0.6)])

    monkeypatch.setattr(
        harness, "build_recognizer", lambda spec: ("flaky", Flaky())
    )

    photos = harness.load_dataset(sample)
    card, _ = asyncio.run(harness.evaluate("flaky", photos, repeat=2))

    assert card.failures == 3  # 6 次里一半失败
    assert card.json_ok_rate == pytest.approx(0.5)


def test_unstable_names_lower_consistency(sample: Path, monkeypatch):
    class Wobbly:
        name = "wobbly"

        def __init__(self) -> None:
            self.calls = 0

        async def recognize(self, image: bytes, content_type: str):
            self.calls += 1
            # 同一张图，两次给不同的名字 —— 缓存表最怕的就是这个（R-020）。
            name = "杂粮饭" if self.calls % 2 else "五谷饭"
            return RecognitionResult(items=[RawItem(name, 150, 152.0, 3.4, 32.0, 0.6)])

    monkeypatch.setattr(
        harness, "build_recognizer", lambda spec: ("wobbly", Wobbly())
    )

    photos = harness.load_dataset(sample)
    card, _ = asyncio.run(harness.evaluate("wobbly", photos, repeat=2))

    assert card.mean_consistency < 1.0


def test_report_renders_every_provider(sample: Path):
    photos = harness.load_dataset(sample)
    card, _ = asyncio.run(harness.evaluate("mock", photos, repeat=1))
    report = harness.render([card], photos=len(photos), repeat=1)

    assert "| mock |" in report
    assert "识别率" in report
    assert "返回可用率" in report


def test_unknown_provider_is_rejected():
    with pytest.raises(SystemExit):
        harness.build_recognizer("nope:whatever")


def test_missing_dataset_is_rejected(tmp_path: Path):
    with pytest.raises(SystemExit):
        harness.load_dataset(tmp_path / "does-not-exist")


def test_run_result_defaults_are_sane():
    result = RunResult(photo="a.jpg", ok=False, latency_ms=12, error="boom")
    assert result.items == []
    assert result.prompt_tokens == 0
