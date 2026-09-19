"""本地假识别。

用途有两个：没有 Provider Key 时也能把整条链路跑通（开发、联调、CI），
以及给测试一个稳定的返回。它返回的营养值故意与缓存里的种子值不同，
这样「缓存命中就该用缓存值」这条规则在测试里是可观测的（PRD R-020）。
"""

from __future__ import annotations

import asyncio
import hashlib

from . import RawItem, RecognitionResult

_PLATES: list[list[RawItem]] = [
    [
        RawItem("杂粮饭", 150, 152.0, 3.4, 32.0, 0.6),
        RawItem("香煎鸡胸", 120, 165.0, 31.0, 0.0, 3.6),
        RawItem("蒜蓉西兰花", 180, 41.0, 2.8, 5.2, 1.4, portion_uncertain=True),
    ],
    [
        RawItem("糙米饭", 180, 148.0, 3.0, 31.0, 1.0),
        RawItem("清蒸鱼", 150, 110.0, 20.5, 0.0, 3.0, portion_uncertain=True),
        RawItem("蒜蓉西兰花", 160, 41.0, 2.8, 5.2, 1.4),
    ],
    [
        RawItem("全麦面包", 70, 247.0, 9.0, 41.0, 4.2),
        RawItem("白煮蛋", 105, 143.0, 12.6, 1.1, 9.5),
        RawItem("希腊式酸奶", 140, 59.0, 10.0, 3.6, 0.4, portion_uncertain=True),
    ],
]


class MockRecognizer:
    name = "mock"

    async def recognize(self, image: bytes, content_type: str) -> RecognitionResult:
        # 真机上这段时间花在上传和模型推理上（PRD N-2 P95 ≤ 8 秒）。
        await asyncio.sleep(0.01)
        # 同一张图永远给同一组结果，方便复现问题。
        index = int(hashlib.sha256(image).hexdigest(), 16) % len(_PLATES)
        return RecognitionResult(items=list(_PLATES[index]), model="mock-plate-v1")
