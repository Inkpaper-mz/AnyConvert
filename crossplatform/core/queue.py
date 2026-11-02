"""并发转换队列：校验 → 入队 → 最多 3 个并发执行 → 进度/取消。

- 校验发生在入队前（UI 拖拽与队列 add 共用 matrix.validate）。
- 用 ThreadPoolExecutor(max_workers=N) 限制并发，默认 3。
- 任何异常都落到 job.error，不会让主线程崩溃。
"""

from __future__ import annotations

import threading
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from typing import Callable, Iterable

from . import engines
from .matrix import MATRIX, ValidationResult

DEFAULT_MAX_WORKERS = 3


@dataclass
class Job:
    id: str
    src: str
    target: str
    status: str = "queued"          # queued / running / done / failed / cancelled
    progress: float = 0.0
    output: str = ""
    error: str = ""
    engine: str = ""
    target_bytes: int = 0
    codec: str = "h264"
    options: dict = field(default_factory=dict)
    started_at: float = 0.0
    ended_at: float = 0.0
    cancel: threading.Event = field(default_factory=threading.Event, repr=False)

    @property
    def elapsed(self) -> float:
        if not self.started_at:
            return 0.0
        end = self.ended_at or time.time()
        return max(0.0, end - self.started_at)

    def to_dict(self) -> dict:
        return {
            "id": self.id, "src": self.src, "target": self.target,
            "status": self.status, "progress": round(self.progress, 4),
            "output": self.output, "error": self.error, "engine": self.engine,
            "elapsed": round(self.elapsed, 1),
        }


class ConversionQueue:
    def __init__(self, max_workers: int = DEFAULT_MAX_WORKERS,
                 on_change: Callable[[], None] | None = None):
        self.max_workers = max(1, int(max_workers))
        self.on_change = on_change
        self.jobs: list[Job] = []
        self._lock = threading.Lock()
        self._executor: ThreadPoolExecutor | None = None
        self._active = 0
        self.peak_concurrency = 0
        self._executor_workers = 0

    # ---- 入队（含校验）---------------------------------------
    def add(self, paths: Iterable[str], target: str,
            target_bytes: int | None = None,
            codec: str | None = None,
            options: dict | None = None) -> tuple[list[Job], list[ValidationResult]]:
        accepted: list[Job] = []
        rejected: list[ValidationResult] = []
        size_limit = int(target_bytes or 0)
        with self._lock:
            if size_limit > 0 and MATRIX.category(target) not in ("image", "video"):
                rejected.append(ValidationResult(
                    False, target, "", "目标体积压缩仅支持图片或视频格式，请切换目标格式。"))
                return accepted, rejected
            for path in paths:
                result = MATRIX.validate(target, path)
                if not result.ok:
                    rejected.append(result)
                    continue
                job = Job(id=uuid.uuid4().hex[:10], src=path, target=result.target,
                          engine=MATRIX.choose_engine(result.target, path),
                          target_bytes=size_limit,
                          codec=codec or "h264",
                          options=dict(options or {}))
                self.jobs.append(job)
                accepted.append(job)
        self._notify()
        return accepted, rejected

    def set_max_workers(self, value: int) -> None:
        """允许用户自定义并发数（1–8）。空闲时立即生效，运行中在下一批生效。"""
        value = max(1, min(8, int(value)))
        if value == self.max_workers:
            return
        self.max_workers = value
        with self._lock:
            idle = self._active == 0 and not any(j.status in ("queued", "running") for j in self.jobs)
        if idle and self._executor is not None:
            self._executor.shutdown(wait=False)
            self._executor = None
            self._executor_workers = 0
        self._notify()

    def start(self) -> int:
        with self._lock:
            pending = [j for j in self.jobs if j.status == "queued"]
        if not pending:
            return 0
        if self._executor is None or self._executor_workers != self.max_workers:
            if self._executor is not None:
                self._executor.shutdown(wait=False)
            self._executor = ThreadPoolExecutor(max_workers=self.max_workers,
                                                thread_name_prefix="anyconvert")
            self._executor_workers = self.max_workers
        for job in pending:
            self._executor.submit(self._run_job, job)
        return len(pending)

    def cancel(self) -> None:
        with self._lock:
            for job in self.jobs:
                if job.status in ("queued", "running"):
                    job.cancel.set()
                    if job.status == "queued":
                        job.status = "cancelled"
        self._notify()
        if self._executor:
            self._executor.shutdown(wait=False, cancel_futures=True)

    def clear_finished(self) -> None:
        with self._lock:
            self.jobs = [j for j in self.jobs if j.status not in ("done", "failed", "cancelled")]
        self._notify()

    def snapshot(self, target: str | None = None) -> list[dict]:
        with self._lock:
            jobs = [j for j in self.jobs if target is None or j.target == target]
            return [j.to_dict() for j in jobs]

    def stats(self) -> dict:
        with self._lock:
            return {
                "total": len(self.jobs),
                "done": sum(1 for j in self.jobs if j.status == "done"),
                "failed": sum(1 for j in self.jobs if j.status == "failed"),
                "running": sum(1 for j in self.jobs if j.status == "running"),
                "queued": sum(1 for j in self.jobs if j.status == "queued"),
                "peak_concurrency": self.peak_concurrency,
            }

    # ---- 执行 ------------------------------------------------
    def _run_job(self, job: Job) -> None:
        if job.cancel.is_set():
            job.status = "cancelled"
            self._notify()
            return
        with self._lock:
            job.status = "running"
            job.started_at = time.time()
            self._active += 1
            self.peak_concurrency = max(self.peak_concurrency, self._active)
        self._notify()

        def progress(value: float) -> None:
            job.progress = max(0.0, min(value, 1.0))
            self._notify()

        try:
            out_dir = getattr(self, "output_dir", None) or self._default_out_dir(job.src)
            job.output = engines.convert(job.src, job.target, out_dir,
                                         progress=progress, cancel=job.cancel,
                                         target_bytes=job.target_bytes or None,
                                         codec=job.codec,
                                         options=job.options)
            job.status = "done"
            job.progress = 1.0
        except engines.EngineError as exc:
            job.status = "cancelled" if exc.code == "E_CANCELLED" else "failed"
            job.error = str(exc)
        except Exception as exc:  # noqa: BLE001
            job.status = "failed"
            job.error = f"{type(exc).__name__}: {exc}"
        finally:
            job.ended_at = time.time()
            with self._lock:
                self._active -= 1
            self._notify()

    @staticmethod
    def _default_out_dir(src: str) -> str:
        import os
        return os.path.dirname(os.path.abspath(src))

    def _notify(self) -> None:
        if self.on_change:
            try:
                self.on_change()
            except Exception:  # noqa: BLE001
                pass
