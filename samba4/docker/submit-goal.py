#!/usr/bin/env python3
"""Submit a high-level goal to the coordination queue."""

import argparse
import asyncio
import json
import os
import sys
from typing import Any, Dict, List

import nats

from enterprise.agent.routing import ensure_stream
from enterprise.agent.task import TaskResult, TaskStatus
from enterprise.coordinator.goal_ingress import (
    DEFAULT_COORDINATION_SUBJECT,
    build_goal,
    build_goal_decomposition_task,
)


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Submit a goal to MissionCoordinator")
    parser.add_argument("--title", required=True, help="Goal title")
    parser.add_argument("--description", default="", help="Goal description")
    parser.add_argument(
        "--priority",
        type=int,
        default=500,
        help="Goal priority (0-1000). Mapped to LOW/NORMAL/HIGH/CRITICAL.",
    )
    parser.add_argument(
        "--constraint",
        action="append",
        default=[],
        help="Constraint text (repeatable)",
    )
    parser.add_argument(
        "--success",
        action="append",
        default=[],
        help="Success criterion text (repeatable)",
    )
    parser.add_argument(
        "--context-json",
        default="",
        help="Inline JSON object for goal context",
    )
    parser.add_argument(
        "--context-file",
        default="",
        help="Path to JSON file for goal context",
    )
    parser.add_argument(
        "--subject",
        default=DEFAULT_COORDINATION_SUBJECT,
        help="NATS subject for coordinator queue",
    )
    parser.add_argument(
        "--nats-url",
        default=os.environ.get("NATS_URL", "nats://coordinator:coord-test@nats.autonomy.local:4222"),
        help="NATS connection URL",
    )
    parser.add_argument(
        "--timeout-seconds",
        type=float,
        default=60.0,
        help="Timeout waiting for coordinator result",
    )
    parser.add_argument(
        "--follow-seconds",
        type=float,
        default=20.0,
        help="Additional seconds to watch worker results for this goal",
    )
    return parser.parse_args()


def _load_context(args: argparse.Namespace) -> Dict[str, Any]:
    context: Dict[str, Any] = {}
    if args.context_file:
        with open(args.context_file, "r", encoding="utf-8") as f:
            loaded = json.load(f)
            if not isinstance(loaded, dict):
                raise ValueError("Context file must contain a JSON object")
            context.update(loaded)
    if args.context_json:
        loaded = json.loads(args.context_json)
        if not isinstance(loaded, dict):
            raise ValueError("--context-json must be a JSON object")
        context.update(loaded)
    return context


async def _run(args: argparse.Namespace) -> int:
    context = _load_context(args)
    goal = build_goal(
        title=args.title,
        description=args.description,
        priority=args.priority,
        context=context,
        constraints=args.constraint,
        success_criteria=args.success,
    )
    task = build_goal_decomposition_task(goal)
    goal_results_subject = f"results.{goal.id}"

    print(f"Connecting to NATS: {args.nats_url}")
    nc = await nats.connect(args.nats_url)
    js = nc.jetstream()

    # Ensure queue stream exists before publishing.
    await ensure_stream(js, args.subject)

    coordinator_result_future = asyncio.get_running_loop().create_future()
    worker_results: List[TaskResult] = []

    async def _on_coordinator_result(msg):
        if not coordinator_result_future.done():
            coordinator_result_future.set_result(TaskResult.from_json(msg.data))

    async def _on_worker_result(msg):
        worker_results.append(TaskResult.from_json(msg.data))

    coordinator_sub = await nc.subscribe(task.reply_to, cb=_on_coordinator_result)
    worker_sub = await nc.subscribe(goal_results_subject, cb=_on_worker_result)

    try:
        ack = await js.publish(args.subject, task.to_json())
        print(f"Submitted goal_id={goal.id} task_id={task.id} subject={args.subject} seq={ack.seq}")
        print(f"Waiting up to {args.timeout_seconds:.1f}s for coordinator result on {task.reply_to}...")

        try:
            coordinator_result = await asyncio.wait_for(
                coordinator_result_future,
                timeout=args.timeout_seconds,
            )
        except asyncio.TimeoutError:
            print("Timed out waiting for coordinator result.")
            return 2

        print(
            f"Coordinator result: status={coordinator_result.status.value} "
            f"agent={coordinator_result.agent_id}"
        )
        if coordinator_result.error:
            print(f"Coordinator error: {coordinator_result.error}")

        if args.follow_seconds > 0:
            print(
                f"Watching worker results on {goal_results_subject} for "
                f"{args.follow_seconds:.1f}s..."
            )
            await asyncio.sleep(args.follow_seconds)
            print(f"Worker results received: {len(worker_results)}")
            for result in worker_results:
                summary = ""
                if isinstance(result.result, dict):
                    summary = result.result.get("description", "")[:120]
                print(
                    f"- agent={result.agent_id} status={result.status.value} "
                    f"task_id={result.task_id} {summary}"
                )

        if coordinator_result.status != TaskStatus.COMPLETED:
            return 3
        return 0
    finally:
        await coordinator_sub.unsubscribe()
        await worker_sub.unsubscribe()
        await nc.close()


def main() -> int:
    try:
        args = _parse_args()
        return asyncio.run(_run(args))
    except KeyboardInterrupt:
        return 130
    except Exception as exc:
        print(f"submit-goal failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
